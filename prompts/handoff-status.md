---
description: "Show whether a handoff package is pending for this directory, and how old it is."
argument-hint: ""
---

# /prompts:handoff-status — check pending handoff state

## 1. Compute the state path

Run exactly this (macOS /bin/bash 3.2 compatible):

```bash
HASH=$(printf '%s' "$PWD" | /usr/bin/shasum -a 256 | awk '{print $1}' | cut -c1-12)
STATE_DIR="${CODEX_HOME:-$HOME/.codex}/overcodex"
PENDING="$STATE_DIR/handoff-pending-$HASH.md"
```

## 2. Report

- If `$PENDING` does not exist: report "no handoff pending for this directory."
- If it exists: read line 1, extract `created="<epoch>"`. Compute age with `NOW=$(date +%s); AGE=$((NOW - CREATED))`.
  - Report the path, age in minutes, and the one-line goal (from the `# Handoff — <goal>` heading, line 2).
  - If age < 600s: "still eligible for auto-injection on next `codex` launch in this directory."
  - If age >= 600s: "expired — no longer auto-injected; contents are still readable at this path, or run `/prompts:handoff` again to repackage."

Do not modify or delete the file — this is a read-only probe. If the user wants it removed, point them at `/prompts:handoff-cancel`.
