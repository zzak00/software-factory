#!/usr/bin/env bash

set -u

VERSION="1.0.0"
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
LOCK_FILE="$REPO_ROOT/skills.lock"
HARNESS="all"
TARGET_HOME_VALUE=${HOME:-}
APPLY=0

usage() {
  cat <<'EOF'
Usage: install-skills.sh [options]

Options:
  --harness all|codex|claude  Select destination harnesses (default: all)
  --target-home ABSOLUTE      Install below this home directory
  --apply                     Apply the verified installation
  --help                      Show this help
  --version                   Show the installer version
EOF
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --harness)
      [ "$#" -ge 2 ] || fail "--harness requires a value"
      HARNESS=$2
      shift 2
      ;;
    --target-home)
      [ "$#" -ge 2 ] || fail "--target-home requires a value"
      TARGET_HOME_VALUE=$2
      shift 2
      ;;
    --apply)
      APPLY=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    --version)
      printf '%s\n' "$VERSION"
      exit 0
      ;;
    *) fail "unknown option: $1" ;;
  esac
done

case "$HARNESS" in
  all|codex|claude) ;;
  *) fail "--harness must be all, codex, or claude" ;;
esac

[ -n "$TARGET_HOME_VALUE" ] || fail "a target home is required"
case "$TARGET_HOME_VALUE" in
  /*) ;;
  *) fail "--target-home must be an absolute path" ;;
esac
[ -f "$LOCK_FILE" ] || fail "missing skills.lock"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/software-factory-install.XXXXXX") || fail "cannot create temporary directory"
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
LOCK_ENTRIES="$TMP_ROOT/lock-entries"
SOURCE_FILES="$TMP_ROOT/source-files"
SKILL_NAMES="$TMP_ROOT/skill-names"

awk '
  /^files:/ { in_files=1; next }
  in_files && /^  - path: / {
    path=$0
    sub(/^  - path: "/, "", path)
    sub(/"$/, "", path)
    next
  }
  in_files && /^    sha256: / {
    hash=$0
    sub(/^    sha256: "/, "", hash)
    sub(/"$/, "", hash)
    print path "|" hash
  }
' "$LOCK_FILE" > "$LOCK_ENTRIES" || fail "cannot parse skills.lock"

[ -s "$LOCK_ENTRIES" ] || fail "skills.lock contains no files"
find "$REPO_ROOT/skills" -type f -print | LC_ALL=C sort > "$SOURCE_FILES" || fail "cannot list source skills"

LOCK_COUNT=$(wc -l < "$LOCK_ENTRIES" | tr -d ' ')
SOURCE_COUNT=$(wc -l < "$SOURCE_FILES" | tr -d ' ')
[ "$LOCK_COUNT" = "$SOURCE_COUNT" ] || fail "skills.lock does not cover every distributed file"

while IFS='|' read -r relative expected; do
  source_path="$REPO_ROOT/$relative"
  [ -f "$source_path" ] || fail "locked file is missing: $relative"
  actual=$(shasum -a 256 "$source_path" | awk '{print $1}') || fail "cannot hash $relative"
  [ "$actual" = "$expected" ] || fail "hash mismatch: $relative"
  if ! grep -Fqx "$source_path" "$SOURCE_FILES"; then
    fail "locked path is outside the distributed bundle: $relative"
  fi
done < "$LOCK_ENTRIES"

awk -F/ '/^skills\// { print $2 }' "$LOCK_ENTRIES" | LC_ALL=C sort -u > "$SKILL_NAMES"

DESTINATIONS=""
case "$HARNESS" in
  all) DESTINATIONS="$TARGET_HOME_VALUE/.agents/skills
$TARGET_HOME_VALUE/.claude/skills" ;;
  codex) DESTINATIONS="$TARGET_HOME_VALUE/.agents/skills" ;;
  claude) DESTINATIONS="$TARGET_HOME_VALUE/.claude/skills" ;;
esac

NEEDED=0
CONFLICT=0
while IFS= read -r destination_root; do
  while IFS= read -r skill; do
    source_dir="$REPO_ROOT/skills/$skill"
    destination="$destination_root/$skill"
    if [ ! -e "$destination" ]; then
      printf 'install needed: %s\n' "$destination"
      NEEDED=1
    elif [ ! -d "$destination" ] || ! diff -qr "$source_dir" "$destination" >/dev/null 2>&1; then
      printf 'conflict: %s\n' "$destination" >&2
      CONFLICT=1
    else
      printf 'verified: %s\n' "$destination"
    fi
  done < "$SKILL_NAMES"
done <<EOF
$DESTINATIONS
EOF

[ "$CONFLICT" -eq 0 ] || fail "refusing to overwrite a differing installation"

if [ "$APPLY" -eq 0 ]; then
  [ "$NEEDED" -eq 0 ] && exit 0
  exit 2
fi

while IFS= read -r destination_root; do
  mkdir -p "$destination_root" || fail "cannot create $destination_root"
  while IFS= read -r skill; do
    source_dir="$REPO_ROOT/skills/$skill"
    destination="$destination_root/$skill"
    [ -e "$destination" ] && continue
    temporary="$destination_root/.${skill}.tmp.$$"
    [ ! -e "$temporary" ] || fail "temporary destination exists: $temporary"
    cp -R "$source_dir" "$temporary" || fail "cannot copy $skill"
    mv "$temporary" "$destination" || fail "cannot finalize $destination"
    printf 'installed: %s\n' "$destination"
  done < "$SKILL_NAMES"
done <<EOF
$DESTINATIONS
EOF

exit 0
