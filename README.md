# Quality Loop

**A mechanical safety net for handing tasks to an AI coding agent.**

Hand out a task. Be sure the result is up to par — without policing every line
yourself.

Quality Loop is a small set of [Claude Code](https://claude.com/claude-code)
hooks and a skill that put a coding agent's output through **verifiers it cannot
talk its way past**. It was reverse-engineered from months of real transcripts:
find where the agent actually fails, then build a gate exactly there. See
[docs/METHODOLOGY.md](docs/METHODOLOGY.md).

## Contents

- [The problem](#the-problem)
- [What it does](#what-it-does)
  - [Opt-in by design](#opt-in-by-design)
- [Install](#install)
- [Make it yours](#make-it-yours)
  - [The kill-list](#the-kill-list)
  - [Other knobs](#other-knobs)
- [The flywheel (optional)](#the-flywheel-optional)
- [How it works under the hood](#how-it-works-under-the-hood)
- [Tests](#tests)
- [License](#license)

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

Install with one command:

```bash
curl -fsSL https://raw.githubusercontent.com/nickohold/quality-loop/main/bootstrap.sh | bash
```

**Where it installs:** everything lands under your Claude Code config directory,
`~/.claude` (override with `CLAUDE_HOME`):

- `~/.claude/skills/handout/` — the self-contained skill: `SKILL.md` plus the whole engine (gates, verifier, config, state, logs) beside it
- `~/.claude/agents/handout-worker.md` — the isolated worker
- `~/.claude/commands/approve-merge.md` — the merge-approval command
- four hook lines added to `~/.claude/settings.json` (PreToolUse, UserPromptSubmit, Stop, SubagentStop)

(Upgrading from an older layout? The installer migrates a previous
`~/.claude/quality-loop` install — keeping your `bans.txt` and logs — then removes it.)

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

### The kill-list

The "kill-list" is your list of things the agent must never write — patterns you've
had to correct more than once and never want to see again. It lives in one file,
`~/.claude/skills/handout/config/bans.txt`. The bans gate reads it and scans every
diff; if a banned pattern shows up in newly-added lines, the turn is blocked.

Each line is one rule with three parts separated by `::` —

```
kind::pattern-to-match::message shown when it's caught
```

- **kind** — a category tag: `added_comment`, `type_in_class`, `concept`, `dependency`, or `generic`.
- **pattern-to-match** — the text/regex to look for in added code.
- **message** — what the agent sees when it trips, telling it what to do instead.

A concrete example — ban a variable name your team deleted and never wants back:

```
concept::\blegacyClient\b::legacyClient was removed. Use the new client instead.
```

Copy the shipped [`bans.example.txt`](src/config/bans.example.txt) to `bans.txt`
and edit it; the examples there cover the common cases (narrating comments,
misplaced types, unwanted dependencies). You don't need to know regex for simple
cases — a plain word in the pattern slot matches that word.

### Other knobs

- **Altitude strictness:** `QL_MAX_LINES` env var — how long a reply to a *question* can be before it's flagged (default 14 lines).
- **Scope thresholds:** `QL_MAX_FILES` (small-ask diff size), `QL_MAX_AGENTS`, `QL_MAX_BG` (runaway fan-out).
- **Claim vocabulary:** the phrases that demand evidence ("tests pass", "deployed", …) live in the `HARD`/`SOFT` lists in `src/gate_claims.py`.

## The flywheel (optional)

This is how the gates get smarter over time instead of staying frozen at whatever
you set up on day one — and it's **LLM-powered on purpose**.

**What it does, step by step:**

1. Once a day (via cron), `nightly-compile.py` gathers *your* messages from the
   last 24 hours of transcripts — the things you typed, not the agent's. This part
   is cheap and programmatic; it's just collecting the raw material.
2. `nightly-compile.sh` hands that corpus to a headless `claude -p` run that
   **reads and understands** it: what was the agent doing that you kept reacting
   to? It clusters the friction into themes — including new kinds nobody listed in
   advance.
3. For each theme it proposes a concrete, paste-ready rule delta (a `bans.txt`
   line, a new claim phrase, or a ledger/knowledge note) with the evidence quotes,
   and writes it to `~/.claude/skills/handout/logs/proposals-YYYY-MM-DD.md`.
4. **You review it and decide.** It only proposes — it never edits your gates.
   Approving means pasting the line into `bans.txt` yourself.

**Why an LLM and not a keyword search?** Because friction is semantic. A regex can
only surface patterns you already thought to write down — which is precisely what
the flywheel exists to get past. The whole point is to let the model *understand*
the corrections (including the ones you'd never have pre-listed) and turn them into
rules. That costs one Claude call per night; that cost is the feature.

Enable it with cron (note the `PATH` line — cron runs with a bare environment):

```bash
crontab -e
# PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.claude/local
# 0 7 * * *  /bin/bash ~/.claude/skills/handout/nightly-compile.sh
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
