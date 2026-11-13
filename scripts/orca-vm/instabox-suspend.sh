#!/usr/bin/env bash
# orca.yaml environmentRecipes[instabox].suspend — runs on the desktop.
# Pauses the instabox machine for this workspace, keeping its processes.
# Orca passes the lifecycle payload on stdin; stdout is reserved for recipe
# JSON (suspend prints nothing on stdout).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
payload="$(cat)"

resource_id="$(printf '%s' "$payload" | node -e '
  let d = ""; process.stdin.on("data", c => d += c).on("end", () => {
    try {
      const p = JSON.parse(d);
      process.stdout.write((p.recipeResult && p.recipeResult.userData && p.recipeResult.userData.resourceId) || "");
    } catch (_) {}
  });')"

# Fallback: derive the machine name from the instance id (a timed-out create
# leaves a payload with instanceId but no recipeResult).
if [ -z "$resource_id" ] && [ -n "${ORCA_VM_INSTANCE_ID:-}" ]; then
  candidate="orca-${ORCA_RECIPE_ID:-openmail}-${ORCA_VM_INSTANCE_ID}"
  candidate="$(printf '%s' "$candidate" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9-]/-/g' -e 's/-\{2,\}/-/g' -e 's/^[^a-z0-9]//' -e 's/-$//')"
  candidate="${candidate:0:63}"
  if instabox get "$candidate" --json >/dev/null 2>&1; then
    resource_id="$candidate"
  fi
fi

if [ -z "$resource_id" ]; then
  echo "[instabox-suspend] no resource id in lifecycle payload and no matching machine" >&2
  exit 1
fi

echo "[instabox-suspend] pausing instabox machine $resource_id" >&2
instabox suspend "$resource_id" >/dev/null
