#!/usr/bin/env bash
# orca.yaml environmentRecipes[instabox].destroy — runs on the desktop.
# Deletes the instabox machine (its SSH tokens stop working automatically).
set -euo pipefail

payload="$(cat)"

resource_id="$(printf '%s' "$payload" | node -e '
  let d = ""; process.stdin.on("data", c => d += c).on("end", () => {
    try {
      const p = JSON.parse(d);
      process.stdout.write((p.recipeResult && p.recipeResult.userData && p.recipeResult.userData.resourceId) || "");
    } catch (_) {}
  });')"

# Fallback: a destroy payload for a create that never returned a result has
# instanceId but no recipeResult; find the machine by its derived name.
if [ -z "$resource_id" ] && [ -n "${ORCA_VM_INSTANCE_ID:-}" ]; then
  candidate="orca-${ORCA_RECIPE_ID:-openmail}-${ORCA_VM_INSTANCE_ID}"
  candidate="$(printf '%s' "$candidate" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9-]/-/g' -e 's/-\{2,\}/-/g' -e 's/^[^a-z0-9]//' -e 's/-$//')"
  candidate="${candidate:0:63}"
  if instabox get "$candidate" --json >/dev/null 2>&1; then
    resource_id="$candidate"
  fi
fi

if [ -z "$resource_id" ]; then
  echo "[instabox-destroy] no resource id and no matching machine; nothing to delete" >&2
  exit 0
fi

echo "[instabox-destroy] deleting instabox machine $resource_id" >&2
instabox rm --yes "$resource_id" >/dev/null
