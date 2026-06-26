#!/usr/bin/env python3
"""Scope gate (warn): small ask + big diff, new infra/deps, or runaway fan-out.
Thresholds via QL_MAX_FILES, QL_MAX_AGENTS, QL_MAX_BG."""
import re, sys, os, qllib

MAX_FILES  = int(os.environ.get("QL_MAX_FILES", "4"))
MAX_AGENTS = int(os.environ.get("QL_MAX_AGENTS", "8"))
MAX_BG     = int(os.environ.get("QL_MAX_BG", "5"))

SMALL_ASK = ("just ", "simple", "only ", "one line", "one-liner", "just change",
             "small ", "quick ", "tiny ", "single ")
INFRA_ADDS = (r"\+\s*\"[\w@/\-]+\"\s*:\s*\"[\^~\d]", r"docker", r"new Redis",
              r"createQueue", r"new microservice", r"resource \"", r"helm ", r"kind: Deployment")

def run(transcript_path, cwd):
    lines = qllib.read_lines(transcript_path)
    user = qllib.last_user_text(lines).lower()
    findings = []
    files = qllib.changed_files(cwd)
    if any(s in user for s in SMALL_ASK) and len(user) < 240 and len(files) > MAX_FILES:
        findings.append("Ask looked small (\"%s…\") but the diff touches %d files: %s. Confirm this isn't a creeping refactor."
                        % (user[:40], len(files), ", ".join(files[:6])))
    diff = qllib.git_diff(cwd)
    for rx in INFRA_ADDS:
        if re.search(rx, diff, re.I):
            findings.append("Diff adds new infra/dependency (/%s/). Reuse what exists first." % rx)
            break
    tools = qllib.turn_tool_uses(lines)
    n_agents = sum(1 for t in tools if t["name"] in ("Agent", "Task", "Workflow"))
    n_bg = sum(1 for t in tools if t["name"] == "Bash" and t["input"].get("run_in_background"))
    if n_agents > MAX_AGENTS:
        findings.append("Spawned %d agents/workflows this turn — that burns the session. Serialize or justify it." % n_agents)
    if n_bg > MAX_BG:
        findings.append("Started %d background processes this turn. Consolidate." % n_bg)
    return findings

if __name__ == "__main__":
    for f in run(sys.argv[1] if len(sys.argv) > 1 else "", sys.argv[2] if len(sys.argv) > 2 else "."):
        print(f)
