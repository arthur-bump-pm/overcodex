#!/bin/bash
# uninstall.sh — overcodex uninstaller.
# macOS /bin/bash 3.2 compatible. set -u; errors handled explicitly.
# Removes exactly what install.sh added. Leaves user state untouched:
# accounts (auth.json), sessions/threads (sqlite), and any non-overcodex
# content in config.toml / AGENTS.md / .zshrc — including whatever Codex wrote
# INSIDE overcodex's config.toml marker blocks (hook trust records, [notice],
# [features], ...): lib/overcodex_config.py moves those out and removes only
# what overcodex shipped, and refuses to write anything it cannot validate.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
LOCALBIN="$HOME/.local/bin"
ZSHRC="$HOME/.zshrc"

CONFIG_TOML="$CODEX_HOME/config.toml"
AGENTS_MD="$CODEX_HOME/AGENTS.md"

CFG_TOOL="$SCRIPT_DIR/lib/overcodex_config.py"
PRIMARY_HOME="$HOME/.codex"
ACCOUNTS_ROOT="$HOME/.codex-accounts"

# Skills this kit ships, and the /prompts:* files releases <= 0.2 installed.
SKILL_NAMES="handoff handoff-status handoff-cancel handoff-claude ultracode"
LEGACY_PROMPTS="handoff handoff-status handoff-cancel handoff-claude ultracode"

# Markers (must match install.sh exactly; config.toml's live in overcodex_config.py).
AGENTS_BEGIN='# --- overcodex ultracode (begin) ---'
AGENTS_END='# --- overcodex ultracode (end) ---'
ZSH_BEGIN='# --- overcodex integration (begin) ---'
ZSH_END='# --- overcodex integration (end) ---'

EPOCH=$(date +%s)

DID=()
SKIPPED=()
WARNED=()
note_did()  { DID[${#DID[@]}]="$1";     echo "  [-] $1"; }
note_skip() { SKIPPED[${#SKIPPED[@]}]="$1"; echo "  [=] $1"; }
note_warn() { WARNED[${#WARNED[@]}]="$1";   echo "  [!] $1" >&2; }
die()       { echo "uninstall: ERROR: $1" >&2; exit 1; }

# resolve_path <path> — follow symlinks on the last component, so a symlinked
# AGENTS.md / .zshrc is edited through the link, never replaced by a file.
resolve_path() {
  rp_p="$1"; rp_n=0
  while [ -L "$rp_p" ] && [ "$rp_n" -lt 40 ]; do
    rp_l=$(readlink "$rp_p")
    case "$rp_l" in /*) rp_p="$rp_l" ;; *) rp_p="$(dirname "$rp_p")/$rp_l" ;; esac
    rp_n=$((rp_n + 1))
  done
  printf '%s\n' "$rp_p"
}

backup_file() {
  bf_path="$1"
  if [ -f "$bf_path" ]; then
    cp -p "$bf_path" "$bf_path.bak-$EPOCH" || die "backup failed: $bf_path"
    echo "$bf_path.bak-$EPOCH"
  fi
}

# marker_state <file> <begin> <end> — none | ok | bad. Markers match WHOLE
# lines only (a trailing CR is tolerated); ok = exactly one begin line and one
# end line, in that order. Must match install.sh's copy.
marker_state() {
  awk -v b="$2" -v e="$3" '
    { l = $0; sub(/\r$/, "", l) }
    l == b { nb++; if (!bl) bl = NR }
    l == e { ne++; if (!el) el = NR }
    END {
      if (nb == 0 && ne == 0) print "none"
      else if (nb == 1 && ne == 1 && bl < el) print "ok"
      else print "bad"
    }' "$1"
}

# copy_mode <from> <to> — give <to> the permission bits of <from>.
copy_mode() {
  cm_mode=$(stat -f %Lp "$1" 2>/dev/null) || return 0
  [ -n "$cm_mode" ] && chmod "$cm_mode" "$2" 2>/dev/null
  return 0
}

# skill_owned <SKILL.md> <name> — overcodex's own copy (kit heading present).
skill_owned() { grep -q "^# \\\$$2 — " "$1" 2>/dev/null; }

# strip_block <file> <begin> <end>
#   Print <file> without the inclusive begin..end range. Only call it when
#   marker_state says ok. Buffers runs of blank lines so the single separator
#   blank install.sh writes before a block is consumed with it (keeps install/
#   uninstall cycles byte-idempotent); at most one blank is dropped. Exits 3
#   (caller discards the output) if the end line never comes — it can never
#   drop everything to EOF.
strip_block() {
  sb_file="$1"; sb_begin="$2"; sb_end="$3"
  awk -v b="$sb_begin" -v e="$sb_end" '
    { l = $0; sub(/\r$/, "", l) }
    drop == 0 && l == b {
      drop = 1
      if (np > 0) np--
      for (i = 1; i <= np; i++) print pend[i]
      np = 0; next
    }
    drop == 1 { if (l == e) drop = 2; next }
    {
      if (l == "") { pend[++np] = $0 }
      else { for (i = 1; i <= np; i++) print pend[i]; np = 0; print }
    }
    END {
      for (i = 1; i <= np; i++) print pend[i]
      if (drop == 1) exit 3
    }
  ' "$sb_file"
}

# remove_marked <file> <begin> <end> <label> — strip a marker block safely:
# refuses (file untouched) unless the markers are intact, keeps the file mode,
# and reports "removed" only when the file actually changed.
remove_marked() {
  rm_file="$1"; rm_begin="$2"; rm_end="$3"; rm_label="$4"
  if [ ! -f "$rm_file" ]; then note_skip "no $rm_label in $rm_file"; return 1; fi
  case "$(marker_state "$rm_file" "$rm_begin" "$rm_end")" in
    none) note_skip "no $rm_label in $rm_file"; return 1 ;;
    bad)
      note_warn "$rm_file: the $rm_label markers are damaged, duplicated or out of order — left untouched."
      note_warn "  Remove the block by hand (from '$rm_begin' to '$rm_end')."
      return 1 ;;
  esac
  rm_tmp="$rm_file.tmp-$EPOCH"
  if ! strip_block "$rm_file" "$rm_begin" "$rm_end" > "$rm_tmp"; then
    rm -f "$rm_tmp"; note_warn "could not strip the $rm_label from $rm_file — left untouched"; return 1
  fi
  if cmp -s "$rm_file" "$rm_tmp"; then
    rm -f "$rm_tmp"; note_warn "$rm_label in $rm_file: nothing was removed"; return 1
  fi
  rm_bak=$(backup_file "$rm_file")
  copy_mode "$rm_file" "$rm_tmp"
  if mv "$rm_tmp" "$rm_file"; then
    note_did "removed $rm_label from $rm_file (backup: $rm_bak)"
    return 0
  fi
  rm -f "$rm_tmp"; note_warn "could not write $rm_file"; return 1
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

# Skills (only overcodex's own copies — never a user's same-named skill; a
# skill dir is pruned once empty).
for sk in $SKILL_NAMES; do
  [ -d "$SCRIPT_DIR/skills/$sk" ] || continue
  if [ -f "$CODEX_HOME/skills/$sk/SKILL.md" ] && ! skill_owned "$CODEX_HOME/skills/$sk/SKILL.md" "$sk"; then
    note_skip "left $CODEX_HOME/skills/$sk in place (not overcodex's copy)"
    continue
  fi
  for sf in $(cd "$SCRIPT_DIR/skills" && find "$sk" -type f | sort); do
    dest="$CODEX_HOME/skills/$sf"
    if [ -f "$dest" ]; then
      rm -f "$dest" && note_did "removed $dest" || note_warn "could not remove $dest"
    fi
  done
  [ -d "$CODEX_HOME/skills/$sk" ] && rmdir "$CODEX_HOME/skills/$sk" 2>/dev/null \
    && note_did "removed skill dir $CODEX_HOME/skills/$sk"
done

# Legacy /prompts:* files installed by overcodex <= 0.2 (only overcodex's copies).
for lp in $LEGACY_PROMPTS; do
  dest="$CODEX_HOME/prompts/$lp.md"
  [ -f "$dest" ] || continue
  if grep -q "^# /prompts:$lp " "$dest" 2>/dev/null; then
    rm -f "$dest" && note_did "removed legacy prompt $dest" || note_warn "could not remove $dest"
  else
    note_skip "left $dest in place (not overcodex's copy)"
  fi
done

# Custom agent definitions (by the names shipped in the kit).
for a in "$SCRIPT_DIR"/agents/*.toml; do
  [ -f "$a" ] || continue
  dest="$CODEX_HOME/agents/$(basename "$a")"
  if [ -f "$dest" ]; then
    rm -f "$dest" && note_did "removed $dest" || note_warn "could not remove $dest"
  else
    note_skip "not present: $dest"
  fi
done

# Prune now-empty kit dirs (never touch anything non-empty).
for d in "$CODEX_HOME/hooks" "$CODEX_HOME/prompts" "$CODEX_HOME/agents" "$CODEX_HOME/skills"; do
  [ -d "$d" ] && rmdir "$d" 2>/dev/null && note_did "removed empty dir $d"
done

# Shared-config symlinks `codex-swap add` created in each account home. Only a
# symlink pointing exactly at the primary's item is removed; config.toml (your
# settings) and every account's auth.json / session state stay.
if [ -d "$ACCOUNTS_ROOT" ]; then
  for acc in "$ACCOUNTS_ROOT"/*/; do
    [ -d "$acc" ] || continue
    acc="${acc%/}"
    for item in hooks skills prompts AGENTS.md; do
      if [ -L "$acc/$item" ] && [ "$(readlink "$acc/$item")" = "$PRIMARY_HOME/$item" ]; then
        rm -f "$acc/$item" && note_did "removed account link $acc/$item"
      fi
    done
  done
fi
echo

# ---------------------------------------------------------------------------
# 2. config.toml — remove ONLY our marker blocks (hooks + agent roles + status_line).
# ---------------------------------------------------------------------------
echo "-- config.toml --"
PYTHON=""
# OVERCODEX_PYTHON (may contain spaces) first; OVERCODEX_PYTHON_CANDIDATES
# replaces the fallback search list (the test suite uses it).
if [ -n "${OVERCODEX_PYTHON:-}" ] && "$OVERCODEX_PYTHON" "$CFG_TOOL" check >/dev/null 2>&1; then
  PYTHON="$OVERCODEX_PYTHON"
fi
for cand in ${OVERCODEX_PYTHON_CANDIDATES:-python3 /usr/bin/python3 python3.14 python3.13 python3.12 python3.11}; do
  [ -z "$PYTHON" ] || break
  command -v "$cand" >/dev/null 2>&1 || continue
  if "$cand" "$CFG_TOOL" check >/dev/null 2>&1; then PYTHON="$cand"; fi
done
if [ ! -f "$CONFIG_TOML" ]; then
  note_skip "no config.toml"
elif [ -z "$PYTHON" ]; then
  if grep -q '^# --- overcodex ' "$CONFIG_TOML" 2>/dev/null; then
    note_warn "config.toml NOT modified: no TOML parser to validate the edit (python3 >= 3.11, or tomli)."
    note_warn "  Run 'overcodex uninstall' (pipx ships one), or remove the overcodex blocks by hand —"
    note_warn "  keep any [hooks.state...] / [notice] / other tables Codex wrote inside them."
  else
    note_skip "config.toml has no overcodex blocks (no change)"
  fi
else
  TAB=$(printf '\t')
  CFG_OUT=$("$PYTHON" "$CFG_TOOL" strip "$CONFIG_TOML" "$EPOCH" --hooks-dir "$CODEX_HOME/hooks" 2>&1)
  while IFS="$TAB" read -r kind msg; do
    case "$kind" in
      did)  note_did "$msg" ;;
      skip) note_skip "$msg" ;;
      warn) note_warn "$msg" ;;
      "")   : ;;
      *)    note_warn "$kind $msg" ;;
    esac
  done <<CFGEOF
$CFG_OUT
CFGEOF
fi
echo

# ---------------------------------------------------------------------------
# 3. AGENTS.md — remove the ultracode block between markers.
# ---------------------------------------------------------------------------
echo "-- AGENTS.md --"
AGENTS_MD=$(resolve_path "$AGENTS_MD")
if remove_marked "$AGENTS_MD" "$AGENTS_BEGIN" "$AGENTS_END" "ultracode block"; then
  # If AGENTS.md is now empty (only whitespace), drop the file we effectively created.
  if [ -f "$AGENTS_MD" ] && ! grep -q '[^[:space:]]' "$AGENTS_MD" 2>/dev/null; then
    rm -f "$AGENTS_MD" && note_did "removed now-empty $AGENTS_MD"
  fi
fi
echo

# ---------------------------------------------------------------------------
# 4. .zshrc — delete the integration block between markers.
# ---------------------------------------------------------------------------
echo "-- .zshrc --"
ZSHRC=$(resolve_path "$ZSHRC")
if remove_marked "$ZSHRC" "$ZSH_BEGIN" "$ZSH_END" "integration block"; then
  note_warn "Open a new shell for the change to take effect."
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
echo "  * remaining $CONFIG_TOML       (all non-overcodex settings, incl. Codex's hook trust records)"
echo "  * any per-account CODEX_HOME dirs you created for codex-swap"
echo "  * timestamped .bak-$EPOCH copies of every file we edited"
echo "Done."
