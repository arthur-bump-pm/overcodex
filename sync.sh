#!/bin/bash
# sync.sh — pull the LIVE setup files from this machine back into the repo,
# scrub-check the diff for personal data, then commit and push.
# With --release: also bump the patch version and cut a GitHub release,
# which triggers the PyPI publish workflow.
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

# directory pairs: every file the repo already tracks under hooks/ and
# prompts/ is synced from its live counterpart in $CODEX_HOME. New files are
# added to the repo by hand (or via `overcodex install`'s payload), not by
# this loop, so an untracked live file never gets pulled in silently.
for dir in hooks prompts; do
  [ -d "$dir" ] || continue
  for repo_file in "$dir"/*; do
    [ -f "$repo_file" ] || continue
    base=$(basename "$repo_file")
    sync_one "$CODEX_HOME/$dir/$base" "$repo_file"
  done
done

# $CODEX_HOME/AGENTS.md block -> codex/AGENTS-ULTRACODE.md
if grep -qF "$AGENTS_BEGIN" "$CODEX_HOME/AGENTS.md" 2>/dev/null; then
  mkdir -p codex
  awk -v b="$AGENTS_BEGIN" -v e="$AGENTS_END" '$0 == b {f=1} f {print} $0 == e {f=0}' \
    "$CODEX_HOME/AGENTS.md" > .agents-ultracode.tmp
  if cmp -s .agents-ultracode.tmp codex/AGENTS-ULTRACODE.md; then
    echo "  [=] unchanged: codex/AGENTS-ULTRACODE.md"
    rm -f .agents-ultracode.tmp
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
  else
    mv .zshrc-snippet.tmp shell/zshrc-snippet.sh
    echo "  [+] updated:   shell/zshrc-snippet.sh"
    CHANGED=1
  fi
else
  echo "  [!] no overcodex block in ~/.zshrc; snippet left as-is" >&2
  rm -f .zshrc-snippet.tmp 2>/dev/null
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
  # Scrub gate: the diff must not contain personal data.
  # -------------------------------------------------------------------------
  ME=$(id -un)
  DIFF=$(git diff; git diff --cached)
  # First char after /Users/ must be alphanumeric so the literal "/Users/..."
  # (used in docs to describe this very gate) doesn't false-positive.
  HITS=$(printf '%s\n' "$DIFF" | grep -nE "^\+" | grep -E \
    -e "/Users/[A-Za-z0-9_-][A-Za-z0-9._-]*" \
    -e "[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z]{2,}" \
    -e "$ME" 2>/dev/null)
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
# --release: patch-bump the version and cut a GitHub release. The repo's
# publish.yml workflow then builds and publishes to PyPI (trusted publishing).
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

sed -i '' "s/^version = \"$CUR\"/version = \"$NEW\"/" pyproject.toml || exit 1
git add pyproject.toml && git commit -m "release: v$NEW" && git push || {
  echo "release: version-bump commit/push failed" >&2; exit 1
}
gh release create "v$NEW" --title "overcodex v$NEW" --notes "$NOTES" || {
  echo "release: gh release create failed — the version bump IS committed; re-run: gh release create v$NEW" >&2
  exit 1
}
echo "Release v$NEW created — GitHub Actions is now publishing to PyPI."
echo "Verify in ~2 min: pipx upgrade overcodex   (or: curl -s https://pypi.org/pypi/overcodex/json | jq -r .info.version)"
