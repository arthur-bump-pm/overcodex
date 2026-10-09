#!/bin/bash
# sync.sh — pull the LIVE setup files from this machine back into the repo,
# scrub-check the diff for personal data, then commit and push.
# With --release: run the release gate (shellcheck + the full test suite) BEFORE
# anything is committed, then cut a GitHub release, which triggers the PyPI
# publish workflow. The patch version is bumped unless pyproject.toml is already
# ahead of the last tag (a manual minor/major bump), which is released as-is.
# macOS /bin/bash 3.2 compatible.
# Usage: ./sync.sh [--dry-run] [--release] [commit message]
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR" || exit 1

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

DRY_RUN=no
RELEASE=no
MSG=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=yes ;;
    --release) RELEASE=yes ;;
    *) MSG="$arg" ;;
  esac
done
[ -n "$MSG" ] || MSG="sync: update from live setup ($(date +%Y-%m-%d))"

BEGIN_MARKER='# --- overcodex integration (begin) ---'
END_MARKER='# --- overcodex integration (end) ---'
AGENTS_BEGIN='# --- overcodex ultracode (begin) ---'
AGENTS_END='# --- overcodex ultracode (end) ---'

echo "== overcodex sync (live -> repo) =="
CHANGED=0

sync_one() {
  # sync_one <live-path> <repo-path>
  live="$1"; repo="$2"
  if [ ! -f "$live" ]; then
    echo "  [!] live file missing, skipped: $live" >&2
    return
  fi
  mkdir -p "$(dirname "$repo")"
  if cmp -s "$live" "$repo" 2>/dev/null; then
    echo "  [=] unchanged: $repo"
  elif [ "$DRY_RUN" = yes ]; then
    echo "  [~] would update: $repo (live differs — run ./install.sh first if the repo is newer)"
    CHANGED=1
  else
    cp "$live" "$repo" || { echo "sync: ERROR copying $live" >&2; exit 1; }
    echo "  [+] updated:   $repo"
    CHANGED=1
  fi
}

# single-file pairs: live-path:repo-path (bash 3.2: newline list, no assoc arrays)
PAIRS="$HOME/.local/bin/codex-swap:bin/codex-swap"

old_ifs="$IFS"; IFS='
'
for pair in $PAIRS; do
  IFS="$old_ifs"
  live="${pair%%:*}"; repo="${pair#*:}"
  sync_one "$live" "$repo"
  IFS='
'
done
IFS="$old_ifs"

# Only files the repo already TRACKS under hooks/ and skills/ are pulled from
# their live counterparts in $CODEX_HOME (hooks/<f>, skills/<name>/<f>). A new
# hook or skill file is added to the repo by hand (or via a payload change) —
# an untracked live file is never pulled in silently.
TRACKED=$(git ls-files -- hooks skills 2>/dev/null)
old_ifs="$IFS"; IFS='
'
for repo_file in $TRACKED; do
  IFS="$old_ifs"
  sync_one "$CODEX_HOME/$repo_file" "$repo_file"
  IFS='
'
done
IFS="$old_ifs"

# $CODEX_HOME/AGENTS.md block -> codex/AGENTS-ULTRACODE.md
if grep -qF "$AGENTS_BEGIN" "$CODEX_HOME/AGENTS.md" 2>/dev/null; then
  mkdir -p codex
  awk -v b="$AGENTS_BEGIN" -v e="$AGENTS_END" '$0 == b {f=1} f {print} $0 == e {f=0}' \
    "$CODEX_HOME/AGENTS.md" > .agents-ultracode.tmp
  if cmp -s .agents-ultracode.tmp codex/AGENTS-ULTRACODE.md; then
    echo "  [=] unchanged: codex/AGENTS-ULTRACODE.md"
    rm -f .agents-ultracode.tmp
  elif [ "$DRY_RUN" = yes ]; then
    rm -f .agents-ultracode.tmp
    echo "  [~] would update: codex/AGENTS-ULTRACODE.md (live differs — run ./install.sh first if the repo is newer)"
    CHANGED=1
  else
    mv .agents-ultracode.tmp codex/AGENTS-ULTRACODE.md
    echo "  [+] updated:   codex/AGENTS-ULTRACODE.md"
    CHANGED=1
  fi
else
  echo "  [!] no overcodex ultracode block in \$CODEX_HOME/AGENTS.md; kit copy left as-is" >&2
  rm -f .agents-ultracode.tmp 2>/dev/null
fi

# zshrc block -> shell/zshrc-snippet.sh
if grep -qF "$BEGIN_MARKER" "$HOME/.zshrc" 2>/dev/null; then
  awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" '$0 == b {f=1} f {print} $0 == e {f=0}' \
    "$HOME/.zshrc" > .zshrc-snippet.tmp
  if cmp -s .zshrc-snippet.tmp shell/zshrc-snippet.sh; then
    echo "  [=] unchanged: shell/zshrc-snippet.sh"
    rm -f .zshrc-snippet.tmp
  elif [ "$DRY_RUN" = yes ]; then
    rm -f .zshrc-snippet.tmp
    echo "  [~] would update: shell/zshrc-snippet.sh (live differs — run ./install.sh first if the repo is newer)"
    CHANGED=1
  else
    mv .zshrc-snippet.tmp shell/zshrc-snippet.sh
    echo "  [+] updated:   shell/zshrc-snippet.sh"
    CHANGED=1
  fi
else
  echo "  [!] no overcodex block in ~/.zshrc; snippet left as-is" >&2
  rm -f .zshrc-snippet.tmp 2>/dev/null
fi

# ---------------------------------------------------------------------------
# Release gate: shellcheck + the full suite must pass BEFORE anything is
# committed, pushed, or released. CI re-checks, but by then a GitHub release
# already exists — a red CI run would leave a release with no PyPI package.
# Runs under /bin/bash 3.2, the strictest shell users' `env bash` resolves to.
# ---------------------------------------------------------------------------
SHELLCHECK_FILES="bin/codex-swap hooks/*.sh install.sh uninstall.sh install-openclaw.sh sync.sh scrub.sh shell/zshrc-snippet.sh tests/*.sh"
if [ "$RELEASE" = yes ]; then
  echo
  echo "== release gate (tests before anything ships) =="
  command -v shellcheck >/dev/null 2>&1 || {
    echo "release: shellcheck not found — brew install shellcheck" >&2; exit 1; }
  # shellcheck disable=SC2086  # intentional glob/word splitting of the file list
  shellcheck -S error $SHELLCHECK_FILES || {
    echo "release: ABORTED — shellcheck errors (nothing committed or released)." >&2; exit 1; }
  echo "  [ok] shellcheck"
  # The wheel-payload check needs a Python with tomllib/tomli AND `build`. Use
  # one that has both, else build a throwaway venv; never let it skip quietly.
  GATE_PY=""
  for c in "${OVERCODEX_GATE_PYTHON:-}" python3.14 python3.13 python3.12 python3.11 python3; do
    [ -n "$c" ] && command -v "$c" >/dev/null 2>&1 || continue
    if "$c" lib/overcodex_config.py check >/dev/null 2>&1 && "$c" -c 'import build' >/dev/null 2>&1; then
      GATE_PY="$c"; break
    fi
  done
  GATE_VENV=""
  if [ -z "$GATE_PY" ]; then
    for c in python3.14 python3.13 python3.12 python3.11 python3; do
      command -v "$c" >/dev/null 2>&1 && "$c" lib/overcodex_config.py check >/dev/null 2>&1 || continue
      GATE_VENV=$(mktemp -d "${TMPDIR:-/tmp}/overcodex-gate-venv.XXXXXX")
      if "$c" -m venv "$GATE_VENV" >/dev/null 2>&1 \
         && "$GATE_VENV/bin/python" -m pip install --quiet build >/dev/null 2>&1; then
        GATE_PY="$GATE_VENV/bin/python"
      fi
      break
    done
  fi
  [ -n "$GATE_PY" ] || {
    [ -n "$GATE_VENV" ] && rm -rf "$GATE_VENV"
    echo "release: ABORTED — no Python with tomllib + build for the wheel check (pip install build)." >&2; exit 1; }
  echo "  [ok] wheel-check python: $GATE_PY"
  GATE_LOG=$(mktemp "${TMPDIR:-/tmp}/overcodex-gate.XXXXXX")
  if PATH=/bin:/usr/bin:$PATH OVERCODEX_TEST_PYTHON="$GATE_PY" OVERCODEX_REQUIRE_WHEEL=1 \
       /bin/bash tests/run.sh >"$GATE_LOG" 2>&1; then
    [ -n "$GATE_VENV" ] && rm -rf "$GATE_VENV"
    echo "  [ok] test suite ($(awk '/ passed, /{n+=$2} END{print n+0}' "$GATE_LOG") checks, /bin/bash 3.2)"
    rm -f "$GATE_LOG"
  else
    [ -n "$GATE_VENV" ] && rm -rf "$GATE_VENV"
    grep -E 'FAIL|failed' "$GATE_LOG" | tail -25 >&2
    echo "release: ABORTED — tests failed (nothing committed or released). Full log: $GATE_LOG" >&2
    exit 1
  fi
fi

NOTHING_TO_COMMIT=no
if [ "$CHANGED" -eq 0 ] && git diff --quiet && git diff --cached --quiet \
   && [ -z "$(git status --porcelain 2>/dev/null)" ]; then
  NOTHING_TO_COMMIT=yes
fi

if [ "$NOTHING_TO_COMMIT" = yes ] && [ "$RELEASE" = no ]; then
  echo "Nothing to sync — repo already matches the live setup."
  exit 0
fi

if [ "$NOTHING_TO_COMMIT" = no ]; then
  # -------------------------------------------------------------------------
  # Scrub gate: the diff must not contain personal data. Scanned: tracked
  # changes AND brand-new untracked files (`git add -A` below commits those
  # too). The matching rules live in scrub.sh (tested by tests/test_scrub.sh).
  # -------------------------------------------------------------------------
  ME=$(id -un)
  DIFF=$(git diff; git diff --cached
         git ls-files --others --exclude-standard -z |
           xargs -0 -I{} sed 's/^/+/' {} 2>/dev/null)
  HITS=$(printf '%s\n' "$DIFF" | bash ./scrub.sh "$ME")
  if [ -n "$HITS" ]; then
    echo
    echo "sync: ABORTED — added lines contain personal data (username/email//Users path):" >&2
    printf '%s\n' "$HITS" | head -20 >&2
    echo "Fix the live files (keep them \$HOME/\$CODEX_HOME-relative and generic), then re-run." >&2
    exit 1
  fi
  echo "  [ok] scrub: no personal data in the diff"

  echo
  git --no-pager diff --stat
  if [ "$DRY_RUN" = yes ]; then
    echo
    echo "(dry run — nothing committed)"
    [ "$RELEASE" = yes ] || exit 0
  else
    git add -A || exit 1
    git commit -m "$MSG" || exit 1
    git push || { echo "sync: commit created but push failed — push manually." >&2; exit 1; }
    echo "Pushed."
  fi
fi

# ---------------------------------------------------------------------------
# --release: cut a GitHub release (patch-bumping the version unless it is
# already ahead of the last tag). The repo's publish.yml workflow then builds
# and publishes to PyPI (trusted publishing).
# Remember: git push alone does NOT update PyPI — only releases do.
# ---------------------------------------------------------------------------
[ "$RELEASE" = yes ] || exit 0
echo
echo "== release =="

command -v gh >/dev/null 2>&1 || {
  echo "release: gh CLI not found — bump the version in pyproject.toml and create the release manually." >&2
  exit 1
}

# gh creates release tags on the REMOTE only — fetch them or describe sees nothing.
git fetch --tags --quiet 2>/dev/null
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null) || LAST_TAG=""
if [ "$NOTHING_TO_COMMIT" = yes ] && [ -n "$LAST_TAG" ] \
   && [ "$(git rev-list -n 1 "$LAST_TAG" 2>/dev/null)" = "$(git rev-parse HEAD)" ]; then
  echo "No commits since $LAST_TAG — nothing to release."
  exit 0
fi

CUR=$(sed -n 's/^version = "\(.*\)"$/\1/p' pyproject.toml | head -1)
case "$CUR" in
  *.*.*) : ;;
  *) echo "release: could not parse version from pyproject.toml (got: '$CUR')" >&2; exit 1 ;;
esac
NEW=$(printf '%s' "$CUR" | awk -F. '{printf "%d.%d.%d", $1, $2, $3+1}')
# Manual minor/major bump (version already ahead of the last tag): release it as-is.
if [ -n "$LAST_TAG" ] && [ "$CUR" != "${LAST_TAG#v}" ] \
   && [ "$(printf '%s\n%s\n' "${LAST_TAG#v}" "$CUR" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" = "$CUR" ]; then
  NEW="$CUR"
fi

# Release notes: the commits since the last tag (before the bump commit).
if [ -n "$LAST_TAG" ]; then
  NOTES=$(git log "$LAST_TAG"..HEAD --oneline --no-decorate | sed 's/^[a-f0-9]* /- /')
else
  NOTES=""
fi
# Nothing committed yet at preview time (or first release): fall back to the sync message.
[ -n "$NOTES" ] || NOTES="- $MSG"

if [ "$DRY_RUN" = yes ]; then
  echo "(dry run) would bump $CUR -> $NEW and create release v$NEW with notes:"
  printf '%s\n' "$NOTES"
  exit 0
fi

if [ "$NEW" != "$CUR" ]; then
  sed -i '' "s/^version = \"$CUR\"/version = \"$NEW\"/" pyproject.toml || exit 1
  git add pyproject.toml && git commit -m "release: v$NEW" || {
    echo "release: version-bump commit failed" >&2; exit 1
  }
fi
# Manual bump: the version is already committed, so there is no bump commit — just push.
git push || { echo "release: push failed" >&2; exit 1; }
gh release create "v$NEW" --title "overcodex v$NEW" --notes "$NOTES" || {
  echo "release: gh release create failed — the version bump IS committed; re-run: gh release create v$NEW" >&2
  exit 1
}
echo "Release v$NEW created — GitHub Actions is now publishing to PyPI."
echo "Verify in ~2 min: pipx upgrade overcodex   (or: curl -s https://pypi.org/pypi/overcodex/json | jq -r .info.version)"
echo "Other machines update with: pipx upgrade overcodex && overcodex install"
