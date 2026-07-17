#!/usr/bin/env bash
# overcodex-precompact-offer.sh — Codex PreCompact hook. No overclaude
# equivalent (Claude Code has no PreCompact-shaped hook Claude actually
# exposes on this axis the same way); added per spec because PreCompact is
# the ONE moment we know for certain context is about to be destroyed:
# pre-compact.command.input's `trigger` field is "auto" when Codex's OWN
# model_auto_compact_token_limit was just crossed, or "manual" on an explicit
# /compact. Since PreCompact fires only when compaction is actually about to
# happen, this is inherently a rare, always-worth-surfacing event — no
# threshold/hysteresis state is kept here (unlike ctx-watch/notify), and it
# fires every time.
#
# pre-compact.command.output has NO hookSpecificOutput/additionalContext
# field (confirmed against the embedded JSON Schema: only continue,
# stopReason, suppressOutput, systemMessage) — unlike SessionStart/
# UserPromptSubmit/PostToolUse/SubagentStart, PreCompact cannot inject
# context into the turn (compaction is about to happen regardless). So this
# is a passive systemMessage banner only, same mechanism as
# overcodex-notify.sh's Stop banner — it is shown to the user, not fed to the
# model as an instruction, so its wording addresses the human reading the
# transcript rather than telling the model what to say.
#
# Contract: always exit 0, silent on every error path, defensive jq parsing,
# never sets "decision" or "continue":false — this hook only informs.
exec 2>/dev/null
set -u

INPUT="$(cat)" || INPUT=""
command -v jq >/dev/null 2>&1 || exit 0

trigger="$(printf '%s' "$INPUT" | jq -r '.trigger // empty' 2>/dev/null)"
case "$trigger" in
    auto)   why="Codex's auto-compact token limit was just reached" ;;
    manual) why="a manual compact was requested" ;;
    *)      exit 0 ;;
esac

jq -n --arg msg "context precompact (${trigger}) - ${why}; older turns are about to be summarized. This is the last chance to /prompts:handoff before that detail is gone." \
    '{systemMessage: $msg}'
exit 0
