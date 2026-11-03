---
name: implement
description: "Implement approved work from the issue and the approved plan in the current checkout, test-first, and return evidence for each acceptance criterion."
disable-model-invocation: true
---

Implement the work described by the approved issue and, on the Standard track, the plan approved in Plannotator.

If the user passes an issue reference, read it with `gh issue view` and state its title and acceptance criteria (ACs) before starting. If the reference or the plan is ambiguous, ask.

## Before editing

- Confirm you are in the item's Worktrunk worktree (`wt list` marks the current one), not the main checkout. If not, stop: the operator runs Prepare first.
- Read the issue's card per [`KANBAN.md`](KANBAN.md). Ready: with the title and ACs, ask to move it to In Progress, and move it after the yes. In Progress or In Review: continue without a move. Inbox, Done, or any other Status: stop, say the ticket is not Ready, and ask the operator to move the card to Ready themselves.
- Record the starting `HEAD`. Inspect tracked and untracked changes, and preserve work you did not make.
- Stop when behavior is ambiguous, sources conflict, or the plan no longer fits the code. Return to the plan instead of improvising.

## Build

- **Bug issue:** load `diagnosing-bugs` first. Fix only after a red-capable reproduction exists.
- **Unexpected failure** (not the expected red of a `tdd` step) whose cause isn't obvious: stop and load `diagnosing-bugs`.
- Load `tdd` and work at the agreed seams, one vertical slice at a time.
- Follow the approved sketch. A needed deviation goes back to the plan for approval, not silently into the code.
- **UI work:** load `frontend-ui-engineering`.
- Run type checks and single test files regularly, and the full suite once at the end.
- **UI:** capture `verify-<app>` screenshots at the AC viewports and compare them with the Claude Design prototype. If the repository has no `verify-<app>` yet, say so and use the closest available evidence.

## Return

- The starting commit, the changed files, and a short diff summary.
- Evidence per AC: the command or screenshot, and its result.
- Checks run, checks skipped with the reason, and open uncertainty.

Then hand the diff to `code-review`. Do not stage, commit, push, or change the issue; the operator owns them. The card's move to In Progress is your only Project change.
