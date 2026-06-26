#!/usr/bin/env python3
"""Claim gate — the #1 friction killer.

If the assistant's final message asserts a verifiable claim ("tests pass",
"merged", "deployed", "fixed", "the DB shows") and the current turn has NO
matching tool-evidence, return a block finding.

Tiered to avoid over-nagging:
  HARD claims (tests pass / merged / deployed) ALWAYS need evidence.
  SOFT claims (done / fixed / works) need evidence only when a diff exists.
"""
import re, sys, qllib

# claim phrase -> evidence command regex it requires in the turn
HARD = {
    r"\b(all\s+)?tests?\s+(are\s+)?(pass|passing|green)\b": r"(test|jest|vitest|pytest|go test|cargo test|npm (run )?test|yarn test|pnpm test|mvn|gradle|rspec|phpunit)",
    r"\ball\s+green\b": r"(test|jest|vitest|pytest|npm (run )?test|yarn test|ci|lint)",
    r"\b(merged|pushed to (main|master)|landed on (main|master))\b": r"(git (merge|push)|gh pr merge)",
    r"\b(deployed|rolled out|shipped to prod)\b": r"(deploy|kubectl|helm|gcloud|aws |vercel|fly |terraform apply)",
    r"\bthe (db|database|document|record|collection|table) (shows|has|contains|returns)\b": r"(mongo|psql|sqlite|find\(|kubectl|curl|select |query)",
    r"\bthe endpoint (returns|responds)\b": r"(curl|http|fetch|wget|xh )",
}
SOFT = {
    r"\b(it'?s|now|fully)\s+(fixed|working|resolved)\b": r"(test|jest|vitest|pytest|npm|yarn|curl|kubectl|mongo|psql|git diff|grep|cat |read)",
    r"\b(done|complete[d]?)\b": r"(test|jest|vitest|pytest|npm|yarn|curl|kubectl|mongo|git|grep|build|compile)",
    r"\bverified\b": r"(test|curl|kubectl|mongo|psql|git log|grep|read|cat )",
}

def evidence_present(commands, all_tools, ev_regex):
    blob = "\n".join(commands)
    if re.search(ev_regex, blob, re.I):
        return True
    # A Read/Grep/Glob this turn counts as light evidence for soft claims
    if any(t["name"] in ("Read", "Grep", "Glob") for t in all_tools):
        return True
    return False

def run(transcript_path, cwd):
    lines = qllib.read_lines(transcript_path)
    msg = qllib.last_assistant_text(lines)
    if not msg:
        return []
    cmds = qllib.turn_bash_commands(lines)
    tools = qllib.turn_tool_uses(lines)
    has_diff = bool(qllib.git_diff(cwd).strip())
    findings = []

    for pat, ev in HARD.items():
        if re.search(pat, msg, re.I) and not evidence_present(cmds, tools, ev):
            m = re.search(pat, msg, re.I)
            findings.append("Claimed \"%s\" with NO matching tool-evidence this turn. Run the check (%s) or downgrade the claim to 'unverified'."
                            % (m.group(0).strip(), ev.split('|')[0].strip('(')))
    if has_diff:
        for pat, ev in SOFT.items():
            if re.search(pat, msg, re.I) and not evidence_present(cmds, tools, ev):
                m = re.search(pat, msg, re.I)
                findings.append("Claimed \"%s\" but there is an uncommitted diff and no verification ran this turn. Prove it or say it's unverified."
                                % m.group(0).strip())
    return findings

if __name__ == "__main__":
    tp = sys.argv[1] if len(sys.argv) > 1 else ""
    cwd = sys.argv[2] if len(sys.argv) > 2 else "."
    for f in run(tp, cwd):
        print(f)
