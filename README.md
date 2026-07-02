# Quality Loop

**The verification stage of a development loop — the part that proves a handed-off
task came back up to par, instead of taking the agent's word for it.**

A sound development loop has three moves: **specify** the task, **hand it off** to a
coding agent, and **verify** what comes back. Quality Loop is the third move, plus
the handoff that makes it enforceable. It is deliberately *one part* of a larger
process — and it is worth being precise about which part.

**What it is:** a small set of [Claude Code](https://claude.com/claude-code) hooks
and a skill that put a coding agent's output through **verifiers it cannot talk its
way past** — claims must cite evidence that actually ran, patterns on your kill-list
cannot land, and irreversible actions are stopped until you approve them. You read
the result once it is provably clean, instead of policing every line yourself.

**What it is not:** it does not specify, design, scope, or plan the work for you. It
assumes a task has already been defined and handed off. The quality of what comes
out is still bounded by the quality of what you put in — hand off a vague task and
the gates faithfully verify a vague result. Specification and design are their own
part of the loop, upstream of this one.

See [docs/METHODOLOGY.md](docs/METHODOLOGY.md) for how the gates were chosen.

## Contents

- [Where this fits in the loop](#where-this-fits-in-the-loop)
- [The dev loop (v2)](#the-dev-loop-v2)
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

## Where this fits in the loop

```
   specify  ─────────▶   hand off   ─────────▶   verify
   the task              to an agent             the result
   (you, a ticket,    ┌──────────────────────────────────┐
    another tool)     │   THIS REPO                       │
                      │   /handout  +  the gates          │
                      └──────────────────────────────────┘
```

This repo owns the boxed part — the handoff and the verification of what comes
back. The **specify** step is a real and equally important part of the loop, but
it lives elsewhere: in your head, a ticket, or another tool. Hand off a sharp
task and the gates guarantee a sharp, evidence-backed result; hand off a vague
one and they faithfully verify a vague one. Quality Loop makes the result
trustworthy; it does not make the task good — that is the part before this.

## The dev loop (v2)

As of 2026-07-02 the package also ships **`/dev-loop`** — a full assembly line
that reuses the gate engine at every station: intake (Linear ticket, GitHub
issue, spec file, or `next`) → repo preflight → flow recon → architect design →
adversarial design review → gated build + independent verifier → targeted QA →
adversarial result review with bounded auto-rework → a three-line human
delivery behind `/approve-merge`. The design reviews run as `/team-review`
(pragmatist vs purist debating to unanimous consensus over SendMessage), and
that consensus is itself mechanically gated by the new `gate_consensus.py`: the
verdict must be a real enum, the debate must have verifiably happened (the
SendMessage count is taken from the transcript, not self-reported), every
accepted finding needs a resolving `path:line`, and `fix-first` with no
findings is rejected. Skills involved: `skill/dev-loop/` (orchestrator + the
worker output contract), `skill/team-review/`, `skill/feature-dev-team/`
(demoted to routing/ownership — its honor-system review loops are retired).
Full architecture walkthrough, with the design decisions and every gate's
rules: [`docs/dev-loop.html`](docs/dev-loop.html).

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

When you run `/handout`, the work goes through **two agents in separate contexts**,
not one. A **builder** makes the change. Then a separate **adversarial verifier** —
in a fresh context that never saw how the builder reasoned — re-runs the builder's
claims itself and tries to break the work. It has no edit tools: it judges, it does
not fix. If it finds a real defect, the task goes back to a fresh builder turn with
those findings, bounded to two rounds before it escalates to you.

The separation is the point. Re-checking work in the same context that produced it
does not catch what that context already talked itself past — so retrying the same
agent in its own growing context is exactly what this avoids. (This is the lesson
the design was rebuilt around; see [docs/METHODOLOGY.md](docs/METHODOLOGY.md).)

Underneath both agents, a set of mechanical gates runs automatically when an agent
tries to finish a turn — the deterministic floor that neither agent can talk past:

| Gate | Blocks the turn when… |
|------|------------------------|
| **claims** | (builder) a "tests pass / fixed / merged / deployed / the DB shows" claim has no matching tool-evidence in the same turn |
| **verdict** | (verifier) the verdict rubber-stamps (a `pass` with no evidence it actually re-ran anything) or rejects vaguely (a `fail` with no concrete defect at `path:line`) |
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
3. It proposes only **macro, agnostic** improvements to the system — a new or
   sharper gate, a general claim phrase — and writes them to
   `~/.claude/skills/handout/logs/proposals-YYYY-MM-DD.md`. The bar is high and
   the **default output is nothing**: most days produce no proposal, and that's the
   preferred result. It will not manufacture suggestions, and it deliberately does
   *not* propose case-specific bans (a particular library or variable) — those are
   yours to add by hand, and they're often wrong later anyway.
4. **You review it and decide.** It only proposes — it never edits your gates.

**Why an LLM and not a keyword search?** Because the judgment that matters here is
semantic: telling a systemic, reusable pattern apart from a one-off frustration,
and knowing when to stay silent. A regex can't do either — it would fire on every
match and surface only what someone already thought to list. The model reads the
day, and most days correctly proposes nothing. That costs one Claude call per
night; that restraint is the feature.

Enable it with cron (note the `PATH` line — cron runs with a bare environment):

```bash
crontab -e
# PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.claude/local
# 0 7 * * *  /bin/bash ~/.claude/skills/handout/nightly-compile.sh
```

## How it works under the hood

Every gate reads the session transcript (`.jsonl`) and the working tree's `git
diff`. A "turn" is the slice of agent activity since the last message — the
window in which a claim must have its evidence. `verify.py` runs the gates for the
current role and aggregates a `{pass, blocks, warnings}` verdict.

The gate set is **role-specific**, and the hook picks the role by what the agent
emitted — a builder ends its turn with an `ql-result` block, a verifier with an
`ql-verdict` block:

- Builder finishes (`SubagentStop`, role `worker`): gated by **claims + bans +
  altitude**. A failing gate sends it back to fix and finish again.
- Verifier finishes (`SubagentStop`, role `verifier`): gated by **verdict** — it
  cannot pass without evidence it re-ran something, nor fail without a concrete
  defect.
- Your report finishes (`Stop`, role `lead`): gated by **bans + altitude** — the
  claims gate is skipped, since the lead relays a result rather than doing the work.

The `scope` gate runs as a warning. The mechanical gates are the floor; the one
judgment the loop asks of the lead is to actually spawn the verifier in a fresh
context. Everything either agent then asserts is gated.

```
you ──/handout──▶ builder works in isolation ──▶ ql-result ──▶ claims/bans gate
                                                                     │ pass
                                                                     ▼
                          fresh verifier (never saw the builder) tries to break it
                                                                     │ ql-verdict
                                                                     ▼
                  ┌──────────────────────────────────────┬──────────────────────┐
                  ▼                                        ▼                      ▼
            verdict: pass                          verdict: fail            gate rejects
                  │                          (re-spawn builder with         the verdict
        result returns to you                findings, max 2 rounds,     (rubber-stamp /
        + an evidence line                   then escalate to you)        vague — retry)
```

## Tests

```bash
./test/run-tests.sh
```

Spins up throwaway repos and synthetic transcripts and asserts every gate fires
(and that a clean turn passes). No install required.

## License

MIT — see [LICENSE](LICENSE).
