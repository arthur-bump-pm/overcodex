# Codex Adapter

Install the Codex kit with:

```bash
pipx install overcodex
overcodex install
```

The installer adds the routing policy to `$CODEX_HOME/AGENTS.md`, installs four role definitions under `$CODEX_HOME/agents/`, and registers them in `config.toml`. The portable skill itself is available from a packaged install with `overcodex skill-path`.

For delegation, use the exact registered Codex `agent_type` and `fork_turns = "none"`; a task name does not route a model. Restart Codex after installation, then review and trust the hooks with `/hooks`. GPT-5.5 Codex uses `none`, `low`, `medium`, `high`, or `xhigh`; GPT-5.6 Sol/Terra/Luna additionally support `max`. Keep `xhigh` for cross-model compatibility and request `max` only when the selected model is GPT-5.6 and the task is quality-critical. Never use Claude Code effort names or `ultra` in Codex configuration.

Run the repository smoke test before changing live configuration:

```bash
./tests/smoke.sh
```
