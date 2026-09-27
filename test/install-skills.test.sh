#!/usr/bin/env bash

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
INSTALLER="$ROOT/scripts/install-skills.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/software-factory-installer-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

expect_status() {
  expected=$1
  shift
  set +e
  "$@" >/dev/null 2>&1
  actual=$?
  set -e
  [ "$actual" -eq "$expected" ] || fail "expected $expected, got $actual: $*"
}

set -e

HOME_ONE="$TEST_ROOT/home-one"
mkdir -p "$HOME_ONE"
expect_status 2 "$INSTALLER" --target-home "$HOME_ONE" --harness all
expect_status 0 "$INSTALLER" --target-home "$HOME_ONE" --harness all --apply
expect_status 0 "$INSTALLER" --target-home "$HOME_ONE" --harness all
diff -qr "$ROOT/skills" "$HOME_ONE/.agents/skills" >/dev/null || fail "Codex bundle differs"
diff -qr "$ROOT/skills" "$HOME_ONE/.claude/skills" >/dev/null || fail "Claude bundle differs"

HOME_TWO="$TEST_ROOT/home-two"
mkdir -p "$HOME_TWO/.agents/skills/code-review"
printf 'conflict\n' > "$HOME_TWO/.agents/skills/code-review/SKILL.md"
expect_status 1 "$INSTALLER" --target-home "$HOME_TWO" --harness all --apply
[ ! -e "$HOME_TWO/.claude" ] || fail "conflict caused a partial installation"

HOME_THREE="$TEST_ROOT/home-three"
mkdir -p "$HOME_THREE"
expect_status 0 "$INSTALLER" --target-home "$HOME_THREE" --harness codex --apply
[ -d "$HOME_THREE/.agents/skills" ] || fail "Codex destination missing"
[ ! -e "$HOME_THREE/.claude" ] || fail "Claude destination should not exist"

printf 'ok - installer safety and idempotency\n'
