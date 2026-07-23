"""overcodex CLI — runs the bundled kit installer/uninstaller.

The package wheel carries the same payload a git clone has (bin/, hooks/,
config/, codex/, prompts/, agents/, shell/, and the install/uninstall scripts). This
CLI just locates that payload and runs the battle-tested bash scripts
against it.
"""

import argparse
import os
import subprocess
import sys
from importlib.metadata import version as pkg_version
from importlib.resources import files


def _payload_dir():
    p = files("overcodex").joinpath("payload")
    path = str(p)
    if not os.path.isdir(path) or not os.path.isfile(os.path.join(path, "install.sh")):
        sys.exit("overcodex: bundled payload is missing — broken install; reinstall the package")
    return path


def _run_script(name):
    return subprocess.call(["bash", os.path.join(_payload_dir(), name)])


def main():
    ap = argparse.ArgumentParser(
        prog="overcodex",
        description="Codex CLI, overclocked — codex-swap, hooks, statusline, AGENTS.md routing.",
    )
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("install", help="install/refresh the kit into $CODEX_HOME (idempotent, backs everything up)")
    sub.add_parser("uninstall", help="remove exactly what install added")
    sub.add_parser("path", help="print the bundled payload directory")
    sub.add_parser("skill-path", help="print the portable OpenClaw/Codex skill directory")
    sub.add_parser("version", help="print the overcodex version")
    args = ap.parse_args()

    if args.cmd == "install":
        sys.exit(_run_script("install.sh"))
    if args.cmd == "uninstall":
        sys.exit(_run_script("uninstall.sh"))
    if args.cmd == "path":
        print(_payload_dir())
        return
    if args.cmd == "skill-path":
        path = os.path.join(_payload_dir(), "skill", "overcodex-ultracode")
        if not os.path.isfile(os.path.join(path, "SKILL.md")):
            sys.exit("overcodex: bundled portable skill is missing — reinstall the package")
        print(path)
        return
    if args.cmd == "version":
        print(pkg_version("overcodex"))


if __name__ == "__main__":
    main()
