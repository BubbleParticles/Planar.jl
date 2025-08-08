---
trigger: model_decision
description: strategy, framework and tests codegen
globs:
---
Always use the actual state or value from the relevant object, not a default or global value, when handling existing entities.
If an action’s precondition (like minimum size) is not met but an entity is still active, perform the appropriate cleanup (e.g., close the position) instead of skipping the action.
Don't write temporary tests files to check if the code you applied works, running the julia repl to check small modifications it too slow, instead simply review the code for potential bugs and discrepancies.
Remember to check that the types and functions that you use are available in the current environment.