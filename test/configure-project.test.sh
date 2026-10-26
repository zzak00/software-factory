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
  # GH_TEST_REPO_VISIBILITY sets the visibility of that repository.
  # In new-repo mode the repository appears after creation on the owner's
  # default branch name, master, until the configurator renames it.
  "repo view")
    if [ "${GH_TEST_MODE:-ok}" = repo-error ]; then
      printf 'error: could not connect to github.com\n' >&2
      exit 1
    fi
    branch=main
    if [ "${GH_TEST_MODE:-ok}" = new-repo ]; then
      # GH_TEST_REPO_EXISTS models a run interrupted after creating the
      # repository and before renaming its branch.
      if [ "${GH_TEST_REPO_EXISTS:-0}" != 1 ] && ! grep -q 'repo create' "$GH_TEST_LOG"; then
        printf 'GraphQL: Could not resolve to a Repository with the name test/project.\n' >&2
        exit 1
      fi
      grep -q 'POST repos/test/project/branches/master/rename' "$GH_TEST_LOG" || branch=master
      # GH_TEST_RENAME_LAG makes the first read after the rename still report
      # master, as GitHub did in a live run.
      if [ "${GH_TEST_RENAME_LAG:-0}" = 1 ] && [ "$(awk '/branches\/master\/rename/ { seen = 1; next } seen && /^repo view/ { n++ } END { print n + 0 }' "$GH_TEST_LOG")" -le 1 ] && grep -q 'branches/master/rename' "$GH_TEST_LOG"; then branch=master; fi
    fi
    jq -n --arg visibility "${GH_TEST_REPO_VISIBILITY:-PRIVATE}" --arg branch "$branch" '{visibility:$visibility,defaultBranchRef:{name:$branch}}'
    ;;
  "repo create") exit 0 ;;
  # An untouched repository has one branch and one commit; ok mode has more.
  "api repos/test/project/branches?per_page=2")
    if [ "${GH_TEST_MODE:-ok}" = new-repo ]; then printf '%s\n' '[{"name":"master"}]'; else printf '%s\n' '[{"name":"main"},{"name":"feature"}]'; fi
    ;;
  "api repos/test/project/commits?sha=master&per_page=2")
    if [ "${GH_TEST_MODE:-ok}" = new-repo ]; then printf '%s\n' '[{"sha":"a"}]'; else printf '%s\n' '[{"sha":"a"},{"sha":"b"}]'; fi
    ;;
  "api users/test") printf '{"id":42,"type":"%s"}\n' "${GH_TEST_OWNER_TYPE:-User}" ;;
  # In no-ci mode, a successful Contents API write makes the workflow appear on
  # the next read, modeling GitHub state changing during one apply operation.
  "api repos/test/project/actions/workflows?per_page=100")
    if { [ "${GH_TEST_MODE:-ok}" = no-ci ] || [ "${GH_TEST_MODE:-ok}" = new-repo ]; } && ! grep -q 'contents/.github/workflows/ci.yml' "$GH_TEST_LOG"; then
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
      new-project|new-repo) printf '%s\n' '{"projects":[{"title":"Development","number":3}]}' ;;
      *) printf '%s\n' '{"projects":[{"title":"Development","number":3},{"title":"Development - Software Factory","number":7}]}' ;;
    esac
    ;;
  "project create") printf '%s\n' '8' ;;
  "project edit") exit 0 ;;
  # The marker in shortDescription is the ownership signal for safe reuse.
  # GH_TEST_PROJECT_ITEMS sets the card count reported for the Project.
  "project view")
    marker="Managed by Software Factory"
    [ "${GH_TEST_MODE:-ok}" = unmarked ] && marker="Unrelated board"
    jq -n --arg marker "$marker" --argjson items "${GH_TEST_PROJECT_ITEMS:-0}" '{id:"project-id",title:"Development - Software Factory",closed:false,public:false,shortDescription:$marker,items:{totalCount:$items}}'
    ;;
  "project field-list")
    # Fields are derived from the mode and the writes logged so far: a new or
    # interrupted Project starts with GitHub's default Status and gains Risk
    # and Track only when they are created. many-fields hides Risk and Track
    # beyond the CLI's old default page; track-conflict has foreign options.
    mode=${GH_TEST_MODE:-ok}
    if [ "$mode" = field-limit ]; then
      jq -n '{fields: [range(0; 1000) | {name: ("Field " + tostring)}]}'
      exit 0
    fi
    status='["Inbox","Ready","In Progress","In Review","Done"]'
    risk=1
    track=1
    padding=0
    track_options='["Fast","Standard","Product"]'
    case "$mode" in
      new-project|new-repo|default-status)
        grep -q 'graphql --input' "$GH_TEST_LOG" || status='["Todo","In Progress","Done"]'
        grep -q -- '--name Risk' "$GH_TEST_LOG" || risk=0
        grep -q -- '--name Track' "$GH_TEST_LOG" || track=0
        ;;
      many-fields) padding=29 ;;
      track-conflict) track_options='["Small","Large"]' ;;
    esac
    jq -n --argjson status "$status" --argjson risk "$risk" --argjson track "$track" --argjson padding "$padding" --argjson track_options "$track_options" '{fields: ([{id:"status",name:"Status",options:[$status[] | {name:.}]}] + [range(0; $padding) | {name:("Field " + tostring)}] + (if $risk == 1 then [{id:"risk",name:"Risk",options:[{name:"Standard"},{name:"Elevated"}]}] else [] end) + (if $track == 1 then [{id:"track",name:"Track",options:[$track_options[] | {name:.}]}] else [] end))}'
    ;;
  "project link"|"project field-create") exit 0 ;;
  # The query response supplies a linked repository, Status database ID, and
  # a grouped Board. no-board withholds the view until POST creates it.
  "api graphql")
    # The repository template query reports PR templates. new-repo and
    # no-templates start without one; new-repo gains it once it is written.
    case "$*" in
      *pullRequestTemplates*)
        if { [ "${GH_TEST_MODE:-ok}" = new-repo ] || [ "${GH_TEST_MODE:-ok}" = no-templates ]; } && ! grep -q 'PUT repos/test/project/contents/.github/pull_request_template.md' "$GH_TEST_LOG"; then
          printf '%s\n' '{"data":{"repository":{"pullRequestTemplates":[]}}}'
        else
          printf '%s\n' '{"data":{"repository":{"pullRequestTemplates":[{"filename":"pull_request_template.md"}]}}}'
        fi
        exit 0
        ;;
    esac
    if [ "${GH_TEST_MODE:-ok}" = no-board ] && ! grep -Eq 'POST (users|orgs)/test/projectsV2/7/views' "$GH_TEST_LOG"; then
      printf '%s\n' '{"data":{"node":{"repositories":{"pageInfo":{"hasNextPage":false},"nodes":[{"nameWithOwner":"test/project"}]},"fields":{"pageInfo":{"hasNextPage":false},"nodes":[{"databaseId":5,"name":"Status"}]},"views":{"pageInfo":{"hasNextPage":false},"nodes":[]}}}}'
    else
      printf '%s\n' '{"data":{"node":{"repositories":{"pageInfo":{"hasNextPage":false},"nodes":[{"nameWithOwner":"test/project"}]},"fields":{"pageInfo":{"hasNextPage":false},"nodes":[{"databaseId":5,"name":"Status"}]},"views":{"pageInfo":{"hasNextPage":false},"nodes":[{"id":"view","name":"Board","layout":"BOARD_LAYOUT","verticalGroupByFields":{"nodes":[{"name":"Status"}]}}]}}}}'
    fi
    ;;
  # The change issue form exists unless the mode starts without templates.
  "api repos/test/project/contents/.github/ISSUE_TEMPLATE/change.yml")
    if { [ "${GH_TEST_MODE:-ok}" = new-repo ] || [ "${GH_TEST_MODE:-ok}" = no-templates ]; } && ! grep -q 'PUT repos/test/project/contents/.github/ISSUE_TEMPLATE/change.yml' "$GH_TEST_LOG"; then
      printf 'gh: Not Found (HTTP 404)\n' >&2
      exit 1
    fi
    printf '%s\n' '{"path":".github/ISSUE_TEMPLATE/change.yml"}'
    ;;
  "api repos/test/project/rulesets?per_page=100")
    # foreign-ci starts without the factory ruleset; after POST it appears.
    if { [ "${GH_TEST_MODE:-ok}" = foreign-ci ] || [ "${GH_TEST_MODE:-ok}" = new-repo ]; } && ! grep -q 'POST repos/test/project/rulesets' "$GH_TEST_LOG"; then
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
      *"PUT repos/test/project/contents/.github/ISSUE_TEMPLATE/change.yml"*)
        if [ -n "${GH_TEST_FORM_BODY:-}" ]; then cat > "$GH_TEST_FORM_BODY"; fi
        exit 0 ;;
      *"PUT repos/test/project/contents/.github/pull_request_template.md"*)
        if [ -n "${GH_TEST_PR_TEMPLATE_BODY:-}" ]; then cat > "$GH_TEST_PR_TEMPLATE_BODY"; fi
        exit 0 ;;
      *"POST users/test/projectsV2/7/views"*|*"POST orgs/test/projectsV2/7/views"*|*"POST repos/test/project/rulesets"*|*"POST repos/test/project/branches/master/rename"*) exit 0 ;;
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
if grep -Eq 'project create|project edit|field-create|graphql --input|--method POST|--method PUT' "$LOG"; then
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
grep -q -- '--name Track --data-type SINGLE_SELECT --single-select-options Fast,Standard,Product' "$LOG" || fail "new Project Track field was not created"
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
# A new repository starts on the owner's default branch name. Setup renames it
# to main before CI and protection are pinned to that branch.
GH_TEST_MODE=new-repo GH_TEST_CI_BODY="$CI_BODY" run_configure --apply >/dev/null || fail "new repository setup failed"
grep -q 'repo create test/project --private --add-readme' "$LOG" || fail "missing repository was not created"
grep -q 'POST repos/test/project/branches/master/rename -f new_name=main' "$LOG" || fail "new repository branch was not renamed to main"
jq -r '.content' "$CI_BODY" | base64 --decode | grep -q 'branches: \["main"\]' || fail "new repository CI was not pinned to main"
jq -e '.branch == "main"' "$CI_BODY" >/dev/null || fail "new repository CI was not committed to main"

: > "$LOG"
# A run interrupted after creating the repository leaves it on master with
# one commit. The rerun finds it unused and still renames the branch to main.
GH_TEST_MODE=new-repo GH_TEST_REPO_EXISTS=1 run_configure --apply >/dev/null || fail "interrupted new repository was not recovered"
if grep -q 'repo create' "$LOG"; then fail "recovery created the repository again"; fi
grep -q 'POST repos/test/project/branches/master/rename -f new_name=main' "$LOG" || fail "interrupted new repository branch was not renamed to main"

: > "$LOG"
# GitHub applies a rename asynchronously; a stale first read must be retried.
GH_TEST_MODE=new-repo GH_TEST_RENAME_LAG=1 CONFIGURE_POLL_SECONDS=0 run_configure --apply >/dev/null || fail "a lagging branch rename was not awaited"

: > "$LOG"
# A new repository also receives the change issue form and PR template from
# this repository's templates/ folder, committed to main.
FORM_BODY="$TEST_ROOT/form-body.json"
PR_TEMPLATE_BODY="$TEST_ROOT/pr-template-body.json"
GH_TEST_MODE=new-repo GH_TEST_FORM_BODY="$FORM_BODY" GH_TEST_PR_TEMPLATE_BODY="$PR_TEMPLATE_BODY" run_configure --apply >/dev/null || fail "new repository template setup failed"
jq -r '.content' "$FORM_BODY" | base64 --decode | cmp -s - "$ROOT/templates/change.yml" || fail "issue form does not match templates/change.yml"
jq -r '.content' "$PR_TEMPLATE_BODY" | base64 --decode | cmp -s - "$ROOT/templates/pull_request_template.md" || fail "PR template does not match templates/pull_request_template.md"
jq -e '.branch == "main"' "$FORM_BODY" >/dev/null || fail "issue form was not committed to main"

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
expect_failure_without_mutation unmarked
expect_failure_without_mutation field-limit
expect_failure_without_mutation excluded-main
expect_failure_without_mutation ambiguous-ci
expect_failure_without_mutation no-ci --required-check build
expect_failure_without_mutation limit
expect_failure_without_mutation repo-error
expect_failure_without_mutation track-conflict

: > "$LOG"
# Behind an existing factory ruleset, missing templates cannot be committed
# directly: setup reports them and still completes without writing.
output=$(GH_TEST_MODE=no-templates run_configure --apply) || fail "missing templates behind a ruleset failed setup"
printf '%s' "$output" | grep -q 'missing .github/ISSUE_TEMPLATE/change.yml: add it through a pull request' || fail "missing issue form was not reported"
printf '%s' "$output" | grep -q 'missing .github/pull_request_template.md: add it through a pull request' || fail "missing PR template was not reported"
if grep -q -- '--method PUT' "$LOG"; then fail "templates were written behind an existing ruleset"; fi

# A run interrupted after marking a new Project leaves GitHub's default Status
# options. With no cards to invalidate, a rerun finishes the configuration.
: > "$LOG"
GH_TEST_MODE=default-status run_configure --apply >/dev/null || fail "interrupted empty factory Project was not recovered"
grep -q 'graphql --input' "$LOG" || fail "interrupted factory Project Status was not configured"
if grep -q 'project create' "$LOG"; then fail "recovery created another Project"; fi

# The same default options on a Project that already holds cards stay
# untouched, because replacing options would clear those cards' Status.
export GH_TEST_PROJECT_ITEMS=3
expect_failure_without_mutation default-status
unset GH_TEST_PROJECT_ITEMS

# GitHub creates a Project as private. A public setup interrupted before its
# visibility change leaves an empty private Project, which a rerun finishes.
: > "$LOG"
GH_TEST_REPO_VISIBILITY=PUBLIC GH_TEST_MODE=default-status run_configure --apply --visibility public >/dev/null || fail "interrupted public factory Project was not recovered"
grep -q 'project edit 7 --owner test --visibility PUBLIC' "$LOG" || fail "interrupted factory Project visibility was not configured"

# A configured Project keeps its own visibility; a mismatch stops setup.
export GH_TEST_REPO_VISIBILITY=PUBLIC
expect_failure_without_mutation ok --visibility public
unset GH_TEST_REPO_VISIBILITY

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
if grep -q 'project field-create' "$LOG"; then fail "existing Risk or Track field beyond default lookup limit was recreated"; fi
grep -q 'project field-list 7 --owner test --limit 1000' "$LOG" || fail "Project fields were fetched with the default limit"

: > "$LOG"
# Existing CI with no factory ruleset gets protection without replacing CI.
GH_TEST_MODE=foreign-ci run_configure --apply >/dev/null
grep -q 'POST repos/test/project/rulesets' "$LOG" || fail "missing ruleset was not created"

printf 'ok - project configuration and conflict safety\n'
