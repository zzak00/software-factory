# Software Factory Review Remediation Plan

## Goal

Resolve the end-to-end review findings while preserving the factory's current
architecture: standalone Bash scripts, pinned Agent Skills, explicit lock files,
crucial tests, and one concise operator guide.

The implementation order is setup, cleanup, Pi installation, review and
operator workflow, then release verification. Each stage should begin with a
realistic failing reproduction and finish with focused regression checks.

## 1. Correct setup validation and inspection

Start with command-level reproductions for:

- a source directory nested inside another Git repository;
- an existing public Project with the requested title;
- a fresh setup whose inspection stops after the first planned operation;
- missing origin or Project linkage that incorrectly returns success.

Update `scripts/setup-factory.sh` to:

- require the canonical Git root to equal `--source` before any mutation;
- verify the visibility of an existing Project before configuring or linking it;
- collect every independently discoverable conflict and planned action;
- show the complete intended operation, identifying resources whose IDs become
  available only after creation;
- return `2` whenever work remains, `0` only when the complete initial state
  matches, and `1` for conflicts or errors;
- revalidate relevant preconditions during apply and retain useful partial
  recovery output.

Acceptance criteria:

- Every refusal leaves local and remote state untouched.
- A nested source directory cannot affect its parent repository.
- Inspect output covers all operations the subsequent apply can perform.
- An existing Project with conflicting visibility is rejected.
- A completed second apply is a no-op and a following inspect exits `0`.

## 2. Make cleanup target-specific and race-safe

Reproduce both cleanup defects using disposable local Git remotes:

- configure different fetch and push destinations for `origin`;
- advance the remote branch between its final inspection and deletion.

Update `scripts/cleanup-ticket.sh` to:

- resolve every configured push URL independently from the fetch URL;
- require exactly one push destination matching the intended GitHub repository;
- perform remote deletion with an explicit expected-commit lease;
- fail without deletion if the remote head changes after inspection;
- preserve current exact-ref local deletion and partial-retry behavior.

Update the operator wording so it explains that remote deletion uses a
conditional lease to prevent removal of newer work.

Acceptance criteria:

- Mismatched or multiple push destinations are rejected.
- A concurrent remote update survives cleanup.
- A matching reviewed remote branch can be deleted after explicit approval.
- Squash-merge cleanup, remote preservation, and partial retries still work.

## 3. Make Pi installation reproducible

First reproduce a fresh installation resolving a transitive dependency version
that differs from `pi-permissions.lock`.

Replace the floating installation path with a factory-owned package definition
and complete npm lockfile. Install the exact dependency graph into a dedicated
runtime directory with a frozen installation operation, verify it, and only
then register the verified local extension with Pi.

The installation procedure must preserve existing Pi settings, packages, and
policy. A failure before activation must leave the active configuration
unchanged. Document recovery if activation is interrupted.

Add an operational verification for the target worktree that inspects trusted
project configuration and agent frontmatter capable of overriding the global
policy.

Acceptance criteria:

- Repeated fresh installations use the same complete dependency graph.
- Package source, version, integrity, and effective policy are verifiable.
- A conflict or failed frozen install leaves active Pi state unchanged.
- Trusted project overrides are reported before factory work begins.
- An interactive test demonstrates the expected allow, ask, and deny behavior
  in the actual ticket worktree.

## 4. Bind human review to the exact reviewed change

Reproduce the comparison mismatch with a ticket branch whose original fixed
point predates a later default-branch integration.

Determine how the pinned Plannotator version exposes or accepts its comparison
boundary. Update the review skills so human approval is accepted only after the
displayed base, head, and changed-file set match the automated review boundary.
If that boundary cannot be established, report the review gate as incomplete.

Update `skills.lock` together with every changed vendored skill file and record
the compatibility patch.

Acceptance criteria:

- Automated and Plannotator review cover the same original fixed point through
  the same reviewed `HEAD`.
- Later default-branch integration cannot silently narrow the human diff.
- Rework rounds retain the original fixed point.
- Any base, head, or file-set mismatch prevents approval.

## 5. Complete the operator workflow

Extend `README.md` with concise direct procedures for transitions currently
missing from the fresh-repository path:

1. Establish initial project content, tests, and CI configuration.
2. Inspect and separately approve the baseline commit.
3. Push and verify the default branch before creating ticket worktrees.
4. Verify the exact default-branch commit used for a new ticket worktree.
5. Synchronize the local default branch after merge.
6. Run the project's crucial tests before cleanup.
7. Verify effective Pi permissions in the target worktree.
8. Recover safely when any transition stops partway through.

Keep these as direct commands and operator gates. Add another script only if a
real end-to-end run shows a repeated failure that a direct procedure cannot
reliably prevent.

Acceptance criteria:

- A new operator can proceed from an empty project directory through baseline,
  planning, implementation, review, merge, synchronization, and cleanup.
- Every mutation remains separately visible and human-approved.
- Cleanup prerequisites are produced by an earlier documented step.
- The manual remains the single operator guide.

## 6. Strengthen verification and finish packaging

Add focused tests for the behavior introduced above. Prefer observable script
outcomes over assertions tied to incidental skill wording.

Add a small macOS and Linux CI matrix that runs:

- all crucial script tests;
- Bash syntax checks and ShellCheck;
- skill and permission lock verification;
- archive-content verification.

Complete the release boundary by:

- deciding whether `skills/setup-factory` remains checkout-only or joins the
  portable installed bundle;
- declaring a license for factory-authored artifacts;
- retaining honest, evidence-based harness compatibility claims;
- evaluating native worktree commands only as an optional alternative whose
  approval and publication behavior matches the current contract;
- rerunning the archive check from the first approved source commit.

Acceptance criteria:

- Required checks pass on supported macOS and Linux environments.
- The release archive contains the README, scripts, skills, locks,
  configuration, and crucial tests.
- Development plan and progress records are absent from the release archive.
- Every distributed skill file is covered by `skills.lock`.
- Compatibility claims name only end-to-end paths that have been demonstrated.

## Final validation

After all stages are complete:

1. Run every focused regression test.
2. Run the complete local test suite and ShellCheck once.
3. Exercise one complete sequential factory workflow from a fresh project
   through cleanup.
4. Exercise the supported review and rework path.
5. Complete each harness-specific workflow before expanding its compatibility
   claim.
6. Create and inspect the portable archive from the reviewed source commit.
7. Confirm the working tree contains only the intended reviewed changes before
   requesting commit approval.

The remediation should not introduce a factory CLI, background service,
coordinator, custom state store, automatic merger, or new automation framework.
