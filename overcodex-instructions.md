# Overcodex Activation Instructions

Repository: https://github.com/arthur-bump-pm/overcodex

## Codex Prompt

```text
Activate Overcodex UltraCode for Codex from:

https://github.com/arthur-bump-pm/overcodex

Clone it if needed. Follow the repository's AGENTS.md and AGENT-SETUP.md instructions.

Install or refresh Overcodex with:

pipx install git+https://github.com/arthur-bump-pm/overcodex.git
overcodex install

Verify:

1. ~/.codex/AGENTS.md contains the overcodex ultracode marker.
2. These agents are registered:
   - scout-luna-low
   - worker-terra-medium
   - reviewer-sol-high
   - judge-sol-xhigh
3. Their Codex model/effort settings are:
   - scout: gpt-5.6-luna, low
   - worker: gpt-5.6-terra, medium
   - reviewer: gpt-5.6-sol, high
   - judge: gpt-5.6-sol, xhigh
4. No invalid "ultra" model_reasoning_effort value is used.
5. The repository root AGENTS.md is present and instructs complex tasks to use UltraCode delegation.
6. ./tests/smoke.sh passes.

Preserve unrelated AGENTS.md, config.toml, and credentials. Do not overwrite unrelated configuration. Report all changed files, registered agents, model/effort settings, test results, and whether Codex must restart.
```

## OpenClaw Prompt

```text
Activate Overcodex UltraCode for OpenClaw from:

https://github.com/arthur-bump-pm/overcodex

Clone it if needed. Follow the repository's AGENTS.md and AGENT-SETUP.md instructions.

Run:

./install-openclaw.sh

Verify:

1. openclaw skills list shows overcodex-ultracode.
2. openclaw agents list works.
3. The portable skill contains:
   - SKILL.md
   - Codex adapter
   - OpenClaw adapter
   - role prompts
4. The workspace AGENTS.md contains the UltraCode instruction layer.
5. OpenClaw role agents are configured using OpenClaw-native agent IDs and sessions_spawn.
6. Do not copy Codex-only fields such as agent_type or fork_turns.
7. Use isolated execution, maximum spawn depth 1, and bounded concurrency where supported.
8. Run a harmless scout verification task.

Show me the proposed AGENTS.md and OpenClaw configuration diff before applying changes. Preserve unrelated instructions, credentials, and agent settings. Report installed paths, changed files, configured roles, verification results, and remaining manual steps.
```
