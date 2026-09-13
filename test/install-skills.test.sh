#!/usr/bin/env bash

set -euo pipefail

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
install_script="$project_root/scripts/install-skills.sh"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/install-skills-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_status() {
  expected=$1
  actual=$2
  context=$3
  [[ "$actual" -eq "$expected" ]] ||
    fail "$context returned $actual, expected $expected"
}

fresh_home="$test_root/fresh-home"
mkdir -p "$fresh_home"

set +e
"$install_script" --target-home "$fresh_home" >"$test_root/inspect-output" 2>&1
command_status=$?
set -e
assert_status 2 "$command_status" 'fresh inspect'
[[ ! -e "$fresh_home/.agents" ]] || fail 'inspect mode created .agents'
[[ ! -e "$fresh_home/.claude" ]] || fail 'inspect mode created .claude'

"$install_script" --target-home "$fresh_home" --apply >"$test_root/apply-output" 2>&1

for destination in "$fresh_home/.agents/skills" "$fresh_home/.claude/skills"; do
  for skill_name in grill-me grill-with-docs grilling domain-modeling to-spec to-tickets implement tdd code-review plannotator-review; do
    [[ -f "$destination/$skill_name/SKILL.md" ]] ||
      fail "missing installed skill: $destination/$skill_name"
  done
  [[ ! -e "$destination/setup-factory" ]] ||
    fail "checkout-only setup-factory skill was installed in $destination"

  grep -Fqx 'disable-model-invocation: true' "$destination/grill-me/SKILL.md" ||
    fail "grill-me is not user-only in $destination"
  grep -Fqx 'disable-model-invocation: true' "$destination/grill-with-docs/SKILL.md" ||
    fail "grill-with-docs is not user-only in $destination"
  grep -Fqx 'disable-model-invocation: true' "$destination/to-spec/SKILL.md" ||
    fail "to-spec is not user-only in $destination"
  grep -Fqx 'disable-model-invocation: true' "$destination/to-tickets/SKILL.md" ||
    fail "to-tickets is not user-only in $destination"
  grep -Fqx 'disable-model-invocation: true' "$destination/implement/SKILL.md" ||
    fail "implement is not user-only in $destination"
  grep -Fqx 'disable-model-invocation: true' "$destination/code-review/SKILL.md" ||
    fail "code-review is not user-only in $destination"
  grep -Fqx 'disable-model-invocation: true' "$destination/plannotator-review/SKILL.md" ||
    fail "plannotator-review is not user-only in $destination"
  grep -Fq "placed in \`In Progress\`" "$destination/implement/SKILL.md" ||
    fail "implement does not require the claimed In Progress state in $destination"
  if grep -Fq "placed in \`Ready for Agent\`" "$destination/implement/SKILL.md"; then
    fail "implement retains the stale Ready for Agent entry state in $destination"
  fi
  grep -Fq 'Never replace the original fixed point' "$destination/implement/SKILL.md" ||
    fail "implement does not preserve the original rework fixed point in $destination"
  grep -Fq 'refuse to perform or delegate it' "$destination/implement/SKILL.md" ||
    fail "implement does not enforce a separate review session in $destination"
  grep -Fqx '  allow_implicit_invocation: false' "$destination/grill-me/agents/openai.yaml" ||
    fail "grill-me is not explicit-only for Codex in $destination"
  grep -Fqx '  allow_implicit_invocation: false' "$destination/to-spec/agents/openai.yaml" ||
    fail "to-spec is not explicit-only for Codex in $destination"
  grep -Fqx '  allow_implicit_invocation: false' "$destination/to-tickets/agents/openai.yaml" ||
    fail "to-tickets is not explicit-only for Codex in $destination"
  grep -Fqx '  allow_implicit_invocation: false' "$destination/implement/agents/openai.yaml" ||
    fail "implement is not explicit-only for Codex in $destination"
  grep -Fqx '  allow_implicit_invocation: false' "$destination/code-review/agents/openai.yaml" ||
    fail "code-review is not explicit-only for Codex in $destination"
  grep -Fqx '  allow_implicit_invocation: false' "$destination/plannotator-review/agents/openai.yaml" ||
    fail "plannotator-review is not explicit-only for Codex in $destination"
  grep -Fq 'without spawning or delegating to another' "$destination/code-review/SKILL.md" ||
    fail "code-review does not enforce sequential review in $destination"
  grep -Fq 'fresh read-only' "$destination/code-review/SKILL.md" ||
    fail "code-review does not preserve the read-only boundary in $destination"
  grep -Fq "git reflog show --format='%H%x09%gs'" "$destination/code-review/SKILL.md" ||
    fail "code-review does not inspect the branch-creation reflog in $destination"
  grep -Fq 'git merge-base --all HEAD <default-branch-ref>' "$destination/code-review/SKILL.md" ||
    fail "code-review does not cross-check the default-branch merge base in $destination"
  grep -Fq 'plannotator-review' "$destination/code-review/SKILL.md" ||
    fail "code-review does not hand off to the explicit Plannotator entry in $destination"
  grep -Fq 'through the harness terminal execution tool' "$destination/plannotator-review/SKILL.md" ||
    fail "plannotator-review does not keep feedback attached to the session in $destination"
  grep -Fq 'Wait for it to finish' "$destination/plannotator-review/SKILL.md" ||
    fail "plannotator-review does not wait for returned feedback in $destination"
  grep -Fq 'request one-time human approval' "$destination/plannotator-review/SKILL.md" ||
    fail "plannotator-review does not request its bounded sandbox exception in $destination"
  grep -Fq 'PLANNOTATOR_AI=disabled' "$destination/plannotator-review/SKILL.md" ||
    fail "plannotator-review does not disable Plannotator AI in $destination"
  grep -Fq 'PLANNOTATOR_SHARE=disabled' "$destination/plannotator-review/SKILL.md" ||
    fail "plannotator-review does not disable sharing in $destination"
  grep -Fq 'PLANNOTATOR_REMOTE=0' "$destination/plannotator-review/SKILL.md" ||
    fail "plannotator-review does not force local mode in $destination"
  grep -Fq 'Scope change requested' "$destination/plannotator-review/SKILL.md" ||
    fail "plannotator-review does not preserve requested product changes in $destination"
  grep -Fq 'Ask the product question in this session' "$destination/plannotator-review/SKILL.md" ||
    fail "plannotator-review does not keep scope decisions in the review session in $destination"
  grep -Fq 'proposed issue-intent update' "$destination/plannotator-review/SKILL.md" ||
    fail "plannotator-review does not prepare the approved intent handoff in $destination"
  grep -Fq 'testable expected behavior without making another product decision' "$destination/code-review/SKILL.md" ||
    fail "code-review does not reject incomplete product decisions in $destination"
  grep -Fq 'testable expected behavior without making another product decision' "$destination/plannotator-review/SKILL.md" ||
    fail "plannotator-review does not reject incomplete product decisions in $destination"
  grep -Fq 'Never edit files or mutate' "$destination/plannotator-review/SKILL.md" ||
    fail "plannotator-review does not preserve the read-only boundary in $destination"
  if grep -Fqx 'disable-model-invocation: true' "$destination/tdd/SKILL.md"; then
    fail "tdd cannot be an internal dependency in $destination"
  fi
  if grep -Fqx '  allow_implicit_invocation: false' "$destination/tdd/agents/openai.yaml"; then
    fail "tdd cannot be an internal Codex dependency in $destination"
  fi
done

"$install_script" --target-home "$fresh_home" >"$test_root/idempotent-output" 2>&1
grep -Fq 'pinned factory skills verified' "$test_root/idempotent-output" ||
  fail 'idempotent inspect did not verify the installation'

conflict_home="$test_root/conflict-home"
mkdir -p "$conflict_home/.agents/skills/grill-me"
printf '%s\n' 'local skill' >"$conflict_home/.agents/skills/grill-me/SKILL.md"

set +e
"$install_script" \
  --harness codex \
  --target-home "$conflict_home" \
  --apply >"$test_root/conflict-output" 2>&1
command_status=$?
set -e
assert_status 1 "$command_status" 'conflicting apply'
grep -Fqx 'local skill' "$conflict_home/.agents/skills/grill-me/SKILL.md" ||
  fail 'conflicting skill was overwritten'
[[ ! -e "$conflict_home/.agents/skills/grilling" ]] ||
  fail 'installer mutated the destination after finding a conflict'

printf '%s\n' 'PASS: install-skills critical tests'
