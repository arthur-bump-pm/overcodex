# OpenClaw Adapter

OpenClaw loads a skill directory containing `SKILL.md`. Install this package from a checkout or extracted wheel with:

```bash
openclaw skills install ./skill/overcodex-ultracode --global
openclaw skills list
```

For a one-message bootstrap, ask the OpenClaw agent to run the repository's `install-openclaw.sh`. It installs the Python package only when needed, installs the skill globally, and prints the remaining verification steps. The agent should show proposed changes before editing existing OpenClaw agent configuration.

The global destination is normally `~/.openclaw/skills`; workspace-local skills are also supported. Configure four OpenClaw agent IDs in the current `agents.list` schema, for example `ultracode-scout`, `ultracode-worker`, `ultracode-reviewer`, and `ultracode-judge`, each with its intended model and default thinking level. Restrict delegation with the agent allowlist and set a maximum spawn depth of 1 and concurrency of 4.

When dispatching, call `sessions_spawn` with the mapped `agentId`, `context: "isolated"`, a descriptive `taskName`, and the role prompt. Use `model` and `thinking` overrides only when the configured OpenClaw version permits them. Wait with `sessions_yield`; do not assume Codex's `agent_type` field exists in OpenClaw.

If separate role IDs are not configured, dispatch remains advisory: include the role prompt and requested model/thinking in the task, then disclose that the runtime could not enforce routing. Verify with `openclaw agents list` and a harmless scout task before relying on the workflow.
