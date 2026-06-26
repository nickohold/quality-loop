#!/usr/bin/env python3
"""Claim gate: validate the worker's ql-result block against this turn's transcript and diff.
No English matching — the worker declares status + per-claim evidence; the gate reconciles it."""
import os, re, sys, qllib

STATUSES = ("completed", "working", "input-required", "failed")
URL_RE = re.compile(r"^https?://[^\s]+$", re.I)
FILE_REF_RE = re.compile(r"^(.+?):(\d+)$")


def parse_block(msg):
    m = re.search(r"```ql-result[^\n]*\n(.*?)```", msg, re.S)
    if not m:
        return None
    out = {"status": None, "summary": "", "claims": [], "blocking_question": "", "files_changed": []}
    cur, section = None, None
    for raw in m.group(1).splitlines():
        if not raw.strip():
            continue
        ind = len(raw) - len(raw.lstrip())
        s = raw.strip()
        if ind == 0 and ":" in s and not s.startswith("-"):
            key, _, val = s.partition(":")
            key, val, section = key.strip(), val.strip(), key.strip()
            if key == "status":
                out["status"] = val.lower()
            elif key in ("summary", "blocking_question"):
                out[key] = val
            continue
        if section == "files_changed" and s.startswith("-"):
            out["files_changed"].append(s[1:].strip())
        elif section == "claims":
            if s.startswith("- claim:"):
                cur = {"claim": s[len("- claim:"):].strip().strip('"'), "evidence": {}}
                out["claims"].append(cur)
            elif cur is not None and ":" in s:
                k, _, v = s.partition(":")
                k = k.strip().lstrip("-").strip()
                if k in ("type", "ref", "result"):
                    cur["evidence"][k] = v.strip().strip('"')
    return out


def ran_command(ref, cmds, tools):
    head = re.split(r"\s+", ref.strip())[0] if ref.strip() else ""
    blob = "\n".join(cmds)
    if ref.strip() and (ref.strip() in blob or (head and re.search(r"\b" + re.escape(head) + r"\b", blob))):
        return True
    return any(t["name"] in ("Read", "Grep", "Glob") for t in tools)


def check_command_claims(block, cmds, tools):
    findings = []
    for c in block["claims"]:
        ev = c.get("evidence", {})
        etype, ref = (ev.get("type") or "").lower(), ev.get("ref", "")
        if etype == "command":
            if not ref:
                findings.append("Claim %r has evidence.type=command but no ref. Name the command you ran." % c["claim"])
            elif not ran_command(ref, cmds, tools):
                findings.append("Claim %r cites command %r that did NOT run this turn. Run it or mark the result unverified." % (c["claim"], ref))
        elif etype == "file":
            fm = FILE_REF_RE.match(ref)
            if not fm:
                findings.append("Claim %r has evidence.type=file but ref %r is not path:line." % (c["claim"], ref))
            elif not os.path.isfile(fm.group(1)):
                findings.append("Claim %r cites file %r that does not resolve." % (c["claim"], fm.group(1)))
            else:
                n = sum(1 for _ in open(fm.group(1), errors="ignore"))
                if not 1 <= int(fm.group(2)) <= n:
                    findings.append("Claim %r cites %s but the file has %d lines." % (c["claim"], ref, n))
        elif etype == "url":
            if not URL_RE.match(ref):
                findings.append("Claim %r has evidence.type=url but ref %r is not a valid http(s) URL." % (c["claim"], ref))
        else:
            findings.append("Claim %r has no valid evidence.type (expected command|file|url)." % c["claim"])
    return findings


def run(transcript_path, cwd):
    lines = qllib.read_lines(transcript_path)
    msg = qllib.last_assistant_text(lines)
    if not msg:
        return []
    tools = qllib.turn_tool_uses(lines)
    if any(t["name"] in ("Agent", "Task", "Workflow") for t in tools):
        return []

    block = parse_block(msg)
    if block is None or block["status"] not in STATUSES:
        return ["No valid ql-result block this turn. End your turn with a fenced ```ql-result``` block: "
                "status (completed|working|input-required|failed), summary, claims[] with evidence, files_changed[]."]

    status = block["status"]
    if status == "working":
        return []
    if status == "input-required":
        if not block["blocking_question"].strip():
            return ["status is input-required but blocking_question is empty. State the single blocking question."]
        return []
    if status == "failed":
        if not any(c.get("claim") and c.get("evidence") for c in block["claims"]):
            return ["status is failed but no claim describes what failed. Add at least one claim with evidence of the failure."]
        return []

    findings = []
    if qllib.git_diff(cwd).strip():
        findings += check_command_claims(block, qllib.turn_bash_commands(lines), tools)
        missing = set(qllib.changed_files(cwd)) - set(block["files_changed"])
        if missing:
            findings.append("files_changed omits edited file(s): %s. Declare every changed file." % ", ".join(sorted(missing)))
    return findings


def status_of(transcript_path):
    msg = qllib.last_assistant_text(qllib.read_lines(transcript_path))
    b = parse_block(msg) if msg else None
    return b["status"] if b and b["status"] in STATUSES else ""


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[-1] == "--status":
        print(status_of(sys.argv[1]))
    else:
        for f in run(sys.argv[1] if len(sys.argv) > 1 else "", sys.argv[2] if len(sys.argv) > 2 else "."):
            print(f)
