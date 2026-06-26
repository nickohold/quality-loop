#!/usr/bin/env python3
"""Binding decision ledger. add|show|clear <cwd> [text]."""
import sys, os, qllib

def add(cwd, text):
    p = qllib.ledger_path(cwd)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    first = not os.path.exists(p)
    with open(p, "a") as fh:
        if first:
            fh.write("# Binding decisions for this workspace — SETTLED; do not reopen or contradict.\n\n")
        fh.write("- " + text.strip() + "\n")

def show(cwd):
    try:
        with open(qllib.ledger_path(cwd)) as fh:
            return fh.read()
    except Exception:
        return ""

def clear(cwd):
    try:
        os.remove(qllib.ledger_path(cwd))
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
