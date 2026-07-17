#!/usr/bin/env bash
# overcodex-notify.sh — Codex Stop hook.
# Ported from overclaude's hooks/ctx-notify.sh. Passive banner: when context
# usage (derived from the rollout transcript — see overcodex-ctx-lib.sh) sits
# in a threshold band that has not been bannered yet, emit
# {"systemMessage": ...}. NEVER emits a "decision" field (stop.command.output
# supports one, but we deliberately never touch it — this hook only informs,
# it never blocks the turn). Contract: always exit 0, silent on every error
# path, defensive jq parsing, no-op when stop_hook_active.
exec 2>/dev/null
set -u

HOOKS_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 0
# shellcheck source=./overcodex-ctx-lib.sh
. "$HOOKS_DIR/overcodex-ctx-lib.sh" 2>/dev/null || exit 0

# Thresholds.
T1=60
T2=75
T3=85

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CTX_DIR="$CODEX_HOME/overcodex/ctx"

INPUT="$(cat)" || INPUT=""
command -v jq >/dev/null 2>&1 || exit 0

# Never act on our own stop cycle.
sha="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)"
[ "$sha" = "true" ] && exit 0

session_id="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "$session_id" ] || exit 0

transcript_path="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)"

pct="$(ctx_pct_from_transcript "$transcript_path")" || exit 0
case "$pct" in ''|*[!0-9]*) exit 0 ;; esac

# State (missing/corrupt -> fired=0 bannered=0). Shared state file with
# overcodex-ctx-watch.sh; see that script's header for the sharing contract.
state="$CTX_DIR/$session_id.state"
fired=0
bannered=0
if [ -f "$state" ]; then
    f="$(jq -r '.fired // 0' "$state" 2>/dev/null)"
    b="$(jq -r '.bannered // 0' "$state" 2>/dev/null)"
    case "$f" in 0|60|75|85) fired=$f ;; esac
    case "$b" in 0|60|75|85) bannered=$b ;; esac
fi

# band = highest threshold <= pct (0 if < 60).
band=0
for t in "$T1" "$T2" "$T3"; do
    [ "$pct" -ge "$t" ] && band=$t
done

if [ "$pct" -ge "$T1" ] && [ "$band" -gt "$bannered" ]; then
    jq -n --arg msg "context ${pct}% - /prompts:handoff available" '{systemMessage: $msg}'
    mkdir -p "$CTX_DIR" 2>/dev/null || exit 0
    tmp="$state.tmp.$$"
    printf '{"fired":%d,"bannered":%d}\n' "$fired" "$band" > "$tmp" 2>/dev/null && mv -f "$tmp" "$state" 2>/dev/null
fi
exit 0
