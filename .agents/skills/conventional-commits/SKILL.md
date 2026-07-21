# conventional-commits

Trigger: format a commit message / enforce Conventional Commits.

Follow-up: have the user paste the formatted message, or use the output in your own commit.

Reads the current commit message from `.git/COMMIT_EDITMSG` and rewrites it to Conventional Commits format: `type(scope): description`.

Usage:
- Interactive: `conventional-commits.sh` (prompts for type, scope, message)
- Direct: `conventional-commits.sh <message>` (parses and reformats given message)
  - Example: `conventional-commits.sh "$(cat .git/COMMIT_EDITMSG)"`

Notes: For best results, pass the message as an argument.
