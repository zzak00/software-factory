#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_VERSION='0.6.5'
readonly -a SKILL_NAMES=(
  'grill-me'
  'grill-with-docs'
  'grilling'
  'domain-modeling'
  'to-spec'
  'to-tickets'
  'implement'
  'tdd'
  'code-review'
  'plannotator-review'
)
readonly -a LOCKED_SKILL_NAMES=(
  'grill-me'
  'grill-with-docs'
  'grilling'
  'domain-modeling'
  'to-spec'
  'to-tickets'
  'implement'
  'tdd'
  'code-review'
  'plannotator-review'
  'setup-factory'
)

apply=false
harness='all'
target_home=${HOME:-}

usage() {
  cat <<'EOF'
Usage: install-skills.sh [options]

Install the pinned factory skills from this checkout into native user-level
harness directories. No network access is required.

Options:
  --harness VALUE   all, claude, codex, or pi (default: all)
  --target-home PATH
                    User home to install beneath (default: current HOME)
  --apply           Perform approved writes; otherwise inspect only
  -h, --help        Show this help
  --version         Show the script version

The script verifies skills.lock before inspecting or writing. It never replaces
or repairs an existing skill. Remove or reconcile a conflicting installation
manually, then rerun the script.
EOF
}

fail() {
  printf 'install-skills: %s\n' "$*" >&2
  exit 1
}

info() {
  printf 'install-skills: %s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --harness)
      [[ $# -ge 2 ]] || fail '--harness requires a value'
      harness=$2
      shift 2
      ;;
    --target-home)
      [[ $# -ge 2 ]] || fail '--target-home requires a value'
      target_home=$2
      shift 2
      ;;
    --apply)
      apply=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --version)
      printf 'install-skills %s\n' "$SCRIPT_VERSION"
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

case $harness in
  all|claude|codex|pi) ;;
  *) fail '--harness must be all, claude, codex, or pi' ;;
esac

[[ -n "$target_home" ]] || fail 'HOME is empty; pass --target-home'
[[ "$target_home" == /* ]] || fail '--target-home must be an absolute path'
[[ -d "$target_home" ]] || fail "target home not found: $target_home"

require_command awk
require_command cmp
require_command cp
require_command find
require_command grep
require_command mktemp
require_command mv
require_command sort

if command -v sha256sum >/dev/null 2>&1; then
  hash_command='sha256sum'
elif command -v shasum >/dev/null 2>&1; then
  hash_command='shasum'
else
  fail 'required command not found: sha256sum or shasum'
fi

script_directory=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
factory_root=$(CDPATH='' cd -- "$script_directory/.." && pwd)
readonly script_directory factory_root
readonly lock_file="$factory_root/skills.lock"

[[ -f "$lock_file" ]] || fail "skills lock not found: $lock_file"

installer_temp_parent=${TMPDIR:-/tmp}
installer_temp_directory=$(mktemp -d "$installer_temp_parent/install-skills.XXXXXX")
active_stage=''

cleanup() {
  if [[ -n "$active_stage" && -d "$active_stage" ]]; then
    rm -rf -- "$active_stage"
  fi
  rm -rf -- "$installer_temp_directory"
}
trap cleanup EXIT

manifest_file="$installer_temp_directory/manifest"
manifest_paths_file="$installer_temp_directory/manifest-paths"

awk '
  $0 == "files:" { in_files = 1; next }
  in_files && $1 == "-" && $2 == "path:" {
    path = $3
    gsub(/^"|"$/, "", path)
    next
  }
  in_files && $1 == "sha256:" {
    hash = $2
    gsub(/^"|"$/, "", hash)
    print path "|" hash
  }
' "$lock_file" >"$manifest_file"

[[ -s "$manifest_file" ]] || fail 'skills.lock contains no file manifest'
awk -F '|' '{ print $1 }' "$manifest_file" >"$manifest_paths_file"

is_locked_skill_path() {
  local path=$1
  local skill_name

  for skill_name in "${LOCKED_SKILL_NAMES[@]}"; do
    if [[ "$path" == "skills/$skill_name/"* ]]; then
      return 0
    fi
  done
  return 1
}

hash_file() {
  if [[ "$hash_command" == 'sha256sum' ]]; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

manifest_count=0
while IFS='|' read -r relative_path expected_hash; do
  [[ -n "$relative_path" && -n "$expected_hash" ]] ||
    fail 'skills.lock contains an incomplete file entry'
  is_locked_skill_path "$relative_path" ||
    fail "skills.lock contains an unexpected path: $relative_path"
  [[ "$relative_path" != *'/../'* && "$relative_path" != '../'* ]] ||
    fail "skills.lock contains an unsafe path: $relative_path"

  source_file="$factory_root/$relative_path"
  [[ -f "$source_file" && ! -L "$source_file" ]] ||
    fail "locked source file not found: $relative_path"
  actual_hash=$(hash_file "$source_file")
  [[ "$actual_hash" == "$expected_hash" ]] ||
    fail "source hash mismatch: $relative_path"
  manifest_count=$((manifest_count + 1))
done <"$manifest_file"

source_count=0
while IFS= read -r source_file; do
  relative_path=${source_file#"$factory_root/"}
  grep -Fqx "$relative_path" "$manifest_paths_file" ||
    fail "source file is not locked: $relative_path"
  source_count=$((source_count + 1))
done < <(find "${LOCKED_SKILL_NAMES[@]/#/$factory_root/skills/}" -type f -print | sort)

[[ "$source_count" -eq "$manifest_count" ]] ||
  fail 'skills.lock does not exactly cover the selected skill files'

readonly -a destinations_all=(
  "$target_home/.agents/skills"
  "$target_home/.claude/skills"
)

case $harness in
  all)
    destinations=("${destinations_all[@]}")
    ;;
  claude)
    destinations=("$target_home/.claude/skills")
    ;;
  codex|pi)
    destinations=("$target_home/.agents/skills")
    ;;
esac

verify_installed_skill() {
  local destination=$1
  local skill_name=$2
  local installed_root="$destination/$skill_name"
  local expected_files="$installer_temp_directory/expected-$skill_name"
  local actual_files="$installer_temp_directory/actual-$skill_name"
  local relative_path expected_hash installed_relative installed_file actual_hash

  [[ -d "$installed_root" && ! -L "$installed_root" ]] ||
    fail "existing skill is not a regular directory: $installed_root"

  : >"$expected_files"
  while IFS='|' read -r relative_path expected_hash; do
    if [[ "$relative_path" != "skills/$skill_name/"* ]]; then
      continue
    fi
    installed_relative=${relative_path#"skills/$skill_name/"}
    printf '%s\n' "$installed_relative" >>"$expected_files"
    installed_file="$installed_root/$installed_relative"
    [[ -f "$installed_file" && ! -L "$installed_file" ]] ||
      fail "installed skill is incomplete: $installed_file"
    actual_hash=$(hash_file "$installed_file")
    [[ "$actual_hash" == "$expected_hash" ]] ||
      fail "installed skill differs from the pinned bundle: $installed_file"
  done <"$manifest_file"

  : >"$actual_files"
  while IFS= read -r installed_file; do
    installed_relative=${installed_file#"$installed_root/"}
    printf '%s\n' "$installed_relative" >>"$actual_files"
  done < <(find "$installed_root" \( -type f -o -type l \) -print | sort)

  sort -o "$expected_files" "$expected_files"
  sort -o "$actual_files" "$actual_files"
  cmp -s "$expected_files" "$actual_files" ||
    fail "installed skill contains unexpected files: $installed_root"
}

copy_skill_to_stage() {
  local stage_root=$1
  local skill_name=$2
  local relative_path expected_hash installed_relative source_file stage_file

  mkdir -p "$stage_root/$skill_name"
  while IFS='|' read -r relative_path expected_hash; do
    if [[ "$relative_path" != "skills/$skill_name/"* ]]; then
      continue
    fi
    installed_relative=${relative_path#"skills/$skill_name/"}
    source_file="$factory_root/$relative_path"
    stage_file="$stage_root/$skill_name/$installed_relative"
    mkdir -p "$(dirname -- "$stage_file")"
    cp -p "$source_file" "$stage_file"
  done <"$manifest_file"
}

info "version=$SCRIPT_VERSION"
info "mode=$(if $apply; then printf apply; else printf inspect; fi)"
info "harness=$harness"
info "source=$factory_root/skills"

missing_installation=false
for destination in "${destinations[@]}"; do
  info "destination=$destination"
  for skill_name in "${SKILL_NAMES[@]}"; do
    installed_root="$destination/$skill_name"
    if [[ -e "$installed_root" || -L "$installed_root" ]]; then
      verify_installed_skill "$destination" "$skill_name"
      info "skill verified: $skill_name"
    else
      missing_installation=true
      info "PLAN install skill: $skill_name"
    fi
  done
done

if ! $apply; then
  if $missing_installation; then
    exit 2
  fi
  info 'pinned factory skills verified'
  exit 0
fi

for destination in "${destinations[@]}"; do
  mkdir -p "$destination"
  for skill_name in "${SKILL_NAMES[@]}"; do
    installed_root="$destination/$skill_name"
    if [[ -e "$installed_root" || -L "$installed_root" ]]; then
      continue
    fi

    active_stage=$(mktemp -d "$destination/.install-skills.XXXXXX")
    copy_skill_to_stage "$active_stage" "$skill_name"
    verify_installed_skill "$active_stage" "$skill_name"
    [[ ! -e "$installed_root" && ! -L "$installed_root" ]] ||
      fail "skill appeared during installation: $installed_root"
    mv "$active_stage/$skill_name" "$installed_root"
    rmdir "$active_stage"
    active_stage=''
    verify_installed_skill "$destination" "$skill_name"
    info "skill installed: $skill_name"
  done
done

info 'pinned factory skills installed and verified'
info 'invoke only grill-me, grill-with-docs, to-spec, to-tickets, implement, code-review, or plannotator-review directly'
