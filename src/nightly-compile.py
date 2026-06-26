#!/usr/bin/env python3
"""Nightly friction compiler — the flywheel.

Mines the last 24h of Claude Code transcripts for fresh correction signals,
clusters them, and writes a dated PROPOSAL of rule deltas (new bans, new claim
phrases, new kill-list concepts) to review and approve.

It NEVER edits bans.txt directly — it only proposes. Approval is manual.
Pure file mining, no LLM cost.
"""
import os, glob, json, time, re, collections, qllib

PROJECTS = os.path.expanduser("~/.claude/projects/")
WINDOW = 24 * 3600

SIGNALS = [
    ("repeated-instruction", r"(told you|how many (times|fucking times)|again|stop (putting|adding|doing))"),
    ("guessing", r"(stop guessing|did you (check|verify)|are you sure|that'?s false|you'?re lying|no deductions|empirically)"),
    ("verbosity", r"(tldr|too (long|much)|shorter|thesis|book to read|in code|so much text)"),
    ("over-engineering", r"(simple|just (this|change)|not a (full|whole)|burnt? through|too many agents|over.?engineer)"),
    ("contradiction", r"(you (said|just said)|contradict|already (built|solved)|why (do|are) you (still|going back))"),
    ("wrong-tool", r"(general.?purpose|don'?t use|never use)"),
    ("unauthorized", r"(without (me|asking)|who (told|asked) you|i didn'?t (ask|say))"),
]

def text_of(c):
    if isinstance(c, str): return c
    if isinstance(c, list):
        return "\n".join(b.get("text","") for b in c if isinstance(b,dict) and b.get("type")=="text")
    return ""

def main():
    now = time.time()
    files = [f for f in glob.glob(PROJECTS+"**/*.jsonl", recursive=True)
             if "/subagents/" not in f and "statusline" not in f]
    hits = collections.defaultdict(list)
    for f in files:
        try:
            if now - os.path.getmtime(f) > WINDOW:
                continue
        except Exception:
            continue
        try:
            with open(f, errors="ignore") as fh:
                for line in fh:
                    try: o = json.loads(line)
                    except: continue
                    if o.get("type") != "user": continue
                    m = o.get("message")
                    if not isinstance(m, dict) or m.get("role") != "user": continue
                    if o.get("isSidechain"): continue
                    t = text_of(m.get("content")).strip()
                    if not t or t.startswith("<") or "[Request interrupted" in t[:40]:
                        continue
                    low = t.lower()
                    for label, rx in SIGNALS:
                        if re.search(rx, low):
                            hits[label].append(t[:240])
        except Exception:
            continue

    logs = os.path.join(qllib.QL_DIR, "logs")
    os.makedirs(logs, exist_ok=True)
    day = time.strftime("%Y-%m-%d")
    out = os.path.join(logs, "proposals-%s.md" % day)
    total = sum(len(v) for v in hits.values())
    with open(out, "w") as w:
        w.write("# Friction proposals — %s\n\n" % day)
        if not total:
            w.write("No new correction signals in the last 24h. Clean day.\n")
        else:
            w.write("Found %d correction signals across %d categories. Review and approve deltas.\n\n" % (total, len(hits)))
            for label, quotes in sorted(hits.items(), key=lambda kv: -len(kv[1])):
                w.write("## %s (%d)\n" % (label, len(quotes)))
                for q in quotes[:8]:
                    w.write("- %s\n" % q.replace("\n", " "))
                w.write("\n**Proposed action:** ")
                if label == "repeated-instruction":
                    w.write("add a line to config/bans.txt so this is grepped on every diff.\n\n")
                elif label == "guessing":
                    w.write("add the claimed phrase to gate_claims HARD list so it requires evidence.\n\n")
                elif label == "unauthorized":
                    w.write("confirm merge-guard covers this; widen if a new irreversible action appeared.\n\n")
                else:
                    w.write("consider a gate tweak or a project-knowledge note.\n\n")
    print(out)

if __name__ == "__main__":
    main()
