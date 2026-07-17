# overcodex — maintainer protocol

This repo is the **published** overcodex kit: GitHub (arthur-bump-pm/overcodex) + PyPI (`overcodex`). It is the Codex CLI sibling of [overclaude](https://github.com/arthur-bump-pm/overclaude) — same packaging shape, same scrub gate, ported to `$CODEX_HOME` (default `~/.codex`) instead of `~/.claude`. Changes here reach other machines only through releases, so:

## After ANY change to the kit

1. **Changes made to the live setup** (`$CODEX_HOME/hooks/...`, `$CODEX_HOME/prompts/...`, `$CODEX_HOME/AGENTS.md`'s overcodex block, `~/.local/bin/codex-swap`, the `~/.zshrc` block): run `./sync.sh` to pull them into the repo. Never hand-copy — sync.sh has the personal-data scrub gate.
2. **Ship it**: `./sync.sh --release` — syncs, patch-bumps `version` in pyproject.toml, commits, pushes, and cuts a GitHub release. The `publish.yml` workflow (PyPI trusted publishing) takes it from there. Use `--dry-run` first when unsure.
3. **`git push` alone does NOT update PyPI.** Only a release does. If a change matters to other machines, it needs a release.

## Rules

- Keep repo copies and live files **byte-identical** — that's what keeps sync.sh diffs clean. If you edit a kit file in the repo directly, also run `./install.sh` (or `overcodex install`) to propagate it to the live setup.
- Never weaken the scrub gate in sync.sh. No usernames, emails, or `/Users/...` paths in any committed file — use `$HOME`, `$CODEX_HOME`, generic aliases (`work`/`personal`), and `myproject` in examples.
- `sync.sh` only ever pulls files the repo **already tracks** under `hooks/` and `prompts/` — a brand-new hook or prompt file must be added to the repo directly (or via a payload change), never invented by the sync loop.
- `config.toml` itself is never synced back — it can carry secrets (`mcp_servers`, `cli_auth_credentials_store`, model auth). Only the generated fragments (the marker-wrapped `[hooks]` block from `config/hooks-block.toml.tpl` and the `AGENTS.md` block) are kit-owned; the rest of `config.toml` stays the user's.
- For a minor/major version bump (new feature / breaking change), edit `version` in pyproject.toml manually before `./sync.sh --release` (it only auto-bumps the patch level).
- After releasing, remind the user that other machines update via `pipx upgrade overcodex && overcodex install`.
- Remember the core caveat this whole kit is built around: **codex-swap is a cold switch** (running sessions read credentials at startup; switching accounts requires a restart) — never describe or document it as hot-swap. That's overclaude's `/swap`, not this.
