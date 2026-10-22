#!/usr/bin/env bash

set -u

OWNER=""
REPOSITORY=""
PROJECT_TITLE=""
VISIBILITY="private"
REQUIRED_CHECK="verify"
REQUIRED_CHECK_EXPLICIT=0
API_VERSION="2026-03-10"
APPLY=0

usage() {
  cat <<'EOF'
Usage: configure-project.sh --owner OWNER --repo NAME --project-title TITLE [options]

Options:
  --visibility private|public  Repository visibility (default: private)
  --required-check NAME        Required CI check (default: verify)
  --apply                      Apply after printing the plan
  --help                       Show this help
EOF
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

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

[ -n "$OWNER" ] || fail "--owner is required"
[ -n "$REPOSITORY" ] || fail "--repo is required"
[ -n "$PROJECT_TITLE" ] || fail "--project-title is required"
[ -n "$REQUIRED_CHECK" ] || fail "--required-check cannot be empty"
case "$VISIBILITY" in private|public) ;; *) fail "--visibility must be private or public" ;; esac
case "$OWNER/$REPOSITORY" in *[!A-Za-z0-9_./-]*) fail "owner and repository contain unsupported characters" ;; esac

printf '%s\n' \
  "Repository: $OWNER/$REPOSITORY ($VISIBILITY)" \
  "Project: $OWNER / $PROJECT_TITLE" \
  "Status: Inbox, Ready, In Progress, In Review, Done" \
  "Risk: Standard, Elevated" \
  "View: Board grouped by Status" \
  "CI: preserve existing workflows or add .github/workflows/ci.yml" \
  "Ruleset: pull requests, no deletion, no force pushes, required check '$REQUIRED_CHECK'" \
  "Excluded: deployments, environments, secrets, production, monitoring"

[ "$APPLY" -eq 1 ] || {
  printf '%s\n' "Dry run only. Re-run with --apply after reviewing this plan."
  exit 0
}

command -v gh >/dev/null 2>&1 || fail "gh is required"
command -v jq >/dev/null 2>&1 || fail "jq is required"
gh auth status >/dev/null 2>&1 || fail "GitHub CLI authentication is unavailable"

TMP_ERR=$(mktemp "${TMPDIR:-/tmp}/configure-project.XXXXXX") || fail "cannot create temporary file"
trap 'rm -f "$TMP_ERR"' EXIT HUP INT TERM

owner_state=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "users/$OWNER") || fail "cannot inspect owner"
owner_type=$(printf '%s' "$owner_state" | jq -r '.type') || fail "invalid owner response"
case "$owner_type" in User|Organization) ;; *) fail "unsupported GitHub owner type: $owner_type" ;; esac

REPO_CREATED=0
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

workflows=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "repos/$OWNER/$REPOSITORY/actions/workflows?per_page=100") || fail "cannot inspect repository workflows"
workflow_count=$(printf '%s' "$workflows" | jq '.total_count') || fail "invalid workflows response"

# A repository that already has CI publishes status checks whose names we cannot
# know. Requiring our default check would block its real pull requests, so stop
# and ask for the exact check name. Skip this when the factory already
# provisioned the repository, because its own CI and ruleset are then expected.
if [ "$workflow_count" -gt 0 ] && [ "$REQUIRED_CHECK_EXPLICIT" -eq 0 ]; then
  existing_rulesets=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "repos/$OWNER/$REPOSITORY/rulesets") || fail "cannot inspect repository rulesets"
  existing_factory=$(printf '%s' "$existing_rulesets" | jq '[.[] | select(.name == "software-factory-development")] | length') || fail "invalid ruleset response"
  [ "$existing_factory" -gt 0 ] || fail "repository already has CI; re-run with --required-check NAME set to the status check its CI publishes"
fi

PROJECT_SCAN_LIMIT=1000
projects=$(gh project list --owner "$OWNER" --limit "$PROJECT_SCAN_LIMIT" --format json) || fail "cannot list Projects"
project_total=$(printf '%s' "$projects" | jq '.projects | length') || fail "invalid Project response"
[ "$project_total" -lt "$PROJECT_SCAN_LIMIT" ] || fail "Project lookup reached the safety limit; narrow or clean up the owner before applying"
project_count=$(printf '%s' "$projects" | jq --arg title "$PROJECT_TITLE" '[.projects[] | select(.title == $title)] | length') || fail "invalid Project response"
[ "$project_count" -le 1 ] || fail "multiple Projects have the requested title"

PROJECT_CREATED=0
if [ "$project_count" -eq 0 ]; then
  project_number=$(gh project create --owner "$OWNER" --title "$PROJECT_TITLE" --format json --jq '.number') || fail "cannot create Project"
  PROJECT_CREATED=1
else
  project_number=$(printf '%s' "$projects" | jq -r --arg title "$PROJECT_TITLE" '.projects[] | select(.title == $title) | .number')
fi

project_id=$(gh project view "$project_number" --owner "$OWNER" --format json --jq '.id') || fail "cannot resolve Project ID"

fields=$(gh project field-list "$project_number" --owner "$OWNER" --format json) || fail "cannot list Project fields"
status_count=$(printf '%s' "$fields" | jq '[.fields[] | select(.name == "Status")] | length') || fail "invalid field response"
[ "$status_count" -eq 1 ] || fail "Project must contain exactly one Status field"
status_options=$(printf '%s' "$fields" | jq -r '.fields[] | select(.name == "Status") | [.options[].name] | join(",")')

# Decide whether Status options need configuring. A Project the factory just
# created, or a pre-existing Project still carrying GitHub's untouched default
# options, is safe to configure. Any other non-matching set is a real conflict,
# for example a Project a prior interrupted run left with its defaults.
NEED_STATUS_UPDATE=0
if [ "$PROJECT_CREATED" -eq 1 ]; then
  NEED_STATUS_UPDATE=1
elif [ "$status_options" != "Inbox,Ready,In Progress,In Review,Done" ]; then
  if [ "$status_options" = "Todo,In Progress,Done" ]; then
    NEED_STATUS_UPDATE=1
  else
    fail "existing Status options conflict"
  fi
fi

risk_count=$(printf '%s' "$fields" | jq '[.fields[] | select(.name == "Risk")] | length')
[ "$risk_count" -le 1 ] || fail "Project has multiple Risk fields"
if [ "$risk_count" -eq 1 ]; then
  risk_options=$(printf '%s' "$fields" | jq -r '.fields[] | select(.name == "Risk") | [.options[].name] | join(",")')
  [ "$risk_options" = "Standard,Elevated" ] || fail "existing Risk options conflict"
fi

rulesets=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "repos/$OWNER/$REPOSITORY/rulesets") || fail "cannot inspect repository rulesets"
ruleset_count=$(printf '%s' "$rulesets" | jq '[.[] | select(.name == "software-factory-development")] | length')
[ "$ruleset_count" -le 1 ] || fail "multiple factory rulesets exist"
if [ "$ruleset_count" -eq 1 ]; then
  existing_ruleset_id=$(printf '%s' "$rulesets" | jq -r '.[] | select(.name == "software-factory-development") | .id')
  existing_ruleset=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "repos/$OWNER/$REPOSITORY/rulesets/$existing_ruleset_id") || fail "cannot inspect factory ruleset"
  printf '%s' "$existing_ruleset" | jq -e --arg check "$REQUIRED_CHECK" '
    .enforcement == "active" and
    (.conditions.ref_name.include | contains(["~DEFAULT_BRANCH"])) and
    ([.rules[].type] | contains(["deletion", "non_fast_forward", "pull_request", "required_status_checks"])) and
    (any(.rules[]; .type == "pull_request" and .parameters.required_approving_review_count == 0)) and
    (any(.rules[]; .type == "required_status_checks" and any(.parameters.required_status_checks[]; .context == $check)))
  ' >/dev/null || fail "existing factory ruleset conflicts"
fi

# Set visibility only on a Project the factory created. For a pre-existing
# Project, verify it already matches and stop on a mismatch rather than silently
# overwriting project-owned visibility.
desired_public=false
[ "$VISIBILITY" = public ] && desired_public=true
if [ "$PROJECT_CREATED" -eq 1 ]; then
  project_visibility=$(printf '%s' "$VISIBILITY" | tr '[:lower:]' '[:upper:]')
  gh project edit "$project_number" --owner "$OWNER" --visibility "$project_visibility" >/dev/null || fail "cannot set Project visibility"
else
  current_public=$(gh project view "$project_number" --owner "$OWNER" --format json --jq '.public') || fail "cannot inspect Project visibility"
  [ "$current_public" = "$desired_public" ] || fail "existing Project visibility does not match --visibility $VISIBILITY"
fi

if [ "$NEED_STATUS_UPDATE" -eq 1 ]; then
  status_id=$(printf '%s' "$fields" | jq -r '.fields[] | select(.name == "Status") | .id')
  payload=$(jq -n --arg id "$status_id" '{query:"mutation($input: UpdateProjectV2FieldInput!) { updateProjectV2Field(input: $input) { projectV2Field { ... on ProjectV2SingleSelectField { id } } } }",variables:{input:{fieldId:$id,singleSelectOptions:[{name:"Inbox",color:"GRAY",description:"Unresolved intent"},{name:"Ready",color:"BLUE",description:"Approved and unblocked"},{name:"In Progress",color:"YELLOW",description:"Implementation active"},{name:"In Review",color:"PURPLE",description:"Published for review"},{name:"Done",color:"GREEN",description:"Merged and synchronized"}]}}}') || fail "cannot build Status update"
  printf '%s' "$payload" | gh api graphql --input - >/dev/null || fail "cannot configure Status"
fi

fields=$(gh project field-list "$project_number" --owner "$OWNER" --format json) || fail "cannot refresh Project fields"
if [ "$risk_count" -eq 0 ]; then
  gh project field-create "$project_number" --owner "$OWNER" --name Risk --data-type SINGLE_SELECT --single-select-options Standard,Elevated >/dev/null || fail "cannot create Risk"
fi

# GraphQL variables are intentionally literal here.
# shellcheck disable=SC2016
project_query='query($id: ID!) { node(id: $id) { ... on ProjectV2 { repositories(first: 100) { nodes { nameWithOwner } } fields(first: 100) { nodes { ... on ProjectV2SingleSelectField { databaseId name } } } views(first: 100) { nodes { id name layout verticalGroupByFields(first: 10) { nodes { ... on ProjectV2Field { name } ... on ProjectV2SingleSelectField { name } } } } } } } }'
project_state=$(gh api graphql -f query="$project_query" -F id="$project_id") || fail "cannot inspect Project views and links"
linked=$(printf '%s' "$project_state" | jq --arg repo "$OWNER/$REPOSITORY" '[.data.node.repositories.nodes[] | select(.nameWithOwner == $repo)] | length')
[ "$linked" -le 1 ] || fail "repository is linked to Project more than once"
if [ "$linked" -eq 0 ]; then
  gh project link "$project_number" --owner "$OWNER" --repo "$REPOSITORY" >/dev/null 2>&1 || fail "cannot link repository to Project"
  project_state=$(gh api graphql -f query="$project_query" -F id="$project_id") || fail "cannot verify Project link"
  linked=$(printf '%s' "$project_state" | jq --arg repo "$OWNER/$REPOSITORY" '[.data.node.repositories.nodes[] | select(.nameWithOwner == $repo)] | length')
fi
[ "$linked" -eq 1 ] || fail "repository was not linked to Project"

board_count=$(printf '%s' "$project_state" | jq '[.data.node.views.nodes[] | select(.layout == "BOARD_LAYOUT" and any(.verticalGroupByFields.nodes[]?; .name == "Status"))] | length')
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
  board_count=$(printf '%s' "$project_state" | jq '[.data.node.views.nodes[] | select(.layout == "BOARD_LAYOUT" and any(.verticalGroupByFields.nodes[]?; .name == "Status"))] | length')
fi
[ "$board_count" -ge 1 ] || fail "Project has no Board view grouped by Status"

if [ "$workflow_count" -eq 0 ]; then
  workflow=$(cat <<'EOF'
name: CI

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
      - name: Check for merge conflict markers
        run: |
          if git grep -nIE '^(<{7}|>{7})( |$)' -- .; then
            echo "merge conflict markers found" >&2
            exit 1
          fi
          echo "no conflict markers"
EOF
)
  workflow=${workflow//__DEFAULT_BRANCH__/$default_branch}
  workflow_content=$(printf '%s\n' "$workflow" | base64 | tr -d '\n') || fail "cannot encode CI starter"
  workflow_payload=$(jq -n --arg message "Add minimal development CI" --arg content "$workflow_content" --arg branch "$default_branch" '{message:$message,content:$content,branch:$branch}') || fail "cannot build CI starter"
  printf '%s' "$workflow_payload" | gh api -H "X-GitHub-Api-Version: $API_VERSION" --method PUT "repos/$OWNER/$REPOSITORY/contents/.github/workflows/ci.yml" --input - >/dev/null || fail "cannot add CI starter"
fi

if [ "$ruleset_count" -eq 0 ]; then
  ruleset=$(jq -n --arg check "$REQUIRED_CHECK" '{name:"software-factory-development",target:"branch",enforcement:"active",conditions:{ref_name:{include:["~DEFAULT_BRANCH"],exclude:[]}},rules:[{type:"deletion"},{type:"non_fast_forward"},{type:"pull_request",parameters:{dismiss_stale_reviews_on_push:true,require_code_owner_review:false,require_last_push_approval:false,required_approving_review_count:0,required_review_thread_resolution:true}},{type:"required_status_checks",parameters:{required_status_checks:[{context:$check}],strict_required_status_checks_policy:true,do_not_enforce_on_create:true}}]}') || fail "cannot build ruleset"
  printf '%s' "$ruleset" | gh api -H "X-GitHub-Api-Version: $API_VERSION" --method POST "repos/$OWNER/$REPOSITORY/rulesets" --input - >/dev/null || fail "cannot create ruleset"
fi

workflows=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "repos/$OWNER/$REPOSITORY/actions/workflows?per_page=100") || fail "cannot verify repository workflows"
workflow_count=$(printf '%s' "$workflows" | jq '.total_count') || fail "invalid workflows response"
[ "$workflow_count" -ge 1 ] || fail "repository has no CI workflow"

rulesets=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "repos/$OWNER/$REPOSITORY/rulesets") || fail "cannot verify repository rulesets"
ruleset_id=$(printf '%s' "$rulesets" | jq -r '.[] | select(.name == "software-factory-development") | .id')
[ -n "$ruleset_id" ] && [ "$ruleset_id" != null ] || fail "factory ruleset is missing after apply"
ruleset_state=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" "repos/$OWNER/$REPOSITORY/rulesets/$ruleset_id") || fail "cannot verify factory ruleset"
printf '%s' "$ruleset_state" | jq -e --arg check "$REQUIRED_CHECK" '
  .enforcement == "active" and
  (.conditions.ref_name.include | contains(["~DEFAULT_BRANCH"])) and
  ([.rules[].type] | contains(["deletion", "non_fast_forward", "pull_request", "required_status_checks"])) and
  (any(.rules[]; .type == "pull_request" and .parameters.required_approving_review_count == 0)) and
  (any(.rules[]; .type == "required_status_checks" and any(.parameters.required_status_checks[]; .context == $check)))
' >/dev/null || fail "existing factory ruleset conflicts"

fields=$(gh project field-list "$project_number" --owner "$OWNER" --format json) || fail "cannot verify Project fields"
final_status=$(printf '%s' "$fields" | jq -r '.fields[] | select(.name == "Status") | [.options[].name] | join(",")')
final_risk=$(printf '%s' "$fields" | jq -r '.fields[] | select(.name == "Risk") | [.options[].name] | join(",")')
[ "$final_status" = "Inbox,Ready,In Progress,In Review,Done" ] || fail "Status verification failed"
[ "$final_risk" = "Standard,Elevated" ] || fail "Risk verification failed"

printf 'configured: %s/%s and Project %s\n' "$OWNER" "$REPOSITORY" "$project_number"
printf 'created repository: %s; created Project: %s\n' "$REPO_CREATED" "$PROJECT_CREATED"
