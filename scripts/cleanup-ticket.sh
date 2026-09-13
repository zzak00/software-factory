#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_VERSION='0.2.0'

apply=false
delete_remote=false
source_directory=$PWD
pull_request=''
repository=''

usage() {
  cat <<'EOF'
Usage: cleanup-ticket.sh [options]

Safely remove the local worktree and branch for one merged GitHub pull request.
Remote branch deletion requires an additional explicit flag.

Options:
  --source PATH       Primary local repository checkout (default: cwd)
  --pr NUMBER         Merged pull-request number
  --repo OWNER/NAME   GitHub repository (default: derive from origin)
  --delete-remote     Include the remote feature branch in the cleanup plan
  --apply             Perform approved deletions; otherwise inspect only
  -h, --help          Show this help
  --version           Show the script version

Inspect mode exits 2 when cleanup is needed, 0 when the requested cleanup is
already complete, and 1 on an unsafe or ambiguous state. Apply mode never uses
unconditional force and does not modify issues, Projects, the default branch,
or pull requests. Remote deletion uses an expected-commit lease.
EOF
}

fail() {
  printf 'cleanup-ticket: %s\n' "$*" >&2
  exit 1
}

info() {
  printf 'cleanup-ticket: %s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

repository_from_origin() {
  local origin_url=$1
  local candidate=''

  case $origin_url in
    https://github.com/*)
      candidate=${origin_url#https://github.com/}
      ;;
    git@github.com:*)
      candidate=${origin_url#git@github.com:}
      ;;
    ssh://git@github.com/*)
      candidate=${origin_url#ssh://git@github.com/}
      ;;
    *)
      return 1
      ;;
  esac

  candidate=${candidate%.git}
  [[ "$candidate" == */* ]] || return 1
  printf '%s\n' "$candidate"
}

remote_branch_oid() {
  local branch_name=$1
  local matches
  local match_count

  matches=$(git -C "$source_directory" ls-remote --heads "$origin_push_url" \
    "refs/heads/$branch_name") || fail "could not inspect origin push destination/$branch_name"
  match_count=$(awk 'NF { count += 1 } END { print count + 0 }' <<<"$matches")
  [[ "$match_count" -le 1 ]] || fail "origin returned multiple refs for branch: $branch_name"
  awk 'NF { print $1 }' <<<"$matches"
}

worktree_for_branch() {
  local branch_name=$1

  git -C "$source_directory" worktree list --porcelain |
    awk -v target_ref="refs/heads/$branch_name" '
      /^worktree / {
        path = $0
        sub(/^worktree /, "", path)
      }
      /^branch / && $2 == target_ref { print path }
    '
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --source)
      [[ $# -ge 2 ]] || fail '--source requires a value'
      source_directory=$2
      shift 2
      ;;
    --pr)
      [[ $# -ge 2 ]] || fail '--pr requires a value'
      pull_request=$2
      shift 2
      ;;
    --repo)
      [[ $# -ge 2 ]] || fail '--repo requires a value'
      repository=$2
      shift 2
      ;;
    --delete-remote)
      delete_remote=true
      shift
      ;;
    --apply)
      apply=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --version)
      printf 'cleanup-ticket %s\n' "$SCRIPT_VERSION"
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

[[ "$pull_request" =~ ^[1-9][0-9]*$ ]] || fail '--pr must be a positive integer'
[[ -d "$source_directory" ]] || fail "source directory not found: $source_directory"

require_command awk
require_command gh
require_command git
require_command jq

source_directory=$(CDPATH='' cd -- "$source_directory" && pwd -P)
readonly source_directory

repository_root=$(git -C "$source_directory" rev-parse --show-toplevel 2>/dev/null) ||
  fail 'source is not a Git repository'
repository_root=$(CDPATH='' cd -- "$repository_root" && pwd -P)
[[ "$repository_root" == "$source_directory" ]] ||
  fail '--source must identify the primary repository root'

origin_url=$(git -C "$source_directory" config --get remote.origin.url 2>/dev/null) ||
  fail 'origin is not configured'
origin_repository=$(repository_from_origin "$origin_url" 2>/dev/null || true)

if [[ -z "$repository" ]]; then
  [[ -n "$origin_repository" ]] ||
    fail 'could not derive a GitHub repository from origin; pass --repo'
  repository=$origin_repository
elif [[ -n "$origin_repository" && "$origin_repository" != "$repository" ]]; then
  fail "origin identifies $origin_repository, not $repository"
fi

[[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
  fail 'repository must use OWNER/NAME format'

origin_push_urls=()
while IFS= read -r configured_push_url; do
  [[ -n "$configured_push_url" ]] &&
    origin_push_urls[${#origin_push_urls[@]}]=$configured_push_url
done < <(git -C "$source_directory" config --get-all remote.origin.pushurl 2>/dev/null || true)

if [[ "${#origin_push_urls[@]}" -eq 0 ]]; then
  while IFS= read -r configured_push_url; do
    [[ -n "$configured_push_url" ]] &&
      origin_push_urls[${#origin_push_urls[@]}]=$configured_push_url
  done < <(git -C "$source_directory" config --get-all remote.origin.url 2>/dev/null || true)
fi

[[ "${#origin_push_urls[@]}" -eq 1 ]] ||
  fail "origin must have exactly one push destination; found ${#origin_push_urls[@]}"
origin_push_url=${origin_push_urls[0]}
origin_push_repository=$(repository_from_origin "$origin_push_url" 2>/dev/null || true)
[[ -n "$origin_push_repository" ]] ||
  fail "origin push destination is not a supported GitHub URL: $origin_push_url"
[[ "$origin_push_repository" == "$repository" ]] ||
  fail "origin push destination identifies $origin_push_repository, not $repository"

readonly apply delete_remote pull_request repository origin_push_url

gh auth status >/dev/null 2>&1 || fail 'GitHub CLI authentication is invalid'

info "version=$SCRIPT_VERSION"
info "mode=$(if $apply; then printf apply; else printf inspect; fi)"
info "source=$source_directory"
info "repository=$repository"
info "pull_request=$pull_request"
info "delete_remote=$delete_remote"

repository_json=$(gh repo view "$repository" --json defaultBranchRef) ||
  fail 'could not inspect the GitHub repository'
default_branch=$(jq -er '.defaultBranchRef.name' <<<"$repository_json") ||
  fail 'GitHub repository has no default branch'

pr_json=$(gh pr view "$pull_request" \
  --repo "$repository" \
  --json state,isDraft,baseRefName,headRefName,headRefOid,mergeCommit,closingIssuesReferences,url) ||
  fail "could not inspect pull request $pull_request"

pr_state=$(jq -er '.state' <<<"$pr_json") || fail 'pull request has no state'
[[ "$pr_state" == 'MERGED' ]] || fail "pull request is not merged: $pr_state"

base_branch=$(jq -er '.baseRefName' <<<"$pr_json") || fail 'pull request has no base branch'
head_branch=$(jq -er '.headRefName' <<<"$pr_json") || fail 'pull request has no head branch'
head_oid=$(jq -er '.headRefOid' <<<"$pr_json") || fail 'pull request has no head commit'
merge_oid=$(jq -er '.mergeCommit.oid' <<<"$pr_json") || fail 'pull request has no merge commit'
pr_url=$(jq -er '.url' <<<"$pr_json") || fail 'pull request has no URL'

[[ "$head_oid" =~ ^[0-9a-f]{40}$ ]] || fail 'pull request returned an invalid head commit'
[[ "$merge_oid" =~ ^[0-9a-f]{40}$ ]] || fail 'pull request returned an invalid merge commit'
git check-ref-format --branch "$base_branch" >/dev/null 2>&1 ||
  fail "pull request returned an invalid base branch: $base_branch"
git check-ref-format --branch "$head_branch" >/dev/null 2>&1 ||
  fail "pull request returned an invalid head branch: $head_branch"
[[ "$base_branch" == "$default_branch" ]] ||
  fail "pull request base $base_branch is not the default branch $default_branch"
[[ "$head_branch" != "$default_branch" ]] || fail 'refusing to clean the default branch'

closing_issue_urls=$(jq -er '
  .closingIssuesReferences
  | if type == "array"
      and length > 0
      and all(.[]; (.url | type) == "string" and (.url | length) > 0)
    then .[].url
    else error("invalid closing issue references")
    end
' <<<"$pr_json") || fail 'pull request has no valid closing issue references'

while IFS= read -r closing_issue_url; do
  closing_issue_json=$(gh issue view "$closing_issue_url" --json state,url) ||
    fail "could not inspect linked issue: $closing_issue_url"
  closing_issue_state=$(jq -er '.state' <<<"$closing_issue_json") ||
    fail "linked issue has no state: $closing_issue_url"
  [[ "$closing_issue_state" == 'CLOSED' ]] ||
    fail "linked issue is not closed: $closing_issue_url"
done <<<"$closing_issue_urls"

current_branch=$(git -C "$source_directory" symbolic-ref --quiet --short HEAD) ||
  fail 'primary checkout is detached'
[[ "$current_branch" == "$default_branch" ]] ||
  fail "primary checkout is on $current_branch, expected $default_branch"
[[ -z "$(git -C "$source_directory" status --porcelain)" ]] ||
  fail 'primary checkout is not clean'

base_oid=$(git -C "$source_directory" rev-parse "refs/heads/$default_branch") ||
  fail "local default branch not found: $default_branch"
remote_base_oid=$(remote_branch_oid "$default_branch")
[[ -n "$remote_base_oid" ]] || fail "remote default branch not found: $default_branch"
[[ "$base_oid" == "$remote_base_oid" ]] ||
  fail "local $default_branch is not synchronized with origin/$default_branch"
git -C "$source_directory" merge-base --is-ancestor "$merge_oid" "$base_oid" ||
  fail "local $default_branch does not contain pull request merge commit $merge_oid"

worktree_paths=$(worktree_for_branch "$head_branch")
worktree_count=$(awk 'NF { count += 1 } END { print count + 0 }' <<<"$worktree_paths")
[[ "$worktree_count" -le 1 ]] || fail "multiple worktrees use branch: $head_branch"
worktree_path=''
if [[ "$worktree_count" -eq 1 ]]; then
  worktree_path=$worktree_paths
fi

local_branch_exists=false
if git -C "$source_directory" show-ref --verify --quiet "refs/heads/$head_branch"; then
  local_branch_exists=true
  local_head_oid=$(git -C "$source_directory" rev-parse "refs/heads/$head_branch")
  [[ "$local_head_oid" == "$head_oid" ]] ||
    fail "local $head_branch no longer matches the reviewed pull-request head"
fi

if [[ -n "$worktree_path" ]]; then
  $local_branch_exists || fail "worktree branch is missing: $head_branch"
  [[ -z "$(git -C "$worktree_path" status --porcelain)" ]] ||
    fail "worktree is not clean: $worktree_path"
fi

remote_head_oid=$(remote_branch_oid "$head_branch")
if [[ -n "$remote_head_oid" && "$remote_head_oid" != "$head_oid" ]]; then
  fail "origin/$head_branch no longer matches the reviewed pull-request head"
fi

info "pull_request_url=$pr_url"
info "default_branch=$default_branch@$base_oid"
info "feature_branch=$head_branch@$head_oid"
info "merge_commit=$merge_oid"

local_cleanup_needed=false
if [[ -n "$worktree_path" || "$local_branch_exists" == true ]]; then
  local_cleanup_needed=true
fi

remote_cleanup_needed=false
if $delete_remote && [[ -n "$remote_head_oid" ]]; then
  remote_cleanup_needed=true
fi

if ! $apply; then
  if [[ -n "$worktree_path" ]]; then
    info "PLAN remove clean worktree: $worktree_path"
  fi
  if $local_branch_exists; then
    info "PLAN delete local branch at reviewed head: $head_branch"
  fi
  if $remote_cleanup_needed; then
    info "PLAN delete remote branch at reviewed head: origin/$head_branch"
  elif [[ -n "$remote_head_oid" ]]; then
    info "remote branch preserved; pass --delete-remote to include it"
  fi

  if $local_cleanup_needed || $remote_cleanup_needed; then
    exit 2
  fi

  info 'requested ticket cleanup already complete'
  exit 0
fi

if [[ -n "$worktree_path" ]]; then
  git -C "$source_directory" worktree remove "$worktree_path"
  info "worktree removed: $worktree_path"
fi

if git -C "$source_directory" show-ref --verify --quiet "refs/heads/$head_branch"; then
  current_head_oid=$(git -C "$source_directory" rev-parse "refs/heads/$head_branch")
  [[ "$current_head_oid" == "$head_oid" ]] ||
    fail "local $head_branch changed during cleanup"
  git -C "$source_directory" update-ref -d "refs/heads/$head_branch" "$head_oid"
  info "local branch deleted: $head_branch"
fi

if $delete_remote; then
  current_remote_head_oid=$(remote_branch_oid "$head_branch")
  if [[ -n "$current_remote_head_oid" ]]; then
    [[ "$current_remote_head_oid" == "$head_oid" ]] ||
      fail "origin/$head_branch changed during cleanup"
    git -C "$source_directory" push "$origin_push_url" \
      "--force-with-lease=refs/heads/$head_branch:$head_oid" \
      --delete "refs/heads/$head_branch" ||
      fail "origin/$head_branch changed before conditional deletion"
    info "remote branch deleted: origin/$head_branch"
  fi
fi

[[ -z "$(worktree_for_branch "$head_branch")" ]] ||
  fail "worktree still exists after cleanup: $head_branch"
if git -C "$source_directory" show-ref --verify --quiet "refs/heads/$head_branch"; then
  fail "local branch still exists after cleanup: $head_branch"
fi
if $delete_remote && [[ -n "$(remote_branch_oid "$head_branch")" ]]; then
  fail "remote branch still exists after cleanup: $head_branch"
fi

info 'requested ticket cleanup complete'
