#!/usr/bin/env bash

# Exercise the guardrail hook the way Claude Code calls it: JSON on stdin,
# exit 2 to block and 0 to allow. A scratch repository supplies branch state.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
HOOK="$ROOT/skills/git-guardrails-claude-code/scripts/block-dangerous-git.sh"
REPO=$(mktemp -d "${TMPDIR:-/tmp}/software-factory-guardrails.XXXXXX")
trap 'rm -rf "$REPO"' EXIT HUP INT TERM
git -C "$REPO" init -q -b main
git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

run_hook() {
  jq -n --arg command "$1" --arg cwd "$REPO" '{tool_input:{command:$command},cwd:$cwd}' | bash "$HOOK" >/dev/null 2>&1
}

expect_blocked() {
  status=0
  run_hook "$1" || status=$?
  [ "$status" -eq 2 ] || fail "not blocked (exit $status): $1"
}

expect_allowed() {
  run_hook "$1" || fail "blocked: $1"
}

# On main: any push that would update the default branch is blocked.
expect_blocked "git push"
expect_blocked "git push origin"
expect_blocked "git push origin main"
expect_blocked "git push origin HEAD:main"
expect_blocked "git push origin feature:refs/heads/main"
expect_blocked "cd app && git push origin main"
expect_blocked "git -C . push origin master"
expect_blocked "git push --force origin feature"
expect_blocked "git push -f origin feature"
expect_blocked "git push origin +feature"
expect_blocked "git push --all origin"
expect_blocked "gh pr merge 5 --merge"
expect_blocked "gh pr merge 5 --squash --auto"
expect_blocked "git reset --hard HEAD~1"
expect_blocked "git clean -fd"
expect_blocked "git clean -xdf"
expect_blocked "git branch -D feature"
expect_blocked "git checkout ."
expect_blocked "git checkout -- ."
expect_blocked "git restore ."
expect_blocked "git status; git reset --hard"

expect_allowed "git status"
expect_allowed "ls -la"
expect_allowed "git push -u origin feature/x"
expect_allowed "git push --force-with-lease origin feature/x"
expect_allowed "gh pr merge 5 --merge --match-head-commit abc123"
expect_allowed "git reset --soft HEAD~1"
expect_allowed "git clean -n"
expect_allowed "git branch -d feature"
expect_allowed "git checkout feature"
expect_allowed "git restore src/app.py"

# On a feature branch, a bare push targets that branch and is allowed.
git -C "$REPO" switch -q -c feature/x
expect_allowed "git push"
expect_allowed "git push -u origin HEAD"
expect_blocked "git push origin HEAD:main"

printf 'ok - git guardrails block unsafe commands\n'
