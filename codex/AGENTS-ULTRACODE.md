# --- overcodex ultracode (begin) ---
# ULTRACODE - Codex multi-agent routing policy

## When to delegate
For a complex task with at least two independent, useful work streams, use subagents proactively by default. Good candidates are read-heavy exploration, independent verification, test/log analysis, and clearly partitioned implementation. A qualifying task should not remain entirely in the parent unless the parent records a concrete reason: no independent stream, unsafe shared writes, unavailable role/model, or coordination cost greater than the expected benefit. Do not spawn agents for a small task or work that is inherently sequential.

At the start of every qualifying task, silently perform the UltraCode planning gate below, then tell the user the selected workstreams and roles before dispatching. The parent must either dispatch at least one useful subagent or state the exception that kept the work serial.

Keep the main thread focused on requirements, decisions, and final synthesis. Give each subagent a bounded objective, scope, expected output, and verification standard. Wait for all required results before synthesizing.

## Ultra planning gate
Before spawning, write a short routing plan in the parent context:

1. Decompose the request into atomic workstreams and identify dependencies.
2. Classify each stream as `inventory`, `mechanical`, `implementation`, `debugging`, `security`, `architecture`, or `adjudication`.
3. Score each stream for ambiguity, blast radius, reversibility, and verification difficulty (low/medium/high).
4. Select the lowest-cost model that meets the task's verification floor. Model choice must be justified by task fit, not by a generic preference for the strongest model.
5. State ownership, allowed paths, expected artifact, test command, and escalation trigger for every dispatch.

Routing guidance:

| Task shape | Default model | Upgrade when |
|---|---|---|
| Inventory, search, schema extraction | `scout-luna-low` | the result is ambiguous or security-relevant |
| Mechanical, bounded implementation | `worker-terra-medium` | the change crosses shared contracts or tests are weak |
| Debugging with a reproducible failure | `worker-terra-medium` then `reviewer-sol-high` | the cause is nondeterministic or high blast radius |
| Security, auth, concurrency, migrations, destructive operations | `reviewer-sol-high` | evidence conflicts or the decision is subtle |
| Architecture tradeoff or disputed review | `judge-sol-xhigh` | only after independent evidence exists |

Do not use `judge-sol-xhigh` as a default worker. Do not send implementation to a read-only role. If no role meets the floor, stop and say what capability or model is missing rather than silently downgrading.

## Installed roles
Use these exact Codex custom-agent types when their role fits:

| Agent | Model / effort | Use for |
|---|---|---|
| `scout-luna-low` | Luna / low | File discovery, mechanical inventory, fixed-schema extraction |
| `worker-terra-medium` | Terra / medium | Well-scoped implementation with explicit ownership |
| `reviewer-sol-high` | Sol / high | Independent correctness, security, regression, and test review |
| `judge-sol-xhigh` | Sol / xhigh | Contradiction resolution and subtle terminal verdicts |

Codex effort compatibility is model-specific. GPT-5.5 supports `none`, `low`, `medium`, `high`, and `xhigh`. GPT-5.6 Sol/Terra/Luna additionally support `max`. Keep `xhigh` as the portable judge default; select `max` only for a GPT-5.6 task whose quality requirement justifies extra cost and latency. Never write `ultra` as a Codex `model_reasoning_effort` value.

Use the parent Sol session for final synthesis. A high or xhigh parent effort may orchestrate proactively, but it does not remove the need for explicit role and scope selection.

When dispatching one of these roles, the `spawn_agent` call MUST set `agent_type` to the exact name above and `fork_turns` to `"none"`. Put all required task context in the child message. `task_name` is only a label and does not select a model; omitting `agent_type` silently inherits the parent model, while a full-history fork rejects role/model overrides.

## Coordination rules
- Read-heavy work may run in parallel. Write-heavy work is serial by default.
- Never let two agents edit the same files concurrently. If parallel writes are justified, partition ownership by non-overlapping paths and say so in every worker prompt.
- Run objective checks such as tests, typecheck, lint, or numeric validation before spending a reviewer agent. A passing deterministic check outranks an LLM opinion.
- Verification must be independent: give the reviewer the artifact, requirements, and evidence, not the generator's conclusion.
- Every reviewer returns `verdict`, `confidence`, and `evidence`. Missing fields, confidence below 0.7, `UNSURE`, or contradictory results trigger one escalation to the next stronger role.
- Use panels only for high-risk fuzzy judgments. Give 2-3 reviewers distinct lenses; unanimous results may pass, while a split goes to `judge-sol-xhigh` rather than majority vote.
- Stop escalating when more than one quarter of downgraded stages require escalation. Re-plan the routing instead of silently moving every task to Sol.
- Reduce fan-out before lowering verification quality. The default `agents.max_depth = 1` is appropriate unless the user explicitly requests recursive delegation.

## Floors
- User-visible final synthesis with no downstream check: parent Sol session.
- Security, auth, concurrency, money math, destructive operations, and migrations: `reviewer-sol-high` minimum.
- A subtle disputed verdict: `judge-sol-xhigh`.
- Bulk or repetitive work stays on Luna or Terra even when the parent runs at high or xhigh effort.

## Dispatch lint
Before spawning, confirm that each agent adds new information or independent verification; has an objective, path or topic boundary, and output contract; uses the lowest role that meets its floor; and cannot race another writer. If those conditions are not met, keep the work in the main thread.
# --- overcodex ultracode (end) ---
