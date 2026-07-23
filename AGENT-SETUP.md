# Agent Setup

This file is the short operational contract for agents working from this repository.

Canonical repository: `https://github.com/arthur-bump-pm/overcodex`

## Codex

When the user requests Codex activation:

1. Inspect the checkout and preserve unrelated changes.
2. Run `pipx install git+https://github.com/arthur-bump-pm/overcodex.git` when `overcodex` is missing, then run `overcodex install`.
3. Verify the `overcodex ultracode` marker in `${CODEX_HOME:-$HOME/.codex}/AGENTS.md`.
4. Verify the four registered roles and their Codex efforts: Luna/low, Terra/medium, Sol/high, Sol/xhigh.
5. Preserve unrelated `AGENTS.md` and `config.toml` content; do not touch credentials.
6. Run `./tests/smoke.sh` and report whether Codex must restart.

## OpenClaw

When the user requests OpenClaw activation:

1. If this checkout is unavailable, clone `https://github.com/arthur-bump-pm/overcodex`, then run `./install-openclaw.sh` from it.
2. Verify with `openclaw skills list` and `openclaw agents list`.
3. Install the portable `skill/overcodex-ultracode` skill if it is not listed.
4. Propose changes to the workspace `AGENTS.md` and OpenClaw agent configuration before applying them. Preserve unrelated content and credentials.
5. Configure role agents using OpenClaw-native IDs and `sessions_spawn`; do not copy Codex-only `agent_type` or `fork_turns` fields.
6. Use isolated execution, depth 1, and bounded concurrency where supported. Run a harmless scout verification task.

After either activation, report changed files, installed paths, role/model/effort settings, checks, and remaining manual steps. For complex work, follow `codex/AGENTS-ULTRACODE.md` and delegate by default when independent workstreams exist.
