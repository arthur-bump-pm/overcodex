#!/bin/bash
# install.sh / uninstall.sh file handling: skills land in $CODEX_HOME/skills and
# legacy /prompts:* copies are cleaned up (H1); symlinked targets are edited
# through the link, never replaced (M3); uninstall removes the account links
# codex-swap created but keeps account state (LOW); trust guidance printed (H2).
. "$(dirname "$0")/lib.sh"
new_home
mkdir -p "$CODEX_HOME/prompts"
# overcodex 0.2.0's prompt copies (recognized by their heading) + a user's own.
printf -- '---\ndescription: "x"\n---\n\n# /prompts:handoff — continue in a fresh Codex session\n' > "$CODEX_HOME/prompts/handoff.md"
printf -- '---\ndescription: "x"\n---\n\n# /prompts:ultracode — explicit Codex multi-agent execution\n' > "$CODEX_HOME/prompts/ultracode.md"
printf 'my own prompt\n' > "$CODEX_HOME/prompts/handoff-status.md"
# dotfiles-managed AGENTS.md and .zshrc (symlinks)
mkdir -p "$HOME/dotfiles"
printf '# my agents rules\n' > "$HOME/dotfiles/AGENTS.md"
printf '# my zshrc\n' > "$HOME/dotfiles/zshrc"
ln -s "$HOME/dotfiles/AGENTS.md" "$CODEX_HOME/AGENTS.md"
ln -s "$HOME/dotfiles/zshrc" "$HOME/.zshrc"

bash "$REPO/install.sh" > "$HOME/i1.log" 2>&1
L="$(cat "$HOME/i1.log")"
for s in handoff handoff-status handoff-cancel handoff-claude ultracode; do
  assert_true '[ -f "$CODEX_HOME/skills/'"$s"'/SKILL.md" ]' "H1: skill $s installed"
done
assert_true '[ ! -e "$CODEX_HOME/prompts/handoff.md" ]' "H1: legacy overcodex prompt removed"
assert_true '[ ! -e "$CODEX_HOME/prompts/ultracode.md" ]' "H1: legacy overcodex prompt removed (ultracode)"
assert_eq "$(cat "$CODEX_HOME/prompts/handoff-status.md")" "my own prompt" "H1: a user's same-named prompt is kept"
assert_true '[ -L "$CODEX_HOME/AGENTS.md" ]' "M3: symlinked AGENTS.md is still a symlink"
assert_contains "$(cat "$HOME/dotfiles/AGENTS.md")" "overcodex ultracode (begin)" "M3: the block went into the link target"
assert_true '[ -L "$HOME/.zshrc" ]' "M3: symlinked .zshrc is still a symlink"
assert_contains "$(cat "$HOME/dotfiles/zshrc")" "overcodex integration (begin)" "M3: zshrc block went into the link target"
assert_contains "$L" "Hooks need review" "H2: install output explains hook review"
assert_contains "$L" "repeat step 1 once in EVERY codex-swap account" "H2: install output explains per-account trust"
assert_contains "$L" 'type $handoff' "install output names the skill syntax"

# An account home: codex-swap links, then a re-install run FROM that account.
"$HOME/.local/bin/codex-swap" add work > /dev/null 2>&1
ACC="$HOME/.codex-accounts/work"
printf '{"tokens":1}\n' > "$ACC/auth.json"
mkdir -p "$ACC/sessions"
assert_eq "$(readlink "$ACC/skills")" "$CODEX_HOME/skills" "account links the shared skills"
CODEX_HOME="$ACC" bash "$REPO/install.sh" > "$HOME/i2.log" 2>&1
assert_true '[ -L "$ACC/AGENTS.md" ] && [ -L "$ACC/config.toml" ]' "M3: install run in an account keeps its AGENTS.md/config.toml links"
assert_absent "$(cat "$CODEX_HOME/config.toml")" ".codex-accounts/work/hooks" "hook commands name the primary hooks dir, not an account"
assert_contains "$(cat "$HOME/i2.log")" "- work:" "H2: next steps list each account to trust"

bash "$REPO/uninstall.sh" > "$HOME/u1.log" 2>&1
assert_true '[ ! -e "$ACC/skills" ] && [ ! -L "$ACC/skills" ]' "uninstall removes the account's skills link"
assert_true '[ ! -L "$ACC/hooks" ] && [ ! -L "$ACC/AGENTS.md" ]' "uninstall removes the account's hooks/AGENTS.md links"
assert_true '[ -L "$ACC/config.toml" ]' "uninstall keeps the account's config.toml link (user settings)"
assert_true '[ -f "$ACC/auth.json" ] && [ -d "$ACC/sessions" ]' "uninstall keeps account state"
assert_true '[ ! -e "$CODEX_HOME/skills/handoff" ]' "uninstall removes the skills"
assert_eq "$(cat "$HOME/dotfiles/AGENTS.md")" "# my agents rules" "uninstall restores the AGENTS.md target"
assert_true '[ -L "$CODEX_HOME/AGENTS.md" ]' "uninstall keeps AGENTS.md a symlink"
assert_eq "$(cat "$HOME/dotfiles/zshrc")" "# my zshrc" "uninstall restores the zshrc target"
assert_true '[ -L "$HOME/.zshrc" ]' "uninstall keeps .zshrc a symlink"

# uninstall also cleans legacy prompt copies a 0.2.0 install left behind
mkdir -p "$CODEX_HOME/prompts"
printf -- '# /prompts:handoff-cancel — cancel a pending handoff\n' > "$CODEX_HOME/prompts/handoff-cancel.md"
bash "$REPO/uninstall.sh" > "$HOME/u2.log" 2>&1
assert_true '[ ! -e "$CODEX_HOME/prompts/handoff-cancel.md" ]' "uninstall removes legacy overcodex prompts"
assert_eq "$(cat "$CODEX_HOME/prompts/handoff-status.md")" "my own prompt" "uninstall keeps the user's prompt"

rm -rf "$HOME"
finish
