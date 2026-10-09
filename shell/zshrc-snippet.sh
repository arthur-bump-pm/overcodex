# --- overcodex integration (begin) ---
# shellcheck shell=bash
# codex-swap is installed to ~/.local/bin — ensure it is on PATH.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
alias cswap-codex='codex-swap'
# codex(): run the active codex-swap account. CODEX_HOME is passed to that one
# codex process as an env prefix — never exported into this shell — and is left
# exactly as you set it when no account marker is active.
codex() {
  local name="" h=""
  [ -f "$HOME/.codex-accounts/.active" ] && name=$(tr -d '[:space:]' <"$HOME/.codex-accounts/.active" 2>/dev/null)
  case "$name" in
    ""|primary) command codex "$@"; return ;;
    *[!A-Za-z0-9_-]*) h="" ;;
    *) h="$HOME/.codex-accounts/$name" ;;
  esac
  if [ -n "$h" ] && [ -d "$h" ]; then
    CODEX_HOME="$h" command codex "$@"
  else
    echo "overcodex: active account '$name' not found under ~/.codex-accounts — ignoring the marker (codex-swap use primary clears it)" >&2
    command codex "$@"
  fi
}
# --- overcodex integration (end) ---
