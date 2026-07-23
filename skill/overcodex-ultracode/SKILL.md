---
name: overcodex-ultracode
description: Coordinate complex engineering work with explicit scout, worker, reviewer, and judge roles, portable across Codex and OpenClaw.
---

# Overcodex UltraCode

Use this skill for complex, cross-file, risky, or explicitly multi-agent work. Keep small, local edits in the current session. The main session owns requirements, decisions, integration, and the final answer.

## Roles

- **scout-luna-low**: fast, read-only reconnaissance; map relevant files, constraints, and likely risks.
- **worker-terra-medium**: bounded implementation; write only within an explicit ownership boundary and report changed files and tests.
- **reviewer-sol-high**: independent review; inspect the diff and behavior, then return `PASS`, `FAIL`, or `UNSURE` with evidence and confidence.
- **judge-sol-xhigh**: adjudicate contradictory findings, choose the safest supported interpretation, and identify unresolved risk.

## Dispatch contract

1. Select a role explicitly. A task name or friendly label alone does not select a model or policy.
2. Use the platform's exact role/agent identifier and request its configured model and reasoning level when supported.
3. Default to isolated context and one delegation level. Do not let a child recursively spawn more workers unless the task explicitly requires it.
4. If the platform cannot enforce role or model routing, preserve the role prompt but report that routing is advisory.

Codex naming is model-specific: GPT-5.5 uses `none`, `low`, `medium`, `high`, and `xhigh`; GPT-5.6 Sol/Terra/Luna also use `max`. Use `xhigh` for portable high-assurance review and reserve `max` for a GPT-5.6-only quality-critical adjudication. `ultra` is not a Codex effort value.

## Task-aware planning

Before dispatching, create a compact plan in the parent session. Decompose the request into independent workstreams, classify each as `inventory`, `mechanical`, `implementation`, `debugging`, `security`, `architecture`, or `adjudication`, and rate ambiguity, blast radius, reversibility, and verification difficulty. Choose the lowest-cost configured model that satisfies the task's verification floor:

| Task shape | Default role | Upgrade trigger |
|---|---|---|
| Inventory or fixed-schema extraction | `scout-luna-low` | ambiguity or security relevance |
| Bounded implementation | `worker-terra-medium` | shared contracts, broad blast radius, or weak tests |
| Reproducible debugging | worker, then `reviewer-sol-high` | nondeterminism or high impact |
| Security, auth, concurrency, migrations, destructive work | `reviewer-sol-high` | conflicting evidence or subtle judgment |
| Architecture tradeoffs or disputed findings | `judge-sol-xhigh` | only after independent evidence |

Every dispatch must state its objective, ownership paths, expected artifact, verification command, and escalation trigger. Stronger models are a targeted upgrade, not the default. If no configured role meets the floor, stop and report the capability gap instead of silently downgrading.

Platform mechanics are in [codex-adapter.md](references/codex-adapter.md) and [openclaw-adapter.md](references/openclaw-adapter.md).

## Coordination rules

- Read-only scouting may run in parallel. Writes to the same worktree run serially with explicit ownership.
- Before review, run the narrowest relevant tests and state the verification floor.
- Escalate `UNSURE`, confidence below 0.70, contradictory findings, security-sensitive changes, or a failed verification floor to the judge.
- Keep reviewer lenses independent: correctness, regressions, security, and operability are separate concerns.
- If more than 25% of delegated tasks escalate, stop scaling out and re-profile the work.
- When context is near its limit, package goals, decisions, changed files, tests, and exact next steps into a fresh-session handoff.

Reusable role prompts and output contracts are in [role-prompts.md](references/role-prompts.md).

## Safety

This skill provides coordination instructions, not permissions. Review hooks, scripts, and external tool calls before trusting them. Never bypass platform trust or sandbox controls as part of normal operation.
