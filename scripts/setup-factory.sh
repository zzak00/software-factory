#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_VERSION='0.3.0'
readonly STATUS_NAMES_JSON='["Triage","Planning","Spec Ready","Ready for Agent","In Progress","In Review","Done"]'

apply=false
owner=''
repository_name=''
source_directory=$PWD
project_title=''
visibility='private'

usage() {
  cat <<'EOF'
Usage: setup-factory.sh [options]

Prepare one local project, GitHub repository, and GitHub Project for the
documentation-first software factory.

Options:
  --owner LOGIN             GitHub user or organization owner
  --repo NAME               GitHub repository name (default: source basename)
  --source PATH             Existing local project directory (default: cwd)
  --project-title TITLE     Exact Project title (default: NAME Software Factory)
  --visibility VALUE        private, public, or internal (default: private)
  --apply                   Perform approved mutations; otherwise inspect only
  -h, --help                Show this help
  --version                 Show the script version

The script only prepares the initial repository and Project state. It does not
configure Project workflows, install repository artifacts, commit, push,
configure rulesets, or enable security features. Those operations belong to
separate, human-approved procedures.
EOF
}

fail() {
  printf 'setup-factory: %s\n' "$*" >&2
  exit 1
}

info() {
  printf 'setup-factory: %s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --owner)
      [[ $# -ge 2 ]] || fail '--owner requires a value'
      owner=$2
      shift 2
      ;;
    --repo)
      [[ $# -ge 2 ]] || fail '--repo requires a value'
      repository_name=$2
      shift 2
      ;;
    --source)
      [[ $# -ge 2 ]] || fail '--source requires a value'
      source_directory=$2
      shift 2
      ;;
    --project-title)
      [[ $# -ge 2 ]] || fail '--project-title requires a value'
      project_title=$2
      shift 2
      ;;
    --visibility)
      [[ $# -ge 2 ]] || fail '--visibility requires a value'
      visibility=$2
      shift 2
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
      printf 'setup-factory %s\n' "$SCRIPT_VERSION"
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

case $visibility in
  private|public|internal) ;;
  *) fail '--visibility must be private, public, or internal' ;;
esac

require_command git
require_command gh
require_command jq
require_command mktemp

[[ -d "$source_directory" ]] || fail "source directory not found: $source_directory"
source_directory=$(CDPATH='' cd -- "$source_directory" && pwd -P)
readonly source_directory

if [[ -z "$repository_name" ]]; then
  repository_name=${source_directory##*/}
fi

[[ "$repository_name" =~ ^[A-Za-z0-9._-]+$ ]] ||
  fail 'repository name contains unsupported characters'

gh auth status >/dev/null 2>&1 || fail 'GitHub CLI authentication is invalid'

if [[ -z "$owner" ]]; then
  owner=$(gh api user --jq '.login') || fail 'could not resolve authenticated GitHub user'
fi

[[ "$owner" =~ ^[A-Za-z0-9-]+$ ]] || fail 'owner contains unsupported characters'

if [[ -z "$project_title" ]]; then
  project_title="$repository_name Software Factory"
fi

readonly owner repository_name project_title visibility apply
readonly repository="$owner/$repository_name"

info "version=$SCRIPT_VERSION"
info "mode=$(if $apply; then printf apply; else printf inspect; fi)"
info "source=$source_directory"
info "repository=$repository"
info "project_title=$project_title"

factory_temp_parent=${TMPDIR:-/tmp}
factory_temp_directory=$(mktemp -d "$factory_temp_parent/setup-factory.XXXXXX")
readonly factory_temp_directory
repository_error="$factory_temp_directory/repository-error"
trap 'rm -rf "$factory_temp_directory"' EXIT
expected_origin="https://github.com/$repository.git"
work_remaining=false
has_conflicts=false
repository_exists=false
project_exists=false
project_number=''
project_id=''
project_url=''

plan() {
  work_remaining=true
  info "PLAN $*"
}

conflict() {
  has_conflicts=true
  info "CONFLICT $*" >&2
}

is_expected_origin() {
  [[ "$1" == "$expected_origin" || "$1" == "git@github.com:$repository.git" ]]
}

canonical_git_root=$(git -C "$source_directory" rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$canonical_git_root" ]]; then
  plan 'initialize local Git repository with default branch main'
  plan "add origin $expected_origin after repository initialization"
else
  canonical_git_root=$(CDPATH='' cd -- "$canonical_git_root" && pwd -P)
  if [[ "$canonical_git_root" != "$source_directory" ]]; then
    conflict "source must be the Git repository root: source=$source_directory root=$canonical_git_root"
  else
    origin_url=$(git -C "$source_directory" remote get-url origin 2>/dev/null || true)
    if [[ -z "$origin_url" ]]; then
      plan "add origin $expected_origin"
    elif ! is_expected_origin "$origin_url"; then
      conflict "origin points to unexpected repository: $origin_url"
    else
      info "origin verified: $origin_url"
    fi
  fi
fi

repository_json=''
if repository_json=$(gh api "repos/$repository" 2>"$repository_error"); then
  repository_exists=true
  info 'repository exists'
  actual_visibility=$(jq -r 'if .private then "private" else .visibility | ascii_downcase end' <<<"$repository_json")
  if [[ "$actual_visibility" != "$visibility" ]]; then
    conflict "repository visibility is $actual_visibility, expected $visibility"
  fi
elif grep -Eq 'HTTP 404|Not Found' "$repository_error" 2>/dev/null; then
  plan "create $visibility GitHub repository $repository"
else
  sed 's/^/setup-factory: /' "$repository_error" >&2
  conflict 'could not inspect the GitHub repository'
fi

projects_error="$factory_temp_directory/projects-error"
projects_json=''
matching_projects='[]'
project_count=0
if projects_json=$(gh project list --owner "$owner" --limit 1000 --format json 2>"$projects_error"); then
  if matching_projects=$(jq -ce --arg title "$project_title" \
    '[.projects[] | select(.title == $title)]' <<<"$projects_json" 2>/dev/null); then
    project_count=$(jq -r 'length' <<<"$matching_projects")
    if [[ "$project_count" -gt 1 ]]; then
      conflict "multiple Projects have the exact title: $project_title"
    elif [[ "$project_count" -eq 1 ]]; then
      project_exists=true
      project_number=$(jq -r '.[0].number' <<<"$matching_projects")
      info "Project exists: $project_number"
    else
      plan "create private Project: $project_title"
    fi
  else
    conflict 'could not parse the GitHub Project list'
  fi
else
  sed 's/^/setup-factory: /' "$projects_error" >&2
  conflict 'could not inspect GitHub Projects'
fi

# shellcheck disable=SC2016 # GraphQL variables must remain literal.
linked_repositories_query='query($project_id: ID!) {
  node(id: $project_id) {
    ... on ProjectV2 {
      repositories(first: 100) {
        totalCount
        nodes { id nameWithOwner }
      }
    }
  }
}'

desired_options='[
    {"name":"Triage","color":"GRAY","description":"New item needs a decision"},
    {"name":"Planning","color":"BLUE","description":"Requirements are being clarified"},
    {"name":"Spec Ready","color":"PURPLE","description":"Parent specification is approved"},
    {"name":"Ready for Agent","color":"GREEN","description":"Approved ticket with no unresolved blockers"},
    {"name":"In Progress","color":"YELLOW","description":"Implementation is active"},
    {"name":"In Review","color":"ORANGE","description":"Pull request is ready for human review"},
    {"name":"Done","color":"GREEN","description":"Issue is complete or closed"}
  ]'

# shellcheck disable=SC2016 # GraphQL variables must remain literal.
update_query='mutation($input: UpdateProjectV2FieldInput!) {
  updateProjectV2Field(input: $input) {
    projectV2Field {
      ... on ProjectV2SingleSelectField {
        id
        name
        options { id name color description }
      }
    }
  }
}'

# shellcheck disable=SC2016 # GraphQL variables must remain literal.
views_query='query($project_id: ID!) {
  node(id: $project_id) {
    ... on ProjectV2 {
      views(first: 100) { nodes { id name layout } }
    }
  }
}'

# shellcheck disable=SC2016 # GraphQL variables must remain literal.
create_view_query='mutation($input: CreateProjectV2ViewInput!) {
  createProjectV2View(input: $input) {
    projectV2View { id name layout }
  }
}'

inspect_project_details() {
  local project_json fields_json status_fields status_count current_status_names
  local items_json item_count linked_repositories_json linked_repositories linked_project_count
  local views_json kanban_views kanban_count

  if ! project_json=$(gh project view "$project_number" --owner "$owner" --format json); then
    conflict 'could not inspect the selected Project'
    return
  fi

  project_id=$(jq -r '.id // empty' <<<"$project_json")
  project_url=$(jq -r '.url // empty' <<<"$project_json")
  if [[ "$project_id" != PVT_* ]]; then
    conflict 'Project returned an invalid node ID'
    return
  fi
  if [[ "$(jq -r '.public | type' <<<"$project_json")" != 'boolean' ]]; then
    conflict 'Project visibility was not reported'
  elif [[ "$(jq -r '.public' <<<"$project_json")" == true ]]; then
    conflict 'Project visibility is public, expected private'
  else
    info 'Project visibility verified: private'
  fi

  if linked_repositories_json=$(gh api graphql -f query="$linked_repositories_query" -F project_id="$project_id") &&
    linked_repositories=$(jq -ce '
      .data.node.repositories as $repositories
      | if ($repositories.nodes | type) != "array" or ($repositories.totalCount | type) != "number"
        then error("invalid Project repositories response")
        elif $repositories.totalCount > 100
        then error("Project has more than 100 linked repositories")
        else $repositories.nodes
        end
    ' <<<"$linked_repositories_json" 2>/dev/null); then
    linked_project_count=$(jq -r --arg repository "$repository" \
      '[.[] | select(.nameWithOwner == $repository)] | length' <<<"$linked_repositories")
    if [[ "$linked_project_count" -eq 0 ]]; then
      plan "link Project to repository $repository using Project $project_number"
    elif [[ "$linked_project_count" -eq 1 ]]; then
      info 'Project link verified'
    else
      conflict 'repository reports duplicate links to the selected Project'
    fi
  else
    conflict 'could not verify repositories linked to the Project'
  fi

  if fields_json=$(gh project field-list "$project_number" --owner "$owner" --limit 1000 --format json) &&
    status_fields=$(jq -ce '[.fields[] | select(.name == "Status")]' <<<"$fields_json" 2>/dev/null); then
    status_count=$(jq -r 'length' <<<"$status_fields")
    if [[ "$status_count" -ne 1 ]]; then
      conflict 'Project must contain exactly one built-in Status field'
    else
      status_field_id=$(jq -r '.[0].id' <<<"$status_fields")
      current_status_names=$(jq -c '.[0].options | map(.name)' <<<"$status_fields")
      if [[ "$current_status_names" == "$STATUS_NAMES_JSON" ]]; then
        info 'seven Status options verified'
      elif items_json=$(gh project item-list "$project_number" --owner "$owner" --limit 1000 --format json) &&
        item_count=$(jq -er '.totalCount' <<<"$items_json" 2>/dev/null); then
        if [[ "$item_count" -eq 0 ]]; then
          plan "update Status field $status_field_id in place"
        else
          conflict 'refusing to replace Status options on a non-empty Project'
        fi
      else
        conflict 'could not verify whether the Project is empty'
      fi
    fi
  else
    conflict 'could not inspect Project fields'
  fi

  if views_json=$(gh api graphql -f query="$views_query" -F project_id="$project_id") &&
    kanban_views=$(jq -ce '[.data.node.views.nodes[] | select(.name == "Kanban")]' \
      <<<"$views_json" 2>/dev/null); then
    kanban_count=$(jq -r 'length' <<<"$kanban_views")
    if [[ "$kanban_count" -gt 1 ]]; then
      conflict 'multiple Project views are named Kanban'
    elif [[ "$kanban_count" -eq 1 ]]; then
      if [[ "$(jq -r '.[0].layout' <<<"$kanban_views")" == 'BOARD_LAYOUT' ]]; then
        info 'Kanban board view verified'
      else
        conflict 'existing Kanban view is not a board layout'
      fi
    else
      plan "create Kanban board view in Project $project_number"
    fi
  else
    conflict 'could not inspect Project views'
  fi
}

inspect_label() {
  local label_name=$1
  local label_color=$2
  local label_description=$3
  local labels_json=$4
  local label_matches label_count existing_color existing_description expected_color

  label_matches=$(jq -c --arg name "$label_name" '[.[] | select(.name == $name)]' <<<"$labels_json")
  label_count=$(jq -r 'length' <<<"$label_matches")
  if [[ "$label_count" -eq 0 ]]; then
    plan "create label: $label_name"
  elif [[ "$label_count" -gt 1 ]]; then
    conflict "duplicate label name: $label_name"
  else
    existing_color=$(jq -r '.[0].color | ascii_downcase' <<<"$label_matches")
    existing_description=$(jq -r '.[0].description // ""' <<<"$label_matches")
    expected_color=$(printf '%s' "$label_color" | tr '[:upper:]' '[:lower:]')
    if [[ "$existing_color" == "$expected_color" && "$existing_description" == "$label_description" ]]; then
      info "label verified: $label_name"
    else
      plan "update label: $label_name"
    fi
  fi
}

if $project_exists; then
  inspect_project_details
elif [[ "$project_count" -eq 0 ]]; then
  plan 'link Project to repository after creation (Project number becomes available after creation)'
  plan 'configure Status field after Project creation (field ID becomes available after creation)'
  plan 'create Kanban board view after Project creation (Project ID becomes available after creation)'
fi

if $repository_exists; then
  if labels_json=$(gh label list --repo "$repository" --limit 1000 --json name,color,description); then
    inspect_label 'factory:spec' '1D76DB' 'Parent issue with an approved factory specification' "$labels_json"
    inspect_label 'needs-info' 'D4C5F9' 'Planning is blocked on human-provided information' "$labels_json"
    inspect_label 'wontfix' 'FFFFFF' 'Work was intentionally rejected or closed without implementation' "$labels_json"
  else
    conflict 'could not inspect repository labels'
  fi
else
  plan 'reconcile factory labels after repository creation'
fi

if $has_conflicts; then
  info 'setup inspection found conflicts; no changes were made' >&2
  exit 1
fi

if ! $apply; then
  if $work_remaining; then
    info 'setup inspection complete; apply is required'
    exit 2
  fi
  info 'initial repository and GitHub Project setup already matches'
  [[ -n "$project_url" ]] && info "Project URL: $project_url"
  exit 0
fi

if ! $work_remaining; then
  info 'initial repository and GitHub Project setup already matches; no changes made'
  [[ -n "$project_url" ]] && info "Project URL: $project_url"
  exit 0
fi

# Apply in dependency order. Every mutable resource is inspected again directly
# before it is changed so concurrent conflicts fail safely.
current_git_root=$(git -C "$source_directory" rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$current_git_root" ]]; then
  git -C "$source_directory" init -b main
  info 'local Git repository initialized'
else
  current_git_root=$(CDPATH='' cd -- "$current_git_root" && pwd -P)
  [[ "$current_git_root" == "$source_directory" ]] ||
    fail "source became nested inside another Git repository: $current_git_root"
fi

if repository_json=$(gh api "repos/$repository" 2>"$repository_error"); then
  actual_visibility=$(jq -r 'if .private then "private" else .visibility | ascii_downcase end' <<<"$repository_json")
  [[ "$actual_visibility" == "$visibility" ]] ||
    fail "repository visibility changed to $actual_visibility, expected $visibility"
else
  grep -Eq 'HTTP 404|Not Found' "$repository_error" 2>/dev/null || {
    sed 's/^/setup-factory: /' "$repository_error" >&2
    fail 'could not revalidate the GitHub repository'
  }
  gh repo create "$repository" "--$visibility" --disable-wiki
  repository_json=$(gh api "repos/$repository")
  actual_visibility=$(jq -r 'if .private then "private" else .visibility | ascii_downcase end' <<<"$repository_json")
  [[ "$actual_visibility" == "$visibility" ]] || fail 'created repository failed visibility verification'
  info 'repository created'
fi

origin_url=$(git -C "$source_directory" remote get-url origin 2>/dev/null || true)
if [[ -z "$origin_url" ]]; then
  git -C "$source_directory" remote add origin "$expected_origin"
  info "origin added: $expected_origin"
elif is_expected_origin "$origin_url"; then
  info "origin verified: $origin_url"
else
  fail "origin changed to unexpected repository: $origin_url"
fi

projects_json=$(gh project list --owner "$owner" --limit 1000 --format json) ||
  fail 'could not revalidate GitHub Projects'
matching_projects=$(jq -ce --arg title "$project_title" \
  '[.projects[] | select(.title == $title)]' <<<"$projects_json") || fail 'could not parse the GitHub Project list'
project_count=$(jq -r 'length' <<<"$matching_projects")
if [[ "$project_count" -eq 0 ]]; then
  project_created=$(gh project create --owner "$owner" --title "$project_title" --format json)
  project_number=$(jq -er '.number' <<<"$project_created") || fail 'created Project returned no number'
  gh project edit "$project_number" --owner "$owner" --visibility PRIVATE >/dev/null
  info "Project created: $project_number"
elif [[ "$project_count" -eq 1 ]]; then
  project_number=$(jq -r '.[0].number' <<<"$matching_projects")
else
  fail "multiple Projects now have the exact title: $project_title"
fi

project_json=$(gh project view "$project_number" --owner "$owner" --format json)
project_id=$(jq -r '.id // empty' <<<"$project_json")
project_url=$(jq -r '.url // empty' <<<"$project_json")
[[ "$project_id" == PVT_* ]] || fail 'Project returned an invalid node ID during apply'
[[ "$(jq -r '.public' <<<"$project_json")" == false ]] || fail 'Project visibility is not private during apply'

linked_repositories_json=$(gh api graphql -f query="$linked_repositories_query" -F project_id="$project_id")
linked_repositories=$(jq -ce '.data.node.repositories as $r |
  if ($r.nodes | type) != "array" or ($r.totalCount | type) != "number" or $r.totalCount > 100
  then error("invalid") else $r.nodes end' <<<"$linked_repositories_json") ||
  fail 'could not revalidate repositories linked to the Project'
linked_project_count=$(jq -r --arg repository "$repository" \
  '[.[] | select(.nameWithOwner == $repository)] | length' <<<"$linked_repositories")
if [[ "$linked_project_count" -eq 0 ]]; then
  gh project link "$project_number" --owner "$owner" --repo "$repository_name"
  info 'Project linked to repository'
elif [[ "$linked_project_count" -ne 1 ]]; then
  fail 'repository reports duplicate links to the selected Project'
fi

fields_json=$(gh project field-list "$project_number" --owner "$owner" --limit 1000 --format json)
status_fields=$(jq -ce '[.fields[] | select(.name == "Status")]' <<<"$fields_json")
[[ "$(jq -r 'length' <<<"$status_fields")" -eq 1 ]] ||
  fail 'Project must contain exactly one built-in Status field'
current_status_names=$(jq -c '.[0].options | map(.name)' <<<"$status_fields")
if [[ "$current_status_names" != "$STATUS_NAMES_JSON" ]]; then
  items_json=$(gh project item-list "$project_number" --owner "$owner" --limit 1000 --format json)
  [[ "$(jq -r '.totalCount' <<<"$items_json")" -eq 0 ]] ||
    fail 'refusing to replace Status options on a Project that is no longer empty'
  status_field_id=$(jq -r '.[0].id' <<<"$status_fields")
  update_options=$(jq -cn --argjson desired "$desired_options" --argjson fields "$status_fields" '
    $fields[0].options as $existing
    | $desired
    | map(
        . as $wanted
        | ([ $existing[] | select(.name == $wanted.name) | .id ][0]
          // if $wanted.name == "Triage"
             then [ $existing[] | select(.name == "Todo") | .id ][0]
             else null
             end) as $existing_id
        | if $existing_id then . + {id: $existing_id} else . end
      )
  ')
  jq -cn \
    --arg query "$update_query" \
    --arg field_id "$status_field_id" \
    --argjson options "$update_options" \
    '{query: $query, variables: {input: {fieldId: $field_id, singleSelectOptions: $options}}}' |
    gh api graphql --input - >/dev/null
  info 'Status field updated in place'
fi

fields_json=$(gh project field-list "$project_number" --owner "$owner" --limit 1000 --format json)
status_fields=$(jq -c '[.fields[] | select(.name == "Status")]' <<<"$fields_json")
jq -e --argjson desired "$STATUS_NAMES_JSON" '
  length == 1 and (.[0].options | map(.name)) == $desired
' <<<"$status_fields" >/dev/null || fail 'Status verification failed'

status_field_id=$(jq -r '.[0].id' <<<"$status_fields")
info 'seven Status options verified'

views_json=$(gh api graphql -f query="$views_query" -F project_id="$project_id")
kanban_views=$(jq -c '[.data.node.views.nodes[] | select(.name == "Kanban")]' <<<"$views_json")
kanban_count=$(jq -r 'length' <<<"$kanban_views")

if [[ "$kanban_count" -gt 1 ]]; then
  fail 'multiple Project views are named Kanban'
elif [[ "$kanban_count" -eq 1 ]]; then
  [[ "$(jq -r '.[0].layout' <<<"$kanban_views")" == 'BOARD_LAYOUT' ]] ||
    fail 'existing Kanban view is not a board layout'
  info 'Kanban board view verified'
else
  jq -cn \
    --arg query "$create_view_query" \
    --arg project_id "$project_id" \
    '{query: $query, variables: {input: {projectId: $project_id, name: "Kanban", layout: "BOARD_LAYOUT"}}}' |
    gh api graphql --input - >/dev/null
  info 'Kanban board view created'
fi

ensure_label() {
  local label_name=$1
  local label_color=$2
  local label_description=$3
  local labels_json=$4
  local label_matches label_count existing_color existing_description expected_color
  label_matches=$(jq -c --arg name "$label_name" '[.[] | select(.name == $name)]' <<<"$labels_json")
  label_count=$(jq -r 'length' <<<"$label_matches")

  if [[ "$label_count" -eq 0 ]]; then
    gh label create "$label_name" --repo "$repository" --color "$label_color" --description "$label_description"
    info "label created: $label_name"
  elif [[ "$label_count" -eq 1 ]]; then
    existing_color=$(jq -r '.[0].color | ascii_downcase' <<<"$label_matches")
    existing_description=$(jq -r '.[0].description // ""' <<<"$label_matches")
    expected_color=$(printf '%s' "$label_color" | tr '[:upper:]' '[:lower:]')

    if [[ "$existing_color" == "$expected_color" && "$existing_description" == "$label_description" ]]; then
      info "label verified: $label_name"
    else
      gh label edit "$label_name" --repo "$repository" --color "$label_color" --description "$label_description"
      info "label updated: $label_name"
    fi
  else
    fail "duplicate label name: $label_name"
  fi
}

labels_json=$(gh label list --repo "$repository" --limit 1000 --json name,color,description)
ensure_label 'factory:spec' '1D76DB' 'Parent issue with an approved factory specification' "$labels_json"
ensure_label 'needs-info' 'D4C5F9' 'Planning is blocked on human-provided information' "$labels_json"
ensure_label 'wontfix' 'FFFFFF' 'Work was intentionally rejected or closed without implementation' "$labels_json"

labels_json=$(gh label list --repo "$repository" --limit 1000 --json name,color,description)
for expected_label in \
  'factory:spec|1d76db|Parent issue with an approved factory specification' \
  'needs-info|d4c5f9|Planning is blocked on human-provided information' \
  'wontfix|ffffff|Work was intentionally rejected or closed without implementation'
do
  IFS='|' read -r expected_name expected_color expected_description <<<"$expected_label"
  jq -e --arg name "$expected_name" --arg color "$expected_color" --arg description "$expected_description" '
    [.[] | select(.name == $name and (.color | ascii_downcase) == $color and (.description // "") == $description)]
    | length == 1
  ' <<<"$labels_json" >/dev/null || fail "label verification failed: $expected_name"
done

info 'initial repository and GitHub Project setup complete'
info "Project URL: $project_url"
info 'Project workflows, repository artifacts, rulesets, security, and workflow execution are intentionally out of scope'
