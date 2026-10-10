#!/bin/bash
# tests/lib.sh — tiny assertion helpers for the plain-bash test suite.
# Every test runs the REPO copies of the kit inside a throwaway $HOME, so the
# developer's live setup (~/.codex, ~/.codex-accounts, ~/.zshrc) is never read
# or written. macOS /bin/bash 3.2 compatible.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CS="$REPO/bin/codex-swap"
CFG_TOOL="$REPO/lib/overcodex_config.py"

T_PASS=0
T_FAIL=0
T_NAME="${0##*/}"

# A python3 with a TOML parser (tomllib >= 3.11, or tomli) for assertions and
# for install.sh (exported as OVERCODEX_PYTHON, like `overcodex install` does).
PY=""
if [ -n "${OVERCODEX_TEST_PYTHON:-}" ] && ! "$OVERCODEX_TEST_PYTHON" "$CFG_TOOL" check >/dev/null 2>&1; then
  echo "tests: OVERCODEX_TEST_PYTHON='$OVERCODEX_TEST_PYTHON' has no tomllib/tomli — refusing to fall back silently" >&2
  exit 1
fi
for _c in "${OVERCODEX_TEST_PYTHON:-}" python3.14 python3.13 python3.12 python3.11 python3 /usr/bin/python3; do
  [ -n "$_c" ] || continue
  command -v "$_c" >/dev/null 2>&1 || continue
  if "$_c" "$CFG_TOOL" check >/dev/null 2>&1; then PY="$_c"; break; fi
done
if [ -z "$PY" ]; then
  echo "tests: no python3 with tomllib/tomli found — set OVERCODEX_TEST_PYTHON" >&2
  exit 1
fi
export OVERCODEX_PYTHON="$PY"

# new_home — fresh sandbox HOME (exported) with an empty CODEX_HOME. Every
# sandbox a test creates is removed on exit.
TH_ALL=""
trap 'for _d in $TH_ALL; do rm -rf "$_d" 2>/dev/null || { sleep 1; rm -rf "$_d" 2>/dev/null; }; done' EXIT
new_home() {
  TH="$(mktemp -d "${TMPDIR:-/tmp}/overcodex-test.XXXXXX")"
  TH="$(cd "$TH" && pwd -P)"
  TH_ALL="$TH_ALL $TH"
  export HOME="$TH"
  export CODEX_HOME="$TH/.codex"
  mkdir -p "$CODEX_HOME"
  export PATH="$TH/.local/bin:$PATH"
}

# toml <file> <python-expr over d> — evaluate an expression on the parsed TOML.
toml() {
  "$PY" - "$1" "$2" <<'PY'
import sys
try:
    import tomllib
except ImportError:
    import tomli as tomllib
with open(sys.argv[1], "rb") as f:
    d = tomllib.load(f)
v = eval(sys.argv[2], {"d": d})
print(v if not isinstance(v, bool) else str(v).lower())
PY
}

toml_valid() { "$PY" - "$1" <<'PY' >/dev/null 2>&1
import sys
try:
    import tomllib
except ImportError:
    import tomli as tomllib
with open(sys.argv[1], "rb") as f:
    tomllib.load(f)
PY
}

# block_body <file> <name> — lines strictly between an overcodex marker pair.
block_body() {
  awk -v b="# --- overcodex $2 (begin) ---" -v e="# --- overcodex $2 (end) ---" \
    '$0 == e {f=0} f {print} $0 == b {f=1}' "$1"
}

pass() { T_PASS=$((T_PASS + 1)); }
fail() { T_FAIL=$((T_FAIL + 1)); printf '  FAIL [%s] %s\n' "$T_NAME" "$1"; [ -n "${2:-}" ] && printf '       got: %s\n' "$2"; }

assert_eq()       { if [ "$1" = "$2" ]; then pass; else fail "$3 (expected '$2')" "$1"; fi; }
assert_contains() { case "$1" in *"$2"*) pass;; *) fail "$3 (expected to contain '$2')" "$1";; esac; }
assert_absent()   { case "$1" in *"$2"*) fail "$3 (expected NOT to contain '$2')" "$1";; *) pass;; esac; }
assert_true()     { if eval "$1"; then pass; else fail "$2"; fi; }

finish() {
  printf '%s: %d passed, %d failed\n' "$T_NAME" "$T_PASS" "$T_FAIL"
  [ "$T_FAIL" -eq 0 ]
}
