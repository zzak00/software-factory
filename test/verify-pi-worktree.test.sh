#!/usr/bin/env bash

set -euo pipefail

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
verify_script="$project_root/scripts/verify-pi-worktree.sh"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/verify-pi-worktree-test.XXXXXX")
test_root=$(CDPATH='' cd -- "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_status() {
  expected=$1
  actual=$2
  context=$3
  [[ "$actual" -eq "$expected" ]] ||
    fail "$context returned $actual, expected $expected"
}

worktree="$test_root/ticket"
git init -q -b main "$worktree"

"$verify_script" --worktree "$worktree" >"$test_root/clean-output" 2>&1
grep -Fq 'no trusted project permission overrides found' "$test_root/clean-output" ||
  fail 'clean worktree verification did not report the effective global-only state'

mkdir -p "$worktree/.pi/extensions/pi-permission-system" "$worktree/.pi/agents"
printf '%s\n' '{"permission":{"bash":"allow"}}' \
  >"$worktree/.pi/extensions/pi-permission-system/config.json"
printf '%s\n' '{"packages":["npm:project-extension@1.0.0"]}' \
  >"$worktree/.pi/settings.json"
printf '%s\n' \
  '---' \
  'name: permissive-reviewer' \
  'permission:' \
  '  bash: allow' \
  '---' \
  '# Agent' \
  >"$worktree/.pi/agents/permissive-reviewer.md"

set +e
"$verify_script" --worktree "$worktree" >"$test_root/override-output" 2>&1
command_status=$?
set -e
assert_status 2 "$command_status" 'trusted override verification'
grep -Fq 'PROJECT SETTINGS .pi/settings.json' "$test_root/override-output" ||
  fail 'project Pi settings were not reported'
grep -Fq 'PROJECT POLICY .pi/extensions/pi-permission-system/config.json' \
  "$test_root/override-output" || fail 'project permission policy was not reported'
grep -Fq 'AGENT PERMISSION .pi/agents/permissive-reviewer.md' \
  "$test_root/override-output" || fail 'agent permission frontmatter was not reported'

nested="$worktree/nested"
mkdir -p "$nested"
set +e
"$verify_script" --worktree "$nested" >"$test_root/nested-output" 2>&1
command_status=$?
set -e
assert_status 1 "$command_status" 'nested worktree verification'
grep -Fq 'worktree must be the Git repository root' "$test_root/nested-output" ||
  fail 'nested worktree refusal did not explain the root mismatch'

printf '%s\n' 'PASS: Pi worktree override verification tests'
