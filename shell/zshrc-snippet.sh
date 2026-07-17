# --- overcodex integration (begin) ---
# codex-swap is installed to ~/.local/bin — ensure it is on PATH.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
alias cswap-codex='codex-swap'
codex() {
  local active_file="$HOME/.codex-accounts/.active"
  local name=""
  [ -f "$active_file" ] && name=$(tr -d '[:space:]' <"$active_file" 2>/dev/null)
  case "$name" in
    ""|primary)
      unset CODEX_HOME
      ;;
    *)
      if [ -d "$HOME/.codex-accounts/$name" ]; then
        export CODEX_HOME="$HOME/.codex-accounts/$name"
      else
        echo "overcodex: active account '$name' not found under ~/.codex-accounts — falling back to primary (~/.codex)" >&2
        unset CODEX_HOME
      fi
      ;;
  esac
  command codex "$@"
}
# --- overcodex integration (end) ---
