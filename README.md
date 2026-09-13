# Software Factory

A portable set of standalone Bash scripts, pinned Agent Skills, and one
human-gated workflow for turning an idea into reviewed, merged code. It is not
an application or factory CLI.

> **Human control is mandatory.** Inspect before apply. Approve each assignment,
> status change, worktree, commit, push, pull request, merge, and cleanup
> separately. Entry skills are invoked only by the human.

## Install

Start by retaining the absolute path to this checkout for every later script:

```bash
cd /absolute/path/to/software-factory
factory_root=$(pwd -P)
```

The tested environment is macOS with Bash, Git, `jq`,
GitHub CLI 2.96.0, Phantom 6.2.0, Plannotator 0.27.12, Claude Code 2.1.236,
Codex 0.153.4, and Pi 0.84.4. Review newer versions before relying on them.

1. Install `gh`, `jq`, `phantom`, `plannotator`, and at least one harness using
   the host's normal package manager.
   Install the pinned Plannotator release with attestation verification when it
   is not already managed and verified declaratively:

   ```bash
   curl -fsSL https://plannotator.ai/install.sh |
     bash -s -- --minimal --version 0.27.12 --verify-attestation
   ```
2. Disable Plannotator sharing in the shell or declarative environment:

   ```bash
   export PLANNOTATOR_SHARE=disabled
   ```
3. Authenticate GitHub and verify that the token includes `repo` and `project`:

   ```bash
   gh auth status
   gh auth refresh -h github.com -s project
   ```
4. Inspect, approve, install, and recheck the pinned skills:

   ```bash
   "$factory_root/scripts/install-skills.sh" --harness all
   "$factory_root/scripts/install-skills.sh" --harness all --apply
   "$factory_root/scripts/install-skills.sh" --harness all
   ```

   Inspect exit `2` means installation is needed, `0` means the exact bundle is
   installed, and `1` means unsafe or conflicting state. The installer is
   offline and never replaces a differing skill. Use `--harness claude`,
   `codex`, or `pi` to select one harness, and `--target-home` for another home.
5. When using Pi, install its pinned command-permission layer the same way:

   ```bash
   "$factory_root/scripts/install-pi-permissions.sh"
   "$factory_root/scripts/install-pi-permissions.sh" --apply
   "$factory_root/scripts/install-pi-permissions.sh"
   ```

   It runs a frozen `npm ci` from the factory-owned
   [`package.json`](pi-extension-runtime/package.json) and complete
   [`package-lock.json`](pi-extension-runtime/package-lock.json), verifies the
   full graph, installs it under `~/.pi/agent/software-factory`, installs the
   policy in
   [`config/pi-permission-system.json`](config/pi-permission-system.json), and
   only then asks Pi to register the verified local extension. Existing Pi
   settings, packages, and policy are preserved. Package or policy drift causes
   exit `1` and must be reconciled manually.

   A failed frozen install leaves active Pi settings unchanged. If activation
   is interrupted after the runtime and policy are installed, rerun the same
   apply command: the verified runtime is reused and only local registration
   remains. If Pi settings became invalid during an external interruption,
   restore `~/.pi/agent/settings.json` from its declarative source or backup,
   inspect, and apply again. An older
   `npm:@gotgenes/pi-permission-system@...` registration must be backed up and
   removed explicitly before this installer will activate the local runtime.
   Never commit the installed npm runtime tree.

Never use permission-bypass flags, a global Plannotator hook, a global Phantom
harness preference, or a shell alias that adds unsafe options. Pi's extension
is a fail-closed permission decision layer, not operating-system isolation.
Review every Bash command it asks to run.

## Create the repository and board

The setup script is standalone, idempotent, and limited to the initial apply
pass. Start with inspection:

```bash
"$factory_root/scripts/setup-factory.sh" \
  --owner <owner> \
  --repo <repository> \
  --source /absolute/path/to/project \
  --project-title "<repository> Software Factory" \
  --visibility private
```

Exit `2` means the plan contains work, `0` means the initial state already
matches, and `1` means error, conflict, or ambiguity. After reviewing every
identifier and `PLAN` line, apply explicitly:

```bash
"$factory_root/scripts/setup-factory.sh" \
  --owner <owner> \
  --repo <repository> \
  --source /absolute/path/to/project \
  --project-title "<repository> Software Factory" \
  --visibility private \
  --apply
```

It creates or verifies the GitHub repository, exact `origin`, one private
GitHub Project, repository link, seven statuses, one Kanban view, and the
`factory:spec`, `needs-info`, and `wontfix` labels. It can initialize local Git
on `main`, but never stages, commits, pushes, deletes, or forces.

Use `factory:spec` for accepted specification content, `needs-info` for blocked
planning, and `wontfix` for an intentionally rejected item. Do not duplicate
Project statuses as labels.

It does **not** configure Project workflows, repository files, rulesets,
security, issues, worktrees, or harness execution. Rerun the same apply command
to prove idempotency.

## Establish the baseline

Before planning tickets, create the smallest real project baseline. Add the
initial application or library entry point, a README that names the crucial
local test command, at least one test that runs it, and
`.github/workflows/ci.yml` that runs the same command for pushes and pull
requests. Add project-specific ignore rules before credentials or generated
files appear. Run the documented formatter, linter, type checker, and crucial
test locally. Do not continue with a placeholder test or a CI workflow that has
never run.

Inspect all tracked and untracked baseline content before staging it:

```bash
cd /absolute/path/to/project
git status --short
git diff -- .
while IFS= read -r -d '' file; do
  git diff --no-index -- /dev/null "$file" || test $? -eq 1
done < <(git ls-files --others --exclude-standard -z)
```

After separate approval to stage, inspect the exact candidate commit and rerun
the crucial command:

```bash
git add --all
git diff --cached --check
git diff --cached --stat
git diff --cached
<project-crucial-test-command>
```

After separate approval of that diff, test evidence, and commit message:

```bash
git commit -m "Initialize project"
baseline_commit=$(git rev-parse HEAD)
git status --short
```

The empty status output is the local baseline gate. After separate approval to
publish it, push and prove that the default branch names the exact commit:

```bash
git push --set-upstream origin main
remote_main=$(
  git ls-remote --heads origin refs/heads/main |
    awk 'NR == 1 { print $1 }'
)
test "$remote_main" = "$baseline_commit"
gh run list --branch main --commit "$baseline_commit" \
  --json databaseId,status,conclusion,url
gh run watch <workflow-run-id> --exit-status
```

Stop if the remote ID differs, more than one relevant CI run exists, or a
required check is missing. Inspect GitHub before retrying an uncertain push.
Only a verified default-branch commit with passing CI may become a ticket
starting point.

## Sources of truth

| Concern                        | Authority                                        |
| ------------------------------ | ------------------------------------------------ |
| Accepted intent and discussion | GitHub issue                                     |
| Lifecycle                      | GitHub Project `Status`                          |
| Dependencies                   | Native GitHub blocking relationships             |
| Active code                    | One Phantom worktree per ticket                  |
| Working specification          | Current session or ignored worktree file         |
| Domain language                | Code and tests, plus an optional scoped glossary |
| Lasting decisions              | Approved EDRs or ADRs                            |
| Review result                  | Checks and pull-request review                   |

Working specifications are disposable and need not enter Git history.
`CONTEXT.md`, a fixed specification template, and a mandatory issue hierarchy
are not required.

The board lifecycle is:

| Status              | Entry condition                                   |
| ------------------- | ------------------------------------------------- |
| `Triage`            | A new idea, bug, or change arrives                |
| `Planning`          | The human starts clarifying it                    |
| `Spec Ready`        | The intended behavior is approved                 |
| `Ready for Agent`   | Scope is executable and all blockers are resolved |
| `In Progress`       | One agent owns its verified worktree              |
| `In Review`         | The pull request and required checks are ready    |
| `Done`              | The issue is closed                               |

Use Project status, not labels, for lifecycle. Resolve item, Project, field, and
option IDs with `gh project item-list`, `gh project view`, and
`gh project field-list`, then make one explicit transition:

```bash
gh project item-edit \
  --id <item-id> \
  --project-id <project-id> \
  --field-id <status-field-id> \
  --single-select-option-id <status-option-id>
```

## Plan the work

Every item starts in `Triage`.

- For a bug or small change, establish current behavior, expected behavior, and
  one observable verification seam. Record accepted intent in the issue.
- For a big or unclear idea, move it to `Planning`, clarify actors, outcomes,
  constraints, exclusions, domain terms, and decisions, then split by valuable
  capabilities rather than technical layers.
- Keep the original big idea in `Planning` while independent sub-ideas advance.
- Record an EDR or ADR only for a consequential, surprising decision that is
  expensive or risky to reverse.
- Use an investigation ticket when one critical question needs evidence before
  implementation can be planned.

Select the smallest coherent sub-idea that fits one implementation session and
pull request. Use a working specification only when it must survive across
sessions. Split it into tickets only when one approved sub-idea still exceeds
one session.

### Entry skills

Only the human invokes these entries. The harness must not select or chain them.
Internal `grilling`, `domain-modeling`, and `tdd` dependencies may run after the
chosen entry starts.

| Entry                  | Use it for                                                  |
| ---------------------- | ----------------------------------------------------------- |
| `grill-me`           | Clarify an idea without durable domain documentation        |
| `grill-with-docs`    | Shape a big idea that may produce durable domain decisions  |
| `to-spec`            | Produce and review a disposable cross-session specification |
| `to-tickets`         | Split one approved specification into buildable tickets     |
| `implement`          | Implement one claimed ticket test-first                     |
| `code-review`        | Review one committed ticket from a fresh session            |
| `plannotator-review` | Return human diff annotations to that review session        |

| Harness     | Entry syntax         | Installed location   |
| ----------- | -------------------- | -------------------- |
| Codex       | `$implement`        | `~/.agents/skills` |
| Pi          | `/skill:implement`  | `~/.agents/skills` |
| Claude Code | `/implement`        | `~/.claude/skills` |

Replace `implement` with another entry name as needed. Planning approval never
authorizes issue creation or implementation. Ask separately before publishing
issues, relationships, specifications, or durable domain records.

## Prepare tickets

Each ticket must deliver an observable vertical outcome, fit one worktree and
pull request, contain acceptance criteria and validation commands, and cite its
approved intent. Create dependencies only when they truly block starting:

```bash
gh issue edit <blocked-issue> \
  --repo <owner>/<repository> \
  --add-blocked-by <blocker-issue>
```

Add an approved issue to the Project with `gh project item-add`. Move it to
`Ready for Agent` only when it is open, approved, scoped for one session, has a
clear verification seam, and has no unresolved blocker. If any readiness check
fails, return it to planning. Parent and sub-issue relationships are optional.

## Implement one ticket

Ask separately before each mutation:

1. Assign the approved owner.
2. Fetch without changing the local default branch, then capture and verify the
   exact ticket starting commit:

   ```bash
   git fetch origin main
   ticket_base=$(git rev-parse refs/remotes/origin/main)
   test "$(git rev-parse refs/heads/main)" = "$ticket_base"
   git status --short
   ```

   Stop unless the local default branch is clean and equals the fetched remote.
3. After separate approval, create one isolated worktree from that default
   branch:

   ```bash
   phantom github checkout <issue-number> --base <default-branch>
   ```

   Native Git is an optional local-only alternative when Phantom is
   unavailable. Approve the exact path and branch separately, then anchor it to
   the already verified commit:

   ```bash
   git worktree add \
     -b issues/<issue-number> \
     /absolute/path/to/worktree \
     "$ticket_base"
   ```

   This command does not assign the issue, update Project status, push the
   branch, or authorize any later publication. Use the same verification and
   human gates below. Do not use the native alternative if the branch or
   worktree path already exists or differs from the approved ticket identity.
4. Verify its path, branch, clean state, and starting commit before changing
   Project status:

   ```bash
   git -C /absolute/path/to/worktree status --short
   test "$(git -C /absolute/path/to/worktree rev-parse HEAD)" = "$ticket_base"
   git -C /absolute/path/to/worktree branch --show-current
   ```
5. Before trusting the worktree with Pi, report every project setting, project
   permission policy, and agent `permission:` frontmatter that could override
   the global policy:

   ```bash
   "$factory_root/scripts/verify-pi-worktree.sh" \
     --worktree /absolute/path/to/worktree
   ```

   Exit `0` means no project override was found, `2` means every listed file
   must be reviewed before trust, and `1` means the target is unsafe or
   malformed. Run this check again whenever trusted `.pi` files change.
6. Move the Project item to `In Progress`.
7. Start a fresh writable harness in that worktree and invoke `implement`.

For Codex, use `workspace-write` with on-request approval. Never use
`danger-full-access` or `--ask-for-approval never`. Pi's interactive shape is:

```bash
phantom exec <worktree> \
  pi --no-session --tools read,edit,write,bash,grep,find,ls
```

On the first real ticket, verify the effective policy interactively in that
exact worktree before implementation. Ask Pi to use `read` on `README.md` and
confirm it proceeds without a permission prompt. Ask it to run `pwd` with Bash
and confirm the permission dialog requires a human decision. Ask it to read
`.env` and confirm the operation is denied. Stop if allow, ask, and deny do not
match those outcomes; recheck the global policy and every override reported by
`verify-pi-worktree.sh`.

`implement` reproduces current behavior, adds only crucial behavior-first tests,
implements within the approved seams, runs repository quality checks and the
complete suite, then shows the exact diff, evidence, and commit message. It may
commit only after explicit approval. That approval does not authorize review,
push, pull-request creation, or status changes.

After the commit, exit the writable session. It must not review its own work or
delegate review to a subagent.

## Run independent tickets in parallel

A parallel wave is optional and fixed before it starts. Every candidate must be
open, approved, unblocked, in `Ready for Agent`, and independent in code
ownership, APIs, schemas, migrations, generated files, and release state.
Dependent tickets wait for a later unblocked frontier.

Before starting, show each ticket, independence evidence, owner, harness,
worktree, common default-branch commit, validation, and integration risk. The
human approves the complete ticket set. Then use one agent and one worktree per
ticket, either in separate user-started sessions or as explicitly requested
bounded workers. A coordinator may collect results, but cannot discover or
refill work, edit a ticket worktree, change Project state, or invoke review.

Commit and review gates remain per ticket. Merge sequentially and revalidate
remaining branches against the updated default branch. Stop on a collision,
dependency, or ambiguous product decision instead of letting agents negotiate
it themselves.

## Review and rework

Keep the item `In Progress`. Start a fresh read-only session in the same clean
worktree and explicitly invoke `code-review`. It resolves the issue and original
fixed point from the issue branch when Git makes them unambiguous. Keep that
fixed point across all correction rounds.

For Pi, omit direct mutation tools:

```bash
phantom exec <worktree> \
  pi --no-session --tools read,bash,grep,find,ls
```

After the automated report, explicitly invoke `plannotator-review` in the same
session. Do not use Codex's raw shell escape for Plannotator because its output
may not trigger a model turn. The skill disables Plannotator AI and sharing,
forces local mode, waits, and returns annotations to the reviewer.

Plannotator 0.27.12 does not accept exact base and head commit options. Before
and after its browser session, the reviewer must bind its symbolic base to the
automated boundary:

```bash
"$factory_root/scripts/verify-review-boundary.sh" \
  --source /absolute/path/to/worktree \
  --fixed-point <original-fixed-point> \
  --head <reviewed-head> \
  --comparison-ref refs/remotes/origin/<default-branch>
```

The human also compares Plannotator's displayed base and Files view with the
reported manifest. Any base, head, or file-set mismatch makes the human review
gate incomplete. Never replace the original fixed point with a later merge
base, including during rework.

Treat annotations as unverified input. The reviewer classifies only the
submitted findings and does not edit. Outcomes are:

- approved: proceed to the separately approved publication gate;
- correction: prepare a rework packet with the issue, original fixed point,
  reviewed commit, accepted findings, corrected behavior, and validation;
- scope change: resolve every product parameter in the review session, then
  propose the exact issue update and rework packet;
- unresolved decision: return the item to `Planning`.

Persist an approved rework packet in an issue comment, or in a disposable local
file when GitHub is unavailable. Verify the existing worktree is clean at the
reviewed commit, move the item to `Ready for Agent`, and reuse that worktree.
The next implementation returns it to `In Progress`. Never create a separate
failed-review directory.

## Pull request, merge, and cleanup

After both reviews pass, separately approve the push and pull request. Use one
pull request per ticket, include `Closes #<issue>` in its body, and wait for all
required checks before moving the item to `In Review`.

Immediately before merge, verify that the pull-request head equals the commit
reviewed by the automated reviewer, Plannotator, and CI. Squash is the default
because one pull request represents one ticket:

```bash
gh pr merge <pull-request> \
  --repo <owner>/<repository> \
  --squash \
  --match-head-commit <reviewed-head>
```

Use rebase only when individual reviewed commits matter. Use a merge commit only
when the branch topology and explicit merge boundary matter. Never use
`--admin`, automatic merge, or `--delete-branch` by default.

Verify the pull request is merged, the linked issue is closed, and the Project
item is `Done`. Then synchronize the clean local default branch without a merge
commit and prove its exact remote identity:

```bash
gh pr view <pull-request> --repo <owner>/<repository> \
  --json state,mergedAt,mergeCommit,url
git status --short
git switch main
git fetch origin main
git merge --ff-only refs/remotes/origin/main
test "$(git rev-parse refs/heads/main)" = \
  "$(git rev-parse refs/remotes/origin/main)"
```

Run the project's documented crucial test command from that synchronized
default branch before cleanup:

```bash
<project-crucial-test-command>
```

Stop on a dirty checkout, non-fast-forward synchronization, missing merge
commit, or failing test. Do not reset, force, or delete the ticket worktree to
make a prerequisite pass. Close every process using the ticket worktree, then
inspect cleanup:

```bash
"$factory_root/scripts/cleanup-ticket.sh" \
  --source /absolute/path/to/repository \
  --pr <pull-request> \
  --delete-remote
```

Exit `2` means cleanup is planned, `0` means already complete, and `1` means
unsafe or ambiguous. After approval:

```bash
"$factory_root/scripts/cleanup-ticket.sh" \
  --source /absolute/path/to/repository \
  --pr <pull-request> \
  --apply \
  --delete-remote
```

The script verifies exact refs, clean worktrees, and the single configured
`origin` push destination, then removes the worktree, local branch, and optional
matching remote branch. Remote deletion uses an explicit expected-commit lease,
so a branch advanced after final inspection is preserved. It never uses
unconditional force or changes GitHub issues, Projects, pull requests, or the
default branch. A partial run can be inspected and safely repeated.

## Required repository protections

Before adopting the factory for important work, configure the default branch to
require pull requests and required CI checks, block force pushes and deletion,
restrict bypass, and enable available secret and security scanning. Team
repositories should require an eligible human approval. A solo repository must
not require an approval its sole maintainer cannot supply.

> These protections are not configured by `setup-factory.sh` and do not yet
> have a factory apply script. Verify them directly in GitHub before relying on
> the repository for production work.

## Recovery

At any interrupted transition, inspect both sides before retrying. Never use a
force push, hard reset, branch deletion, or a second worktree as recovery.

| Situation                                     | Safe response                                                                                              |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Setup stopped after partial creation          | Rerun setup inspection, resolve only reported conflicts, approve the new complete plan, then apply         |
| Baseline stopped before commit                | Inspect `git status`, unstaged diff, and cached diff; preserve the index and resume only after approval     |
| Baseline commit exists but push is uncertain  | Compare `HEAD` with `git ls-remote`; push only when the remote is absent or still at the known prior commit |
| CI stopped or no run appeared                 | Inspect `gh run list` and the workflow file; do not create tickets until the exact baseline run passes     |
| Worktree creation stopped partway through     | Inspect `git worktree list --porcelain`, branch refs, and the expected base; reuse only one exact result    |
| Skill or Pi installer reports drift           | Preserve the installation and settings; reconcile the named file manually before retrying                 |
| Pi activation stopped after runtime install   | Inspect again and rerun apply; restore invalid settings from their declarative source or backup            |
| Ticket becomes ambiguous or blocked           | Stop and return it to `Planning`; do not guess                                                              |
| Review comparison no longer matches the base  | Keep the original fixed point and report the human gate incomplete; never accept a narrowed diff           |
| Review requests changes                       | Keep and requeue the same clean worktree with a verified rework packet                                     |
| Merge outcome is uncertain                    | Inspect the pull request and remote default OID before any retry or synchronization                         |
| Default branch will not fast-forward          | Preserve both histories and resolve why they diverged; do not reset or force                               |
| Worktree has uncommitted or unpushed work     | Preserve it; cleanup must refuse deletion                                                                  |
| Cleanup fails partway through                 | Inspect again and rerun the approved command; the remote deletion lease preserves newer work               |
| GitHub is unavailable                         | Stop external mutations; use verified local evidence only where the skill permits                          |

## Compatibility status

| Harness             | Verified boundary                                                                                |
| ------------------- | ------------------------------------------------------------------------------------------------ |
| Codex 0.153.4       | Skill discovery, implementation, rework, automated review, and Plannotator feedback loop         |
| Claude Code 2.1.236 | Skill discovery and implementation                                                               |
| Pi 0.84.4           | Skill discovery, permission installation, policy verification, and headless fail-closed behavior |

Pi's complete interactive ticket flow and Claude Code's complete review flow
remain unverified. Do not claim full harness interchangeability until each has
completed the same end-to-end workflow.

## Maintain the factory

- `README.md` is the single operator guide.
- `.gitattributes` excludes the development plan and progress tracker from
  archives created with `git archive`; crucial tests remain distributable.
- Script `--help` output is authoritative for flags and exit behavior.
- [`skills.lock`](skills.lock) records vendored skill provenance, patches, and
  file hashes.
- `skills/setup-factory` remains checkout-only because it requires the adjacent
  setup script and this guide. It ships in the portable archive and is covered
  by `skills.lock`, but `install-skills.sh` does not copy it into user-level
  harness directories. Initial setup uses the direct commands above.
- [`pi-permissions.lock`](pi-permissions.lock) records the Pi extension,
  runtime manifest and lock hashes, and policy hash. The complete dependency
  sources, versions, and integrities are in
  [`pi-extension-runtime/package-lock.json`](pi-extension-runtime/package-lock.json).
- Claude Code and Pi use `disable-model-invocation: true` for user-only entry
  skills. Codex uses `policy.allow_implicit_invocation: false` in
  `agents/openai.yaml`. Do not apply those controls to internal dependencies.
- `docs/software-factory-plan.md` and
  `docs/software-factory-progress.md`, together with
  `docs/software-factory-review-remediation-plan.md`, are development records
  and must not ship in the final distribution.
- Audit every upstream change at an immutable revision, review dependencies and
  permissions, obtain approval, update hashes, and rerun the relevant E2E.

Run the crucial local checks after changing factory artifacts:

```bash
cd "$factory_root"
bash test/setup-factory.test.sh
bash test/install-skills.test.sh
bash test/install-pi-permissions.test.sh
bash test/verify-pi-worktree.test.sh
bash test/review-boundary.test.sh
bash test/cleanup-ticket.test.sh
bash test/factory-workflow.test.sh
bash test/locks.test.sh
bash test/archive.test.sh HEAD
bash -n scripts/*.sh test/*.sh test/fakes/*
shellcheck scripts/*.sh test/*.sh test/fakes/*
```

After committing the reviewed release state, create the portable archive with:

```bash
git -C "$factory_root" archive \
  --format=tar.gz \
  --prefix=software-factory/ \
  --output=/tmp/software-factory.tar.gz \
  HEAD
```

Inspect the archive before publishing it. It must contain the README, scripts,
skills, locks, configuration, and crucial tests, but no development records.

## Third-party licenses

Factory-authored files are licensed under the root [`LICENSE`](LICENSE), using
the MIT License with copyright held by Software Factory contributors.

The exact redistributed files and local modifications are recorded in
[`skills.lock`](skills.lock).

<details>
<summary>MIT License for mattpocock/skills</summary>

```text
MIT License

Copyright (c) 2026 Matt Pocock

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Source: [`mattpocock/skills`](https://github.com/mattpocock/skills), commit
`3cca18b368ae95cdbdebbff572ccafa662551015`.

</details>

<details>
<summary>MIT License for backnotprop/plannotator</summary>

```text
MIT License

Copyright (c) 2025 backnotprop

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Source: [`backnotprop/plannotator`](https://github.com/backnotprop/plannotator),
release `v0.27.12`, commit
`96313ab228ede843203d38d9d2a86e1c87e18c81`. The upstream project offers MIT
or Apache-2.0; this distribution uses MIT.

</details>

The factory installs but does not redistribute
[`@gotgenes/pi-permission-system`](https://github.com/gotgenes/pi-packages/tree/pi-permission-system-v31.1.3/packages/pi-permission-system),
pinned to version `31.1.3` and commit
`cf99c19b2cad9d26f6c4d0b9dc464c7fde0fab18`. It is MIT-licensed. Exact runtime
dependencies and integrity values are recorded in
[`pi-extension-runtime/package-lock.json`](pi-extension-runtime/package-lock.json),
while [`pi-permissions.lock`](pi-permissions.lock) records the pinned source
provenance and factory-file hashes.
