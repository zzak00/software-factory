#!/usr/bin/env bash

# Exercise the installer's public CLI in disposable home directories. Each
# scenario inspects filesystem effects as a user would see them.
set -u

# The installer always reads skills/ and skills.lock beside itself. Tests that
# alter a bundle therefore make a temporary copy rather than editing sources.
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
INSTALLER="$ROOT/scripts/install-skills.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/software-factory-installer-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

# The dry run intentionally returns 2 when installation is needed. Capture
# status without letting `set -e` stop the script before the comparison.
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

# Install into both harnesses, confirm each copy matches the repository, and
# confirm a second dry run reports that everything is already installed.
HOME_ONE="$TEST_ROOT/home-one"
mkdir -p "$HOME_ONE"
expect_status 2 "$INSTALLER" --target-home "$HOME_ONE" --harness all
expect_status 0 "$INSTALLER" --target-home "$HOME_ONE" --harness all --apply
expect_status 0 "$INSTALLER" --target-home "$HOME_ONE" --harness all
diff -qr "$ROOT/skills" "$HOME_ONE/.agents/skills" >/dev/null || fail "Codex bundle differs"
diff -qr "$ROOT/skills" "$HOME_ONE/.claude/skills" >/dev/null || fail "Claude bundle differs"

# A macOS .DS_Store left in an installed skill must not read as a conflict.
printf 'Bud1\0' > "$HOME_ONE/.claude/skills/code-review/.DS_Store"
expect_status 0 "$INSTALLER" --target-home "$HOME_ONE" --harness all

HOME_TWO="$TEST_ROOT/home-two"
# A user-modified skill in either requested destination blocks the entire
# operation before the other destination is created.
mkdir -p "$HOME_TWO/.agents/skills/code-review"
printf 'conflict\n' > "$HOME_TWO/.agents/skills/code-review/SKILL.md"
expect_status 1 "$INSTALLER" --target-home "$HOME_TWO" --harness all --apply
[ ! -e "$HOME_TWO/.claude" ] || fail "conflict caused a partial installation"

HOME_THREE="$TEST_ROOT/home-three"
# A one-harness request must not create the other harness's directory.
mkdir -p "$HOME_THREE"
expect_status 0 "$INSTALLER" --target-home "$HOME_THREE" --harness codex --apply
[ -d "$HOME_THREE/.agents/skills" ] || fail "Codex destination missing"
[ ! -e "$HOME_THREE/.claude" ] || fail "Claude destination should not exist"

BROKEN_BUNDLE="$TEST_ROOT/broken-bundle"
# Build a copy of the published artifact to exercise malicious or malformed
# sources without changing the repository's skill files or lock.
mkdir -p "$BROKEN_BUNDLE/scripts"
cp -R "$ROOT/skills" "$BROKEN_BUNDLE/skills"
cp "$ROOT/skills.lock" "$BROKEN_BUNDLE/skills.lock"
cp "$INSTALLER" "$BROKEN_BUNDLE/scripts/install-skills.sh"
printf 'outside the lock\n' > "$TEST_ROOT/external.md"
ln -s "$TEST_ROOT/external.md" "$BROKEN_BUNDLE/skills/code-review/unlisted.md"
# Even an unlisted symlink is unsafe; the installer must reject it before
# creating a destination directory.
expect_status 1 "$BROKEN_BUNDLE/scripts/install-skills.sh" --target-home "$TEST_ROOT/symlink-home" --harness codex --apply
[ ! -e "$TEST_ROOT/symlink-home/.agents" ] || fail "unlisted symlink caused an installation"
unlink "$BROKEN_BUNDLE/skills/code-review/unlisted.md"

# Replace the second lock entry with a duplicate of the first. This used to
# leave one genuine file uncovered while still satisfying a simple count.
awk '
  /^  - path: / {
    entry++
    if (entry == 1) {
      first_path = $0
      getline
      first_hash = $0
      print first_path
      print first_hash
      next
    }
    if (entry == 2) {
      getline
      print first_path
      print first_hash
      next
    }
  }
  { print }
' "$BROKEN_BUNDLE/skills.lock" > "$BROKEN_BUNDLE/duplicate.lock"
mv "$BROKEN_BUNDLE/duplicate.lock" "$BROKEN_BUNDLE/skills.lock"
# Also change a file to ensure the malformed lock cannot be used to copy
# content whose hash no longer matches the distributed artifact.
printf 'unverified change\n' > "$BROKEN_BUNDLE/skills/code-review/agents/openai.yaml"
expect_status 1 "$BROKEN_BUNDLE/scripts/install-skills.sh" --target-home "$TEST_ROOT/duplicate-home" --harness codex --apply
[ ! -e "$TEST_ROOT/duplicate-home/.agents" ] || fail "duplicate lock entry caused an installation"

printf 'ok - installer safety and idempotency\n'
