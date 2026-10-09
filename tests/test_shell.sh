#!/bin/bash
# shell/zshrc-snippet.sh (M3): the codex() wrapper passes CODEX_HOME to the one
# codex process (env prefix), never exports it into the shell, and leaves a
# user-set CODEX_HOME alone when no account marker is active.
. "$(dirname "$0")/lib.sh"
new_home
unset CODEX_HOME
STUB="$HOME/stub"; mkdir -p "$STUB" "$HOME/.codex-accounts/work"
printf '#!/bin/bash\necho "codex sees CODEX_HOME=${CODEX_HOME-<unset>}"\n' > "$STUB/codex"
chmod +x "$STUB/codex"
SNIP="$REPO/shell/zshrc-snippet.sh"

run() { # run <shell> <script>
  env -i HOME="$HOME" PATH="$STUB:/usr/bin:/bin" "$1" -c ". '$SNIP'; $2"
}
for sh in bash zsh; do
  command -v "$sh" >/dev/null 2>&1 || continue
  echo work > "$HOME/.codex-accounts/.active"
  o="$(run "$sh" 'codex; echo "shell sees CODEX_HOME=${CODEX_HOME-<unset>}"')"
  assert_contains "$o" "codex sees CODEX_HOME=$HOME/.codex-accounts/work" "$sh: codex gets the active account home"
  assert_contains "$o" "shell sees CODEX_HOME=<unset>" "$sh: CODEX_HOME is not exported into the shell"
  rm -f "$HOME/.codex-accounts/.active"
  o="$(run "$sh" 'export CODEX_HOME=/my/home; codex; echo "shell sees CODEX_HOME=$CODEX_HOME"')"
  assert_contains "$o" "codex sees CODEX_HOME=/my/home" "$sh: no marker -> a user-set CODEX_HOME reaches codex"
  assert_contains "$o" "shell sees CODEX_HOME=/my/home" "$sh: no marker -> the user's CODEX_HOME is kept"
  echo primary > "$HOME/.codex-accounts/.active"
  o="$(run "$sh" 'codex')"
  assert_contains "$o" "codex sees CODEX_HOME=<unset>" "$sh: primary marker -> CODEX_HOME untouched"
  echo gone > "$HOME/.codex-accounts/.active"
  o="$(run "$sh" 'export CODEX_HOME=/my/home; codex 2>&1')"
  assert_contains "$o" "not found under ~/.codex-accounts" "$sh: stale marker warns"
  assert_contains "$o" "codex sees CODEX_HOME=/my/home" "$sh: stale marker leaves CODEX_HOME alone"
  printf '../x\n' > "$HOME/.codex-accounts/.active"
  o="$(run "$sh" 'codex 2>&1')"
  assert_contains "$o" "codex sees CODEX_HOME=<unset>" "$sh: a malformed marker is never used as a path"
  rm -f "$HOME/.codex-accounts/.active"
done

rm -rf "$HOME"
finish
