#!/usr/bin/env python3
"""Shared helpers for the gates. QL_DIR is self-locating so the package runs wherever it's installed."""
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
        return "\n".join(b.get("text", "") for b in content
                         if isinstance(b, dict) and b.get("type") == "text")
    return ""

def _is_real_user(o):
    if o.get("type") != "user":
        return False
    m = o.get("message")
    if not isinstance(m, dict) or m.get("role") != "user" or o.get("isSidechain"):
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
            return _text_of(o.get("message", {}).get("content")).strip()
    return ""

def turn_tool_uses(lines):
    """Assistant tool_use blocks since the last real user message."""
    uses = []
    for o in lines[last_user_index(lines):]:
        if o.get("type") != "assistant":
            continue
        c = o.get("message", {}).get("content")
        if isinstance(c, list):
            for b in c:
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    uses.append({"name": b.get("name", ""), "input": b.get("input", {})})
    return uses

def turn_bash_commands(lines):
    return [str(u["input"].get("command", "")) for u in turn_tool_uses(lines) if u["name"] == "Bash"]

def git_diff(cwd):
    out = ""
    for args in (["git", "diff", "HEAD"], ["git", "diff", "--cached"]):
        try:
            out += subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=10).stdout
        except Exception:
            pass
    return out

def changed_files(cwd):
    files = set()
    for args in (["git", "diff", "--name-only", "HEAD"], ["git", "diff", "--cached", "--name-only"]):
        try:
            r = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=10).stdout
            files.update(ln.strip() for ln in r.splitlines() if ln.strip())
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
    """Load a config list; fall back to the shipped .example so gates work pre-customisation."""
    cfg = os.path.join(QL_DIR, "config")
    candidates = [os.path.join(cfg, name)]
    if name.endswith(".txt"):
        candidates.append(os.path.join(cfg, name[:-4] + ".example.txt"))
    for p in candidates:
        if not os.path.exists(p):
            continue
        try:
            with open(p) as fh:
                return [ln.strip() for ln in fh if ln.strip() and not ln.startswith("#")]
        except Exception:
            pass
    return []

def ledger_path(cwd):
    return os.path.join(QL_DIR, "decisions", "ledger-" + cwd_key(cwd) + ".md")
