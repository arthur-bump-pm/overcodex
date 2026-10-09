#!/bin/bash
# config.toml handling (H3/H4/H5/M4/M7 + LOW template fixes): Codex-written
# tables inside overcodex's marker blocks survive install refreshes and
# uninstall; only shipped content is removed; Codex's own [hooks.state] does not
# count as user hooks; nothing is written without a TOML validator; an inline
# tui table only skips the status line; changed shipped blocks are refreshed.
. "$(dirname "$0")/lib.sh"
new_home
CFG="$CODEX_HOME/config.toml"
H="$CODEX_HOME/hooks"
A="$CODEX_HOME/agents"
inst()   { bash "$REPO/install.sh" > "$HOME/$1.log" 2>&1; }
uninst() { bash "$REPO/uninstall.sh" > "$HOME/$1.log" 2>&1; }

# --- H3 + M7: a 0.2.0-era install that Codex has written into ---------------
# (`codex features enable ...` -> [features], the full-access notice -> [notice]
# inside the agent-roles block; hook trust -> [hooks.state."..."] inside the
# hooks block — exactly where Codex's toml_edit writer puts them.)
cat > "$CFG" <<EOF
model = "gpt-5.6-sol"
model_reasoning_effort = "high"

[mcp_servers.docs]
command = "docs-mcp"

# --- overcodex hooks (begin) ---
# overcodex hook wiring — TOML fragment. install.sh substitutes $H
# with the resolved absolute \$CODEX_HOME/hooks.

[[hooks.SessionStart]]
[[hooks.SessionStart.hooks]]
type = "command"
command = "bash $H/overcodex-handoff-inject.sh"
timeout = 10

[[hooks.UserPromptSubmit]]
[[hooks.UserPromptSubmit.hooks]]
type = "command"
command = "bash $H/overcodex-ctx-watch.sh"
timeout = 5

[[hooks.Stop]]
[[hooks.Stop.hooks]]
type = "command"
command = "bash $H/overcodex-notify.sh"
timeout = 5

[[hooks.PreCompact]]
[[hooks.PreCompact.hooks]]
type = "command"
command = "bash $H/overcodex-precompact-offer.sh"
timeout = 5

[hooks.state."$CFG:session_start:0:0"]
trusted_hash = "sha256:aaaa"

[hooks.state."$HOME/.codex-accounts/work/config.toml:stop:0:0"]
trusted_hash = "sha256:bbbb"
# --- overcodex hooks (end) ---

# --- overcodex agent roles (begin) ---
# overcodex custom-agent registration. install.sh substitutes @AGENTS_DIR@.
[agents]
max_threads = 4
max_depth = 1

[agents.scout-luna-low]
description = "Fast read-only scout for discovery, inventory, and extraction."
config_file = "$A/scout-luna-low.toml"

[agents.worker-terra-medium]
description = "Bounded implementation worker with explicit file ownership."
config_file = "$A/worker-terra-medium.toml"

[agents.reviewer-sol-high]
description = "Independent correctness, security, regression, and test reviewer."
config_file = "$A/reviewer-sol-high.toml"

[agents.judge-sol-xhigh]
description = "Adjudicator for contradictory or subtle high-risk verdicts."
config_file = "$A/judge-sol-xhigh.toml"

[notice]
hide_full_access_warning = true

[features]
web_search_request = true
# --- overcodex agent roles (end) ---
EOF
cp "$CFG" "$HOME/before-upgrade.toml"

inst up1
L="$(cat "$HOME/up1.log")"
assert_eq "$?" "0" "upgrade install runs"
assert_true 'toml_valid "$CFG"' "upgraded config.toml is valid TOML"
assert_contains "$L" "refreshed the overcodex [hooks] block" "M7: a changed shipped hooks block is refreshed"
assert_contains "$L" "Codex will not run them until you trust them" "M7: changed hooks block prints the re-trust notice"
assert_contains "$L" "moved settings Codex wrote inside the agent-roles block" "H3: install reports moving foreign tables out"
assert_eq "$(toml "$CFG" 'd["notice"]["hide_full_access_warning"]')" "true" "H3: [notice] survives the refresh"
assert_eq "$(toml "$CFG" 'd["features"]["web_search_request"]')" "true" "H3: [features] survives the refresh"
assert_eq "$(toml "$CFG" "d['hooks']['state']['$CFG:session_start:0:0']['trusted_hash']")" "sha256:aaaa" "H3: hook trust record survives"
assert_eq "$(toml "$CFG" "d['hooks']['state']['$HOME/.codex-accounts/work/config.toml:stop:0:0']['trusted_hash']")" "sha256:bbbb" "H3: other account's trust record survives"
assert_absent "$(block_body "$CFG" 'agent roles')" "[notice]" "H3: [notice] now sits outside the agent-roles block"
assert_absent "$(block_body "$CFG" hooks)" "[hooks.state.\"" "H3: trust records now sit outside the hooks block"
assert_eq "$(toml "$CFG" 'd["hooks"]["SessionStart"][0]["matcher"]')" "startup" "M2: SessionStart matcher = startup"
assert_eq "$(toml "$CFG" 'd["hooks"]["SessionStart"][0]["hooks"][0]["additionalContextLimit"]')" "8000" "M2: additionalContextLimit set on the handler"
assert_eq "$(toml "$CFG" 'len(d["hooks"]["Stop"])')" "1" "refresh does not duplicate hook groups"
assert_eq "$(toml "$CFG" 'd["mcp_servers"]["docs"]["command"]')" "docs-mcp" "unrelated settings untouched"
assert_contains "$(block_body "$CFG" hooks)" "substitutes @HOOKS_DIR@ on non-comment lines" "LOW: @HOOKS_DIR@ is not substituted inside comments"
assert_contains "$(block_body "$CFG" hooks)" "command = \"bash '$H/overcodex-notify.sh'\"" "hooks dir substituted in commands"
assert_contains "$(block_body "$CFG" 'agent roles')" "install.sh substitutes @AGENTS_DIR@" "LOW: @AGENTS_DIR@ is not substituted inside comments"
assert_contains "$L" "[ok] SessionStart hook registered" "H4: verify checks the actual hook commands"

cp "$CFG" "$HOME/after-upgrade.toml"
inst up2
assert_true 'cmp -s "$CFG" "$HOME/after-upgrade.toml"' "re-install after the upgrade is a byte no-op"
assert_contains "$(cat "$HOME/up2.log")" "changed:  0" "re-install reports nothing changed"
assert_absent "$(cat "$HOME/up2.log")" "trust them (again)" "no re-trust notice when hooks did not change"

# Codex writes again, this time INSIDE the new hooks block (as its writer would
# with no sentinel), then the user uninstalls.
"$PY" - "$CFG" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
end = "# --- overcodex hooks (end) ---"
s = s.replace(end, '[hooks.state."late:pre_compact:0:0"]\ntrusted_hash = "sha256:cccc"\n\n[profiles.fast]\nmodel = "gpt-6-luna"\n' + end)
open(p, "w").write(s)
PY
uninst un1
U="$(cat "$HOME/un1.log")"
assert_true 'toml_valid "$CFG"' "uninstalled config.toml is valid TOML"
assert_contains "$U" "removed hooks block from config.toml" "uninstall removes the hooks block"
assert_contains "$U" "kept the settings Codex had written inside those blocks" "uninstall reports keeping foreign tables"
assert_eq "$(grep -c '^# --- overcodex\|^# overcodex:' "$CFG")" "0" "no overcodex markers or sentinel remain"
assert_eq "$(toml "$CFG" '"SessionStart" in d.get("hooks", {})')" "false" "overcodex hook handlers removed"
assert_eq "$(toml "$CFG" '"agents" in d')" "false" "overcodex agent roles removed"
assert_eq "$(toml "$CFG" '"status_line" in d.get("tui", {})')" "false" "overcodex status line removed"
assert_eq "$(toml "$CFG" 'd["notice"]["hide_full_access_warning"]')" "true" "H3: [notice] survives uninstall"
assert_eq "$(toml "$CFG" 'd["features"]["web_search_request"]')" "true" "H3: [features] survives uninstall"
assert_eq "$(toml "$CFG" 'd["hooks"]["state"]["late:pre_compact:0:0"]["trusted_hash"]')" "sha256:cccc" "H3: a trust record written inside the block survives uninstall"
assert_eq "$(toml "$CFG" "d['hooks']['state']['$CFG:session_start:0:0']['trusted_hash']")" "sha256:aaaa" "H3: earlier trust records survive uninstall"
assert_eq "$(toml "$CFG" 'd["profiles"]["fast"]["model"]')" "gpt-6-luna" "H3: an unrelated table written inside the block survives uninstall"
assert_eq "$(toml "$CFG" 'd["model"]')" "gpt-5.6-sol" "top-level settings survive uninstall"

# --- H4: only Codex's own [hooks.state] -> still wired, verify is honest ------
new_home
CFG="$CODEX_HOME/config.toml"
printf '%s\n' 'model = "gpt-6-astra"' '' '[hooks.state."x:stop:0:0"]' 'trusted_hash = "sha256:1"' > "$CFG"
inst h4
L="$(cat "$HOME/h4.log")"
assert_contains "$L" "wired the overcodex [hooks] table" "H4: [hooks.state] alone does not block hook wiring"
assert_eq "$(toml "$CFG" 'sorted(k for k in d["hooks"] if k != "state")')" "['PreCompact', 'SessionStart', 'Stop', 'UserPromptSubmit']" "H4: all four events wired"
assert_eq "$(toml "$CFG" 'd["hooks"]["state"]["x:stop:0:0"]["trusted_hash"]')" "sha256:1" "H4: existing trust record kept"

# --- H4: a user's own hooks are left alone, and verify does NOT say [ok] -------
new_home
CFG="$CODEX_HOME/config.toml"
printf '%s\n' '[[hooks.Stop]]' '[[hooks.Stop.hooks]]' 'type = "command"' 'command = "say done"' > "$CFG"
cp "$CFG" "$HOME/user-hooks.toml"
inst h4b
L="$(cat "$HOME/h4b.log")"
assert_contains "$L" "already defines its own hooks" "H4: user-defined hooks are not overwritten"
assert_contains "$L" "SessionStart hook NOT registered" "H4: verify reports the missing overcodex hooks"
assert_absent "$L" "[ok] SessionStart hook registered" "H4: verify does not print [ok] for unwired hooks"
assert_eq "$(toml "$CFG" 'd["hooks"]["Stop"][0]["hooks"][0]["command"]')" "say done" "H4: the user's hook is untouched"

# --- H5: no TOML parser -> config.toml never written, re-install never appends ---
new_home
CFG="$CODEX_HOME/config.toml"
printf '%s\n' 'model = "gpt-6-astra"' > "$CFG"
cp "$CFG" "$HOME/orig.toml"
NOPY="OVERCODEX_PYTHON= OVERCODEX_PYTHON_CANDIDATES=no-such-python"
env $NOPY bash "$REPO/install.sh" > "$HOME/h5a.log" 2>&1
env $NOPY bash "$REPO/install.sh" > "$HOME/h5b.log" 2>&1
assert_true 'cmp -s "$CFG" "$HOME/orig.toml"' "H5: config.toml untouched without a validator (twice)"
assert_contains "$(cat "$HOME/h5a.log")" "config.toml NOT modified" "H5: clear refusal message"
assert_contains "$(cat "$HOME/h5a.log")" "overcodex install" "H5: points at overcodex install"
assert_true '[ -f "$CODEX_HOME/skills/handoff/SKILL.md" ]' "H5: the rest of the install still ran"
# a block from a previous (validated) install is recognized in grep mode
bash "$REPO/install.sh" > "$HOME/h5c.log" 2>&1
cp "$CFG" "$HOME/wired.toml"
env $NOPY bash "$REPO/install.sh" > "$HOME/h5d.log" 2>&1
assert_true 'cmp -s "$CFG" "$HOME/wired.toml"' "H5: no second hooks block appended in no-parser mode"
assert_contains "$(cat "$HOME/h5d.log")" "present but NOT verified" "H5: grep-mode verify recognizes the overcodex block"
env $NOPY bash "$REPO/uninstall.sh" > "$HOME/h5e.log" 2>&1
assert_true 'cmp -s "$CFG" "$HOME/wired.toml"' "H5: uninstall without a validator leaves config.toml alone"
assert_contains "$(cat "$HOME/h5e.log")" "config.toml NOT modified" "H5: uninstall says why"

# --- M4: inline tui table -> only the status line is skipped -------------------
new_home
CFG="$CODEX_HOME/config.toml"
printf '%s\n' 'model = "gpt-6-astra"' 'tui = { theme = "dark" }' > "$CFG"
inst m4
L="$(cat "$HOME/m4.log")"
assert_eq "$?" "0" "M4: install completes"
assert_true 'toml_valid "$CFG"' "M4: config stays valid TOML"
assert_contains "$L" "status_line" "M4: status_line step reports the skip"
assert_eq "$(toml "$CFG" 'd["tui"]')" "{'theme': 'dark'}" "M4: inline tui untouched"
assert_contains "$L" "wired the overcodex [hooks] table" "M4: hooks still wired"
assert_contains "$L" "registered custom [agents] roles" "M4: agent roles still wired"
assert_true '[ -f "$CODEX_HOME/AGENTS.md" ]' "M4: later install steps still ran"

# --- fresh install/uninstall is byte-identical; a symlinked config stays a link -
new_home
mkdir -p "$HOME/dotfiles"
printf '%s\n' 'model = "gpt-6-astra"' '' '[tui]' 'theme = "dark"' > "$HOME/dotfiles/codex.toml"
cp "$HOME/dotfiles/codex.toml" "$HOME/orig.toml"
ln -s "$HOME/dotfiles/codex.toml" "$CODEX_HOME/config.toml"
inst f1
assert_true '[ -L "$CODEX_HOME/config.toml" ]' "symlinked config.toml is still a symlink after install"
assert_eq "$(toml "$HOME/dotfiles/codex.toml" 'd["tui"]["theme"]')" "dark" "status line inserted into the existing [tui]"
assert_contains "$(cat "$HOME/dotfiles/codex.toml")" "[hooks.state]" "sentinel placed after the hooks block"
# Codex adds a tui key right after ours inside the status-line block
"$PY" - "$HOME/dotfiles/codex.toml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("# --- overcodex statusline (end) ---", 'animations = false\n# --- overcodex statusline (end) ---')
open(p, "w").write(s)
PY
uninst f2
assert_true '[ -L "$CODEX_HOME/config.toml" ]' "symlinked config.toml is still a symlink after uninstall"
assert_eq "$(toml "$HOME/dotfiles/codex.toml" 'sorted(d["tui"].items())')" "[('animations', False), ('theme', 'dark')]" "a foreign key Codex put inside the status-line block survives"
"$PY" - "$HOME/dotfiles/codex.toml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read().replace("animations = false\n", "")
open(p, "w").write(s)
PY
assert_true 'cmp -s "$HOME/dotfiles/codex.toml" "$HOME/orig.toml"' "install + uninstall restores the original bytes"

# --- semantic guard: a damaged marker pair is refused, not "fixed" -------------
new_home
CFG="$CODEX_HOME/config.toml"
printf '%s\n' 'model = "x"' '# --- overcodex hooks (begin) ---' '[[hooks.Stop]]' > "$CFG"
cp "$CFG" "$HOME/orig.toml"
inst g1
assert_contains "$(cat "$HOME/g1.log")" "damaged or duplicated overcodex hooks marker" "damaged markers are reported"
assert_true 'cmp -s "$CFG" "$HOME/orig.toml"' "damaged-marker config left untouched"

rm -rf "$HOME"
finish
