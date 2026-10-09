# Codex Adapter

Install the Codex kit with:

```bash
pipx install overcodex
overcodex install
```

The installer adds the routing policy to `$CODEX_HOME/AGENTS.md`, installs four role definitions under `$CODEX_HOME/agents/`, and registers them in `config.toml`. The portable skill itself is available from a packaged install with `overcodex skill-path`.

For delegation, use the exact registered Codex `agent_type` and `fork_turns = "none"`; a task name does not route a model. Restart Codex after installation, then trust the hooks ("Hooks need review" -> "Trust all and continue", or `/hooks`) — once per codex-swap account, because Codex keys hook trust by config path. Every Codex model accepts `low`, `medium`, `high`, and `xhigh`; `max` is also available on GPT-6 Astra/Sol/Luna and GPT-5.6 Sol/Terra/Luna; `ultra` only on `gpt-6-astra`, `gpt-6-sol`, `gpt-5.6-sol`, and `gpt-5.6-terra`. Keep `xhigh` for cross-model compatibility and request `max`/`ultra` only on a model that lists it, for quality-critical work. Never use Claude Code effort names in Codex configuration.

Run the repository smoke test before changing live configuration:

```bash
./tests/run.sh
```
