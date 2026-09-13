#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_VERSION='0.1.0'

worktree=''

usage() {
  cat <<'EOF'
Usage: verify-pi-worktree.sh --worktree PATH

Report project-local Pi configuration that becomes effective when the target
worktree is trusted. The command is read-only.

Options:
  --worktree PATH   Ticket worktree to inspect
  -h, --help        Show this help
  --version         Show the script version

Exit 0 means no project override was found, 2 means listed files require human
review before trust, and 1 means the target or configuration is unsafe.
EOF
}

fail() {
  printf 'verify-pi-worktree: %s\n' "$*" >&2
  exit 1
}

info() {
  printf 'verify-pi-worktree: %s\n' "$*"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --worktree)
      [[ $# -ge 2 ]] || fail '--worktree requires a value'
      worktree=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --version)
      printf 'verify-pi-worktree %s\n' "$SCRIPT_VERSION"
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

[[ -n "$worktree" ]] || fail '--worktree is required'
[[ -d "$worktree" ]] || fail "worktree directory not found: $worktree"
command -v git >/dev/null 2>&1 || fail 'required command not found: git'
command -v jq >/dev/null 2>&1 || fail 'required command not found: jq'

worktree=$(CDPATH='' cd -- "$worktree" && pwd -P)
git_root=$(git -C "$worktree" rev-parse --show-toplevel 2>/dev/null) ||
  fail 'worktree is not a Git repository'
git_root=$(CDPATH='' cd -- "$git_root" && pwd -P)
[[ "$git_root" == "$worktree" ]] ||
  fail "worktree must be the Git repository root: worktree=$worktree root=$git_root"

info "version=$SCRIPT_VERSION"
info "worktree=$worktree"
info 'scope=project files effective after Pi trusts this worktree'

overrides_found=false
project_settings="$worktree/.pi/settings.json"
project_policy="$worktree/.pi/extensions/pi-permission-system/config.json"
project_agents="$worktree/.pi/agents"

if [[ -e "$project_settings" || -L "$project_settings" ]]; then
  [[ -f "$project_settings" ]] || fail "project Pi settings are not a readable file: $project_settings"
  jq -e 'type == "object"' "$project_settings" >/dev/null ||
    fail "project Pi settings are invalid JSON: $project_settings"
  info 'PROJECT SETTINGS .pi/settings.json'
  overrides_found=true
fi

if [[ -e "$project_policy" || -L "$project_policy" ]]; then
  [[ -f "$project_policy" ]] || fail "project permission policy is not a readable file: $project_policy"
  jq -e 'type == "object"' "$project_policy" >/dev/null ||
    fail "project permission policy is invalid JSON: $project_policy"
  info 'PROJECT POLICY .pi/extensions/pi-permission-system/config.json'
  overrides_found=true
fi

frontmatter_has_permission() {
  awk '
    NR == 1 {
      sub(/\r$/, "")
      if ($0 != "---") exit 1
      next
    }
    {
      sub(/\r$/, "")
      if ($0 == "---") exit 1
      if ($0 ~ /^permission[[:space:]]*:/) found = 1
    }
    END { exit(found ? 0 : 1) }
  ' "$1"
}

if [[ -e "$project_agents" || -L "$project_agents" ]]; then
  [[ -d "$project_agents" ]] || fail "project agents path is not a directory: $project_agents"
  shopt -s nullglob
  agent_files=("$project_agents"/*.md)
  shopt -u nullglob
  for agent_file in "${agent_files[@]}"; do
    [[ -f "$agent_file" ]] || fail "project agent is not a readable file: $agent_file"
    if frontmatter_has_permission "$agent_file"; then
      info "AGENT PERMISSION .pi/agents/${agent_file##*/}"
      overrides_found=true
    fi
  done
fi

if $overrides_found; then
  info 'review every listed project override before granting or reusing Pi trust'
  exit 2
fi

info 'no trusted project permission overrides found; factory global policy is the only permission layer'
