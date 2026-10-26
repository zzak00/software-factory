---
name: plannotator-review
description: "Open the exact CI-passing pull request head, or an explicit diff, in Plannotator for human review, and verify that the reviewed boundary did not change."
disable-model-invocation: true
---

# Plannotator Review

Use when the user invokes this skill with a pull request, a committed boundary (`base`, `head`), or a working boundary (`staged`, `unstaged`, or `combined`).

## Gate a pull request

For a pull request, the reviewed head must be what will merge:

1. `gh pr view NUMBER --json headRefOid,baseRefName` gives the head SHA and base branch.
2. The local checkout's `HEAD` equals that head SHA.
3. `gh pr checks NUMBER` reports every required check passing.

Stop if any of these fails. Review against `origin/<baseRefName>` after `git fetch origin`.

## Capture the boundary

Before launch, record the repository root, the complete changed-file manifest, and the SHA-256 digest of the complete patch. For committed work, require the base to be an ancestor of the head. For working review, record `HEAD` and include exactly the requested state.

Stop if Plannotator cannot represent the boundary exactly.

## Run the review

For committed work and pull requests, launch through the harness terminal:

```bash
PLANNOTATOR_AI=disabled \
PLANNOTATOR_SHARE=disabled \
PLANNOTATOR_REMOTE=0 \
plannotator review --git --base <base> --diff-type since-base --json
```

For working review, map the boundary to `--diff-type`: `staged` to `staged`, `unstaged` to `unstaged`, and `combined` with no untracked files to `uncommitted`. Plannotator's diff types cover tracked changes only, so a boundary with untracked files has no exact representation: stop rather than approximate it. Add `--no-git-remote-check` only when the user asks for a local-only review.

Request the narrow approval needed to start the local browser when the harness sandbox blocks it. Wait for completion. Run the command yourself; never ask the user to copy it.

Before submission, the human confirms that the displayed boundary and Files view match the recorded manifest.

## Verify and return

After exit, recapture the boundary. The head or working state, the patch digest, and the manifest must match the pre-review record; any mismatch invalidates the result, including an approval.

Read the outcome from the JSON `decision` field (`approved`, `annotated`, or `dismissed`), not from the message text.

Check each annotation against the accepted intent and the source. Classify it as `Confirmed`, `Partly`, `Not a bug`, or `Intended`, with brief evidence, and say whether it was introduced, pre-existing, or accepted scope. List scope changes separately, each with the smallest product question needed to make it testable.

- **Confirmed defect:** file and line, expected behavior, and the command that will prove the fix.
- **Approval:** report the exact boundary, head SHA, and patch digest. The operator merges with `--match-head-commit <head SHA>`.

Do not edit files, change Git, the issue, or the PR, or invoke another skill.
