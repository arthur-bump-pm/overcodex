#!/usr/bin/env python3
"""Tiny JSON-RPC driver for `codex app-server` (stdio) used by test_codex_live.sh.
Never points at a real home: the caller passes a throwaway HOME / CODEX_HOME and a
config whose model provider is unreachable, so turns fire hooks but reach no model.
usage: codex_rpc.py <home> <codex_home|-> <cwd> <cmd>...
  cmd: skills | hooks | thread | turn:<text> | write:<keyPath>=<json>
  ("-" for codex_home starts app-server with CODEX_HOME unset)."""
import json, os, subprocess, sys, time, threading, queue

BIN = os.environ.get("CODEX_BIN") or "codex"
home, chome, cwd = sys.argv[1:4]
cmds = sys.argv[4:]
env = dict(os.environ, HOME=home)
if chome != "-":
    env["CODEX_HOME"] = chome
else:
    env.pop("CODEX_HOME", None)
p = subprocess.Popen([BIN, "app-server"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                     stderr=open(os.path.join(home, "app-server.stderr"), "a"), env=env, cwd=cwd, text=True)
q = queue.Queue()
def reader():
    for line in p.stdout:
        try:
            q.put(json.loads(line))
        except Exception:
            q.put({"raw": line})
threading.Thread(target=reader, daemon=True).start()
nid = [0]
def send(method, params=None, notify=False):
    msg = {"method": method}
    if params is not None:
        msg["params"] = params
    if not notify:
        nid[0] += 1
        msg["id"] = nid[0]
    p.stdin.write(json.dumps(msg) + "\n"); p.stdin.flush()
    return msg.get("id")
def wait(rid, timeout=30, collect=None):
    end = time.time() + timeout
    while time.time() < end:
        try:
            m = q.get(timeout=0.5)
        except queue.Empty:
            continue
        if m.get("id") == rid and ("result" in m or "error" in m):
            return m
        if collect is not None:
            collect.append(m)
        # auto-decline server requests (approvals)
        if "method" in m and "id" in m:
            p.stdin.write(json.dumps({"id": m["id"], "result": {"decision": "decline"}}) + "\n"); p.stdin.flush()
    return {"timeout": rid}
def drain(seconds, collect):
    end = time.time() + seconds
    while time.time() < end:
        try:
            collect.append(q.get(timeout=0.5))
        except queue.Empty:
            pass

r = wait(send("initialize", {"clientInfo": {"name": "overcodex-test", "version": "0"}}))
send("initialized", notify=True)
thread_id = None
out = {}
for c in cmds:
    if c == "skills":
        out["skills"] = wait(send("skills/list", {"cwds": [cwd], "forceReload": True}))
    elif c == "hooks":
        out["hooks"] = wait(send("hooks/list", {"cwds": [cwd]}))
    elif c == "thread":
        notes = []
        r = wait(send("thread/start", {"cwd": cwd}), collect=notes)
        drain(4, notes)
        out["thread"] = r
        out["thread_notes"] = notes
        try:
            thread_id = r["result"]["thread"]["id"]
        except Exception:
            pass
    elif c.startswith("write:"):
        kp, val = c[6:].split("=", 1)
        out.setdefault("writes", []).append(wait(send("config/value/write", {"keyPath": kp, "value": json.loads(val), "mergeStrategy": "upsert"})))
    elif c.startswith("turn:"):
        notes = []
        r = wait(send("turn/start", {"threadId": thread_id, "input": [{"type": "text", "text": c[5:]}]}), collect=notes)
        drain(float(os.environ.get("RPC_TURN_WAIT", "5")), notes)
        out["turn"] = r
        out["turn_notes"] = notes
print(json.dumps(out))
p.stdin.close()
try:
    p.terminate(); p.wait(timeout=5)
except Exception:
    p.kill()
