---
name: prototype
description: Build a throwaway logic prototype to answer a state-model or business-logic question. UI questions go to Claude Design.
disable-model-invocation: true
---

# Prototype

A prototype is **throwaway code that answers a question**. The question decides the tool.

## Pick the tool

- **"Does this logic / state model feel right?"** -> [LOGIC.md](LOGIC.md). Build a single shareable HTML file (free-play buttons plus tabbed guided walkthroughs) that pushes the state machine through cases that are hard to reason about on paper, and that a non-developer can drive.
- **"What should this look like?"** -> prototype it in Claude Design, not in code. The approved design is linked from the issue as the visual reference.

If the question is ambiguous and the user isn't reachable, a backend module points to logic and a page or component points to Claude Design. State the assumption at the top of the prototype.

## Rules

1. **Throwaway from day one, and clearly marked as such.** Name the file so a casual reader can see it's a prototype, not production.
2. **Trivial to run.** A single HTML file the user double-clicks. No thinking required to start it.
3. **No persistence by default.** State lives in memory. Persistence is the thing the prototype is _checking_, not something it should depend on.
4. **Skip the polish.** No tests, no error handling beyond what makes the prototype _runnable_, no abstractions. The point is to learn something fast.
5. **Surface the state.** After every action, render the full relevant state so the user can see what changed.
6. **Capture it when done.** Fold the validated decision into the issue or spec, and into an ADR when it qualifies (`domain-modeling`). Hand back the prototype file with its verdict and the question it settled. The operator keeps the file (on a throwaway branch or attached to the issue) and records the verdict there. The main branch keeps only the validated decision.
