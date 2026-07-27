#!/usr/bin/env bash
# Local mirror of the kubeconform / pluto / kube-score CI checks
# (clubcedille/cedille-workflows), run by pre-commit on staged files.
#
# Builds each changed kustomization root with `kubectl kustomize --enable-helm`
# and validates the rendered manifests. kubeconform and pluto are blocking;
# kube-score is report-only (the CI-side CRITICAL gate depends on `/kube-score
# skip` PR comments, which don't exist locally).
#
# Requires: kubectl, kubeconform, pluto, kube-score.

set -euo pipefail

changed_root_for() {
  local path="$1"
  IFS=/ read -r top second third fourth _ <<<"$path"
  case "$path" in
    apps/clubs/*/*/*)
      printf '%s/%s/%s/%s\n' "$top" "$second" "$third" "$fourth"
      ;;
    apps/*/* | bases/*/* | system/*/* | common/*/*)
      printf '%s/%s\n' "$top" "$second"
      ;;
  esac
}

roots_to_build=$(
  { printf '%s\n' "$@" | grep -E '^(apps|bases|system|common)/' || true; } |
    while IFS= read -r f; do changed_root_for "$f"; done |
    sed 's:/$::' | sort -u
)

if [ -z "${roots_to_build:-}" ]; then
  echo "kube-validate: rien à valider (aucun fichier sous apps/bases/system/common)."
  exit 0
fi

out_dir="$(mktemp -d)"
trap 'rm -rf "$out_dir"' EXIT

roots=()
for d in apps bases system common; do
  [ -d "$d" ] && roots+=("./$d")
done

built_any=false
if [ "${#roots[@]}" -gt 0 ]; then
  while IFS= read -r -d '' kustom; do
    dir="$(dirname "$kustom")"
    rel="${dir#./}"
    should_build=false
    while IFS= read -r root_key; do
      [ -z "$root_key" ] && continue
      if [[ "$rel" == "$root_key" || "$rel" == "$root_key"/* ]]; then
        should_build=true
        break
      fi
    done <<<"$roots_to_build"

    if [ "$should_build" = true ]; then
      name="${rel//\//_}.yaml"
      echo "▶ building $rel"
      if kubectl kustomize --enable-helm --load-restrictor LoadRestrictionsNone "$dir" >"$out_dir/$name"; then
        built_any=true
      else
        echo "::error::❌ kustomize build failed: $rel"
        rm -f "$out_dir/$name"
      fi
    fi
  done < <(find "${roots[@]}" -type f \( -name kustomization.yaml -o -name kustomization.yml \) -not -path '*/base/*' -print0)
fi

if [ "$built_any" = false ]; then
  echo "kube-validate: aucune kustomization buildable trouvée."
  exit 0
fi

shopt -s nullglob
files=("$out_dir"/*.yaml)

echo "--- kubeconform ---"
kubeconform \
  -summary -output text \
  -kubernetes-version 1.30.0 \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  -ignore-missing-schemas \
  "${files[@]}"

echo "--- pluto (deprecated APIs) ---"
pluto detect-files -d "$out_dir" --target-versions k8s=v1.31.0 -o wide

echo "--- kube-score (rapport, non bloquant localement) ---"
kube-score score --output-format ci "${files[@]}" || true
