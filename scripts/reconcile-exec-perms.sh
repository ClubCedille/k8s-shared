#!/usr/bin/env bash
# Keeps the per-club exec roles' object + global permissions in sync.
#
# Every exec-{club} role is expected to grant, on both the exec-{club} and the
# club-{club} group objects:
#   authentik_core.view_group
#   authentik_core.add_user_to_group
#   authentik_core.remove_user_from_group
#
# Each role is also expected to carry the global (non-object) permissions,
# matching the reference exec roles (conjure, canoe, ...):
#   authentik_rbac.access_admin_interface   Can access admin interface
#   authentik_core.view_group               Can view Group
#   authentik_core.view_user                Can view User
#
# Permissions are not expressible through the terraform provider (they only
# live in the Authentik UI/API), so this script is the source of truth for the
# grant wiring. It repairs drift like: exec-algoets missing its club grant,
# exec-eclipse/exec-jdgets roles with no grants at all, exec-applets role just
# created by tofu apply, exec roles lacking the global permissions.
#
# Default run only prints a report and never modifies anything. Pass --apply
# --yes to add the missing grants (idempotent, additive only). Extra/unknown
# grants are never removed — if you want them trimmed, do it in the UI.
#
# Requires AUTHENTIK_API_TOKEN (same as terraform.tfvars).
# Optional: AUTHENTIK_URL (default https://auth.etsmtl.club).

set -euo pipefail

URL="${AUTHENTIK_URL:-https://auth.etsmtl.club}"   # strip trailing slash
AUTH="Authorization: Bearer ${AUTHENTIK_API_TOKEN:?Set AUTHENTIK_API_TOKEN}"
API="$URL/api/v3"

DO_APPLY=0
CONFIRMED=0
for arg in "$@"; do
  case "$arg" in
    --apply) DO_APPLY=1 ;;
    --yes) CONFIRMED=1 ;;
    -h|--help)
      echo "usage: $0 [--apply] [--yes]"
      echo "  (no flags)  print report of missing grants (dry run)"
      echo "  --apply     add the missing grants (requires --yes)"
      exit 0 ;;
  esac
done
if [[ $DO_APPLY -eq 1 && $CONFIRMED -ne 1 ]]; then
  echo "ERROR: --apply requires --yes" >&2
  exit 2
fi

STD_PERMS=("authentik_core.view_group" "authentik_core.add_user_to_group" "authentik_core.remove_user_from_group")
GLOBAL_PERMS=("authentik_rbac.access_admin_interface" "authentik_core.view_group" "authentik_core.view_user")

get() { curl -fsS -H "$AUTH" -H "Accept: application/json" "$@"; }

# --- exec roles (paged) ----------------------------------------------------
roles_raw=()
page=1
while :; do
  resp=$(get "$API/rbac/roles/?search=exec-&page_size=100&page=$page")
  mapfile -O "${#roles_raw[@]}" -t roles_raw < <(jq -r '.results[] | "\(.pk)\t\(.name)"' <<<"$resp")
  next=$(jq -r '.pagination.next' <<<"$resp")
  [[ -n "$next" && "$next" != "null" && "$next" != "0" ]] || break
  page=$((page + 1))
done

declare -A ROLE_NAME=() ROLE_PK=()
while IFS=$'\t' read -r pk name; do
  [[ "$name" == exec-* ]] || continue
  [[ "$name" != exec-test && "$name" != exec-base ]] || continue
  ROLE_NAME[$pk]=$name
  ROLE_PK[$name]=$pk
done < <(printf '%s\n' "${roles_raw[@]}")

if [[ ${#ROLE_PK[@]} -eq 0 ]]; then
  echo "No exec-* roles found in Authentik." >&2
  exit 1
fi

# --- expected group object per club ----------------------------------------
declare -A GROUP_PK=()
for name in "${!ROLE_PK[@]}"; do
  club=${name#exec-}
  for label in exec club; do
    gname="$label-$club"
    pk=$(get "$API/core/groups/?name=$gname" | jq -r '.results[0].pk // empty')
    if [[ -z "$pk" ]]; then
      echo "WARNING: group '$gname' not found — will tofu apply first?" >&2
    fi
    GROUP_PK[$gname]=$pk
  done
done

# --- current grants, per role ----------------------------------------------
declare -A GRANTS=()   # role_pk -> "perm:object|..." (string)
declare -A GLOBALS=()  # role_pk -> "app_label.codename|..." (string)
for pk in "${!ROLE_NAME[@]}"; do
  GRANTS[$pk]=$(get "$API/rbac/permissions/roles/?uuid=$pk&page_size=100" \
    | jq -r '.results[] | select(.object_pk != null) | "\(.app_label).\(.codename):\(.object_pk)"')
  GLOBALS[$pk]=$(get "$API/rbac/permissions/?role=$pk&page_size=100" \
    | jq -r '.results[] | select(.object_pk == null) | "\(.app_label).\(.codename)"')
done

# --- report -----------------------------------------------------------------
ok=1
for name in $(printf '%s\n' "${!ROLE_PK[@]}" | sort); do
  pk=${ROLE_PK[$name]}
  club=${name#exec-}
  for label in exec club; do
    gname="$label-$club"
    opk=${GROUP_PK[$gname]:-}
    missing=()
    for perm in "${STD_PERMS[@]}"; do
      grep -qxF "$perm:$opk" <<<"${GRANTS[$pk]:-}" || missing+=("$perm")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
      echo "  OK    $name -> $gname"
    else
      ok=0
      printf '  MISS  %-14s -> %-18s grants needed: %s\n' "$name" "$gname" "$(printf '%s, ' "${missing[@]}" | sed 's/, $//')"
    fi
  done
  gmissing=()
  for perm in "${GLOBAL_PERMS[@]}"; do
    grep -qxF "$perm" <<<"${GLOBALS[$pk]:-}" || gmissing+=("$perm")
  done
  if [[ ${#gmissing[@]} -eq 0 ]]; then
    echo "  OK    $name -> (global)"
  else
    ok=0
    printf '  MISS  %-14s -> %-18s globals needed: %s\n' "$name" "(global)" "$(printf '%s, ' "${gmissing[@]}" | sed 's/, $//')"
  fi
done
echo
if [[ $ok -eq 1 ]]; then
  echo "All exec-* roles have the expected grants."
  exit 0
fi

echo "Some grants are missing. Rerun with: --apply --yes"
if [[ $DO_APPLY -eq 1 ]]; then
  echo "== applying =="
  for name in $(printf '%s\n' "${!ROLE_PK[@]}" | sort); do
    pk=${ROLE_PK[$name]}
    club=${name#exec-}
    for label in exec club; do
      gname="$label-$club"
      opk=${GROUP_PK[$gname]:-}
      [[ -n "$opk" ]] || continue
      missing=()
      for perm in "${STD_PERMS[@]}"; do
        grep -qxF "$perm:$opk" <<<"${GRANTS[$pk]:-}" || missing+=("$perm")
      done
      [[ ${#missing[@]} -gt 0 ]] || continue
      payload=$(jq -nc --arg model authentik_core.group --arg object_pk "$opk" --args \
        '{permissions: $ARGS.positional, model: $model, object_pk: $object_pk}' "${missing[@]}")
      curl -fsS -X POST -H "$AUTH" -H "Content-Type: application/json" \
        -d "$payload" "$API/rbac/permissions/assigned_by_roles/$pk/assign/" >/dev/null
      echo "  granted $(printf '%s, ' "${missing[@]}" | sed 's/, $//') on $gname to $name"
    done
    gmissing=()
    for perm in "${GLOBAL_PERMS[@]}"; do
      grep -qxF "$perm" <<<"${GLOBALS[$pk]:-}" || gmissing+=("$perm")
    done
    [[ ${#gmissing[@]} -gt 0 ]] || continue
    payload=$(jq -nc --args '{permissions: $ARGS.positional}' "${gmissing[@]}")
    curl -fsS -X POST -H "$AUTH" -H "Content-Type: application/json" \
      -d "$payload" "$API/rbac/permissions/assigned_by_roles/$pk/assign/" >/dev/null
    echo "  granted $(printf '%s, ' "${gmissing[@]}" | sed 's/, $//') (global) to $name"
  done
fi
