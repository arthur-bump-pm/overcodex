#!/bin/bash
# tests/run.sh — run tests/smoke.sh and every tests/test_*.sh; exit 1 if any fails.
# Needs bash, jq, a python3 with tomllib (or tomli) and macOS userland. No live
# state is touched: every test uses a throwaway $HOME. test_codex_live.sh also
# drives the installed Codex CLI's `codex app-server` (no model calls) and skips
# itself when codex is not installed.
cd "$(dirname "$0")" || exit 1
rc=0
for t in smoke.sh test_*.sh; do
  bash "$t" || { rc=1; echo "  -> $t FAILED"; }
done
[ "$rc" -eq 0 ] && echo "ALL TESTS PASSED" || echo "TESTS FAILED"
exit "$rc"
