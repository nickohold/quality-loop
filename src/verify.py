#!/usr/bin/env python3
"""Run every gate against the current turn and aggregate.

Usage:
    python3 verify.py <transcript_path> <cwd>
Prints a JSON object: {"pass": bool, "blocks": [...], "warnings": [...]}
Gates in HARD_GATES block the turn; SOFT_GATES only warn.
"""
import json, sys, importlib, os

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

HARD_GATES = ["gate_claims", "gate_bans", "gate_altitude"]
SOFT_GATES = ["gate_scope"]

def main():
    tp = sys.argv[1] if len(sys.argv) > 1 else ""
    cwd = sys.argv[2] if len(sys.argv) > 2 else "."
    blocks, warnings = [], []
    for name in HARD_GATES:
        try:
            mod = importlib.import_module(name)
            blocks += mod.run(tp, cwd)
        except Exception as e:
            warnings.append("gate %s errored: %s" % (name, e))
    for name in SOFT_GATES:
        try:
            mod = importlib.import_module(name)
            warnings += mod.run(tp, cwd)
        except Exception as e:
            warnings.append("gate %s errored: %s" % (name, e))
    print(json.dumps({"pass": len(blocks) == 0, "blocks": blocks, "warnings": warnings}))

if __name__ == "__main__":
    main()
