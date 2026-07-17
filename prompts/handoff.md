---
description: "Package this session's state and prepare a fresh Codex session to pick it up."
argument-hint: "[now|force]"
---

GATE — read before acting. Only run this if the user explicitly asked for a handoff (typed `/prompts:handoff` or `/handoff` themselves, or said yes to an offer to hand off). If no such consent exists in this conversation, stop and ask instead: "Want me to hand this off to a fresh session?"

# /prompts:handoff — continue in a fresh Codex session

Codex has no live session-switching command analogous to `/swap` — this prompt only packages state for the NEXT `codex` invocation to pick up via the SessionStart hook. The user must exit and relaunch manually; there is no in-place restart.

## 1. Compute the state paths

Run exactly this to get the cwd hash (macOS /bin/bash 3.2 compatible):

```bash
HASH=$(printf '%s' "$PWD" | /usr/bin/shasum -a 256 | awk '{print $1}' | cut -c1-12)
STATE_DIR="${CODEX_HOME:-$HOME/.codex}/overcodex"
PENDING="$STATE_DIR/handoff-pending-$HASH.md"
mkdir -p "$STATE_DIR"
```

`$PENDING` is the target file for this cwd. If `$CODEX_HOME` is set in the environment, it wins — never hardcode `~/.codex`.

## 2. Overwrite guard

If `$PENDING` already exists, check its `created` epoch (first line, see format below). If less than 600 seconds old, warn the user: "another handoff pending for this cwd (<N> min ago) — proceeding replaces it" and wait for confirmation before continuing.

## 3. Write the package

Write to `$PENDING` with this exact structure. Line 1 MUST be the comment shown, first line, no blank line before it — `cwd` is the absolute cwd, `created` is the current epoch integer (`date +%s`):

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

Fill every section from this conversation — concise and decision-dense, a summary not a transcript. Files touched: absolute paths. Work in flight: anything half-done, with exact resume points. Session chain: append one line for this session — `<session-id-if-known> — <cwd> — <YYYY-MM-DD>` — keep only the last 3 entries; if this session itself began with an injected handoff note, carry its prior entries forward first.

## 4. Tell the user

"Handoff packaged at `$PENDING`. Exit this session and run `codex` again from the same directory — the SessionStart hook will inject it automatically. The package expires after 10 minutes; after that it's stale (still readable via `/prompts:handoff-status`, but no longer auto-injected)."

`now` token: there is no phase-2 idle-kill for Codex sessions yet — always fall back to the manual exit-and-relaunch instruction above, and say so explicitly rather than implying an automatic kill happened.

## VS Code / non-TTY entrypoints

If the entrypoint can't be exited/relaunched by the user directly (e.g. an embedded extension host), write the package (steps 1–3) but tell the user the window must be reloaded manually for the injector to pick it up on the next session start.
