# Build the Focused Software Factory

## Outcome

Build a lean codebase-only factory around:

`Clarify -> Prepare -> Implement -> Review -> Integrate -> Maintain`

The deliverable includes workflow-agnostic skills, a concise runbook and mental
map, offline Codex and Claude installation, automated reusable GitHub project
configuration, critical repository validation and CI, and a disposable
end-to-end pilot.

Deployment, production operations, monitoring, rollback, and product lifecycle
management remain out of scope.

## Implementation checklist

- [x] Capture the starting commit, dirty-tree inventory, and file hashes.
- [x] Create `build/focused-software-factory` without discarding local work.
- [x] Decouple the reusable skill contracts and update their UI metadata.
- [x] Add the concise operator README.
- [x] Restore the safe offline skill installer.
- [x] Add reusable GitHub repository and Project configuration.
- [x] Add only the critical repository and integration tests.
- [x] Add the package manifest and generated dependency lockfile.
- [x] Refresh `skills.lock` descriptions and hashes.
- [x] Run local validation and inspect the complete diff.
- [ ] Obtain independent code and Plannotator review before committing.
- [ ] Run the approved disposable GitHub pilot.

## Repository changes

### Retain the simplification

- Keep the current removal of setup, cleanup, permission, and review-boundary
  automation.
- Keep the Pi runtime and permission configuration removed.
- Keep the `setup-factory` coordinating skill removed.
- Keep the old seven-state documentation and tests removed.
- Add `software-factory-mental-map.html` to version control.
- Track this implementation plan as `software-factory-build-plan.md`.
- Do not add `docs/software-factory-contract.md` or another policy document.

### Add a concise operator README

Create `README.md` with:

- purpose, supported environment, and boundaries;
- prerequisite and capability checks;
- skill installation and safe upgrade instructions;
- automated GitHub repository and Project configuration;
- compact and extended planning routes;
- commands and human gates for every development phase;
- Standard and Elevated risk behavior;
- rework, synchronization, and cleanup procedures.

Update the mental map so the workflow-owned commit appears between
implementation and independent review. Keep `.gitattributes` minimal and keep
the expanded third-party notices in `LICENSE`.

## Reusable skill changes

### Unchanged skills

- `focused-output`
- `grill-me`
- `grill-with-docs`
- `grilling`
- `domain-modeling`
- `tdd`, retained as the internal test-first dependency of `implement`

### `to-spec`

- Input: approved intent, scope, exclusions, decisions, and verification seams.
- Produce a concise disposable working specification.
- Review a materialized specification with
  `plannotator annotate <path> --gate --json --require-approval`.
- Return the approved specification or a precise unresolved-decision stop.
- Remove labels, Project fields, issue publication, and lifecycle transitions.

### `to-tickets`

- Input: an approved plan or specification and any caller-provided sizing rule.
- Produce draft-only, tracker-neutral work items.
- Each item contains title, outcome, scope, exclusions, acceptance criteria,
  validation evidence, dependencies, and source trace.
- Validate requirement coverage and an acyclic dependency graph.
- Remove GitHub publication, Project mutations, fixed session duration,
  worktree requirements, and pull-request assumptions.

### `implement`

- Input: current checkout, approved behavior, exclusions, verification seams,
  and known project commands.
- Inspect repository instructions and preserve user-owned work.
- Reproduce current behavior, load internal `tdd`, implement vertical slices,
  and run project-native checks.
- Output changed files, acceptance evidence, command results, uncertainty, and
  an optional multi-session handoff.
- Remove ticket status, assignment, GitHub, branch, worktree, commit, and review
  sequencing requirements.
- Never commit. The calling workflow owns staging and commits.

### `code-review`

- Require an explicit committed range or explicit working-diff boundary.
- Committed input is an explicit base and head.
- Working input selects staged, unstaged, untracked, or combined state.
- Review correctness, security, accepted intent, and maintainability read-only.
- Output severity-ranked findings, acceptance coverage, commands run, skipped
  checks, and residual uncertainty.
- Remove ticket inference, branch conventions, Project state, GitHub mutations,
  Plannotator dependency, and workflow handoffs.

### `plannotator-review`

- Become a standalone read-only code-review skill.
- Accept the same explicit boundary forms as `code-review`.
- For committed work, use an explicit base with `--diff-type since-base`.
- For working changes, use the matching explicit diff type.
- Hash the complete diff and file manifest before and after review.
- Return structured approval or annotations without assuming another skill,
  tracker, or workflow.

Update affected `agents/openai.yaml` descriptions to match these contracts.

## Installation and verification

Restore a simplified `scripts/install-skills.sh`:

```text
install-skills.sh
  --harness all|codex|claude
  --target-home <absolute-path>
  --apply
  --help
  --version
```

The installer must:

- install the complete locked bundle into `.agents/skills` and
  `.claude/skills`;
- include `focused-output`;
- verify every source file against `skills.lock`;
- run as a dry-run by default;
- never overwrite, merge, or delete a differing installation;
- return `0` when verified or applied, `2` when installation is needed, and
  `1` for unsafe or conflicting state;
- contain no Pi or workflow-automation behavior.

Add only the critical verification surface:

- `package.json` and generated lockfile using Node 24, `html-validate` 11.16.0,
  and a YAML parser;
- one repository test covering the locked bundle, hashes, required skill
  metadata, forbidden workflow coupling, and valid mental-map HTML;
- one installer integration test covering dry-run, apply, idempotency, harness
  selection, and refusal to overwrite a conflict without partial mutation;
- one macOS GitHub Actions job running dependency installation, the two test
  suites, Bash syntax checking, and ShellCheck.

Avoid duplicative tests for implementation details. Test only safety boundaries
and behavior whose failure could distribute the wrong skills, overwrite user
files, reintroduce workflow coupling, or leave the documented artifact invalid.

Update `skills.lock` patch descriptions and hashes only after all skill and
metadata edits are final. Require exact coverage of every distributed file.

## Reusable project configuration

Add `scripts/configure-project.sh` as the factory's only project-provisioning
automation. It must configure a caller-selected GitHub repository and Project
without embedding any application-specific workflow.

Interface:

```text
configure-project.sh
  --owner <user-or-organization>
  --repo <repository-name>
  --project-title <title>
  --visibility private|public
  --apply
```

Behavior:

- dry-run by default, printing the exact repository, Project, fields, ruleset,
  labels, and files it would create or update;
- create or reuse the selected repository and Project;
- link the repository to the Project;
- configure `Status` as Inbox, Ready, In Progress, In Review, and Done;
- configure `Risk` as Standard and Elevated;
- group the default Project view by `Status`;
- configure the default branch to require pull requests and the repository's
  native CI while blocking force pushes and deletion;
- install a minimal development-only CI starter only when the target repository
  has no CI workflow, leaving existing project-native CI unchanged;
- be idempotent and verify the resulting configuration after applying;
- stop on ambiguous matches, insufficient GitHub scopes, unsupported ruleset
  access, or any conflict that would overwrite project-owned configuration;
- perform no deployment, environment, secret, production, or monitoring setup.

Keep this script direct and bounded. Do not add a daemon, state store, workflow
engine, automatic merger, or generic control plane. Record reusable defaults in
plain data beside the script only if the implementation proves they are needed.

Add one focused integration test with a fake `gh` command for dry-run,
idempotent apply, and conflict refusal. Do not test every GitHub response shape.

## Execution sequence

1. Record the complete current dirty-tree inventory and hashes.
2. Preserve every existing modification and deletion.
3. Create a dedicated implementation branch in the current checkout because
   the uncommitted work cannot safely move to a new worktree.
4. Implement the repository, skill, installer, project configurator, critical
   tests, and documentation changes.
5. Run all local validation.
6. Review the complete diff against the original `main` fixed point.
7. Present the exact candidate and commit message before committing.
8. Reauthenticate GitHub CLI for `zzak00` with `repo` and `project` scopes.
9. Install Worktrunk through Homebrew and verify `--create`, `--base`,
   `--no-cd`, and `--no-hooks`.
10. Verify Plannotator supports `--base`, `--diff-type`, `--json`,
    `--no-git-remote-check`, and strict annotation gates.
11. After approval, archive conflicting installed skills and install the locked
    bundle for Codex and Claude.

## Disposable pilot

Use `scripts/configure-project.sh --apply` to create and configure the private
repository and Project `software-factory-pilot-20260926`. Verify the five Status
values, two Risk values, repository link, grouped view, ruleset, and CI before
creating pilot work.

Seed the repository with a minimal vanilla website with locked dependencies and
native format, lint, test, build, and browser checks. This application seed is
pilot data, not a template imposed on future projects.

Exercise the compact Standard route:

- Create one issue changing the primary button token from blue to approved
  purple.
- Define hover, focus, disabled, responsive, and contrast expectations.
- Skip grilling, specification, and ticket breakdown.
- Codex implements and Claude reviews.

Exercise the extended route:

- Use `grill-me` to define a system/light/dark theme selector.
- Use `to-spec` and approve the specification in Plannotator.
- Use `to-tickets` to draft:
  1. Accessible theme selection with immediate application.
  2. Persistence with invalid-value fallback to system.
- Publish the approved drafts with direct GitHub commands.
- Make persistence blocked by theme selection.
- Claude implements the first ticket and Codex reviews it.
- Use the opposite pairing for the second ticket.

For each ticket:

1. Create the exact-base worktree with
   `wt switch --create <branch> --base <commit> --no-cd --no-hooks`.
2. Run project setup explicitly.
3. Move through the five statuses with direct GitHub commands.
4. Let the workflow commit after `implement` returns evidence.
5. Run independent `code-review` before publication.
6. Open the pull request and wait for exact-head CI.
7. Run `plannotator-review` on that exact head.
8. Merge only the reviewed commit.
9. Fast-forward local `main`, compare object IDs, and rerun the crucial check.
10. Request approval before branch or worktree cleanup.

Also run:

- one isolated rework drill with a known seeded defect that cannot merge until
  corrected;
- one Elevated dry-run proving candidate and publication gates stop without
  approval;
- evidence preservation before any pilot resource deletion.

## Completion criteria

- All critical checks pass locally and in GitHub Actions.
- The tracked plan reflects all accepted Plannotator feedback.
- The mental map passes desktop, narrow-width, keyboard, reduced-motion, print,
  and no-JavaScript review.
- No retained skill requires factory statuses, GitHub Projects, Worktrunk,
  branch naming, approval order, or another workflow skill, except internal
  `implement` to `tdd` loading.
- `to-tickets` performs no tracker mutation and supports bounded multi-session
  work.
- `implement` performs no commit or tracker mutation.
- `code-review` handles committed and working boundaries.
- `plannotator-review` verifies exact boundaries before and after review.
- Critical installer tests pass for fresh, idempotent, selective, and
  conflicting cases.
- The project configurator provisions and verifies a new reusable development
  repository and Project without touching deployment or production concerns.
- Every distributed file matches `skills.lock`.
- Compact, extended, cross-agent review, rework, Elevated, CI, Plannotator,
  merge, synchronization, and cleanup scenarios succeed.
- No deployment, production, monitoring, rollback, daemon, scheduler, database,
  workflow engine, automatic merger, or coordinating skill is introduced.

## Assumptions and gates

- V1 supports one expert operator on macOS, GitHub.com, Codex, Claude Code,
  Worktrunk, and Plannotator.
- Current file deletions are the intended removal of the old architecture.
- No migration of the old seven-state Project is required.
- A PRD is optional input. Use a working specification only when decisions must
  survive across sessions.
- Standard work may be committed and published under approved workflow policy.
- Elevated work requires exact-candidate approval and separate publication
  approval.
- Tool installation, replacement of installed skills, external GitHub changes,
  publishing, merging, and deletion each retain their explicit approval gates.
