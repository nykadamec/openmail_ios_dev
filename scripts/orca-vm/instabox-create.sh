#!/usr/bin/env bash
# orca.yaml environmentRecipes[instabox].create — runs on the desktop.
#
# Creates an ephemeral instabox box from the `orca` template, clones the repo
# into it at the requested ref (git auth via the GH_TOKEN org Secret proxy),
# issues a never-expiring SSH token, and prints the SSH connection block Orca
# dials in on. SSH mode: no `orca serve` here; Orca installs its own runtime
# over SSH after connecting.
#
# stdout carries ONLY the final recipe-result JSON; progress goes to stderr.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
state_file="$script_dir/instabox-state.json"

log() { echo "[instabox-create] $*" >&2; }
die() { echo "[instabox-create] ERROR: $*" >&2; exit 1; }

# --- value resolution: env var -> state file -> fallback ---------------------
json_value() { # json_value <key> <fallback>
  node -e '
    const fs = require("fs");
    try {
      const s = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      const v = s[process.argv[2]];
      if (v !== undefined && v !== null && v !== "") process.stdout.write(String(v));
    } catch (_) {}
  ' "$state_file" "$1"
}
env_value() { # env_value <NAME> <fallback>
  if [ -n "${2:-}" ]; then printf '%s' "$2"; else printf '%s' "$1"; fi
}

template="$(env_value "${INSTABOX_TEMPLATE:-}" "$(json_value template orca)")"
project_root="$(env_value "${INSTABOX_PROJECT_ROOT:-}" "$(json_value projectRoot /data/home/openmail)")"
ssh_host="$(env_value "${INSTABOX_SSH_HOST:-}" "$(json_value sshHost ssh.instabox.sh)")"
ssh_port="$(env_value "${INSTABOX_SSH_PORT:-}" "$(json_value sshPort 2222)")"
repo_url="$(env_value "${ORCA_REPO_URL:-}" "$(json_value repoUrl '')")"
repo_ref="$(env_value "${ORCA_REPO_REF:-}" "$(json_value repoRef '')")"

if [ -z "$repo_url" ] && command -v git >/dev/null 2>&1; then
  repo_url="$(cd "$repo_root" && git remote get-url origin 2>/dev/null || true)"
fi
if [ -z "$repo_ref" ] && command -v git >/dev/null 2>&1; then
  repo_ref="$(cd "$repo_root" && git branch --show-current 2>/dev/null || true)"
fi
[ -n "$repo_url" ] || die "no repo URL (set ORCA_REPO_URL or repoUrl in $state_file, or add an origin remote)"
[ -n "$repo_ref" ] || repo_ref="main"

# Normalise git@host:path SSH remotes to HTTPS (the box has no SSH key for the
# Git host; it authenticates over HTTPS through the GH_TOKEN secret proxy).
case "$repo_url" in
  git@github.com:*) repo_url="https://github.com/${repo_url#git@github.com:}" ;;
esac
repo_url="${repo_url%.git}"
repo_url="${repo_url}.git"

# --- machine name: orca-<recipe-id>-<instance-id>, sanitized ----------------
name="orca-${ORCA_RECIPE_ID:-openmail}-${ORCA_VM_INSTANCE_ID:-adhoc}"
name="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9-]/-/g' -e 's/-\{2,\}/-/g' -e 's/^[^a-z0-9]//')"
name="${name:0:63}"
name="${name%-}"
[ -n "$name" ] || die "could not build a valid machine name"
log "machine name: $name"

# --- prerequisites -----------------------------------------------------------
command -v instabox >/dev/null 2>&1 || die "instabox CLI not on PATH (npx instabox@latest installs it)"
instabox whoami >/dev/null 2>&1 || die "instabox is not signed in (run: instabox login)"

if ! instabox secrets ls --json 2>/dev/null | node -e '
  let d = ""; process.stdin.on("data", c => d += c).on("end", () => {
    let ok = false;
    try { ok = JSON.parse(d).items.some(s => s.name === "GH_TOKEN"); } catch (_) {}
    process.exit(ok ? 0 : 1);
  });'; then
  die "no GH_TOKEN org Secret. Create it once with:
    gh auth token | instabox secrets set GH_TOKEN --host github.com --host api.github.com
  (the token is piped straight in; it is never printed or stored in a file)"
fi

# `instabox get --json` prints its error object on stdout even when the machine
# does not exist, so branch on the exit code, not on output.
if instabox get "$name" --json >/dev/null 2>&1; then
  log "machine $name already exists; reusing it (idempotent re-run)"
  created=0
else
  created=1
fi

cleanup() {
  if [ "${created:-0}" = 1 ] && [ "${result_emitted:-0}" != 1 ]; then
    log "create failed; removing half-provisioned machine $name"
    instabox rm --yes "$name" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [ "$created" = 1 ]; then
  log "creating machine from template '$template' (this waits until it runs)"
  if ! create_out="$(instabox create --name "$name" --template "$template" --secrets GH_TOKEN --meta "orca-vm=true" --json 2>&1)"; then
    create_err="$(printf '%s\n' "$create_out" | tail -20)"
    case "$create_err" in
      *quota_exceeded*|*template_not_allowed*)
        die "instabox refused the create: $create_err
On the free plan only 1 machine may exist at a time and only some templates are creatable.
Check \`instabox ls\` and \`instabox templates --json\`, free the slot or upgrade, then re-run."
        ;;
      *) die "instabox create failed: $create_err" ;;
    esac
  fi
fi

# --- clone / sync the repo inside the box (over exec, not raw SSH) ----------
# printf %q quotes every value, so spaces or quotes in paths/refs cannot break out.
remote_sync='set -euo pipefail
  export GIT_TERMINAL_PROMPT=0
  gh auth setup-git >/dev/null 2>&1 || true
  if [ ! -d "$p/.git" ]; then
    git clone -q "$u" "$p"
  fi
  cd "$p"
  git fetch -q origin "$r"
  git checkout -q -B "$r" FETCH_HEAD
  git config --global --get safe.directory >/dev/null 2>&1 || true
  echo "repo ready at $(pwd) on $(git rev-parse --short HEAD)"'
sync_script="$(printf 'p=%q u=%q r=%q bash -lc %q' "$project_root" "$repo_url" "$repo_ref" "$remote_sync")"

log "syncing $repo_url (ref $repo_ref) into $project_root"
sync_out="$(instabox exec "$name" --timeout 590 -- "$sync_script" 2>&1)" \
  || die "repo sync inside the box failed:
$sync_out
(hint: check the GH_TOKEN Secret exists and includes host github.com; check \`instabox logs $name\`)"
log "$sync_out" | tail -1

# --- SSH token for Orca's relay ---------------------------------------------
ssh_json="$(instabox ssh-token "$name" --ttl never --json)" \
  || die "could not issue an SSH token for $name"
read -r token_host token_port token_user <<EOF
$(printf '%s' "$ssh_json" | node -e '
  let d = ""; process.stdin.on("data", c => d += c).on("end", () => {
    const t = JSON.parse(d);
    process.stdout.write([t.host, t.port, t.token].join(" "));
  });')
EOF
[ -n "$token_host" ] && [ -n "$token_port" ] && [ -n "$token_user" ] \
  || die "could not parse ssh-token output: $ssh_json"

# --- emit the recipe result ---------------------------------------------------
result_emitted=1
trap - EXIT
node -e '
  const [host, port, user, label, root, provider, rid] = process.argv.slice(1);
  const result = {
    schemaVersion: 1,
    connection: {
      type: "ssh",
      projectRoot: root,
      target: { label, host, port: Number(port), username: user },
    },
    userData: { provider, resourceId: rid },
  };
  process.stdout.write(JSON.stringify(result));
' "$ssh_host" "$ssh_port" "$token_user" "$name" "$project_root" "instabox" "$name"
