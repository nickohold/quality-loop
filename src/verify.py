#!/usr/bin/env python3
"""Run all gates against one turn. Usage: verify.py <transcript> <cwd> -> {"pass","blocks","warnings"}."""
import json, sys, importlib, os

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

HARD_GATES = ["gate_claims", "gate_bans", "gate_altitude"]
SOFT_GATES = ["gate_scope"]

def main():
    tp = sys.argv[1] if len(sys.argv) > 1 else ""
    cwd = sys.argv[2] if len(sys.argv) > 2 else "."
    blocks, warnings = [], []
    for name, sink in [(n, blocks) for n in HARD_GATES] + [(n, warnings) for n in SOFT_GATES]:
        try:
            sink += importlib.import_module(name).run(tp, cwd)
        except Exception as e:
            warnings.append("gate %s errored: %s" % (name, e))
    print(json.dumps({"pass": len(blocks) == 0, "blocks": blocks, "warnings": warnings}))

if __name__ == "__main__":
    main()
