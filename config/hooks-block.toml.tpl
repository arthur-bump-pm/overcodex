# overcodex hook wiring (Codex CLI 0.158+; app-server 0.162). The installer
# substitutes @HOOKS_DIR@ on non-comment lines only (never in comments) and
# keeps this block at the END of config.toml, between marker comments.
#
# Shape (verified against `codex app-server` hooks/list on 0.158):
#   PascalCase event keys (PreToolUse, PermissionRequest, PostToolUse,
#   PreCompact, PostCompact, SessionStart, SessionEnd, UserPromptSubmit,
#   SubagentStart, SubagentStop, Stop, Interrupt); each holds an ARRAY of
#   matcher groups (matcher?, hooks[]); handlers are `type = "command"` with
#   command / timeout / async / statusMessage / additionalContextLimit.
#   `additionalContextLimit` is camelCase and set per HANDLER; unset, Codex
#   spills additionalContext above ~2,500 tokens (middle-truncates the
#   handoff package). SessionStart `matcher` filters on its `source` field.
#
# TRUST: Codex runs a hook only after it is trusted per config path. The
# trust key is <config path>:<event>:<group>:<handler> and the path is not
# canonicalized, so every ~/.codex-accounts/<name> must be trusted on its own
# (TUI: "Hooks need review" -> "Trust all and continue", or /hooks). Changing
# any handler below changes its hash and forces a fresh review.
# Codex records trust in hooks.state tables keyed by that string; they are Codex's,
# not overcodex's — the installer and uninstaller move them out of this block
# instead of deleting them.

[[hooks.SessionStart]]
matcher = "startup"
[[hooks.SessionStart.hooks]]
type = "command"
command = "bash '@HOOKS_DIR@/overcodex-handoff-inject.sh'"
timeout = 10
additionalContextLimit = 8000

[[hooks.UserPromptSubmit]]
[[hooks.UserPromptSubmit.hooks]]
type = "command"
command = "bash '@HOOKS_DIR@/overcodex-ctx-watch.sh'"
timeout = 5

[[hooks.Stop]]
[[hooks.Stop.hooks]]
type = "command"
command = "bash '@HOOKS_DIR@/overcodex-notify.sh'"
timeout = 5

[[hooks.PreCompact]]
[[hooks.PreCompact.hooks]]
type = "command"
command = "bash '@HOOKS_DIR@/overcodex-precompact-offer.sh'"
timeout = 5
