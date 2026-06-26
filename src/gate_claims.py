#!/usr/bin/env python3
"""Claim gate: a verifiable claim with no matching tool-evidence this turn is blocked.
HARD claims always need evidence; SOFT claims only when a diff exists."""
import re, sys, qllib

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
    if re.search(ev_regex, "\n".join(commands), re.I):
        return True
    return any(t["name"] in ("Read", "Grep", "Glob") for t in all_tools)

def run(transcript_path, cwd):
    lines = qllib.read_lines(transcript_path)
    msg = qllib.last_assistant_text(lines)
    if not msg:
        return []
    tools = qllib.turn_tool_uses(lines)
    # Delegated work is enforced at the worker's SubagentStop gate, not here.
    if any(t["name"] in ("Agent", "Task", "Workflow") for t in tools):
        return []
    cmds = qllib.turn_bash_commands(lines)
    has_diff = bool(qllib.git_diff(cwd).strip())
    findings = []
    for pat, ev in HARD.items():
        m = re.search(pat, msg, re.I)
        if m and not evidence_present(cmds, tools, ev):
            findings.append("Claimed \"%s\" with NO matching tool-evidence this turn. Run the check (%s) or mark it unverified."
                            % (m.group(0).strip(), ev.split('|')[0].strip('(')))
    if has_diff:
        for pat, ev in SOFT.items():
            m = re.search(pat, msg, re.I)
            if m and not evidence_present(cmds, tools, ev):
                findings.append("Claimed \"%s\" with an uncommitted diff and no verification this turn. Prove it or mark it unverified."
                                % m.group(0).strip())
    return findings

if __name__ == "__main__":
    for f in run(sys.argv[1] if len(sys.argv) > 1 else "", sys.argv[2] if len(sys.argv) > 2 else "."):
        print(f)
