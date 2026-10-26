---
name: git-guardrails-claude-code
description: "Install repository-scoped Claude Code hooks that block destructive Git commands and factory-gate bypasses."
disable-model-invocation: true
---

# Git guardrails for Claude Code

Install a repository-scoped `PreToolUse` hook as a safety net around the
factory's Git workflow. The GitHub ruleset remains the authoritative control;
this hook catches mistakes before Claude Code sends the command.

This skill is Claude Code-specific. It does not configure Codex or change a
global Claude Code setting.

## Inspect

Read `.claude/settings.json` and `.claude/hooks/` when they exist. Preserve
every existing setting and hook. Stop if the repository already defines a
different hook at the target path or an equivalent Git guardrail whose
ownership is unclear.

The bundled hook is
[`scripts/block-dangerous-git.sh`](scripts/block-dangerous-git.sh). It blocks:

- direct pushes to `main`, `master`, or the remote default branch;
- force pushes, except `--force-with-lease` to a feature branch;
- pushes of every branch or mirror;
- `git reset --hard`, forced `git clean`, `git branch -D`, and broad checkout
  or restore of `.`;
- `gh pr merge` without `--match-head-commit`.

It allows ordinary reads, feature-branch pushes, soft resets, dry-run cleans,
safe branch deletion, and file-scoped restores.

## Install

1. Copy the bundled hook to
   `.claude/hooks/block-dangerous-git.sh` and make it executable.
2. Merge this entry into `.claude/settings.json` without replacing other keys
   or existing `PreToolUse` entries:

   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Bash",
           "hooks": [
             {
               "type": "command",
               "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-dangerous-git.sh"
             }
           ]
         }
       ]
     }
   }
   ```

3. Do not add the entry twice. When an equivalent entry exists, verify its
   target instead of appending another.

## Verify

Run the hook directly with Claude Code-shaped JSON from the repository root:

```bash
set +e
printf '%s\n' '{"tool_input":{"command":"git push origin main"},"cwd":"'"$PWD"'"}' \
  | bash .claude/hooks/block-dangerous-git.sh
status=$?
set -e
test "$status" -eq 2

printf '%s\n' '{"tool_input":{"command":"git status"},"cwd":"'"$PWD"'"}' \
  | bash .claude/hooks/block-dangerous-git.sh
```

Then validate `.claude/settings.json` with `jq`, inspect the diff, and report
the blocked and allowed cases. A shell-command hook is a guardrail, not a
security boundary: keep the repository ruleset and exact-head merge gate.
