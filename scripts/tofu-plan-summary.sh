#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <module> <module-dir> <output-summary.json>" >&2
  exit 2
}

[[ $# -eq 3 ]] || usage

module="$1"
dir="$2"
output="$3"

log="$dir/plan.log"
plan_json="$dir/plan.json"
mkdir -p "$(dirname "$output")"

warnings_json='[]'
if [[ -f "$log" ]]; then
  warnings_json=$(
    grep -E '(^|│ )Warning:' "$log" \
      | sed 's/^[│ ]*//' \
      | head -20 \
      | jq -R -s 'split("\n") | map(select(length > 0))'
  ) || warnings_json='[]'
fi

if [[ -s "$plan_json" ]]; then
  jq \
    --arg module "$module" \
    --arg dir "$dir" \
    --arg artifact_name "tfplan-$module" \
    --argjson warnings "$warnings_json" '
      def action_symbol:
        if (index("create") != null and index("delete") != null) then "±"
        else map(
          if . == "create" then "+"
          elif . == "update" then "~"
          elif . == "delete" then "-"
          elif . == "import" then "i"
          else . end
        ) | join("") end;

      {
        module: $module,
        dir: $dir,
        artifact_name: $artifact_name,
        status: "success",
        add: ([.resource_changes[]? | select(.change.actions | index("create"))] | length),
        change: ([.resource_changes[]? | select(.change.actions | index("update"))] | length),
        destroy: ([.resource_changes[]? | select(.change.actions | index("delete"))] | length),
        import: ([.resource_changes[]? | select(.change.importing != null)] | length),
        changes: [
          .resource_changes[]?
          | select((.change.actions | index("no-op")) | not)
          | select((.change.actions | index("read")) | not)
          | {symbol: (.change.actions | action_symbol), address: .address}
          | "\(.symbol) \(.address)"
        ],
        warnings: $warnings
      }
    ' "$plan_json" > "$output"
else
  error="No plan log found"
  if [[ -f "$log" ]]; then
    error=$(tail -n 100 "$log")
  fi

  jq -n \
    --arg module "$module" \
    --arg dir "$dir" \
    --arg artifact_name "tfplan-$module" \
    --arg error "$error" \
    --argjson warnings "$warnings_json" \
    '{
      module: $module,
      dir: $dir,
      artifact_name: $artifact_name,
      status: "failure",
      add: 0,
      change: 0,
      destroy: 0,
      import: 0,
      changes: [],
      warnings: $warnings,
      error: $error
    }' > "$output"
fi
