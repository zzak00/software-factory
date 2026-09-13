---
name: domain-modeling
description: Build and sharpen a project's domain model. Use when discussing codebase terminology, resolving domain ambiguity, or recording or editing an EDR, ADR, or optional scoped glossary.
---

# Domain Modeling

Actively build and sharpen the project's domain model as you design. This is the *active* discipline: challenging terms, inventing edge-case scenarios, and capturing durable decisions when they crystallise. Domain reasoning happens in the conversation first. Do not create a glossary merely because this skill is active.

## Sources of truth

Prefer the narrowest source that preserves the knowledge:

- Keep provisional terminology in the current planning conversation or idea issue.
- Prefer clear public code interfaces and tests for terminology that the implementation can express directly.
- Use focused EDRs or ADRs for durable decisions and their rationale.
- Offer a scoped glossary only after repeated ambiguity demonstrates that code, discussion, and decision records are insufficient.

Do not require a root `CONTEXT.md`. If the user approves a glossary, follow the repository's existing convention and keep it scoped to the relevant domain. Use [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md) only when the user chooses the upstream `CONTEXT.md` convention.

## During the session

### Challenge existing language

When the user uses a term that conflicts with established repository language, call it out immediately. Ask which meaning is intended.

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. Distinguish concepts that the current wording incorrectly combines.

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. Surface contradictions and ask which behavior is authoritative.

### Keep glossaries optional and small

Do not create or update a glossary automatically. First show the proposed change and explain which repeated ambiguity it resolves. Write it only after explicit approval.

A glossary contains only non-obvious, project-specific terms whose meanings affect product behavior or architecture. Keep each definition to one sentence. Exclude implementation details, examples, history, requirements, and decisions. Rewrite or remove stale entries instead of continually appending. Do not load a glossary when its domain terminology is irrelevant to the current work.

### Offer EDRs or ADRs sparingly

Only offer to create a decision record when all three are true:

1. **Hard to reverse**: the cost of changing your mind later is meaningful
2. **Surprising without context**: a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off**: there were genuine alternatives and you picked one for specific reasons

If any of the three is missing, skip the decision record. Follow the repository's existing EDR or ADR convention. If none exists, offer the concise format in [ADR-FORMAT.md](./ADR-FORMAT.md). Show the proposed record and obtain explicit approval before writing it.
