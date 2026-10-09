#!/bin/bash
# Regressions from the hostile-sandbox review: marker blocks in AGENTS.md /
# .zshrc (damaged markers, CRLF, quoted markers), per-handler hook ownership,
# per-key role ownership, file modes, a user's own same-named skill, CRLF
# config.toml, markers inside TOML strings, the orphan sentinel comment, and a
# wheel check that cannot be skipped quietly.
. "$(dirname "$0")/lib.sh"
inst()   { bash "$REPO/install.sh" > "$HOME/$1.log" 2>&1; }
uninst() { bash "$REPO/uninstall.sh" > "$HOME/$1.log" 2>&1; }
mode()   { stat -f %Lp "$1"; }
CR=$(printf '\r')
ZEND='# --- overcodex integration (end) ---'
AEND='# --- overcodex ultracode (end) ---'
ABEGIN='# --- overcodex ultracode (begin) ---'

# --- FIX 1: a damaged end marker never makes uninstall eat the rest of the file
new_home
inst f1a
"$PY" - "$HOME/.zshrc" "$ZEND" <<'PY'
import sys
p, end = sys.argv[1], sys.argv[2]
s = open(p).read().replace(end + "\n", end + " \n")
open(p, "w").write(s + "export AFTER_BLOCK=1\nalias keepme='echo kept'\n")
PY
cp "$HOME/.zshrc" "$HOME/zshrc.before"
uninst f1b
assert_true 'cmp -s "$HOME/.zshrc" "$HOME/zshrc.before"' "FIX 1: .zshrc with an edited end marker is left untouched"
assert_contains "$(cat "$HOME/.zshrc")" "alias keepme='echo kept'" "FIX 1: user lines after the block survive (reviewer repro)"
assert_contains "$(cat "$HOME/f1b.log")" "markers are damaged" "FIX 1: uninstall warns instead of stripping"
assert_absent "$(cat "$HOME/f1b.log")" "removed integration block" "FIX 1: and does not claim it removed anything"
# AGENTS.md with the end marker deleted outright (the reviewer's other repro)
printf '%s\n' '# my rules' "$ABEGIN" 'policy' '# my later rules' > "$CODEX_HOME/AGENTS.md"
cp "$CODEX_HOME/AGENTS.md" "$HOME/agents.before"
uninst f1c
assert_true 'cmp -s "$CODEX_HOME/AGENTS.md" "$HOME/agents.before"' "FIX 1: AGENTS.md without an end marker is left untouched"
inst f1d
assert_true 'cmp -s "$CODEX_HOME/AGENTS.md" "$HOME/agents.before"' "FIX 1: install also refuses (no append, no die)"
assert_contains "$(cat "$HOME/f1d.log")" "markers are damaged" "FIX 1: install warns about the damaged markers"
assert_contains "$(cat "$HOME/f1d.log")" "Done." "FIX 1: install still completes"

# --- FIX 8: CRLF files and quoted markers ---------------------------------------
new_home
inst f8a
sed -i '' "s/\$/$CR/" "$CODEX_HOME/AGENTS.md" "$HOME/.zshrc"
sed -i '' "s/^# ULTRACODE - Codex multi-agent routing policy$CR\$/# stale policy$CR/" "$CODEX_HOME/AGENTS.md"
inst f8b
L="$(cat "$HOME/f8b.log")"
assert_contains "$L" "refreshed overcodex ultracode block" "FIX 8: a stale CRLF block is refreshed, not reported up-to-date"
assert_contains "$(cat "$CODEX_HOME/AGENTS.md")" "# ULTRACODE - Codex multi-agent routing policy" "FIX 8: refreshed content landed"
assert_eq "$(LC_ALL=C grep -c "[^$CR]\$" "$CODEX_HOME/AGENTS.md")" "0" "FIX 8: refreshed CRLF AGENTS.md stays all-CRLF"
assert_contains "$L" "overcodex integration block already up-to-date" "FIX 8: an intact CRLF .zshrc block is recognized as up to date"
uninst f8c
U="$(cat "$HOME/f8c.log")"
assert_contains "$U" "removed integration block" "FIX 8: uninstall removes a CRLF .zshrc block"
assert_eq "$(grep -c 'overcodex integration' "$HOME/.zshrc" 2>/dev/null || true)" "0" "FIX 8: ...and it is really gone"
assert_true '[ ! -e "$CODEX_HOME/AGENTS.md" ] || ! grep -q "overcodex ultracode (begin)" "$CODEX_HOME/AGENTS.md"' "FIX 8: CRLF AGENTS.md block really removed"
# a marker quoted in a code fence (whole line) and one quoted mid-line
new_home
printf '%s\n' '# Notes' '```' "$ABEGIN" '```' > "$CODEX_HOME/AGENTS.md"
cp "$CODEX_HOME/AGENTS.md" "$HOME/fence.before"
inst f8d
assert_contains "$(cat "$HOME/f8d.log")" "Done." "FIX 8: a marker quoted in a code fence does not kill install"
assert_true 'cmp -s "$CODEX_HOME/AGENTS.md" "$HOME/fence.before"' "FIX 8: that AGENTS.md is left untouched"
assert_true '[ -f "$HOME/.zshrc" ]' "FIX 8: later install steps still ran"
new_home
printf '%s\n' "The block starts at \`$ABEGIN\` in the global file." > "$CODEX_HOME/AGENTS.md"
inst f8e
assert_contains "$(cat "$HOME/f8e.log")" "appended overcodex ultracode block" "FIX 8: a marker quoted mid-line is not a marker"
uninst f8f
assert_eq "$(cat "$CODEX_HOME/AGENTS.md")" "The block starts at \`$ABEGIN\` in the global file." "FIX 8: ...and uninstall keeps that line"

# --- FIX 2: hook ownership is per handler, by exact command ----------------------
new_home
CFG="$CODEX_HOME/config.toml"
inst f2a
"$PY" - "$CFG" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
end = "# --- overcodex hooks (end) ---"
add = ('[[hooks.Stop.hooks]]\ntype = "command"\ncommand = "say done"\n\n'
       '[[hooks.UserPromptSubmit]]\n[[hooks.UserPromptSubmit.hooks]]\ntype = "command"\n'
       'command = "bash ~/bin/my-overcodex-notify.sh"\n')
s = s.replace(end, add + end)
# a user handler inside the overcodex SessionStart group (matcher = "startup")
s = s.replace("additionalContextLimit = 8000\n", 'additionalContextLimit = 8000\n\n[[hooks.SessionStart.hooks]]\ntype = "command"\ncommand = "echo user-start"\n', 1)
open(p, "w").write(s)
PY
# appended before the end marker it would join the last (PreCompact) group;
# put it right after overcodex's Stop handler instead, i.e. inside our group:
"$PY" - "$CFG" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
blk = '[[hooks.Stop.hooks]]\ntype = "command"\ncommand = "say done"\n\n'
s = s.replace(blk, "")
s = s.replace("overcodex-notify.sh'\"\ntimeout = 5\n", "overcodex-notify.sh'\"\ntimeout = 5\n\n" + blk, 1)
open(p, "w").write(s)
PY
cmds() { toml "$CFG" "sorted((ev, g.get('matcher'), h['command']) for ev, gs in d.get('hooks', {}).items() if ev != 'state' for g in gs for h in g.get('hooks', []))"; }
assert_contains "$(cmds)" "('Stop', None, 'say done')" "FIX 2 setup: user handler sits in the overcodex Stop group"
inst f2b
C="$(cmds)"
assert_contains "$C" "('Stop', None, 'say done')" "FIX 2: reinstall keeps a user handler added to an overcodex group"
assert_contains "$C" "'bash ~/bin/my-overcodex-notify.sh')" "FIX 2: reinstall keeps a user command that merely contains 'overcodex-'"
assert_contains "$C" "('SessionStart', 'startup', 'echo user-start')" "FIX 2: the user handler keeps its group's matcher"
assert_eq "$(toml "$CFG" "sum(1 for g in d['hooks']['Stop'] for h in g['hooks'] if 'overcodex-notify.sh' in h['command'] and 'my-' not in h['command'])")" "1" "FIX 2: overcodex's own Stop handler is not duplicated"
uninst f2c
C="$(cmds)"
assert_contains "$C" "('Stop', None, 'say done')" "FIX 2: uninstall keeps the user handler"
assert_contains "$C" "'bash ~/bin/my-overcodex-notify.sh')" "FIX 2: uninstall keeps my-overcodex-notify.sh"
assert_contains "$C" "('SessionStart', 'startup', 'echo user-start')" "FIX 2: uninstall keeps the user SessionStart handler with its matcher"
assert_absent "$C" "$CODEX_HOME/hooks/overcodex-" "FIX 2: overcodex's own handlers are gone"

# --- FIX 3: only shipped keys of a role table are overcodex's -----------------------
new_home
CFG="$CODEX_HOME/config.toml"
inst f3a
"$PY" - "$CFG" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('[agents.reviewer-sol-high]\n', '[agents.reviewer-sol-high]\nmodel = "gpt-6-sol"\nsandbox_mode = "workspace-write"\n', 1)
s = s.replace('description = "Fast read-only scout for discovery, inventory, and extraction."', 'description = "stale text from an older release"', 1)
open(p, "w").write(s)
PY
inst f3b
assert_contains "$(cat "$HOME/f3b.log")" "refreshed the custom [agents] roles" "FIX 3 setup: the role block was refreshed"
assert_eq "$(toml "$CFG" 'd["agents"]["reviewer-sol-high"].get("model")')" "gpt-6-sol" "FIX 3: a user-added key in a shipped role survives refresh"
assert_eq "$(toml "$CFG" 'd["agents"]["reviewer-sol-high"].get("sandbox_mode")')" "workspace-write" "FIX 3: a second user key survives too"
assert_contains "$(toml "$CFG" 'd["agents"]["scout-luna-low"]["description"]')" "Fast read-only scout" "FIX 3: shipped keys are refreshed"
uninst f3c
assert_eq "$(toml "$CFG" 'd["agents"]["reviewer-sol-high"]')" "{'model': 'gpt-6-sol', 'sandbox_mode': 'workspace-write'}" "FIX 3: uninstall keeps only the user's role keys"
assert_eq "$(toml "$CFG" '"scout-luna-low" in d["agents"]')" "false" "FIX 3: overcodex's untouched roles are removed"

# --- FIX 4: file modes survive every rewrite ----------------------------------------
new_home
mkdir -p "$HOME/dot"
printf 'model = "gpt-6-astra"\n' > "$HOME/dot/codex.toml"; chmod 600 "$HOME/dot/codex.toml"
ln -s "$HOME/dot/codex.toml" "$CODEX_HOME/config.toml"
printf '# mine\n' > "$CODEX_HOME/AGENTS.md"; chmod 600 "$CODEX_HOME/AGENTS.md"
printf '# zsh\n' > "$HOME/.zshrc"; chmod 640 "$HOME/.zshrc"
inst f4a
assert_eq "$(mode "$HOME/dot/codex.toml")" "600" "FIX 4: config.toml (symlink target) stays 0600 after install"
sed -i '' 's/^# ULTRACODE - Codex multi-agent routing policy$/# stale/' "$CODEX_HOME/AGENTS.md"; chmod 600 "$CODEX_HOME/AGENTS.md"
inst f4b
assert_contains "$(cat "$HOME/f4b.log")" "refreshed overcodex ultracode block" "FIX 4 setup: AGENTS.md refreshed via temp file"
assert_eq "$(mode "$CODEX_HOME/AGENTS.md")" "600" "FIX 4: AGENTS.md stays 0600 after a refresh"
uninst f4c
assert_eq "$(mode "$HOME/dot/codex.toml")" "600" "FIX 4: config.toml stays 0600 after uninstall"
assert_eq "$(mode "$CODEX_HOME/AGENTS.md")" "600" "FIX 4: AGENTS.md stays 0600 after uninstall"
assert_eq "$(mode "$HOME/.zshrc")" "640" "FIX 4: .zshrc keeps its mode after uninstall"
assert_true '[ -L "$CODEX_HOME/config.toml" ]' "FIX 4: config.toml is still a symlink"

# --- FIX 5: a user's own same-named skill is never overwritten or deleted ----------
new_home
inst f5a
ACC="$HOME/.codex-accounts/work"
mkdir -p "$ACC/skills/handoff"
printf -- '---\nname: handoff\ndescription: my own handoff\n---\n# My handoff\n' > "$ACC/skills/handoff/SKILL.md"
cp "$ACC/skills/handoff/SKILL.md" "$HOME/myskill"
CODEX_HOME="$ACC" bash "$REPO/install.sh" > "$HOME/f5b.log" 2>&1
assert_true 'cmp -s "$ACC/skills/handoff/SKILL.md" "$HOME/myskill"' "FIX 5: install leaves the user's own handoff skill alone"
assert_contains "$(cat "$HOME/f5b.log")" "is not overcodex's copy" "FIX 5: install warns about it"
assert_true '[ -f "$ACC/skills/handoff-status/SKILL.md" ]' "FIX 5: the other skills are still installed there"
CODEX_HOME="$ACC" bash "$REPO/uninstall.sh" > "$HOME/f5c.log" 2>&1
assert_true 'cmp -s "$ACC/skills/handoff/SKILL.md" "$HOME/myskill"' "FIX 5: uninstall keeps the user's skill"
assert_true '[ ! -e "$ACC/skills/handoff-status" ]' "FIX 5: uninstall removes overcodex's skills"

# --- FIX 7: a CRLF config.toml stays CRLF ---------------------------------------------
new_home
CFG="$CODEX_HOME/config.toml"
printf 'model = "gpt-6-astra"\r\n\r\n[tui]\r\ntheme = "dark"\r\n' > "$CFG"
cp "$CFG" "$HOME/crlf.before"
inst f7a
assert_true 'toml_valid "$CFG"' "FIX 7: CRLF config still valid after install"
assert_eq "$(LC_ALL=C grep -c "[^$CR]\$" "$CFG")" "0" "FIX 7: every line still ends in CRLF after install"
assert_contains "$(cat "$HOME/f7a.log")" "wired the overcodex [hooks] table" "FIX 7: hooks wired into the CRLF config"
uninst f7b
assert_true 'cmp -s "$CFG" "$HOME/crlf.before"' "FIX 7: install + uninstall restores the CRLF bytes"

# --- #9: marker text inside a multi-line string is not a marker -------------------------
new_home
CFG="$CODEX_HOME/config.toml"
printf '%s\n' 'notes = """' '# --- overcodex hooks (begin) ---' '"""' 'model = "x"' > "$CFG"
inst f9a
assert_contains "$(cat "$HOME/f9a.log")" "wired the overcodex [hooks] table" "#9: hooks still wired"
assert_eq "$(toml "$CFG" 'd["notes"]')" "# --- overcodex hooks (begin) ---" "#9: the string is untouched"
uninst f9b
assert_eq "$(toml "$CFG" 'sorted(d)')" "['model', 'notes']" "#9: uninstall leaves only the user's keys"

# --- #10a: an orphan sentinel comment is removed by uninstall ----------------------------
new_home
CFG="$CODEX_HOME/config.toml"
inst f10a
"$PY" - "$CFG" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read().replace("[hooks.state]\n", '[hooks.state."k:stop:0:0"]\ntrusted_hash = "sha256:1"\n')
open(p, "w").write(s)
PY
uninst f10b
assert_eq "$(grep -c '^# overcodex:' "$CFG")" "0" "#10a: orphan sentinel comment removed"
assert_eq "$(toml "$CFG" 'd["hooks"]["state"]["k:stop:0:0"]["trusted_hash"]')" "sha256:1" "#10a: the trust record next to it survives"

# --- #11: the wheel check cannot pass quietly when required -----------------------------
new_home
printf '#!/bin/bash\n[ "$1" = -c ] && [ "$2" = "import build" ] && exit 1\nexec "%s" "$@"\n' "$PY" > "$HOME/nobuild-python"
chmod +x "$HOME/nobuild-python"
o="$(OVERCODEX_TEST_PYTHON="$HOME/nobuild-python" OVERCODEX_REQUIRE_WHEEL=1 bash "$REPO/tests/test_payload.sh" 2>&1)"; rc=$?
assert_eq "$rc" "1" "#11: test_payload fails when the wheel check is required but impossible"
assert_contains "$o" "wheel check required" "#11: ...and says why"
o="$(env -u OVERCODEX_REQUIRE_WHEEL OVERCODEX_TEST_PYTHON="$HOME/nobuild-python" bash "$REPO/tests/test_payload.sh" 2>&1)"
assert_contains "$o" "wheel check skipped" "#11: an optional skip is announced, not silent"

finish
