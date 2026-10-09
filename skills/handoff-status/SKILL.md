---
name: handoff-status
description: "Read-only: show whether an overcodex handoff package is pending for this directory, how old it is, and whether the next `codex` launch will still load it."
metadata:
  short-description: "Show this directory's pending handoff"
---

# $handoff-status — check pending handoff state

## 1. Compute the state path

Run exactly this (macOS /bin/bash 3.2 compatible):

```bash
HASH=$(printf '%s' "$PWD" | /usr/bin/shasum -a 256 | awk '{print $1}' | cut -c1-12)
STATE_DIR="${CODEX_HOME:-$HOME/.codex}/overcodex"
PENDING="$STATE_DIR/handoff-pending-$HASH.md"
ls -t "$STATE_DIR/handoff-archive/"*"-$HASH"*.md 2>/dev/null | head -n 3
```

## 2. Report

- If `$PENDING` does not exist: report "no handoff pending for this directory", plus the newest archived packages for this directory if step 1 listed any (they are readable, but no longer auto-loaded).
- If it exists: read line 1 and extract `created="<epoch>"`; compute `AGE=$(( $(date +%s) - CREATED ))`.
  - Report the path, the age in minutes, and the one-line goal (the `# Handoff — <goal>` heading on line 2).
  - Age under 600 s: "still eligible — the next `codex` launch in this directory loads it."
  - Age 600 s or more: "expired — the next launch archives it instead of loading it; re-run `$handoff` to repackage."

Do not modify or delete anything — this is a read-only probe. To remove a pending package, point the user at `$handoff-cancel`.
