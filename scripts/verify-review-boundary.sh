#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_VERSION='0.1.0'

source_directory=''
fixed_point=''
reviewed_head=''
comparison_ref=''

usage() {
  cat <<'EOF'
Usage: verify-review-boundary.sh [options]

Verify that a symbolic Git comparison used by human review covers the same
original fixed point, reviewed HEAD, and changed-file set as automated review.
The command is read-only.

Options:
  --source PATH          Exact ticket worktree root
  --fixed-point COMMIT   Original review fixed point, as a full commit ID
  --head COMMIT          Reviewed HEAD, as a full commit ID
  --comparison-ref REF   Full remote-tracking ref displayed by the review tool
  -h, --help             Show this help
  --version              Show the script version
EOF
}

fail() {
  printf 'verify-review-boundary: %s\n' "$*" >&2
  exit 1
}

info() {
  printf 'verify-review-boundary: %s\n' "$*"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --source)
      [[ $# -ge 2 ]] || fail '--source requires a value'
      source_directory=$2
      shift 2
      ;;
    --fixed-point)
      [[ $# -ge 2 ]] || fail '--fixed-point requires a value'
      fixed_point=$2
      shift 2
      ;;
    --head)
      [[ $# -ge 2 ]] || fail '--head requires a value'
      reviewed_head=$2
      shift 2
      ;;
    --comparison-ref)
      [[ $# -ge 2 ]] || fail '--comparison-ref requires a value'
      comparison_ref=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --version)
      printf 'verify-review-boundary %s\n' "$SCRIPT_VERSION"
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

[[ -n "$source_directory" ]] || fail '--source is required'
[[ -d "$source_directory" ]] || fail "source directory not found: $source_directory"
[[ "$fixed_point" =~ ^[0-9a-f]{40}$ ]] || fail '--fixed-point must be a full lowercase commit ID'
[[ "$reviewed_head" =~ ^[0-9a-f]{40}$ ]] || fail '--head must be a full lowercase commit ID'
[[ "$comparison_ref" == refs/remotes/origin/* ]] ||
  fail '--comparison-ref must be a full origin remote-tracking ref'

command -v git >/dev/null 2>&1 || fail 'required command not found: git'
if command -v sha256sum >/dev/null 2>&1; then
  hash_stream() { sha256sum | awk '{ print $1 }'; }
elif command -v shasum >/dev/null 2>&1; then
  hash_stream() { shasum -a 256 | awk '{ print $1 }'; }
else
  fail 'required command not found: sha256sum or shasum'
fi

source_directory=$(CDPATH='' cd -- "$source_directory" && pwd -P)
repository_root=$(git -C "$source_directory" rev-parse --show-toplevel 2>/dev/null) ||
  fail 'source is not a Git repository'
repository_root=$(CDPATH='' cd -- "$repository_root" && pwd -P)
[[ "$repository_root" == "$source_directory" ]] ||
  fail "source must be the Git worktree root: source=$source_directory root=$repository_root"
git check-ref-format "$comparison_ref" >/dev/null 2>&1 ||
  fail "invalid comparison ref: $comparison_ref"
[[ -z "$(git -C "$source_directory" status --porcelain --untracked-files=all)" ]] ||
  fail 'ticket worktree is not clean'

fixed_oid=$(git -C "$source_directory" rev-parse --verify "$fixed_point^{commit}" 2>/dev/null) ||
  fail "fixed point does not resolve: $fixed_point"
head_oid=$(git -C "$source_directory" rev-parse --verify "$reviewed_head^{commit}" 2>/dev/null) ||
  fail "reviewed head does not resolve: $reviewed_head"
current_head=$(git -C "$source_directory" rev-parse HEAD)
[[ "$current_head" == "$head_oid" ]] ||
  fail "worktree HEAD is $current_head, expected reviewed head $head_oid"
git -C "$source_directory" merge-base --is-ancestor "$fixed_oid" "$head_oid" ||
  fail 'original fixed point is not an ancestor of the reviewed head'

comparison_oid=$(git -C "$source_directory" rev-parse --verify "$comparison_ref^{commit}" 2>/dev/null) ||
  fail "comparison ref does not resolve: $comparison_ref"
comparison_merge_bases=$(git -C "$source_directory" merge-base --all "$head_oid" "$comparison_oid") ||
  fail 'could not resolve the human-review comparison merge base'
comparison_merge_base_count=$(awk 'NF { count += 1 } END { print count + 0 }' <<<"$comparison_merge_bases")
comparison_merge_base=$(awk 'NF { print; exit }' <<<"$comparison_merge_bases")

required_files_hash=$(git -C "$source_directory" diff --name-only -z "$fixed_oid...$head_oid" | hash_stream)
comparison_files_hash=$(git -C "$source_directory" diff --name-only -z "$comparison_ref...$head_oid" | hash_stream)

info "version=$SCRIPT_VERSION"
info "source=$source_directory"
info "required_fixed_point=$fixed_oid"
info "fixed_point=$fixed_oid"
info "reviewed_head=$head_oid"
info "comparison_ref=$comparison_ref"
info "comparison_base_oid=$comparison_oid"
info "comparison_merge_base=$comparison_merge_base"
info "required_changed_files_sha256=$required_files_hash"
info "comparison_changed_files_sha256=$comparison_files_hash"
while IFS= read -r changed_file; do
  [[ -n "$changed_file" ]] && info "changed_file=$changed_file"
done < <(git -C "$source_directory" diff --name-only "$fixed_oid...$head_oid")

if [[ "$comparison_merge_base_count" -ne 1 || "$comparison_merge_base" != "$fixed_oid" ||
  "$comparison_files_hash" != "$required_files_hash" ]]; then
  fail 'human review boundary is incomplete; the displayed comparison does not match automated review'
fi

info 'human and automated review boundaries match'
