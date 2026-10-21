# Software Factory

A lean, codebase-only development workflow for turning intent into reviewed,
integrated, maintainable code:

`Clarify -> Prepare -> Implement -> Review -> Integrate -> Maintain`

It supports macOS, GitHub.com, Codex, Claude Code, Worktrunk, and Plannotator.
It does not manage deployment, production, environments, monitoring, or
rollback.

## Choose the route

Use the compact route for a clear, low-risk change that fits one implementation
session. Record the outcome and acceptance evidence in one issue, then prepare,
implement, review, and integrate it.

Use the extended route when important decisions are unresolved or the work must
span sessions:

1. Use `grill-me` or `grill-with-docs` to settle intent.
2. Use `to-spec` only when a disposable cross-session specification helps.
3. Review that specification in Plannotator.
4. Use `to-tickets` only when the approved work benefits from decomposition.
5. Publish approved drafts through the project's own tracker workflow.

A PRD is optional. The approved issue can be the plan for compact work. A
disposable specification is the plan for extended work when decisions need a
stable cross-session artifact.

See [the mental map](software-factory-mental-map.html) for the complete routing
and [the build plan](software-factory-build-plan.md) for implementation scope.

## Prerequisites

- macOS with Git and Bash
- Node.js 24
- GitHub CLI authenticated with `repo` and `project` scopes
- Worktrunk
- Plannotator 0.27.20 or newer
- Codex, Claude Code, or both

Check capabilities directly:

```bash
git --version
node --version
gh auth status
wt --version
plannotator --version
plannotator review --help
```

## Install the skills

The installer is offline, verifies every source file against `skills.lock`, and
never overwrites a differing installation.

```bash
./scripts/install-skills.sh --harness all
./scripts/install-skills.sh --harness all --apply
```

The default is a dry run. Use `--target-home /absolute/path` to verify or install
against another home directory. Exit status `0` means verified or applied, `2`
means installation is needed, and `1` means input, source, or destination state
is unsafe.

For upgrades, review the repository diff and lock changes first. If an installed
skill differs, archive it outside the destination, rerun the dry run, then apply.
The installer never merges, deletes, or replaces it.

## Configure a project

Preview first:

```bash
./scripts/configure-project.sh \
  --owner OWNER \
  --repo REPOSITORY \
  --project-title "Development" \
  --visibility private
```

After checking the exact preview, add `--apply`. The configurator creates or
reuses the repository and Project, links them, configures the five Status values
and two Risk values, and applies development-only branch protection. Existing
CI is preserved. When a repository has no workflow, the configurator adds a
minimal `verify` hygiene check before requiring it. It refuses to overwrite
incompatible existing configuration and never touches deployment, secrets,
environments, production, or monitoring.

## Development workflow

### Clarify

Record outcome, scope, exclusions, risk, and observable acceptance criteria.
Use `grill-me` only when assumptions or decisions need stress-testing.

### Prepare

Confirm the exact base commit. Create an isolated worktree directly:

```bash
wt switch --create BRANCH --base COMMIT --no-cd --no-hooks
```

Run the project's documented setup commands. Move the item to `In Progress`
only after the checkout and requirements are ready.

### Implement

Invoke `implement` with approved behavior, exclusions, verification seams, and
project commands. The skill edits and validates the current checkout but never
commits or changes tracker state. The workflow reviews its evidence, then owns
the commit.

### Review

Run `code-review` in a fresh read-only session with either an explicit base and
head or an explicit working-diff boundary. After automated findings are clear,
run `plannotator-review` against the same exact boundary. Any changed head or
file manifest invalidates prior approval.

### Integrate

Publish the reviewed commit, open the pull request, and wait for required checks
on that exact head. Standard work can proceed under an already-approved policy.
Elevated work stops for explicit candidate approval and a separate publication
approval. Merge only the reviewed commit.

### Maintain

Fast-forward local `main`, compare local and remote object IDs, and rerun the
crucial project check. Branch and worktree cleanup remain separate human
decisions.

## Rework

Keep the original comparison base. Review corrections as part of the complete
change, not only the latest patch. Reuse the existing worktree when safe. A
scope change returns to clarification and updates accepted intent before more
implementation.

## Validation

```bash
npm ci
npm test
bash -n scripts/*.sh test/*.sh
shellcheck scripts/*.sh test/*.sh
```

The checks cover only distribution integrity, skill boundaries, valid HTML, and
the destructive-risk boundaries of installation and project configuration.
