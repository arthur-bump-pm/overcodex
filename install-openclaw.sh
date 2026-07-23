#!/usr/bin/env bash
set -euo pipefail

repo_url="https://github.com/arthur-bump-pm/overcodex.git"

if ! command -v openclaw >/dev/null 2>&1; then
  echo "install-openclaw: openclaw is required and was not found" >&2
  exit 1
fi

if ! command -v overcodex >/dev/null 2>&1; then
  if ! command -v pipx >/dev/null 2>&1; then
    echo "install-openclaw: install pipx or overcodex first" >&2
    exit 1
  fi
  pipx install "git+${repo_url}"
fi

skill_path="$(overcodex skill-path)"
openclaw skills install "$skill_path" --global

echo "Overcodex UltraCode is installed in OpenClaw."
echo "Next: ask OpenClaw to run 'openclaw skills list' and 'openclaw agents list',"
echo "then configure scout, worker, reviewer, and judge agent IDs."
