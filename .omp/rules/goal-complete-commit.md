---
name: goal-complete-commit
description: "After calling goal complete, always stage and commit changes"
condition: "\"op\":\"complete\""
scope: "tool:goal"
---

After completing the goal, immediately stage and commit all changes. Run `git add -A && git commit -m "<conventional-commit message>"` or verify with `git status` that is clean before yielding. Never end a goal-complete turn without a commit — the repo state must be saved.