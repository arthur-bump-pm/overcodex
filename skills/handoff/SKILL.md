---
name: handoff
description: "Package this Codex session (goal, state, decisions, next steps) so the next `codex` launch in this directory resumes it via overcodex's SessionStart hook. Use ONLY when the user explicitly asks to hand off / continue in a fresh session, or accepts an offer to."
metadata:
  short-description: "Hand this session off to a fresh Codex session"
---

GATE — read before acting. Only run this if the user explicitly asked for a handoff in this conversation (typed `$handoff`, said "hand off", or said yes to an offer to hand off). An offer you made yourself is not consent. If no such consent exists, stop and ask instead: "Want me to hand this off to a fresh session?"

# $handoff — continue in a fresh Codex session

Codex has no live session switch: this skill only packages state for the NEXT `codex` launch, which overcodex's SessionStart hook injects automatically. The user exits and relaunches manually. If the user's message also says `now` or `force`, there is still no automatic restart: say so and give the manual instruction.

## 1. Compute the state paths

Run exactly this (macOS /bin/bash 3.2 compatible). `CODEX_HOME` is the account home the running Codex was started with; the SessionStart hook resolves the same way, so never hardcode `~/.codex`:

```bash
HASH=$(printf '%s' "$PWD" | /usr/bin/shasum -a 256 | awk '{print $1}' | cut -c1-12)
STATE_DIR="${CODEX_HOME:-$HOME/.codex}/overcodex"
PENDING="$STATE_DIR/handoff-pending-$HASH.md"
mkdir -p "$STATE_DIR"
echo "thread=${CODEX_THREAD_ID:-unknown}"
ls "${CODEX_HOME:-$HOME/.codex}"/sessions/*/*/*/rollout-*"${CODEX_THREAD_ID:-none}".jsonl 2>/dev/null | tail -n 1
```

## 2. Overwrite guard

If `$PENDING` already exists, read its `created` epoch from line 1. If it is under 600 seconds old, warn: "another handoff is pending for this directory (<N> min ago) — proceeding replaces it" and wait for the user's confirmation.

## 3. Write the package

Write `$PENDING` with this exact structure. Line 1 MUST be the comment shown — first line, no blank line before it; `cwd` is the absolute cwd (`$PWD`), `created` is `date +%s`:

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

Fill every section from this conversation — concise and decision-dense, a summary not a transcript. Files touched: absolute paths. Work in flight: anything half-done, with exact resume points.

SIZE BUDGET: keep the whole package under ~8,000 bytes (Korean/CJK is ~3 bytes per character, so ~2,700 characters). Check with `wc -c "$PENDING"` and tighten if over; the hook's injection limit is sized for this budget.

Session chain: if this session began with "## Handoff from previous session (loaded by handoff-inject)", copy that package's Session chain entries first. Then append one line for THIS session, in the same format overclaude uses: `<thread id from step 1, or "unknown"> — <rollout path from step 1, or "unknown"> — <YYYY-MM-DD>`. Keep only the last 3 entries.

## 4. Tell the user

"Handoff packaged at `$PENDING`. Exit this session and run `codex` again from the same directory within 10 minutes — the SessionStart hook injects it automatically. After 10 minutes it is archived instead (`$handoff-status` shows it; re-run `$handoff` to repackage)."

If this is an embedded/IDE session that the user cannot simply exit and relaunch, still write the package, and tell them to start a new session (or reload the window) from the same directory within 10 minutes.

To also switch accounts, the user runs `codex-swap use <name>` before relaunching (a cold switch: only new `codex` processes pick it up).
