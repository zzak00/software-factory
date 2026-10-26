---
name: to-spec
description: "Turn settled decisions into an issue body with acceptance criteria, or a product spec with requirements, gate it in Plannotator, and return it for the operator to file. No interview: synthesis of what is already decided."
disable-model-invocation: true
---

Turn the current conversation and codebase understanding into a spec. Do not interview the user; synthesize what is already decided. If a missing decision would change the outcome, stop and name it.

## Pick the form

- **Issue** (Fast or Standard track): one outcome, acceptance criteria AC1, AC2...
- **Product spec** (Product track): the parent issue body, requirements R1, R2... Slices come later from `to-tickets`.

## Process

1. Explore the repository as needed. Use its domain terms and respect the ADRs in the area you touch.
2. Sketch the seams where the behavior will be verified. Prefer existing seams and the highest one possible; the ideal number is one. For UI, the seam is a `verify-<app>` screenshot at named viewports. Check with the user that the seams match their expectations.
3. Write the spec with the template below to a file outside the repository, such as the session's temporary directory.
4. Gate it:

   ```bash
   plannotator annotate <spec-file> --gate --json --require-approval
   ```

   Treat rejection, cancellation, annotations, or a nonzero exit as a stop. Revise within the decided scope and gate again.
5. Return the approved text and its file path. The operator files it, for example with `gh issue create --body-file <spec-file>`. Do not publish, label, or change Project state.

<spec-template>

## Problem

The problem from the user's perspective.

## Outcome

What is true for the user when this is done.

## Scope

What is in, and what is explicitly out.

## Acceptance criteria

Numbered AC1, AC2... for an issue; R1, R2... for a product spec. Each item is observable by a user or operator and checkable at an agreed seam. Keep the list as short as the outcome allows.

## Validation seams

Where each criterion is proven: the test seam, the `verify-<app>` journey, or the screenshot viewport.

## Decisions

The decisions made: modules built or changed, their interfaces, API contracts, schema changes, architectural choices, and specific interactions. No file paths or code snippets, which go stale. Exception: a prototype snippet that encodes a decision more precisely than prose (state machine, schema, type shape), trimmed to the decision and marked as coming from a prototype.

## Testing decisions

What makes a good test here (external behavior, not implementation details), which modules are tested, and prior art in the codebase.

## Risk and track

Risk: Standard or Elevated, with the reason. Track: Fast, Standard, or Product.

## Design reference

The approved Claude Design prototype link and the viewports that matter. Omit when there is no UI.

## Open questions

Each one answered, or deferred with an owner.

</spec-template>
