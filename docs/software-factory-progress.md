# Software Factory Progress

Last updated: 2026-09-11

This file records execution evidence for the build plan in
`docs/software-factory-plan.md`. A checked item means it was directly verified.

## Current checkpoint

- Phase: Review remediation - Final validation
- Step: Prepare the first reviewed source commit
- State: All six stages in
  `docs/software-factory-review-remediation-plan.md` are implemented. Focused
  regressions, the complete sequential factory workflow with rework, Bash
  syntax, ShellCheck, and lock verification pass locally on macOS. The release
  now has an MIT license, a macOS and Linux CI matrix, and an archive-content
  test. The first human-approved source commit was created and its portable
  archive passed content verification. Linux CI, the billed interactive Pi
  ticket flow, and a fresh human Plannotator UI pass remain external validation
  gates; compatibility claims do not include unproven paths.

## Phase 1

- [x] GitHub CLI authentication succeeds with the `project` scope.
  - Audit: `gh auth status` found active account `zzak00`, but its token is invalid.
  - Attempt: the HTTPS and web-browser login flow was started, but `gh` failed
    with `error connecting to github.com` before presenting a device code.
  - Human action: run `gh auth login -h github.com` in a local terminal with
    network access.
  - Verification: run `gh auth status`; if `project` is absent, run
    `gh auth refresh -h github.com -s project`, then check status again.
  - Follow-up: the user completed login, but the restricted agent environment
    could not retrieve the credential or reach GitHub to verify it directly.
  - Human verification: `gh auth status` reports account `zzak00` authenticated
    through the keyring with `gist`, `project`, `read:org`, `repo`, and
    `workflow` scopes.
- [x] Required executables are currently discoverable.
  - GitHub CLI: 2.96.0
  - Phantom: 6.2.0
  - Plannotator: 0.27.12
  - Claude Code: 2.1.236
  - Codex CLI: 0.153.4
  - Pi: 0.84.4
- [x] `PLANNOTATOR_SHARE` is `disabled` in the current shell.
- [x] No factory or harness selection override was found in the inspected
  environment variables or global Git configuration.
- [x] Phantom is declared in `homebrew.brews`.
  - Evidence: `/Users/zak/Desktop/dotfiles/configuration.nix` lists `"phantom"`
    in the `homebrew.brews` array.
- [x] The Plannotator privacy default is declared in Home Manager.
  - Evidence: `/Users/zak/Desktop/dotfiles/home.nix` sets
    `home.sessionVariables.PLANNOTATOR_SHARE = "disabled"`.
- [ ] Remove permission-bypass defaults from harness aliases before declaring
  Phase 1 complete.
  - `/Users/zak/Desktop/dotfiles/home.nix` alias `cc` uses
    `--dangerously-skip-permissions`.
  - The same file's `co` alias uses `--ask-for-approval never`.
  - Decision: the user chose to retain both aliases. This remains an explicit
    deviation from the Phase 1 acceptance criteria. Factory adapters must
    resolve the real executables and must not inherit either alias or its flags.
- [x] Confirm no global Plannotator plan-exit hook is installed.
  - Active Claude, Codex, and Pi configuration contains no Plannotator or exit
    hook entry.
  - No Plannotator-related Claude plugin is installed, and no global
    Plannotator configuration directory exists.
- [x] Rebuild the dotfiles and start a fresh login shell.
  - Human verification: the user confirmed this was already completed.
  - Supporting evidence: the current shell finds Phantom and exports
    `PLANNOTATOR_SHARE=disabled`.
- [ ] Verify the installed Plannotator release provenance.
  - Binary: `/Users/zak/.local/bin/plannotator`
  - Version: 0.27.12
  - Architecture: Mach-O arm64
  - SHA-256: `f0b2df2b55d95c96912891ce99b2bbdac918df2d6354c4a6649e55f84c5d7029`
  - The local installation contains no attestation receipt or release metadata,
    and the binary has no signing team identifier. Version pinning is verified,
    but the prior install's `--verify-attestation` use cannot be proven locally.
  - Decision: the user confirmed the existing 0.27.12 installation and chose
    not to reinstall it. Attestation verification remains unresolved.
- [x] Shared tools and all three intended harnesses report versions.
  - Verified versions are listed above, and GitHub authentication was verified
    separately from the user's unrestricted shell.
- [x] Validate the planned non-interactive command flags against installed CLI
  help and record executable resolution.
  - Claude Code resolves to
    `/opt/homebrew/Caskroom/claude-code/2.1.236/claude` and supports `--print`,
    text input, stream-JSON output, no session persistence, and tool controls.
  - Codex resolves to
    `/Users/zak/.npm-global/lib/node_modules/@openai/codex/bin/codex.js` and
    supports stdin prompts, workspace-write sandboxing, ephemeral sessions, and
    JSONL output.
  - Pi resolves to
    `/Users/zak/.npm-global/lib/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js`
    and supports print mode, JSON output, no session persistence, and an
    explicit tool allowlist.
  - Phantom resolves to its 6.2.0 installation and documents that `exec` runs
    inside the selected worktree and preserves the command exit code.
- [x] Record the initial invocation contracts supported by these versions.
  - Claude Code: `phantom exec <worktree> claude --print --input-format text
    --output-format stream-json --no-session-persistence`
  - Codex: `phantom exec <worktree> codex exec --sandbox workspace-write
    --ephemeral --json -`
  - Pi implementation: `phantom exec <worktree> pi --no-session --tools
    read,edit,write,bash,grep,find,ls`
  - Pi review: `phantom exec <worktree> pi --no-session --tools
    read,bash,grep,find,ls`
  - Claude and Codex prompts are supplied on standard input. Pi remains
    interactive so the user can invoke the entry skill and answer permission
    prompts. Operation-specific adapters must narrow tool permissions further
    where appropriate and never add bypass flags.
- [ ] Run a harmless stdin and exit-status smoke test through each harness.

## Later phases

- [ ] Phase 2 - Prove the direct path manually
  - [x] Create a dependency-free Python scratch project with passing unit and
    command-line tests plus a least-privilege GitHub Actions workflow.
    - Location: `/Users/zak/Desktop/scratch-project`
    - Decision: keep it as a separate companion repository rather than part of
      this scaffold.
  - [x] Document direct, human-gated repository creation and baseline
    verification in `docs/runbooks/repository-setup.md`.
  - [x] Publish the companion project as private repository
    `zzak00/scratch-project` and verify its first CI run from an unrestricted
    authenticated shell.
    - The earlier `zzak00/software-factory-e2e` repository was deleted by the
      user and is no longer part of the plan.
    - Local evidence: clean `main` tracks `origin/main`, whose remote is
      `https://github.com/zzak00/scratch-project.git`; commit `08e3cb0` is the
      initial Python project commit and both local tests pass.
    - Human verification: the repository is private and its baseline GitHub CI
      run succeeded.
  - [x] Document Project discovery, collision handling, creation, linking, and
    seven-status verification in `docs/runbooks/repository-setup.md`.
  - [x] Replace the web-only Status setup guidance with an idempotent JSON-driven
    CLI procedure in both setup runbooks. It fails closed unless the current
    field is already correct or the Project is empty and replacement is
    explicitly approved.
  - [x] Realign the plan and repository setup runbook after moving the Python
    project into a separate companion checkout named `scratch-project`.
  - [ ] Create or reuse the `Software Factory E2E` Project, link it to the
    scratch repository, and verify exactly seven statuses.
    - Project 5 exists. Its empty default Status field has ID
      `PVTSSF_lAHOBHnURs4BinTkzhherLY` and options `Todo`, `In Progress`, and
      `Done`.
    - The human approved replacing this empty field through the JSON-driven CLI
      procedure.
    - The agent environment stopped on its first read-only Project query with
      `unknown owner type` because it cannot access the user's GitHub keyring.
      No deletion or other GitHub mutation occurred.
    - Human-shell evidence disproved the initial replacement procedure: GitHub
      rejected deletion because the built-in Status field is not custom, then
      rejected creation because `Status` is reserved and already taken. No
      Project field changed.
    - The invalid delete-and-recreate procedure was removed from both runbooks.
      A read-only GraphQL schema inspection is required before an in-place
      update is proposed.
    - Live schema inspection confirmed `updateProjectV2Field` and
      `createProjectV2View` are available. The schema exposes only deletion for
      Project workflows, with no create, update, or enable mutation.
    - Decision: build one standalone Bash setup script with no pre-existing
      Project dependency. Its boundary ends after repository, Project, Status,
      Kanban, link, and label setup. Project workflows belong to later approved
      work.
- [x] Phase 3 - Build initial repository setup
  - Decision: no monolithic factory CLI will be built. The final result may be
    a small library of standalone scripts, pinned upstream skills, and docs.
    The current setup script owns only initial GitHub repository and Project
    state.
  - [x] Remove the temporary CLI, library, package manifest, and CLI tests.
  - [x] Add `docs/runbooks/prerequisites.md` with pinned tested versions,
    authentication, privacy, and safe harness command contracts.
  - [x] Reduce `scripts/setup-factory.sh` version 0.2.0 to inspect/apply modes
    for Git initialization, exact remote and repository setup, one linked
    Project, seven Status options, one Kanban view, and three factory labels.
  - [x] Remove workflow confirmation, repository artifact installation,
    commits, pushes, rulesets, required checks, and security configuration from
    the script.
  - [x] Remove the previously planned fixed spec skeleton. The audited upstream
    `to-spec` skill will own how clarified requirements become a working
    specification.
  - [x] Align `docs/runbooks/repository-setup.md` and the existing
    `setup-factory` skill with the initial-setup boundary.
  - [x] Remove the redundant scratch-specific E2E runbook after consolidating
    its reusable procedure into the canonical repository setup runbook.
  - [x] Keep one focused end-to-end suite covering inspect-only behavior, fresh
    apply, exact GraphQL payloads, no unrelated local writes, idempotent rerun,
    rejected legacy completion flags, API failure, and partial recovery.
  - [x] Run `shellcheck` on `scripts/setup-factory.sh`.
    - Human approved installing ShellCheck with Homebrew only. Do not modify
      the Nix configuration for this tool.
    - ShellCheck 0.11.0 ran successfully with no warning or error. It reported
      four informational SC2016 findings for intentionally single-quoted
      GraphQL variables.
    - Human approved four localized SC2016 suppression comments.
    - Final result: clean ShellCheck output, valid Bash syntax, and
      `PASS: setup-factory initial-setup tests` after the comments.
  - [x] Run the skill-creator `quick_validate.py` check with ephemeral PyYAML.
    - Decision: manage `uv` as a global Nix package in the separate dotfiles
      repository, then use an ephemeral `uv` environment for PyYAML.
    - The dotfiles change and `darwin-rebuild` must be performed from the
      user's unrestricted terminal because that repository is outside this
      workspace.
    - First rebuild completed but `uv` remained unavailable because the
      intended `uv` entry was not present in `home.packages` on disk.
    - The rebuild's managed Homebrew cleanup removed the one-off ShellCheck
      installation. Its completed validation result remains recorded above.
    - [x] Verify the corrected dotfiles edit: `uv` is now declared in
      `home.packages` immediately after `nodejs`.
    - [x] Verify the active Nix installation: `uv 0.11.21
      (aarch64-apple-darwin)`.
    - The sandboxed validator attempt could not resolve `pypi.org`, so PyYAML
      was not downloaded and no validation result was produced.
    - The user ran the same ephemeral validation command from an unrestricted
      terminal. Result: `Skill is valid!`, exit status `0`.
  - [x] Execute the revised script against a fresh disposable GitHub repository
    and verify the authoritative state before declaring Phase 3 complete.
    - Inspect evidence: version 0.2.0 inspected
      `/Users/zak/Desktop/scratch-project` for private repository
      `zzak00/scratch-project` and Project `Software Factory E2E`.
    - Result: exit status `2` with one planned repository-creation mutation and
      no applied changes.
    - [x] Human approved the apply pass.
    - Live result: the apply pass created private repository
      `zzak00/scratch-project`, verified its HTTPS `origin`, and created Project
      6, then exited `5` when the unlinked repository returned a null
      `projectsV2` value that the link check tried to iterate.
    - No Project link, Status update, Kanban view, or labels were reported after
      the failure.
    - [x] Reproduce the live null `projectsV2` response in the focused E2E test;
      the unmodified script exited `5` as observed live.
    - [x] Release script version 0.2.1 with a null-safe Project-link check.
    - [x] Verify Bash syntax, the null response expression, and the focused E2E
      suite. Result: `PASS: setup-factory initial-setup tests`.
    - [x] Reinspect the partial live state with version 0.2.1. It found the
      existing repository and Project 6, verified `origin`, and returned exit
      status `2` with planned Project-link and in-place Status updates.
    - Next gate: explicit human approval for the recovery apply, which will
      continue with the link, statuses, Kanban view, and labels.
    - [x] Human approved the recovery apply.
    - Recovery result: the script linked Project 6, updated and verified all
      seven statuses, created the Kanban view, and created `factory:spec` and
      `needs-info`.
    - Failure: GitHub's existing default `wontfix` label had a different
      description, so the script stopped with exit status `1` before changing
      it.
    - [x] Reproduce the default GitHub label in the focused E2E test; the
      unmodified script exited `1` as observed live.
    - [x] Release version 0.2.2 with exact, bounded reconciliation for only the
      three factory-owned labels and change-required exit status for inspect
      mode.
    - [x] Verify Bash syntax and the focused E2E suite. Result:
      `PASS: setup-factory initial-setup tests`.
    - [x] Reinspect the nearly complete live state. Statuses, Kanban, and the
      first two labels verified; `wontfix` correctly reported a planned update.
    - Unexpected result: the repository-side `projectsV2` value still appeared
      unlinked even though the preceding live mutation reported that Project 6
      was linked successfully.
    - [x] Query Project 6's documented `repositories` connection directly. It
      returned repository node `R_kgDOUQdr3g` with name
      `zzak00/scratch-project`, confirming the link exists.
    - [x] Reproduce the idempotency defect with a persistently null
      repository-side value; the second apply attempted a duplicate link and
      the focused E2E test exited `1`.
    - [x] Release version 0.2.3 using the documented Project-side
      `repositories` connection, with response validation and a fail-closed
      one-page bound.
    - [x] Verify Bash syntax and two idempotent apply passes in the focused E2E
      suite. Result: `PASS: setup-factory initial-setup tests`.
    - [x] Reinspect live state with version 0.2.3. Repository, origin, Project
      6, Project link, seven statuses, Kanban view, `factory:spec`, and
      `needs-info` all verified.
    - Remaining change: update only the existing `wontfix` description. Inspect
      returned the expected exit status `2`.
    - [x] Human approved the `wontfix` label update.
    - [x] Run the approved recovery apply. It verified every existing resource,
      updated only `wontfix`, printed Project URL
      `https://github.com/users/zzak00/projects/6`, and exited `0`.
    - Next gate: approval for one final apply rerun that must report only
      verified state and perform no mutation.
    - [x] Human approved the final idempotency rerun.
    - [x] Run the final apply rerun. Repository, origin, Project 6, Project link,
      seven statuses, Kanban view, and all three labels reported only existing
      or verified state; no mutation was reported and the script exited `0`.
    - Live initial apply and idempotency acceptance criteria are satisfied.
- [ ] Phase 4 - Audit and adopt upstream planning skills
  - [x] Remove the premature fixed output files. Audited upstream skills will
    define required content without factory-owned skeletons.
  - [x] Revise the plan after annotated review to define the result as a small
    portable library of scripts, skills, and docs rather than one setup script.
  - [x] Mark the plan and progress tracker as development-only files that must
    not ship in the installed library.
  - [x] Remove the prescribed work-item hierarchy and the separate preflight
    artifact from the planned workflow.
  - [x] Remove the requirement to commit or push working specifications. The
    revised plan keeps them beside active code as disposable workspace state.
  - [x] Research reusable public skills and select the AI Hero
    `mattpocock/skills` flow as the provisional baseline, subject to pinned
    source audit, E2E proof, licensing, and compatibility patches.
  - [x] Apply the second annotated review by removing the unwanted optional
    skill recommendations from the planned skill set and planning flow.
  - [x] Re-run Bash syntax checks and the focused setup E2E suite after removing
    the preflight-dependent Status description.
  - [x] Obtain human approval of the revised plan.
    - Human confirmation: "looks good to me"
  - [x] Audit the exact upstream planning and implementation skill sources and
    their transitive dependencies without copying or installing them.
    - `grill-with-docs` delegates to `grilling` and `domain-modeling`.
    - `to-spec`, `to-tickets`, `implement`, and `code-review` require bounded
      compatibility changes before they can preserve the factory's gates.
    - `tdd` depends on its testing references and `codebase-design` vocabulary.
  - [x] Correct the audit conclusion that durable domain records were unwanted.
    The user approved domain models and EDRs or ADRs as valuable long-lived
    knowledge for shaping big ideas.
  - [x] Add `docs/runbooks/planning.md` with separate bounded-item and big-idea
    paths, progressive capability splitting, artifact lifetimes, and explicit
    approval checkpoints.
  - [x] Pin and vendor the approved big-idea planning bundle at upstream commit
    `3cca18b368ae95cdbdebbff572ccafa662551015`, including its transitive skill
    dependencies, OpenAI metadata, format references, license, and file hashes.
  - [x] Approve explicit-only invocation for the two entry skills. The human
    invokes `grill-me` or `grill-with-docs`; those user-started flows may call
    `grilling` and `domain-modeling` internally.
  - [x] Validate the bundle's file hashes, entry-only invocation metadata, and
    entry-to-dependency composition. The native `grilling` and
    `domain-modeling` directories and Codex projections of both entry skills
    pass the official skill validator offline.
  - [x] Replace the two entry wrappers' Claude-specific Skill tool calls with
    harness-neutral dependency-loading instructions and update their locked
    hashes and compatibility records.
  - [x] Add `scripts/install-skills.sh` for offline, user-level installation in
    Claude Code, Codex, and Pi. Inspect mode is the default, apply is explicit,
    source hashes are verified, Codex and Pi share `.agents/skills`, and
    existing or unexpected skill content is never overwritten.
  - [x] Add and pass the critical installer tests for dry-run safety, complete
    installation in both native locations, explicit-only entry metadata,
    idempotent verification, and conflict refusal. Bash parsing and ShellCheck
    0.11.0 also pass.
  - [x] Run the live user-level inspect pass for all three harnesses. It planned
    four skills under `~/.agents/skills` for Codex and Pi and the same four
    under `~/.claude/skills` for Claude Code, performed no installation, and
    exited `2`.
  - [x] Install the pinned bundle in the real user-level harness directories.
    The human-run apply installed four skills under `~/.agents/skills` and
    `~/.claude/skills` and exited `0`. A subsequent inspect verified every
    installed file against `skills.lock` and exited `0` without mutation.
    Codex's implicit inventory exposes only the internal `grilling` and
    `domain-modeling` dependencies, not the two explicit entry skills.
  - [x] Prove a manually invoked planning entry flow outside this repository.
    The user ran it from the separate `scratch-project` checkout in a separate
    harness session and confirmed that it worked correctly.
  - [x] Audit upstream `to-spec` at the pinned revision before adoption.
    - The skill contains only `SKILL.md` and Codex interface metadata, has no
      scripts or transitive skill calls, and is already explicit-only.
    - The unmodified workflow conflicts with the approved factory because it
      requires a fixed specification template and root glossary, assumes the
      upstream setup skill, and automatically publishes an issue with a
      `ready-for-agent` label.
    - It has no disposable local-file or Plannotator feedback and cancellation
      path. It also says not to interview while separately requiring testing
      seam confirmation.
  - [x] Vendor the approved `to-spec` compatibility patch.
    - The patched skill preserves synthesis and high-level verification seams,
      uses no fixed template, does not require `CONTEXT.md`, and stops on
      material gaps instead of inventing decisions.
    - Materialization, Plannotator acceptance, tracker publication, labels,
      and Project status remain separate human gates. It never invokes the
      next skill automatically.
    - `skills.lock`, `docs/upstream-skills.md`, the planning runbook, and
      installer version 0.2.0 now include the patched explicit-only entry
      skill.
  - [x] Run the crucial local `to-spec` and installer checks.
    - Bash parsing and ShellCheck 0.11.0 passed.
    - The focused installer test passed for offline installation, explicit-only
      metadata, idempotent verification, and conflict refusal.
    - A temporary Codex projection passed the official skill validator offline.
  - [x] Run the live user-level inspect pass after adding `to-spec`.
    - All four existing skills verified against the lock in both
      `~/.agents/skills` and `~/.claude/skills`.
    - The installer planned only the missing `to-spec` entry skill in both
      locations and performed no write.
  - [x] Install `to-spec` in the real user-level harness directories.
    - The human-run apply verified the four existing skills, installed only
      `to-spec` under `~/.agents/skills` and `~/.claude/skills`, verified the
      completed bundle, and exited `0`.
  - [x] Prove `to-spec` safely skips unnecessary specifications.
    - In the separate scratch-project session, the manually invoked skill
      determined that the personalized greeting change fit one implementation
      session.
    - It identified the existing `greeting()` API and subprocess CLI as the
      verification seams, returned a focused implementation and test plan, and
      created or published no specification.
    - This validates the no-spec routing branch. It does not yet validate the
      disposable-file, Plannotator feedback, cancellation, or optional
      publication gates used for genuinely multi-session work.
  - [x] Audit upstream `to-tickets` at the pinned revision before adoption.
    - The skill contains only `SKILL.md` and Codex interface metadata, has no
      scripts or sub-agent calls, and is already explicit-only.
    - Its tracer-bullet slicing, dependency ordering, user review, and
      expand-contract exception are useful and retained.
    - The unmodified workflow assumes the upstream setup skill and root
      glossary, combines breakdown approval with publication, applies a
      `ready-for-agent` label, and does not integrate the factory's Project
      status or separate relationship approvals.
    - Its tracker-neutral relationship guidance has known GitHub failures and
      it lacks a complete source-coverage and dependency-graph check before
      publication. Installed GitHub CLI 2.96.0 provides native blocker,
      parent, sub-issue, and relationship-verification fields.
  - [x] Vendor the approved `to-tickets` compatibility patch.
    - The explicit-only skill safely skips one-session work, validates source
      coverage and the complete blocker graph, and requires vertical,
      observable, falsifiable tickets at approved verification seams.
    - Issue creation, Project insertion at `Spec Ready`, native blocking
      relationships, and optional parent relationships are distinct approval
      gates with partial-failure recovery evidence.
    - The skill never applies `ready-for-agent`, promotes a ticket to `Ready
      for Agent`, infers a hierarchy, or invokes implementation automatically.
    - `skills.lock`, `docs/upstream-skills.md`, the planning runbook, and
      installer version 0.3.0 now include this entry skill.
  - [x] Run the crucial local `to-tickets` and installer checks.
    - Bash parsing and ShellCheck 0.11.0 passed.
    - The focused installer test passed for the complete six-skill bundle,
      explicit-only metadata, idempotent verification, and conflict refusal.
    - A temporary Codex projection passed the official skill validator offline.
  - [x] Run the live user-level inspect pass after adding `to-tickets`.
    - All five existing skills verified against the lock in both
      `~/.agents/skills` and `~/.claude/skills`.
    - The installer planned only the missing `to-tickets` entry skill in both
      locations and performed no write.
  - [x] Install `to-tickets` in the real user-level harness directories.
    - The human-run apply verified the five existing skills, installed only
      `to-tickets` under `~/.agents/skills` and `~/.claude/skills`, verified
      the completed bundle, and exited `0`.
  - [x] Prove `to-tickets` safely skips unnecessary ticket splitting.
    - In the separate scratch-project session, the manually invoked skill
      determined that the approved greeting change fit one implementation
      session and one pull request.
    - It recommended retaining one existing issue and created no issues,
      Project items, labels, statuses, or relationships.
    - GitHub API access was unavailable in that harness environment, so it
      could not perform the optional duplicate-issue check. This did not affect
      the safe no-mutation result.
    - This validates the no-split routing branch. Real issue publication,
      Project insertion, partial recovery, and native relationship gates remain
      pending until genuinely multi-ticket work exists.
- [ ] Phase 5 - Complete implementation and review operations
  - [x] Audit upstream `implement` and its `tdd` dependency at the pinned
    revision before adoption.
    - `implement` contains only `SKILL.md` and Codex interface metadata. It is
      already an explicit-only entry skill and delegates implementation tests
      to `tdd` and the completed-work review to `code-review`.
    - `tdd` contains `SKILL.md`, Codex interface metadata, `tests.md`, and
      `mocking.md`. Its behavior-first public-interface tests, pre-agreed
      seams, vertical red-green slices, independent expected values, and
      boundary-only mocking are useful and should be retained.
    - The upstream ordering is unsafe: `implement` invokes `code-review`
      before committing, while `code-review` reviews
      `git diff <fixed-point>...HEAD`. The current uncommitted implementation
      can therefore be absent from the review, after which `implement`
      commits automatically without a human gate.
    - The upstream implementation flow also omits the factory's ticket
      readiness check, end-user reproduction, formatting, linting, relevant
      end-to-end validation, complete evidence summary, and explicit commit
      approval.
    - `tdd` optionally reads `CONTEXT.md` and uses a Claude-specific Skill tool
      call to load `codebase-design` when a seam is unresolved. That dependency
      can in turn prescribe three or more parallel sub-agents and additional
      `CONTEXT.md` use. A ready ticket must already have approved seams, so this
      design branch should stop for clarification instead of expanding the
      implementation session or delegating automatically.
    - `tdd` also postpones all refactoring to `code-review`. The compatibility
      patch should instead permit small behavior-preserving cleanup after each
      green test, followed by rerunning that focused test, so implementation
      reaches the commit gate in reviewable condition.
    - Proposed patch boundary: vendor `implement`, `tdd`, `tests.md`, and
      `mocking.md`; keep `implement` as the only explicit user entry; make
      `tdd` an internal dependency; require a clean isolated worktree and the
      approved readiness context; reproduce first; preserve focused vertical
      red-green-refactor slices and the final complete suite; add
      repository-defined quality and E2E checks; ask before the commit; then
      stop with evidence and instruct the human to invoke `code-review`
      separately in a fresh session. Do not vendor `codebase-design` for this
      path or invoke review automatically.
  - [x] Vendor the approved `implement` and `tdd` compatibility patch.
    - `implement` is an explicit-only manual entry that verifies a clean,
      isolated, non-default worktree and an open, assigned, unblocked `In
      Progress` ticket before editing.
    - It reproduces the current behavior first, loads `tdd` internally, limits
      work to approved seams, requires repository-defined quality and relevant
      end-to-end checks, and presents complete evidence before asking for
      commit approval.
    - After an approved commit it stops with the captured starting commit and
      tells the human to invoke `code-review` in a fresh session. It never
      reviews, pushes, opens a pull request, changes Project state, closes an
      issue, or removes a worktree automatically.
    - `tdd` preserves the pinned upstream test and mocking references, favors
      the fewest crucial behavior tests, removes `CONTEXT.md` and automatic
      design or delegation paths, and runs focused red-green-refactor slices.
    - Installer version 0.4.0, `skills.lock`, upstream compatibility docs, and
      third-party attribution include the complete eight-skill bundle.
  - [x] Complete the crucial local validation before installation.
    - Bash parsing and the focused installer test pass. The test verifies
      offline installation, exact locked contents, all five explicit-only
      entries, internal `tdd` availability, idempotency, and conflict refusal.
    - `implement`, through the established temporary Codex projection, and
      `tdd` both pass the official skill validator offline.
    - Source whitespace, prohibited em-dash, stale installer wording, and
      installer version checks pass.
    - ShellCheck was initially unavailable after the environment rebuild. The
      human installed it with Homebrew and verified the updated installer and
      test script with exit status `0`.
  - [x] Run the live user-level inspect pass after adding `implement` and
    `tdd`.
    - The installer verified the existing skills, planned only `implement` and
      `tdd`, made no writes, and exited `2` as expected.
  - [x] Install `implement` and `tdd` in the real user-level harness
    directories.
    - The human-run apply installed the missing skills, verified the complete
      pinned factory bundle, preserved the five-entry manual invocation list,
      and exited `0`.
  - [x] Verify the completed user-level installation is idempotent.
    - The human-run inspect reported the installed `tdd` dependency and the
      complete pinned factory bundle as verified, planned no writes, and
      exited `0`.
  - [x] Prove `implement` against one approved ticket in the separate Python
    scratch project.
    - Read-only local inspection found `/Users/zak/Desktop/scratch-project`
      clean on `main` at `08e3cb0be81c8fa549825867e17b93405479df54`,
      tracking the expected `zzak00/scratch-project` origin.
    - Only the base checkout exists. No isolated implementation worktree or
      non-default implementation branch has been created.
    - The restricted agent environment could not reach `api.github.com`, so it
      could not verify open issues, assignment, blockers, or Project status.
      No GitHub mutation was attempted.
    - The human's connected-shell query returned an empty open-issue list.
      There is therefore no ticket that can satisfy the implementation entry
      gate yet.
    - The current program exposes `greeting()` and `python3 hello.py`, with one
      unit test and one subprocess test for the fixed software-factory
      greeting. These are the existing verification seams for the approved
      personalized-greeting change.
    - The exact bounded issue draft was presented before creation. Its later
      Project insertion, readiness status, assignment, and worktree each
      remain separate steps.
    - The human approved the exact personalized-greeting issue title, outcome,
      acceptance criteria, and validation evidence. The approved creation has
      no labels, assignment, Project insertion, status change, relationships,
      or other mutation.
    - The connected-shell issue-creation attempt ended with exit status `130`,
      which indicates interruption. Whether the remote mutation completed is
      unknown, so no retry is allowed until a read-only exact-title query rules
      out partial success.
    - The human ran that exact-title query across all issue states. It returned
      no issue and exited `0`, proving the interrupted attempt made no remote
      change. Retrying the already-approved issue-only mutation is safe.
    - The safer `printf` pipeline created
      `https://github.com/zzak00/scratch-project/issues/1` with the exact
      approved content and exited `0`. It did not add labels, assignment,
      Project state, or relationships.
    - Read-only inspection resolved Project 6 as `Software Factory E2E` with
      node ID `PVT_kwHOBHnURs4BipPV` and confirmed issue 1 is not already a
      Project item.
    - The Project Status field is `PVTSSF_lAHOBHnURs4BipPVzhhgd8Y`, and its
      `Spec Ready` option is `f661c7c1`. Adding the issue and setting that
      status remain separate approved mutations.
    - The human approved adding issue 1 to Project 6 without changing its
      Status or performing any other mutation.
    - The connected-shell Project insertion created item
      `PVTI_lAHOBHnURs4BipPVzg5x3Bk` for issue 1 and exited `0`. The command did
      not explicitly change Status.
    - Read-only item inspection verified that the new Project item is in
      `Triage`. No assignment or other Project field was observed or changed.
    - The human approved changing only item
      `PVTI_lAHOBHnURs4BipPVzg5x3Bk` from `Triage` to `Spec Ready`.
    - The direct `gh project item-edit` command reported the expected item
      title and exited `0`. This is the first successful direct lifecycle
      transition evidence; the resulting status still requires a read-only
      check.
    - A separate connected-shell item query verified the item in `Spec Ready`
      and exited `0`. The `Triage` to `Spec Ready` direct transition is now
      proven end to end.
    - Read-only issue inspection verified issue 1 is open, unassigned, and has
      zero native `blockedBy` and `blocking` relationships. The accepted scope
      fits one implementation session and uses the existing `greeting()` and
      subprocess CLI seams.
    - The human approved implementing the exact issue scope and changing only
      its Project Status from `Spec Ready` to `Ready for Agent`.
    - The direct `gh project item-edit` readiness command reported the expected
      item title and exited `0`.
    - A separate connected-shell item query verified item
      `PVTI_lAHOBHnURs4BipPVzg5x3Bk` in `Ready for Agent` and exited `0`.
    - The human separately approved assigning issue 1 to the active GitHub
      user. No other issue or Project field change is included in that gate.
    - The connected-shell assignment command returned the issue URL and exited
      `0`. A separate read-only query is required before the issue is treated
      as claimed.
    - A separate connected-shell issue query verified issue 1 is open and its
      sole assignee is `zzak00`; the query exited `0`. The ticket is now
      claimed without changing its Project status or other fields.
    - Installed Phantom 6.2.0 documents `phantom github checkout <number>
      --base <branch>` for issues and creates an `issues/<number>` worktree and
      branch. The human approved creating that local isolated worktree for
      issue 1 from `main`; no push or GitHub field change is included.
    - Phantom reported worktree `issues/1` at
      `/Users/zak/Desktop/scratch-project/.git/phantom/worktrees/issues/1` and
      exited `0`.
    - Read-only Git checks verified that path as a registered worktree on branch
      `issues/1`, clean under porcelain v2 status, at starting commit
      `08e3cb0be81c8fa549825867e17b93405479df54`. The base checkout remains on
      `main` at the same commit.
    - The human separately approved changing only Project item
      `PVTI_lAHOBHnURs4BipPVzg5x3Bk` from `Ready for Agent` to `In Progress`.
      Starting the implementation harness is not part of this mutation.
    - The direct `gh project item-edit` command reported the expected issue
      title and exited `0`. A separate read-only Project query is required
      before the implementation session starts.
    - A separate connected-shell Project query returned item
      `PVTI_lAHOBHnURs4BipPVzg5x3Bk` with status `In Progress` and the expected
      issue URL. The user did not include the query's exit-status line, but the
      authoritative item payload verifies the requested field value.
    - The human chose Codex for the first implementation-flow proof and
      approved starting a fresh session inside the isolated worktree. The
      `implement` entry remains manually invoked and must stop at its commit
      gate.
    - Pre-launch inspection found a contract mismatch: the plan defines
      `Ready for Agent` as the pre-claim readiness state and `In Progress` as
      the state after worktree creation, but `skills/implement/SKILL.md`
      requires `Ready for Agent` at session start. Launching the installed
      skill now would correctly stop on its own stale guard. No harness was
      launched and no implementation file changed.
    - The human confirmed that `implement` belongs after assignment, isolated
      worktree creation, and the `In Progress` transition, and approved a
      narrow compatibility correction.
    - Installer version 0.4.1 now ships an explicit-only `implement` entry that
      requires an open, assigned, unblocked `In Progress` ticket in its clean
      isolated worktree. Its OpenAI metadata, compatibility documentation,
      locked hashes, and one focused regression assertion are aligned.
    - Bash parsing, clean ShellCheck, the focused installer test, and the
      official skill validator through a temporary Codex-compatible projection
      all pass. No additional test suite was added.
    - Read-only SHA-256 checks verified both live `implement` installations as
      exact version 0.4.0 copies, not user-modified content. Their source and
      metadata hashes match the previous lock values. The installer remains
      intentionally overwrite-safe, so refreshing those two copies requires a
      separately approved recoverable replacement.
    - The human approved moving only those exact old copies to a persistent
      backup and using installer 0.4.1 to recreate them. Backup deletion is not
      included and requires later verification and approval.
    - The connected-shell refresh moved both old directories to
      `/Users/zak/Desktop/implement-skill-0.4.0-backup`, installed only
      `implement` under `~/.agents/skills` and `~/.claude/skills`, verified the
      complete bundle internally, and exited `0`. The backup remains intact.
    - A separate local installer inspect verified every locked skill in both
      destinations, planned no writes, and exited `0`. The live explicit entry
      contract now matches the `In Progress` lifecycle.
    - A final read-only porcelain v2 check verified `issues/1` is still clean
      at the captured starting commit immediately before harness launch.
    - The user reports that the manually invoked Codex `implement` session
      created commit `a1e04bc123e64d0c93afa1576a67c69b4f2726af`, left the
      `issues/1` worktree clean, and stopped without push, pull request, or
      review. It named starting commit
      `08e3cb0be81c8fa549825867e17b93405479df54` for the later fresh review.
    - Independent Git inspection verified the reported commit and clean branch.
      Its sole parent is the captured starting commit, its message is
      `Personalize greeting CLI with optional names`, it has no co-author, and
      it changes only `README.md`, `hello.py`, and `tests/test_hello.py` with no
      diff-check errors.
    - The committed eight-test suite passes. Direct public-API inspection also
      showed that `greeting("  Ada  ")` preserves the meaningful supplied value
      while the CLI trims individual argument parts. The human explicitly
      confirmed this is intended behavior, not a bug: only empty or
      whitespace-only API values fall back to `X`. No correction or issue
      comment is required.
    - The worktree remained clean after all independent checks. Code review,
      push, and pull-request creation have not occurred.
    - The user's first abbreviated report included only the post-commit
      summary. The user then supplied the preceding commit-gate output and
      confirmed that the gate did occur before the commit.
    - The gate showed the captured starting commit, the exact three changed
      files, behavior and acceptance evidence, eight passing tests, CLI E2E
      evidence including invalid-option exit status 2, clean `git diff --check`,
      unavailable quality tools, absence of dependencies and
      generated files, the diff summary, and the proposed commit message.
    - With the human-approved commit followed by a clean stop before review,
      push, pull request, Project mutation, or worktree removal, the Codex
      `implement` path is proven end to end.
  - [x] Audit and adopt `code-review` as a separate explicit entry.
    - Read-only inspection covered the exact upstream `SKILL.md` and OpenAI
      metadata at pinned revision
      `3cca18b368ae95cdbdebbff572ccafa662551015`.
    - Useful behavior to retain: require a resolvable non-empty fixed-point
      comparison, inspect the commit list, keep intent and repository-standard
      reasoning distinguishable, cite sources, and report when no specification
      exists.
    - The pinned skill cannot be adopted unchanged. It always spawns two
      parallel sub-agents, assumes `docs/agents/issue-tracker.md` and the
      unrelated `/setup-matt-pocock-skills` flow, is implicitly invocable, and
      has no strict no-edit or no-remote-mutation boundary.
    - Its two axes also omit a first-class correctness and security review,
      preserve sub-agent findings without source verification, and cannot
      resolve the current issue from branch `issues/1` when the commit message
      contains no issue reference.
    - Local Plannotator 0.27.12 directly supports `plannotator review --git`.
      Its default Git review includes committed branch work since the base plus
      staged, unstaged, and untracked state, and submitted annotations contain
      file and line references.
    - Plannotator is best placed after the fresh automated review and before
      fixes, push, or pull-request creation as the human diff-approval surface.
      For the initial sequential proof, use its manual viewer rather than its
      agent-review job: current Plannotator documentation says Codex review jobs
      run full-auto with a workspace-write sandbox and that read-only behavior
      is prompt-based rather than enforced.
    - Proposed compatibility boundary: make `code-review` explicit-only and
      sequential; accept either a user-supplied fixed point or Plannotator's
      supplied comparison; resolve issue intent from explicit input or the
      issue branch without a setup file; review correctness, security, intent,
      standards, and maintainability; verify material findings against source;
      anchor them to changed files and lines with severity; and never edit,
      commit, push, post, or change tracker state.
    - The human approved the same-worktree rework loop. Actionable human review
      feedback returns to `Ready for Agent` only after a rework packet is
      persisted and verified; a new harness reuses the clean worktree, claims
      it into `In Progress`, and repeats review from the original branch base.
      Ambiguous product feedback returns to `Planning`, while an approved diff
      advances to the push and pull-request gate.
    - Vendor source now contains an explicit-only, dependency-free
      `code-review` entry with one sequential read-only review of correctness,
      security, intent, repository standards, and maintainability. It verifies
      findings, supports issue-number and `issues/<number>` resolution, keeps a
      stable review fixed point across corrections, and never launches
      Plannotator or performs a mutation.
    - `docs/runbooks/implementation.md` records the implementation, automated
      review, user-started Plannotator review, durable rework-packet, requeue,
      same-worktree reuse, and cross-machine handoff boundaries. The plan,
      prerequisites, upstream compatibility notes, lock file, and third-party
      notice are aligned.
    - Installer version 0.5.0 includes `code-review` as the sixth manual entry.
      Bash parsing, clean ShellCheck, the focused installer test, source wording
      checks, and the official skill validator through a temporary
      Codex-compatible projection pass.
    - The live user-level inspect verified all eight existing skills under both
      `~/.agents/skills` and `~/.claude/skills`, planned only the missing
      `code-review` directory in each destination, made no writes, and exited
      `2` as expected.
    - The human approved installing only the two planned `code-review` copies.
      Invocation and Plannotator review remain separate later gates.
    - The connected-shell apply reported one planned `code-review` installation
      per destination, installed both copies, and internally verified the
      complete bundle. The user did not include the command's exit-status line,
      so an independent inspect remains required.
    - A separate installer 0.5.0 inspect verified every locked skill, including
      `code-review`, in both destinations, planned no writes, and exited `0`.
    - Installed Codex CLI help confirms the interactive client accepts
      `--sandbox read-only`, `--ask-for-approval on-request`, and `--cd`. The
      live review must use the real `codex` command rather than the retained
      permission-bypass alias.
    - The human ran the review from the prepared `issues/1` worktree and then
      started `plannotator review --git` inside the same harness session.
      Plannotator opened successfully, remained attached to that session, and
      returned `Code review completed - no changes requested` directly into
      the harness context without a manual feedback transfer.
    - Independent Git inspection after the review verified a clean worktree on
      branch `issues/1` at reviewed commit
      `a1e04bc123e64d0c93afa1576a67c69b4f2726af`.
    - This proves the explicit, read-only, no-changes-requested review path end
      to end. Actionable annotation and rework-packet handling remain available
      for the first review that genuinely requests a correction; no synthetic
      correction was added merely to exercise that branch.
  - [x] Complete the first sequential ticket through publication, merge, and
    cleanup.
    - Phase 6 inspection found that the plan requires two completed sequential
      tickets before parallel guidance is documented. Phase 5 therefore remains
      open even though `code-review` adoption and issue 1 are complete; a second
      ticket must pass sequentially.
    - The recreated GitHub repository initially contained only `issues/1`, so
      GitHub selected that branch as its default. Local inspection verified a
      clean `main` checkout at the original base commit
      `08e3cb0be81c8fa549825867e17b93405479df54`; the human published it without
      a force push and changed the repository default to `main` as separate
      operations.
    - The GitHub branch selector then showed both `main` and `issues/1`. Pull
      request inspection later confirmed `main` as the base and `issues/1` as
      the head.
    - A read-only duplicate check returned no pull request for `issues/1`.
      During the approved creation, a missing shell line continuation caused
      the initial `gh pr create` command to run interactively and create pull
      request 2; the following `--title` token failed as a separate command.
      The successful mutation was not retried.
    - Read-only `gh pr view` inspection verified pull request 2 open with the
      approved title and body, base `main`, head `issues/1`, validation
      evidence, and `Closes #1` linkage.
    - The pull-request CI gate completed with one successful `CI/test
      (pull_request)` check and no cancelled, failing, skipped, or pending
      checks. A later PR query verified it is not a draft and reports
      `MERGEABLE` with merge state `CLEAN`.
    - Project item `PVTI_lAHOBHnURs4BipPVzg5x3Bk` was verified in `In Progress`
      before the transition. The human approved changing only its Status field,
      direct `gh project item-edit` reported success, and a separate item query
      verified status `In Review` for issue 1.
    - At the human review checkpoint, pull request 2 was ready and no merge,
      issue-completion transition, or worktree cleanup had yet been performed.
    - The implementation runbook now compares merge commit, squash, and rebase
      behavior. It records squash as the one-ticket-per-pull-request default,
      requires pinning the reviewed head commit, and keeps branch deletion and
      worktree removal as separate later gates. The development plan points to
      that authoritative policy.
    - The human approved squash-merging only pull request 2 at reviewed head
      `a1e04bc123e64d0c93afa1576a67c69b4f2726af`, with no branch deletion. The
      pinned `gh pr merge` command reported success and exited `0`.
    - Independent remote queries verified pull request 2 in `MERGED` state at
      `2026-09-07T18:10:04Z` with default-branch merge commit
      `e48e6d27ddfb338307dac0990f9ba5d03c9d6973`, and issue 1 in `CLOSED` state
      one second later.
    - A separate Project query verified item
      `PVTI_lAHOBHnURs4BipPVzg5x3Bk` in `Done`. GitHub applied the
      closure-to-`Done` transition automatically; the factory performed no
      manual completion mutation and did not claim that initial setup created
      or configured this workflow.
    - The remote feature branch and local Phantom worktree were intentionally
      retained while updating and validating local `main`, deleting the remote
      branch, and removing the worktree remained separate gates.
    - The human fast-forwarded local `main` from the original base to merge
      commit `e48e6d27ddfb338307dac0990f9ba5d03c9d6973` with `--ff-only`.
      Independent local checks verified `main` clean and synchronized with
      `origin/main`, and all eight tests passed without writing bytecode. The
      retained `issues/1` worktree remained clean at the reviewed head.
    - The human requested automatic cleanup for the repeated post-merge
      lifecycle. The approved design is a standalone, inspect-first
      `scripts/cleanup-ticket.sh`; local apply and explicit remote deletion are
      distinguishable, no force is used, and no issue or Project state is
      mutated.
    - Cleanup script version 0.1.1 validates a merged pull request with closed
      linked issues, synchronized default branch containing the merge commit,
      exact reviewed local and remote feature refs, and clean primary and
      ticket worktrees. It uses exact-ref deletion for the local branch and
      requires `--delete-remote` before deleting the GitHub branch.
    - Bash parsing and ShellCheck pass. One focused disposable-repository test
      proves inspect makes no changes, a dirty worktree blocks all cleanup,
      approved apply removes local and remote ticket refs without changing the
      default branch, and completed retries are idempotent. The implementation
      runbook and development plan document the new cleanup gate.
    - The first live version 0.1.0 inspect stopped before planning or deleting
      anything because it expected closing-issue state inside the pull-request
      response. A direct GitHub query proved `closingIssuesReferences` contains
      identity, repository, and URL fields but no issue state.
    - Version 0.1.1 now resolves each closing-issue URL and verifies its state
      through a separate read-only `gh issue view` call. The focused fixture
      matches the observed GitHub response, proves an open linked issue blocks
      cleanup, and retains the complete clean apply and retry coverage. Bash
      parsing and ShellCheck pass after the correction.
    - The corrected live inspect verified pull request 2, closed issue 1,
      synchronized `main` at merge commit
      `e48e6d27ddfb338307dac0990f9ba5d03c9d6973`, and matching local and remote
      `issues/1` refs at reviewed head
      `a1e04bc123e64d0c93afa1576a67c69b4f2726af`. It planned exactly the clean
      worktree, local branch, and remote branch deletions and exited `2` without
      changing them.
    - After explicit approval, the live apply removed the worktree, deleted the
      exact local branch, then deleted `origin/issues/1`. Its internal final
      verification reported completion, and the command exited `0`.
    - Independent Git inspection found only the primary worktree, with clean
      local and remote-tracking `main` refs at the merge commit and no local or
      remote-tracking `issues/1` ref. A final live inspect with remote cleanup
      requested exited `0`, proving completed-state idempotency against GitHub.
    - Issue 1 is the first complete sequential factory ticket from intake
      through cleanup. Pull request, issue, Project, and default-branch history
      remain intact; only the merged feature worktree and refs were removed.
  - [ ] Complete the second sequential ticket through publication, merge, and
    cleanup.
    - A duplicate-title search across all issue states found no existing issue
      named `Add optional ANSI color to greeting output`.
    - The human approved a bounded change that adds explicit ANSI foreground
      color selection while preserving plain output by default, the reusable
      plain-text `greeting()` API, existing CLI behavior, and a dependency-free
      implementation.
    - The first editor-based creation split the intended title at a newline and
      stored only its remainder as the body. Issue 3 was repaired in place
      rather than replaced.
    - Read-only human-shell verification confirmed issue 3 now has the exact
      title `Add optional ANSI color to greeting output` and the complete
      approved outcome, behavior, and verification body.
    - The approved Project insertion created item
      `PVTI_lAHOBHnURs4BipPVzg52KF4` for issue 3. Human-shell verification
      confirmed its initial status is `Triage`.
    - The human approved changing only that item's Status from `Triage` to
      `Spec Ready`. The direct edit exited `0`, and a separate Project query
      verified the resulting `Spec Ready` status.
    - Read-only issue inspection verified issue 3 is open, unassigned, and has
      zero native `blockedBy` and `blocking` relationships. Its approved scope
      fits one implementation session and preserves the existing `greeting()`
      API and subprocess CLI verification seams.
    - The human approved changing only the Project item from `Spec Ready` to
      `Ready for Agent`. The direct edit exited `0`, and a separate Project
      query verified the resulting status.
    - The human separately approved assignment to the active GitHub user. The
      edit exited `0`, and a read-only query verified issue 3 remains open with
      `zzak00` as its sole assignee.
    - Local inspection found only the primary worktree, clean on `main` at
      `e48e6d27ddfb338307dac0990f9ba5d03c9d6973`. Local `main` and
      `origin/main` match, and the origin is
      `https://github.com/zzak00/scratch-project.git`.
    - The first checkout attempt ran outside `scratch-project` and failed with
      `no git remotes found`; it created no worktree. The retry from the correct
      repository created the isolated `issues/3` worktree and exited `0`.
    - Independent Git inspection verified the registered worktree at
      `/Users/zak/Desktop/scratch-project/.git/phantom/worktrees/issues/3`,
      clean on branch `issues/3` at starting commit
      `e48e6d27ddfb338307dac0990f9ba5d03c9d6973`. The primary checkout remains
      clean on synchronized `main` at the same commit.
    - The human approved changing only the Project item from `Ready for Agent`
      to `In Progress`. The direct edit exited `0`, and a separate Project
      query verified the resulting status.
    - Claude Code 2.1.236 resolves through `/opt/homebrew/bin/claude`, the live
      Claude skill directory contains `implement`, and the issue worktree
      remained clean at the captured starting commit immediately before launch.
    - The user reports that the manually invoked Claude Code implementation is
      complete. Independent Git inspection found a clean commit
      `e63c495035bd96971cd4289b2eff32586922398a` whose sole parent is the
      captured starting commit.
    - The commit changes only `README.md`, `hello.py`, and
      `tests/test_hello.py`, with 58 insertions and one deletion. Its message
      has no co-author, and the complete branch diff passes `git diff --check`.
    - All 11 tests pass without bytecode writes. Direct CLI checks verified
      unchanged plain output and exact green and cyan ANSI foreground sequences
      with the reset code immediately before the newline, including an
      option-like name after `--`. A separate missing-value invocation printed
      argparse usage and an error and exited `2`.
    - The supplied Claude transcript proves the pre-commit gate. It identified
      ticket 3 and the captured starting commit, listed the exact three files,
      mapped every acceptance criterion to implementation or test evidence,
      reported 11 passing tests, a clean compile check, the manual plain and
      green terminal demonstrations, no configured linter or formatter, no
      dependency changes, and the proposed commit message.
    - Claude inferred that argparse's missing-value behavior matches its tested
      unsupported-value behavior. A separate independent subprocess check
      closed that evidence gap: `--color` without a value exits `2`, writes
      usage and the expected error only to stderr, and leaves stdout empty.
    - The human confirmed Claude explicitly requested commit approval and,
      after approval, stopped without review, push, pull-request creation, or
      Project mutation. The Claude Code `implement` path is proven end to end
      for the second sequential ticket.
    - Before review, the human requested that `code-review` infer both issue 3
      and its fixed point when invoked without arguments. Real Git evidence is
      unambiguous: `origin/HEAD` resolves to `origin/main`, the `issues/3`
      reflog records `branch: Created from main` at
      `e48e6d27ddfb338307dac0990f9ba5d03c9d6973`, both local and remote
      default-branch merge bases equal that commit, and it is an ancestor of
      reviewed `HEAD`.
    - The approved compatibility correction keeps `code-review` explicit-only
      and adds no script or context file. It prefers a valid unique
      branch-creation reflog entry, cross-checks the default branch and all
      merge bases, accepts explicit overrides, reports the chosen evidence, and
      stops rather than guessing on missing or conflicting history.
    - Installer version 0.5.1, the lock manifest, OpenAI metadata, upstream
      compatibility notes, implementation runbook, development plan, and
      focused installer checks are aligned with automatic inference.
    - Bash parsing, ShellCheck, the focused installer test, repository hygiene,
      the real worktree inference check, and the official skill validator
      through a temporary Codex-compatible projection all pass.
    - Read-only hashes prove both live `code-review` installations still match
      the exact previous source and metadata hashes. No backup target currently
      exists. Replacing those copies remains a separate approved operation;
      review has not started.
    - The human moved both previous copies into
      `/Users/zak/Desktop/code-review-skill-0.5.0-backup` and installed the
      updated bundle. Read-only hashes verify both live `code-review` source
      and metadata files exactly match the new lock values.
    - The human confirmed the first fresh Codex attempt accidentally invoked
      `implement`, not `code-review`. It stopped before any implementation or
      review because it could not retrieve the ticket or verify tracker state.
      Independent Git inspection confirms the `issues/3` worktree remains
      clean at `e63c495035bd96971cd4289b2eff32586922398a`. No recovery or
      Project change is needed.
    - In a second fresh read-only Codex session, the human invoked only
      `code-review`. It inferred issue 3 from branch `issues/3`, selected fixed
      point `e48e6d2` from the `Created from main` reflog entry, resolved
      `origin/main` as the default branch, and reviewed clean HEAD `e63c495`
      without an explicit argument.
    - The automated source review found no actionable findings. Eleven tests,
      colored and plain CLI checks, invalid-color behavior, and
      `git diff --check` passed, and the session reported no repository or
      tracker mutation.
    - GitHub API access was unavailable inside the review sandbox, so that
      session could not read the accepted issue body or independently confirm
      the open issue and `In Progress` Project status. The source-only report
      is not yet the final automated review; current human-shell tracker
      evidence must be supplied before Plannotator starts.
    - The human started `plannotator review --git` before closing that tracker
      evidence gap. Plannotator reviewed all changes since `origin/main` and
      returned two annotations in `tests/test_hello.py`: remove `blue` and
      add `pink`.
    - Direct shell-mode execution displayed the feedback and its verification
      instructions inside Codex but did not trigger another model turn, so no
      verdict or rework packet was produced automatically. A short explicit
      follow-up prompt in the same session is required to process the already
      returned feedback.
    - Independent Git inspection after Plannotator verified branch `issues/3`
      remains clean at reviewed HEAD
      `e63c495035bd96971cd4289b2eff32586922398a`, with no diff-check errors.
    - Local inspection found no installed `plannotator-review` skill under
      either Codex skill root. Plannotator preserved the submitted annotations
      in
      `/Users/zak/.plannotator/feedback/_unknown/records/2026-09-07T22-35-35-781Z-review-feedback.md`.
    - Official Plannotator documentation confirms Codex shell syntax
      `!plannotator review` prints feedback to stdout, while the separately
      installed `$plannotator-review` skill runs the command through the
      agent, waits for completion, and handles returned feedback. The current
      binary-only installation therefore behaved as documented.
    - Proposed correction: audit and vendor only the pinned upstream
      `plannotator-review` entry, keep it explicit-only, and constrain its
      handoff to the active read-only `code-review` contract. Do not run the
      broader upstream installer or enable unrelated hooks automatically.
    - The approved audit resolved Plannotator release `v0.27.12` to commit
      `96313ab228ede843203d38d9d2a86e1c87e18c81`. Its official core review
      skill launches the terminal command, waits for completion, and handles
      returned annotations in the same conversation. The project is
      dual-licensed under MIT or Apache-2.0; the vendored copy uses MIT.
    - Factory source version 0.6.0 vendors only `plannotator-review`, records
      its immutable provenance and hashes, and adds the MIT notice. It remains
      a manual entry under both Claude/Pi and Codex explicit-only metadata.
    - The compatibility patch fixes the factory invocation to
      `plannotator review --git`, rejects raw shell-escape execution, requires
      the completed `code-review` boundary, processes only incoming human
      findings, and preserves the no-edit and no-external-mutation contract.
    - `code-review`, the implementation runbook, prerequisites, development
      plan, upstream compatibility notes, installer, and focused installer
      checks now point to the connected manual entry rather than the raw shell
      command.
    - Bash parsing, ShellCheck without diagnostics, the focused installer
      test, lock verification, diff hygiene, and official Codex authoring
      validation for both changed skills pass. Refreshing the two live skill
      roots remains a separate human-approved operation.
    - The human backed up the previous `code-review` directories, inspected
      installer version 0.6.0, and confirmed it planned only `code-review` and
      `plannotator-review`. The inspect exited `2` without installation.
    - After separate approval, the apply installed the refreshed entries and
      exited `0`. An independent inspect then verified the complete locked
      bundle in both `~/.agents/skills` and `~/.claude/skills` and exited `0`.
    - Independent SHA-256 checks confirm both live `code-review` copies and all
      four live `plannotator-review` source and OpenAI metadata files exactly
      match the version 0.6.0 lock manifest. The connected actionable-feedback
      retry remains the next E2E gate.
    - A fresh read-only Codex session discovered the updated entries and
      manually ran `code-review`. It again inferred issue 3, resolved original
      fixed point `e48e6d27ddfb338307dac0990f9ba5d03c9d6973` from the branch
      creation reflog, cross-checked the same `origin/main` merge base, and
      reviewed clean HEAD `e63c495035bd96971cd4289b2eff32586922398a`.
    - The repeated automated review found no actionable source findings. All
      11 tests and the focused manual CLI checks passed, and no repository or
      tracker mutation occurred. The session still lacks authenticated tracker
      access, so fresh human-shell evidence for the open issue and `In Progress`
      Project state is required before invoking `plannotator-review`.
    - Fresh authenticated human-shell queries verified issue 3 is open,
      assigned to `zzak00`, and still contains the accepted six-color behavior,
      while its Project item remains `In Progress`. The evidence was returned
      to the same Codex review session.
    - Codex accepted that evidence, resolved the remaining tracker and intent
      gates, confirmed all accepted criteria are covered by the reviewed
      implementation and tests, retained its no-findings verdict, and reported
      no file or external-state mutation. The connected Plannotator entry is
      now ready for explicit human invocation.
    - The first explicit `plannotator-review` invocation did trigger a Codex
      model turn and waited for the command, proving the missing-response fix.
      Plannotator itself then failed after five attempts with the misleading
      message `Port 0 in use`, before opening the review UI.
    - Upstream issue 916 records the same `EADDRINUSE` message together with an
      underlying `EPERM` failure when Plannotator cannot create its session
      directory. The current read-only Codex sandbox likewise cannot bind the
      required local review server or write Plannotator session metadata,
      while the earlier shell escape ran outside that sandbox successfully.
      A one-command, human-approved sandbox escalation is the next direct E2E
      test before changing the vendored skill again.
    - A second raw Codex shell command successfully opened Plannotator but again
      only printed the returned annotations, confirming that shell mode is not
      a connected feedback path even when the browser review succeeds.
    - The human then instructed Codex through a normal model turn to run the
      privacy-restricted Plannotator command with one-time approval. Codex
      launched it through its terminal tool, waited, received both annotations,
      and automatically produced verdicts without any file or external-state
      mutation. This proves the connected command path end to end.
    - Codex classified removal of `blue` as contrary to the currently accepted
      ticket and addition of `pink` as a product-scope change, so it correctly
      made no edits. If the human retains that product decision, issue 3 must be
      updated and requeued through the approved review-rework lifecycle.
    - One factory correction remains: encode the proven one-time terminal
      approval and privacy environment directly in `plannotator-review` so its
      explicit invocation works without a follow-up natural-language command.
    - Factory source version 0.6.1 now encodes that correction. In a read-only
      harness it requests one-time approval for only the Plannotator process,
      disables Plannotator AI and sharing, forces local mode, and explicitly
      forbids widening the session sandbox or reusing the approval.
    - The lock hash, compatibility documentation, implementation runbook,
      installer version, and crucial installer assertions are aligned. Bash
      parsing, ShellCheck, the focused installer E2E test, repository hygiene,
      lock verification, and official Codex skill validation all pass. At this
      checkpoint the live `plannotator-review` copies still held version 0.6.0
      pending separate approval for replacement.
    - The human backed up the 0.6.0 `plannotator-review` copies, inspected the
      update, and confirmed only that entry was planned. After separate
      approval, installer 0.6.1 applied both replacements and exited `0`.
    - Independent installer inspection verified the complete locked bundle in
      both live roots. SHA-256 checks confirm both `plannotator-review` source
      files equal `94655812de891ed4637f5ec6be8224adc59703f3d0683f89c8e308a377bfac9f`
      and both OpenAI metadata files equal
      `7d4f46cf4f09c8e19c3a2d8c0c00eeb830eb6f0823cc3744228ce80e29ff0efa`.
      A fresh-session invocation remains the final proof of the encoded path.
    - The human resumed the existing read-only Codex review conversation in a
      fresh process so the updated skill was discovered without losing the
      accepted ticket intent or original review boundary.
    - The explicit `$plannotator-review` invocation followed the encoded path,
      opened the interactive review, waited for the two submitted annotations,
      and automatically returned them to Codex for verdicts. No follow-up shell
      command or manual feedback transfer was required.
    - Codex again classified `blue` as deliberate accepted scope and `pink` as
      a product-scope change, then made no file or external-state mutation. The
      version 0.6.1 connected review entry is now proven end to end in Codex.
      The requested color change requires an explicit ANSI mapping before issue
      3 can be updated and requeued.
    - Review of that result exposed a workflow gap: Codex recognized the scope
      conflict but ended with `No actionable findings` instead of asking the
      product question in the same review session. The human confirmed that
      scope decisions belong in the session receiving Plannotator feedback.
    - Factory source version 0.6.2 now distinguishes code verdicts from a
      separate `Scope change requested` disposition. A conflicting human
      directive cannot approve the review or disappear as merely `Not a bug`.
      The review session must ask the smallest product question and wait.
    - When the human rejects a scope change, the old intent remains. When the
      human approves and fully defines it, the session shows the exact proposed
      issue-intent update and a rework packet while remaining read-only. An
      unresolved decision returns to `Planning` without implementation work.
    - Both review skills, installer 0.6.2, the lock hashes, plan, runbook,
      compatibility notes, and crucial installer assertions are aligned. Bash
      parsing, ShellCheck without diagnostics, the focused installer E2E test,
      repository hygiene, and official Codex validation for both changed
      skills pass.
    - The first 0.6.2 refresh inspection exited `1` after detecting that the
      live Claude `code-review` still differed from the new lock. The installer
      stopped before installing anything, proving its non-overwrite boundary.
    - The human recovered the four prior 0.6.1 review skills with short,
      one-source commands and retained them under `/Users/zak/sf-bak`.
      Installer 0.6.2 then installed `code-review` and `plannotator-review` for
      both Agents and Claude. A final independent inspection verified the
      complete pinned bundle and exited `0`.
    - A fresh read-only Codex session proved the 0.6.2 review loop against
      ticket 3. `code-review` retained the original fixed point, and
      `plannotator-review` returned the human directives to the model as scope
      changes. Codex asked whether pink should replace blue or supplement it
      and waited for the answer in the same session.
    - The human chose to replace blue with pink and clarified that pink uses
      ANSI bright magenta code `95`, distinct from magenta code `35`. The
      updated intent is verified in issue 3, the complete rework packet is
      verified in an issue comment, the existing worktree remains clean at
      reviewed HEAD `e63c495`, and the Project item is back in
      `Ready for Agent` for a fresh implementation claim.
    - The E2E also exposed a smaller gap: after the first product answer,
      Codex proposed code `35` for both pink and magenta instead of recognizing
      that the mapping was still ambiguous. A human follow-up was required to
      define distinct ANSI mappings before the issue update and rework packet
      became executable.
    - Ticket 3 then completed its rework cycle. The updated implementation was
      committed at `e3c34bc`, both fresh-session reviews passed against the
      original `e48e6d2` fixed point, pull request 4 passed CI, and the human
      squash-merged it as `f8ef71c`. The linked issue closed, its Project item
      moved to `Done`, merged `main` passed all 13 tests, and cleanup removed
      the exact worktree and local and remote feature refs. A second cleanup
      inspection verified the operation was idempotently complete.
    - That rework exposed two additional implementation-contract defects. The
      skill incorrectly presented the rework round's `e63c495` starting commit
      as the next review fixed point, and the writable session accepted a
      request for a same-session subagent review after its commit. That review
      was not accepted as a factory gate; fresh automated and Plannotator
      reviews were run instead.
    - Factory source version 0.6.3 now records the implementation-round start
      separately from the original review fixed point, validates the rework
      packet relationship, and carries the original point through the handoff.
      After committing, `implement` must refuse direct, skill-driven,
      delegated, and subagent review from the writable session.
    - The runbook, plan, compatibility notes, lock manifest, and two crucial
      installer assertions are aligned. Bash parsing, ShellCheck, the focused
      installer E2E and lock verification, repository hygiene, and the official
      Codex skill validator all pass. The human backed up both previous
      `implement` copies under `/Users/zak/sf-bak/i62`, confirmed the installer
      planned no other changes, and applied version 0.6.3. A final inspection
      verified the complete pinned bundle in both live roots and exited `0`.
    - Factory source version 0.6.4 closes the remaining scope-completeness gap
      in both review entries. After every product answer, the review must verify
      that another implementation session can derive one testable expected
      behavior without another product decision. It must ask the next smallest
      question rather than inventing unresolved values, mappings, defaults,
      compatibility rules, or error behavior.
    - The runbook, plan, compatibility notes, lock hashes, and two crucial
      installer assertions are aligned. Bash parsing, ShellCheck, the focused
      installer E2E and lock verification, repository hygiene, and official
      Codex validation for both changed skills pass. The four previous review
      entries are verified under `/Users/zak/sf-bak/r63`. Installer inspection
      planned only `code-review` and `plannotator-review`, apply installed those
      entries for Agents and Claude, and an independent inspection verified the
      complete live 0.6.4 bundle with exit `0`.
  - [x] Audit and install a permission layer before enabling Pi Bash.
    - Pi 0.84.4 has no built-in Codex-style approval sandbox. The initial
      `--tools` shape omitted Bash and therefore could not run Git, GitHub CLI,
      repository tests, or Plannotator.
    - The exact `pi-sandbox` 0.6.8 source at commit
      `31fa5060689624467c1aeace2664ce91784522ff` was rejected. Failed sandbox
      initialization falls back to ordinary Bash, and project-local settings
      can disable or broaden its global policy.
    - `@gotgenes/pi-permission-system` 31.1.3 was audited at immutable tag
      `pi-permission-system-v31.1.3`, commit
      `cf99c19b2cad9d26f6c4d0b9dc464c7fde0fab18`. It fails closed, gates
      unresolved Bash commands, canonicalizes symlinked paths, and withholds
      project policy until Pi trusts the project. CI passed on the exact
      release commit. Its documented limitation is explicit: it provides
      permission decisions, not OS isolation.
    - The user approved the exact installation. Pi installed version 31.1.3,
      all locked dependencies matched their npm integrity records, and
      `tree-sitter-bash` loaded successfully despite npm reporting that its
      optional install script had not run.
    - The approved global policy allows ordinary repository reads and
      in-working-directory edits, asks before Bash and external access, denies
      common secret, Git metadata, SSH, and project-policy paths, disables YOLO
      mode, and disables command logging. Its installed file is mode `0600`.
    - A billed headless Pi smoke test allowed a first-line `.gitignore` read
      and blocked `pwd` because no interactive approval UI was available. This
      proves the default no-authority path fails closed; it does not replace
      the pending interactive ticket proof.
    - The host's Pi settings and extensions paths resolve into the dotfiles
      checkout. The exact package declaration and policy therefore appear as
      declarative dotfiles changes, while downloaded npm contents remain Pi
      runtime state.
    - Factory source now includes `config/pi-permission-system.json`,
      `pi-permissions.lock`, `scripts/install-pi-permissions.sh`, and the Pi
      permission runbook. Installer 0.1.0 defaults to inspection, applies only
      explicitly, verifies every resolved package and integrity plus parser
      loading, installs policy mode `0600`, supports Nix-managed settings
      symlinks, refuses policy conflicts or dependency drift, and is
      idempotent.
    - Bash parsing, ShellCheck, JSON validation, the critical installer tests,
      and a live installer inspection all pass. The live inspection exits `0`
      with the pinned extension and policy verified.
- [x] Phase 6 - Add optional parallel guidance
  - [x] Verify the prerequisite through two completed sequential tickets.
  - [x] Document candidate independence, fixed-wave approval, isolated
    ownership, bounded worker behavior, per-ticket review, integration risk,
    and dependent-ticket sequencing in the implementation runbook.
  - [x] Receive human approval of the documented parallel-wave contract.
- [ ] Phase 7 - Package and adopt
  - [x] Consolidate required third-party attribution into `README.md`, update
    lock and plan references, and remove the redundant standalone notice file.
  - [x] Consolidate the complete operator workflow into `README.md` and verify
    its relative links, Markdown hygiene, lock parsing, ShellCheck, and four
    crucial script test suites.
  - [x] Receive human approval of the consolidated operator guide.
  - [x] Remove the superseded operator runbooks and repair active references.
  - [x] Define and verify the portable release boundary without the development
    plan or progress tracker. Direct attribute inspection and a temporary Git
    archive retained `README.md` and the crucial test while excluding both
    development records.
  - [ ] Create the first approved source commit and verify its real archive.
