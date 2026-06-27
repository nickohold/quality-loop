#!/usr/bin/env python3
"""Run all gates against one turn. Usage: verify.py <transcript> <cwd> [--role worker|lead|verifier].
The ql-result claim gate runs only for the builder; the lead writes prose to the
operator; the verifier emits an adversarial ql-verdict checked by the verdict gate."""
import json, sys, importlib, os

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

WORKER_HARD = ["gate_claims", "gate_bans", "gate_altitude"]
LEAD_HARD = ["gate_bans", "gate_altitude"]
VERIFIER_HARD = ["gate_verdict"]
SOFT_GATES = ["gate_scope"]
HARD_BY_ROLE = {"lead": LEAD_HARD, "verifier": VERIFIER_HARD, "worker": WORKER_HARD}

def main():
    args = sys.argv[1:]
    role = "worker"
    if "--role" in args:
        i = args.index("--role")
        role = args[i + 1] if i + 1 < len(args) else "worker"
        del args[i:i + 2]
    tp = args[0] if len(args) > 0 else ""
    cwd = args[1] if len(args) > 1 else "."
    HARD_GATES = HARD_BY_ROLE.get(role, WORKER_HARD)
    blocks, warnings = [], []
    for name, sink in [(n, blocks) for n in HARD_GATES] + [(n, warnings) for n in SOFT_GATES]:
        try:
            sink += importlib.import_module(name).run(tp, cwd)
        except Exception as e:
            warnings.append("gate %s errored: %s" % (name, e))
    print(json.dumps({"pass": len(blocks) == 0, "blocks": blocks, "warnings": warnings}))

if __name__ == "__main__":
    main()
