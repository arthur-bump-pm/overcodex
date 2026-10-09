#!/bin/bash
# Packaging + docs consistency: the wheel payload mapping carries everything
# install.sh needs (skills/ and lib/, no legacy prompts/), and the user-facing
# docs describe the skills-based UX of Codex 0.158 (no /prompts:* commands).
. "$(dirname "$0")/lib.sh"
PP="$REPO/pyproject.toml"
for d in bin hooks skills config codex agents shell skill lib; do
  assert_eq "$(toml "$PP" "d['tool']['hatch']['build']['targets']['wheel']['force-include'].get('$d')")" "overcodex/payload/$d" "wheel payload maps $d/"
  assert_contains "$(toml "$PP" "d['tool']['hatch']['build']['targets']['sdist']['include']")" "'/$d'" "sdist includes $d/"
  assert_true '[ -d "$REPO/'"$d"'" ]' "$d/ exists in the repo"
done
assert_eq "$(toml "$PP" "'prompts' in d['tool']['hatch']['build']['targets']['wheel']['force-include']")" "false" "legacy prompts/ is not in the payload"
assert_true '[ ! -e "$REPO/prompts" ]' "legacy prompts/ dir is gone from the repo"
assert_contains "$(toml "$PP" "d['project']['dependencies']")" "tomli" "Python < 3.11 installs get tomli (config.toml validator)"
for s in handoff handoff-status handoff-cancel handoff-claude ultracode; do
  f="$REPO/skills/$s/SKILL.md"
  assert_eq "$(sed -n 1p "$f")" "---" "$s: SKILL.md starts with YAML frontmatter"
  assert_eq "$(sed -n 2p "$f")" "name: $s" "$s: frontmatter name matches the directory"
  assert_contains "$(sed -n 3p "$f")" "description: " "$s: frontmatter has a description"
done
assert_contains "$(grep -E '^SHARED_ITEMS=' "$REPO/bin/codex-swap")" "skills" "codex-swap shares skills/ with accounts"

# Docs: the skills UX, hook trust, versions table; no stale prompt commands.
for f in README.md AGENT-SETUP.md; do
  assert_absent "$(grep -v -i 'legacy\|removed\|0\.158 dropped\|no longer' "$REPO/$f")" "/prompts:" "$f has no /prompts:* commands"
  assert_contains "$(cat "$REPO/$f")" '$handoff' "$f documents the \$handoff skill"
  assert_contains "$(cat "$REPO/$f")" "Trust all and continue" "$f documents hook trust"
done
README="$(cat "$REPO/README.md")"
assert_contains "$README" "## Versions" "README has a Versions table"
assert_contains "$README" "allow_managed_hooks_only" "README keeps the managed-hooks caveat"
assert_absent "$README" "blocks this kit's hooks from installing" "managed-hooks caveat is about running, not installing"
assert_absent "$README" "Sessions are sqlite, not JSONL" "README no longer says sessions are sqlite"
for c in 'codex-swap use' 'codex-swap which' 'codex-swap remove' 'codex-swap list --json' 'codex-swap path handoff' 'overcodex doctor'; do
  assert_contains "$README" "$c" "README command table lists: $c"
done
assert_absent "$(cat "$REPO/AGENTS.md" "$REPO/codex/AGENTS-ULTRACODE.md" "$REPO/overcodex-instructions.md" "$REPO/README.md")" '`none`' "no doc claims a \`none\` effort"
assert_contains "$(cat "$REPO/codex/AGENTS-ULTRACODE.md")" "ultra" "routing policy documents the ultra effort"
assert_contains "$(cat "$REPO/codex/AGENTS-ULTRACODE.md")" "gpt-6-astra" "routing policy names the catalog default model"
assert_eq "$(grep -rl '/Users/[A-Za-z]' "$REPO"/README.md "$REPO"/skills "$REPO"/hooks "$REPO"/lib "$REPO"/config 2>/dev/null)" "" "no /Users/<name> paths in shipped files"

# Built wheel. CI and sync.sh's release gate set OVERCODEX_REQUIRE_WHEEL=1, so
# a missing `build` module fails loudly there instead of skipping this check.
if ! "$PY" -c 'import build' >/dev/null 2>&1; then
  if [ "${OVERCODEX_REQUIRE_WHEEL:-}" = 1 ]; then
    fail "wheel check required but '$PY' has no 'build' module (pip install build)"
  else
    echo "  (wheel check skipped: no 'build' module in $PY)"
  fi
fi
if "$PY" -c 'import build' >/dev/null 2>&1; then
  W="$(mktemp -d "${TMPDIR:-/tmp}/overcodex-wheel.XXXXXX")"
  (cd "$REPO" && "$PY" -m build --wheel --outdir "$W" >/dev/null 2>&1)
  whl="$(ls "$W"/*.whl 2>/dev/null | head -n 1)"
  for f in install.sh uninstall.sh lib/overcodex_config.py skills/handoff/SKILL.md skills/handoff-claude/SKILL.md \
           hooks/overcodex-handoff-inject.sh config/hooks-block.toml.tpl bin/codex-swap shell/zshrc-snippet.sh; do
    assert_contains "$(unzip -l "$whl" 2>/dev/null)" "overcodex/payload/$f" "wheel carries $f"
  done
  assert_absent "$(unzip -l "$whl" 2>/dev/null)" "overcodex/payload/prompts/" "wheel carries no legacy prompts"
  rm -rf "$W"
fi
finish
