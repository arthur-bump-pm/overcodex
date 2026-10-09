#!/usr/bin/env python3
"""overcodex_config.py — marker-block-aware editor for $CODEX_HOME/config.toml.

Used by install.sh and uninstall.sh. Never writes config.toml unless the result
parses (tomllib, or tomli on Python < 3.11) AND passes a semantic check: the new
document must equal the old one minus exactly what overcodex shipped (plus, on
install, exactly what it ships now). Anything else is refused and reported.

Why this exists: Codex's own config writer (toml_edit) inserts the tables it
creates (hook trust records `[hooks.state."..."]`, `[notice]`, `[features]`, ...)
INSIDE overcodex's marker blocks — just before the trailing end-marker comment.
A plain "delete everything between the markers" uninstall/refresh would delete
them. Here, every table or key inside a block that overcodex did not ship is
classified as foreign and moved out of the block (never deleted).

Commands (output: one `<kind>\t<message>` line per event; kinds are did, skip,
warn, info, retrust, ok, fail):
  apply   <config> <epoch> --hooks-tpl F --hooks-dir D --agents-tpl F --agents-dir D [--statusline F]
  strip   <config> <epoch>
  verify  <config> <hooks-dir>
  check   (exit 0 when a TOML parser is available)
"""
import json
import os
import re
import shutil
import sys

try:
    import tomllib  # Python >= 3.11
except ImportError:  # pragma: no cover - exercised on stock macOS python 3.9
    try:
        import tomli as tomllib  # type: ignore
    except ImportError:
        tomllib = None

MARKERS = {
    "hooks": ("# --- overcodex hooks (begin) ---", "# --- overcodex hooks (end) ---"),
    "agents": ("# --- overcodex agent roles (begin) ---", "# --- overcodex agent roles (end) ---"),
    "statusline": ("# --- overcodex statusline (begin) ---", "# --- overcodex statusline (end) ---"),
}
# Placed after the hooks block so Codex's writer positions the tables it adds
# (hook trust records, and new top-level tables when `hooks` is the last
# top-level key) BELOW overcodex's blocks instead of inside them.
SENTINEL_COMMENT = "# overcodex: Codex appends the settings it writes (hook trust, notices, features) below this line."
SENTINEL_HEADER = "[hooks.state]"

AGENT_ROLES = ("scout-luna-low", "worker-terra-medium", "reviewer-sol-high", "judge-sol-xhigh")
HOOK_SCRIPTS = (
    ("SessionStart", "overcodex-handoff-inject.sh"),
    ("UserPromptSubmit", "overcodex-ctx-watch.sh"),
    ("Stop", "overcodex-notify.sh"),
    ("PreCompact", "overcodex-precompact-offer.sh"),
)
SL_KEYS = ("status_line", "status_line_use_colors")
SCRIPT_EVENT = dict((script, event) for event, script in HOOK_SCRIPTS)

# Set per run (apply/strip): the hooks directories overcodex installs into.
# A hook handler is overcodex's only if its command is exactly what overcodex
# ships for that event: `bash '<dir>/<script>'` (0.3+) or `bash <dir>/<script>`
# (<= 0.2), with <dir> one of these. Anything else is the user's.
HOOK_DIRS = []
# Keys overcodex ships per [agents.<role>] table (set from the template).
ROLE_KEYS = ("description", "config_file")
# Newline style of the config being edited ("\n" or "\r\n").
NL = "\n"


def owned_hook_command(event, command):
    if not isinstance(command, str):
        return False
    for d in HOOK_DIRS:
        for script, ev in SCRIPT_EVENT.items():
            if ev != event:
                continue
            path = d.rstrip("/") + "/" + script
            if command in ("bash '%s'" % path, "bash %s" % path):
                return True
    return False


def set_hook_dirs(dirs):
    del HOOK_DIRS[:]
    for d in dirs:
        if not d:
            continue
        for x in (d, os.path.realpath(d)):
            if x not in HOOK_DIRS:
                HOOK_DIRS.append(x)


def out(kind, msg):
    sys.stdout.write("%s\t%s\n" % (kind, msg))


class Refuse(Exception):
    pass


# ---------------------------------------------------------------------------
# Line scanner: classifies physical lines into logical TOML items.
# ---------------------------------------------------------------------------
BARE = r"[A-Za-z0-9_-]+"
QUOTED = r'"(?:[^"\\]|\\.)*"|\'[^\']*\''
KEYPART = r"(?:%s|%s)" % (BARE, QUOTED)
DOTTED = r"%s(?:\s*\.\s*%s)*" % (KEYPART, KEYPART)
HEADER_RE = re.compile(r"^\s*(\[\[?)\s*(%s)\s*(\]\]?)\s*(?:#.*)?$" % DOTTED)
KEY_RE = re.compile(r"^\s*(%s)\s*=" % DOTTED)
PART_RE = re.compile(KEYPART)


def split_key(dotted):
    parts = []
    for m in PART_RE.finditer(dotted):
        p = m.group(0)
        if p[0] in "\"'":
            p = p[1:-1]
        parts.append(p)
    return tuple(parts)


def _advance(line, state):
    """Track string/bracket state across a physical line. state = [mode, depth];
    mode: None, '"""', "'''". Returns updated state."""
    mode, depth = state
    i, n = 0, len(line)
    while i < n:
        c = line[i]
        if mode == '"""':
            if c == "\\":
                i += 2
                continue
            if line.startswith('"""', i):
                mode = None
                i += 3
                continue
            i += 1
            continue
        if mode == "'''":
            if line.startswith("'''", i):
                mode = None
                i += 3
                continue
            i += 1
            continue
        if c == "#":
            break
        if line.startswith('"""', i):
            mode = '"""'
            i += 3
            continue
        if line.startswith("'''", i):
            mode = "'''"
            i += 3
            continue
        if c == '"':
            i += 1
            while i < n and line[i] != '"':
                i += 2 if line[i] == "\\" else 1
            i += 1
            continue
        if c == "'":
            j = line.find("'", i + 1)
            i = n if j < 0 else j + 1
            continue
        if c in "[{":
            depth += 1
        elif c in "]}":
            depth = max(0, depth - 1)
        i += 1
    return [mode, depth]


def items_of(lines):
    """Group physical lines into logical items:
    {kind: header|key|comment|blank|other, lines: [...], path, array, key, value}"""
    items = []
    state = [None, 0]
    for idx, ln in enumerate(lines):
        if state[0] is not None or state[1] > 0:
            items[-1]["lines"].append(ln)
            state = _advance(ln, state)
            continue
        s = ln.strip()
        if s == "":
            items.append({"kind": "blank", "lines": [ln]})
            continue
        if s.startswith("#"):
            items.append({"kind": "comment", "lines": [ln], "start": idx})
            continue
        m = HEADER_RE.match(ln)
        if m and (m.group(1) == "[[") == (m.group(3) == "]]"):
            items.append({"kind": "header", "lines": [ln], "path": split_key(m.group(2)),
                          "array": m.group(1) == "[["})
            continue
        m = KEY_RE.match(ln)
        if m:
            it = {"kind": "key", "lines": [ln], "key": split_key(m.group(1)), "value": ln[m.end():]}
            items.append(it)
            state = _advance(ln[m.end():], [None, 0])
            continue
        items.append({"kind": "other", "lines": [ln]})
    return items


def sections_of(items):
    """Split items into sections: [{header: item|None, pre: [comments], body: [items]}]."""
    secs = [{"header": None, "pre": [], "body": []}]
    for it in items:
        if it["kind"] == "header":
            prev = secs[-1]["body"]
            pre = []
            while prev and prev[-1]["kind"] == "comment":
                pre.insert(0, prev.pop())
            secs.append({"header": it, "pre": pre, "body": []})
        else:
            secs[-1]["body"].append(it)
    return secs


def lines_of(items):
    res = []
    for it in items:
        res.extend(it["lines"])
    return res


def sec_lines(sec):
    res = lines_of(sec["pre"])
    if sec["header"] is not None:
        res.extend(sec["header"]["lines"])
    res.extend(lines_of(sec["body"]))
    return res


def trim_blank(lines):
    lines = list(lines)
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    return lines


# ---------------------------------------------------------------------------
# Block location and classification.
# ---------------------------------------------------------------------------
def comment_lines(lines):
    """(index, text) of every real comment line — never text inside a
    multi-line string or array."""
    return [(it["start"], it["lines"][0].rstrip()) for it in items_of(lines) if it["kind"] == "comment"]


def find_block(lines, name):
    b, e = MARKERS[name]
    com = comment_lines(lines)
    bi = [i for i, ln in com if ln == b]
    ei = [i for i, ln in com if ln == e]
    if not bi and not ei:
        return None
    if len(bi) != 1 or len(ei) != 1 or ei[0] < bi[0]:
        raise Refuse("config.toml has a damaged or duplicated overcodex %s marker pair — fix it by hand" % name)
    return bi[0], ei[0]


def find_sentinel(lines):
    for i, txt in comment_lines(lines):
        if i + 1 < len(lines) and txt == SENTINEL_COMMENT and lines[i + 1].strip() == SENTINEL_HEADER:
            # only ours while the table carries no keys of its own
            j = i + 2
            while j < len(lines) and (not lines[j].strip() or lines[j].lstrip().startswith("#")):
                j += 1
            if j < len(lines) and KEY_RE.match(lines[j]) and not HEADER_RE.match(lines[j]):
                return None
            return i
    return None


def context_header(lines, upto):
    """The table header in effect at line `upto` (outside any block body), or ()."""
    for it in reversed(items_of(lines[:upto])):
        if it["kind"] == "header":
            return it["path"], it["array"]
    return (), False


def classify(name, body_lines, shipped_agent_keys):
    """Return dict with owned (list of line-lists), foreign_pre (keys that belong
    to the table in effect before the block), foreign_keyed ({header-line: [lines]}
    for foreign keys inside an owned plain table), foreign_secs (list of line-lists)."""
    secs = sections_of(items_of(body_lines))
    res = {"owned": [], "owned_pre": [], "foreign_pre": [], "foreign_keyed": [], "foreign_secs": [],
           "owned_headers": []}

    def is_owned_key(path, key):
        if name == "statusline":
            return key[0] in SL_KEYS
        if name == "agents" and path == ("agents",):
            return key[0] in shipped_agent_keys
        if name == "agents":
            return key[0] in ROLE_KEYS
        return True

    # preamble
    pre = secs[0]
    owned_pre, foreign_pre = [], []
    pending = []
    for it in pre["body"]:
        if it["kind"] in ("comment", "blank"):
            pending.append(it)
            continue
        if it["kind"] == "key" and name == "statusline" and is_owned_key((), it["key"]):
            owned_pre.extend(pending + [it])
        else:
            foreign_pre.extend([p for p in pending if p["kind"] == "comment"] + [it])
        pending = []
    res["owned_pre"] = lines_of(owned_pre)
    res["foreign_pre"] = lines_of(foreign_pre)

    i = 1
    while i < len(secs):
        sec = secs[i]
        h = sec["header"]
        path = h["path"]
        if name == "hooks":
            if h["array"] and len(path) == 2 and path[0] == "hooks" and path[1] != "state":
                unit = [sec]
                j = i + 1
                while j < len(secs):
                    p2 = secs[j]["header"]["path"]
                    if len(p2) > 2 and p2[:2] == path:
                        unit.append(secs[j])
                        j += 1
                    else:
                        break
                # Ownership is per HANDLER: only a handler whose command is
                # exactly one overcodex ships for this event is ours. Other
                # handlers in the same group are re-emitted, under a copy of
                # the group header and its keys (matcher), as foreign content.
                group = unit[0]
                group_lines = lines_of(group["pre"]) + group["header"]["lines"] + lines_of(group["body"])
                group_core = group["header"]["lines"] + lines_of([it for it in group["body"] if it["kind"] != "comment"])
                mine, theirs = [], []
                for hs in unit[1:]:
                    cmd = None
                    for it in hs["body"]:
                        if it["kind"] == "key" and it["key"] == ("command",):
                            try:
                                cmd = parse("v =" + it["value"]).get("v")
                            except Exception:
                                cmd = None
                    is_handler = hs["header"]["path"] == path + ("hooks",) and hs["header"]["array"]
                    (mine if is_handler and owned_hook_command(path[1], cmd) else theirs).append(hs)
                if mine and not theirs:
                    res["owned"].append([ln for s_ in unit for ln in sec_lines(s_)])
                elif not mine:
                    res["foreign_secs"].append([ln for s_ in unit for ln in sec_lines(s_)])
                else:
                    res["owned"].append(group_lines + [ln for s_ in mine for ln in sec_lines(s_)])
                    res["foreign_secs"].append(trim_blank(group_core) + [""] + [ln for s_ in theirs for ln in sec_lines(s_)])
                i = j
                continue
            res["foreign_secs"].append(sec_lines(sec))
            i += 1
            continue
        if name == "agents":
            owned_hdr = path == ("agents",) or (len(path) == 2 and path[0] == "agents" and path[1] in AGENT_ROLES)
        else:  # statusline
            owned_hdr = path == ("tui",) and not h["array"]
        if not owned_hdr or h["array"]:
            res["foreign_secs"].append(sec_lines(sec))
            i += 1
            continue
        owned_body, foreign_body, pending = [], [], []
        for it in sec["body"]:
            if it["kind"] in ("comment", "blank"):
                pending.append(it)
                continue
            if it["kind"] == "key" and is_owned_key(path, it["key"]):
                owned_body.extend(pending + [it])
            else:
                foreign_body.extend([p for p in pending if p["kind"] == "comment"] + [it])
            pending = []
        owned_body.extend(pending)
        res["owned"].append(lines_of(sec["pre"]) + h["lines"] + lines_of(owned_body))
        res["owned_headers"].append(path)
        if foreign_body:
            res["foreign_keyed"].append((h["lines"][0], path, lines_of(foreign_body)))
        i += 1
    return res


# ---------------------------------------------------------------------------
# Semantic check helpers.
# ---------------------------------------------------------------------------
def parse(text):
    return tomllib.loads(text)


def canon(x):
    if isinstance(x, dict):
        d = {}
        for k, v in x.items():
            cv = canon(v)
            if cv == {}:
                continue
            d[k] = cv
        return d
    if isinstance(x, list):
        return sorted((canon(v) for v in x), key=lambda v: json.dumps(v, sort_keys=True, default=str))
    return x


def explode(tree):
    """Hooks compared per handler: hooks.<Event> = list of groups becomes a list
    of {group keys..., "__handler": handler} so a group split into an owned and
    a foreign copy (same matcher) compares equal to the original."""
    if not isinstance(tree, dict) or not isinstance(tree.get("hooks"), dict):
        return tree
    t = dict(tree)
    hk = dict(t["hooks"])
    for ev, groups in list(hk.items()):
        if ev == "state" or not isinstance(groups, list):
            continue
        flat = []
        for g in groups:
            if not isinstance(g, dict) or not isinstance(g.get("hooks"), list) or not g["hooks"]:
                flat.append(g)
                continue
            base = dict((k, v) for k, v in g.items() if k != "hooks")
            for h in g["hooks"]:
                e = dict(base)
                e["__handler"] = h
                flat.append(e)
        hk[ev] = flat
    t["hooks"] = hk
    return t


def subtract(a, b):
    a = dict(a)
    for k, bv in b.items():
        if k not in a:
            raise Refuse("internal check: shipped key %r not found" % k)
        av = a[k]
        if isinstance(bv, dict) and isinstance(av, dict):
            r = subtract(av, bv)
            if r:
                a[k] = r
            else:
                del a[k]
        elif isinstance(bv, list) and isinstance(av, list):
            rest = list(av)
            for el in bv:
                if el in rest:
                    rest.remove(el)
                else:
                    raise Refuse("internal check: shipped array element under %r not found" % k)
            if rest:
                a[k] = rest
            else:
                del a[k]
        else:
            del a[k]
    return a


def add(a, b):
    a = dict(a)
    for k, bv in b.items():
        if k in a and isinstance(a[k], dict) and isinstance(bv, dict):
            a[k] = add(a[k], bv)
        elif k in a and isinstance(a[k], list) and isinstance(bv, list):
            a[k] = a[k] + bv
        else:
            a[k] = bv
    return a


def nest(path, tree):
    for p in reversed(path):
        tree = {p: tree}
    return tree


def owned_tree(lines, bounds, cls):
    """TOML data of the owned part of one block (preamble keys nested under the
    table in effect before the block)."""
    tree = {}
    try:
        if cls["owned_pre"]:
            ctx, is_arr = context_header(lines, bounds[0])
            if is_arr:
                raise Refuse("status_line block sits inside an array table — fix config.toml by hand")
            tree = add(tree, nest(ctx, parse("\n".join(cls["owned_pre"]) + "\n")))
        for chunk in cls["owned"]:
            tree = add(tree, parse("\n".join(chunk) + "\n"))
    except Refuse:
        raise
    except Exception as ex:
        raise Refuse("cannot interpret an overcodex block (hand-edited?): %s" % ex)
    return tree


# ---------------------------------------------------------------------------
# Edits.
# ---------------------------------------------------------------------------
def remove_block(lines, name, agent_keys, new_body=None, keep_in_place=True):
    """Remove (or, with new_body, replace) block `name`, relocating foreign
    content. Returns (lines, owned_old_tree, info)."""
    b, e = find_block(lines, name)
    cls = classify(name, lines[b + 1:e], agent_keys)
    old_owned = owned_tree(lines, (b, e), cls)
    begin, end = MARKERS[name]
    foreign_sec_lines = []
    for chunk in cls["foreign_secs"]:
        chunk = trim_blank(chunk)
        if chunk:
            if foreign_sec_lines:
                foreign_sec_lines.append("")
            foreign_sec_lines.extend(chunk)
    keyed_tail = []  # foreign keys of owned tables whose header the new block lacks
    if new_body is not None:
        body = list(new_body)
        for hline, path, flines in cls["foreign_keyed"]:
            # re-insert after that header's section inside the new block
            idx = None
            for k, ln in enumerate(body):
                m = HEADER_RE.match(ln)
                if m and split_key(m.group(2)) == path:
                    idx = k
                    break
            if idx is None:
                keyed_tail.extend([""] + [hline] + flines)
                continue
            k = idx + 1
            while k < len(body) and not HEADER_RE.match(body[k]):
                k += 1
            while k > idx + 1 and not body[k - 1].strip():
                k -= 1
            body[k:k] = flines
        tail = keyed_tail[:]
        if foreign_sec_lines:
            tail += [""] + foreign_sec_lines
        if keep_in_place:
            lines = lines[:b] + cls["foreign_pre"] + [begin] + body + [end] + tail + lines[e + 1:]
            return lines, old_owned, {"cls": cls}
        # Moving: only keys that belong to the table before the block stay here;
        # the block and the foreign tables found inside it go to the caller.
        stay = cls["foreign_pre"]
        start = b
        if not stay and b > 0 and not lines[b - 1].strip():
            start = b - 1
        lines = lines[:start] + stay + lines[e + 1:]
        return lines, old_owned, {"repl": [begin] + body + [end] + tail, "cls": cls}
    # strip
    stay = list(cls["foreign_pre"])
    for hline, path, flines in cls["foreign_keyed"]:
        if stay:
            stay.append("")
        stay += [hline] + flines
    if foreign_sec_lines:
        if stay:
            stay.append("")
        stay += foreign_sec_lines
    start = b
    if b > 0 and not lines[b - 1].strip():
        start = b - 1
    if stay:
        mid = ([""] if start < b else []) + stay
    else:
        mid = []
    lines = lines[:start] + mid + lines[e + 1:]
    return lines, old_owned, {"cls": cls}


def remove_sentinel(lines):
    """Remove the sentinel comment + its empty [hooks.state] header, and any
    orphan copy of the sentinel comment (header gone or carrying keys)."""
    changed = False
    i = find_sentinel(lines)
    if i is not None:
        start = i - 1 if i > 0 and not lines[i - 1].strip() else i
        lines = lines[:start] + lines[i + 2:]
        changed = True
    orphans = set(j for j, txt in comment_lines(lines) if txt == SENTINEL_COMMENT)
    if orphans:
        lines = [ln for j, ln in enumerate(lines) if j not in orphans]
        changed = True
    return lines, changed


def append_at_eof(lines, block):
    lines = list(lines)
    while lines and not lines[-1].strip():
        lines.pop()
    if lines:
        lines.append("")
    return lines + block


def render_tpl(path, subst):
    res = []
    with open(path) as f:
        for ln in f.read().splitlines():
            if not ln.lstrip().startswith("#"):
                for k, v in subst.items():
                    ln = ln.replace(k, v)
            res.append(ln)
    return res


def toml_str_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def has_table_after(lines, idx):
    for ln in lines[idx + 1:]:
        if HEADER_RE.match(ln):
            return True
    return False


def last_block_end(lines):
    ends = []
    for name in MARKERS:
        try:
            bnd = find_block(lines, name)
        except Refuse:
            continue
        if bnd:
            ends.append(bnd[1])
    return max(ends) if ends else None


def explicit_header(lines, path):
    for it in items_of(lines):
        if it["kind"] == "header" and it["path"] == path and not it["array"]:
            return True
    return False


def join(lines):
    return NL.join(lines) + NL if lines else ""


def write_config(path, epoch, text):
    real = os.path.realpath(path)  # never replace a symlinked config with a file
    if os.path.exists(real):
        shutil.copy2(real, path + ".bak-" + epoch)
    tmp = real + ".tmp-" + epoch
    with open(tmp, "w", newline="") as f:
        f.write(text)
    if os.path.exists(real):
        shutil.copymode(real, tmp)  # a 0600 config (mcp env secrets) stays 0600
    os.replace(tmp, real)
    return path + ".bak-" + epoch if os.path.exists(path + ".bak-" + epoch) else ""


def read_lines(path):
    """Lines without terminators, the raw text, and the file's newline style
    is remembered in NL so a CRLF config is written back as CRLF."""
    global NL
    NL = "\n"
    if not os.path.exists(path):
        return [], ""
    with open(path, newline="") as f:
        text = f.read()
    if "\r\n" in text and text.count("\r\n") * 2 >= text.count("\n"):
        NL = "\r\n"
    return text.splitlines(), text


DEFAULT_AGENT_KEYS = ("max_threads", "max_depth")


def strip_all(lines, agent_keys=DEFAULT_AGENT_KEYS):
    """Virtual uninstall: (lines without any overcodex-owned content, owned tree)."""
    owned = {}
    for name in MARKERS:
        if find_block(lines, name):
            lines, t, _ = remove_block(lines, name, agent_keys)
            owned = add(owned, t)
    lines, _ = remove_sentinel(lines)
    return lines, owned


def checked(old_text, new_lines, owned_removed, owned_added):
    new_text = join(new_lines)
    try:
        new_tree = parse(new_text)
    except Exception as ex:
        raise Refuse("result would not be valid TOML (%s)" % ex)
    expected = add(subtract(explode(parse(old_text)), explode(owned_removed)), explode(owned_added))
    if canon(explode(new_tree)) != canon(expected):
        raise Refuse("result would change settings overcodex does not own")
    return new_text


# ---------------------------------------------------------------------------
# Commands.
# ---------------------------------------------------------------------------
def cmd_apply(args):
    global ROLE_KEYS
    cfg, epoch = args[0], args[1]
    opts = dict(zip(args[2::2], args[3::2]))
    set_hook_dirs([opts.get("--hooks-dir", "")] + default_hook_dirs(cfg))
    lines, text = read_lines(cfg)
    try:
        parse(text)
    except Exception as ex:
        out("warn", "config.toml is not valid TOML (%s); leaving it completely untouched." % ex)
        out("warn", "  Fix %s, then re-run the installer to wire hooks/agents/status_line." % cfg)
        return 0
    try:
        base_lines, _ = strip_all(lines)
        base = parse(join(base_lines))
    except Refuse as ex:
        out("warn", "%s; config.toml left untouched." % ex)
        return 0

    hooks_dir = opts["--hooks-dir"]
    agents_dir = opts["--agents-dir"]
    if "'" in hooks_dir:
        out("warn", "hooks dir path contains a single quote; not wiring hooks: %s" % hooks_dir)
        hooks_body = None
    else:
        hooks_body = render_tpl(opts["--hooks-tpl"], {"@HOOKS_DIR@": toml_str_escape(hooks_dir)})
    agents_body = render_tpl(opts["--agents-tpl"], {"@AGENTS_DIR@": toml_str_escape(agents_dir)})
    shipped_agents = parse(join(agents_body)).get("agents", {})
    ROLE_KEYS = tuple(sorted(set(k for v in shipped_agents.values() if isinstance(v, dict) for k in v))) or ROLE_KEYS
    agent_keys = tuple(k for k, v in shipped_agents.items() if not isinstance(v, dict)) + DEFAULT_AGENT_KEYS

    hooks_val = base.get("hooks")
    user_hooks = isinstance(hooks_val, dict) and bool(set(hooks_val) - {"state"}) or \
        (hooks_val is not None and not isinstance(hooks_val, dict))
    tui = base.get("tui") if isinstance(base.get("tui"), dict) else {}
    user_sl = "status_line" in tui
    user_sl_colors = "status_line_use_colors" in tui

    cur = list(lines)
    cur_text = text
    retrust = False
    changed = []

    def attempt(label, new_lines, removed, added):
        nonlocal cur, cur_text
        try:
            new_text = checked(cur_text, new_lines, removed, added)
        except Refuse as ex:
            out("warn", "%s: %s — skipped (config.toml not changed for this step)." % (label, ex))
            return False
        cur, cur_text = new_lines, new_text
        return True

    # Sentinel is re-derived at the end.
    s_lines, had_sentinel = remove_sentinel(cur)
    if had_sentinel:
        attempt("sentinel", s_lines, {}, {})

    def guarded(label, fn):
        try:
            fn()
        except Refuse as ex:
            out("warn", "%s: %s — skipped (config.toml not changed for this step)." % (label, ex))

    def step_statusline():
        # --- status line ---------------------------------------------------------
        sl_src = opts.get("--statusline", "")
        sl_keys = []
        if sl_src and os.path.isfile(sl_src):
            with open(sl_src) as f:
                for ln in f.read().splitlines():
                    s = ln.strip()
                    if not s or s == "[tui]" or s.startswith("#"):
                        continue
                    if user_sl_colors and re.match(r"^status_line_use_colors\s*=", s):
                        continue
                    sl_keys.append(ln)
        sb, se = MARKERS["statusline"]
        bnd = find_block(cur, "statusline")
        if bnd:
            cls = classify("statusline", cur[bnd[0] + 1:bnd[1]], agent_keys)
            fresh = ("tui",) in cls["owned_headers"]
            body = (["[tui]"] if fresh else []) + sl_keys
            if not sl_keys:
                out("skip", "no statusline fragment in kit — leaving the overcodex status_line block as-is")
            elif [ln for ln in sum(cls["owned"], cls["owned_pre"]) if ln.strip()] == [ln for ln in body if ln.strip()]:
                out("skip", "config.toml [tui].status_line already set by overcodex")
            else:
                nl, old_owned, _ = remove_block(cur, "statusline", agent_keys, new_body=body)
                ctx = () if fresh else context_header(cur, bnd[0])[0]
                new_owned = parse(join(body)) if fresh else nest(ctx, parse(join(body)))
                if attempt("status_line refresh", nl, old_owned, new_owned):
                    changed.append("refreshed the overcodex [tui].status_line block")
        elif user_sl:
            out("warn", "config.toml already defines [tui].status_line — leaving it untouched.")
        elif not sl_keys:
            out("skip", "no statusline fragment in kit — leaving [tui].status_line alone")
        else:
            idx = None
            for k, it_ln in enumerate(cur):
                m = HEADER_RE.match(it_ln)
                if m and m.group(1) == "[" and split_key(m.group(2)) == ("tui",):
                    idx = k
                    break
            if idx is not None:
                nl = cur[:idx + 1] + [sb] + sl_keys + [se] + cur[idx + 1:]
                ok = attempt("status_line", nl, {}, {"tui": parse(join(sl_keys))})
            else:
                # A fresh [tui] table. Before the agents/hooks blocks when those are
                # appended now, so `hooks` stays the last top-level table.
                block = [sb, "[tui]"] + sl_keys + [se]
                nl = append_at_eof(cur, block)
                ok = attempt("status_line", nl, {}, {"tui": parse(join(sl_keys))})
                if not ok:
                    out("warn", "  (an inline `tui = {...}` table cannot take new keys: add status_line to it by hand)")
            if ok:
                changed.append("set [tui].status_line in config.toml")

    def step_agents():
        # --- agent roles -----------------------------------------------------------
        ab, ae = MARKERS["agents"]
        bnd = find_block(cur, "agents")
        if bnd:
            cls = classify("agents", cur[bnd[0] + 1:bnd[1]], agent_keys)
            owned_now = [ln for ch in cls["owned"] for ln in ch if ln.strip() and not ln.lstrip().startswith("#")]
            want = [ln for ln in agents_body if ln.strip() and not ln.lstrip().startswith("#")]
            has_foreign = cls["foreign_secs"] or cls["foreign_pre"]
            if owned_now == want and not has_foreign:
                out("skip", "config.toml custom agent roles already wired by overcodex")
            else:
                nl, old_owned, _ = remove_block(cur, "agents", agent_keys, new_body=agents_body)
                if attempt("agent roles refresh", nl, old_owned, parse(join(agents_body))):
                    if owned_now != want:
                        changed.append("refreshed the custom [agents] roles in config.toml")
                    if has_foreign:
                        changed.append("moved settings Codex wrote inside the agent-roles block to below it")
        elif "agents" in base:
            out("warn", "config.toml already defines an 'agents' key — leaving it untouched.")
            out("warn", "  Merge the roles from config/agents-block.toml.tpl into your [agents] table")
            out("warn", "  manually (substitute @AGENTS_DIR@ with %s)." % agents_dir)
        else:
            if attempt("agent roles", append_at_eof(cur, [ab] + agents_body + [ae]), {}, parse(join(agents_body))):
                changed.append("registered custom [agents] roles in config.toml")

    def step_hooks():
        nonlocal retrust
        # --- hooks ----------------------------------------------------------------
        hb, he = MARKERS["hooks"]
        bnd = find_block(cur, "hooks")
        if hooks_body is None:
            pass
        elif bnd:
            cls = classify("hooks", cur[bnd[0] + 1:bnd[1]], agent_keys)
            owned_now = [ln for ch in cls["owned"] for ln in ch if ln.strip() and not ln.lstrip().startswith("#")]
            want = [ln for ln in hooks_body if ln.strip() and not ln.lstrip().startswith("#")]
            old_comments = [ln for ln in cur[bnd[0] + 1:bnd[1]] if ln.lstrip().startswith("#")]
            new_comments = [ln for ln in hooks_body if ln.lstrip().startswith("#")]
            has_foreign = bool(cls["foreign_secs"] or cls["foreign_pre"])
            if owned_now == want and not has_foreign and old_comments == new_comments:
                out("skip", "config.toml hooks block already up to date")
            else:
                # Refresh, moving the block to the end of the file (see SENTINEL_COMMENT).
                nl, old_owned, info = remove_block(cur, "hooks", agent_keys, new_body=hooks_body, keep_in_place=False)
                nl = append_at_eof(nl, info["repl"])
                new_owned = parse(join(hooks_body))
                if attempt("hooks refresh", nl, old_owned, new_owned):
                    if canon(old_owned) != canon(new_owned):
                        changed.append("refreshed the overcodex [hooks] block in config.toml")
                        retrust = True
                    else:
                        changed.append("refreshed the overcodex [hooks] block comments in config.toml")
                    if has_foreign:
                        changed.append("moved settings Codex wrote inside the hooks block (e.g. hook trust) to below it")
        elif user_hooks:
            out("warn", "config.toml already defines its own hooks — leaving them untouched.")
            out("warn", "  Merge the handlers from config/hooks-block.toml.tpl into your hooks")
            out("warn", "  manually (substitute @HOOKS_DIR@ with %s)." % hooks_dir)
        else:
            if attempt("hooks", append_at_eof(cur, [hb] + hooks_body + [he]), {}, parse(join(hooks_body))):
                changed.append("wired the overcodex [hooks] table into config.toml")
                retrust = True

    guarded("status_line", step_statusline)
    guarded("agent roles", step_agents)
    guarded("hooks", step_hooks)

    # --- sentinel ---------------------------------------------------------------
    try:
        bnd = find_block(cur, "hooks")
    except Refuse:
        bnd = None
    if bnd and last_block_end(cur) == bnd[1] and not has_table_after(cur, bnd[1]) \
            and not explicit_header(cur, ("hooks", "state")):
        attempt("sentinel", append_at_eof(cur, [SENTINEL_COMMENT, SENTINEL_HEADER]), {}, {})

    if cur_text == text:
        out("skip", "config.toml: no changes needed")
        return 0
    try:
        bak = write_config(cfg, epoch, cur_text)
    except OSError as ex:
        out("warn", "could not write %s: %s" % (cfg, ex))
        return 0
    suffix = " (backup: %s)" % bak if bak else ""
    if not changed:
        changed.append("tidied overcodex markers in config.toml")
    for c in changed:
        out("did", c + suffix)
    if retrust:
        out("retrust", "1")
    return 0


def default_hook_dirs(cfg):
    return [os.path.join(os.path.dirname(os.path.abspath(cfg)), "hooks"),
            os.path.join(os.path.expanduser("~"), ".codex", "hooks")]


def cmd_strip(args):
    cfg, epoch = args[0], args[1]
    extra = [args[k + 1] for k in range(2, len(args) - 1) if args[k] == "--hooks-dir"]
    set_hook_dirs(extra + default_hook_dirs(cfg))
    lines, text = read_lines(cfg)
    if not lines:
        out("skip", "no config.toml")
        return 0
    try:
        parse(text)
    except Exception as ex:
        out("warn", "config.toml is not valid TOML (%s) — not editing it; remove the overcodex blocks by hand." % ex)
        return 0
    try:
        present = [n for n in MARKERS if find_block(lines, n)]
    except Refuse as ex:
        out("warn", "%s; config.toml left untouched." % ex)
        return 0
    if not present and not remove_sentinel(lines)[1]:
        out("skip", "config.toml has no overcodex blocks (no change)")
        return 0
    try:
        new_lines, owned = strip_all(lines)
        new_text = checked(text, new_lines, owned, {})
    except Refuse as ex:
        out("warn", "could not safely remove the overcodex blocks (%s); config.toml left untouched." % ex)
        return 0
    moved = False
    for n in present:
        b, e = find_block(lines, n)
        cls = classify(n, lines[b + 1:e], DEFAULT_AGENT_KEYS)
        if cls["foreign_secs"] or cls["foreign_pre"] or cls["foreign_keyed"]:
            moved = True
    bak = write_config(cfg, epoch, new_text)
    label = {"hooks": "hooks block", "agents": "custom agent roles block", "statusline": "[tui].status_line block"}
    for n in present:
        out("did", "removed %s from config.toml (backup: %s)" % (label[n], bak))
    if moved:
        out("did", "kept the settings Codex had written inside those blocks (hook trust, notices, features)")
    return 0


def cmd_verify(args):
    cfg, hooks_dir = args[0], args[1]
    lines, text = read_lines(cfg)
    try:
        d = parse(text)
    except Exception as ex:
        out("fail", "config.toml does not parse: %s" % ex)
        return 0
    hooks = d.get("hooks") if isinstance(d.get("hooks"), dict) else {}
    for event, script in HOOK_SCRIPTS:
        cmds = []
        for group in hooks.get(event, []) if isinstance(hooks.get(event), list) else []:
            for h in group.get("hooks", []) if isinstance(group, dict) else []:
                if isinstance(h, dict):
                    cmds.append(str(h.get("command", "")))
        want = os.path.join(hooks_dir, script)
        if any(want in c for c in cmds):
            out("ok", "%s hook registered -> %s" % (event, script))
        else:
            out("fail", "%s hook NOT registered (%s)" % (event, script))
    agents = d.get("agents") if isinstance(d.get("agents"), dict) else {}
    missing = [r for r in AGENT_ROLES if r not in agents]
    if missing:
        out("fail", "custom agent roles not registered: %s" % ", ".join(missing))
    else:
        out("ok", "custom agent roles registered")
    return 0


def main(argv):
    if not argv:
        sys.stderr.write(__doc__)
        return 2
    cmd, args = argv[0], argv[1:]
    if cmd == "check":
        return 0 if tomllib is not None else 1
    if tomllib is None:
        out("warn", "no TOML parser (need python3 >= 3.11, or tomli) — config.toml NOT modified")
        return 3
    fn = {"apply": cmd_apply, "strip": cmd_strip, "verify": cmd_verify}.get(cmd)
    if fn is not None:
        try:
            return fn(args)
        except Exception as ex:  # never leave a half-written config: writes happen last
            out("warn", "config tool error (%s: %s); config.toml left untouched." % (type(ex).__name__, ex))
            return 0
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
