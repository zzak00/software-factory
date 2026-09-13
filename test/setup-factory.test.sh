#!/usr/bin/env bash

set -euo pipefail

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
setup_script="$project_root/scripts/setup-factory.sh"
fake_bin="$project_root/test/fakes"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/setup-factory-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

export PATH="$fake_bin:$PATH"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file: $1"
}

assert_status() {
  expected=$1
  actual=$2
  context=$3
  [[ "$actual" -eq "$expected" ]] ||
    fail "$context returned $actual, expected $expected"
}

seed_complete_remote_state() {
  : >"$FACTORY_TEST_STATE/repository"
  : >"$FACTORY_TEST_STATE/project"
  : >"$FACTORY_TEST_STATE/status_updated"
  : >"$FACTORY_TEST_STATE/view_created"
  printf '%s\n' \
    'factory:spec|1D76DB|Parent issue with an approved factory specification' \
    'needs-info|D4C5F9|Planning is blocked on human-provided information' \
    'wontfix|FFFFFF|Work was intentionally rejected or closed without implementation' \
    >"$FACTORY_TEST_STATE/labels"
}

initialize_source_with_origin() {
  git -C "$source_directory" init -q -b main
  git -C "$source_directory" remote add origin 'https://github.com/zzak00/scratch-project.git'
}

new_case() {
  case_name=$1
  case_root="$test_root/$case_name"
  source_directory="$case_root/scratch-project"
  export FACTORY_TEST_STATE="$case_root/state"
  mkdir -p "$source_directory" "$FACTORY_TEST_STATE"
  : >"$FACTORY_TEST_STATE/labels"
}

run_setup() {
  "$setup_script" \
    --owner zzak00 \
    --repo scratch-project \
    --source "$source_directory" \
    "$@"
}

new_case inspect_fresh
set +e
run_setup >"$case_root/output" 2>&1
command_status=$?
set -e
assert_status 2 "$command_status" 'fresh inspect'
[[ ! -d "$source_directory/.git" ]] || fail 'inspect mode initialized Git'
[[ ! -e "$FACTORY_TEST_STATE/repository" ]] || fail 'inspect mode created repository'
for planned_operation in \
  'initialize local Git repository' \
  'create private GitHub repository' \
  'add origin' \
  'create private Project' \
  'link Project to repository' \
  'configure Status field' \
  'create Kanban board view' \
  'reconcile factory labels'
do
  grep -Fq "PLAN $planned_operation" "$case_root/output" ||
    fail "fresh inspection omitted planned operation: $planned_operation"
done

new_case nested_source
git -C "$case_root" init -q -b main
set +e
run_setup --apply >"$case_root/output" 2>&1
command_status=$?
set -e
assert_status 1 "$command_status" 'nested source apply'
grep -Fq 'source must be the Git repository root' "$case_root/output" ||
  fail 'nested source refusal did not explain the Git root mismatch'
[[ ! -e "$FACTORY_TEST_STATE/repository" ]] || fail 'nested source created a remote repository'
[[ -z "$(git -C "$case_root" remote)" ]] || fail 'nested source changed the parent repository remote'

new_case collect_conflicts
seed_complete_remote_state
initialize_source_with_origin
git -C "$source_directory" remote set-url origin 'https://github.com/other/project.git'
export FACTORY_TEST_PROJECT_PUBLIC=true
set +e
run_setup >"$case_root/output" 2>&1
command_status=$?
set -e
unset FACTORY_TEST_PROJECT_PUBLIC
assert_status 1 "$command_status" 'conflicting setup inspection'
grep -Fq 'CONFLICT origin points to unexpected repository' "$case_root/output" ||
  fail 'inspection omitted the origin conflict'
grep -Fq 'CONFLICT Project visibility is public, expected private' "$case_root/output" ||
  fail 'inspection omitted the Project visibility conflict'

new_case missing_origin
seed_complete_remote_state
: >"$FACTORY_TEST_STATE/linked"
git -C "$source_directory" init -q -b main
set +e
run_setup >"$case_root/output" 2>&1
command_status=$?
set -e
assert_status 2 "$command_status" 'missing origin inspection'
grep -Fq 'PLAN add origin' "$case_root/output" || fail 'missing origin was not planned'

new_case missing_project_link
seed_complete_remote_state
initialize_source_with_origin
set +e
run_setup >"$case_root/output" 2>&1
command_status=$?
set -e
assert_status 2 "$command_status" 'missing Project link inspection'
grep -Fq 'PLAN link Project to repository' "$case_root/output" ||
  fail 'missing Project link was not planned'

new_case apply_and_rerun
printf '%s\n' 'local application file' >"$source_directory/app.txt"
printf '%s\n' 'untracked secret' >"$source_directory/local.secret"

run_setup --apply >"$case_root/first-output" 2>&1

assert_file "$FACTORY_TEST_STATE/repository"
assert_file "$FACTORY_TEST_STATE/project"
assert_file "$FACTORY_TEST_STATE/linked"
assert_file "$FACTORY_TEST_STATE/status_updated"
assert_file "$FACTORY_TEST_STATE/view_created"
[[ "$(wc -l <"$FACTORY_TEST_STATE/labels" | tr -d ' ')" -eq 3 ]] ||
  fail 'factory labels were not created exactly once'
grep -Fqx 'wontfix|FFFFFF|Work was intentionally rejected or closed without implementation' "$FACTORY_TEST_STATE/labels" ||
  fail 'default wontfix label was not reconciled'
[[ -d "$source_directory/.git" ]] || fail 'apply mode did not initialize Git'
[[ "$(git -C "$source_directory" remote get-url origin)" == 'https://github.com/zzak00/scratch-project.git' ]] ||
  fail 'origin was not configured'
[[ ! -e "$source_directory/.factory.json" ]] || fail 'setup wrote .factory.json'
[[ ! -e "$source_directory/AGENTS.md" ]] || fail 'setup wrote AGENTS.md'
[[ ! -e "$source_directory/scripts/factory-move.sh" ]] || fail 'setup installed a status helper'
[[ ! -e "$FACTORY_TEST_STATE/ruleset" ]] || fail 'setup created a ruleset'
[[ ! -e "$FACTORY_TEST_STATE/pushes" ]] || fail 'setup pushed a branch'
[[ -f "$source_directory/local.secret" ]] || fail 'untracked file was removed'
[[ -f "$source_directory/app.txt" ]] || fail 'application file was removed'

run_setup --apply >"$case_root/second-output" 2>&1
[[ "$(wc -l <"$FACTORY_TEST_STATE/labels" | tr -d ' ')" -eq 3 ]] ||
  fail 'idempotent rerun duplicated labels'

run_setup >"$case_root/inspect-complete-output" 2>&1

set +e
run_setup --workflows-confirmed >"$case_root/removed-option-output" 2>&1
command_status=$?
set -e
assert_status 1 "$command_status" 'removed completion option'
grep -q 'unknown option: --workflows-confirmed' "$case_root/removed-option-output" ||
  fail 'removed completion option did not fail clearly'

new_case partial_recovery
export FACTORY_TEST_FAIL_PROJECT_LIST_CALL=2
set +e
run_setup --apply >"$case_root/failed-output" 2>&1
command_status=$?
set -e
assert_status 1 "$command_status" 'simulated API failure'
assert_file "$FACTORY_TEST_STATE/repository"
[[ ! -e "$FACTORY_TEST_STATE/project" ]] || fail 'Project was created after list failure'

unset FACTORY_TEST_FAIL_PROJECT_LIST_CALL
run_setup --apply >"$case_root/recovery-output" 2>&1
assert_file "$FACTORY_TEST_STATE/project"
assert_file "$FACTORY_TEST_STATE/view_created"

printf '%s\n' 'PASS: setup-factory initial-setup tests'
