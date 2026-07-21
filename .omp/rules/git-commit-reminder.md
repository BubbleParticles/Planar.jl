---
name: git-commit-reminder
description: "Remind to stage and commit changes between heavy modifications"
condition: "(?:bash.*git\\s+commit|(?:done|finished|completed|done\\s+with).*(?:changes|edits|modifications|files))"
scope: ["tool:bash", "text"]
---

Remember to stage and commit changes between heavy modifications. Run `git add -A && git commit -m "descriptive message"` to maintain a clean git history and avoid losing track of changes.