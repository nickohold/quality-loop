#!/usr/bin/env python3
"""Scope & resource gate — catches over-engineering and runaway fan-out.

(1) If the task was phrased as a small ask ("just change this", "simple", a
    one-liner) but the diff touches many files or adds a new dependency/service,
    flag it.
(2) If the turn spawned many agents / background processes, flag the burn.

Thresholds are env-tunable: QL_MAX_FILES, QL_MAX_AGENTS, QL_MAX_BG.
"""
import re, sys, os, qllib

MAX_FILES  = int(os.environ.get("QL_MAX_FILES", "4"))
MAX_AGENTS = int(os.environ.get("QL_MAX_AGENTS", "8"))
MAX_BG     = int(os.environ.get("QL_MAX_BG", "5"))

SMALL_ASK = ("just ", "simple", "only ", "one line", "one-liner", "just change",
             "small ", "quick ", "tiny ", "single ")
INFRA_ADDS = (r"\+\s*\"[\w@/\-]+\"\s*:\s*\"[\^~\d]",  # new package.json dep
              r"docker", r"new Redis", r"createQueue", r"new microservice",
              r"resource \"", r"helm ", r"kind: Deployment")

def run(transcript_path, cwd):
    lines = qllib.read_lines(transcript_path)
    user = qllib.last_user_text(lines).lower()
    findings = []

    files = qllib.changed_files(cwd)
    small = any(s in user for s in SMALL_ASK) and len(user) < 240
    if small and len(files) > MAX_FILES:
        findings.append("Ask looked small (\"%s…\") but the diff touches %d files: %s. Confirm this isn't a creeping refactor."
                        % (user[:40], len(files), ", ".join(files[:6])))

    diff = qllib.git_diff(cwd)
    for rx in INFRA_ADDS:
        if re.search(rx, diff, re.I):
            findings.append("Diff adds new infra/dependency (matched /%s/). Reuse what exists before introducing this." % rx)
            break

    tools = qllib.turn_tool_uses(lines)
    n_agents = sum(1 for t in tools if t["name"] in ("Agent", "Task", "Workflow"))
    n_bg = sum(1 for t in tools if t["name"] == "Bash" and t["input"].get("run_in_background"))
    if n_agents > MAX_AGENTS:
        findings.append("Spawned %d agents/workflows this turn — that burns the session. Serialize or justify the fan-out." % n_agents)
    if n_bg > MAX_BG:
        findings.append("Started %d background processes this turn. Resource-leak risk; consolidate." % n_bg)
    return findings

if __name__ == "__main__":
    tp = sys.argv[1] if len(sys.argv) > 1 else ""
    cwd = sys.argv[2] if len(sys.argv) > 2 else "."
    for f in run(tp, cwd):
        print(f)
