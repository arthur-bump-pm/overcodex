#!/usr/bin/env bash
# End-to-end smoke test in an isolated HOME. No live Codex state is touched.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# A python3 with tomllib/tomli (stock macOS /usr/bin/python3 3.9 has neither);
# exported so install.sh uses it exactly as `overcodex install` passes its own.
PY=""
for c in "${OVERCODEX_TEST_PYTHON:-}" python3.14 python3.13 python3.12 python3.11 python3 /usr/bin/python3; do
  [ -n "$c" ] || continue
  command -v "$c" >/dev/null 2>&1 || continue
  if "$c" "$ROOT/lib/overcodex_config.py" check >/dev/null 2>&1; then PY="$c"; break; fi
done
[ -n "$PY" ] || { echo "smoke: no python3 with tomllib/tomli" >&2; exit 1; }
export OVERCODEX_PYTHON="$PY"
python3() { "$PY" "$@"; }
test -f "$ROOT/AGENTS.md"
grep -q 'UltraCode planning gate' "$ROOT/AGENTS.md"
test -f "$ROOT/AGENT-SETUP.md"
grep -q '## Codex' "$ROOT/AGENT-SETUP.md"
grep -q '## OpenClaw' "$ROOT/AGENT-SETUP.md"
! grep -q 'get_context_remaining' "$ROOT/README.md"
grep -q 'context-remaining' "$ROOT/README.md"
T=$(mktemp -d "${TMPDIR:-/tmp}/overcodex-smoke.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM

export HOME="$T/home"
export CODEX_HOME="$HOME/.codex"
export PATH="$HOME/.local/bin:$PATH"
mkdir -p "$CODEX_HOME"
printf 'model = "gpt-5.6-sol"\nmodel_reasoning_effort = "high"\n' > "$CODEX_HOME/config.toml"

bash "$ROOT/install.sh" > "$T/install-1.log" 2>&1
python3 - "$CODEX_HOME/config.toml" <<'PY'
import sys
try:
    import tomllib
except ImportError:
    import tomli as tomllib
with open(sys.argv[1], "rb") as f:
    config = tomllib.load(f)
assert set(config["hooks"]) - {"state"} == {"SessionStart", "UserPromptSubmit", "Stop", "PreCompact"}
assert config["hooks"]["SessionStart"][0]["matcher"] == "startup"
assert config["hooks"]["SessionStart"][0]["hooks"][0]["additionalContextLimit"] == 8000
assert config["model_reasoning_effort"] in {"low", "medium", "high", "xhigh", "max", "ultra"}
assert {"scout-luna-low", "worker-terra-medium", "reviewer-sol-high", "judge-sol-xhigh"}.issubset(config["agents"])
assert config["agents"]["scout-luna-low"]["config_file"].endswith("/agents/scout-luna-low.toml")
assert config["tui"]["status_line"] == [
    "model-with-reasoning",
    "current-dir",
    "project-name",
    "context-remaining",
    "five-hour-limit",
    "weekly-limit",
]
assert config["tui"]["status_line_use_colors"] is True
PY

for name in scout-luna-low worker-terra-medium reviewer-sol-high judge-sol-xhigh; do
  test -f "$CODEX_HOME/agents/$name.toml"
done
for name in handoff handoff-status handoff-cancel handoff-claude ultracode; do
  test -f "$CODEX_HOME/skills/$name/SKILL.md"
  head -n 1 "$CODEX_HOME/skills/$name/SKILL.md" | grep -qx -- '---'
  grep -q "^name: $name\$" "$CODEX_HOME/skills/$name/SKILL.md"
done
test ! -e "$CODEX_HOME/prompts"
if command -v codex >/dev/null 2>&1; then
  CODEX_HOME="$CODEX_HOME" command codex features list > "$T/codex-parse.log" 2>&1
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
grep -q 'changed:  0' "$T/install-2.log" || { cat "$T/install-2.log" >&2; exit 1; }
sed -i '' 's/# ULTRACODE - Codex multi-agent routing policy/# stale policy/' "$CODEX_HOME/AGENTS.md"
bash "$ROOT/install.sh" > "$T/install-3.log" 2>&1
grep -q 'refreshed overcodex ultracode block' "$T/install-3.log"
grep -q '^# ULTRACODE - Codex multi-agent routing policy$' "$CODEX_HOME/AGENTS.md"

# A user-selected native status line remains untouched on a separate isolated install.
PRESERVE_HOME="$T/preserve-home"
PRESERVE_CODEX_HOME="$PRESERVE_HOME/.codex"
mkdir -p "$PRESERVE_CODEX_HOME"
printf '%s\n' '[tui]' 'status_line = ["model-with-reasoning", "current-dir"]' > "$PRESERVE_CODEX_HOME/config.toml"
HOME="$PRESERVE_HOME" CODEX_HOME="$PRESERVE_CODEX_HOME" PATH="$PRESERVE_HOME/.local/bin:$PATH" \
  bash "$ROOT/install.sh" > "$T/install-preserve-statusline.log" 2>&1
python3 - "$PRESERVE_CODEX_HOME/config.toml" <<'PY'
import sys
try:
    import tomllib
except ImportError:
    import tomli as tomllib
with open(sys.argv[1], "rb") as f:
    config = tomllib.load(f)
assert config["tui"]["status_line"] == ["model-with-reasoning", "current-dir"]
assert "status_line_use_colors" not in config["tui"]
PY

# A color preference without a status line remains intact while defaults add the line.
COLOR_ONLY_HOME="$T/color-only-home"
COLOR_ONLY_CODEX_HOME="$COLOR_ONLY_HOME/.codex"
mkdir -p "$COLOR_ONLY_CODEX_HOME"
printf '%s\n' '[tui]' 'status_line_use_colors = false' > "$COLOR_ONLY_CODEX_HOME/config.toml"
HOME="$COLOR_ONLY_HOME" CODEX_HOME="$COLOR_ONLY_CODEX_HOME" PATH="$COLOR_ONLY_HOME/.local/bin:$PATH" \
  bash "$ROOT/install.sh" > "$T/install-color-only-statusline.log" 2>&1
python3 - "$COLOR_ONLY_CODEX_HOME/config.toml" <<'PY'
import sys
try:
    import tomllib
except ImportError:
    import tomli as tomllib
with open(sys.argv[1], "rb") as f:
    config = tomllib.load(f)
assert config["tui"]["status_line"] == [
    "model-with-reasoning",
    "current-dir",
    "project-name",
    "context-remaining",
    "five-hour-limit",
    "weekly-limit",
]
assert config["tui"]["status_line_use_colors"] is False
PY

# Handoff interop with overclaude: the reverse skill ships, and the pending path uses
# the shared 12-hex sha256-of-cwd convention under the session's CODEX_HOME.
grep -q 'claude-swap-backup/handoff-pending-' "$CODEX_HOME/skills/handoff-claude/SKILL.md" \
  || grep -q 'STATE_DIR="$HOME/.claude-swap-backup"' "$CODEX_HOME/skills/handoff-claude/SKILL.md"
want="$CODEX_HOME/overcodex/handoff-pending-$(printf '%s' /tmp/smoke-cwd | /usr/bin/shasum -a 256 | cut -c1-12).md"
test "$("$HOME/.local/bin/codex-swap" path handoff --cwd /tmp/smoke-cwd)" = "$want"

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
