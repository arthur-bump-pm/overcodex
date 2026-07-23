---
description: "Plan and execute a complex task with Codex subagents, model-aware routing, and independent verification."
argument-hint: "[task or objective]"
---

# /prompts:ultracode — explicit Codex multi-agent execution

Use the Codex-native UltraCode policy in `$CODEX_HOME/AGENTS.md`.

1. Restate the requested objective and split it into independent workstreams.
2. Classify each stream and choose the best registered Codex role/model/effort for it. Use the exact `agent_type` and `fork_turns = "none"` fields when spawning.
3. Before writing, announce the plan: workstream, owner, allowed paths, expected output, verification command, and escalation trigger.
4. Dispatch read-only scouts in parallel. Serialize workers that could touch overlapping paths.
5. Run objective checks before review. Use `reviewer-sol-high` for independent review and `judge-sol-xhigh` only for unresolved or high-risk disputes.
6. Synthesize the results in the parent session. Report which agents ran, what they contributed, model/effort selected, checks run, and residual risk.

If the task is too small or inherently sequential, do it in the parent and explicitly state why delegation would not add value.
