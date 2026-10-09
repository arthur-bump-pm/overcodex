#!/bin/bash
# install.sh — overcodex installer.
# macOS /bin/bash 3.2 compatible. set -u; errors handled explicitly.
# Reproduces the overcodex multi-account / ultracode setup for the Codex CLI.
#
# config.toml is edited ONLY through lib/overcodex_config.py, which needs a TOML
# parser (python3 >= 3.11, or tomli — `overcodex install` passes its own pipx
# interpreter, which always has one). Without one, config.toml is left alone.
# Overcodex-owned marker blocks are refreshed when their shipped content
# changes; anything Codex wrote inside them (hook trust, [notice], ...) is
# moved below the block, never deleted; a user's own hooks/agents/status_line
# are never overwritten. AGENTS.md and ~/.zshrc use begin/end marker blocks
# (a symlinked target is edited through the link, never replaced).

set -u

# ---------------------------------------------------------------------------
# Locate the kit (this script lives at the repo root).
# ---------------------------------------------------------------------------
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# CODEX_HOME: honor the env var (relocatable state dir), else ~/.codex.
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
LOCALBIN="$HOME/.local/bin"
ZSHRC="$HOME/.zshrc"

CONFIG_TOML="$CODEX_HOME/config.toml"
AGENTS_MD="$CODEX_HOME/AGENTS.md"

# Kit sources.
SRC_SWAP="$SCRIPT_DIR/bin/codex-swap"
SRC_HOOKS_TPL="$SCRIPT_DIR/config/hooks-block.toml.tpl"
SRC_AGENT_ROLES_TPL="$SCRIPT_DIR/config/agents-block.toml.tpl"
SRC_AGENTS="$SCRIPT_DIR/codex/AGENTS-ULTRACODE.md"
SRC_ZSNIPPET="$SCRIPT_DIR/shell/zshrc-snippet.sh"
CFG_TOOL="$SCRIPT_DIR/lib/overcodex_config.py"

# Codex skills shipped by the kit, and the /prompts:* files older releases
# installed (Codex 0.158 removed custom prompts; install/uninstall clean them up).
SKILL_NAMES="handoff handoff-status handoff-cancel handoff-claude ultracode"
LEGACY_PROMPTS="handoff handoff-status handoff-cancel handoff-claude ultracode"

# Statusline TOML fragment (owned by the config builder). Optional; either name.
SRC_STATUSLINE=""
for c in "$SCRIPT_DIR/config/statusline.toml" "$SCRIPT_DIR/config/statusline"; do
  [ -f "$c" ] && [ -s "$c" ] && { SRC_STATUSLINE="$c"; break; }
done

# Marker strings (must match uninstall.sh exactly).
AGENTS_BEGIN='# --- overcodex ultracode (begin) ---'
AGENTS_END='# --- overcodex ultracode (end) ---'
ZSH_BEGIN='# --- overcodex integration (begin) ---'
ZSH_END='# --- overcodex integration (end) ---'
# config.toml markers live in lib/overcodex_config.py (MARKERS); only the hooks
# begin marker is needed here, for the no-parser verify fallback.
HOOKS_BEGIN='# --- overcodex hooks (begin) ---'

EPOCH=$(date +%s)

# Summary accumulators (bash 3.2: plain indexed arrays).
DID=()
SKIPPED=()
WARNED=()
note_did()  { DID[${#DID[@]}]="$1";     echo "  [+] $1"; }
note_skip() { SKIPPED[${#SKIPPED[@]}]="$1"; echo "  [=] $1"; }
note_warn() { WARNED[${#WARNED[@]}]="$1";   echo "  [!] $1" >&2; }
die()       { echo "install: ERROR: $1" >&2; exit 1; }

echo "== overcodex installer =="
echo "   kit:        $SCRIPT_DIR"
echo "   CODEX_HOME: $CODEX_HOME"
echo "   epoch:      $EPOCH"
echo

# ---------------------------------------------------------------------------
# 0. Sanity: required kit files present.
# ---------------------------------------------------------------------------
for f in "$SRC_SWAP" "$SRC_HOOKS_TPL" "$SRC_AGENT_ROLES_TPL" "$SRC_AGENTS" "$SRC_ZSNIPPET" "$CFG_TOOL"; do
  [ -f "$f" ] || die "kit file missing: $f (run from the repo root)"
done
# At least one hook script.
HOOK_SCRIPTS=$(ls "$SCRIPT_DIR"/hooks/*.sh 2>/dev/null)
[ -n "$HOOK_SCRIPTS" ] || die "no hook scripts found under $SCRIPT_DIR/hooks/*.sh"

# ---------------------------------------------------------------------------
# 1. Dependency preflight.
# ---------------------------------------------------------------------------
echo "-- preflight --"

# jq is required.
if ! command -v jq >/dev/null 2>&1; then
  die "jq is required but not found. Install it: brew install jq"
fi
echo "  [ok] jq: $(command -v jq)"

# codex CLI: warn only (do not fail).
if command -v codex >/dev/null 2>&1; then
  echo "  [ok] codex: $(command -v codex)"
else
  note_warn "codex CLI not found on PATH. Install it, e.g.:"
  note_warn "    brew install codex        (or)   npm install -g @openai/codex"
  note_warn "  The kit installs fine without it, but codex must be present to use it."
fi

# A TOML parser is required to touch config.toml (validator before every write).
# OVERCODEX_PYTHON is exported by `overcodex install` (its pipx interpreter).
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
if [ -n "$PYTHON" ]; then
  echo "  [ok] TOML validator: $(command -v "$PYTHON")"
else
  note_warn "no TOML parser found (python3 >= 3.11, or tomli) — config.toml will NOT be modified."
  note_warn "  Use 'overcodex install' (pipx ships one), or: python3 -m pip install --user tomli"
fi

# CODEX_HOME: create if missing.
if [ -d "$CODEX_HOME" ]; then
  echo "  [ok] CODEX_HOME exists: $CODEX_HOME"
else
  mkdir -p "$CODEX_HOME" || die "could not create CODEX_HOME: $CODEX_HOME"
  note_did "created CODEX_HOME: $CODEX_HOME"
fi

# PATH check for ~/.local/bin (where codex-swap lands).
case ":$PATH:" in
  *":$LOCALBIN:"*) echo "  [ok] $LOCALBIN is on PATH" ;;
  *) note_warn "$LOCALBIN is not on your PATH. Add it so codex-swap is found:"
     note_warn "    export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac
echo

# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------

# resolve_path <path> — follow symlinks on the last component (bash 3.2 / BSD
# readlink: no -f). Edits go to the link target so a symlinked AGENTS.md,
# config.toml or .zshrc is never replaced by a regular file.
resolve_path() {
  rp_p="$1"; rp_n=0
  while [ -L "$rp_p" ] && [ "$rp_n" -lt 40 ]; do
    rp_l=$(readlink "$rp_p")
    case "$rp_l" in /*) rp_p="$rp_l" ;; *) rp_p="$(dirname "$rp_p")/$rp_l" ;; esac
    rp_n=$((rp_n + 1))
  done
  printf '%s\n' "$rp_p"
}

# marker_state <file> <begin> <end> — none | ok | bad. Markers match WHOLE
# lines only (a trailing CR is tolerated); ok = exactly one begin line and one
# end line, in that order. A marker quoted mid-line never counts; anything else
# (missing/duplicated/edited end line) is bad, and callers then refuse.
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

# skill_owned <SKILL.md> <name> — overcodex's own copy (kit heading present).
skill_owned() { grep -q "^# \\\$$2 — " "$1" 2>/dev/null; }

# copy_mode <from> <to> — give <to> the permission bits of <from> (a 0600
# file stays 0600 when we replace it through a temp file).
copy_mode() {
  cm_mode=$(stat -f %Lp "$1" 2>/dev/null) || return 0
  [ -n "$cm_mode" ] && chmod "$cm_mode" "$2" 2>/dev/null
  return 0
}

# backup_file <path> — timestamped backup if the file exists. Prints backup path.
backup_file() {
  bf_path="$1"
  if [ -f "$bf_path" ]; then
    cp -p "$bf_path" "$bf_path.bak-$EPOCH" || die "backup failed: $bf_path"
    echo "$bf_path.bak-$EPOCH"
  fi
}

# install_file <src> <dest> <mode|-> — copy with backup-on-change, chmod.
# No backup, no copy when the destination is already identical (idempotent).
install_file() {
  if_src="$1"; if_dest="$2"; if_mode="$3"
  mkdir -p "$(dirname "$if_dest")" || die "mkdir failed for $if_dest"
  if [ -f "$if_dest" ]; then
    if cmp -s "$if_src" "$if_dest"; then
      [ "$if_mode" != "-" ] && chmod "$if_mode" "$if_dest" 2>/dev/null
      note_skip "up-to-date: $if_dest"
      return 0
    fi
    b=$(backup_file "$if_dest")
    cp "$if_src" "$if_dest" || die "copy failed: $if_dest"
    [ "$if_mode" != "-" ] && chmod "$if_mode" "$if_dest"
    note_did "updated: $if_dest (backup: $b)"
  else
    cp "$if_src" "$if_dest" || die "copy failed: $if_dest"
    [ "$if_mode" != "-" ] && chmod "$if_mode" "$if_dest"
    note_did "installed: $if_dest"
  fi
}

# ---------------------------------------------------------------------------
# 2. File copies (per the FIXED DESTINATIONS contract).
# ---------------------------------------------------------------------------
echo "-- files --"

install_file "$SRC_SWAP" "$LOCALBIN/codex-swap" 755

# hooks/*.sh -> $CODEX_HOME/hooks/ (755)
mkdir -p "$CODEX_HOME/hooks" || die "mkdir failed: $CODEX_HOME/hooks"
for h in "$SCRIPT_DIR"/hooks/*.sh; do
  [ -f "$h" ] || continue
  install_file "$h" "$CODEX_HOME/hooks/$(basename "$h")" 755
done

# skills/<name>/... -> $CODEX_HOME/skills/<name>/  (Codex skills: `$handoff`, /skills)
# A SKILL.md is overcodex's when it carries the kit's own "# $<name> — " heading
# (the same kind of ownership rule as the legacy prompts). A user's own skill
# with the same name — e.g. in an account whose skills/ is a real directory —
# is never overwritten.
for sk in $SKILL_NAMES; do
  [ -f "$SCRIPT_DIR/skills/$sk/SKILL.md" ] || die "kit skill missing: skills/$sk/SKILL.md"
  if [ -f "$CODEX_HOME/skills/$sk/SKILL.md" ] && ! skill_owned "$CODEX_HOME/skills/$sk/SKILL.md" "$sk"; then
    note_warn "left $CODEX_HOME/skills/$sk/SKILL.md alone: it is not overcodex's copy (your own \$$sk skill?)"
    continue
  fi
  for sf in $(cd "$SCRIPT_DIR/skills" && find "$sk" -type f | sort); do
    install_file "$SCRIPT_DIR/skills/$sf" "$CODEX_HOME/skills/$sf" -
  done
done

# Legacy /prompts:* files from overcodex <= 0.2 (dead since Codex 0.158). Only
# files that still carry overcodex's own "# /prompts:<name>" heading are removed.
for lp in $LEGACY_PROMPTS; do
  f="$CODEX_HOME/prompts/$lp.md"
  [ -f "$f" ] || continue
  if grep -q "^# /prompts:$lp " "$f" 2>/dev/null; then
    rm -f "$f" && note_did "removed legacy custom prompt $f (now the \$$lp skill)"
  else
    note_skip "left $f in place (not overcodex's copy)"
  fi
done
[ -d "$CODEX_HOME/prompts" ] && rmdir "$CODEX_HOME/prompts" 2>/dev/null && note_did "removed empty $CODEX_HOME/prompts"

# agents/*.toml -> $CODEX_HOME/agents/ (optional custom subagent roles)
AGENT_FILES=$(ls "$SCRIPT_DIR"/agents/*.toml 2>/dev/null)
if [ -n "$AGENT_FILES" ]; then
  mkdir -p "$CODEX_HOME/agents" || die "mkdir failed: $CODEX_HOME/agents"
  for a in "$SCRIPT_DIR"/agents/*.toml; do
    [ -f "$a" ] || continue
    install_file "$a" "$CODEX_HOME/agents/$(basename "$a")" -
  done
else
  note_warn "no agents/*.toml in kit — routing policy will be advisory only"
fi
echo

# ---------------------------------------------------------------------------
# 3. config.toml — hooks, agent roles and [tui].status_line marker blocks,
#    via lib/overcodex_config.py (validated; foreign tables preserved).
# ---------------------------------------------------------------------------
echo "-- config.toml --"
RETRUST=0
# Hook/agent paths written into config.toml: through a symlinked dir (an
# account home) to its target, so the shared config never names one account.
HOOKS_DIR_CFG="$CODEX_HOME/hooks"
[ -L "$HOOKS_DIR_CFG" ] && HOOKS_DIR_CFG=$(resolve_path "$HOOKS_DIR_CFG")
AGENTS_DIR_CFG="$CODEX_HOME/agents"
[ -L "$AGENTS_DIR_CFG" ] && AGENTS_DIR_CFG=$(resolve_path "$AGENTS_DIR_CFG")
TAB=$(printf '\t')
if [ -z "$PYTHON" ]; then
  note_warn "config.toml NOT modified (no TOML validator): hooks, agent roles and the status line"
  note_warn "  are not wired or refreshed. Re-run via 'overcodex install', or install tomli and re-run."
else
  CFG_OUT=$("$PYTHON" "$CFG_TOOL" apply "$CONFIG_TOML" "$EPOCH" \
    --hooks-tpl "$SRC_HOOKS_TPL" --hooks-dir "$HOOKS_DIR_CFG" \
    --agents-tpl "$SRC_AGENT_ROLES_TPL" --agents-dir "$AGENTS_DIR_CFG" \
    --statusline "$SRC_STATUSLINE" 2>&1) || note_warn "config tool exited non-zero (config.toml unchanged unless reported above)"
  while IFS="$TAB" read -r kind msg; do
    case "$kind" in
      did)     note_did "$msg" ;;
      skip)    note_skip "$msg" ;;
      warn)    note_warn "$msg" ;;
      retrust) RETRUST=1 ;;
      "")      : ;;
      *)       note_warn "$kind $msg" ;;
    esac
  done <<CFGEOF
$CFG_OUT
CFGEOF
fi
echo

# ---------------------------------------------------------------------------
# append_marked <target> <begin> <end> <src> <label>
#   Install or refresh a marker-wrapped block. Any pre-existing overcodex
#   marker lines in <src> are stripped so we never nest. Existing blocks are
#   replaced on change, which makes upgrades refresh policy text safely.
# ---------------------------------------------------------------------------
append_marked() {
  am_target=$(resolve_path "$1"); am_begin="$2"; am_end="$3"; am_src="$4"; am_label="$5"
  mkdir -p "$(dirname "$am_target")" || die "mkdir failed for $am_target"
  am_state=none
  [ -f "$am_target" ] && am_state=$(marker_state "$am_target" "$am_begin" "$am_end")
  if [ "$am_state" = bad ]; then
    note_warn "$am_target: the $am_label markers are damaged, duplicated or out of order"
    note_warn "  (each must be one whole line: '$am_begin' ... '$am_end') — left untouched; fix by hand and re-run."
    return 0
  fi
  # CRLF files get CRLF lines from us too.
  am_cr=""
  [ -f "$am_target" ] && head -n 1 "$am_target" | grep -q "$(printf '\r')\$" && am_cr=$(printf '\r')
  am_block="$am_target.block-$EPOCH-$$"
  {
    printf '%s\n' "$am_begin"
    grep -vxF "$am_begin" "$am_src" | grep -vxF "$am_end"
    printf '%s\n' "$am_end"
  } | sed "s/\$/$am_cr/" > "$am_block" || die "could not stage $am_label"

  if [ "$am_state" = ok ]; then
    am_tmp="$am_target.tmp-$EPOCH-$$"
    awk -v b="$am_begin" -v e="$am_end" -v repl="$am_block" '
      { l = $0; sub(/\r$/, "", l) }
      replacing != 1 && l == b {
        while ((getline line < repl) > 0) print line
        close(repl); replacing = 1; next
      }
      replacing == 1 { if (l == e) replacing = 2; next }
      { print }
      END { if (replacing == 1) exit 3 }
    ' "$am_target" > "$am_tmp" || { rm -f "$am_block" "$am_tmp"; note_warn "could not refresh $am_label in $am_target (left untouched)"; return 0; }
    rm -f "$am_block"
    if cmp -s "$am_target" "$am_tmp"; then
      rm -f "$am_tmp"
      note_skip "$am_label already up-to-date in $am_target"
      return 0
    fi
    b=$(backup_file "$am_target")
    copy_mode "$am_target" "$am_tmp"
    mv "$am_tmp" "$am_target" || die "could not refresh $am_label in $am_target"
    note_did "refreshed $am_label in $am_target (backup: $b)"
    return 0
  fi
  b=""
  [ -f "$am_target" ] && b=$(backup_file "$am_target")
  # Separator blank line before our block when the file has content.
  if [ -f "$am_target" ] && [ -s "$am_target" ]; then
    [ -n "$(tail -c1 "$am_target")" ] && printf '%s\n' "$am_cr" >> "$am_target"
    printf '%s\n' "$am_cr" >> "$am_target"
  fi
  cat "$am_block" >> "$am_target" || { rm -f "$am_block"; die "could not append to $am_target"; }
  rm -f "$am_block"
  if [ -n "$b" ]; then
    note_did "appended $am_label to $am_target (backup: $b)"
  else
    note_did "created $am_target with $am_label"
  fi
}

# ---------------------------------------------------------------------------
# 4. AGENTS.md — install or refresh the ultracode block between markers.
# ---------------------------------------------------------------------------
echo "-- AGENTS.md --"
append_marked "$AGENTS_MD" "$AGENTS_BEGIN" "$AGENTS_END" "$SRC_AGENTS" "overcodex ultracode block"
echo

# ---------------------------------------------------------------------------
# 5. .zshrc — append the integration snippet between markers (if absent).
# ---------------------------------------------------------------------------
echo "-- .zshrc --"
ZBEFORE_EXISTS=no
[ -f "$ZSHRC" ] && [ "$(marker_state "$ZSHRC" "$ZSH_BEGIN" "$ZSH_END")" = ok ] && ZBEFORE_EXISTS=yes
append_marked "$ZSHRC" "$ZSH_BEGIN" "$ZSH_END" "$SRC_ZSNIPPET" "overcodex integration block"
[ "$ZBEFORE_EXISTS" = no ] && note_warn "Open a new shell or run: source $ZSHRC"
echo

# ---------------------------------------------------------------------------
# 6. Verify.
# ---------------------------------------------------------------------------
echo "-- verify --"

# codex-swap resolves.
if command -v codex-swap >/dev/null 2>&1 || [ -x "$LOCALBIN/codex-swap" ]; then
  echo "  [ok] codex-swap resolves"
else
  note_warn "codex-swap does NOT resolve — is $LOCALBIN on PATH? (exec zsh, then re-check)"
fi

# hooks dir populated.
if ls "$CODEX_HOME"/hooks/*.sh >/dev/null 2>&1; then
  echo "  [ok] hooks dir populated: $CODEX_HOME/hooks/"
else
  note_warn "no hook scripts found under $CODEX_HOME/hooks/"
fi

# hooks + agent roles registered (the four overcodex hook commands, not just
# "some hooks key": Codex's own [hooks.state] trust records do not count).
if [ -n "$PYTHON" ] && [ -f "$CONFIG_TOML" ]; then
  VER_OUT=$("$PYTHON" "$CFG_TOOL" verify "$CONFIG_TOML" "$HOOKS_DIR_CFG" 2>&1)
  while IFS="$TAB" read -r kind msg; do
    case "$kind" in
      ok)   echo "  [ok] $msg" ;;
      fail) note_warn "$msg" ;;
      "")   : ;;
      *)    note_warn "$kind $msg" ;;
    esac
  done <<VEREOF
$VER_OUT
VEREOF
elif [ -f "$CONFIG_TOML" ] && grep -qF "$HOOKS_BEGIN" "$CONFIG_TOML" \
     && grep -Eq '^[[:space:]]*\[\[?hooks\.' "$CONFIG_TOML"; then
  note_warn "overcodex hooks block present but NOT verified (no TOML parser)"
else
  note_warn "overcodex hooks are not registered in config.toml — hooks will not load."
fi

# skills installed.
SK_MISSING=""
for sk in $SKILL_NAMES; do
  skill_owned "$CODEX_HOME/skills/$sk/SKILL.md" "$sk" || SK_MISSING="$SK_MISSING $sk"
done
if [ -z "$SK_MISSING" ]; then
  echo "  [ok] skills installed: $CODEX_HOME/skills/ ($SKILL_NAMES)"
else
  note_warn "overcodex skills missing (or replaced by your own) under $CODEX_HOME/skills:$SK_MISSING"
fi

# AGENTS marker present.
if [ -f "$AGENTS_MD" ] && [ "$(marker_state "$AGENTS_MD" "$AGENTS_BEGIN" "$AGENTS_END")" = ok ]; then
  echo "  [ok] AGENTS.md ultracode marker present"
else
  note_warn "AGENTS.md ultracode marker missing."
fi
echo

# ---------------------------------------------------------------------------
# Summary.
# ---------------------------------------------------------------------------
echo "== summary =="
echo "  changed:  ${#DID[@]}"
echo "  skipped:  ${#SKIPPED[@]}"
echo "  warnings: ${#WARNED[@]}"
if [ "${#WARNED[@]}" -gt 0 ]; then
  echo "  -- warnings --"
  i=0
  while [ "$i" -lt "${#WARNED[@]}" ]; do
    echo "    ! ${WARNED[$i]}"
    i=$((i + 1))
  done
fi
echo
echo "== next steps =="
if [ "$RETRUST" = 1 ]; then
  echo "  [!] The overcodex hooks are new or changed: Codex will not run them until you trust them (again)."
fi
echo "  1. Start a NEW codex session. When Codex shows \"Hooks need review\", choose"
echo "     \"Trust all and continue\" (or inspect them first with /hooks)."
echo "  2. Hook trust is per config path, so repeat step 1 once in EVERY codex-swap account"
echo "     (~/.codex-accounts/<name> has its own trust key even though config.toml is shared)."
if [ -d "$HOME/.codex-accounts" ]; then
  for acc in "$HOME/.codex-accounts"/*/; do
    [ -d "$acc" ] || continue
    echo "       - $(basename "$acc"):  codex-swap use $(basename "$acc"), then start codex"
  done
fi
echo "  3. Inside Codex, type \$handoff to hand off to a fresh session (\$handoff-status,"
echo "     \$handoff-cancel, \$handoff-claude, \$ultracode; browse them with /skills)."
echo
echo "Switch accounts with:  codex-swap use <name>  (cold switch: restart codex to adopt it)."
echo "Done."
