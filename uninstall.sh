#!/bin/bash
# uninstall.sh — overcodex uninstaller.
# macOS /bin/bash 3.2 compatible. set -u; errors handled explicitly.
# Removes exactly what install.sh added. Leaves user state untouched:
# accounts (auth.json), sessions/threads (sqlite), and any non-overcodex
# content in config.toml / AGENTS.md / .zshrc.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
LOCALBIN="$HOME/.local/bin"
ZSHRC="$HOME/.zshrc"

CONFIG_TOML="$CODEX_HOME/config.toml"
AGENTS_MD="$CODEX_HOME/AGENTS.md"

SRC_SWAP="$SCRIPT_DIR/bin/codex-swap"

# Markers (must match install.sh exactly).
AGENTS_BEGIN='# --- overcodex ultracode (begin) ---'
AGENTS_END='# --- overcodex ultracode (end) ---'
ZSH_BEGIN='# --- overcodex integration (begin) ---'
ZSH_END='# --- overcodex integration (end) ---'
HOOKS_BEGIN='# --- overcodex hooks (begin) ---'
HOOKS_END='# --- overcodex hooks (end) ---'
SL_BEGIN='# --- overcodex statusline (begin) ---'
SL_END='# --- overcodex statusline (end) ---'

EPOCH=$(date +%s)

DID=()
SKIPPED=()
WARNED=()
note_did()  { DID[${#DID[@]}]="$1";     echo "  [-] $1"; }
note_skip() { SKIPPED[${#SKIPPED[@]}]="$1"; echo "  [=] $1"; }
note_warn() { WARNED[${#WARNED[@]}]="$1";   echo "  [!] $1" >&2; }
die()       { echo "uninstall: ERROR: $1" >&2; exit 1; }

backup_file() {
  bf_path="$1"
  if [ -f "$bf_path" ]; then
    cp -p "$bf_path" "$bf_path.bak-$EPOCH" || die "backup failed: $bf_path"
    echo "$bf_path.bak-$EPOCH"
  fi
}

# strip_block <file> <begin> <end>
#   Delete the inclusive begin..end range. Buffers runs of blank lines so the
#   single separator blank that install.sh writes before a block is consumed
#   with it (keeps install/uninstall cycles byte-idempotent); at most one blank
#   is dropped, user blank lines survive. Prints nothing; returns 0 always.
strip_block() {
  sb_file="$1"; sb_begin="$2"; sb_end="$3"
  awk -v b="$sb_begin" -v e="$sb_end" '
    $0 == b { drop = 1
              if (pending > 0) pending--
              while (pending > 0) { print ""; pending-- } }
    drop != 1 {
      if ($0 == "") { pending++ }
      else { while (pending > 0) { print ""; pending-- }; print }
    }
    $0 == e { drop = 0 }
    END { while (pending > 0) { print ""; pending-- } }
  ' "$sb_file"
}

echo "== overcodex uninstaller =="
echo "   CODEX_HOME: $CODEX_HOME"
echo "   epoch:      $EPOCH"
echo

# ---------------------------------------------------------------------------
# 1. Remove copied files (only the ones the kit installs).
# ---------------------------------------------------------------------------
echo "-- files --"

# codex-swap.
if [ -f "$LOCALBIN/codex-swap" ]; then
  rm -f "$LOCALBIN/codex-swap" && note_did "removed $LOCALBIN/codex-swap" \
    || note_warn "could not remove $LOCALBIN/codex-swap"
else
  note_skip "not present: $LOCALBIN/codex-swap"
fi

# Hook scripts (by the names shipped in the kit).
for h in "$SCRIPT_DIR"/hooks/*.sh; do
  [ -f "$h" ] || continue
  dest="$CODEX_HOME/hooks/$(basename "$h")"
  if [ -f "$dest" ]; then
    rm -f "$dest" && note_did "removed $dest" || note_warn "could not remove $dest"
  else
    note_skip "not present: $dest"
  fi
done


# Prompts (by the names shipped in the kit).
for p in "$SCRIPT_DIR"/prompts/*.md; do
  [ -f "$p" ] || continue
  dest="$CODEX_HOME/prompts/$(basename "$p")"
  if [ -f "$dest" ]; then
    rm -f "$dest" && note_did "removed $dest" || note_warn "could not remove $dest"
  else
    note_skip "not present: $dest"
  fi
done

# Prune now-empty kit dirs (never touch anything non-empty).
for d in "$CODEX_HOME/hooks" "$CODEX_HOME/prompts"; do
  [ -d "$d" ] && rmdir "$d" 2>/dev/null && note_did "removed empty dir $d"
done
echo

# ---------------------------------------------------------------------------
# 2. config.toml — remove ONLY our marker blocks (hooks + status_line).
# ---------------------------------------------------------------------------
echo "-- config.toml --"
if [ ! -f "$CONFIG_TOML" ]; then
  note_skip "no config.toml"
else
  HAS_HOOKS=no; HAS_SL=no
  grep -qF "$HOOKS_BEGIN" "$CONFIG_TOML" && HAS_HOOKS=yes
  grep -qF "$SL_BEGIN"    "$CONFIG_TOML" && HAS_SL=yes
  if [ "$HAS_HOOKS" = no ] && [ "$HAS_SL" = no ]; then
    note_skip "config.toml has no overcodex blocks (no change)"
  else
    b=$(backup_file "$CONFIG_TOML")
    tmp="$CONFIG_TOML.tmp-$EPOCH"
    cp "$CONFIG_TOML" "$tmp" || die "could not stage config.toml"
    if [ "$HAS_HOOKS" = yes ]; then
      strip_block "$tmp" "$HOOKS_BEGIN" "$HOOKS_END" > "$tmp.2" && mv "$tmp.2" "$tmp" \
        || die "could not strip hooks block"
    fi
    if [ "$HAS_SL" = yes ]; then
      strip_block "$tmp" "$SL_BEGIN" "$SL_END" > "$tmp.2" && mv "$tmp.2" "$tmp" \
        || die "could not strip status_line block"
    fi
    mv "$tmp" "$CONFIG_TOML" || die "could not write $CONFIG_TOML"
    [ "$HAS_HOOKS" = yes ] && note_did "removed hooks block from config.toml (backup: $b)"
    [ "$HAS_SL" = yes ]    && note_did "removed [tui].status_line block from config.toml (backup: $b)"
  fi
fi
echo

# ---------------------------------------------------------------------------
# 3. AGENTS.md — remove the ultracode block between markers.
# ---------------------------------------------------------------------------
echo "-- AGENTS.md --"
if [ -f "$AGENTS_MD" ] && grep -qF "$AGENTS_BEGIN" "$AGENTS_MD"; then
  b=$(backup_file "$AGENTS_MD")
  strip_block "$AGENTS_MD" "$AGENTS_BEGIN" "$AGENTS_END" > "$AGENTS_MD.tmp-$EPOCH" \
    && mv "$AGENTS_MD.tmp-$EPOCH" "$AGENTS_MD" \
    && note_did "removed ultracode block from $AGENTS_MD (backup: $b)" \
    || note_warn "could not edit $AGENTS_MD"
  # If AGENTS.md is now empty (only whitespace), drop the file we effectively created.
  if [ -f "$AGENTS_MD" ] && ! grep -q '[^[:space:]]' "$AGENTS_MD" 2>/dev/null; then
    rm -f "$AGENTS_MD" && note_did "removed now-empty $AGENTS_MD"
  fi
else
  note_skip "no ultracode block in AGENTS.md"
fi
echo

# ---------------------------------------------------------------------------
# 4. .zshrc — delete the integration block between markers.
# ---------------------------------------------------------------------------
echo "-- .zshrc --"
if [ -f "$ZSHRC" ] && grep -qF "$ZSH_BEGIN" "$ZSHRC"; then
  b=$(backup_file "$ZSHRC")
  strip_block "$ZSHRC" "$ZSH_BEGIN" "$ZSH_END" > "$ZSHRC.tmp-$EPOCH" \
    && mv "$ZSHRC.tmp-$EPOCH" "$ZSHRC" \
    && note_did "removed integration block from $ZSHRC (backup: $b)" \
    || note_warn "could not edit $ZSHRC"
  note_warn "Open a new shell for the change to take effect."
else
  note_skip "no integration block in .zshrc"
fi
echo

# ---------------------------------------------------------------------------
# Summary + what we deliberately kept.
# ---------------------------------------------------------------------------
echo "== summary =="
echo "  changed:  ${#DID[@]}"
echo "  skipped:  ${#SKIPPED[@]}"
echo "  warnings: ${#WARNED[@]}"
echo
echo "-- kept (user state, never touched) --"
echo "  * $CODEX_HOME/auth.json        (your account credentials)"
echo "  * $CODEX_HOME/*.sqlite         (sessions / thread history)"
echo "  * remaining $CONFIG_TOML       (all non-overcodex settings)"
echo "  * any per-account CODEX_HOME dirs you created for codex-swap"
echo "  * timestamped .bak-$EPOCH copies of every file we edited"
echo "Done."
