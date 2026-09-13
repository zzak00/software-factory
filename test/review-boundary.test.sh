#!/usr/bin/env bash

set -euo pipefail

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
verify_script="$project_root/scripts/verify-review-boundary.sh"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/review-boundary-test.XXXXXX")
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

repository="$test_root/repository"
git init -q -b main "$repository"
git -C "$repository" config user.name 'Factory Test'
git -C "$repository" config user.email 'factory-test@example.invalid'
printf '%s\n' 'base' >"$repository/base.txt"
git -C "$repository" add base.txt
git -C "$repository" commit -q -m 'Original fixed point'
fixed_point=$(git -C "$repository" rev-parse HEAD)
git -C "$repository" update-ref refs/remotes/origin/main "$fixed_point"

git -C "$repository" switch -q -c issues/1
printf '%s\n' 'ticket' >"$repository/ticket.txt"
git -C "$repository" add ticket.txt
git -C "$repository" commit -q -m 'Ticket change'
reviewed_head=$(git -C "$repository" rev-parse HEAD)

"$verify_script" \
  --source "$repository" \
  --fixed-point "$fixed_point" \
  --head "$reviewed_head" \
  --comparison-ref refs/remotes/origin/main \
  >"$test_root/matching-output" 2>&1
grep -Fq "fixed_point=$fixed_point" "$test_root/matching-output" ||
  fail 'matching review boundary omitted the fixed point'
grep -Fq "reviewed_head=$reviewed_head" "$test_root/matching-output" ||
  fail 'matching review boundary omitted the reviewed head'
grep -Fq 'changed_file=ticket.txt' "$test_root/matching-output" ||
  fail 'matching review boundary omitted its changed-file set'

git -C "$repository" switch -q main
printf '%s\n' 'later default work' >"$repository/default.txt"
git -C "$repository" add default.txt
git -C "$repository" commit -q -m 'Later default branch change'
later_default=$(git -C "$repository" rev-parse HEAD)
git -C "$repository" update-ref refs/remotes/origin/main "$later_default"
git -C "$repository" switch -q issues/1
git -C "$repository" merge -q --no-edit main
integrated_head=$(git -C "$repository" rev-parse HEAD)

set +e
"$verify_script" \
  --source "$repository" \
  --fixed-point "$fixed_point" \
  --head "$integrated_head" \
  --comparison-ref refs/remotes/origin/main \
  >"$test_root/narrowed-output" 2>&1
command_status=$?
set -e
assert_status 1 "$command_status" 'narrowed Plannotator comparison'
grep -Fq 'human review boundary is incomplete' "$test_root/narrowed-output" ||
  fail 'narrowed comparison did not fail the human review gate'
grep -Fq "comparison_merge_base=$later_default" "$test_root/narrowed-output" ||
  fail 'narrowed comparison did not report the later merge base'
grep -Fq "required_fixed_point=$fixed_point" "$test_root/narrowed-output" ||
  fail 'narrowed comparison did not retain the original fixed point'

printf '%s\n' 'rework' >>"$repository/ticket.txt"
git -C "$repository" add ticket.txt
git -C "$repository" commit -q -m 'Rework ticket'
rework_head=$(git -C "$repository" rev-parse HEAD)
set +e
"$verify_script" \
  --source "$repository" \
  --fixed-point "$fixed_point" \
  --head "$rework_head" \
  --comparison-ref refs/remotes/origin/main \
  >"$test_root/rework-output" 2>&1
command_status=$?
set -e
assert_status 1 "$command_status" 'narrowed rework comparison'
grep -Fq "required_fixed_point=$fixed_point" "$test_root/rework-output" ||
  fail 'rework comparison replaced the original fixed point'

printf '%s\n' 'PASS: exact human review boundary tests'
