#!/usr/bin/env bash

set -euo pipefail

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
archive_ref=${1:-HEAD}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

if ! source_commit=$(git -C "$project_root" rev-parse --verify "$archive_ref^{commit}" 2>/dev/null); then
  if [[ $# -eq 0 ]]; then
    printf '%s\n' 'SKIP: archive verification requires an approved source commit'
    exit 0
  fi
  fail "archive ref does not resolve to a commit: $archive_ref"
fi

archive_root=$(mktemp -d "${TMPDIR:-/tmp}/software-factory-archive.XXXXXX")
archive_file="$archive_root/software-factory.tar"
archive_entries="$archive_root/entries"
trap 'rm -rf "$archive_root"' EXIT

git -C "$project_root" archive \
  --format=tar \
  --prefix=software-factory/ \
  --output="$archive_file" \
  "$source_commit"
tar -tf "$archive_file" >"$archive_entries"

for required_path in \
  README.md \
  LICENSE \
  .github/workflows/ci.yml \
  skills.lock \
  pi-permissions.lock \
  config/pi-permission-system.json \
  pi-extension-runtime/package.json \
  pi-extension-runtime/package-lock.json \
  scripts/setup-factory.sh \
  scripts/cleanup-ticket.sh \
  scripts/install-skills.sh \
  scripts/install-pi-permissions.sh \
  scripts/verify-pi-worktree.sh \
  scripts/verify-review-boundary.sh \
  test/setup-factory.test.sh \
  test/install-skills.test.sh \
  test/install-pi-permissions.test.sh \
  test/verify-pi-worktree.test.sh \
  test/review-boundary.test.sh \
  test/cleanup-ticket.test.sh \
  test/factory-workflow.test.sh \
  test/locks.test.sh \
  test/archive.test.sh
do
  grep -Fqx "software-factory/$required_path" "$archive_entries" ||
    fail "portable archive is missing: $required_path"
done

while IFS= read -r locked_skill; do
  grep -Fqx "software-factory/$locked_skill" "$archive_entries" ||
    fail "portable archive is missing locked skill file: $locked_skill"
done < <(awk '
  $0 == "files:" { in_files = 1; next }
  in_files && $1 == "-" && $2 == "path:" {
    path = $3
    gsub(/^"|"$/, "", path)
    print path
  }
' "$project_root/skills.lock")

for excluded_path in \
  docs/software-factory-plan.md \
  docs/software-factory-progress.md \
  docs/software-factory-review-remediation-plan.md \
  .DS_Store
do
  if grep -Fqx "software-factory/$excluded_path" "$archive_entries"; then
    fail "portable archive contains development-only file: $excluded_path"
  fi
done

printf 'PASS: portable archive verified from %s\n' "$source_commit"
