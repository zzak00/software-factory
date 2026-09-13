#!/usr/bin/env bash

set -euo pipefail

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/factory-workflow-test.XXXXXX")
test_root=$(CDPATH='' cd -- "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

source_directory="$test_root/project"
ticket_worktree="$test_root/ticket-worktree"
remote_repository="$test_root/origin.git"
setup_bin="$test_root/setup-bin"
cleanup_bin="$test_root/cleanup-bin"
export FACTORY_TEST_STATE="$test_root/setup-state"
mkdir -p "$source_directory" "$setup_bin" "$cleanup_bin" "$FACTORY_TEST_STATE"
: >"$FACTORY_TEST_STATE/labels"
ln -s "$project_root/test/fakes/gh" "$setup_bin/gh"
ln -s "$project_root/test/fakes/cleanup-gh" "$cleanup_bin/gh"

PATH="$setup_bin:$PATH" "$project_root/scripts/setup-factory.sh" \
  --owner zzak00 \
  --repo scratch-project \
  --source "$source_directory" \
  --apply >"$test_root/setup-output" 2>&1
PATH="$setup_bin:$PATH" "$project_root/scripts/setup-factory.sh" \
  --owner zzak00 \
  --repo scratch-project \
  --source "$source_directory" >"$test_root/setup-verify-output" 2>&1

git init -q --bare "$remote_repository"
git -C "$source_directory" config user.name 'Factory Test'
git -C "$source_directory" config user.email 'factory-test@example.invalid'
git -C "$source_directory" config url."$remote_repository".insteadOf \
  'https://github.com/zzak00/scratch-project.git'

mkdir -p "$source_directory/.github/workflows"
printf '%s\n' '# Scratch project' >"$source_directory/README.md"
printf '%s\n' 'factory workflow' >"$source_directory/app.txt"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
  'grep -Fqx "factory workflow" app.txt' >"$source_directory/test.sh"
chmod +x "$source_directory/test.sh"
printf '%s\n' \
  'name: test' \
  'on: [push, pull_request]' \
  'jobs:' \
  '  test:' \
  '    runs-on: ubuntu-latest' \
  '    steps:' \
  '      - uses: actions/checkout@v4' \
  '      - run: bash test.sh' \
  >"$source_directory/.github/workflows/ci.yml"
(
  cd "$source_directory"
  bash test.sh
)
git -C "$source_directory" add README.md app.txt test.sh .github/workflows/ci.yml
git -C "$source_directory" diff --cached --check
git -C "$source_directory" commit -q -m 'Initialize project'
baseline_commit=$(git -C "$source_directory" rev-parse HEAD)
git -C "$source_directory" push -q --set-upstream origin main
remote_main=$(git -C "$source_directory" ls-remote --heads origin refs/heads/main |
  awk 'NR == 1 { print $1 }')
[[ "$remote_main" == "$baseline_commit" ]] || fail 'published baseline commit differs'

git -C "$source_directory" fetch -q origin main
ticket_base=$(git -C "$source_directory" rev-parse refs/remotes/origin/main)
[[ "$(git -C "$source_directory" rev-parse refs/heads/main)" == "$ticket_base" ]] ||
  fail 'local default branch differs before ticket creation'
git -C "$source_directory" worktree add -q -b issues/1 "$ticket_worktree" "$ticket_base"
[[ "$(git -C "$ticket_worktree" rev-parse HEAD)" == "$ticket_base" ]] ||
  fail 'ticket worktree did not start at the verified default commit'
"$project_root/scripts/verify-pi-worktree.sh" --worktree "$ticket_worktree" \
  >"$test_root/pi-worktree-output" 2>&1

printf '%s\n' 'ticket implementation' >>"$ticket_worktree/app.txt"
git -C "$ticket_worktree" add app.txt
git -C "$ticket_worktree" commit -q -m 'Implement ticket'
first_reviewed_head=$(git -C "$ticket_worktree" rev-parse HEAD)
"$project_root/scripts/verify-review-boundary.sh" \
  --source "$ticket_worktree" \
  --fixed-point "$ticket_base" \
  --head "$first_reviewed_head" \
  --comparison-ref refs/remotes/origin/main \
  >"$test_root/first-review-output" 2>&1

printf '%s\n' 'review correction' >>"$ticket_worktree/app.txt"
git -C "$ticket_worktree" add app.txt
git -C "$ticket_worktree" commit -q -m 'Apply review correction'
reviewed_head=$(git -C "$ticket_worktree" rev-parse HEAD)
"$project_root/scripts/verify-review-boundary.sh" \
  --source "$ticket_worktree" \
  --fixed-point "$ticket_base" \
  --head "$reviewed_head" \
  --comparison-ref refs/remotes/origin/main \
  >"$test_root/rework-review-output" 2>&1
grep -Fq "fixed_point=$ticket_base" "$test_root/rework-review-output" ||
  fail 'rework review did not retain the original fixed point'
git -C "$ticket_worktree" push -q --set-upstream origin issues/1

git -C "$source_directory" merge -q --squash issues/1 >/dev/null 2>&1
git -C "$source_directory" commit -q -m 'Merge ticket'
merge_oid=$(git -C "$source_directory" rev-parse HEAD)
git -C "$source_directory" push -q origin main
git -C "$source_directory" fetch -q origin main
git -C "$source_directory" merge -q --ff-only refs/remotes/origin/main
[[ "$(git -C "$source_directory" rev-parse HEAD)" == \
  "$(git -C "$source_directory" rev-parse refs/remotes/origin/main)" ]] ||
  fail 'local default branch did not synchronize after merge'
(
  cd "$source_directory"
  bash test.sh
)

export CLEANUP_TEST_BASE_BRANCH=main
export CLEANUP_TEST_HEAD_BRANCH=issues/1
export CLEANUP_TEST_HEAD_OID="$reviewed_head"
export CLEANUP_TEST_MERGE_OID="$merge_oid"
export CLEANUP_TEST_ISSUE_STATE=CLOSED
PATH="$cleanup_bin:$PATH" "$project_root/scripts/cleanup-ticket.sh" \
  --source "$source_directory" \
  --repo zzak00/scratch-project \
  --pr 2 \
  --delete-remote >"$test_root/cleanup-inspect-output" 2>&1 || cleanup_status=$?
[[ "${cleanup_status:-0}" -eq 2 ]] || fail 'cleanup inspection did not require approval'
PATH="$cleanup_bin:$PATH" "$project_root/scripts/cleanup-ticket.sh" \
  --source "$source_directory" \
  --repo zzak00/scratch-project \
  --pr 2 \
  --delete-remote \
  --apply >"$test_root/cleanup-apply-output" 2>&1

[[ ! -e "$ticket_worktree" ]] || fail 'sequential workflow left the ticket worktree'
git -C "$source_directory" show-ref --verify --quiet refs/heads/issues/1 &&
  fail 'sequential workflow left the local ticket branch'
[[ -z "$(git -C "$source_directory" ls-remote --heads origin refs/heads/issues/1)" ]] ||
  fail 'sequential workflow left the remote ticket branch'

printf '%s\n' 'PASS: complete sequential factory workflow with rework'
