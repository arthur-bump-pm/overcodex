#!/bin/bash
# install.sh — overcodex installer.
# macOS /bin/bash 3.2 compatible. set -u; errors handled explicitly.
# Reproduces the overcodex multi-account / ultracode setup for the Codex CLI.
#
# Never rewrites config.toml wholesale: top-level `hooks` and `[tui].status_line`
# are only ADDED when absent (detected with python3+tomllib, grep fallback),
# never overwritten. AGENTS.md and ~/.zshrc use begin/end marker blocks.

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
SRC_AGENTS="$SCRIPT_DIR/codex/AGENTS-ULTRACODE.md"
SRC_ZSNIPPET="$SCRIPT_DIR/shell/zshrc-snippet.sh"

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
HOOKS_BEGIN='# --- overcodex hooks (begin) ---'
HOOKS_END='# --- overcodex hooks (end) ---'
SL_BEGIN='# --- overcodex statusline (begin) ---'
SL_END='# --- overcodex statusline (end) ---'

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
for f in "$SRC_SWAP" "$SRC_HOOKS_TPL" "$SRC_AGENTS" "$SRC_ZSNIPPET"; do
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

# python3 is preferred for TOML read/decide; grep is the fallback.
PYTHON=""
if command -v python3 >/dev/null 2>&1 && python3 -c 'import tomllib' >/dev/null 2>&1; then
  PYTHON="python3"
  echo "  [ok] python3 + tomllib: $(command -v python3)"
else
  note_warn "python3 with tomllib not found — using grep-based config.toml detection (best effort)."
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

# prompts/*.md -> $CODEX_HOME/prompts/  (optional)
PROMPTS=$(ls "$SCRIPT_DIR"/prompts/*.md 2>/dev/null)
if [ -n "$PROMPTS" ]; then
  mkdir -p "$CODEX_HOME/prompts" || die "mkdir failed: $CODEX_HOME/prompts"
  for p in "$SCRIPT_DIR"/prompts/*.md; do
    [ -f "$p" ] || continue
    install_file "$p" "$CODEX_HOME/prompts/$(basename "$p")" -
  done
else
  note_skip "no prompts/*.md in kit (nothing to install)"
fi
echo

# ---------------------------------------------------------------------------
# 3. config.toml — add the inline [hooks] table and [tui].status_line IF ABSENT.
#    Never rewrites the file: python3+tomllib decides presence; the hooks block
#    is APPENDED at EOF between markers (a [hooks] table prepended at the top
#    would capture every top-level key after it); status_line is a [tui] insert.
# ---------------------------------------------------------------------------
echo "-- config.toml --"

# toml_present <config> -> prints "hooks=present|absent" and "sl=present|absent"
# on stdout. Exits 3 on a parse error (caller then leaves the file untouched).
toml_present() {
  tp_cfg="$1"
  if [ -n "$PYTHON" ]; then
    "$PYTHON" - "$tp_cfg" <<'PY'
import sys, tomllib
p = sys.argv[1]
try:
    with open(p, "rb") as f:
        d = tomllib.load(f)
except FileNotFoundError:
    d = {}
except Exception as e:
    sys.stderr.write("parse-error: %s\n" % e)
    sys.exit(3)
tui = d.get("tui")
tui = tui if isinstance(tui, dict) else {}
print("hooks=%s" % ("present" if "hooks" in d else "absent"))
print("sl=%s" % ("present" if "status_line" in tui else "absent"))
PY
    return $?
  fi
  # grep fallback (heuristic: matches a top-level-looking key line).
  if [ -f "$tp_cfg" ]; then
    if grep -Eq '^[[:space:]]*hooks[[:space:]]*=' "$tp_cfg"; then
      echo "hooks=present"; else echo "hooks=absent"; fi
    if grep -Eq '^[[:space:]]*status_line[[:space:]]*=' "$tp_cfg"; then
      echo "sl=present"; else echo "sl=absent"; fi
  else
    echo "hooks=absent"; echo "sl=absent"
  fi
  return 0
}

CFG_OK=1
DET=$(toml_present "$CONFIG_TOML")
if [ $? -eq 3 ]; then
  CFG_OK=0
  note_warn "config.toml is not valid TOML; leaving it completely untouched."
  note_warn "  Fix $CONFIG_TOML, then re-run ./install.sh to wire hooks/status_line."
fi

if [ "$CFG_OK" = 1 ]; then
  HOOKS_STATE=$(printf '%s\n' "$DET" | sed -n 's/^hooks=//p')
  SL_STATE=$(printf '%s\n' "$DET" | sed -n 's/^sl=//p')

  NEED_HOOKS=0
  [ "$HOOKS_STATE" = absent ] && NEED_HOOKS=1

  NEED_SL=0
  if [ "$SL_STATE" = absent ]; then
    if [ -n "$SRC_STATUSLINE" ]; then
      NEED_SL=1
    else
      note_skip "no statusline fragment in kit — leaving [tui].status_line alone"
    fi
  fi

  # Report the never-overwrite decisions.
  if [ "$HOOKS_STATE" = present ]; then
    if [ -f "$CONFIG_TOML" ] && grep -qF "$HOOKS_BEGIN" "$CONFIG_TOML"; then
      note_skip "config.toml hooks key already wired by overcodex"
    else
      note_warn "config.toml already defines a 'hooks' key — leaving it untouched."
      note_warn "  Merge the handlers from config/hooks-block.toml.tpl into your [hooks] table"
      note_warn "  manually (substitute @HOOKS_DIR@ with $CODEX_HOME/hooks)."
    fi
  fi
  if [ "$SL_STATE" = present ]; then
    if [ -f "$CONFIG_TOML" ] && grep -qF "$SL_BEGIN" "$CONFIG_TOML"; then
      note_skip "config.toml [tui].status_line already set by overcodex"
    else
      note_warn "config.toml already defines [tui].status_line — leaving it untouched."
    fi
  fi

  if [ "$NEED_HOOKS" = 1 ] || [ "$NEED_SL" = 1 ]; then
    b=""
    [ -f "$CONFIG_TOML" ] && b=$(backup_file "$CONFIG_TOML")
    TMP="$CONFIG_TOML.tmp-$EPOCH"
    : > "$TMP" || die "cannot write $TMP"

    # the existing file first, verbatim.
    [ -f "$CONFIG_TOML" ] && cat "$CONFIG_TOML" >> "$TMP"

    # hooks: APPEND the inline [hooks] table at EOF between markers, with
    # @HOOKS_DIR@ resolved. (EOF is the only safe spot for a table block —
    # prepended, it would capture the file's top-level keys.)
    if [ "$NEED_HOOKS" = 1 ]; then
      if [ -s "$TMP" ]; then
        [ -n "$(tail -c1 "$TMP")" ] && printf '\n' >> "$TMP"
        printf '\n' >> "$TMP"
      fi
      {
        printf '%s\n' "$HOOKS_BEGIN"
        sed "s|@HOOKS_DIR@|$CODEX_HOME/hooks|g" "$SRC_HOOKS_TPL"
        printf '%s\n' "$HOOKS_END"
      } >> "$TMP"
    fi

    # status_line: insert our keys just after an existing [tui] header, else
    # append a fresh [tui] table at EOF. Fragment header/comment/blank lines are
    # dropped so only the key lines land inside our markers.
    if [ "$NEED_SL" = 1 ]; then
      TMP2="$CONFIG_TOML.tmp2-$EPOCH"
      awk -v sb="$SL_BEGIN" -v se="$SL_END" -v kf="$SRC_STATUSLINE" '
        function emitkeys(   line) {
          while ((getline line < kf) > 0) {
            if (line == "" || line == "[tui]") continue
            if (line ~ /^[ \t]*#/) continue
            print line
          }
          close(kf)
        }
        { print }
        /^[ \t]*\[tui\][ \t]*(#.*)?$/ && done != 1 {
          print sb; emitkeys(); print se; done = 1
        }
        END {
          if (done != 1) { print ""; print sb; print "[tui]"; emitkeys(); print se }
        }
      ' "$TMP" > "$TMP2" || die "awk failed inserting status_line"
      mv "$TMP2" "$TMP" || die "could not stage status_line insert"
    fi

    # Validate before committing (python3 only; grep path trusts the insert).
    if [ -n "$PYTHON" ]; then
      "$PYTHON" - "$TMP" <<'PY' || { rm -f "$TMP"; die "generated config.toml is not valid TOML; original left untouched (backup: kept)"; }
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    tomllib.load(f)
PY
    fi

    mv "$TMP" "$CONFIG_TOML" || die "could not write $CONFIG_TOML"
    _bmsg=""
    [ -n "$b" ] && _bmsg=" (backup: $b)"
    [ "$NEED_HOOKS" = 1 ] && note_did "wired the inline [hooks] table into config.toml$_bmsg"
    [ "$NEED_SL" = 1 ]    && note_did "set [tui].status_line in config.toml$_bmsg"
  else
    [ "$HOOKS_STATE" = absent ] || [ "$NEED_HOOKS" = 1 ] || true
    note_skip "config.toml: no changes needed"
  fi
fi
echo

# ---------------------------------------------------------------------------
# append_marked <target> <begin> <end> <src> <label>
#   Append a marker-wrapped block only if the begin marker is absent. Any
#   pre-existing overcodex marker lines in <src> are stripped so we never nest.
# ---------------------------------------------------------------------------
append_marked() {
  am_target="$1"; am_begin="$2"; am_end="$3"; am_src="$4"; am_label="$5"
  if [ -f "$am_target" ] && grep -qF "$am_begin" "$am_target"; then
    note_skip "$am_label already present in $am_target"
    return 0
  fi
  mkdir -p "$(dirname "$am_target")" || die "mkdir failed for $am_target"
  b=""
  [ -f "$am_target" ] && b=$(backup_file "$am_target")
  # Separator blank line before our block when the file has content.
  if [ -f "$am_target" ] && [ -s "$am_target" ]; then
    [ -n "$(tail -c1 "$am_target")" ] && printf '\n' >> "$am_target"
    printf '\n' >> "$am_target"
  fi
  {
    printf '%s\n' "$am_begin"
    # Drop any stray marker lines already in the source to avoid nesting.
    grep -vxF "$am_begin" "$am_src" | grep -vxF "$am_end"
    printf '%s\n' "$am_end"
  } >> "$am_target" || die "could not append to $am_target"
  if [ -n "$b" ]; then
    note_did "appended $am_label to $am_target (backup: $b)"
  else
    note_did "created $am_target with $am_label"
  fi
}

# ---------------------------------------------------------------------------
# 4. AGENTS.md — append the ultracode block between markers (if absent).
# ---------------------------------------------------------------------------
echo "-- AGENTS.md --"
append_marked "$AGENTS_MD" "$AGENTS_BEGIN" "$AGENTS_END" "$SRC_AGENTS" "overcodex ultracode block"
echo

# ---------------------------------------------------------------------------
# 5. .zshrc — append the integration snippet between markers (if absent).
# ---------------------------------------------------------------------------
echo "-- .zshrc --"
ZBEFORE_EXISTS=no
[ -f "$ZSHRC" ] && grep -qF "$ZSH_BEGIN" "$ZSHRC" && ZBEFORE_EXISTS=yes
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

# hooks key wired.
HOOKS_WIRED=no
if [ -n "$PYTHON" ] && [ -f "$CONFIG_TOML" ]; then
  if "$PYTHON" - "$CONFIG_TOML" <<'PY' >/dev/null 2>&1
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    d = tomllib.load(f)
sys.exit(0 if "hooks" in d else 1)
PY
  then HOOKS_WIRED=yes; fi
elif [ -f "$CONFIG_TOML" ] && grep -Eq '^[[:space:]]*hooks[[:space:]]*=' "$CONFIG_TOML"; then
  HOOKS_WIRED=yes
fi
if [ "$HOOKS_WIRED" = yes ]; then
  echo "  [ok] config.toml hooks key wired"
else
  note_warn "config.toml has no hooks key — hooks will not load."
fi

# AGENTS marker present.
if [ -f "$AGENTS_MD" ] && grep -qF "$AGENTS_BEGIN" "$AGENTS_MD"; then
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
echo "Switch accounts with:  codex-swap  (isolated CODEX_HOME per account)."
echo "Done."
