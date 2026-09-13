#!/usr/bin/env bash

set -euo pipefail

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cleanup_script="$project_root/scripts/cleanup-ticket.sh"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/cleanup-ticket-test.XXXXXX")
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

remote_repository="$test_root/origin.git"
source_directory="$test_root/scratch-project"
worktree_directory="$source_directory/.git/phantom/worktrees/issues/1"
fake_bin="$test_root/bin"
export CLEANUP_TEST_REAL_GIT
CLEANUP_TEST_REAL_GIT=$(command -v git)

mkdir -p "$fake_bin"
ln -s "$project_root/test/fakes/cleanup-gh" "$fake_bin/gh"
ln -s "$project_root/test/fakes/cleanup-git" "$fake_bin/git"

git init --bare "$remote_repository" >/dev/null 2>&1
git init -b main "$source_directory" >/dev/null 2>&1
git -C "$source_directory" config user.name 'Factory Test'
git -C "$source_directory" config user.email 'factory-test@example.invalid'
printf '%s\n' 'base' >"$source_directory/app.txt"
git -C "$source_directory" add app.txt
git -C "$source_directory" commit -m 'Initialize test repository' >/dev/null
git -C "$source_directory" config url."$remote_repository".insteadOf \
  'https://github.com/test/repo.git'
git -C "$source_directory" remote add origin 'https://github.com/test/repo.git'
git -C "$source_directory" push --set-upstream origin main >/dev/null 2>&1

mkdir -p "$(dirname -- "$worktree_directory")"
git -C "$source_directory" worktree add -b issues/1 "$worktree_directory" main >/dev/null 2>&1
printf '%s\n' 'feature' >"$worktree_directory/app.txt"
git -C "$worktree_directory" add app.txt
git -C "$worktree_directory" commit -m 'Implement issue 1' >/dev/null
git -C "$worktree_directory" push --set-upstream origin issues/1 >/dev/null 2>&1

export CLEANUP_TEST_BASE_BRANCH=main
export CLEANUP_TEST_HEAD_BRANCH=issues/1
export CLEANUP_TEST_ISSUE_STATE=CLOSED
export CLEANUP_TEST_HEAD_OID
CLEANUP_TEST_HEAD_OID=$(git -C "$worktree_directory" rev-parse HEAD)

printf '%s\n' 'concurrent feature update' >"$worktree_directory/app.txt"
git -C "$worktree_directory" add app.txt
git -C "$worktree_directory" commit -m 'Prepare concurrent update' >/dev/null
export CLEANUP_TEST_RACE_OID
CLEANUP_TEST_RACE_OID=$(git -C "$worktree_directory" rev-parse HEAD)
git -C "$worktree_directory" push origin \
  "$CLEANUP_TEST_RACE_OID:refs/heads/race-staging" >/dev/null 2>&1
git -C "$worktree_directory" reset --hard "$CLEANUP_TEST_HEAD_OID" >/dev/null

git -C "$source_directory" merge --squash issues/1 >/dev/null
git -C "$source_directory" commit -m 'Merge issue 1' >/dev/null
git -C "$source_directory" push origin main >/dev/null 2>&1
export CLEANUP_TEST_MERGE_OID
CLEANUP_TEST_MERGE_OID=$(git -C "$source_directory" rev-parse HEAD)

run_cleanup() {
  PATH="$fake_bin:$PATH" "$cleanup_script" \
    --source "$source_directory" \
    --repo test/repo \
    --pr 2 \
    "$@"
}

git -C "$source_directory" config --add remote.origin.pushurl \
  'https://github.com/other/repo.git'
set +e
run_cleanup --delete-remote >"$test_root/mismatched-push-output" 2>&1
command_status=$?
set -e
assert_status 1 "$command_status" 'mismatched push destination inspection'
grep -Fq 'origin push destination identifies other/repo, not test/repo' \
  "$test_root/mismatched-push-output" ||
  fail 'mismatched push destination refusal was not explained'
[[ -d "$worktree_directory" ]] || fail 'push destination inspection removed the worktree'

git -C "$source_directory" config --unset-all remote.origin.pushurl
git -C "$source_directory" config --add remote.origin.pushurl \
  'https://github.com/test/repo.git'
git -C "$source_directory" config --add remote.origin.pushurl \
  'git@github.com:test/repo.git'
set +e
run_cleanup --delete-remote >"$test_root/multiple-push-output" 2>&1
command_status=$?
set -e
assert_status 1 "$command_status" 'multiple push destinations inspection'
grep -Fq 'origin must have exactly one push destination' "$test_root/multiple-push-output" ||
  fail 'multiple push destination refusal was not explained'

git -C "$source_directory" config --unset-all remote.origin.pushurl
git -C "$source_directory" config --add remote.origin.pushurl \
  'https://github.com/test/repo.git'

export CLEANUP_TEST_ISSUE_STATE=OPEN
set +e
run_cleanup --apply --delete-remote >"$test_root/open-issue-output" 2>&1
command_status=$?
set -e
assert_status 1 "$command_status" 'open-issue apply'
grep -Fq 'linked issue is not closed: https://github.com/test/repo/issues/1' \
  "$test_root/open-issue-output" || fail 'open-issue apply did not explain its refusal'
[[ -d "$worktree_directory" ]] || fail 'open-issue apply removed the worktree'
export CLEANUP_TEST_ISSUE_STATE=CLOSED

set +e
run_cleanup >"$test_root/inspect-output" 2>&1
command_status=$?
set -e
assert_status 2 "$command_status" 'initial inspect'
grep -Fq "PLAN remove clean worktree: $worktree_directory" "$test_root/inspect-output" ||
  fail 'inspect did not plan worktree removal'
grep -Fq 'remote branch preserved; pass --delete-remote to include it' "$test_root/inspect-output" ||
  fail 'inspect did not preserve the remote branch by default'
[[ -d "$worktree_directory" ]] || fail 'inspect removed the worktree'

printf '%s\n' 'uncommitted' >"$worktree_directory/local.txt"
set +e
run_cleanup --apply --delete-remote >"$test_root/dirty-output" 2>&1
command_status=$?
set -e
assert_status 1 "$command_status" 'dirty apply'
grep -Fq "worktree is not clean: $worktree_directory" "$test_root/dirty-output" ||
  fail 'dirty apply did not explain its refusal'
[[ -d "$worktree_directory" ]] || fail 'dirty apply removed the worktree'
rm "$worktree_directory/local.txt"

export CLEANUP_TEST_ADVANCE_BEFORE_DELETE=true
export CLEANUP_TEST_RACE_REMOTE="$remote_repository"
export CLEANUP_TEST_RACE_MARKER="$test_root/race-triggered"
set +e
run_cleanup --apply --delete-remote >"$test_root/race-output" 2>&1
command_status=$?
set -e
unset CLEANUP_TEST_ADVANCE_BEFORE_DELETE
assert_status 1 "$command_status" 'concurrent remote update cleanup'
[[ "$(git --git-dir="$remote_repository" rev-parse refs/heads/issues/1)" == \
  "$CLEANUP_TEST_RACE_OID" ]] || fail 'cleanup deleted a concurrent remote update'

git --git-dir="$remote_repository" update-ref refs/heads/issues/1 "$CLEANUP_TEST_HEAD_OID"
run_cleanup --apply --delete-remote >"$test_root/apply-output" 2>&1
[[ ! -e "$worktree_directory" ]] || fail 'apply did not remove the worktree'
if git -C "$source_directory" show-ref --verify --quiet refs/heads/issues/1; then
  fail 'apply did not delete the local branch'
fi
[[ -z "$(git -C "$source_directory" ls-remote --heads origin refs/heads/issues/1)" ]] ||
  fail 'apply did not delete the remote branch'
[[ "$(git -C "$source_directory" rev-parse HEAD)" == "$CLEANUP_TEST_MERGE_OID" ]] ||
  fail 'apply changed the default branch'

run_cleanup --apply --delete-remote >"$test_root/retry-output" 2>&1
grep -Fq 'requested ticket cleanup complete' "$test_root/retry-output" ||
  fail 'idempotent retry did not report completion'

run_cleanup --delete-remote >"$test_root/complete-output" 2>&1
grep -Fq 'requested ticket cleanup already complete' "$test_root/complete-output" ||
  fail 'completed inspect did not report idempotency'

printf '%s\n' 'PASS: cleanup-ticket critical lifecycle test'
