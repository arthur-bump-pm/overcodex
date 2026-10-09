---
name: handoff-claude
description: "Package this Codex session so a fresh Claude Code session (overclaude) in the same directory picks it up. Use ONLY when the user explicitly asks to continue in Claude Code, or accepts an offer to."
metadata:
  short-description: "Hand this session off to Claude Code (overclaude)"
---

GATE — read before acting. Only run this if the user explicitly asked to continue in Claude Code in this conversation (typed `$handoff-claude`, or said yes to an offer to move the work to Claude). An offer you made yourself is not consent. If no such consent exists, stop and ask instead: "Want me to hand this off to Claude Code?"

# $handoff-claude — continue in Claude Code

The reverse of overclaude's `/handoff codex`: this writes the package where overclaude's Claude Code SessionStart hook (`handoff-inject.sh`) loads it — same header line, same 12-hex sha256-of-cwd file name, same 10-minute window. It needs overclaude on this machine (`pipx install overclaude && overclaude install`). Nothing switches automatically: the user exits Codex and starts `claude` in the same directory.

## 1. Compute the state paths

Run exactly this (macOS /bin/bash 3.2 compatible):

```bash
HASH=$(printf '%s' "$PWD" | /usr/bin/shasum -a 256 | awk '{print $1}' | cut -c1-12)
STATE_DIR="$HOME/.claude-swap-backup"
PENDING="$STATE_DIR/handoff-pending-$HASH.md"
[ -f "$HOME/.claude/hooks/handoff-inject.sh" ] && echo overclaude-ok || echo overclaude-missing
mkdir -p "$STATE_DIR"
echo "thread=${CODEX_THREAD_ID:-unknown}"
ls "${CODEX_HOME:-$HOME/.codex}"/sessions/*/*/*/rollout-*"${CODEX_THREAD_ID:-none}".jsonl 2>/dev/null | tail -n 1
```

If it prints `overclaude-missing`, stop and tell the user Claude Code will not load the package until overclaude is installed.

## 2. Overwrite guard

If `$PENDING` already exists and its `created` epoch (line 1) is under 600 seconds old, warn: "another handoff is pending for this directory (<N> min ago) — proceeding replaces it" and wait for the user's confirmation.

## 3. Write the package

Line 1 MUST be exactly this comment — first line, no blank line before it; `cwd` is the absolute cwd (`$PWD`), `created` is `date +%s`:

```markdown
<!-- handoff cwd="<abs-cwd>" created="<epoch-int>" -->
# Handoff — <one-line goal>

## Goal
## Current state
## Decisions + rationale
## Files touched
## Work in flight
## Next steps
## Gotchas
## Session chain
```

Fill every section from this conversation — concise and decision-dense, a summary not a transcript. Files touched: absolute paths. Make the first line of `## Gotchas`: "Continuing in Claude Code from a Codex session: Codex-only items (custom agents in agents/*.toml, Codex skills such as $handoff) are not available here."

SIZE BUDGET: keep the whole package under ~8,000 bytes (Korean/CJK is ~3 bytes per character): Claude Code caps injected hook output at 10,000 characters. Check with `wc -c "$PENDING"` and tighten if over.

Session chain: if this session began with "## Handoff from previous session (loaded by handoff-inject)", copy that package's Session chain entries first. Then append one line for THIS session, in the same format overclaude uses: `<thread id from step 1, or "unknown"> — <rollout path from step 1, or "unknown"> — <YYYY-MM-DD>`. Keep only the last 3 entries.

## 4. Tell the user

"Handoff packaged for Claude Code at `$PENDING`. Exit Codex and run `claude` from the same directory within 10 minutes — overclaude's SessionStart hook loads it automatically. After 10 minutes it is archived; `/handoff restore` in Claude Code brings it back."
