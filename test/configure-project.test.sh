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
  "repo view")
    if [ "${GH_TEST_MODE:-ok}" = repo-error ]; then
      printf 'error: could not connect to github.com\n' >&2
      exit 1
    fi
    printf '%s\n' '{"visibility":"PRIVATE","defaultBranchRef":{"name":"main"}}'; exit 0
    ;;
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
  "project view")
    case "$*" in
      *.public*) printf '%s\n' "${GH_TEST_PROJECT_PUBLIC:-false}" ;;
      *) printf '%s\n' 'project-id' ;;
    esac
    ;;
  "project field-list")
    if [ "${GH_TEST_MODE:-ok}" = conflict ]; then
      printf '%s\n' '{"fields":[{"id":"status","name":"Status","options":[{"name":"Todo"}]}]}'
    elif [ "${GH_TEST_MODE:-ok}" = default-status ] && ! grep -q 'graphql --input' "$GH_TEST_LOG"; then
      printf '%s\n' '{"fields":[{"id":"status","name":"Status","options":[{"name":"Todo"},{"name":"In Progress"},{"name":"Done"}]}]}'
    else
      printf '%s\n' '{"fields":[{"id":"status","name":"Status","options":[{"name":"Inbox"},{"name":"Ready"},{"name":"In Progress"},{"name":"In Review"},{"name":"Done"}]},{"id":"risk","name":"Risk","options":[{"name":"Standard"},{"name":"Elevated"}]}]}'
    fi
    ;;
  "project link") exit 0 ;;
  "project field-create") exit 0 ;;
  "api graphql")
    if [ "${GH_TEST_MODE:-ok}" = no-board ] && ! grep -Eq 'POST (users|orgs)/test/projectsV2/7/views' "$GH_TEST_LOG"; then
      printf '%s\n' '{"data":{"node":{"repositories":{"nodes":[{"nameWithOwner":"test/project"}]},"fields":{"nodes":[{"databaseId":5,"name":"Status"}]},"views":{"nodes":[]}}}}'
    else
      printf '%s\n' '{"data":{"node":{"repositories":{"nodes":[{"nameWithOwner":"test/project"}]},"fields":{"nodes":[{"databaseId":5,"name":"Status"}]},"views":{"nodes":[{"id":"view","name":"Board","layout":"BOARD_LAYOUT","verticalGroupByFields":{"nodes":[{"name":"Status"}]}}]}}}}'
    fi
    ;;
  "api repos/test/project/rulesets")
    if [ "${GH_TEST_MODE:-ok}" = foreign-ci ]; then
      printf '%s\n' '[]'
    else
      printf '%s\n' '[{"id":9,"name":"software-factory-development"}]'
    fi
    ;;
  "api repos/test/project/rulesets/9") printf '%s\n' '{"enforcement":"active","conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"]}},"rules":[{"type":"deletion"},{"type":"non_fast_forward"},{"type":"pull_request","parameters":{"required_approving_review_count":0}},{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"verify"}]}}]}' ;;
  "api --method")
    case "$*" in
      *"PUT repos/test/project/contents/.github/workflows/ci.yml"*)
        if [ -n "${GH_TEST_CI_BODY:-}" ]; then cat > "$GH_TEST_CI_BODY"; fi
        exit 0 ;;
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
CI_BODY="$TEST_ROOT/ci-body.json"
PATH="$FAKE_BIN:$PATH" GH_TEST_LOG="$LOG" GH_TEST_MODE=no-ci GH_TEST_CI_BODY="$CI_BODY" "$CONFIGURE" --owner test --repo project --project-title Development --apply >/dev/null
grep -q 'PUT repos/test/project/contents/.github/workflows/ci.yml' "$LOG" || fail "missing CI starter was not created"
ci_yaml=$(jq -r '.content' "$CI_BODY" | base64 --decode)
printf '%s' "$ci_yaml" | grep -q 'git grep' || fail "CI starter is missing the conflict-marker check"
printf '%s' "$ci_yaml" | grep -q 'branches: \["main"\]' || fail "CI starter did not pin push to the default branch"
if printf '%s' "$ci_yaml" | grep -q 'git diff --check'; then
  fail "CI starter still uses the whole-repo whitespace scan"
fi

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

: > "$LOG"
set +e
PATH="$FAKE_BIN:$PATH" GH_TEST_LOG="$LOG" GH_TEST_MODE=foreign-ci "$CONFIGURE" --owner test --repo project --project-title Development --apply >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 1 ] || fail "foreign CI without an explicit check was not rejected"
if grep -Eq 'repo create|project list|project create|project edit|project link|--method POST' "$LOG"; then
  fail "foreign CI rejection caused a mutation"
fi

: > "$LOG"
set +e
PATH="$FAKE_BIN:$PATH" GH_TEST_LOG="$LOG" GH_TEST_MODE=repo-error "$CONFIGURE" --owner test --repo project --project-title Development --apply >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 1 ] || fail "repository inspection error was not fail-closed"
if grep -q 'repo create' "$LOG"; then
  fail "repository inspection error triggered creation"
fi

: > "$LOG"
set +e
PATH="$FAKE_BIN:$PATH" GH_TEST_LOG="$LOG" GH_TEST_PROJECT_PUBLIC=true "$CONFIGURE" --owner test --repo project --project-title Development --apply >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 1 ] || fail "conflicting Project visibility was not rejected"
if grep -Eq 'project edit|project create|--method POST' "$LOG"; then
  fail "visibility conflict caused a mutation"
fi

: > "$LOG"
set +e
out=$(PATH="$FAKE_BIN:$PATH" GH_TEST_LOG="$LOG" GH_TEST_MODE=default-status "$CONFIGURE" --owner test --repo project --project-title Development --apply 2>&1)
status=$?
set -e
[ "$status" -eq 0 ] || fail "untouched default Status options were not reconfigured (exit $status: $out)"
grep -q 'graphql --input' "$LOG" || fail "default Status options were not updated to the factory set"

printf 'ok - project configuration dry-run and conflict safety\n'
