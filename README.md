# Software Factory

A lightweight workflow for turning an agreed code change into reviewed, merged code:

Clarify -> Prepare -> Implement -> Review -> Integrate -> Maintain

The repository provides a GitHub Project configurator and an operator runbook. It also contains an optional skill bundle for Codex and Claude Code. The workflow works without installing those skills. Deployment and production operations are outside its scope.

See the [mental map](software-factory-mental-map.md) for the workflow at a glance and the [current plan](software-factory-plan.md) for the accepted setup decisions.

## Requirements

- macOS, Git, Bash, jq, and an authenticated GitHub CLI with repository and Project access
- Permission to write workflows when setup must create Python CI (the workflow scope for a classic token)
- Worktrunk for isolated worktrees
- Plannotator for human inspection of the final code diff
- The target repository's own development tools and checks

Check local capabilities with:

    git --version
    gh auth status
    jq --version
    wt --version
    plannotator --version

Private repository rulesets require an eligible GitHub plan. A ruleset failure must be resolved on GitHub before setup can complete.

## Optional harness skills

The skills in this repository are a separate artifact for local harnesses. Their source files are recorded in skills.lock. The offline installer verifies the lock and refuses to overwrite a differing installation. Preview, then install if you want to use them:

    ./scripts/install-skills.sh --harness all
    ./scripts/install-skills.sh --harness all --apply

Codex installs to ~/.agents/skills and Claude Code installs to ~/.claude/skills. Use --target-home with an absolute path to select another home directory. The dry run returns 0 when already verified, 2 when installation is needed, and 1 for a conflict or unsafe bundle.

## Configure a repository and Project

Preview the intended resources:

    ./scripts/configure-project.sh \
      --owner OWNER \
      --repo REPOSITORY \
      --project-title "Development" \
      --visibility private

Run the same command with --apply when ready. The configurator always targets a Project named "Development - Software Factory" in this example. An existing "Development" Project and its cards remain untouched. The factory Project carries a description marker; a same-named Project without that marker is treated as a conflict.

The factory Project has Status options Inbox, Ready, In Progress, In Review, and Done, plus Risk options Standard and Elevated. It is linked to the repository and has a Board view grouped by Status. Reusing a marked Project requires compatible fields and visibility. Existing Status options are never rewritten.

For a repository without CI, setup adds one Python quality workflow. Its verify job runs Ruff lint and a formatting check on pull requests and pushes to the default branch. These checks report issues but do not edit files. Run Ruff locally to fix them:

    ruff check .
    ruff format .

For a repository with CI, setup reads checks published on its default branch. If exactly one check name exists, it requires that check. If no check or several check names exist, pass --required-check NAME after confirming the check name in GitHub. This also supports checks that run only on pull requests. Existing workflows are preserved. The ruleset requires a pull request, the chosen check, resolved review threads, and an up-to-date branch; it blocks deletion and force pushes. A conflicting factory ruleset is reported and left untouched.

The default command is a dry run. It does not contact GitHub, so the final check name and whether a Project will be reused are resolved during --apply. An interrupted creation before the Project receives its marker requires inspection before another run.

## Development workflow

### Clarify

Record the outcome, scope, exclusions, risk, and observable acceptance criteria in an issue. Standard work with clear intent can proceed from that issue. For larger or uncertain work, settle decisions in discussion or a short working specification. Any external planning skill is optional.

### Prepare

Confirm the exact base commit, create an isolated worktree, and run that repository's setup commands:

    wt switch --create BRANCH --base COMMIT --no-cd --no-hooks

Move the Project item to In Progress when its checkout and requirements are ready.

### Implement

Change only the approved behavior. Reproduce bugs as close to the user experience as practical, add focused tests where they protect meaningful behavior, and run the target repository's checks. The operator owns staging and commits, regardless of which assistant or tool writes code.

### Review

Run an independent read-only code review against an explicit base and head, or an explicit working diff. Resolve findings against the complete change. Record the reviewed head and file set.

### Integrate

Push the reviewed commit, open the pull request, and wait for the required CI check on that exact head. Then inspect the CI-passing diff in Plannotator. If the head changes, rerun the affected checks and review. Merge only the approved head:

    gh pr merge NUMBER --repo OWNER/REPOSITORY --merge --match-head-commit REVIEWED_SHA

Standard work can proceed under an approved workflow policy. Elevated work needs approval of the exact candidate before publication and approval of publication itself. The final human diff review and merge decision remain separate.

### Maintain

After merge, fast-forward local main, verify it matches the remote object ID, and rerun the crucial target-project check:

    git fetch origin
    git switch main
    git merge --ff-only origin/main
    git rev-parse main
    git rev-parse origin/main

Branch and worktree cleanup are separate decisions. Keep both Projects during migration; move existing cards only through a separately agreed migration.

## Validate this repository

    bash test/configure-project.test.sh
    bash test/install-skills.test.sh
    bash -n scripts/*.sh test/*.sh
    shellcheck scripts/*.sh test/*.sh
