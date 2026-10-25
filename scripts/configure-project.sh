#!/usr/bin/env bash

# Configure the GitHub resources for one factory-managed repository. Without
# --apply this script only prints the intended shape and makes no API calls.
# The script uses explicit failures instead of `set -e` so each stop explains
# which GitHub object was incomplete or incompatible.
set -u

# Values supplied by the caller, followed by the stable API and lookup limits.
# An empty REQUIRED_CHECK means we must infer it from published CI later.
OWNER=""
REPOSITORY=""
PROJECT_TITLE=""
VISIBILITY="private"
REQUIRED_CHECK=""
REQUIRED_CHECK_EXPLICIT=0
API_VERSION="2026-03-10"
PROJECT_FIELD_LIMIT=1000
FACTORY_DESCRIPTION="Managed by Software Factory"
APPLY=0

usage() {
  cat <<'EOF'
Usage: configure-project.sh --owner OWNER --repo NAME --project-title TITLE [options]

Options:
  --visibility private|public  Repository visibility (default: private)
  --required-check NAME        Required check when existing CI is ambiguous
  --apply                      Apply after printing the plan
  --help                       Show this help
EOF
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# Parse flags before touching GitHub. The explicit-check flag distinguishes an
# omitted check from a caller-selected check that should skip inference.
while [ "$#" -gt 0 ]; do
  case "$1" in
    --owner) [ "$#" -ge 2 ] || fail "--owner requires a value"; OWNER=$2; shift 2 ;;
    --repo) [ "$#" -ge 2 ] || fail "--repo requires a value"; REPOSITORY=$2; shift 2 ;;
    --project-title) [ "$#" -ge 2 ] || fail "--project-title requires a value"; PROJECT_TITLE=$2; shift 2 ;;
    --visibility) [ "$#" -ge 2 ] || fail "--visibility requires a value"; VISIBILITY=$2; shift 2 ;;
    --required-check) [ "$#" -ge 2 ] || fail "--required-check requires a value"; REQUIRED_CHECK=$2; REQUIRED_CHECK_EXPLICIT=1; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --help) usage; exit 0 ;;
    *) fail "unknown option: $1" ;;
  esac
done

# Validate the minimum identity and configuration needed for a safe target.
# The owner/repository character check also keeps these values suitable for
# building REST paths used below.
[ -n "$OWNER" ] || fail "--owner is required"
[ -n "$REPOSITORY" ] || fail "--repo is required"
[ -n "$PROJECT_TITLE" ] || fail "--project-title is required"
[ "$REQUIRED_CHECK_EXPLICIT" -eq 0 ] || [ -n "$REQUIRED_CHECK" ] || fail "--required-check cannot be empty"
case "$VISIBILITY" in private|public) ;; *) fail "--visibility must be private or public" ;; esac
case "$OWNER/$REPOSITORY" in *[!A-Za-z0-9_./-]*) fail "owner and repository contain unsupported characters" ;; esac
FACTORY_PROJECT_TITLE="$PROJECT_TITLE - Software Factory"

# Print the same high-level plan in dry-run and apply mode. The suffix always
# reserves a separate Project, even if a Project with the base title exists.
printf '%s\n' \
  "Repository: $OWNER/$REPOSITORY ($VISIBILITY)" \
  "Project: $OWNER / $FACTORY_PROJECT_TITLE" \
  "Status: Inbox, Ready, In Progress, In Review, Done" \
  "Risk: Standard, Elevated" \
  "View: Board grouped by Status" \
  "CI: preserve existing workflows or add a Python quality workflow" \
  "Ruleset: pull requests, no deletion, no force pushes, one required CI check" \
  "Excluded: deployments, environments, secrets, production, monitoring"

[ "$APPLY" -eq 1 ] || {
  printf '%s\n' "Dry run only. Re-run with --apply after reviewing this plan."
  exit 0
}

# Do all local prerequisite checks before any potentially mutating API call.
command -v gh >/dev/null 2>&1 || fail "gh is required"
command -v jq >/dev/null 2>&1 || fail "jq is required"
gh auth status >/dev/null 2>&1 || fail "GitHub CLI authentication is unavailable"

TMP_ERR=$(mktemp "${TMPDIR:-/tmp}/configure-project.XXXXXX") || fail "cannot create temporary file"
trap 'rm -f "$TMP_ERR"' EXIT HUP INT TERM

# The REST user endpoint covers both users and organizations. Later, the Board
# creation URL depends on which kind owns the Project.
owner_state=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "users/$OWNER") || fail "cannot inspect owner"
owner_type=$(printf '%s' "$owner_state" | jq -r '.type') || fail "invalid owner response"
case "$owner_type" in User|Organization) ;; *) fail "unsupported GitHub owner type: $owner_type" ;; esac

REPO_CREATED=0
# Reuse a repository only when its visibility matches the request. A missing
# repository is the one condition under which setup creates a new one.
if repository_state=$(gh repo view "$OWNER/$REPOSITORY" --json visibility,defaultBranchRef 2>"$TMP_ERR"); then
  actual_visibility=$(printf '%s' "$repository_state" | jq -r '.visibility | ascii_downcase') || fail "cannot inspect repository"
  [ "$actual_visibility" = "$VISIBILITY" ] || fail "existing repository visibility is $actual_visibility"
else
  # Only a genuinely missing repository may be created. Any other failure
  # (access, network, rate limit) must stop so a transient error never
  # provisions an unexpected repository.
  repo_error=$(cat "$TMP_ERR")
  case "$repo_error" in
    *"Could not resolve to a Repository"*) ;;
    *) fail "cannot inspect repository: ${repo_error:-unknown error}" ;;
  esac
  gh repo create "$OWNER/$REPOSITORY" "--$VISIBILITY" --add-readme || fail "cannot create repository"
  REPO_CREATED=1
  repository_state=$(gh repo view "$OWNER/$REPOSITORY" --json visibility,defaultBranchRef) || fail "cannot inspect created repository"
fi
default_branch=$(printf '%s' "$repository_state" | jq -r '.defaultBranchRef.name // empty') || fail "invalid repository response"
[ -n "$default_branch" ] || fail "repository has no default branch; initialize it before applying factory configuration"

# Inspect workflows and every repository ruleset before changing Projects.
# A single ruleset page could hide an existing factory ruleset and make a
# later create attempt unsafe. Capture gh's output before jq so API failures
# cannot be hidden by a successful JSON parse of partial output.
workflows=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "repos/$OWNER/$REPOSITORY/actions/workflows?per_page=100") || fail "cannot inspect repository workflows"
workflow_count=$(printf '%s' "$workflows" | jq '.total_count') || fail "invalid workflows response"
ruleset_pages=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" --paginate "repos/$OWNER/$REPOSITORY/rulesets?per_page=100") || fail "cannot inspect repository rulesets"
rulesets=$(printf '%s\n' "$ruleset_pages" | jq -s 'if length > 0 and all(.[]; type == "array") then add else error("invalid ruleset pages") end') || fail "invalid ruleset response"
ruleset_count=$(printf '%s' "$rulesets" | jq '[.[] | select(.name == "software-factory-development")] | length') || fail "invalid ruleset response"
[ "$ruleset_count" -le 1 ] || fail "multiple factory rulesets exist"
if [ "$ruleset_count" -eq 1 ]; then
  existing_ruleset_id=$(printf '%s' "$rulesets" | jq -r '.[] | select(.name == "software-factory-development") | .id')
  existing_ruleset=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "repos/$OWNER/$REPOSITORY/rulesets/$existing_ruleset_id") || fail "cannot inspect factory ruleset"
fi

# A newly created workflow publishes a job named verify. For existing CI,
# infer a name only when the default branch exposes exactly one unique check.
# Reusing the old ruleset check supports a rerun before the new job first runs.
if [ "$workflow_count" -eq 0 ]; then
  [ "$REQUIRED_CHECK_EXPLICIT" -eq 0 ] || [ "$REQUIRED_CHECK" = verify ] || fail "the Python CI starter publishes 'verify'; remove --required-check or use verify"
  REQUIRED_CHECK=verify
else
  # Infer only from a check that GitHub has actually published. An explicit
  # name is needed when the branch has no runs or publishes several jobs. A
  # caller can select a pull-request-only check that has not run on main.
  if [ "$REQUIRED_CHECK_EXPLICIT" -eq 0 ]; then
    check_runs=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "repos/$OWNER/$REPOSITORY/commits/$default_branch/check-runs?per_page=100") || fail "cannot inspect published CI checks"
    check_count=$(printf '%s' "$check_runs" | jq -e '.total_count') || fail "invalid check-run response"
    [ "$check_count" -le 100 ] || fail "check lookup is incomplete; pass --required-check NAME after inspecting GitHub"
    check_names=$(printf '%s' "$check_runs" | jq -r '[.check_runs[].name] | unique | .[]') || fail "invalid check-run response"
    unique_check_count=$(printf '%s\n' "$check_names" | sed '/^$/d' | wc -l | tr -d ' ')
    if [ "$unique_check_count" -eq 1 ]; then
      REQUIRED_CHECK=$check_names
    elif [ "$unique_check_count" -eq 0 ] && [ "$ruleset_count" -eq 1 ]; then
      # A newly installed workflow may not have run yet. Reuse the check from
      # its existing factory ruleset, then validate the whole ruleset below.
      REQUIRED_CHECK=$(printf '%s' "$existing_ruleset" | jq -r '[.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context] | unique | if length == 1 then .[0] else empty end') || fail "cannot inspect factory check"
      [ -n "$REQUIRED_CHECK" ] || fail "cannot infer one CI check; pass --required-check NAME"
    else
      fail "cannot infer one CI check; pass --required-check NAME"
    fi
  fi
fi

# Compare the full protection contract, not just the ruleset name. In
# particular, excluding main would cancel an otherwise correct include rule.
# This function reads one JSON ruleset from stdin and returns jq's status.
ruleset_matches() {
  jq -e --arg check "$REQUIRED_CHECK" '
    .target == "branch" and
    .enforcement == "active" and
    .conditions.ref_name.include == ["~DEFAULT_BRANCH"] and
    .conditions.ref_name.exclude == [] and
    (.bypass_actors // []) == [] and
    ([.rules[].type] | sort) == (["deletion", "non_fast_forward", "pull_request", "required_status_checks"] | sort) and
    (any(.rules[]; .type == "pull_request" and
      .parameters.dismiss_stale_reviews_on_push == true and
      .parameters.require_code_owner_review == false and
      .parameters.require_last_push_approval == false and
      .parameters.required_approving_review_count == 0 and
      .parameters.required_review_thread_resolution == true)) and
    (any(.rules[]; .type == "required_status_checks" and
      .parameters.strict_required_status_checks_policy == true and
      .parameters.do_not_enforce_on_create == true and
      (.parameters.required_status_checks | length) == 1 and
      .parameters.required_status_checks[0].context == $check))
  ' >/dev/null
}

if [ "$ruleset_count" -eq 1 ]; then
  printf '%s' "$existing_ruleset" | ruleset_matches || fail "existing factory ruleset conflicts"
fi

# Include closed Projects in the lookup so a same-title closed board is not
# mistaken for an available name. A saturated result cannot prove uniqueness.
PROJECT_SCAN_LIMIT=1000
projects=$(gh project list --owner "$OWNER" --closed --limit "$PROJECT_SCAN_LIMIT" --format json) || fail "cannot list Projects"
project_total=$(printf '%s' "$projects" | jq '.projects | length') || fail "invalid Project response"
[ "$project_total" -lt "$PROJECT_SCAN_LIMIT" ] || fail "Project lookup reached the safety limit; narrow or clean up the owner before applying"
project_count=$(printf '%s' "$projects" | jq --arg title "$FACTORY_PROJECT_TITLE" '[.projects[] | select(.title == $title)] | length') || fail "invalid Project response"
[ "$project_count" -le 1 ] || fail "multiple factory Projects have the requested title"

PROJECT_CREATED=0
# Only a new Project receives the marker here. An existing same-title Project
# is inspected next and will be rejected unless it already carries that marker.
if [ "$project_count" -eq 0 ]; then
  project_number=$(gh project create --owner "$OWNER" --title "$FACTORY_PROJECT_TITLE" --format json --jq '.number') || fail "cannot create Project"
  PROJECT_CREATED=1
  gh project edit "$project_number" --owner "$OWNER" --description "$FACTORY_DESCRIPTION" >/dev/null || fail "cannot mark new factory Project"
else
  project_number=$(printf '%s' "$projects" | jq -r --arg title "$FACTORY_PROJECT_TITLE" '.projects[] | select(.title == $title) | .number')
fi

project_details=$(gh project view "$project_number" --owner "$OWNER" --format json) || fail "cannot inspect factory Project"
# Check identity, open state, and the marker before modifying fields or links.
project_id=$(printf '%s' "$project_details" | jq -r '.id // empty') || fail "cannot resolve Project ID"
[ -n "$project_id" ] || fail "factory Project has no ID"
actual_project_title=$(printf '%s' "$project_details" | jq -r '.title // empty') || fail "cannot inspect factory Project title"
[ "$actual_project_title" = "$FACTORY_PROJECT_TITLE" ] || fail "factory Project was renamed during setup"
[ "$(printf '%s' "$project_details" | jq -r '.closed')" = false ] || fail "factory Project is closed"
project_description=$(printf '%s' "$project_details" | jq -r '.shortDescription // empty') || fail "cannot inspect factory Project description"
[ "$project_description" = "$FACTORY_DESCRIPTION" ] || fail "same-named Project is not marked as factory-owned; leaving it untouched"

# GitHub's field-list command paginates. Request a large page and reject a
# result at the limit, since a hidden Status or Risk field would be dangerous.
fields=$(gh project field-list "$project_number" --owner "$OWNER" --limit "$PROJECT_FIELD_LIMIT" --format json) || fail "cannot list Project fields"
field_count=$(printf '%s' "$fields" | jq -e '.fields | length') || fail "invalid field response"
[ "$field_count" -lt "$PROJECT_FIELD_LIMIT" ] || fail "Project field lookup reached the safety limit"
status_count=$(printf '%s' "$fields" | jq '[.fields[] | select(.name == "Status")] | length') || fail "invalid field response"
[ "$status_count" -eq 1 ] || fail "Project must contain exactly one Status field"
status_options=$(printf '%s' "$fields" | jq -r '.fields[] | select(.name == "Status") | [.options[].name] | join(",")')

PROJECT_UNUSED=0
# Replacing single-select options can invalidate values on existing cards.
# Consequently, setup finishes Status and visibility only on an unused Project:
# one created in this run, or a marked Project that a previous run left with
# GitHub's defaults and no cards.
project_items=$(printf '%s' "$project_details" | jq -e '.items.totalCount') || fail "cannot count factory Project cards"
if [ "$PROJECT_CREATED" -eq 1 ]; then
  PROJECT_UNUSED=1
elif [ "$status_options" = "Todo,In Progress,Done" ] && [ "$project_items" -eq 0 ]; then
  PROJECT_UNUSED=1
elif [ "$status_options" != "Inbox,Ready,In Progress,In Review,Done" ]; then
  fail "existing factory Project has different Status options; leaving its cards untouched"
fi

risk_count=$(printf '%s' "$fields" | jq '[.fields[] | select(.name == "Risk")] | length')
# A missing Risk field is safe to create; different existing options are not.
[ "$risk_count" -le 1 ] || fail "Project has multiple Risk fields"
if [ "$risk_count" -eq 1 ]; then
  risk_options=$(printf '%s' "$fields" | jq -r '.fields[] | select(.name == "Risk") | [.options[].name] | join(",")')
  [ "$risk_options" = "Standard,Elevated" ] || fail "existing Risk options conflict"
fi

# Set visibility only on an unused Project, which GitHub created as private.
# For a configured Project, verify it already matches and stop on a mismatch
# rather than silently overwriting project-owned visibility.
desired_public=false
[ "$VISIBILITY" = public ] && desired_public=true
if [ "$PROJECT_UNUSED" -eq 1 ]; then
  project_visibility=$(printf '%s' "$VISIBILITY" | tr '[:lower:]' '[:upper:]')
  gh project edit "$project_number" --owner "$OWNER" --visibility "$project_visibility" >/dev/null || fail "cannot set Project visibility"
else
  current_public=$(printf '%s' "$project_details" | jq -r '.public') || fail "cannot inspect Project visibility"
  [ "$current_public" = "$desired_public" ] || fail "existing Project visibility does not match --visibility $VISIBILITY"
fi

if [ "$PROJECT_UNUSED" -eq 1 ]; then
  # GitHub exposes option replacement through GraphQL. The colors and short
  # descriptions are visible on the unused Project's Status field.
  status_id=$(printf '%s' "$fields" | jq -r '.fields[] | select(.name == "Status") | .id')
  payload=$(jq -n --arg id "$status_id" '{query:"mutation($input: UpdateProjectV2FieldInput!) { updateProjectV2Field(input: $input) { projectV2Field { ... on ProjectV2SingleSelectField { id } } } }",variables:{input:{fieldId:$id,singleSelectOptions:[{name:"Inbox",color:"GRAY",description:"Unresolved intent"},{name:"Ready",color:"BLUE",description:"Approved and unblocked"},{name:"In Progress",color:"YELLOW",description:"Implementation active"},{name:"In Review",color:"PURPLE",description:"Published for review"},{name:"Done",color:"GREEN",description:"Merged and synchronized"}]}}}') || fail "cannot build Status update"
  printf '%s' "$payload" | gh api graphql --input - >/dev/null || fail "cannot configure Status"
fi

# Read repository links, field database IDs, and views in one GraphQL query.
# Each connection reports whether its first 100 results are complete. Refuse
# to infer an absent link, field, or Board from a partial result.
# GraphQL variables are intentionally literal here.
# shellcheck disable=SC2016
project_query='query($id: ID!) { node(id: $id) { ... on ProjectV2 { repositories(first: 100) { pageInfo { hasNextPage } nodes { nameWithOwner } } fields(first: 100) { pageInfo { hasNextPage } nodes { ... on ProjectV2SingleSelectField { databaseId name } } } views(first: 100) { pageInfo { hasNextPage } nodes { id name layout verticalGroupByFields(first: 10) { nodes { ... on ProjectV2Field { name } ... on ProjectV2SingleSelectField { name } } } } } } } }'
project_state_complete() {
  jq -e '.data.node.repositories.pageInfo.hasNextPage == false and .data.node.fields.pageInfo.hasNextPage == false and .data.node.views.pageInfo.hasNextPage == false' >/dev/null
}
project_state=$(gh api graphql -f query="$project_query" -F id="$project_id") || fail "cannot inspect Project views and links"
printf '%s' "$project_state" | project_state_complete || fail "Project link, field, or view lookup is incomplete; leaving it untouched"
# Delay creation of the missing Risk field until the Project link and view
# lookup is known to be complete. A large reused Project should stop without
# a partial field change.
if [ "$risk_count" -eq 0 ]; then
  gh project field-create "$project_number" --owner "$OWNER" --name Risk --data-type SINGLE_SELECT --single-select-options Standard,Elevated >/dev/null || fail "cannot create Risk"
fi
linked=$(printf '%s' "$project_state" | jq --arg repo "$OWNER/$REPOSITORY" '[.data.node.repositories.nodes[] | select(.nameWithOwner == $repo)] | length')
# Linking is idempotent: create the link only when it is absent, then read back
# the relation rather than assuming the command succeeded semantically.
[ "$linked" -le 1 ] || fail "repository is linked to Project more than once"
if [ "$linked" -eq 0 ]; then
  gh project link "$project_number" --owner "$OWNER" --repo "$REPOSITORY" >/dev/null || fail "cannot link repository to Project"
  project_state=$(gh api graphql -f query="$project_query" -F id="$project_id") || fail "cannot verify Project link"
  printf '%s' "$project_state" | project_state_complete || fail "Project link verification is incomplete"
  linked=$(printf '%s' "$project_state" | jq --arg repo "$OWNER/$REPOSITORY" '[.data.node.repositories.nodes[] | select(.nameWithOwner == $repo)] | length')
fi
[ "$linked" -eq 1 ] || fail "repository was not linked to Project"

board_count=$(printf '%s' "$project_state" | jq '[.data.node.views.nodes[] | select(.layout == "BOARD_LAYOUT" and any(.verticalGroupByFields.nodes[]?; .name == "Status"))] | length')
# A board qualifies only when it is grouped by Status. The REST endpoint for
# creating a missing view differs between user and organization owners.
if [ "$board_count" -eq 0 ]; then
  status_database_id=$(printf '%s' "$project_state" | jq -r '.data.node.fields.nodes[] | select(.name == "Status") | .databaseId')
  [ -n "$status_database_id" ] && [ "$status_database_id" != null ] || fail "cannot resolve Status database ID"
  if [ "$owner_type" = Organization ]; then
    view_endpoint="orgs/$OWNER/projectsV2/$project_number/views"
  else
    view_endpoint="users/$OWNER/projectsV2/$project_number/views"
  fi
  view_payload=$(jq -n --argjson status "$status_database_id" '{name:"Board",layout:"board",vertical_group_by:[$status]}') || fail "cannot build Status board"
  printf '%s' "$view_payload" | gh api -H "X-GitHub-Api-Version: $API_VERSION" --method POST "$view_endpoint" --input - >/dev/null || fail "cannot create Status board"
  project_state=$(gh api graphql -f query="$project_query" -F id="$project_id") || fail "cannot verify Status board"
  printf '%s' "$project_state" | project_state_complete || fail "Project Board verification is incomplete"
  board_count=$(printf '%s' "$project_state" | jq '[.data.node.views.nodes[] | select(.layout == "BOARD_LAYOUT" and any(.verticalGroupByFields.nodes[]?; .name == "Status"))] | length')
fi
[ "$board_count" -ge 1 ] || fail "Project has no Board view grouped by Status"

if [ "$workflow_count" -eq 0 ]; then
  # The starter CI is intentionally small: one verify job runs Ruff lint and
  # formatting checks on PRs and default-branch pushes. It never edits code.
  workflow=$(cat <<'EOF'
name: Python quality

on:
  pull_request:
  push:
    branches: ["__DEFAULT_BRANCH__"]

permissions:
  contents: read

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/ruff-action@v4.1.0
        with:
          version: "0.17.1"
          args: "check ."
      - name: Check Python formatting
        run: ruff format --check .
EOF
)
  workflow=${workflow//__DEFAULT_BRANCH__/$default_branch}
  # The GitHub Contents API accepts base64 content plus a commit message.
  workflow_content=$(printf '%s\n' "$workflow" | base64 | tr -d '\n') || fail "cannot encode CI starter"
  workflow_payload=$(jq -n --arg message "Add Python quality CI" --arg content "$workflow_content" --arg branch "$default_branch" '{message:$message,content:$content,branch:$branch}') || fail "cannot build CI starter"
  printf '%s' "$workflow_payload" | gh api -H "X-GitHub-Api-Version: $API_VERSION" --method PUT "repos/$OWNER/$REPOSITORY/contents/.github/workflows/ci.yml" --input - >/dev/null || fail "cannot add CI starter"
fi

if [ "$ruleset_count" -eq 0 ]; then
  # Create protection only when no factory ruleset exists. Existing protection
  # was validated above and is deliberately left untouched.
  ruleset=$(jq -n --arg check "$REQUIRED_CHECK" '{name:"software-factory-development",target:"branch",enforcement:"active",conditions:{ref_name:{include:["~DEFAULT_BRANCH"],exclude:[]}},rules:[{type:"deletion"},{type:"non_fast_forward"},{type:"pull_request",parameters:{dismiss_stale_reviews_on_push:true,require_code_owner_review:false,require_last_push_approval:false,required_approving_review_count:0,required_review_thread_resolution:true}},{type:"required_status_checks",parameters:{required_status_checks:[{context:$check}],strict_required_status_checks_policy:true,do_not_enforce_on_create:true}}]}') || fail "cannot build ruleset"
  printf '%s' "$ruleset" | gh api -H "X-GitHub-Api-Version: $API_VERSION" --method POST "repos/$OWNER/$REPOSITORY/rulesets" --input - >/dev/null || fail "cannot create ruleset"
fi

workflows=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "repos/$OWNER/$REPOSITORY/actions/workflows?per_page=100") || fail "cannot verify repository workflows"
# Read back remote state after all writes. A successful API exit alone is not
# enough to prove the required workflow, ruleset, and field options now exist.
workflow_count=$(printf '%s' "$workflows" | jq '.total_count') || fail "invalid workflows response"
[ "$workflow_count" -ge 1 ] || fail "repository has no CI workflow"

ruleset_pages=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" --paginate "repos/$OWNER/$REPOSITORY/rulesets?per_page=100") || fail "cannot verify repository rulesets"
rulesets=$(printf '%s\n' "$ruleset_pages" | jq -s 'if length > 0 and all(.[]; type == "array") then add else error("invalid ruleset pages") end') || fail "invalid ruleset response"
ruleset_id=$(printf '%s' "$rulesets" | jq -r '.[] | select(.name == "software-factory-development") | .id')
[ -n "$ruleset_id" ] && [ "$ruleset_id" != null ] || fail "factory ruleset is missing after apply"
ruleset_state=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "repos/$OWNER/$REPOSITORY/rulesets/$ruleset_id") || fail "cannot verify factory ruleset"
printf '%s' "$ruleset_state" | ruleset_matches || fail "factory ruleset verification failed"

fields=$(gh project field-list "$project_number" --owner "$OWNER" --limit "$PROJECT_FIELD_LIMIT" --format json) || fail "cannot verify Project fields"
final_status=$(printf '%s' "$fields" | jq -r '.fields[] | select(.name == "Status") | [.options[].name] | join(",")')
final_risk=$(printf '%s' "$fields" | jq -r '.fields[] | select(.name == "Risk") | [.options[].name] | join(",")')
[ "$final_status" = "Inbox,Ready,In Progress,In Review,Done" ] || fail "Status verification failed"
[ "$final_risk" = "Standard,Elevated" ] || fail "Risk verification failed"

printf 'configured: %s/%s and Project %s\n' "$OWNER" "$REPOSITORY" "$project_number"
printf 'created repository: %s; created Project: %s\n' "$REPO_CREATED" "$PROJECT_CREATED"
