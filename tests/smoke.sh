#!/usr/bin/env bash
# End-to-end smoke test in an isolated HOME. No live Codex state is touched.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
test -f "$ROOT/AGENTS.md"
grep -q 'UltraCode planning gate' "$ROOT/AGENTS.md"
test -f "$ROOT/AGENT-SETUP.md"
grep -q '## Codex' "$ROOT/AGENT-SETUP.md"
grep -q '## OpenClaw' "$ROOT/AGENT-SETUP.md"
T=$(mktemp -d "${TMPDIR:-/tmp}/overcodex-smoke.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM

export HOME="$T/home"
export CODEX_HOME="$HOME/.codex"
export PATH="$HOME/.local/bin:$PATH"
mkdir -p "$CODEX_HOME"
printf 'model = "gpt-5.6-sol"\nmodel_reasoning_effort = "high"\n' > "$CODEX_HOME/config.toml"

bash "$ROOT/install.sh" > "$T/install-1.log" 2>&1
python3 - "$CODEX_HOME/config.toml" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    config = tomllib.load(f)
assert set(config["hooks"]) == {"SessionStart", "UserPromptSubmit", "Stop", "PreCompact"}
assert config["model_reasoning_effort"] in {"none", "low", "medium", "high", "xhigh", "max"}
assert {"scout-luna-low", "worker-terra-medium", "reviewer-sol-high", "judge-sol-xhigh"}.issubset(config["agents"])
assert config["agents"]["scout-luna-low"]["config_file"].endswith("/agents/scout-luna-low.toml")
PY

for name in scout-luna-low worker-terra-medium reviewer-sol-high judge-sol-xhigh; do
  test -f "$CODEX_HOME/agents/$name.toml"
done
test -f "$CODEX_HOME/prompts/ultracode.md"
if command -v codex >/dev/null 2>&1; then
  CODEX_HOME="$CODEX_HOME" codex features list > "$T/codex-parse.log" 2>&1
fi

# Cumulative usage is intentionally above the window; current context is 80%.
TRANSCRIPT="$T/rollout.jsonl"
printf '%s\n' '{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":900000},"last_token_usage":{"total_tokens":160000},"model_context_window":200000}}}' > "$TRANSCRIPT"
printf '%s' "{\"session_id\":\"smoke-session\",\"transcript_path\":\"$TRANSCRIPT\",\"prompt\":\"continue\"}" \
  | bash "$CODEX_HOME/hooks/overcodex-ctx-watch.sh" > "$T/ctx-output.json"
jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit" and (.hookSpecificOutput.additionalContext | contains("80%"))' "$T/ctx-output.json" >/dev/null
jq -e '.fired == 75' "$CODEX_HOME/overcodex/ctx/smoke-session.state" >/dev/null

# A fresh cwd-scoped package is injected and archived exactly once.
CWD="$T/project"
mkdir -p "$CWD"
HASH=$(printf '%s' "$CWD" | /usr/bin/shasum -a 256 | awk '{print $1}' | cut -c1-12)
NOW=$(date +%s)
PENDING="$CODEX_HOME/overcodex/handoff-pending-$HASH.md"
printf '<!-- handoff cwd="%s" created="%s" -->\n# Handoff - smoke\n\n## Goal\nResume smoke test.\n' "$CWD" "$NOW" > "$PENDING"
printf '%s' "{\"source\":\"startup\",\"cwd\":\"$CWD\"}" \
  | bash "$CODEX_HOME/hooks/overcodex-handoff-inject.sh" > "$T/handoff-output.json"
jq -e '.hookSpecificOutput.hookEventName == "SessionStart" and (.hookSpecificOutput.additionalContext | contains("Resume smoke test"))' "$T/handoff-output.json" >/dev/null
test ! -f "$PENDING"

# Reinstall is a no-op; stale owned policy content is refreshed on upgrade.
bash "$ROOT/install.sh" > "$T/install-2.log" 2>&1
grep -q 'changed:  0' "$T/install-2.log"
sed -i '' 's/# ULTRACODE - Codex multi-agent routing policy/# stale policy/' "$CODEX_HOME/AGENTS.md"
bash "$ROOT/install.sh" > "$T/install-3.log" 2>&1
grep -q 'refreshed overcodex ultracode block' "$T/install-3.log"
grep -q '^# ULTRACODE - Codex multi-agent routing policy$' "$CODEX_HOME/AGENTS.md"

bash "$ROOT/uninstall.sh" > "$T/uninstall.log" 2>&1
for name in scout-luna-low worker-terra-medium reviewer-sol-high judge-sol-xhigh; do
  test ! -e "$CODEX_HOME/agents/$name.toml"
done
test ! -e "$HOME/.local/bin/codex-swap"
if grep -q 'overcodex \(ultracode\|hooks\|agent roles\|integration\)' \
  "$CODEX_HOME/config.toml" "$CODEX_HOME/AGENTS.md" "$HOME/.zshrc" 2>/dev/null; then
  echo "smoke: overcodex marker remained after uninstall" >&2
  exit 1
fi

echo "overcodex smoke: PASS"
