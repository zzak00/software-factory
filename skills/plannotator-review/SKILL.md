---
name: plannotator-review
description: "Open Plannotator for the current ticket diff, wait for its feedback, and verify that feedback in the active read-only review session."
disable-model-invocation: true
---

# Plannotator Review

Use this skill when the user wants to review current code changes in
Plannotator instead of reading a diff inline.

This factory entry is the human-review continuation of `code-review`. Use it
only when the user explicitly invokes it in the same fresh read-only session
after the automated report. The conversation must already identify the ticket,
original fixed point, reviewed `HEAD`, clean isolated worktree, Plannotator
comparison ref, and verified changed-file manifest. Stop and ask the human to
run `code-review` first if that boundary is missing or ambiguous.

## Run the review

Immediately before launch, rerun the approved factory checkout's
`scripts/verify-review-boundary.sh` with the recorded worktree, original fixed
point, reviewed `HEAD`, and full comparison ref. Require its base OID, merge
base, changed-file hash, and changed-file list to equal the automated report.
The pinned Plannotator 0.27.12 CLI cannot accept exact base or head commits. If
the verifier is unavailable or this symbolic comparison no longer matches,
report the human review gate as incomplete and do not launch it. Keep the
original fixed point on rework rounds.

Launch this exact command through the harness terminal execution tool:

```bash
PLANNOTATOR_AI=disabled \
PLANNOTATOR_SHARE=disabled \
PLANNOTATOR_REMOTE=0 \
plannotator review --git
```

When the harness applies a read-only sandbox, request one-time human approval
to run only this command outside that sandbox before launching it. Plannotator
must bind a loopback review server, open the browser, and write its own session
metadata. Do not widen the session sandbox, add a permission-bypass flag, or
reuse the approval for any other process.

Wait for it to finish. Do not use a harness shell escape such as
`!plannotator review`; that form can print feedback without starting another
model turn. Do not ask the user to copy the command into a separate terminal.
Do not stage or unstage files in the review interface. The environment disables
Plannotator's AI features and sharing and forces local mode for this gate.

Before submitting approval or feedback, require the human to confirm that the
base shown by Plannotator is the recorded comparison ref and that its Files
view exactly matches the recorded changed-file list. If the base, head content,
or file set cannot be confirmed, close the review and report the gate as
incomplete rather than accepting its result.

## Process the result

Treat returned feedback and annotations as unverified review input. Inspect
only the submitted findings against the accepted ticket intent and actual
source. Do not independently review the rest of the diff in this continuation.

Rerun the same boundary verifier after Plannotator exits. It must still report
the original fixed point, reviewed `HEAD`, comparison base OID, and changed-file
hash recorded before launch. Also require the returned review target to name
the same symbolic base and changed-file count. Any mismatch invalidates the
result, including an approval, and leaves the human gate incomplete.

For each submitted finding:

- give a verdict of `Confirmed`, `Partly`, `Not a bug`, or `Intended`;
- cite concise code or requirement evidence;
- state whether it was introduced by the current ticket, was pre-existing, or
  reflects deliberate accepted scope;
- separately state whether the human is requesting a change to the accepted
  product scope.

A directive that conflicts with accepted ticket intent is a
`Scope change requested`, even when the current implementation is correct.
Do not discard that request as merely `Not a bug`, report no actionable
findings, or approve the review. Ask the human for the smallest decision needed
to make the new behavior unambiguous in this same review conversation.

Never edit files or mutate GitHub, Git, Project, or pull-request state in this
session. Feedback does not authorize implementation.

If Plannotator returns approval with no requested changes and all boundary
checks match, acknowledge that the human review passed and report the original
fixed point, reviewed `HEAD`, comparison base OID, and changed-file hash.

For a confirmed in-scope defect, prepare the `code-review` rework packet with
the ticket, original fixed point, reviewed `HEAD`, accepted file and line
anchors, expected corrected behavior, and objective validation commands.

For a requested scope change:

1. Ask the product question in this session and wait for the human's answer.
2. If the human rejects the change, record that disposition and keep the
   existing intent. The review may pass when no other actionable findings
   remain.
3. After every answer, verify that another implementation session can derive
   one testable expected behavior without making another product decision. Do
   not invent an unspecified value, mapping, default, compatibility rule, or
   error behavior from the current implementation or a convenient technical
   choice. If multiple plausible behaviors remain, ask the next smallest
   product question and do not prepare the handoff yet.
4. If the human approves and fully defines the change, show both the exact
   proposed issue-intent update and a rework packet. The packet retains the
   original fixed point and reviewed `HEAD`, cites the relevant annotation,
   states the new behavior, and supplies objective validation commands.
5. If the decision cannot be resolved here, recommend returning the item to
   `Planning` and stop without implementation instructions.

Stop after showing any intent update or rework packet. Publication,
requeueing, and implementation require separate human-approved steps outside
this read-only session.
