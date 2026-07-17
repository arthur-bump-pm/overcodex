#!/usr/bin/env bash
# overcodex-ctx-lib.sh — shared helper, sourced by overcodex-ctx-watch.sh,
# overcodex-notify.sh and overcodex-precompact-offer.sh. Not a hook itself
# (no shebang execution expected; hooks.json never references this file).
#
# Codex hook stdin carries NO context-usage percentage (verified: none of the
# ten hook input JSON Schemas embedded in the codex-cli 0.144.5 binary —
# PreToolUse/PermissionRequest/PostToolUse/PreCompact/PostCompact/SessionStart/
# UserPromptSubmit/SubagentStart/SubagentStop/Stop — carry a token or context
# field). There is also no custom-command statusline relay available: Codex's
# `tui.status_line` only lists built-in item names (run state, ctx/limits
# meters) — unlike Claude Code's statusline, it is not an external command fed
# rich JSON, so there is nothing analogous to overclaude's
# statusline-command.sh relay-file trick to piggyback on.
#
# What IS available: every hook payload with a `transcript_path` field points
# at the session's rollout JSONL file
# ($CODEX_HOME/sessions/YYYY/MM/DD/rollout-<ts>-<thread-id>.jsonl, confirmed by
# direct inspection of a real rollout in this sandbox — never modified, only
# read). Codex periodically appends a line shaped like:
#   {"timestamp":"...","type":"event_msg",
#    "payload":{"type":"token_count",
#      "info":{"total_token_usage":{"...","total_tokens":N},
#              "last_token_usage":{...},
#              "model_context_window":W},
#      "rate_limits":{...}}}
# total_tokens / model_context_window * 100, taken from the LAST such line, is
# used as the context-usage percentage everywhere below. This is a real
# measurement (not a heuristic) but its recency depends on how often Codex
# emits token_count events — needs live-session validation (see hooks-test
# notes) to confirm the cadence is tight enough for the 60/75/85 thresholds to
# feel timely rather than lagging.
#
# Contract: ctx_pct_from_transcript prints an integer 0-100 on stdout and
# returns 0 on success; on ANY failure (no file, no jq, malformed, division by
# zero) it prints nothing and returns 1. Callers must treat a non-zero return
# as "context usage unknown right now" and silently skip, never error.
exec 2>/dev/null

# Only scan the last N bytes of the rollout for performance/safety on very
# long sessions (rollouts can grow to many MB; a full-file grep on every
# UserPromptSubmit would add up). Falls back to a full-file scan on the rare
# chance the last token_count line is further back than the tail window (e.g.
# immediately followed by a very large function_call_output).
OVERCODEX_CTX_TAIL_BYTES=${OVERCODEX_CTX_TAIL_BYTES:-2000000}

ctx_pct_from_transcript() {
    tp="${1:-}"
    [ -n "$tp" ] && [ "$tp" != "null" ] && [ -f "$tp" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1

    line="$(tail -c "$OVERCODEX_CTX_TAIL_BYTES" "$tp" 2>/dev/null | grep -a '"type":"token_count"' | tail -n 1)"
    if [ -z "$line" ]; then
        line="$(grep -a '"type":"token_count"' "$tp" 2>/dev/null | tail -n 1)"
    fi
    [ -n "$line" ] || return 1

    total="$(printf '%s' "$line" | jq -r '.payload.info.total_token_usage.total_tokens // empty' 2>/dev/null)"
    window="$(printf '%s' "$line" | jq -r '.payload.info.model_context_window // empty' 2>/dev/null)"
    [ -n "$total" ] && [ -n "$window" ] || return 1
    case "$total" in ''|*[!0-9]*) return 1 ;; esac
    case "$window" in ''|*[!0-9]*) return 1 ;; esac
    [ "$window" -gt 0 ] || return 1

    awk -v t="$total" -v w="$window" 'BEGIN { printf "%d", (t / w) * 100 }'
}
