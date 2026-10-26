---
name: architect
description: "Sketch types, signatures, and module structure before code, and turn the chosen shape into the plan approved in Plannotator. Use for /architect, 'architect this', 'design this', or Standard and Product work where jumping to code would lock in the wrong shape."
disable-model-invocation: true
---

# Architect

Sketch types, function signatures, class shapes, and module boundaries with `not implemented` bodies and pseudocode before any code is written. The result is the plan the Plan stage approves; `implement` fills it in.

Work through four phases: Ground, Sketch, Plan, Guard.

## Phase A: Ground the problem

Build a real mental model of every system the change touches. Read the code, tests, and ADRs in the area, then explain the current shape: owners, data flow, boundaries, and callers that cannot break. Naming a file is not grounding.

If the design changes ownership or layering, find out why the current shape exists (commit history, ADRs) so the reason becomes a constraint, not a guess.

Skip Phase A only for greenfield work with no surrounding system.

## Phase B: Sketch

Design it twice. Produce at least two structurally distinct candidates, whole-shape alternatives rather than point fixes inside one shape, before choosing.

For each candidate:

- **Usage first.** Write the caller's view before the types: the quickstart a consumer reads and two or three real call sites, such as an API request and response or a component using a hook. Derive the types from the usage; when they diverge, change the sketch, not the usage.
- **Data structures first.** Trace each main access pattern through the proposed structures. "We'll add an index or cache later" means the structure is wrong.
- **Visible boundaries.** `not implemented` bodies, pseudocode for tricky logic, doc comments stating intent and invariants. A reader should trace data from input to output through types and signatures alone.
- **Invariants in types.** Hard-to-misuse types first, runtime checks second, comments last. Validate at the boundaries (HTTP, CLI, config, external APIs), trust types inside, and keep business logic in pure functions.
- **One owner per state.** One source of truth per invariant; derive instead of syncing. Make a step idempotent when it can run twice or crash halfway.
- **Short call chains.** A flow that takes more than three files to trace needs flattening.

Screen every candidate against [`references/design-red-flags.md`](references/design-red-flags.md). Assume the next contributor is an agent that sees only the files it opened, copies the nearest example, and takes the shortest path that compiles. Prefer the design where a change that looks right from one file is right for the whole repository.

Choose by interface depth: the smallest, simplest public surface for the complexity it hides. For a contract between the Python backend and the frontend, use `api-and-interface-design`.

## Phase C: Plan, approved by a person

Write the plan in plan mode with:

- **Files:** new and modified paths.
- **Order of work:** numbered steps, each citing the ACs it serves.
- **Sketch:** types, signatures, and module map; one file for a small change.
- **Rationale:** shaped per [`references/rationale-template.md`](references/rationale-template.md).
- **Risks.**
- **Proof:** the test or `verify-<app>` evidence for each AC.

Leaving plan mode opens the plan in Plannotator. Stop until it is approved. Treat annotations as Phase A evidence: re-ground, re-sketch if the shape changes, and present the plan again. Do not start implementing.

## Phase D: Guard the shape during implementation

The approved sketch is the contract `implement` works against. A deviation is a signal to surface, not friction to absorb. If a function needs a parameter the sketch did not anticipate, decide whether the sketch was wrong, a requirement was missed, or the implementation is overreaching. Then revise the plan and get it approved again.

Scrap the sketch when friction is a pattern rather than a single instance. Tells:

- The same shape of workaround appearing across unrelated code.
- Several unrelated edge cases that each need a special-case branch.
- Types that need escape hatches (`Any`, casts, optional fields always set in practice) to compile.
- A lock appearing where the sketch said the state was not shared.
- Callers needing to know the abstraction's internal rules to use it.
- Two or more independent deviations of the same shape.

A few edge cases do not condemn an architecture; complexity in the data is not complexity in the design. When you scrap:

1. Re-ground on what has been built.
2. Redesign as if the new constraints had been day-one assumptions.
3. Subtract before adding: the new sketch is smaller than the old one before it grows.
4. Return to Phase B.

## Output

The approved plan, ready to paste into the pull request body.
