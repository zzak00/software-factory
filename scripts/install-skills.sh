#!/usr/bin/env bash

# Install the repository's optional skill bundle into local agent harnesses.
# The preflight writes only disposable manifests; --apply is required before
# any destination directory is created or changed.
set -u

# Resolve paths from this script rather than from the caller's current folder.
# The lock and skills directory always come from the same checkout.
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

# Parse requested harnesses and an optional home override. `all` installs the
# same source into the Codex and Claude Code skill directories.
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

# Reject relative homes, unsupported harnesses, and absent metadata before
# making temporary files or touching the destination.
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

# Keep derived manifests in a disposable directory, removed on every exit.
# LOCK_ENTRIES contains path|hash pairs; the other files are sorted indexes.
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/software-factory-install.XXXXXX") || fail "cannot create temporary directory"
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
LOCK_ENTRIES="$TMP_ROOT/lock-entries"
SOURCE_FILES="$TMP_ROOT/source-files"
LOCK_PATHS="$TMP_ROOT/lock-paths"
SKILL_NAMES="$TMP_ROOT/skill-names"

# Extract the small, fixed lock-file shape without executing its contents.
# A path is paired with the following sha256 line, then verified below.
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
# The bundle may contain directories and ordinary files only. Reject symlinks
# and other special entries even if a tool might otherwise follow them.
unsupported=$(find "$REPO_ROOT/skills" ! -type f ! -type d -print -quit) || fail "cannot inspect source skills"
[ -z "$unsupported" ] || fail "unsupported source entry: $unsupported"
(CDPATH='' cd -- "$REPO_ROOT" && find skills -type f ! -name '.DS_Store' -print | LC_ALL=C sort) > "$SOURCE_FILES" || fail "cannot list source skills"
# Exact sorted equality catches missing files, unlocked files, and duplicate
# lock paths. It also prevents an extra file from silently entering a bundle.
awk -F'|' '{print $1}' "$LOCK_ENTRIES" | LC_ALL=C sort > "$LOCK_PATHS" || fail "cannot list locked paths"
cmp -s "$LOCK_PATHS" "$SOURCE_FILES" || fail "skills.lock does not exactly cover the distributed files"

# Hash every listed source file before any installation. A mismatch means the
# checkout is different from the audited artifact recorded in skills.lock.
while IFS='|' read -r relative expected; do
  source_path="$REPO_ROOT/$relative"
  [ -f "$source_path" ] || fail "locked file is missing: $relative"
  actual=$(shasum -a 256 "$source_path" | awk '{print $1}') || fail "cannot hash $relative"
  [ "$actual" = "$expected" ] || fail "hash mismatch: $relative"
done < "$LOCK_ENTRIES"

# Each first path component below skills/ names one installable skill folder.
awk -F/ '/^skills\// { print $2 }' "$LOCK_ENTRIES" | LC_ALL=C sort -u > "$SKILL_NAMES"

# Destination roots are assembled once; the same loop below handles one or
# both harnesses. No source file is generated or changed by this installer.
DESTINATIONS=""
case "$HARNESS" in
  all) DESTINATIONS="$TARGET_HOME_VALUE/.agents/skills
$TARGET_HOME_VALUE/.claude/skills" ;;
  codex) DESTINATIONS="$TARGET_HOME_VALUE/.agents/skills" ;;
  claude) DESTINATIONS="$TARGET_HOME_VALUE/.claude/skills" ;;
esac

NEEDED=0
CONFLICT=0
# Scan every requested destination before installing anything. An existing
# skill must be byte-for-byte equivalent except for harmless .DS_Store files;
# a differing skill is user-owned and must not be overwritten.
while IFS= read -r destination_root; do
  while IFS= read -r skill; do
    source_dir="$REPO_ROOT/skills/$skill"
    destination="$destination_root/$skill"
    if [ ! -e "$destination" ]; then
      printf 'install needed: %s\n' "$destination"
      NEEDED=1
    elif [ ! -d "$destination" ] || ! diff -qr -x '.DS_Store' "$source_dir" "$destination" >/dev/null 2>&1; then
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

# Dry-run exit codes are intentional: 0 means already installed, 2 means an
# install is needed, and 1 means unsafe input or an existing conflict.
if [ "$APPLY" -eq 0 ]; then
  [ "$NEEDED" -eq 0 ] && exit 0
  exit 2
fi

# Copy each absent skill into a temporary sibling and rename it into place.
# This avoids presenting a partially copied skill as an installed one. The
# pre-scan above ensures an existing destination is never replaced.
while IFS= read -r destination_root; do
  mkdir -p "$destination_root" || fail "cannot create $destination_root"
  while IFS= read -r skill; do
    source_dir="$REPO_ROOT/skills/$skill"
    destination="$destination_root/$skill"
    [ -e "$destination" ] && continue
    temporary="$destination_root/.${skill}.tmp.$$"
    [ ! -e "$temporary" ] || fail "temporary destination exists: $temporary"
    cp -R "$source_dir" "$temporary" || fail "cannot copy $skill"
    # Finder metadata is ignored by the manifest and destination comparison,
    # so remove it from a new copy before publishing that destination.
    find "$temporary" -name '.DS_Store' -type f -delete || fail "cannot remove source metadata from $skill"
    mv "$temporary" "$destination" || fail "cannot finalize $destination"
    printf 'installed: %s\n' "$destination"
  done < "$SKILL_NAMES"
done <<EOF
$DESTINATIONS
EOF

exit 0
