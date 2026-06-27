#!/usr/bin/env python3
"""Verdict gate: validate the adversarial verifier's ql-verdict block.

The verifier runs in a FRESH context (a separate agent that never saw the builder's
reasoning) and tries to break the builder's work. This gate is the mechanical floor
on the verifier itself: it cannot rubber-stamp (a `pass` needs evidence it actually
re-ran something) and it cannot reject vaguely (a `fail` needs a concrete defect)."""
import os, re, sys, qllib

VERDICTS = ("pass", "fail")
FILE_REF_RE = re.compile(r"^(.+?):(\d+)$")
URL_RE = re.compile(r"^https?://[^\s]+$", re.I)


def parse_block(msg):
    m = re.search(r"```ql-verdict[^\n]*\n(.*?)```", msg, re.S)
    if not m:
        return None
    out = {"verdict": None, "summary": "", "checks": [], "findings": []}
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
            elif key == "summary":
                out["summary"] = val
            continue
        if section == "checks":
            if s.startswith("- check:"):
                cur = {"check": s[len("- check:"):].strip().strip('"'), "evidence": {}}
                out["checks"].append(cur)
            elif cur is not None and ":" in s:
                k, _, v = s.partition(":")
                k = k.strip().lstrip("-").strip()
                if k in ("type", "ref", "result"):
                    cur["evidence"][k] = v.strip().strip('"')
        elif section == "findings":
            if s.startswith("- severity:"):
                cur = {"severity": s[len("- severity:"):].strip().strip('"'), "issue": "", "where": ""}
                out["findings"].append(cur)
            elif cur is not None and ":" in s:
                k, _, v = s.partition(":")
                k = k.strip().lstrip("-").strip()
                if k in ("issue", "where", "severity"):
                    cur[k] = v.strip().strip('"')
    return out


def evidence_ran(ev, cmds, tools):
    """True if this evidence points at something the verifier actually executed/inspected."""
    etype, ref = (ev.get("type") or "").lower(), ev.get("ref", "")
    if etype == "command":
        if not ref.strip():
            return False
        head = re.split(r"\s+", ref.strip())[0]
        blob = "\n".join(cmds)
        if ref.strip() in blob or (head and re.search(r"\b" + re.escape(head) + r"\b", blob)):
            return True
        return any(t["name"] in ("Read", "Grep", "Glob") for t in tools)
    if etype == "file":
        fm = FILE_REF_RE.match(ref)
        return bool(fm and os.path.isfile(fm.group(1)))
    if etype == "url":
        return bool(URL_RE.match(ref))
    return False


def run(transcript_path, cwd):
    lines = qllib.read_lines(transcript_path)
    msg = qllib.last_assistant_text(lines)
    if not msg:
        return []
    block = parse_block(msg)
    if block is None or block["verdict"] not in VERDICTS:
        return ["No valid ql-verdict block this turn. End with a fenced ```ql-verdict``` block: "
                "verdict (pass|fail), summary, checks[] each with evidence you actually ran, "
                "findings[] (required when fail) each with severity, issue, and where (path:line)."]

    cmds = qllib.turn_bash_commands(lines)
    tools = qllib.turn_tool_uses(lines)
    findings = []

    # No rubber-stamping: a verdict must rest on a check the verifier independently ran.
    if not any(evidence_ran(c.get("evidence", {}), cmds, tools) for c in block["checks"]):
        findings.append("Verdict cites no check backed by evidence you actually ran this turn. "
                        "Independently re-run the builder's claims (command|file|url) before judging.")

    # No vague rejection: a fail must name a concrete defect and where it lives.
    if block["verdict"] == "fail":
        concrete = [f for f in block["findings"]
                    if f.get("issue", "").strip() and f.get("where", "").strip()]
        if not concrete:
            findings.append("verdict is fail but no finding names a concrete issue + where (path:line). "
                            "State at least one specific defect, or change the verdict to pass.")
    return findings


def verdict_of(transcript_path):
    msg = qllib.last_assistant_text(qllib.read_lines(transcript_path))
    b = parse_block(msg) if msg else None
    return b["verdict"] if b and b["verdict"] in VERDICTS else ""


def is_verdict(transcript_path):
    msg = qllib.last_assistant_text(qllib.read_lines(transcript_path))
    return bool(msg and parse_block(msg))


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[-1] == "--verdict":
        print(verdict_of(sys.argv[1]))
    elif len(sys.argv) > 1 and sys.argv[-1] == "--is-verdict":
        print("yes" if is_verdict(sys.argv[1]) else "no")
    else:
        for f in run(sys.argv[1] if len(sys.argv) > 1 else "", sys.argv[2] if len(sys.argv) > 2 else "."):
            print(f)
