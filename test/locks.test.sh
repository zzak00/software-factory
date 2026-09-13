#!/usr/bin/env bash

set -euo pipefail

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

if command -v sha256sum >/dev/null 2>&1; then
  hash_file() { sha256sum "$1" | awk '{ print $1 }'; }
elif command -v shasum >/dev/null 2>&1; then
  hash_file() { shasum -a 256 "$1" | awk '{ print $1 }'; }
else
  fail 'sha256sum or shasum is required'
fi

manifest=$(mktemp "${TMPDIR:-/tmp}/factory-skill-lock.XXXXXX")
trap 'rm -f "$manifest"' EXIT
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
' "$project_root/skills.lock" >"$manifest"

locked_count=0
while IFS='|' read -r relative_path expected_hash; do
  [[ "$relative_path" == skills/* && "$relative_path" != *'/../'* ]] ||
    fail "unsafe skill lock path: $relative_path"
  [[ -f "$project_root/$relative_path" && ! -L "$project_root/$relative_path" ]] ||
    fail "locked skill file is missing or unsafe: $relative_path"
  [[ "$(hash_file "$project_root/$relative_path")" == "$expected_hash" ]] ||
    fail "locked skill hash differs: $relative_path"
  locked_count=$((locked_count + 1))
done <"$manifest"

source_count=$(find "$project_root/skills" -type f | wc -l | tr -d ' ')
[[ "$locked_count" -eq "$source_count" ]] ||
  fail "skills.lock covers $locked_count files, but $source_count are distributed"

lock_file="$project_root/pi-permissions.lock"
package_definition="$project_root/$(jq -er '.runtime.packageDefinition' "$lock_file")"
package_lock="$project_root/$(jq -er '.runtime.packageLock' "$lock_file")"
policy="$project_root/$(jq -er '.policy.source' "$lock_file")"
[[ "$(hash_file "$package_definition")" == \
  "$(jq -er '.runtime.packageDefinitionSha256' "$lock_file")" ]] ||
  fail 'Pi package definition hash differs'
[[ "$(hash_file "$package_lock")" == \
  "$(jq -er '.runtime.packageLockSha256' "$lock_file")" ]] ||
  fail 'Pi package lock hash differs'
[[ "$(hash_file "$policy")" == "$(jq -er '.policy.sha256' "$lock_file")" ]] ||
  fail 'Pi policy hash differs'
jq -e '
  .lockfileVersion == 3 and
  ([.packages | to_entries[] | select(.key != "") |
    (.value.version | type == "string" and length > 0) and
    (.value.resolved | startswith("https://registry.npmjs.org/")) and
    (.value.integrity | startswith("sha512-"))] | all)
' "$package_lock" >/dev/null || fail 'Pi package lock is incomplete'

printf '%s\n' 'PASS: skill and Pi permission lock verification'
