#!/bin/bash
# codex-swap: skills shared by symlink (H1), hook-trust next step (H2), stale
# marker falls back to primary (M1), JSON-escaped list --json that hides dirs
# `use` would reject, strict `path handoff` flags, remove resets the marker.
. "$(dirname "$0")/lib.sh"
new_home
unset CODEX_HOME
mkdir -p "$HOME/.codex/skills/handoff" "$HOME/.codex/hooks"
printf 'x\n' > "$HOME/.codex/AGENTS.md"
printf 'model = "gpt-6-astra"\n' > "$HOME/.codex/config.toml"

out="$("$CS" add work 2>&1)"
assert_eq "$(readlink "$HOME/.codex-accounts/work/skills")" "$HOME/.codex/skills" "H1: add links skills/ from primary"
assert_eq "$(readlink "$HOME/.codex-accounts/work/hooks")" "$HOME/.codex/hooks" "add links hooks/"
assert_contains "$out" "Trust the overcodex hooks for THIS account" "H2: add prints the per-account hook-trust step"
assert_contains "$out" "Trust all and continue" "H2: names the TUI choice"
assert_absent "$out" "prompts -> " "no prompts link when primary has no prompts/"

# An account Codex already started in has a real skills/ with only .system.
mkdir -p "$HOME/.codex-accounts/old/skills/.system/imagegen"
out="$("$CS" add old 2>&1)"
assert_eq "$(readlink "$HOME/.codex-accounts/old/skills")" "$HOME/.codex/skills" "H1: a Codex-created .system-only skills/ is replaced by the link"
mkdir -p "$HOME/.codex-accounts/mine/skills/my-skill"
out="$("$CS" add mine 2>&1)"
assert_eq "$([ -L "$HOME/.codex-accounts/mine/skills" ] && echo link || echo dir)" "dir" "a skills/ with the user's own skills is left alone"
assert_contains "$out" "leaving as-is" "and reported"

# list --json: valid JSON, escaped, hides names `use` would reject.
mkdir -p "$HOME/.codex-accounts/bad name" "$HOME/.codex-accounts/q\"uote" "$HOME/.codex-accounts/primary"
j="$("$CS" list --json)"
assert_eq "$(printf '%s' "$j" | jq -r 'map(.name) | join(",")')" "primary,mine,old,work" "list --json lists only usable accounts"
assert_eq "$(printf '%s' "$j" | jq -r '.[] | select(.name=="work") | .codexHome')" "$HOME/.codex-accounts/work" "codexHome per account"
json_str_out="$(bash -c ". '$CS'; json_str 'a\"b\\\\c'")"
assert_eq "$(printf '%s' "$json_str_out" | jq -r .)" 'a"b\\c' "json_str escapes quotes and backslashes"
nojq="$(PATH=/usr/bin:/bin bash -c "command() { [ \"\$2\" = jq ] && return 1; builtin command \"\$@\"; }; . '$CS'; json_str 'a\"b\\\\c'")"
assert_eq "$(printf '%s' "$nojq" | jq -r .)" 'a"b\\c' "json_str fallback (no jq) escapes too"

# use / which / stale marker.
"$CS" use work >/dev/null
assert_eq "$("$CS" which | head -n 1)" "work" "which reports the active account"
assert_eq "$("$CS" path handoff --cwd /tmp/x)" "$HOME/.codex-accounts/work/overcodex/handoff-pending-$(printf '%s' /tmp/x | /usr/bin/shasum -a 256 | cut -c1-12).md" "path handoff follows the active account"
assert_eq "$(CODEX_HOME=/elsewhere "$CS" path handoff --cwd /tmp/x | sed 's|/overcodex/.*||')" "/elsewhere" "a running session's CODEX_HOME wins"
mv "$HOME/.codex-accounts/work" "$HOME/work-moved"
assert_eq "$("$CS" which 2>/dev/null | head -n 1)" "primary" "M1: a marker naming a missing dir falls back to primary"
assert_contains "$("$CS" which 2>&1 >/dev/null)" "no longer exists" "M1: which warns about the stale marker"
assert_eq "$("$CS" path handoff --cwd /tmp/x | sed 's|/overcodex/.*||')" "$HOME/.codex" "M1: path handoff resolves primary for a stale marker"
assert_eq "$("$CS" list --json | jq -r '.[] | select(.active) | .name')" "primary" "M1: list marks primary active for a stale marker"
mv "$HOME/work-moved" "$HOME/.codex-accounts/work"

# path handoff flag handling.
"$CS" path handoff --cdw /tmp/x >/dev/null 2>&1; assert_eq "$?" "1" "path handoff rejects an unknown flag"
"$CS" path handoff --cwd >/dev/null 2>&1; assert_eq "$?" "1" "path handoff rejects --cwd without a value"
assert_eq "$("$CS" path handoff --cwd=/tmp/y | sed 's|.*-||')" "$(printf '%s' /tmp/y | /usr/bin/shasum -a 256 | cut -c1-12).md" "--cwd=D form works"

# remove resets the marker even though active_name already falls back.
"$CS" remove work --yes >/dev/null
assert_eq "$([ -f "$HOME/.codex-accounts/.active" ] && echo kept || echo reset)" "reset" "remove of the active account clears the marker"

rm -rf "$HOME"
finish
