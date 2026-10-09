#!/bin/bash
# Hook scripts: $handoff skill syntax in every user-facing message (H1), skip
# patterns, SessionStart home resolution = ${CODEX_HOME:-$HOME/.codex} like the
# skills (M1), overclaude-compatible package header/hash/TTL.
. "$(dirname "$0")/lib.sh"
new_home
unset CODEX_HOME
HK="$REPO/hooks"
hash12() { printf '%s' "$1" | /usr/bin/shasum -a 256 | awk '{print $1}' | cut -c1-12; }

TR="$HOME/rollout.jsonl"
printf '%s\n' '{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":900000},"last_token_usage":{"total_tokens":160000},"model_context_window":200000}}}' > "$TR"
ctx() { printf '%s' "{\"session_id\":\"$1\",\"transcript_path\":\"$TR\",\"prompt\":$(printf '%s' "$2" | jq -Rs .)}" | bash "$HK/overcodex-ctx-watch.sh"; }

o="$(ctx s1 'continue please')"
assert_contains "$(printf '%s' "$o" | jq -r .hookSpecificOutput.additionalContext)" '$handoff' "ctx-watch offers \$handoff"
assert_absent "$o" "/prompts:" "ctx-watch no longer mentions /prompts:"
for p in '$handoff' 'please $handoff now' '$handoff-claude' '  /handoff' '/prompts:handoff' '/swap work'; do
  assert_eq "$(ctx "skip-$RANDOM" "$p")" "" "ctx-watch skips: $p"
done
assert_eq "$(ls "$HOME/.codex/overcodex/ctx" | grep -c skip-)" "0" "skip path writes no state"

o="$(printf '%s' "{\"session_id\":\"s2\",\"transcript_path\":\"$TR\"}" | bash "$HK/overcodex-notify.sh")"
assert_contains "$(printf '%s' "$o" | jq -r .systemMessage)" '$handoff' "Stop banner names \$handoff"
o="$(printf '{"trigger":"auto"}' | bash "$HK/overcodex-precompact-offer.sh")"
assert_contains "$(printf '%s' "$o" | jq -r .systemMessage)" '$handoff' "PreCompact banner names \$handoff"
assert_eq "$(grep -l '/prompts:handoff' "$HK"/*.sh | grep -v ctx-watch)" "" "no hook message mentions /prompts:handoff"

# SessionStart: package for this cwd under ${CODEX_HOME:-$HOME/.codex}.
CWD="$HOME/proj"; mkdir -p "$CWD"
pkg() { # pkg <home> <created>
  mkdir -p "$1/overcodex"
  printf '<!-- handoff cwd="%s" created="%s" -->\n# Handoff — t\n\n## Goal\nGOAL-%s\n' "$CWD" "$2" "$(basename "$1")" > "$1/overcodex/handoff-pending-$(hash12 "$CWD").md"
}
start() { printf '%s' "{\"source\":\"${1:-startup}\",\"cwd\":\"$CWD\"}" | bash "$HK/overcodex-handoff-inject.sh"; }

pkg "$HOME/.codex" "$(date +%s)"
mkdir -p "$HOME/.codex-accounts/work"; echo work > "$HOME/.codex-accounts/.active"
pkg "$HOME/.codex-accounts/work" "$(date +%s)"
o="$(start)"
assert_contains "$o" "GOAL-.codex" "M1: no CODEX_HOME -> reads ~/.codex (the active marker is NOT consulted)"
o="$(CODEX_HOME="$HOME/.codex-accounts/work" start)"
assert_contains "$o" "GOAL-work" "M1: CODEX_HOME (wrapper env prefix) -> reads that account"
assert_eq "$(printf '%s' "$o" | jq -r .hookSpecificOutput.hookEventName)" "SessionStart" "valid SessionStart JSON"
assert_eq "$(ls "$HOME/.codex-accounts/work/overcodex/handoff-archive" | wc -l | tr -d ' ')" "1" "injected package archived"

pkg "$HOME/.codex" "$(date +%s)"
assert_eq "$(start resume)" "" "source=resume does not inject"
assert_eq "$(start clear)" "" "source=clear does not inject"
pkg "$HOME/.codex" "$(( $(date +%s) - 601 ))"
assert_eq "$(start)" "" "expired (>600 s) package is not injected"
assert_eq "$(ls "$HOME/.codex/overcodex/handoff-archive" | grep -c expired)" "1" "expired package archived with -expired"
printf '<!-- handoff cwd="/other" created="%s" -->\n' "$(date +%s)" > "$HOME/.codex/overcodex/handoff-pending-$(hash12 "$CWD").md"
assert_eq "$(start)" "" "cwd mismatch is not injected"
assert_true '[ -f "$HOME/.codex/overcodex/handoff-pending-$(hash12 "$CWD").md" ]' "cwd-mismatch package left in place"

# The skills write exactly what the hook reads: same header, hash, state dir.
for f in handoff handoff-status handoff-cancel; do
  assert_contains "$(cat "$REPO/skills/$f/SKILL.md")" 'STATE_DIR="${CODEX_HOME:-$HOME/.codex}/overcodex"' "$f skill resolves the hook's state dir"
  assert_contains "$(cat "$REPO/skills/$f/SKILL.md")" "/usr/bin/shasum -a 256 | awk '{print \$1}' | cut -c1-12" "$f skill uses the 12-hex cwd hash"
done
for f in handoff handoff-claude; do
  assert_contains "$(cat "$REPO/skills/$f/SKILL.md")" '<!-- handoff cwd="<abs-cwd>" created="<epoch-int>" -->' "$f skill writes the shared header"
  assert_contains "$(cat "$REPO/skills/$f/SKILL.md")" "under ~8,000 bytes" "$f skill has the 8,000-byte budget"
  assert_contains "$(cat "$REPO/skills/$f/SKILL.md")" '`<thread id from step 1, or "unknown"> — <rollout path from step 1, or "unknown"> — <YYYY-MM-DD>`' "$f skill uses the shared session-chain format"
done
assert_contains "$(cat "$REPO/skills/handoff-claude/SKILL.md")" 'STATE_DIR="$HOME/.claude-swap-backup"' "handoff-claude writes overclaude's pending dir"

rm -rf "$HOME"
finish
