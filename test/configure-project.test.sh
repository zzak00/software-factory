#!/usr/bin/env bash

set -u

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

cat > "$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_TEST_LOG"

if [ "$1" = api ] && [ "${2:-}" = -H ]; then
  shift
  shift 2
  set -- api "$@"
fi

case "$1 $2" in
  "auth status") exit 0 ;;
  "repo view") printf '%s\n' '{"visibility":"PRIVATE","defaultBranchRef":{"name":"main"}}'; exit 0 ;;
  "api users/test") printf '{"id":42,"type":"%s"}\n' "${GH_TEST_OWNER_TYPE:-User}" ;;
  "api repos/test/project/actions/workflows?per_page=100")
    if [ "${GH_TEST_MODE:-ok}" = no-ci ] && ! grep -q 'contents/.github/workflows/ci.yml' "$GH_TEST_LOG"; then
      printf '%s\n' '{"total_count":0,"workflows":[]}'
    else
      printf '%s\n' '{"total_count":1,"workflows":[{"path":".github/workflows/project.yml"}]}'
    fi
    ;;
  "project list")
    if [ "${GH_TEST_MODE:-ok}" = limit ]; then
      jq -n '{projects: [range(0; 1000) | {title: ("Project " + tostring), number: .}]}'
    else
      printf '%s\n' '{"projects":[{"title":"Development","number":7}]}'
    fi
    ;;
  "project edit") exit 0 ;;
  "project view") printf '%s\n' 'project-id' ;;
  "project field-list")
    if [ "${GH_TEST_MODE:-ok}" = conflict ]; then
      printf '%s\n' '{"fields":[{"id":"status","name":"Status","options":[{"name":"Todo"}]}]}'
    else
      printf '%s\n' '{"fields":[{"id":"status","name":"Status","options":[{"name":"Inbox"},{"name":"Ready"},{"name":"In Progress"},{"name":"In Review"},{"name":"Done"}]},{"id":"risk","name":"Risk","options":[{"name":"Standard"},{"name":"Elevated"}]}]}'
    fi
    ;;
  "project link") exit 0 ;;
  "api graphql")
    if [ "${GH_TEST_MODE:-ok}" = no-board ] && ! grep -Eq 'POST (users|orgs)/test/projectsV2/7/views' "$GH_TEST_LOG"; then
      printf '%s\n' '{"data":{"node":{"repositories":{"nodes":[{"nameWithOwner":"test/project"}]},"fields":{"nodes":[{"databaseId":5,"name":"Status"}]},"views":{"nodes":[]}}}}'
    else
      printf '%s\n' '{"data":{"node":{"repositories":{"nodes":[{"nameWithOwner":"test/project"}]},"fields":{"nodes":[{"databaseId":5,"name":"Status"}]},"views":{"nodes":[{"id":"view","name":"Board","layout":"BOARD","groupByFields":{"nodes":[{"name":"Status"}]}}]}}}}'
    fi
    ;;
  "api repos/test/project/rulesets") printf '%s\n' '[{"id":9,"name":"software-factory-development"}]' ;;
  "api repos/test/project/rulesets/9") printf '%s\n' '{"enforcement":"active","conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"]}},"rules":[{"type":"deletion"},{"type":"non_fast_forward"},{"type":"pull_request","parameters":{"required_approving_review_count":0}},{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"CI / verify"}]}}]}' ;;
  "api --method")
    case "$*" in
      *"PUT repos/test/project/contents/.github/workflows/ci.yml"*) exit 0 ;;
      *"POST users/test/projectsV2/7/views"*) exit 0 ;;
      *"POST orgs/test/projectsV2/7/views"*) exit 0 ;;
      *) printf 'unexpected mutating API call: %s\n' "$*" >&2; exit 90 ;;
    esac
    ;;
  *) printf 'unexpected gh call: %s\n' "$*" >&2; exit 90 ;;
esac
EOF
chmod +x "$FAKE_BIN/gh"

set -e

: > "$LOG"
PATH="$FAKE_BIN:$PATH" GH_TEST_LOG="$LOG" "$CONFIGURE" --owner test --repo project --project-title Development >/dev/null
[ ! -s "$LOG" ] || fail "dry run called GitHub"

: > "$LOG"
PATH="$FAKE_BIN:$PATH" GH_TEST_LOG="$LOG" "$CONFIGURE" --owner test --repo project --project-title Development --apply >/dev/null
if grep -Eq 'repo create|project create|field-create|--method POST' "$LOG"; then
  fail "idempotent apply attempted a creation"
fi

: > "$LOG"
PATH="$FAKE_BIN:$PATH" GH_TEST_LOG="$LOG" GH_TEST_MODE=no-ci "$CONFIGURE" --owner test --repo project --project-title Development --apply >/dev/null
grep -q 'PUT repos/test/project/contents/.github/workflows/ci.yml' "$LOG" || fail "missing CI starter was not created"

: > "$LOG"
PATH="$FAKE_BIN:$PATH" GH_TEST_LOG="$LOG" GH_TEST_MODE=no-board "$CONFIGURE" --owner test --repo project --project-title Development --apply >/dev/null
grep -q 'POST users/test/projectsV2/7/views' "$LOG" || fail "user-owned Status board used the wrong endpoint"

: > "$LOG"
PATH="$FAKE_BIN:$PATH" GH_TEST_LOG="$LOG" GH_TEST_MODE=no-board GH_TEST_OWNER_TYPE=Organization "$CONFIGURE" --owner test --repo project --project-title Development --apply >/dev/null
grep -q 'POST orgs/test/projectsV2/7/views' "$LOG" || fail "organization-owned Status board used the wrong endpoint"

: > "$LOG"
set +e
PATH="$FAKE_BIN:$PATH" GH_TEST_LOG="$LOG" GH_TEST_MODE=conflict "$CONFIGURE" --owner test --repo project --project-title Development --apply >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 1 ] || fail "conflicting Project was not rejected"
if grep -Eq 'project link|--method POST' "$LOG"; then
  fail "conflict caused a later mutation"
fi

: > "$LOG"
set +e
PATH="$FAKE_BIN:$PATH" GH_TEST_LOG="$LOG" GH_TEST_MODE=limit "$CONFIGURE" --owner test --repo project --project-title Development --apply >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 1 ] || fail "saturated Project lookup did not fail closed"
if grep -Eq 'project create|project edit|project link|--method POST' "$LOG"; then
  fail "saturated Project lookup caused a mutation"
fi

printf 'ok - project configuration dry-run and conflict safety\n'
