---
name: setup-factory
description: Create or audit the initial GitHub repository and Project state for the software factory. Use when configuring the repository remote, linked Project, seven lifecycle statuses, Kanban view, and three factory labels. Do not use for repository artifacts, planning, workflows, rulesets, security settings, or implementation.
---

# Setup Factory

Prepare only the initial GitHub repository and Project state. Later skills and
separately approved scripts own every subsequent factory phase.

## Required procedure

Read [the repository and board section](../../README.md#create-the-repository-and-board)
of the operator guide before acting. Use `../../scripts/setup-factory.sh` for
deterministic setup. The script is standalone and does not depend on other
scaffold files.

If the script or operator guide is unavailable, stop and ask the human for the
software-factory scaffold location. Do not reconstruct the GraphQL mutations
from memory.

## Execution contract

1. Resolve the target checkout, GitHub owner, repository name, visibility, and
   exact Project title without guessing.
2. Run the script in inspect mode and show its output.
3. Ask for explicit human approval before rerunning with `--apply`.
4. Verify the repository, remote, Project link, Status options, Kanban view, and
   labels from authoritative GitHub queries.
5. Report the result and stop. Do not continue into later factory setup.

Approval for initial setup does not authorize Project workflow configuration,
repository file installation, commits, pushes, rulesets, security settings,
issues, planning, or implementation.

## Invariants

- Never delete a repository, Project, field, item, branch, or local file.
- Never force-push, overwrite repository files, or commit application content.
- Reuse exactly one Project with the exact requested title.
- Update the built-in Status field only when the Project is empty.
- Configure exactly `Triage`, `Planning`, `Spec Ready`, `Ready for Agent`,
  `In Progress`, `In Review`, and `Done`.
- Use only `factory:spec`, `needs-info`, and `wontfix` as initial factory labels.
- Keep lifecycle state in the Project Status field, not labels.
- Stop on authentication failures, collisions, ambiguity, or unexpected state.

## Completion report

Describe the result as initial setup, not a factory-ready repository. Report:

- repository and Project URLs;
- repository visibility and configured remote;
- Project number and the seven Status names;
- Kanban view and three label results;
- whether a second apply pass was a no-op;
- every unresolved item.

Explicitly list Project workflows, repository artifacts, rulesets, security
configuration, planning, and implementation as out of scope.
