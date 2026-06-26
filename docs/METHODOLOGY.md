# How this was built

Quality Loop wasn't designed from first principles. It was **reverse-engineered
from evidence** — the actual record of where an AI coding agent and its operator
rubbed against each other, day after day, for months.

## 1. Mine the friction

Every Claude Code session is logged as a transcript. The operator's own typed
messages — not the assistant's — are where friction surfaces: the corrections,
the "no, not like that," the "I already told you," the "just answer the
question." Those messages are the ground truth of what the agent keeps getting
wrong.

The build started by extracting thousands of those operator messages across
months of work and clustering them into a friction taxonomy.

## 2. The taxonomy

A handful of patterns accounted for the overwhelming majority of friction:

| Rank | Friction | What the agent did |
|------|----------|--------------------|
| 1 | **Unverified claims** | Said "tests pass / fixed / done / merged" without running the check |
| 2 | **Wrong altitude** | Answered a yes/no question with a thesis |
| 3 | **Ignored standing instructions** | Regenerated banned patterns; took unauthorized irreversible actions |
| 4 | **Over-engineering** | Turned a one-line ask into a sprawling build; ran away with agents/processes |
| 5 | **Wrong mental model** | Reasoned from priors instead of reading the ticket/doc/code |

## 3. The key insight

The same failures recurred for months even though the rules against them were
written down and in context the whole time. **Soft corrections don't persist —
the model's generative defaults beat a standing instruction under load.**

So the fix is not more rules. The fix is to move each rule out of prose the model
can override and into a **mechanical gate** that runs at the moment the failure
would reach the human:

- "Don't claim it works without checking" → a gate that scans the turn for
  evidence behind every claim, and blocks if it's missing.
- "Answer at the right altitude" → a linter on the outgoing message.
- "Stop regenerating banned patterns" → a grep of the actual diff against a
  durable kill-list.
- "Never merge without permission" → a hard pre-tool block with a one-shot token.
- "Stop forgetting what we decided" → a ledger re-injected every turn.

## 4. Keep it from nagging

An always-on gate that miscalibrates becomes its own friction. So enforcement is
**opt-in**: the teeth only engage while a task is explicitly being run through
the loop. Outside it, the gates are silent.

## 5. Close the flywheel

A nightly job mines each day's new corrections and proposes additions to the
kill-list and claim vocabulary. Every correction becomes a durable, machine-
checked rule instead of a thing the agent is asked to "remember harder." The
system gets measurably less wrong over time.

---

The deliverable is small on purpose. The value isn't lines of code — it's the
method: **measure where the agent fails, then build a verifier exactly there.**
