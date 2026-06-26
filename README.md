# Quality Loop

**A mechanical safety net for handing tasks to an AI coding agent.**

Hand out a task. Be sure the result is up to par — without policing every line
yourself.

Quality Loop is a small set of [Claude Code](https://claude.com/claude-code)
hooks and a skill that put a coding agent's output through **verifiers it cannot
talk its way past**. It was reverse-engineered from months of real transcripts:
find where the agent actually fails, then build a gate exactly there. See
[docs/METHODOLOGY.md](docs/METHODOLOGY.md).

---

## The problem

Coding agents fail in the same handful of ways, over and over:

- they claim *"tests pass / fixed / done / merged"* without running the check,
- they answer a one-line question with a thesis,
- they regenerate patterns you've banned a dozen times,
- they turn a one-line ask into a sprawling refactor,
- they take irreversible actions (merge, push to main) you never approved.

Writing these rules into a prompt doesn't hold — the model's defaults win under
load. **The only thing that holds is a machine check at the moment the failure
would reach you.**

## What it does

When you run `/handout`, the loop arms a set of gates that run automatically when
the agent tries to finish a turn:

| Gate | Blocks the turn when… |
|------|------------------------|
| **claims** | a "tests pass / fixed / merged / deployed / the DB shows" claim has no matching tool-evidence in the same turn |
| **bans** | the diff adds a pattern on your kill-list (narrating comments, types in the wrong file, a concept you removed, an unwanted dependency) |
| **altitude** | you asked a question and the reply is a thesis (code blocks, file refs, tables, or over ~14 lines) |
| **scope** *(warn)* | a small ask produced a big diff, or the turn spawned runaway agents/processes |

Plus two always-on guards:

- **merge-guard** — blocks `git merge`, push-to-main, and `gh pr merge` unless you explicitly run `/approve-merge` (one-shot).
- **decision ledger** — re-injects the binding decisions you've made so the agent stops contradicting itself or re-architecting settled work.

When a gate blocks, the agent sees exactly what failed, fixes it, and finishes
again. You only see the result once it's clean.

### Opt-in by design

The gates have teeth **only while a task is running through `/handout`**. Every
other session is untouched — an always-on gate that miscalibrates just becomes
new friction. You promote a gate to always-on yourself once it's earned it.

## Install

Requires [Claude Code](https://claude.com/claude-code), `python3`, and `jq`.

One command, no clone:

```bash
curl -fsSL https://raw.githubusercontent.com/nickohold/quality-loop/main/bootstrap.sh | bash
```

<details>
<summary>From a clone, or for a private fork</summary>

```bash
# from a clone
git clone https://github.com/nickohold/quality-loop.git && cd quality-loop && ./install.sh

# private repo, using your GitHub CLI auth
gh api repos/nickohold/quality-loop/contents/bootstrap.sh -H "Accept: application/vnd.github.raw" | bash
```
</details>

Restart Claude Code. Then, in any project:

```
/handout
> migrate the payments service off the deprecated client
```

Uninstall any time with `./uninstall.sh` (removes the hooks and the engine; your
settings.json is otherwise left alone).

## Make it yours

- **Kill-list:** edit `~/.claude/quality-loop/config/bans.txt` (`<kind>::<regex>::<message>`). Start from [`bans.example.txt`](src/config/bans.example.txt).
- **Altitude strictness:** `QL_MAX_LINES` env var (default 14).
- **Scope thresholds:** `QL_MAX_FILES`, `QL_MAX_AGENTS`, `QL_MAX_BG`.
- **Claim vocabulary:** the `HARD`/`SOFT` dicts in `src/gate_claims.py`.

## The flywheel (optional)

`nightly-compile.py` mines each day's transcripts for new corrections and writes
a dated proposal of rule deltas to review — so the gates get smarter over time.
Pure file mining, no LLM cost. Enable with cron:

```bash
crontab -e
# 0 7 * * *  /bin/bash ~/.claude/quality-loop/nightly-compile.sh
```

## How it works under the hood

Every gate reads the session transcript (`.jsonl`) and the working tree's `git
diff`. A "turn" is the slice of agent activity since your last message — the
window in which a claim must have its evidence. `verify.py` runs all gates and
aggregates a `{pass, blocks, warnings}` verdict; the Stop hook turns a failing
verdict into a block. Nothing depends on the model choosing to behave.

```
you ──/handout──▶ agent works ──▶ tries to finish
                                      │
                              Stop hook runs verify.py
                                      │
                   ┌──────────────────┴──────────────────┐
                   ▼                                      ▼
              all gates pass                        a gate blocks
                   │                                      │
              you see the result            agent sees the failure, fixes,
              + an evidence line                  finishes again
```

## Tests

```bash
./test/run-tests.sh
```

Spins up throwaway repos and synthetic transcripts and asserts every gate fires
(and that a clean turn passes). No install required.

## License

MIT — see [LICENSE](LICENSE).
