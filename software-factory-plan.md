# Software Factory plan

## Purpose

Provide a direct, reviewable path from accepted intent to merged code. Keep the factory usable without bundled agent skills or a mandatory application stack.

## Accepted setup decisions

- A factory Project is always separate from any existing Project. Its name is "<requested title> - Software Factory" and its description marks it for safe reuse.
- Existing cards and the Status options of any Project holding cards remain untouched. A marked factory Project that an interrupted run left empty with GitHub's default Status options gets its Status options and visibility on rerun. A collision with an unmarked Project or incompatible factory configuration stops setup.
- Read all Project fields before deciding whether Status or Risk exists. Incomplete results stop setup.
- When the target repository has no CI, add a single Python quality job running Ruff lint and formatting checks. CI reports findings and never commits fixes.
- When CI already exists, use one unambiguous published check or an explicitly selected check. Do not replace existing workflows.
- The factory ruleset protects the default branch. Conflicting existing rulesets are reported, not rewritten.
- Read every ruleset page before deciding one is absent. Reject a Project GraphQL result whose repository, field, or view connection has more pages, so a partial lookup cannot trigger a duplicate link or Board.
- Agent skills are an optional, separately installed artifact kept in this repository. Their installer verifies exact lock coverage and refuses differing destinations. The mental map is Markdown, and this repository does not use npm.

## Delivery sequence

1. Clarify the outcome, scope, risk, and acceptance criteria.
2. Prepare an exact-base isolated checkout.
3. Implement and run the target repository's checks.
4. Review the complete diff independently.
5. Publish the reviewed head and wait for CI.
6. Inspect the CI-passing head in Plannotator, then merge that exact head.
7. Synchronize the local default branch and verify the result.

## Verification and remaining boundary

The configurator is exercised against simulated GitHub responses for new and existing Projects, CI selection, incomplete fields, and ruleset conflicts. The optional skill installer is exercised for fresh, existing, and unsafe bundles. Repository CI runs those shell tests and ShellCheck. A live GitHub setup must be verified against the actual repository and Project before depending on the configured protections. Migration of cards from an older Project is a separate decision.
