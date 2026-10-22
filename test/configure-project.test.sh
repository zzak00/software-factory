#!/usr/bin/env bash

# Exercise the configurator at its command-line boundary without a GitHub
# account. A fake gh executable records every call and returns controlled API
# responses, allowing the assertions to inspect both output and mutations.
set -eu

# Locate the real script, then give every scenario an isolated temporary area.
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
CONFIGURE="$ROOT/scripts/configure-project.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/software-factory-project-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
FAKE_BIN="$TEST_ROOT/bin"
LOG="$TEST_ROOT/gh.log"
mkdir -p "$FAKE_BIN"

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

# This here-document becomes the fake gh binary at the front of PATH. The
# outer shell does not expand it; environment variables select a mode each
# time the fake binary runs.
cat > "$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
# Record the command before responding so tests can detect unintended writes.
printf '%s\n' "$*" >> "$GH_TEST_LOG"

# Strip the API-version header from ordinary REST calls. The configurator
# adds that header and a pagination flag, but neither changes which fake
# endpoint should answer. The fixture stands in for a complete API response.
if [ "$1" = api ] && [ "${2:-}" = -H ]; then
  shift
  shift 2
  set -- api "$@"
fi
if [ "$1" = api ] && [ "${2:-}" = --paginate ]; then
  shift 2
  set -- api "$@"
fi

case "$1 $2" in
  "auth status") exit 0 ;;
  # The default repository already exists. repo-error represents a network
  # failure, which must not be confused with a genuinely missing repository.
  "repo view")
    if [ "${GH_TEST_MODE:-ok}" = repo-error ]; then
      printf 'error: could not connect to github.com\n' >&2
      exit 1
    fi
    printf '%s\n' '{"visibility":"PRIVATE","defaultBranchRef":{"name":"main"}}'
    ;;
  "api users/test") printf '{"id":42,"type":"%s"}\n' "${GH_TEST_OWNER_TYPE:-User}" ;;
  # In no-ci mode, a successful Contents API write makes the workflow appear on
  # the next read, modeling GitHub state changing during one apply operation.
  "api repos/test/project/actions/workflows?per_page=100")
    if [ "${GH_TEST_MODE:-ok}" = no-ci ] && ! grep -q 'contents/.github/workflows/ci.yml' "$GH_TEST_LOG"; then
      printf '%s\n' '{"total_count":0,"workflows":[]}'
    else
      printf '%s\n' '{"total_count":1,"workflows":[{"path":".github/workflows/project.yml"}]}'
    fi
    ;;
  "api repos/test/project/commits/main/check-runs?per_page=100")
    # These responses distinguish one published check, multiple checks, and no
    # checks yet. The explicit-build case models a caller-selected check name.
    case "${GH_TEST_MODE:-ok}" in
      ambiguous-ci) printf '%s\n' '{"total_count":2,"check_runs":[{"name":"lint"},{"name":"test"}]}' ;;
      no-check-runs) printf '%s\n' '{"total_count":0,"check_runs":[]}' ;;
      explicit-build) printf '%s\n' '{"total_count":1,"check_runs":[{"name":"build"}]}' ;;
      *) printf '%s\n' '{"total_count":1,"check_runs":[{"name":"verify"}]}' ;;
    esac
    ;;
  "project list")
    # The base Development board is deliberately present in new-project mode.
    # Only the suffixed factory board may be created or reused.
    case "${GH_TEST_MODE:-ok}" in
      limit) jq -n '{projects: [range(0; 1000) | {title: ("Project " + tostring), number: .}]}' ;;
      new-project) printf '%s\n' '{"projects":[{"title":"Development","number":3}]}' ;;
      *) printf '%s\n' '{"projects":[{"title":"Development","number":3},{"title":"Development - Software Factory","number":7}]}' ;;
    esac
    ;;
  "project create") printf '%s\n' '8' ;;
  "project edit") exit 0 ;;
  # The marker in shortDescription is the ownership signal for safe reuse.
  "project view")
    if [ "${GH_TEST_MODE:-ok}" = unmarked ]; then
      printf '%s\n' '{"id":"project-id","title":"Development - Software Factory","closed":false,"public":false,"shortDescription":"Unrelated board"}'
    else
      printf '%s\n' '{"id":"project-id","title":"Development - Software Factory","closed":false,"public":false,"shortDescription":"Managed by Software Factory"}'
    fi
    ;;
  "project field-list")
    # Modes cover the default Status options on a new board, an existing field
    # beyond the CLI's old default page, and a saturated lookup that must fail.
    case "${GH_TEST_MODE:-ok}" in
      field-limit) jq -n '{fields: [range(0; 1000) | {name: ("Field " + tostring)}]}' ;;
      many-fields) jq -n '{fields: ([{id:"status",name:"Status",options:[{name:"Inbox"},{name:"Ready"},{name:"In Progress"},{name:"In Review"},{name:"Done"}]}] + [range(0; 29) | {name:("Field " + tostring)}] + [{id:"risk",name:"Risk",options:[{name:"Standard"},{name:"Elevated"}]}])}' ;;
      default-status) printf '%s\n' '{"fields":[{"id":"status","name":"Status","options":[{"name":"Todo"},{"name":"In Progress"},{"name":"Done"}]}]}' ;;
      new-project)
        if ! grep -q 'graphql --input' "$GH_TEST_LOG"; then
          printf '%s\n' '{"fields":[{"id":"status","name":"Status","options":[{"name":"Todo"},{"name":"In Progress"},{"name":"Done"}]}]}'
        elif ! grep -q 'project field-create' "$GH_TEST_LOG"; then
          printf '%s\n' '{"fields":[{"id":"status","name":"Status","options":[{"name":"Inbox"},{"name":"Ready"},{"name":"In Progress"},{"name":"In Review"},{"name":"Done"}]}]}'
        else
          printf '%s\n' '{"fields":[{"id":"status","name":"Status","options":[{"name":"Inbox"},{"name":"Ready"},{"name":"In Progress"},{"name":"In Review"},{"name":"Done"}]},{"id":"risk","name":"Risk","options":[{"name":"Standard"},{"name":"Elevated"}]}]}'
        fi
        ;;
      *) printf '%s\n' '{"fields":[{"id":"status","name":"Status","options":[{"name":"Inbox"},{"name":"Ready"},{"name":"In Progress"},{"name":"In Review"},{"name":"Done"}]},{"id":"risk","name":"Risk","options":[{"name":"Standard"},{"name":"Elevated"}]}]}' ;;
    esac
    ;;
  "project link"|"project field-create") exit 0 ;;
  # The query response supplies a linked repository, Status database ID, and
  # a grouped Board. no-board withholds the view until POST creates it.
  "api graphql")
    if [ "${GH_TEST_MODE:-ok}" = no-board ] && ! grep -Eq 'POST (users|orgs)/test/projectsV2/7/views' "$GH_TEST_LOG"; then
      printf '%s\n' '{"data":{"node":{"repositories":{"pageInfo":{"hasNextPage":false},"nodes":[{"nameWithOwner":"test/project"}]},"fields":{"pageInfo":{"hasNextPage":false},"nodes":[{"databaseId":5,"name":"Status"}]},"views":{"pageInfo":{"hasNextPage":false},"nodes":[]}}}}'
    else
      printf '%s\n' '{"data":{"node":{"repositories":{"pageInfo":{"hasNextPage":false},"nodes":[{"nameWithOwner":"test/project"}]},"fields":{"pageInfo":{"hasNextPage":false},"nodes":[{"databaseId":5,"name":"Status"}]},"views":{"pageInfo":{"hasNextPage":false},"nodes":[{"id":"view","name":"Board","layout":"BOARD_LAYOUT","verticalGroupByFields":{"nodes":[{"name":"Status"}]}}]}}}}'
    fi
    ;;
  "api repos/test/project/rulesets?per_page=100")
    # foreign-ci starts without the factory ruleset; after POST it appears.
    if [ "${GH_TEST_MODE:-ok}" = foreign-ci ] && ! grep -q 'POST repos/test/project/rulesets' "$GH_TEST_LOG"; then
      printf '%s\n' '[]'
    else
      printf '%s\n' '[{"id":9,"name":"software-factory-development"}]'
    fi
    ;;
  "api repos/test/project/rulesets/9")
    # excluded-main includes the default branch symbolically but explicitly
    # excludes its concrete ref, so protection must not be trusted.
    excluded='[]'
    if [ "${GH_TEST_MODE:-ok}" = excluded-main ] || [ "${GH_TEST_RULESET_EXCLUDED:-0}" = 1 ]; then excluded='["refs/heads/main"]'; fi
    check=verify
    [ "${GH_TEST_MODE:-ok}" = explicit-build ] && check=build
    jq -n --argjson exclude "$excluded" --arg check "$check" '{target:"branch",enforcement:"active",conditions:{ref_name:{include:["~DEFAULT_BRANCH"],exclude:$exclude}},bypass_actors:[],rules:[{type:"deletion"},{type:"non_fast_forward"},{type:"pull_request",parameters:{dismiss_stale_reviews_on_push:true,require_code_owner_review:false,require_last_push_approval:false,required_approving_review_count:0,required_review_thread_resolution:true}},{type:"required_status_checks",parameters:{strict_required_status_checks_policy:true,do_not_enforce_on_create:true,required_status_checks:[{context:$check}]}}]}'
    ;;
  "api --method")
    # Accept only remote writes that this suite permits. Optionally capture
    # the new CI payload so its decoded YAML can be inspected below.
    case "$*" in
      *"PUT repos/test/project/contents/.github/workflows/ci.yml"*)
        if [ -n "${GH_TEST_CI_BODY:-}" ]; then cat > "$GH_TEST_CI_BODY"; fi
        exit 0 ;;
      *"POST users/test/projectsV2/7/views"*|*"POST orgs/test/projectsV2/7/views"*|*"POST repos/test/project/rulesets"*) exit 0 ;;
      *) printf 'unexpected mutating API call: %s\n' "$*" >&2; exit 90 ;;
    esac
    ;;
  *) printf 'unexpected gh call: %s\n' "$*" >&2; exit 90 ;;
esac
EOF
chmod +x "$FAKE_BIN/gh"

# Invoke the actual script, injecting fake gh only for this command.
run_configure() {
  PATH="$FAKE_BIN:$PATH" GH_TEST_LOG="$LOG" "$CONFIGURE" --owner test --repo project --project-title Development "$@"
}

# A plain invocation is a true dry run: no gh command should execute.
: > "$LOG"
run_configure >/dev/null
[ ! -s "$LOG" ] || fail "dry run called GitHub"

: > "$LOG"
# A compatible factory setup is idempotent and does not update fields or
# create resources again.
run_configure --apply >/dev/null
if grep -Eq 'project create|project edit|field-create|graphql --input|--method POST' "$LOG"; then
  fail "idempotent apply attempted a creation or field update"
fi

: > "$LOG"
# The first workflow run may not exist yet. The configured ruleset still lets
# an immediate repeat recover the intended check without changing resources.
GH_TEST_MODE=no-check-runs run_configure --apply >/dev/null
if grep -Eq 'project create|project edit|field-create|graphql --input|--method POST' "$LOG"; then
  fail "rerun before the first CI result attempted a mutation"
fi

: > "$LOG"
# Creating a second Project must leave the original Development board alone.
GH_TEST_MODE=new-project run_configure --apply >/dev/null
grep -q 'project create --owner test --title Development - Software Factory' "$LOG" || fail "factory Project was not created separately"
grep -q 'project edit 8 --owner test --description Managed by Software Factory' "$LOG" || fail "new Project was not marked"
grep -q 'graphql --input' "$LOG" || fail "new Project Status was not configured"
if grep -q 'project edit 3' "$LOG"; then fail "original Project was modified"; fi

: > "$LOG"
# Decode the GitHub Contents payload to check the user-visible CI behavior.
CI_BODY="$TEST_ROOT/ci-body.json"
GH_TEST_MODE=no-ci GH_TEST_CI_BODY="$CI_BODY" run_configure --apply >/dev/null
grep -q 'PUT repos/test/project/contents/.github/workflows/ci.yml' "$LOG" || fail "missing Python CI was not created"
ci_yaml=$(jq -r '.content' "$CI_BODY" | base64 --decode)
printf '%s' "$ci_yaml" | grep -q 'ruff format --check' || fail "Python CI has no formatting check"
printf '%s' "$ci_yaml" | grep -q 'check .' || fail "Python CI has no lint check"
printf '%s' "$ci_yaml" | grep -q 'branches: \["main"\]' || fail "Python CI did not pin push to the default branch"

: > "$LOG"
# GitHub uses different view endpoints for user and organization owners.
GH_TEST_MODE=no-board run_configure --apply >/dev/null
grep -q 'POST users/test/projectsV2/7/views' "$LOG" || fail "user-owned Status board used the wrong endpoint"

: > "$LOG"
GH_TEST_MODE=no-board GH_TEST_OWNER_TYPE=Organization run_configure --apply >/dev/null
grep -q 'POST orgs/test/projectsV2/7/views' "$LOG" || fail "organization-owned Status board used the wrong endpoint"

expect_failure_without_mutation() {
  # Every conflict case must fail before a Project or repository write occurs.
  mode=$1
  shift
  : > "$LOG"
  if GH_TEST_MODE="$mode" run_configure --apply "$@" >/dev/null 2>&1; then
    fail "$mode was accepted"
  fi
  if grep -Eq 'project create|project edit|project link|field-create|graphql --input|--method POST|--method PUT' "$LOG"; then
    fail "$mode caused a mutation"
  fi
}

# Reject incompatible fields, ownership, incomplete scans, excluded default
# branch protection, ambiguous checks, and repository inspection errors.
expect_failure_without_mutation default-status
expect_failure_without_mutation unmarked
expect_failure_without_mutation field-limit
expect_failure_without_mutation excluded-main
expect_failure_without_mutation ambiguous-ci
expect_failure_without_mutation no-ci --required-check build
expect_failure_without_mutation limit
expect_failure_without_mutation repo-error

: > "$LOG"
# Verify ordering: ruleset conflict is detected before creating a Project.
if GH_TEST_RULESET_EXCLUDED=1 GH_TEST_MODE=new-project run_configure --apply >/dev/null 2>&1; then
  fail "excluded ruleset was accepted before creating a factory Project"
fi
if grep -q 'project create' "$LOG"; then fail "ruleset conflict created a factory Project"; fi

: > "$LOG"
# An explicit name may be used by PR-only CI, so default-branch inference is
# intentionally skipped when the caller supplies --required-check.
GH_TEST_MODE=explicit-build run_configure --apply --required-check build >/dev/null
if grep -q 'commits/main/check-runs' "$LOG"; then fail "explicit pull-request-only check triggered branch inference"; fi

: > "$LOG"
# Risk beyond thirty fields must be found, never created a second time.
GH_TEST_MODE=many-fields run_configure --apply >/dev/null
if grep -q 'project field-create' "$LOG"; then fail "existing Risk field beyond default lookup limit was recreated"; fi
grep -q 'project field-list 7 --owner test --limit 1000' "$LOG" || fail "Project fields were fetched with the default limit"

: > "$LOG"
# Existing CI with no factory ruleset gets protection without replacing CI.
GH_TEST_MODE=foreign-ci run_configure --apply >/dev/null
grep -q 'POST repos/test/project/rulesets' "$LOG" || fail "missing ruleset was not created"

printf 'ok - project configuration and conflict safety\n'
