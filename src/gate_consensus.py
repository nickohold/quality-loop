#!/usr/bin/env python3
"""Consensus gate: validate the team-review presenter's ql-consensus block.

Two reviewers debate to unanimous agreement; this gate is the mechanical floor on
that agreement. It cannot be short-circuited (the SendMessage exchanges are counted
from the transcript itself, not taken from a self-reported number) and it cannot be
vague (every accepted finding needs a path:line receipt that resolves)."""
import os, re, sys, qllib

VERDICTS = ("ship-as-is", "fix-first", "cosmetic-only")
FILE_REF_RE = re.compile(r"^(.+?):(\d+)$")
MIN_ROUNDS = 3
MIN_MESSAGES = 3


def parse_block(msg):
    m = re.search(r"```ql-consensus[^\n]*\n(.*?)```", msg, re.S)
    if not m:
        return None
    out = {"verdict": None, "rounds": None, "summary": "", "accepted": [], "dropped": []}
    cur, section = None, None
    for raw in m.group(1).splitlines():
        if not raw.strip():
            continue
        ind = len(raw) - len(raw.lstrip())
        s = raw.strip()
        if ind == 0 and ":" in s and not s.startswith("-"):
            key, _, val = s.partition(":")
            key, val, section = key.strip(), val.strip(), key.strip()
            cur = None
            if key == "verdict":
                out["verdict"] = val.lower()
            elif key == "rounds":
                try:
                    out["rounds"] = int(val)
                except ValueError:
                    out["rounds"] = None
            elif key == "summary":
                out["summary"] = val
            continue
        if section in ("accepted", "dropped"):
            if s.startswith("- finding:"):
                cur = {"finding": s[len("- finding:"):].strip().strip('"'), "evidence": "", "reason": ""}
                out[section].append(cur)
            elif cur is not None and ":" in s:
                k, _, v = s.partition(":")
                k = k.strip().lstrip("-").strip()
                if k in ("evidence", "reason"):
                    cur[k] = v.strip().strip('"')
    return out


def all_tool_uses(lines):
    uses = []
    for o in lines:
        if o.get("type") != "assistant":
            continue
        c = o.get("message", {}).get("content")
        if isinstance(c, list):
            for b in c:
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    uses.append({"name": b.get("name", ""), "input": b.get("input", {})})
    return uses


def evidence_resolves(ref, cwd):
    fm = FILE_REF_RE.match((ref or "").strip())
    if not fm:
        return False
    for p in (fm.group(1), os.path.join(cwd or ".", fm.group(1))):
        if os.path.isfile(p):
            n = sum(1 for _ in open(p, errors="ignore"))
            return 1 <= int(fm.group(2)) <= n
    return False


def run(transcript_path, cwd):
    lines = qllib.read_lines(transcript_path)
    msg = qllib.last_assistant_text(lines)
    if not msg:
        return []
    block = parse_block(msg)
    if block is None or block["verdict"] not in VERDICTS:
        return ["No valid ql-consensus block this turn. End with a fenced ```ql-consensus``` block: "
                "verdict (ship-as-is|fix-first|cosmetic-only), rounds, summary, "
                "accepted[] each with finding + evidence (path:line), dropped[] each with finding + reason."]

    findings = []
    sends = [u for u in all_tool_uses(lines) if u["name"] == "SendMessage"]
    if len(sends) < MIN_MESSAGES:
        findings.append("Transcript shows only %d SendMessage exchange(s); the protocol requires >=%d messages "
                        "each way. Actually debate the findings with your counterpart before declaring consensus."
                        % (len(sends), MIN_MESSAGES))
    if block["rounds"] is None or block["rounds"] < MIN_ROUNDS:
        findings.append("rounds is %s but the protocol requires >=%d. Report the true round count of the debate."
                        % (block["rounds"], MIN_ROUNDS))
    for f in block["accepted"]:
        if not f.get("finding", "").strip():
            findings.append("An accepted entry has an empty finding. State the defect or remove the entry.")
        elif not evidence_resolves(f.get("evidence", ""), cwd):
            findings.append("Accepted finding %r has no resolving evidence (need path:line where the file exists "
                            "and the line is real). Point at the exact line or drop the finding." % f["finding"])
    if block["verdict"] == "fix-first" and not block["accepted"]:
        findings.append("verdict is fix-first but accepted is empty. Name at least one accepted finding "
                        "with evidence, or change the verdict.")
    return findings


def verdict_of(transcript_path):
    msg = qllib.last_assistant_text(qllib.read_lines(transcript_path))
    b = parse_block(msg) if msg else None
    return b["verdict"] if b and b["verdict"] in VERDICTS else ""


def is_consensus(transcript_path):
    msg = qllib.last_assistant_text(qllib.read_lines(transcript_path))
    return bool(msg and parse_block(msg))


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[-1] == "--verdict":
        print(verdict_of(sys.argv[1]))
    elif len(sys.argv) > 1 and sys.argv[-1] == "--is-consensus":
        print("yes" if is_consensus(sys.argv[1]) else "no")
    else:
        for f in run(sys.argv[1] if len(sys.argv) > 1 else "", sys.argv[2] if len(sys.argv) > 2 else "."):
            print(f)
