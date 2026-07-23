# Overcodex repository instructions

This repository packages the Overcodex UltraCode orchestration layer for Codex and OpenClaw.

Read `AGENT-SETUP.md` for the repository's compact Codex/OpenClaw activation contract. Follow it when the user asks to install or activate the system; do not require the user to paste a separate long bootstrap prompt.

## Activation

When the user asks to activate, install, or use Overcodex/UltraCode:

1. Read `codex/AGENTS-ULTRACODE.md` and follow it as the repository's full coordination policy.
2. For Codex, inspect `$CODEX_HOME/AGENTS.md` for the `overcodex ultracode` marker. If it is absent, explain that global activation is pending and run `./install.sh` only as part of the requested activation.
3. For OpenClaw, run `./install-openclaw.sh` when requested, then verify `openclaw skills list` and `openclaw agents list`. Do not edit existing OpenClaw agent configuration without showing the proposed change first.
4. After activation, report the exact instruction file, role registrations, model/effort assignments, and verification performed.

## Default orchestration

For complex work with two or more independent streams, use the UltraCode planning gate and delegate by default. Select the lowest-cost Codex role that satisfies the task's verification floor, use explicit ownership boundaries, run objective checks before review, and escalate uncertainty or contradictory evidence. If the task is small or inherently sequential, keep it in the parent and state why.

Do not describe `ultra` as a Codex reasoning effort. Use the effort names supported by the selected model: GPT-5.5 uses `none`, `low`, `medium`, `high`, and `xhigh`; GPT-5.6 Sol/Terra/Luna additionally support `max`.

This file is a repository-local instruction layer. The global installer remains the mechanism for making the same policy apply across all Codex projects.
