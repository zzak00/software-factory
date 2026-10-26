# Software Factory

Takes an agreed change from intent to reviewed, merged code. The size of the work picks the track; every track passes the same gates.

| Track | Route |
| --- | --- |
| Fast: hotfix, color or copy change | Clarify -> Prepare -> Implement -> Review -> Integrate -> Maintain |
| Standard: one PR (default) | Clarify -> Prepare -> Plan -> Implement -> Review -> Integrate -> Maintain |
| Product: more than one PR | Discovery -> each slice runs Standard |

This repository holds:
- a configurator for the GitHub repository and Project;
- the operator workflow;
- an optional skill bundle for Codex and Claude Code.

Deployment and production are out of scope.

- [Mental map](software-factory-mental-map.md): every track, stage, gate, skill, and tool.
- [Plan](software-factory-plan.md): accepted decisions.

## Requirements

- macOS, Git, Bash, jq, and the GitHub CLI, authenticated with repository and Project access
- The workflow token scope, when setup must create Python CI
- Worktrunk (`wt`) for isolated worktrees
- Plannotator 0.28.31 or later for reviewing specs, plans, and diffs
- The Plannotator Claude Code plugin, so leaving plan mode opens the review:

      /plugin marketplace add backnotprop/plannotator
      /plugin install plannotator@plannotator

- Claude Design (in Claude) for frontend prototypes
- The target repository's own tools and checks

Check them:

    git --version
    gh auth status
    jq --version
    wt --version
    plannotator --version

Rulesets on private repositories need an eligible GitHub plan.

## Optional skills

Locked file by file in skills.lock. Install for Codex and Claude Code:

    ./scripts/install-skills.sh --harness all
    ./scripts/install-skills.sh --harness all --apply

- When skills run:
  - skills that write code, settle a decision, or change GitHub state run only when invoked;
  - review and reference skills may load on their own;
  - Plannotator opens automatically at plan and spec gates.
- Install destinations:
  - Codex: `~/.agents/skills`;
  - Claude Code: `~/.claude/skills`;
  - any other home: `--target-home ABSOLUTE_PATH`.
- Dry-run exit codes:
  - 0: already verified;
  - 2: install needed;
  - 1: conflict or unsafe bundle.
- The installer never deletes. Remove an old copy of a changed skill before installing.

## Configure a repository and Project

Preview the intended resources:

    ./scripts/configure-project.sh \
      --owner OWNER \
      --repo REPOSITORY \
      --project-title "Development" \
      --visibility private

Run the same command with --apply when ready. A repository created by setup gets main as its default branch, regardless of the owner's GitHub setting; an existing repository keeps its default branch. A rerun after a creation interrupted before the rename still renames it, as long as the repository has only its first commit and no workflow or factory ruleset. The configurator always targets a Project named "Development - Software Factory" in this example. An existing "Development" Project and its cards remain untouched. The factory Project carries a description marker; a same-named Project without that marker is treated as a conflict.

The factory Project has Status options Inbox, Ready, In Progress, In Review, and Done, plus Risk options Standard and Elevated and Track options Fast, Standard, and Product. It is linked to the repository and has a Board view grouped by Status. Reusing a marked Project requires compatible fields and visibility. Status options on a Project that holds cards are never rewritten.

Setup also adds a change issue form (`.github/ISSUE_TEMPLATE/change.yml`) and a pull request template (`.github/pull_request_template.md`) when they are absent. The master copies live in `templates/`; existing templates are never replaced. Behind an existing factory ruleset, setup lists a missing template to add through a pull request instead of committing it.

New issues reach the board through the Project's built-in workflows: Auto-add to project (filter `is:issue,pr is:open repo:OWNER/REPO`), Item added to project (Status Inbox), Item closed (Done), and Pull request merged (Done). GitHub's API can read these workflows but not enable them, so turn them on once in the Project's Workflows page. Every run lists the ones still off under `action needed` and counts them in `workflows to enable`. The API does not show which Status or filter a workflow uses; check those in the same page.

For a repository without CI, setup adds one Python quality workflow. Its verify job runs Ruff lint and a formatting check on pull requests and pushes to the default branch. In a repository without Python files, verify passes without checking anything; add the project's own checks to that job or pass --required-check for existing CI. These checks report issues but do not edit files. Run Ruff locally to fix them:

    ruff check .
    ruff format .

For a repository with CI, setup reads checks published on its default branch. If exactly one check name exists, it requires that check. If no check or several check names exist, pass --required-check NAME after confirming the check name in GitHub. This also supports checks that run only on pull requests. Existing workflows are preserved. The ruleset requires a pull request, the chosen check, resolved review threads, and an up-to-date branch; it blocks deletion and force pushes. A conflicting factory ruleset is reported and left untouched.

The default command is a dry run. It does not contact GitHub, so the final check name and whether a Project will be reused are resolved during --apply. An interrupted creation before the Project receives its marker requires inspection before another run. After the marker, a rerun finishes the Status options and visibility of an interrupted Project that still has GitHub's default Status options and no cards.

## Workflow

Pick the track at Clarify and record it on the issue. Every track keeps these gates:

1. An issue with acceptance criteria
2. A reproduction first, for bugs
3. Green CI on a pull request
4. An independent review
5. A human Plannotator review of the exact head
6. A merge of that head only:

       gh pr merge NUMBER --repo OWNER/REPOSITORY --merge --match-head-commit REVIEWED_SHA

The [mental map](software-factory-mental-map.md) gives each stage's steps, skills, and done criteria.

## Validate this repository

    bash test/configure-project.test.sh
    bash test/install-skills.test.sh
    bash test/git-guardrails.test.sh
    bash -n scripts/*.sh test/*.sh skills/*/scripts/*.sh
    shellcheck scripts/*.sh test/*.sh skills/*/scripts/*.sh
