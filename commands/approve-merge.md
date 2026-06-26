---
description: One-shot approval for the next merge / push-to-main. Use only when the user has explicitly said to merge.
---

The user has explicitly approved the next merge / push-to-main. Write the one-shot token so `merge-guard.sh` allows exactly one merge command, then proceed with it:

```bash
touch ~/.claude/skills/handout/state/merge-approved
```

The token is consumed on the first merge/push. If more merges are needed later, the user must approve again. Never create this token unless the user said so in their own words this turn.
