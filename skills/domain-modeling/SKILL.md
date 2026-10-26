---
name: domain-modeling
description: Build and sharpen a project's domain model. Use when discussing codebase terminology, defining domain terms, or recording or editing an ADR.
disable-model-invocation: true
---

# Domain Modeling

Actively build and sharpen the project's domain model as you design. This is the *active* discipline: challenging terms, inventing edge-case scenarios, and writing the terms and decisions down the moment they crystallise. (Merely *reading* the terms is not this skill: any skill does that. This skill is for when you're changing the model, not just consuming it.)

## Where it lives

- **Domain terms:** the `## Domain terms` section of the nearest `AGENTS.md`, which its sibling `CLAUDE.md` imports. One place for agents and people. Add the section when the first term is resolved.
- **Decisions:** `docs/adr/` next to that `AGENTS.md`, numbered `0001-slug.md`, `0002-slug.md`. Create the directory when the first ADR is needed.

A monorepo has one `AGENTS.md` per context (for example `backend/`, `frontend/`) plus the root one. Agents load the root file and the one for the directory they work in. Put each term and ADR in the context that owns it; only terms and decisions shared across contexts go at the root.

## Domain terms

Each term is one line: the canonical word in bold, a one-sentence meaning, and the words to avoid.

```md
## Domain terms

- **Order**: a customer's request to buy one or more products. Avoid: purchase, cart.
- **Cancellation**: ends a whole Order before shipping; partial cancellation does not exist. Avoid: refund.
```

Keep it to terms that are ambiguous or overloaded in this domain. No implementation details: the section is a glossary, not a spec or a scratch pad. When it outgrows about 15 terms, the domain probably needs splitting, not a longer list.

## During the session

### Challenge against the terms

When the user uses a term that conflicts with the existing `## Domain terms`, call it out immediately. "The terms define 'cancellation' as X, but you seem to mean Y. Which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account': do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible. Which is right?"

### Capture terms as they resolve

When a term is resolved, propose its line and add it to `## Domain terms` as soon as the user agrees. Don't batch these up: capture them as they happen.

### Offer ADRs sparingly

Only offer to create an ADR when all three are true:

1. **Hard to reverse**: the cost of changing your mind later is meaningful
2. **Surprising without context**: a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off**: there were genuine alternatives and you picked one for specific reasons

If any of the three is missing, skip the ADR. Use the format in [ADR-FORMAT.md](./ADR-FORMAT.md).

## Hand-off

Write a term or an ADR only after the user agrees to it. Report the files written; the operator reviews and commits them.
