# Software Factory plan

## Purpose

A direct, reviewable path from accepted intent to merged code. It works without the optional skills or a mandatory application stack.

## Accepted setup decisions

- A factory Project is always separate from any existing Project. Its name is "<requested title> - Software Factory" and its description marks it for safe reuse.
- Existing cards and the Status options of any Project holding cards remain untouched. A marked factory Project that an interrupted run left empty with GitHub's default Status options gets its Status options and visibility on rerun. A collision with an unmarked Project or incompatible factory configuration stops setup.
- Read all Project fields before deciding whether Status or Risk exists. Incomplete results stop setup.
- A repository created by setup uses main as its default branch, also when a rerun finds it untouched (one branch, one commit, no workflow or factory ruleset) after an interrupted run. Any other existing repository keeps its default branch.
- When the target repository has no CI, add a single Python quality job running Ruff lint and formatting checks. CI reports findings and never commits fixes.
- When CI already exists, use one unambiguous published check or an explicitly selected check. Do not replace existing workflows.
- The factory ruleset protects the default branch. Conflicting existing rulesets are reported, not rewritten.
- Read every ruleset page before deciding one is absent. Reject a Project GraphQL result whose repository, field, or view connection has more pages, so a partial lookup cannot trigger a duplicate link or Board.
- The factory Project has a Track field (Fast, Standard, Product) beside Status and Risk, created and checked the same way as Risk.
- Setup adds the change issue form and pull request template from `templates/` only when absent, never replacing an existing template, and only before the factory ruleset requires pull requests.
- Agent skills are an optional, separately installed artifact kept in this repository. Their installer verifies exact lock coverage and refuses differing destinations. The mental map is Markdown, and this repository does not use npm.

## Accepted workflow decisions

| Decision | Detail |
| --- | --- |
| Three tracks | Fast, Standard, Product. Picked at Clarify; work moves up a track when it outgrows its own |
| Fixed gates | Issue with ACs, reproduction for bugs, green CI on a PR, independent review, Plannotator review of the exact head, `--match-head-commit` merge |
| Plan stage | Standard work only. Approved in Plannotator and recorded in the PR body, not committed |
| Product discovery | Parent issue holds the spec; slices are sub-issues with blockers; ADRs for one-way decisions; walking-skeleton first slice |
| Frontend | Claude Design prototypes are the visual reference. `/design-sync` keeps the design system in step. `verify-<app>` screenshots prove UI ACs |
| Invocation | Code, decisions, and GitHub changes are invoked only. Review and reference skills may load on their own. Plannotator opens at plan and spec gates |
| Skill bundle | Pinned upstream revisions with factory patches recorded in skills.lock. Python conventions live in each repo's CLAUDE.md |

## Verification and remaining boundary

The configurator is exercised against simulated GitHub responses for new and existing Projects, CI selection, incomplete fields, and ruleset conflicts. The optional skill installer is exercised for fresh, existing, and unsafe bundles. Repository CI runs those shell tests and ShellCheck. A live GitHub setup must be verified against the actual repository and Project before depending on the configured protections. Migration of cards from an older Project is a separate decision.
