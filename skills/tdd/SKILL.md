---
name: tdd
description: "Internal test-first implementation guidance for the implement skill, focused on crucial observable behavior at approved seams."
---

# Test-Driven Development

Use this as the internal test-first reference for an explicitly started
`implement` flow. Do not require a separate user invocation.

Read the repository instructions, accepted behavior, approved seams, and
relevant EDRs or ADRs. Do not require `CONTEXT.md`. If the appropriate seam or
interface is unresolved, stop the implementation flow and ask the user. Do not
invoke a design skill or spawn sub-agents.

## Choose tests worth keeping

Tests verify behavior through public interfaces, not implementation details.
Prefer the highest practical approved seam and the fewest tests that protect
the critical path, complex logic, regression, and important error behavior.
Do not test every permutation merely because it is possible.

Read [tests.md](tests.md) when selecting or evaluating test cases. Read
[mocking.md](mocking.md) only when a test crosses a real system boundary and a
stand-in may be needed.

A durable test:

- describes behavior a user or caller cares about;
- observes the approved public interface;
- uses an expected value independent of the implementation;
- fails when that behavior is wrong;
- survives behavior-preserving internal refactoring.

Avoid tests that mock internal collaborators, call private methods, duplicate
the production calculation, assert incidental call order, or verify through a
side channel instead of the approved interface.

## Run vertical red-green-refactor cycles

For one material behavior at a time:

1. Red: write one focused test and run it. Confirm that it fails for the
   expected behavioral reason, not a setup error.
2. Green: write only enough production code to satisfy that behavior, then run
   the focused test again.
3. Refactor: while green, perform only behavior-preserving cleanup justified
   by the code now present, then rerun the focused test.

Repeat for the next approved behavior. Do not write all tests before any
implementation, anticipate future requirements, add speculative abstractions,
or refactor unrelated code.

For a bug, first reproduce the failure at the most realistic approved
end-to-end seam. Keep the smallest regression test that reliably protects the
behavior, then use narrower tests only where they materially improve diagnosis
or protect complex logic.
