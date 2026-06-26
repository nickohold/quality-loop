#!/usr/bin/env python3
"""Altitude gate — keep answers at the altitude of the question.

If the user's last message was a QUESTION (not a build command) and the
assistant's reply is a thesis (too long / code blocks / file:line refs /
multi-section headers / tables), block and tell it to lead with the decision.

Also: if the user message was interrogative and the turn produced file
mutations, flag that the assistant acted on a question instead of answering.

Tune the strictness with QL_MAX_LINES (env) or MAX_LINES below.
"""
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
    if any(t.startswith(c) or (" " + c + " ") in t[:40] for c in COMMAND_HINTS):
        if "?" not in t[:120]:
            return False
    return ("?" in t) or any(t.startswith(h) for h in QUESTION_HINTS)

def run(transcript_path, cwd):
    lines = qllib.read_lines(transcript_path)
    user = qllib.last_user_text(lines)
    msg = qllib.last_assistant_text(lines)
    if not msg:
        return []
    findings = []
    if not is_question(user):
        return findings

    nlines = len([l for l in msg.splitlines() if l.strip()])
    has_code = "```" in msg
    has_fileref = bool(re.search(r"\b[\w/\-]+\.(ts|tsx|js|jsx|py|go|java|rb|rs|sh|md):\d+", msg))
    has_headers = len(re.findall(r"(?m)^#{1,6}\s", msg)) >= 2
    has_table = msg.count("|") >= 6 and "---" in msg
    reasons = []
    if nlines > MAX_LINES:
        reasons.append("%d non-blank lines (>%d)" % (nlines, MAX_LINES))
    if has_code:
        reasons.append("contains code blocks")
    if has_fileref:
        reasons.append("contains file:line refs")
    if has_headers:
        reasons.append("multi-section headers")
    if has_table:
        reasons.append("a table")
    if reasons:
        findings.append("A QUESTION was asked but the reply is a thesis (%s). Lead with the decision in sentence one, plain prose, under %d lines." % (", ".join(reasons), MAX_LINES))

    tools = qllib.turn_tool_uses(lines)
    if any(t["name"] in ("Edit", "Write", "MultiEdit", "NotebookEdit") for t in tools):
        findings.append("A question was asked and the turn EDITED files. Answer the question; do not act unless told to.")
    return findings

if __name__ == "__main__":
    tp = sys.argv[1] if len(sys.argv) > 1 else ""
    cwd = sys.argv[2] if len(sys.argv) > 2 else "."
    for f in run(tp, cwd):
        print(f)
