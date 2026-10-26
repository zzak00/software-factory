#!/usr/bin/env bash

# Claude Code PreToolUse hook for the Bash tool. It blocks git and gh commands
# that would bypass the factory gates or destroy uncommitted work. Exit code 2
# blocks the command and shows the reason to the agent; exit 0 allows it.
# Treat unset variables as errors instead of silently using empty text.
# Empty arrays are expanded as ${name[@]+"${name[@]}"} below, because bash 3.2
# (macOS /bin/bash) treats an empty array as unset under set -u.
set -u

# Print why the command is blocked (to stderr, which Claude Code shows the
# agent) and stop with exit code 2, which tells Claude Code to block it.
block() {
  printf 'BLOCKED by software-factory guardrails: %s\n' "$1" >&2
  exit 2
}

# Claude Code sends one JSON object on stdin. Read it, then pull out the shell
# command the agent wants to run and the directory it would run in.
command -v jq >/dev/null 2>&1 || block "jq is required to inspect commands"
input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty') || block "cannot parse the hook input"
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty') || block "cannot parse the hook input"
# Nothing to check: allow. No directory given: use the current one.
[ -n "$command" ] || exit 0
[ -n "$cwd" ] || cwd=$PWD

# Find the remote default branch (origin/HEAD, e.g. "origin/main" -> "main").
# is_protected succeeds for that branch and for main and master.
default_branch=$(git -C "$cwd" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
default_branch=${default_branch#origin/}
is_protected() {
  case "$1" in main|master|"${default_branch:-main}") return 0 ;; *) return 1 ;; esac
}

# A command can chain several commands ("cd app && git push"). Put each one on
# its own line by replacing ;, &&, ||, and | with newlines.
segments=$(printf '%s\n' "$command" | awk '{ gsub(/&&|\|\||;|\|/, "\n"); print }')

# Check the chained commands one at a time.
while IFS= read -r segment; do
  # Split the command into words: words[0] is the program, the rest are arguments.
  read -r -a words <<< "$segment"
  [ "${#words[@]}" -gt 0 ] || continue
  # Skip leading environment assignments such as GIT_DIR=x.
  while [ "${#words[@]}" -gt 0 ] && [[ ${words[0]} == *=* ]]; do words=("${words[@]:1}"); done
  [ "${#words[@]}" -gt 0 ] || continue

  # gh pr merge must name the reviewed head with --match-head-commit.
  if [ "${words[0]}" = gh ] && [ "${words[1]:-}" = pr ] && [ "${words[2]:-}" = merge ]; then
    [[ " ${words[*]} " == *" --match-head-commit "* ]] || block "merge only the reviewed head: add --match-head-commit SHA"
    continue
  fi
  # Everything below applies to git only; other programs are allowed.
  [ "${words[0]}" = git ] || continue

  # Drop global options such as -C PATH and -c KEY=VALUE before the subcommand.
  # -C also changes the repository the command acts on, so remember it.
  words=("${words[@]:1}")
  while [ "${#words[@]}" -gt 0 ]; do
    case "${words[0]}" in
      -C) [ "${#words[@]}" -ge 2 ] && cwd=${words[1]}; words=("${words[@]:2}") ;;
      -c) words=("${words[@]:2}") ;;
      -*) words=("${words[@]:1}") ;;
      *) break ;;
    esac
  done
  [ "${#words[@]}" -gt 0 ] || continue
  # The git subcommand (push, reset, ...) and the arguments after it.
  subcommand=${words[0]}
  args=("${words[@]:1}")

  case "$subcommand" in
    push)
      # Reject force and bulk pushes; collect the non-option arguments
      # (the remote, then any branches or refspecs).
      positional=()
      for arg in ${args[@]+"${args[@]}"}; do
        case "$arg" in
          --force|-f) block "force push is not allowed; use --force-with-lease on a feature branch" ;;
          --all|--mirror) block "push one branch at a time" ;;
          -*) ;;
          *) positional+=("$arg") ;;
        esac
      done
      # No branch named: git pushes the current branch. Block it on main.
      if [ "${#positional[@]}" -le 1 ]; then
        current=$(git -C "$cwd" branch --show-current 2>/dev/null)
        is_protected "$current" && block "do not push $current directly; open a pull request"
      fi
      # Each named refspec: "+x" forces; "src:dst" pushes to dst; HEAD means
      # the current branch. Block any that lands on a protected branch.
      for refspec in ${positional[@]+"${positional[@]:1}"}; do
        [[ $refspec == +* ]] && block "force push is not allowed"
        target=${refspec##*:}
        target=${target#refs/heads/}
        if [ "$target" = HEAD ]; then target=$(git -C "$cwd" branch --show-current 2>/dev/null); fi
        is_protected "$target" && block "do not push $target directly; open a pull request"
      done
      ;;
    reset)
      # --hard throws away uncommitted changes.
      [[ " ${args[*]-} " == *" --hard "* ]] && block "git reset --hard discards work"
      ;;
    clean)
      # Any short flag group containing f (-f, -fd, -xdf) or --force deletes files.
      for arg in ${args[@]+"${args[@]}"}; do
        [[ $arg == --force || ( $arg == -* && $arg != --* && $arg == *f* ) ]] && block "git clean -f deletes untracked files"
      done
      ;;
    branch)
      # -D deletes a branch even when its work is not merged; -d is safe.
      for arg in ${args[@]+"${args[@]}"}; do
        [ "$arg" = -D ] && block "git branch -D deletes unmerged work; use -d"
      done
      ;;
    checkout|restore)
      # "." means every file: it discards all local changes at once.
      for arg in ${args[@]+"${args[@]}"}; do
        [ "$arg" = . ] && block "git $subcommand . discards all local changes"
      done
      ;;
  esac
done <<< "$segments"

# No rule matched: allow the command.
exit 0
