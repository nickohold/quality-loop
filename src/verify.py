#!/usr/bin/env python3
"""Run all gates against one turn. Usage: verify.py <transcript> <cwd> [--role worker|lead].
The ql-result claim gate runs only for the worker; the lead writes prose to the operator."""
import json, sys, importlib, os

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

WORKER_HARD = ["gate_claims", "gate_bans", "gate_altitude"]
LEAD_HARD = ["gate_bans", "gate_altitude"]
SOFT_GATES = ["gate_scope"]

def main():
    args = sys.argv[1:]
    role = "worker"
    if "--role" in args:
        i = args.index("--role")
        role = args[i + 1] if i + 1 < len(args) else "worker"
        del args[i:i + 2]
    tp = args[0] if len(args) > 0 else ""
    cwd = args[1] if len(args) > 1 else "."
    HARD_GATES = LEAD_HARD if role == "lead" else WORKER_HARD
    blocks, warnings = [], []
    for name, sink in [(n, blocks) for n in HARD_GATES] + [(n, warnings) for n in SOFT_GATES]:
        try:
            sink += importlib.import_module(name).run(tp, cwd)
        except Exception as e:
            warnings.append("gate %s errored: %s" % (name, e))
    print(json.dumps({"pass": len(blocks) == 0, "blocks": blocks, "warnings": warnings}))

if __name__ == "__main__":
    main()
