#!/usr/bin/env bash
# orca.yaml environmentRecipes[instabox].resume — runs on the desktop.
# Resumes the instabox machine and re-emits a FRESH recipe result: the SSH
# token is re-issued here (never stored in a file) because the pairing may
# have changed across suspend/resume.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
state_file="$script_dir/instabox-state.json"
payload="$(cat)"

json_value() {
  node -e '
    const fs = require("fs");
    try {
      const s = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      const v = s[process.argv[2]];
      if (v !== undefined && v !== null && v !== "") process.stdout.write(String(v));
    } catch (_) {}
  ' "$state_file" "$1"
}

ssh_host="$(json_value sshHost ssh.instabox.sh)"
ssh_port="$(json_value sshPort 2222)"

resource_id="$(printf '%s' "$payload" | node -e '
  let d = ""; process.stdin.on("data", c => d += c).on("end", () => {
    try {
      const p = JSON.parse(d);
      process.stdout.write((p.recipeResult && p.recipeResult.userData && p.recipeResult.userData.resourceId) || "");
    } catch (_) {}
  });')"

if [ -z "$resource_id" ] && [ -n "${ORCA_VM_INSTANCE_ID:-}" ]; then
  candidate="orca-${ORCA_RECIPE_ID:-openmail}-${ORCA_VM_INSTANCE_ID}"
  candidate="$(printf '%s' "$candidate" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9-]/-/g' -e 's/-\{2,\}/-/g' -e 's/^[^a-z0-9]//' -e 's/-$//')"
  candidate="${candidate:0:63}"
  if instabox get "$candidate" --json >/dev/null 2>&1; then
    resource_id="$candidate"
  fi
fi

if [ -z "$resource_id" ]; then
  echo "[instabox-resume] no resource id in lifecycle payload and no matching machine" >&2
  exit 1
fi

echo "[instabox-resume] resuming instabox machine $resource_id" >&2
if ! instabox resume "$resource_id" >/dev/null 2>&1; then
  # A resume can 409 machine_cooldown right after a max-run pause; surface it.
  echo "[instabox-resume] resume failed; retrying once after 30s" >&2
  sleep 30
  instabox resume "$resource_id" >/dev/null
fi

# Re-issue the never-expiring SSH token and emit the fresh connection block.
ssh_json="$(instabox ssh-token "$resource_id" --ttl never --json)"
read -r token_host token_port token_user <<EOF
$(printf '%s' "$ssh_json" | node -e '
  let d = ""; process.stdin.on("data", c => d += c).on("end", () => {
    const t = JSON.parse(d);
    process.stdout.write([t.host, t.port, t.token].join(" "));
  });')
EOF
[ -n "$token_user" ] || { echo "[instabox-resume] could not parse ssh-token output" >&2; exit 1; }

project_root="$(json_value projectRoot /data/home/openmail)"
node -e '
  const [host, port, user, label, root, provider, rid] = process.argv.slice(1);
  process.stdout.write(JSON.stringify({
    schemaVersion: 1,
    connection: { type: "ssh", projectRoot: root, target: { label, host, port: Number(port), username: user } },
    userData: { provider, resourceId: rid },
  }));
' "$ssh_host" "$ssh_port" "$token_user" "$resource_id" "$project_root" "instabox" "$resource_id"
