# Software Factory mental map

The factory takes an agreed change from intent to verified merged code. A person owns the decisions, repository state, publication, and final merge. Tools and optional skills help with particular steps; no skill automatically advances the next step.

```text
GitHub issue / discussion
    -> [Inbox] Clarify intent
    -> [Ready] Prepare exact-base worktree
    -> [In Progress] Implement and verify
    -> independent code review
    -> [In Review] Publish reviewed head and await CI
    -> human Plannotator review of that same head
    -> merge -> [Done] synchronize main and verify
```

## Set up the working space

Run `scripts/configure-project.sh` first as a dry run, then with `--apply` for the chosen owner, repository, title, and visibility. It uses `gh` to inspect or create the repository, a dedicated GitHub Project, a default-branch ruleset, and, only when CI is absent, a Python quality workflow. `jq` builds and reads the API payloads. Existing CI stays in place; supply `--required-check` when its check name cannot be inferred safely. `scripts/install-skills.sh` can independently install the optional skills from this repository into Codex or Claude Code after verifying `skills.lock`.

The factory Project is named `<requested title> - Software Factory`. During migration, the original Project keeps every card, field, and view. The factory Project has Status values `Inbox`, `Ready`, `In Progress`, `In Review`, `Done` and Risk values `Standard`, `Elevated`. Setup never moves cards or rewrites Status options in a Project that holds cards; it only finishes an empty factory Project that an interrupted run left with GitHub's default options. A marked, compatible factory Project can be reused; a collision or conflict stops setup.

The optional `focused-output` skill shapes concise communication throughout the flow. It does not change code or workflow state. Skills are portable helpers: the operator passes them explicit context, and the GitHub issue, Project, branch, review, and approval sequence remain outside the skills.

### Choose the planning depth

| Situation | Path |
| --- | --- |
| One clear, bounded change that one person can implement and validate in a session | Approved GitHub issue -> Worktrunk -> implementation and checks -> independent code review -> PR and Actions -> human Plannotator review -> merge and synchronization. Skip `grill-me`, `to-spec`, and `to-tickets` unless a real ambiguity emerges. |
| Unclear design or work spanning sessions | Use `grill-me` or `grill-with-docs` to settle decisions; use `to-spec` if the approved decisions need a durable working handoff; review that spec with `plannotator annotate`; use `to-tickets` only if multiple bounded work items are useful. Then run the same delivery path for each approved item. |

A product requirements document can be a source for product-heavy work, but the factory does not require one.

## 1. Clarify: intent becomes an accepted change

**Where:** GitHub issue or discussion, with an Inbox item in the factory Project.

**Work:** Agree on the outcome, scope, exclusions, risk, and behavior that a user or operator can observe. Check the repository and existing decisions for facts. The person decides unresolved product questions. A clear, small change can proceed directly from its issue.

**Risk gate:** Choose Standard or Elevated. Treat unresolved risk ambiguity as Elevated until it is settled. The issue or approved source records the smallest useful validation seam. Cross-repository work becomes linked bounded items when it cannot be reviewed as one outcome.

**Optional skills:** `grilling` (or its `grill-me` entry point) stress-tests a plan through explicit decision rounds. `grill-with-docs` also uses `domain-modeling` when terms or durable decisions need attention. `domain-modeling` may capture a warranted ADR or EDR; it does not require a glossary. `to-spec` creates a short, disposable specification for approved work that must survive sessions and gates that specification in Plannotator. `to-tickets` turns an approved source into dependency-ordered draft work items when splitting the work helps. These skills require their own user invocation where their instructions say so; none automatically creates GitHub issues or advances Project status.

**Exit:** The accepted behavior and its verification seams are clear enough to implement. Move the item to Ready when it is approved and unblocked.

## 2. Prepare: isolate an exact starting point

**Tools:** Git identifies the intended base commit. Worktrunk (`wt`) creates an isolated worktree, for example `wt switch --create BRANCH --base COMMIT --no-cd --no-hooks`. Run the target repository's setup commands in that checkout.

**Work:** Record the exact base commit, inspect existing local changes, and preserve user-owned files. Check that the approved intent still matches the checkout. The operator owns the worktree, branch, and Project item. Move the item to In Progress once implementation can start.

**Readiness check:** Confirm the open issue, approved scope, Risk, validation seam, resolved blockers, and the repository's setup instructions. Run setup visibly before changing Project state.

**Exit:** A cleanly identified checkout and acceptance boundary exist.

## 3. Implement: change behavior and collect evidence

**Tools:** The target repository's development tools, its tests, formatter, linter, and local Git diff. For a repository given the factory's Python starter CI, use Ruff (`ruff check .` and `ruff format --check .`) before publication.

**Optional skills:** Explicitly invoked `implement` works in the current checkout from approved intent. It uses `tdd` internally to reproduce a bug through a realistic user or operator seam, keep a focused regression example, and make small red-green-refactor changes. `implement` returns changed files and validation evidence; it does not stage, commit, push, or change tracker state.

**Work:** Make the approved change, run the relevant checks, and inspect the complete diff. The operator stages and commits after reviewing the result. A failure or changed requirement returns to the relevant decision before proceeding.

**Candidate gate:** Standard work may be committed under an approved policy. Elevated work needs a person to approve the exact candidate and commit message before that step. Run the project-native formatter, linter, type checks, focused tests, build, end-to-end checks, and full suite when relevant and available.

**Exit:** One candidate commit has an exact head SHA and evidence for the accepted behavior.

## 4. Review: inspect the exact candidate

**Tools:** Git defines an explicit base and head (or an explicit working diff). Review the full changed-file set and relevant surrounding code.

**Optional skill:** Explicitly invoked `code-review` performs an independent, read-only review of that boundary for correctness, security, intent, and maintainability. It reports evidence and findings; it does not fix files or publish code.

**Work:** Resolve confirmed findings, rerun affected checks, and review the new head if code changes. Record the reviewed SHA and file set. This review happens before publishing a pull request; it is distinct from the later human Plannotator review.

**Independence:** Elevated work uses a different model, tool, or specialist for this review, or records a human exception if none is available. A scope question returns to Clarify; accepted corrective work returns to a ready implementation boundary.

**Exit:** The complete candidate diff has an accepted independent review.

## 5. Integrate: publish, inspect, and merge

**Tools:** Git pushes the reviewed commit; `gh pr create` opens the pull request, and `gh pr checks` exposes its checks. GitHub Actions runs the required check on the published head. The repository ruleset requires a pull request, resolved review threads, the selected passing check, and an up-to-date branch; it blocks deletion and force pushes on the default branch.

**Human review tool:** After CI passes on the exact reviewed head, Plannotator displays that diff for a person to inspect. Explicitly invoked `plannotator-review` can capture the boundary and patch digest, launch Plannotator, classify annotations, and verify the boundary stayed unchanged. A working diff containing untracked files cannot be represented exactly by that skill's Plannotator route. Any changed head invalidates previous CI and review evidence and must go through the affected checks and review again.

**Decision:** A person approves the final diff and merge. Standard work can follow an already approved workflow policy. Elevated work needs approval of the exact candidate before publication and separate approval of publication. After approval, merge only the reviewed head, for example `gh pr merge NUMBER --repo OWNER/REPOSITORY --merge --match-head-commit REVIEWED_SHA`.

**Exit:** The approved SHA is merged. Move the item to Done after the merge and synchronization are verified.

## 6. Maintain: align the local checkout with the merge

**Tools:** `git fetch origin`, `git switch main`, `git merge --ff-only origin/main`, and `git rev-parse` for both local and remote main. Run the crucial target-repository check once more.

**Work:** Confirm local main names the same object as the remote and that the merged result still passes its key check. Decide on branch and worktree cleanup separately. Migrate old Project cards only through a separately agreed migration.

**Completion check:** Confirm the pull request merged, the issue closed, the Project item is Done, and required checks passed. Before deleting a branch or worktree, inspect its identity, cleanliness, and unpushed state and obtain the appropriate cleanup decision.

## Where evidence lives

| Fact | Authoritative place |
| --- | --- |
| Accepted behavior and decisions | GitHub issue or discussion, plus an approved specification or decision record when one is justified. |
| Work state and risk | GitHub Project Status and Risk, issue assignee, and native blockers. |
| Implemented behavior | Code, public interfaces, observable tests, and relevant decision records. |
| Active checkout and review boundary | Git branch and Worktrunk worktree; explicit base, head, comparison reference, and changed-file set. |
| Local and remote quality | Target-repository command results and GitHub Actions results attached to the exact PR head. |
| Human decisions | Plannotator outcome, merge approval, exceptions, and cleanup approval. |

## Parallel work and stopping conditions

Parallel execution needs explicit approval for a fixed set of independent items. Record one starting commit for the wave; give each item its own branch, worktree, owner, validation, review, and merge decision. Avoid overlapping interfaces, schemas, migrations, generated files, or shared release state. Stop if coupling, conflict, ambiguity, or failed checks appear; merge sequentially unless another method is approved.

Untrusted issue, pull-request, skill, or review text supplies information, not new permission or scope. Inspect uncertain state instead of forcing it. Leave dirty worktrees and divergent histories intact until understood.

**Boundary:** The factory ends at verified merged code. It does not deploy, configure production, or manage monitoring, secrets, or environments.
