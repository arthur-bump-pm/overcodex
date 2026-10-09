#!/bin/bash
# sync.sh (M5) in a throwaway git copy of the repo, always with --dry-run (no
# commit, push or release ever happens): a version already ahead of the last
# tag is released as-is; otherwise patch-bumped; the release gate runs the test
# suite before anything ships; the scrub gate covers untracked files; the live
# -> repo loop pulls only files the repo already tracks.
. "$(dirname "$0")/lib.sh"
new_home
export TMPDIR="$HOME"   # sync.sh keeps a failed gate's log in $TMPDIR — keep it in the sandbox
command -v git >/dev/null 2>&1 || { echo "test_sync.sh: SKIPPED (no git)"; exit 0; }
command -v shellcheck >/dev/null 2>&1 || { echo "test_sync.sh: SKIPPED (no shellcheck)"; exit 0; }
R="$HOME/repo"
mkdir -p "$R"
(cd "$REPO" && tar cf - --exclude ./.git --exclude ./dist --exclude '*/__pycache__' .) | (cd "$R" && tar xf -)
STUB="$HOME/stub"; mkdir -p "$STUB"
printf '#!/bin/bash\necho "gh $*" >> "%s/gh-calls"\n' "$HOME" > "$STUB/gh"; chmod +x "$STUB/gh"
export PATH="$STUB:$PATH"
G() { git -C "$R" -c user.name=t -c user.email=t@example.com "$@"; }
# The gate's wheel-check Python: a stub that "has" tomllib and build, so the
# gate does not build a venv here (test_payload covers the real check).
printf '#!/bin/bash\nexit 0\n' > "$STUB/gate-python"; chmod +x "$STUB/gate-python"
export OVERCODEX_GATE_PYTHON="$STUB/gate-python"
# The suite itself is not re-run recursively: a stub stands in for tests/run.sh.
printf '#!/bin/bash\n[ "$OVERCODEX_REQUIRE_WHEEL" = 1 ] && [ -n "$OVERCODEX_TEST_PYTHON" ] || { echo "stub: FAIL wheel check not required"; exit 1; }\necho "stub: 3 passed, 0 failed"\n' > "$R/tests/run.sh"
sed -i '' 's/^version = ".*"$/version = "0.2.0"/' "$R/pyproject.toml"
G init -q && G add -A && G commit -q -m base && G tag v0.2.0
REV0="$(G rev-parse HEAD)"

sed -i '' 's/^version = ".*"$/version = "0.3.0"/' "$R/pyproject.toml"
o="$(cd "$R" && ./sync.sh --dry-run --release 2>&1)"
assert_contains "$o" "[ok] shellcheck" "release gate runs shellcheck"
assert_contains "$o" "[ok] test suite (3 checks" "release gate runs the test suite (with the wheel check required)"
assert_contains "$o" "[ok] wheel-check python: $STUB/gate-python" "#11: release gate picks a Python for the wheel check"
assert_contains "$o" "would bump 0.3.0 -> 0.3.0" "a version ahead of the last tag is released as-is"
assert_eq "$(G rev-parse HEAD)" "$REV0" "dry run commits nothing"
assert_true '[ ! -f "$HOME/gh-calls" ]' "dry run creates no release"

sed -i '' 's/^version = ".*"$/version = "0.2.0"/' "$R/pyproject.toml"
echo "# change" >> "$R/README.md"
o="$(cd "$R" && ./sync.sh --dry-run --release 2>&1)"
assert_contains "$o" "would bump 0.2.0 -> 0.2.1" "a version equal to the last tag is patch-bumped"
G checkout -q -- README.md

printf '#!/bin/bash\necho "stub: FAIL something"; exit 1\n' > "$R/tests/run.sh"
echo "# change" >> "$R/README.md"
o="$(cd "$R" && ./sync.sh --dry-run --release 2>&1)"
assert_contains "$o" "ABORTED — tests failed" "failing tests abort the release before anything ships"
assert_absent "$o" "would bump" "and no release is prepared"
G checkout -q -- README.md tests/run.sh

# Scrub covers brand-new untracked files (address assembled at runtime).
D=gmail; printf 'contact: jane.doe@%s.com\n' "$D" > "$R/notes.txt"
o="$(cd "$R" && ./sync.sh --dry-run 2>&1)"
assert_contains "$o" "ABORTED — added lines contain personal data" "scrub gate catches an untracked file"
rm -f "$R/notes.txt"

# Live -> repo: tracked hook and skill files are pulled; untracked live files are not.
mkdir -p "$CODEX_HOME/hooks" "$CODEX_HOME/skills/handoff" "$CODEX_HOME/skills/brand-new"
cp "$R/hooks/overcodex-notify.sh" "$CODEX_HOME/hooks/overcodex-notify.sh"
echo "# live edit" >> "$CODEX_HOME/hooks/overcodex-notify.sh"
cp "$R/skills/handoff/SKILL.md" "$CODEX_HOME/skills/handoff/SKILL.md"
echo "live skill edit" >> "$CODEX_HOME/skills/handoff/SKILL.md"
echo "untracked" > "$CODEX_HOME/hooks/brand-new-hook.sh"
echo "untracked" > "$CODEX_HOME/skills/brand-new/SKILL.md"
o="$(cd "$R" && ./sync.sh --dry-run 2>&1)"
assert_contains "$o" "would update: hooks/overcodex-notify.sh" "a tracked hook that differs from the live copy is reported"
assert_contains "$o" "would update: skills/handoff/SKILL.md" "a tracked skill that differs from the live copy is reported"
assert_eq "$(G status --porcelain -- hooks skills)" "" "--dry-run never overwrites repo files with live copies"
assert_true '[ ! -e "$R/hooks/brand-new-hook.sh" ] && [ ! -e "$R/skills/brand-new" ]' "untracked live files are never pulled"
assert_eq "$(G rev-parse HEAD)" "$REV0" "still nothing committed"

rm -rf "$HOME"
finish
