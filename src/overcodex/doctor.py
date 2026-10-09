"""overcodex doctor — per-account hook trust and skill check via `codex app-server`.

For the primary home (~/.codex) and every codex-swap account under
~/.codex-accounts, starts `codex app-server` (stdio JSON-RPC; no model request
is ever made), asks `hooks/list` and `skills/list`, and reports:
  * each overcodex hook's trustStatus (trusted / untrusted / modified / managed)
    — Codex keys trust by config path, so every account is reviewed separately;
  * whether the overcodex skills ($handoff, ...) are visible in that account.
"""

import json
import os
import queue
import re
import shutil
import subprocess
import threading
import time

SKILLS = ("handoff", "handoff-status", "handoff-cancel", "handoff-claude", "ultracode")
HOOK_EVENTS = {
    "overcodex-handoff-inject.sh": "sessionStart",
    "overcodex-ctx-watch.sh": "userPromptSubmit",
    "overcodex-notify.sh": "stop",
    "overcodex-precompact-offer.sh": "preCompact",
}


def homes():
    home = os.path.expanduser("~")
    res = [("primary", os.path.join(home, ".codex"))]
    root = os.path.join(home, ".codex-accounts")
    if os.path.isdir(root):
        for n in sorted(os.listdir(root)):
            if re.match(r"^[A-Za-z0-9_-]+$", n) and n != "primary" and os.path.isdir(os.path.join(root, n)):
                res.append((n, os.path.join(root, n)))
    return res


class AppServer:
    def __init__(self, codex, codex_home, cwd, timeout=30):
        env = dict(os.environ, CODEX_HOME=codex_home)
        self.timeout = timeout
        self.p = subprocess.Popen([codex, "app-server"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, env=env, cwd=cwd, text=True)
        self.q = queue.Queue()
        self.n = 0
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.p.stdout:
            try:
                self.q.put(json.loads(line))
            except ValueError:
                pass

    def call(self, method, params=None):
        self.n += 1
        msg = {"id": self.n, "method": method}
        if params is not None:
            msg["params"] = params
        self.p.stdin.write(json.dumps(msg) + "\n")
        self.p.stdin.flush()
        end = time.time() + self.timeout
        while time.time() < end:
            try:
                m = self.q.get(timeout=0.5)
            except queue.Empty:
                if self.p.poll() is not None:
                    break
                continue
            if m.get("id") == self.n and ("result" in m or "error" in m):
                if "error" in m:
                    raise RuntimeError("%s: %s" % (method, m["error"].get("message", m["error"])))
                return m["result"]
        raise RuntimeError("%s: no answer from codex app-server" % method)

    def notify(self, method):
        self.p.stdin.write(json.dumps({"method": method}) + "\n")
        self.p.stdin.flush()

    def close(self):
        try:
            self.p.stdin.close()
            self.p.terminate()
            self.p.wait(timeout=5)
        except Exception:
            self.p.kill()


def check_home(codex, name, chome, cwd):
    lines, ok = [], True
    srv = AppServer(codex, chome, cwd)
    try:
        srv.call("initialize", {"clientInfo": {"name": "overcodex-doctor", "version": "1"}})
        srv.notify("initialized")
        hl = srv.call("hooks/list", {"cwds": [cwd]})
        sl = srv.call("skills/list", {"cwds": [cwd]})
    finally:
        srv.close()
    entry = (hl.get("data") or [{}])[0]
    found = {}
    for h in entry.get("hooks", []):
        cmd = h.get("command", "") or ""
        for script, ev in HOOK_EVENTS.items():
            if script in cmd and h.get("eventName") == ev:
                found[script] = h
    for script, ev in HOOK_EVENTS.items():
        h = found.get(script)
        if h is None:
            lines.append("  [!] %-17s %s not registered" % (ev, script))
            ok = False
            continue
        st = h.get("trustStatus")
        mark = "ok" if st in ("trusted", "managed") and h.get("enabled", True) else "!"
        ok = ok and mark == "ok"
        lines.append("  [%s] %-17s %-10s %s" % (mark, ev, st, h.get("key", "")))
    for w in entry.get("warnings", []) + [e.get("message", str(e)) for e in entry.get("errors", [])]:
        lines.append("  [!] codex: %s" % w)
    have = set()
    for e in sl.get("data", []):
        for s in e.get("skills", []):
            if s.get("enabled", True):
                have.add(s.get("name"))
    missing = [s for s in SKILLS if s not in have]
    if missing:
        ok = False
        lines.append("  [!] skills missing: %s" % ", ".join("$" + s for s in missing))
    else:
        lines.append("  [ok] skills: %s" % " ".join("$" + s for s in SKILLS))
    return ok, lines


def main(argv=None):
    codex = os.environ.get("OVERCODEX_CODEX_BIN") or shutil.which("codex")
    if not codex:
        print("overcodex doctor: codex CLI not found on PATH")
        return 1
    cwd = os.getcwd()
    all_ok = True
    for name, chome in homes():
        if not os.path.isdir(chome):
            continue
        print("%s  (CODEX_HOME=%s)" % (name, chome))
        try:
            ok, lines = check_home(codex, name, chome, cwd)
        except Exception as ex:  # noqa: BLE001 — report, keep checking other homes
            ok, lines = False, ["  [!] %s" % ex]
        all_ok = all_ok and ok
        print("\n".join(lines))
    if not all_ok:
        print()
        print("Untrusted/modified hooks do not run. Start codex in that account (codex-swap use <name>,")
        print("then codex) and choose \"Trust all and continue\" at \"Hooks need review\" (or use /hooks).")
        print("Trust is per config path, so each account needs it once; changing a hook re-asks.")
    return 0 if all_ok else 1
