#!/usr/bin/env bash
# Reconciles the per-club exec roles' permissions in Authentik.
#
# Every exec-{club} role is expected to grant, on both the exec-{club} and the
# club-{club} group objects, these object-scoped permissions:
#   authentik_core.view_group
#   authentik_core.add_user_to_group
#   authentik_core.remove_user_from_group
#
# Every exec-{club} role is also expected to carry these global permissions,
# matching the reference exec roles (conjure, canoe, ...):
#   authentik_rbac.access_admin_interface   Can access admin interface
#   authentik_core.view_group               Can view Group
#   authentik_core.view_user                Can view User
#
# Permissions are not expressible through the terraform provider (they only
# live in the Authentik UI/API), so this script is the source of truth for the
# grant wiring.
#
# Default run only prints a report and never modifies anything. Pass --apply
# to add the missing grants (idempotent, additive only). Extra/unknown grants
# are never removed - if you want them trimmed, do it in the UI.
#
# Requires AUTHENTIK_API_TOKEN (same as terraform.tfvars).
# Optional: AUTHENTIK_URL (default https://auth.etsmtl.club).

set -euo pipefail

URL="${AUTHENTIK_URL:-https://auth.etsmtl.club}"
URL="${URL%/}"
API="$URL/api/v3"
AUTH="Authorization: Bearer ${AUTHENTIK_API_TOKEN:?Set AUTHENTIK_API_TOKEN}"

DO_APPLY=0
for arg in "$@"; do
  case "$arg" in
    --apply) DO_APPLY=1 ;;
    -h|--help)
      echo "usage: $0 [--apply]"
      echo "  (no flags)  print report of missing grants (dry run)"
      echo "  --apply     add the missing grants"
      exit 0 ;;
  esac
done

OBJECT_PERMS=("authentik_core.view_group" "authentik_core.add_user_to_group" "authentik_core.remove_user_from_group")
GLOBAL_PERMS=("authentik_rbac.access_admin_interface" "authentik_core.view_group" "authentik_core.view_user")

get() { curl -fsS -H "$AUTH" -H "Accept: application/json" "$@"; }

# List every exec-* role as "pk<TAB>name", paging through the API.
exec_roles() {
  local page=1 resp next
  while :; do
    resp=$(get "$API/rbac/roles/?search=exec-&page_size=100&page=$page")
    jq -r '.results[] | "\(.pk)\t\(.name)"' <<<"$resp"
    next=$(jq -r '.pagination.next' <<<"$resp")
    [[ -n "$next" && "$next" != "null" && "$next" != "0" ]] || break
    page=$((page + 1))
  done
}

# Compute perms missing on $1 and store them in MISSING.
# $2 = object pk (checks OBJECT_PERMS for that object), or empty for globals.
missing() {
  MISSING=()
  local perm
  if [[ -n "$2" ]]; then
    for perm in "${OBJECT_PERMS[@]}"; do
      grep -qxF "$perm:$2" <<<"${GRANTS[$1]:-}" || MISSING+=("$perm")
    done
  else
    for perm in "${GLOBAL_PERMS[@]}"; do
      grep -qxF "$perm" <<<"${GLOBALS[$1]:-}" || MISSING+=("$perm")
    done
  fi
}

join_csv() { printf '%s, ' "${MISSING[@]}" | sed 's/, $//'; }

# Grant MISSING perms on $1 (role pk) for $2 (object pk), or globally if empty.
assign() {
  local payload
  if [[ -n "$2" ]]; then
    payload=$(jq -nc --arg model authentik_core.group --arg object_pk "$2" --args \
      '{permissions: $ARGS.positional, model: $model, object_pk: $object_pk}' "${MISSING[@]}")
  else
    payload=$(jq -nc --args '{permissions: $ARGS.positional}' "${MISSING[@]}")
  fi
  curl -fsS -X POST -H "$AUTH" -H "Content-Type: application/json" \
    -d "$payload" "$API/rbac/permissions/assigned_by_roles/$1/assign/" >/dev/null
}

# --- discover exec roles and their groups -----------------------------------
declare -A ROLE_NAME=() ROLE_PK=()
while IFS=$'\t' read -r pk name; do
  [[ "$name" != exec-test && "$name" != exec-base ]] || continue
  ROLE_NAME[$pk]=$name
  ROLE_PK[$name]=$pk
done < <(exec_roles)

if [[ ${#ROLE_PK[@]} -eq 0 ]]; then
  echo "No exec-* roles found in Authentik." >&2
  exit 1
fi

declare -A GROUP_PK=()
for name in "${!ROLE_PK[@]}"; do
  club=${name#exec-}
  for label in exec club; do
    gname="$label-$club"
    GROUP_PK[$gname]=$(get "$API/core/groups/?name=$gname" | jq -r '.results[0].pk // empty')
  done
done

# --- snapshot current grants per role ----------------------------------------
declare -A GRANTS=() GLOBALS=()
for pk in "${!ROLE_NAME[@]}"; do
  GRANTS[$pk]=$(get "$API/rbac/permissions/roles/?uuid=$pk&page_size=100" \
    | jq -r '.results[] | select(.object_pk != null) | "\(.app_label).\(.codename):\(.object_pk)"')
  GLOBALS[$pk]=$(get "$API/rbac/permissions/?role=$pk&page_size=100" \
    | jq -r '.results[] | select(.object_pk == null) | "\(.app_label).\(.codename)"')
done

# --- report ------------------------------------------------------------------
ok=1
for name in $(printf '%s\n' "${!ROLE_PK[@]}" | sort); do
  pk=${ROLE_PK[$name]}
  club=${name#exec-}
  for label in exec club; do
    gname="$label-$club"
    opk=${GROUP_PK[$gname]:-}
    missing "$pk" "$opk"
    if [[ -z "$opk" ]]; then
      printf '  WARN  %-14s -> %-18s group not found\n' "$name" "$gname"
      ok=0
    elif [[ ${#MISSING[@]} -eq 0 ]]; then
      echo "  OK    $name -> $gname"
    else
      ok=0
      printf '  MISS  %-14s -> %-18s grants needed: %s\n' "$name" "$gname" "$(join_csv)"
    fi
  done
  missing "$pk" ""
  if [[ ${#MISSING[@]} -eq 0 ]]; then
    echo "  OK    $name -> (global)"
  else
    ok=0
    printf '  MISS  %-14s -> %-18s globals needed: %s\n' "$name" "(global)" "$(join_csv)"
  fi
done
echo
if [[ $ok -eq 1 ]]; then
  echo "All exec-* roles have the expected grants."
  exit 0
fi
echo "Some grants are missing. Rerun with: --apply"
[[ $DO_APPLY -eq 1 ]] || exit 0

# --- apply -------------------------------------------------------------------
echo "== applying =="
for name in $(printf '%s\n' "${!ROLE_PK[@]}" | sort); do
  pk=${ROLE_PK[$name]}
  club=${name#exec-}
  for label in exec club; do
    gname="$label-$club"
    opk=${GROUP_PK[$gname]:-}
    [[ -n "$opk" ]] || continue
    missing "$pk" "$opk"
    [[ ${#MISSING[@]} -gt 0 ]] || continue
    assign "$pk" "$opk"
    echo "  granted $(join_csv) on $gname to $name"
  done
  missing "$pk" ""
  [[ ${#MISSING[@]} -gt 0 ]] || continue
  assign "$pk" ""
  echo "  granted $(join_csv) (global) to $name"
done