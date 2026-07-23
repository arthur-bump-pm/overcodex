# overcodex custom-agent registration. install.sh substitutes @AGENTS_DIR@.
# `task_name` only labels a child; routing requires agent_type plus a non-full
# history fork. AGENTS-ULTRACODE.md carries that dispatch contract.
[agents]
max_threads = 4
max_depth = 1

[agents.scout-luna-low]
description = "Fast read-only scout for discovery, inventory, and extraction."
config_file = "@AGENTS_DIR@/scout-luna-low.toml"

[agents.worker-terra-medium]
description = "Bounded implementation worker with explicit file ownership."
config_file = "@AGENTS_DIR@/worker-terra-medium.toml"

[agents.reviewer-sol-high]
description = "Independent correctness, security, regression, and test reviewer."
config_file = "@AGENTS_DIR@/reviewer-sol-high.toml"

[agents.judge-sol-xhigh]
description = "Adjudicator for contradictory or subtle high-risk verdicts."
config_file = "@AGENTS_DIR@/judge-sol-xhigh.toml"
