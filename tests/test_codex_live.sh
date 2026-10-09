#!/bin/bash
# Live checks against the installed Codex CLI's `codex app-server` (JSON-RPC),
# in a throwaway HOME whose model provider is unreachable (127.0.0.1:9): turns
# start and fire hooks but never reach a model. Skipped when codex is absent.
#   H1  skills/list returns the five overcodex skills (primary + linked account);
#       a `$handoff-status` mention injects exactly that skill into the turn.
#   H2  hooks/list: our four hooks, per-account trust keys, untrusted until
#       trusted; trusted -> they run.
#   H3  Codex's own config writer (config/value/write) lands BELOW the blocks
#       (sentinel), and uninstall keeps what it wrote.
#   M1  SessionStart hook with CODEX_HOME unset resolves ~/.codex and injects.
#   M2  matcher "startup" + additionalContextLimit accepted (no warnings).
. "$(dirname "$0")/lib.sh"
if [ -n "${OVERCODEX_SKIP_LIVE:-}" ] || ! command -v codex >/dev/null 2>&1; then
  echo "test_codex_live.sh: SKIPPED (codex CLI not installed)"
  exit 0
fi
CODEX_BIN="$(command -v codex)"; export CODEX_BIN
RPC() { "$PY" "$REPO/tests/codex_rpc.py" "$@"; }
new_home
CFG="$CODEX_HOME/config.toml"
cat > "$CFG" <<'EOF'
model = "gpt-5.6-sol"
model_provider = "overcodex_test_dead"

[model_providers.overcodex_test_dead]
name = "unreachable test provider"
base_url = "http://127.0.0.1:9"
wire_api = "responses"
EOF
bash "$REPO/install.sh" > "$HOME/install.log" 2>&1
PROJ="$HOME/proj"; mkdir -p "$PROJ"

# --- H1: skills/list ----------------------------------------------------------
j="$(RPC "$HOME" "$CODEX_HOME" "$PROJ" skills hooks)"
names="$(printf '%s' "$j" | jq -r '[.skills.result.data[0].skills[] | select(.scope=="user") | .name] | sort | join(",")')"
assert_eq "$names" "handoff,handoff-cancel,handoff-claude,handoff-status,ultracode" "H1: skills/list returns the overcodex skills"
assert_eq "$(printf '%s' "$j" | jq -r '.skills.result.data[0].errors | length')" "0" "H1: no SKILL.md errors"

# --- H2/M2: hooks/list ----------------------------------------------------------
hk() { printf '%s' "$j" | jq -r "[.hooks.result.data[0].hooks[] | select(.command | contains(\"overcodex-\"))] | $1"; }
assert_eq "$(hk 'map(.eventName) | sort | join(",")')" "preCompact,sessionStart,stop,userPromptSubmit" "H2: the four overcodex hooks are registered"
assert_eq "$(hk 'map(.trustStatus) | unique | join(",")')" "untrusted" "H2: hooks start untrusted"
assert_eq "$(hk '.[] | select(.eventName=="sessionStart") | .matcher')" "startup" "M2: SessionStart matcher accepted"
assert_eq "$(hk '.[] | select(.eventName=="sessionStart") | .additionalContextLimit')" "8000" "M2: additionalContextLimit accepted"
assert_eq "$(printf '%s' "$j" | jq -r '.hooks.result.data[0] | (.warnings + .errors) | length')" "0" "no hook config warnings/errors (sentinel accepted)"
SS_KEY="$(hk '.[] | select(.eventName=="sessionStart") | .key')"
SS_HASH="$(hk '.[] | select(.eventName=="sessionStart") | .currentHash')"
assert_eq "$SS_KEY" "$CFG:session_start:0:0" "H2: trust key = <config path>:<event>:<group>:<handler>"

"$HOME/.local/bin/codex-swap" add work >/dev/null 2>&1
ACC="$HOME/.codex-accounts/work"
ja="$(RPC "$HOME" "$ACC" "$PROJ" skills hooks)"
assert_eq "$(printf '%s' "$ja" | jq -r '[.skills.result.data[0].skills[] | select(.scope=="user") | .name] | length')" "5" "H1: a codex-swap account sees the skills via its skills/ link"
assert_contains "$(printf '%s' "$ja" | jq -r '.hooks.result.data[0].hooks[0].key')" "$ACC/config.toml:" "H2: an account's trust key uses its own (uncanonicalized) path"

# --- H3: Codex's own writer -------------------------------------------------------
# (config/value/write splits keyPath on dots, so a real trust key — a path with
# dots — cannot go through it; a dot-free key exercises the same writer path.)
w="$(RPC "$HOME" "$CODEX_HOME" "$PROJ" \
  'write:notice.hide_full_access_warning=true' \
  'write:features.overcodex_test_flag=true' \
  'write:hooks.state.overcodex-test:stop:0:0.trusted_hash="sha256:feed"')"
assert_eq "$(printf '%s' "$w" | jq -r '[.writes[].result.status] | join(",")')" "ok,ok,ok" "Codex config writes succeed"
for b in hooks 'agent roles' statusline; do
  body="$(block_body "$CFG" "$b")"
  assert_absent "$body" "hide_full_access_warning" "H3: Codex's [notice] write lands outside the $b block"
  assert_absent "$body" "overcodex_test_flag" "H3: Codex's [features] write lands outside the $b block"
  assert_absent "$body" "trusted_hash" "H3: Codex's hook-trust write lands outside the $b block"
done
# Trust the SessionStart hook the way the TUI records it.
printf '\n[hooks.state."%s"]\ntrusted_hash = "%s"\n' "$SS_KEY" "$SS_HASH" >> "$CFG"
j="$(RPC "$HOME" "$CODEX_HOME" "$PROJ" hooks)"
assert_eq "$(hk '.[] | select(.eventName=="sessionStart") | .trustStatus')" "trusted" "H2: the trusted SessionStart hook reports trusted"
assert_eq "$(hk '.[] | select(.eventName=="stop") | .trustStatus')" "untrusted" "H2: trust is per hook"
d="$(cd "$PROJ" && PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$REPO/src" "$PY" -c 'import sys; from overcodex.doctor import main; sys.exit(main())' 2>&1)"; drc=$?
assert_contains "$d" "[ok] sessionStart      trusted" "H2: overcodex doctor shows the trusted hook"
assert_contains "$d" "[!] stop              untrusted" "H2: overcodex doctor flags untrusted hooks"
assert_contains "$d" "work  (CODEX_HOME=$ACC)" "H2: overcodex doctor checks every account"
assert_contains "$d" '[ok] skills: $handoff' "overcodex doctor sees the skills"
assert_eq "$drc" "1" "overcodex doctor exits 1 while any hook is untrusted"

# --- M1 + H1: a trusted SessionStart hook injects the package (CODEX_HOME unset) --
H12="$(printf '%s' "$PROJ" | /usr/bin/shasum -a 256 | awk '{print $1}' | cut -c1-12)"
mkdir -p "$CODEX_HOME/overcodex"
printf '<!-- handoff cwd="%s" created="%s" -->\n# Handoff — live\n\n## Goal\nLIVE-PACKAGE-MARKER\n' "$PROJ" "$(date +%s)" \
  > "$CODEX_HOME/overcodex/handoff-pending-$H12.md"
RPC_TURN_WAIT=4 RPC "$HOME" - "$PROJ" thread 'turn:$handoff-status' > "$HOME/turn.json"
RO="$(find "$CODEX_HOME/sessions" -name 'rollout-*.jsonl' | head -n 1)"
assert_true '[ -n "$RO" ]' "a rollout was written"
msgs="$(jq -r 'select(.type=="response_item") | .payload.content[]?.text // empty' "$RO" </dev/null 2>/dev/null)"
assert_contains "$msgs" "LIVE-PACKAGE-MARKER" "M1: SessionStart hook (no CODEX_HOME in its env) injected the ~/.codex package"
assert_contains "$msgs" "## Handoff from previous session (loaded by handoff-inject)" "M1: injected with the handoff heading"
assert_true '[ ! -f "$CODEX_HOME/overcodex/handoff-pending-$H12.md" ]' "M1: package archived after injection"
assert_contains "$msgs" "<name>handoff-status</name>" "H1: a \$handoff-status mention injects that skill"
assert_absent "$msgs" "<name>handoff</name>" "H1: ...and not the \$handoff skill"

# --- M2: a package above Codex's default ~2,500-token spill is injected whole ----
# (unset, Codex middle-truncates additionalContext: "…N tokens truncated…").
{ printf '<!-- handoff cwd="%s" created="%s" -->\n# Handoff — big\n\n## Goal\nBIG-START\n' "$PROJ" "$(date +%s)"
  i=0; while [ "$i" -lt 190 ]; do printf 'line %05d of a long English handoff package with distinct tokens.\n' "$i"; i=$((i + 1)); done
  printf 'BIG-END\n'; } > "$CODEX_HOME/overcodex/handoff-pending-$H12.md"
assert_true '[ "$(wc -c < "$CODEX_HOME/overcodex/handoff-pending-$H12.md")" -gt 12000 ]' "M2: test package is ~12 KB (>2,500 tokens)"
rm -rf "$CODEX_HOME/sessions"
RPC_TURN_WAIT=3 RPC "$HOME" - "$PROJ" thread 'turn:hi' > /dev/null
RO="$(find "$CODEX_HOME/sessions" -name 'rollout-*.jsonl' | head -n 1)"
msgs="$(jq -r 'select(.type=="response_item") | .payload.content[]?.text // empty' "$RO" </dev/null 2>/dev/null)"
assert_contains "$msgs" "BIG-END" "M2: the end of a ~12 KB package survives injection"
assert_absent "$msgs" "tokens truncated" "M2: no middle truncation with additionalContextLimit"
assert_eq "$(printf '%s\n' "$msgs" | grep -c '^line [0-9]* of a long')" "190" "M2: every line of the package was injected"

# --- H3: uninstall keeps what Codex wrote ------------------------------------------
bash "$REPO/uninstall.sh" > "$HOME/uninstall.log" 2>&1
assert_true 'toml_valid "$CFG"' "config valid after uninstall"
assert_eq "$(toml "$CFG" 'd["notice"]["hide_full_access_warning"]')" "true" "H3: Codex's [notice] survives uninstall"
assert_eq "$(toml "$CFG" 'd["features"]["overcodex_test_flag"]')" "true" "H3: Codex's [features] survives uninstall"
assert_eq "$(toml "$CFG" "d['hooks']['state']['$SS_KEY']['trusted_hash']")" "$SS_HASH" "H3: the trust record survives uninstall"
assert_eq "$(toml "$CFG" "d['hooks']['state']['overcodex-test:stop:0:0']['trusted_hash']")" "sha256:feed" "H3: Codex's hooks.state write survives uninstall"
j="$(RPC "$HOME" "$CODEX_HOME" "$PROJ" hooks)"
assert_eq "$(hk 'length')" "0" "no overcodex hooks after uninstall"

# app-server children can still be flushing into $HOME/.codex/.tmp for a moment.
rm -rf "$HOME" 2>/dev/null || { sleep 2; rm -rf "$HOME" 2>/dev/null; }
finish
