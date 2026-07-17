# overcodex hook wiring — TOML fragment. install.sh substitutes @HOOKS_DIR@
# with the resolved absolute $CODEX_HOME/hooks and appends the result between
# marker comments at the END of config.toml (a [hooks] table cannot be
# prepended: it would capture every top-level key that follows it).
#
# Shape provenance (codex-cli 0.144.5, reconstructed from the binary's
# embedded types — no public docs exist for this surface as of this writing):
#   HookEventsToml: PascalCase event keys (PreToolUse, PermissionRequest,
#   PostToolUse, PreCompact, PostCompact, SessionStart, UserPromptSubmit,
#   SubagentStart, SubagentStop, Stop); each event holds an ARRAY of matcher
#   groups (ConfiguredHookMatcherGroup: matcher?, hooks[]).
#   Handlers: internally tagged HookHandlerConfig::Command with fields
#   type / command / commandWindows / timeout / async / statusMessage
#   (`timeout`, NOT the app-server wire name `timeoutSec`).
#   `matcher` semantics for non-tool events are unconfirmed — omitted here;
#   each script filters on its own payload fields instead.
# FLAG FOR LIVE VALIDATION: if codex warns on config load, check its
# configWarning output first — the shape above is inferred, not documented.

[[hooks.SessionStart]]
[[hooks.SessionStart.hooks]]
type = "command"
command = "bash @HOOKS_DIR@/overcodex-handoff-inject.sh"
timeout = 10

[[hooks.UserPromptSubmit]]
[[hooks.UserPromptSubmit.hooks]]
type = "command"
command = "bash @HOOKS_DIR@/overcodex-ctx-watch.sh"
timeout = 5

[[hooks.Stop]]
[[hooks.Stop.hooks]]
type = "command"
command = "bash @HOOKS_DIR@/overcodex-notify.sh"
timeout = 5

[[hooks.PreCompact]]
[[hooks.PreCompact.hooks]]
type = "command"
command = "bash @HOOKS_DIR@/overcodex-precompact-offer.sh"
timeout = 5
