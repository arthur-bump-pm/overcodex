#!/usr/bin/env bash
# overcodex-ctx-watch.sh — Codex UserPromptSubmit hook.
# Ported from overclaude's hooks/ctx-watch.sh. Computes context usage from the
# session's rollout transcript (see overcodex-ctx-lib.sh for why: Codex hook
# stdin carries no context percentage and there is no statusline relay to
# piggyback on) and, when usage crosses a new threshold, injects a
# handoff-offer note into the turn via hookSpecificOutput.additionalContext.
# Contract: always exit 0, silent on every error path, defensive jq parsing,
# no state writes on the /handoff skip path.
exec 2>/dev/null
set -u

HOOKS_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 0
# shellcheck source=./overcodex-ctx-lib.sh
. "$HOOKS_DIR/overcodex-ctx-lib.sh" 2>/dev/null || exit 0

# Thresholds (contract: variables at top).
T1=60
T2=75
T3=85

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CTX_DIR="$CODEX_HOME/overcodex/ctx"

INPUT="$(cat)" || INPUT=""
command -v jq >/dev/null 2>&1 || exit 0

# Skip path FIRST — before any state read/write. Matches the /prompts:handoff
# custom-prompt convention this kit's prompts/ builder uses (see repo
# README), plus /handoff and /swap as generic aliases in case those also end
# up wired.
prompt="$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)"
case "$prompt" in
    "/handoff"*|"/swap"*|"/prompts:handoff"*) exit 0 ;;
esac

session_id="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "$session_id" ] || exit 0

transcript_path="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)"

# pct unavailable (missing transcript, no token_count line yet, no jq) ->
# silent exit. This is expected/common early in a session before the first
# token_count event has been written.
pct="$(ctx_pct_from_transcript "$transcript_path")" || exit 0
case "$pct" in ''|*[!0-9]*) exit 0 ;; esac

# State (missing/corrupt -> fired=0 bannered=0). Shared state file with
# overcodex-notify.sh: each script only actively manages its own field but
# preserves the other's across writes, exactly as overclaude's ctx-watch.sh /
# ctx-notify.sh pair do.
state="$CTX_DIR/$session_id.state"
fired=0
bannered=0
if [ -f "$state" ]; then
    f="$(jq -r '.fired // 0' "$state" 2>/dev/null)"
    b="$(jq -r '.bannered // 0' "$state" 2>/dev/null)"
    case "$f" in 0|60|75|85) fired=$f ;; esac
    case "$b" in 0|60|75|85) bannered=$b ;; esac
fi

changed=0

# Re-arm rule: if pct < fired-10 -> fired = highest threshold <= pct
# (else 0), and bannered = min(bannered, fired).
if [ "$pct" -lt $(( fired - 10 )) ]; then
    new_fired=0
    for t in "$T1" "$T2" "$T3"; do
        [ "$pct" -ge "$t" ] && new_fired=$t
    done
    fired=$new_fired
    [ "$bannered" -gt "$fired" ] && bannered=$fired
    changed=1
fi

# Fire: highest threshold T with pct >= T and T > fired.
T=0
for t in "$T1" "$T2" "$T3"; do
    [ "$pct" -ge "$t" ] && T=$t
done
if [ "$T" -gt "$fired" ]; then
    jq -n --arg ctx "[context-watch] Context is at ${pct}%. After fully completing the user's current request, tell them context is filling up and OFFER /prompts:handoff to continue in a fresh session. Do NOT invoke the handoff flow yourself unless the user explicitly accepts in their own message — an offer you made is not acceptance. If they decline or ignore the offer, drop the subject; this notice will re-appear at the next threshold." \
        '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
    fired=$T
    changed=1
fi

# Persist only when something changed (atomic write).
if [ "$changed" -eq 1 ]; then
    mkdir -p "$CTX_DIR" 2>/dev/null || exit 0
    tmp="$state.tmp.$$"
    printf '{"fired":%d,"bannered":%d}\n' "$fired" "$bannered" > "$tmp" 2>/dev/null && mv -f "$tmp" "$state" 2>/dev/null
fi
exit 0
