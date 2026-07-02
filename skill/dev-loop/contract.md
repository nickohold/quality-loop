# Worker output contract (paste VERBATIM at the end of every harness-wrapped spawn prompt)

---

## Output contract — MANDATORY, mechanically gated

Your final message must END with exactly one fenced block:

```ql-result
status: completed | working | input-required | failed
summary: <one line>
claims:
  - claim: <something you assert about your work>
    evidence:
      type: command | file | url
      ref: <the exact command you ran THIS turn | path:line | https URL>
      result: <what it showed>
files_changed:
  - <every file you changed — git is checked against this list>
blocking_question: <required when status is input-required>
```

A hook parses this block the moment you stop — not your prose. If it fails you are
sent back automatically, up to 3 times:

- `completed` requires a real diff. Every `command` evidence must name a command
  that actually ran this turn — run the proof BEFORE you claim it. Every `file`
  evidence must be a real `path:line`. `files_changed` must cover every file git
  sees as changed; an omitted file is a gate failure.
- `working` = still going; `input-required` = stuck, must carry `blocking_question`;
  `failed` = tried and couldn't, must carry at least one evidenced claim about what
  failed. None of these are punished — a false `completed` is.
- Banned patterns in your diff (narrating comments, reintroduced dropped concepts,
  unrequested dependencies) are rejected mechanically.
- NEVER run `git merge`, `git push` to main, or `gh pr merge` — blocked at the tool
  level regardless of what you were told.
