---
name: to-spec
description: "Synthesize an approved multi-session change into a disposable working specification for explicit human review, without publishing or changing tracker state automatically."
disable-model-invocation: true
---

# To Spec

Use this skill only when the user explicitly invokes it after the important
planning decisions are settled and the selected change needs to survive across
sessions. If the change fits one implementation session, recommend proceeding
without a separate specification.

Do not restart the planning interview or invent missing decisions. If a gap or
contradiction could materially change the outcome, identify it and stop so the
user can return to planning.

## Gather accepted context

Read the target repository's instructions, relevant code, tests, and public
interfaces. Use the accepted discussion and any relevant approved EDRs, ADRs,
or scoped glossary. Do not require `CONTEXT.md`, a repository-wide glossary, or
another setup skill.

Limit the specification to the smallest approved sub-idea. Preserve the
project's language and distinguish accepted decisions from remaining
uncertainty.

## Agree on verification seams

Propose the smallest useful set of externally observable seams at which the
change will be verified. Prefer an existing high-level seam over new or
implementation-specific seams.

Show the proposed seams, supporting evidence, assumptions, and unresolved
questions. Ask for approval before materializing the specification. Approval
of the seams authorizes only creation of the disposable working file.

## Materialize the working specification

Ask the user to approve its location. Use an ignored path in the active
worktree when cross-session access is needed, or keep it in the current session
when no file is needed. Do not edit ignore rules without separate approval.

Choose a structure that fits the change instead of following a fixed template.
Capture only the information a fresh implementation session needs, including:

- the user or operator problem and intended outcome;
- scope, exclusions, and externally observable behavior;
- accepted product, domain, engineering, and architecture decisions;
- constraints, dependencies, and compatibility expectations;
- the approved verification seams and expected evidence;
- any explicitly unresolved matter that does not block the approved scope.

Keep it concise. Do not generate exhaustive user stories, boilerplate, code
snippets, or fragile file-path predictions. Do not turn provisional ideas into
decisions.

## Review and optional publication

Open a materialized file for human review with:

```bash
plannotator annotate <approved-spec-path> --gate --json --require-approval
```

Treat rejection, cancellation, annotations, or a nonzero result as a stop, not
as permission to publish. Apply requested revisions only within the approved
scope, then repeat the review gate.

After approval, report the accepted file and its disposable status. Do not
commit it, publish it, create or modify an issue, add a label, change Project
status, create tickets, or invoke another skill automatically.

If the user requests publication, first show the exact tracker target and
proposed mutation. Ask for separate approval, then publish to the approved
existing or new item. Do not infer a parent issue or relationship. Use
`factory:spec` only when the user approved applying it to an issue that carries
the accepted specification. Project status remains a separate approval gate.
