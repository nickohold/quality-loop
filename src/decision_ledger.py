#!/usr/bin/env python3
"""Decision ledger — persists binding in-session decisions so the assistant
stops contradicting itself and re-architecting settled work.

    python3 decision_ledger.py add  <cwd> "drop the legacy adapter"
    python3 decision_ledger.py show <cwd>
    python3 decision_ledger.py clear <cwd>
"""
import sys, os, qllib

def add(cwd, text):
    p = qllib.ledger_path(cwd)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    first = not os.path.exists(p)
    with open(p, "a") as fh:
        if first:
            fh.write("# Binding decisions for this workspace\n# These are SETTLED. Do not reopen, re-architect, or contradict.\n\n")
        fh.write("- " + text.strip() + "\n")

def show(cwd):
    p = qllib.ledger_path(cwd)
    try:
        with open(p) as fh:
            return fh.read()
    except Exception:
        return ""

def clear(cwd):
    p = qllib.ledger_path(cwd)
    try:
        os.remove(p)
    except Exception:
        pass

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    cwd = sys.argv[2] if len(sys.argv) > 2 else "."
    if cmd == "add" and len(sys.argv) > 3:
        add(cwd, sys.argv[3])
    elif cmd == "show":
        sys.stdout.write(show(cwd))
    elif cmd == "clear":
        clear(cwd)
