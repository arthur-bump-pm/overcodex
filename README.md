# overcodex

[![PyPI version](https://img.shields.io/pypi/v/overcodex)](https://pypi.org/project/overcodex/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
![Platform: macOS](https://img.shields.io/badge/platform-macOS-lightgrey)

**Codex CLI, overclocked.** Cold-switch between Codex accounts, hand off to a fresh session with `/prompts:handoff` before context fills up, watch usage on the statusline, and route multi-agent work with an AGENTS.md policy:

```text
codex-swap work         # register/list accounts, then switch — restart required
/prompts:handoff        # package this session's state, resume fresh next launch

ctx [████░░░░░░] 42% remaining | 5h limit 71% | weekly limit 18%
└ get_context_remaining      └ native Codex statusline items
```

## Install

```bash
pipx install overcodex && overcodex install
```

> **Fresh machine?** If you get `command not found: overcodex`, pipx's bin folder isn't on your PATH yet — run `pipx ensurepath && source ~/.zshrc`, then `overcodex install`. (Use `source`, not `exec zsh`: replacing the shell swallows any commands you pasted after it.)

Then register your accounts (once, per account):

```bash
codex-swap add work        # creates an isolated account home + links shared config
codex-swap add personal    # then log in to each: CODEX_HOME=~/.codex-accounts/work codex login
codex-swap work             # cold switch: writes auth.json, then restart codex
```

Start a **new** Codex CLI session (hooks and AGENTS.md load at session start) and confirm the statusline shows the context/limit meters. Run `/prompts:handoff` inside Codex to hand off before you hit auto-compact.

<details>
<summary>Other install methods, requirements, upgrading</summary>

```bash
# uv
uv tool install overcodex && overcodex install

# from source
git clone https://github.com/arthur-bump-pm/overcodex && cd overcodex && ./install.sh
```

Or paste this into any Codex CLI session and let it install itself:

> Install overcodex (https://github.com/arthur-bump-pm/overcodex) on this machine, fix anything its preflight complains about, and tell me what post-install steps I need to do myself.

**Requirements:** macOS, zsh, `pipx` or `uv`, a Codex CLI install (`codex --version`). No keychain daemon and no background credential engine — cold switching is just isolated `$CODEX_HOME` directories, one per account.

**Upgrade:** `pipx upgrade overcodex && overcodex install`

**Uninstall:** `overcodex uninstall` — removes exactly what install added (backed up); each account's isolated `$CODEX_HOME` copy survives untouched.

The installer is idempotent and conservative: timestamped backups of everything it touches, additive edits to `config.toml` (never overwrites an existing `hooks` or `status_line` key), re-running is a no-op.

</details>

## What you get

### `codex-swap` — cold account switching
Each account gets its own isolated `CODEX_HOME` (a separate `auth.json`, never a copied/overwritten one — refresh tokens can be single-use across copies, so isolation is the only safe design). `codex-swap <account>` points the shell at that directory and tells you to restart. **This is a cold switch**: any Codex session already running keeps its old credentials until you quit and relaunch it. There is no hot mid-session swap here — if you need that, it's overclaude's `/swap` for Claude Code, not this.

### `/prompts:handoff` — escape context bloat, keep the thread

```mermaid
flowchart LR
    A[Context fills up] --> B[get_context_remaining / statusline flags it]
    B --> C[You run /prompts:handoff]
    C --> D[Codex packages goals, state, next steps]
    D --> E[Session ends]
    E --> F[SessionStart hook injects the package on next launch]
    F --> G[Fresh session, ctx near zero]
    G --> A
```

You lose the token bloat, not the thread. Combine with a `codex-swap` restart when you're also switching accounts.

### Statusline
Codex's native statusline already covers the meters — run `/statusline` inside Codex and enable the context, five-hour, and weekly items (or set `tui.status_line` in config.toml yourself). The kit deliberately ships no statusline config: the native picker is authoritative, and the exact config-key vocabulary is undocumented — nothing to clobber, nothing to break.

### AGENTS.md routing policy
A policy block appended to `$CODEX_HOME/AGENTS.md` (loaded globally, then project `AGENTS.md` files concatenate root-down): bulk work rides cheap models/effort, verification rides a stronger reasoning tier, only final judgment spends the top tier. Routing table, hard floors, escalation rules included.

### Hooks + prompts
`PreToolUse`/`PostToolUse`/`SessionStart`/`Stop` hooks wired via an inline `[hooks]` table in `config.toml`, plus `/prompts:*` markdown prompts under `$CODEX_HOME/prompts/` (YAML frontmatter, `$1`-`$9` placeholders) for the handoff flow and other repeatable operations.

## Cheat sheet

| Command | Effect |
|---|---|
| `codex-swap add <name>` | Create an isolated home under `~/.codex-accounts/<name>` and link shared config; log in to it with the printed `CODEX_HOME=... codex login` |
| `codex-swap <name>` | Point `$CODEX_HOME` at that account's isolated store — **restart codex after** |
| `codex-swap list` | Show registered accounts and which is active |
| `/prompts:handoff` | Package this session's state; auto-injected on next launch |
| `overcodex install` | (Re)install/refresh the kit — idempotent |
| `overcodex uninstall` | Remove exactly what install added |
| `overcodex path` | Print the bundled payload directory |

Or skip memorizing and **paste a prompt**:

| Paste into Codex CLI | Runs |
|---|---|
| "Hand off — context is filling up" | `/prompts:handoff` |
| "Switch me to my work account" | walks you through `codex-swap work` + the restart |
| "Install overcodex on this machine" | the whole install flow (works before the kit exists) |
| "Upgrade overcodex and refresh the hooks" | `pipx upgrade overcodex && overcodex install` |

## How it fits together

```mermaid
flowchart TD
    AH[AGENTS.md routing policy] --> HK[config.toml hooks table: SessionStart/UserPromptSubmit/Stop]
    HK --> PR[/prompts:handoff and friends]
    PR --> CS[codex-swap: isolated CODEX_HOME per account]
    CS --> RS[Cold restart adopts the new account]
    SL[Statusline: get_context_remaining + native limit items] --> HK
```

<details>
<summary>Caveats worth knowing</summary>

- **Cold switch only.** `codex-swap` changes which `$CODEX_HOME` the shell points at; a session already running keeps reading its original `auth.json` until you quit and relaunch. There is no live/hot swap in this kit.
- **Refresh-token isolation is the whole point.** Codex's refresh tokens can be single-use across copies of the same credential (open upstream bug reports) — so accounts are never file-swapped or symlinked into a shared `auth.json`. Each account's `CODEX_HOME` refreshes its own token in place, permanently separate from the others.
- **Hooks run arbitrary shell on your events.** Review `hooks/*.sh` before installing on a machine you don't fully trust, same as any hook-based tool.
- **Sessions are sqlite, not JSONL.** `experimental_thread_store` keeps history in `sqlite_home` (e.g. `logs_2.sqlite`) — `codex resume --last` / `codex resume <id>` read from there, not from plain log files.
- Enterprise configs can set `allow_managed_hooks_only`, which blocks this kit's hooks from installing — check that first if hooks don't seem to load.

</details>

<details>
<summary>Components (file → destination)</summary>

| File | Installs to | Role |
|---|---|---|
| `bin/codex-swap` | `~/.local/bin/` | Cold account switcher: register, list, point `$CODEX_HOME` at an account |
| `hooks/*.sh` | `$CODEX_HOME/hooks/` | SessionStart / UserPromptSubmit / Stop handlers |
| `config/hooks-block.toml.tpl` | inline `[hooks]` table appended to `config.toml` (markers) | Hook wiring — only if no `hooks` key exists |
| `codex/AGENTS-ULTRACODE.md` | appended to `$CODEX_HOME/AGENTS.md` (markers) | Model/effort routing policy |
| `prompts/*.md` | `$CODEX_HOME/prompts/` | `/prompts:*` custom prompts (handoff, etc.) |

| `shell/zshrc-snippet.sh` | `~/.zshrc` (markers) | `codex-swap` PATH/alias wiring |

</details>

<details>
<summary>Maintainer workflow</summary>

```bash
./sync.sh            # live setup -> repo: scrub-gated diff, commit, push
./sync.sh --release  # + version bump + GitHub release -> PyPI (trusted publishing)
./sync.sh --dry-run  # preview either
```

A plain `git push` updates git installs only — **PyPI users get changes only via releases**. The scrub gate aborts any commit whose diff contains usernames, emails, or `/Users/…` paths. See `CLAUDE.md` for the full protocol.

</details>

## Credits

overcodex is the Codex CLI sibling of **[overclaude](https://github.com/arthur-bump-pm/overclaude)** (same author, same packaging shape) — overclaude does hot account swapping for Claude Code; Codex CLI's credential model only allows a cold switch, so this kit is built around that constraint instead of hiding it.

### Hot-swap and the codext fork

True hot account switching exists on Codex only via [codext](https://github.com/Loongphy/codext) — an Apache-2.0 hard fork of the Codex CLI that polls `auth.json` and reloads it in-process at idle turn boundaries (verified in its source: `tui/src/auth_watch.rs`, `login/src/auth/manager.rs`). It works, with two trade-offs `codex-swap` deliberately doesn't make: it requires running a single-maintainer fork that rebases onto each upstream release, and it still doesn't solve cross-copy refresh-token rotation — switching back to an account whose token rotated elsewhere can force a re-login (codext issue #1 confirms). `codex-swap` stays cold-but-bulletproof by isolating accounts in separate `CODEX_HOME`s where tokens never move. If OpenAI ships auth live-reload upstream, `codex-swap` grows hot for free.

## License

MIT — see [LICENSE](LICENSE).
