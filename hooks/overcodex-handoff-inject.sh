#!/usr/bin/env bash
# overcodex-handoff-inject.sh — Codex SessionStart hook.
# Ported from overclaude's hooks/handoff-inject.sh. Injects a pending handoff
# package for this cwd into the new session's context, then archives it.
# Contract: always exit 0, silent on every error path, defensive jq parsing,
# tolerate a missing state root.
#
# Payload (Codex 0.158, verified via app-server): session_id, transcript_path,
# cwd, hook_event_name, model, permission_mode, source. `source` is
# "startup"|"resume"|"clear"|"compact"; the config block also sets
# matcher = "startup", and this script re-checks it, so a /clear, a `codex
# resume`, or the SessionStart after a compaction never re-injects a package.
# Output: hookSpecificOutput.additionalContext (hookEventName "SessionStart")
# — there is no plain-stdout passthrough, so output MUST be well-formed JSON.
# The handler's additionalContextLimit (config/hooks-block.toml.tpl) keeps
# Codex from spilling/middle-truncating a package within the ~8,000-byte
# budget the handoff skills enforce.
#
# Home resolution: Codex passes NO CODEX_HOME to hooks — a hook only inherits
# the environment the `codex` process was started with (the codex() shell
# wrapper sets it per account as an env prefix). The $handoff skills resolve
# the state dir the same way, `${CODEX_HOME:-$HOME/.codex}`, so writer and
# reader always agree. The active-account marker is deliberately NOT used
# here: a `codex` started outside the wrapper runs on ~/.codex no matter what
# the marker says, and so do its skills.
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

# Pending file: shared 12-hex sha256-of-cwd convention (overclaude's
# `/handoff codex` and `codex-swap path handoff` compute the same name).
h="$(printf '%s' "$cwd" | /usr/bin/shasum -a 256 | awk '{print $1}' | cut -c1-12)"
[ -n "$h" ] || exit 0
P="$STATE_ROOT/handoff-pending-$h.md"

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
