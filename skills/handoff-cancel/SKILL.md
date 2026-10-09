---
name: handoff-cancel
description: "Remove the pending overcodex handoff package for this directory so the next `codex` launch starts clean. Use only when the user asks to cancel a pending handoff."
metadata:
  short-description: "Cancel this directory's pending handoff"
---

# $handoff-cancel — cancel a pending handoff

## 1. Compute the state path

Run exactly this (macOS /bin/bash 3.2 compatible):

```bash
HASH=$(printf '%s' "$PWD" | /usr/bin/shasum -a 256 | awk '{print $1}' | cut -c1-12)
STATE_DIR="${CODEX_HOME:-$HOME/.codex}/overcodex"
PENDING="$STATE_DIR/handoff-pending-$HASH.md"
```

## 2. Cancel

- If `$PENDING` does not exist: report "no handoff pending for this directory — nothing to cancel."
- If it exists: read line 1 for the `created` epoch and line 2 for the goal, tell the user what is being removed ("removing the pending handoff from <age> ago: '<goal>'"), then delete it: `rm "$PENDING"`.

Only ever remove that single file for this directory's hash — never glob-delete other pending packages under `$STATE_DIR`; they belong to other working directories.
