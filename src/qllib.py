#!/usr/bin/env python3
"""Shared helpers for the quality-loop gates.

Everything keys off the Claude Code transcript (.jsonl). A "turn" is the slice
of assistant activity since the LAST real user message — that is the window in
which a claim must have its evidence.

Paths are self-locating: QL_DIR is the directory this file lives in, so the
package works wherever it is installed (no hardcoded ~/.claude).
"""
import json, os, subprocess, hashlib, re

QL_DIR = os.path.dirname(os.path.realpath(__file__))

def read_lines(transcript_path):
    out = []
    try:
        with open(transcript_path, errors="ignore") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    out.append(json.loads(line))
                except Exception:
                    continue
    except Exception:
        pass
    return out

def _text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for b in content:
            if isinstance(b, dict) and b.get("type") == "text":
                parts.append(b.get("text", ""))
        return "\n".join(parts)
    return ""

def _is_real_user(o):
    """A real typed user message — not a tool_result, not a system reminder."""
    if o.get("type") != "user":
        return False
    m = o.get("message")
    if not isinstance(m, dict) or m.get("role") != "user":
        return False
    if o.get("isSidechain"):
        return False
    c = m.get("content")
    if isinstance(c, list):
        for b in c:
            if isinstance(b, dict) and b.get("type") == "tool_result":
                return False
    t = _text_of(c).strip()
    if not t:
        return False
    for marker in ("<system-reminder>", "<command-name>", "<local-command-stdout>",
                   "<command-message>", "Caveat:", "[Request interrupted"):
        if t.startswith(marker) or marker in t[:60]:
            return False
    return True

def last_user_text(lines):
    for o in reversed(lines):
        if _is_real_user(o):
            return _text_of(o["message"]["content"]).strip()
    return ""

def last_user_index(lines):
    for i in range(len(lines) - 1, -1, -1):
        if _is_real_user(lines[i]):
            return i
    return 0

def last_assistant_text(lines):
    for o in reversed(lines):
        if o.get("type") == "assistant":
            m = o.get("message", {})
            return _text_of(m.get("content")).strip()
    return ""

def turn_tool_uses(lines):
    """All assistant tool_use blocks since the last real user message."""
    start = last_user_index(lines)
    uses = []
    for o in lines[start:]:
        if o.get("type") != "assistant":
            continue
        m = o.get("message", {})
        c = m.get("content")
        if isinstance(c, list):
            for b in c:
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    uses.append({"name": b.get("name", ""), "input": b.get("input", {})})
    return uses

def turn_bash_commands(lines):
    cmds = []
    for u in turn_tool_uses(lines):
        if u["name"] == "Bash":
            cmds.append(str(u["input"].get("command", "")))
    return cmds

def git_diff(cwd):
    try:
        a = subprocess.run(["git", "diff", "HEAD"], cwd=cwd, capture_output=True,
                           text=True, timeout=10).stdout
    except Exception:
        a = ""
    try:
        b = subprocess.run(["git", "diff", "--cached"], cwd=cwd, capture_output=True,
                           text=True, timeout=10).stdout
    except Exception:
        b = ""
    return a + b

def changed_files(cwd):
    files = set()
    for args in (["git", "diff", "--name-only", "HEAD"], ["git", "diff", "--cached", "--name-only"]):
        try:
            r = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=10).stdout
            for ln in r.splitlines():
                if ln.strip():
                    files.add(ln.strip())
        except Exception:
            pass
    return sorted(files)

def cwd_key(cwd):
    return hashlib.sha1((cwd or "").encode()).hexdigest()[:16]

def marker_path(cwd):
    return os.path.join(QL_DIR, "state", "active-" + cwd_key(cwd))

def loop_active(cwd):
    return os.path.exists(marker_path(cwd))

def load_list(name):
    """Load a config list file, ignoring blanks and # comments.

    Falls back to the shipped <name>.example file so the gates are active
    immediately after install, before the user has customised their own copy.
    """
    cfg = os.path.join(QL_DIR, "config")
    candidates = [os.path.join(cfg, name)]
    if name.endswith(".txt"):
        candidates.append(os.path.join(cfg, name[:-4] + ".example.txt"))
    items = []
    for p in candidates:
        if not os.path.exists(p):
            continue
        try:
            with open(p) as fh:
                for ln in fh:
                    ln = ln.strip()
                    if ln and not ln.startswith("#"):
                        items.append(ln)
            break
        except Exception:
            pass
    return items

def ledger_path(cwd):
    return os.path.join(QL_DIR, "decisions", "ledger-" + cwd_key(cwd) + ".md")
