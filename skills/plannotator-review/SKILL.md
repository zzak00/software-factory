---
name: plannotator-review
description: "Open Plannotator for an explicit committed or working diff and verify that the reviewed boundary does not change."
disable-model-invocation: true
---

# Plannotator Review

Use only when the user explicitly invokes this skill with a committed boundary
(`base`, `head`) or working boundary (`staged`, `unstaged`, `untracked`, or
`combined`). It is standalone and requires no other skill, tracker, branch
convention, or workflow state.

## Capture the boundary

Before launch, resolve the boundary and record the repository root, complete
changed-file manifest, and SHA-256 digest of the complete patch. For committed
work, require base ancestry and current checkout content matching the requested
head. For working review, record `HEAD` and include exactly the requested state.

Stop if the installed Plannotator cannot represent the boundary exactly.

## Run the review

For committed work, launch through the harness terminal tool:

```bash
PLANNOTATOR_AI=disabled \
PLANNOTATOR_SHARE=disabled \
PLANNOTATOR_REMOTE=0 \
plannotator review --git --base <base> --diff-type since-base --json
```

`--json` makes Plannotator emit one decision record on exit. For working review,
map the boundary to the matching `--diff-type`: `staged` to `staged` and
`unstaged` to `unstaged`. Plannotator's diff types cover tracked changes only, so
a boundary that includes untracked content (`untracked`, or `combined` when
untracked files are present) has no exact representation; stop rather than
approximate it. A `combined` boundary with no untracked files maps to
`uncommitted`. Pass `--json` the same way, and add `--no-git-remote-check` only
when the user requests a local-only review.

Request the narrow approval required to start the local browser when the
harness sandbox blocks it. Wait for completion. Do not ask the user to copy a
command, use a shell escape, or stage or unstage through the review interface.

Before submission, require the human to confirm the displayed boundary and
Files view match the recorded boundary and manifest.

## Verify and return

After exit, recapture the boundary. The head or working state, patch digest,
and complete manifest must match the pre-review record. Any mismatch invalidates
the result, including approval.

Read the outcome from the JSON `decision` field (`approved`, `annotated`, or
`dismissed`), not the message text.

Verify returned annotations against accepted intent and source. Classify each
as `Confirmed`, `Partly`, `Not a bug`, or `Intended`, with concise evidence and
whether it is introduced, pre-existing, or accepted scope. Identify scope
changes separately and ask the smallest product question needed to make their
behavior testable.

For confirmed defects, return file and line anchors, expected corrected
behavior, and objective validation commands. For approval, report the exact
boundary and patch digest.

Do not edit files, mutate Git or tracker state, publish, or invoke another
skill.
