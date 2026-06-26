#!/usr/bin/env python3
"""Altitude gate: if the user asked a QUESTION, a thesis reply (long / code / refs / tables) is blocked.
Strictness via QL_MAX_LINES."""
import re, sys, os, qllib

MAX_LINES = int(os.environ.get("QL_MAX_LINES", "14"))

QUESTION_HINTS = ("?", "what", "why", "how", "which", "is it", "are we", "should i",
                  "should we", "can you tell", "do we", "does it", "where", "who")
COMMAND_HINTS = ("build", "implement", "add", "create", "fix", "write", "refactor",
                 "run", "make", "set up", "delete", "remove", "update", "deploy",
                 "do it", "go ahead", "proceed", "handout", "hand out", "install")

def is_question(user_msg):
    t = user_msg.lower().strip()
    if not t:
        return False
    if any(t.startswith(c) or (" " + c + " ") in t[:40] for c in COMMAND_HINTS) and "?" not in t[:120]:
        return False
    return ("?" in t) or any(t.startswith(h) for h in QUESTION_HINTS)

def run(transcript_path, cwd):
    lines = qllib.read_lines(transcript_path)
    user = qllib.last_user_text(lines)
    msg = qllib.last_assistant_text(lines)
    if not msg or not is_question(user):
        return []
    reasons = []
    if len([l for l in msg.splitlines() if l.strip()]) > MAX_LINES:
        reasons.append("over %d lines" % MAX_LINES)
    if "```" in msg:
        reasons.append("code blocks")
    if re.search(r"\b[\w/\-]+\.(ts|tsx|js|jsx|py|go|java|rb|rs|sh|md):\d+", msg):
        reasons.append("file:line refs")
    if len(re.findall(r"(?m)^#{1,6}\s", msg)) >= 2:
        reasons.append("multi-section headers")
    if msg.count("|") >= 6 and "---" in msg:
        reasons.append("a table")
    findings = []
    if reasons:
        findings.append("A QUESTION was asked but the reply is a thesis (%s). Lead with the decision, plain prose, under %d lines."
                        % (", ".join(reasons), MAX_LINES))
    if any(t["name"] in ("Edit", "Write", "MultiEdit", "NotebookEdit") for t in qllib.turn_tool_uses(lines)):
        findings.append("A question was asked and the turn EDITED files. Answer it; don't act unless told to.")
    return findings

if __name__ == "__main__":
    for f in run(sys.argv[1] if len(sys.argv) > 1 else "", sys.argv[2] if len(sys.argv) > 2 else "."):
        print(f)
