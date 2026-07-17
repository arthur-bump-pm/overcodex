#!/usr/bin/env bash
# overcodex-handoff-inject.sh — Codex SessionStart hook.
# Ported from overclaude's hooks/handoff-inject.sh. Injects a pending handoff
# package for this cwd into the new session's context, then archives it.
# Contract: always exit 0, silent on every error path, defensive jq parsing,
# tolerate a missing state root.
#
# Schema notes (see config/hooks.json header for the full write-up):
# session-start.command.input carries `source`: "startup"|"resume"|"clear"|
# "compact". We act ONLY on "startup" — mirroring overclaude's Claude Code
# matcher, which is also "startup"-only — so a mid-session /clear, a `codex
# resume`, or the SessionStart that fires right after PreCompact's own
# auto-compaction does not re-inject a stale package. This is a deliberate,
# possibly-too-narrow choice: needs live validation that `codex resume` does
# NOT also need this path (if handoff packages should survive a resume too,
# widen to `startup|resume`).
# session-start.command.output supports hookSpecificOutput.additionalContext
# (hookEventName must echo "SessionStart") — that's how the package reaches
# the new session; there is no plain-stdout passthrough the way Claude Code's
# UserPromptSubmit works, so output MUST be well-formed JSON.
exec 2>/dev/null
set -u

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
STATE_ROOT="$CODEX_HOME/overcodex"
ARCHIVE_DIR="$STATE_ROOT/handoff-archive"
PENDING_TTL=600

INPUT="$(cat)" || INPUT=""
command -v jq >/dev/null 2>&1 || exit 0

source_field="$(printf '%s' "$INPUT" | jq -r '.source // empty' 2>/dev/null)"
[ "$source_field" = "startup" ] || exit 0

cwd="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$cwd" ] || cwd="$PWD"

# Pending-file path: codex-swap would be the canonical resolver if/when it
# grows a `path handoff --cwd` subcommand (it does not, as of this writing —
# it's an account-swap tool only); fall back to the shared hash convention
# (identical result) unconditionally today. The probe is kept for forward
# compatibility and is harmless: an unknown codex-swap subcommand prints usage
# to stderr (redirected away) and exits non-zero, leaving P empty.
P=""
if command -v codex-swap >/dev/null 2>&1; then
    P="$(codex-swap path handoff --cwd "$cwd" 2>/dev/null)"
elif [ -x "$HOME/.local/bin/codex-swap" ]; then
    P="$("$HOME/.local/bin/codex-swap" path handoff --cwd "$cwd" 2>/dev/null)"
fi
if [ -z "$P" ]; then
    h="$(printf '%s' "$cwd" | /usr/bin/shasum -a 256 | awk '{print $1}' | cut -c1-12)"
    [ -n "$h" ] || exit 0
    P="$STATE_ROOT/handoff-pending-$h.md"
fi

[ -f "$P" ] || exit 0

# Line 1 must be: <!-- handoff cwd="<abs>" created="<epoch-int>" -->
header="$(head -n 1 "$P")"
emb_cwd="$(printf '%s' "$header" | sed -n 's/^<!-- handoff cwd="\(.*\)" created="[0-9][0-9]*" -->[[:space:]]*$/\1/p')"
emb_created="$(printf '%s' "$header" | sed -n 's/^<!-- handoff cwd=".*" created="\([0-9][0-9]*\)" -->[[:space:]]*$/\1/p')"

# Malformed header -> leave file, silent.
{ [ -n "$emb_cwd" ] && [ -n "$emb_created" ]; } || exit 0

# cwd mismatch -> leave file, silent.
[ "$emb_cwd" = "$cwd" ] || exit 0

now="$(date +%s)"
age=$(( now - emb_created ))

# Archive name: <YYYYmmdd-HHMMSS>-<HASH>.md (UTC); hash taken from filename.
base="${P##*/}"
fhash="${base#handoff-pending-}"
fhash="${fhash%.md}"
ts="$(date -u +%Y%m%d-%H%M%S)"

if [ "$age" -ge "$PENDING_TTL" ]; then
    # Expired -> archive with -expired suffix, no output.
    mkdir -p "$ARCHIVE_DIR" 2>/dev/null && mv -f "$P" "$ARCHIVE_DIR/$ts-$fhash-expired.md" 2>/dev/null
    exit 0
fi

# Claim first (atomic mv), then read from the archived path — prevents a
# concurrent same-cwd startup from injecting a dangling header after losing
# the race for the pending file.
A="$ARCHIVE_DIR/$ts-$fhash.md"
{ mkdir -p "$ARCHIVE_DIR" && mv "$P" "$A"; } 2>/dev/null || exit 0

body="$(tail -n +2 "$A" 2>/dev/null)"
ctx="$(printf '%s\n\n%s' "## Handoff from previous session (loaded by handoff-inject)" "$body")"

jq -n --arg ctx "$ctx" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
exit 0
