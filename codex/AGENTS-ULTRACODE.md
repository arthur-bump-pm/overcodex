# --- overcodex ultracode (begin) ---
# ULTRACODE.md — Model & Effort Routing for Codex (v2-codex, ported 2026-07 from the Claude Code ULTRACODE v2)

## 1. Core principle
Spend the flagship tier only where judgment is the bottleneck, never where volume is. `model_reasoning_effort` and any per-role `model` override that you omit silently inherits the top-level `model` (currently `gpt-5.6-sol` — the flagship). Explicit down-routing is your default posture, not an optimization.
Route each subagent/role by one question: "if this is quietly wrong, who catches it?" — a downstream check means you may downgrade; nobody means top tier.

## 2. Tier map (GPT-5.6 family, mid-2026)
Codex's current lineup is three permanent price/capability tiers, not a Claude-style haiku/sonnet/opus/apex ladder — treat them as the equivalent rungs:

| Rung | Codex tier | Claude-side equivalent | Use for |
|---|---|---|---|
| 1 (cheap/fast) | **Luna** | haiku | scouting, file listing, mechanical transforms, fixed-schema extraction |
| 2 (mid) | **Terra** | sonnet | finder sweeps, well-scoped implementation edits, bulk reading of dense code |
| 3 (flagship) | **Sol** | opus | security sweeps, cross-cutting edits, adversarial verification, judge panels, completeness critics |
| 3 + effort ceiling | **Sol @ high** (or the Max reasoning-effort / Ultra sub-agent mode where the deployment exposes it) | fable/apex | terminal judge, final synthesis, subtle-correctness verdicts |

Effort is the second axis: `model_reasoning_effort = low \| medium \| high` (config.toml or `--config`). Pair rung × effort the same way ULTRACODE always has:
- Rung 1 → low. Rung 2 → medium. Rung 3 → high. Terminal/apex → Sol @ high, plus Max/Ultra if the account has it — never below Sol.
- Effort amplifies capability, it never substitutes: Luna@high loses to Terra@medium on judgment work. Never pair a high-effort setting with a fan-out stage.

## 3. Routing surface (how to actually pin a tier per subagent)
Codex's per-subagent override surface is younger than Claude Code's Task-tool `model` param — there is no first-class "one dispatch call, one model" primitive yet. Use what exists, and state the gap honestly where it doesn't:
- **`[agents]` table (`AgentRoleToml` per role)** in config.toml — the closest analog to Claude's per-agent `model`. Give each role you define (scout, finder, verifier, judge) its own `model` + `model_reasoning_effort` entry. This is the primary lever; use it whenever the orchestrator supports role-scoped agents.
- **`profiles`** (`codex --profile <name>`) — a named bundle of `model` + `model_reasoning_effort` (+ sandbox/approval settings). Define one profile per rung (e.g. `scout`, `implement`, `verify`, `apex`) and invoke the right profile per stage instead of editing global config mid-session.
- **`orchestrator.max_threads` / `max_depth`** — the fan-out width and recursion-depth knobs. Set `max_threads` to match the routing-lint width rule below (wide stages get width, not tier); use `max_depth` to cap runaway recursive sub-agent spawning, which is the Codex-side proxy for "never two agents editing the same files."
- **Where enforcement is weak** (no live per-call model override mid-session, no schema-typed subagent handoff): the orchestrating model itself must apply the routing table by discipline — choosing the right profile/role before dispatch — because the harness will not silently downgrade or refuse an unrouted call the way a stricter per-call API might. Say so in-session rather than assuming the harness caught it.

## 4. Hard guardrails (unchanged from v2, ported verbatim)
Never downgrade below floor:
- Final synthesis and any output the user sees with no downstream check: Sol, never below. Terminal stage = apex profile, or Sol@high with Max/Ultra if available.
- Adversarial verification, judge panels, security verdicts, completeness critics: Sol floor. A false CONFIRM ends scrutiny.
- Subtle-correctness verdicts (concurrency, auth/crypto, money math, migrations): apex — "looks correct" and "is correct" diverge most here.

Verification order: where an OBJECTIVE check exists (tests, typecheck, lint, a numeric answer), gate on it via `codex exec` + shell BEFORE spending an LLM verifier. A passing test outranks an LLM CONFIRM. For fuzzy deliverables with no automatic check, buy a stronger generator, not a weak-generator-plus-judge pipeline.

Escalation rule: every finder/verifier role emits `verdict`/`confidence`/`evidence` (approximate via prompt contract — Codex has no first-class typed `schema` param yet, so state the required shape in the prompt and treat a response missing any field as low confidence). Re-run once at the next rung up on confidence < 0.7, UNSURE, empty/malformed output, or contradiction between parallel roles. Escalation target must be ≥ generator's rung. Escalation has a ceiling too: >1-in-4 downgraded stages escalating means the routing was miscalibrated — stop and re-profile, don't silently run everything on Sol.

Panels: 2–3 voters with distinct lenses (correctness / security / reproduces-it), never N identical-role repeats. Unanimous → accept; split → one apex adjudicator; never majority-vote or average.

Budget pressure: cut `max_threads` / batch more files per role first; floors are the last thing to fall. Treat the apex rung as a read-only reserve (usually synthesis only). If budget can't cover the apex/Sol terminal stages, say so and propose the cut — never silently ship a downgraded final answer.

## 5. Routing lint (pre-flight, fix before dispatch)
1. Every role/profile has an explicit `model` + `model_reasoning_effort`, or the omission is a deliberate apex spend (inherits top-level `model`). More than 2 omissions = under-routing.
2. No wide/parallel role runs on Sol@high or inherits the apex profile; bulk roles sit at Luna/Terra regardless of the rest of the routing.
3. Verifiers, judges, synthesis are at their floors even under budget pressure; `max_depth` prevents two roles editing the same files concurrently.
4. Every downgraded trusted-adjacent stage has a stated escalation trigger, and an objective check (test/lint/typecheck via shell) gates before any LLM verifier where one exists.
5. Every role's prompt states an objective + expected output shape + scope boundary vs sibling roles — Codex has no schema enforcement, so the prompt IS the contract.
6. A stage is justified only if it accesses information the prior stage couldn't (new tool call, test run, independent read). A stage that reformats an upstream conclusion is overhead — collapse it into one higher-effort call.
7. Profile/role names embed the tier (e.g. `verify-sol-high`), so a session log shows the routing without opening config.toml.

## 6. Scope
This table binds any one-off `codex exec` dispatch too, not just multi-agent orchestrator runs: a lone bulk-reading call is still a Luna/Terra job; a lone terminal judgment still earns Sol@high or a deliberate apex inheritance. Absence of `[agents]`/`orchestrator` config does not relax the discipline — apply it by hand via `--profile` and `--config model_reasoning_effort=`.
# --- overcodex ultracode (end) ---
