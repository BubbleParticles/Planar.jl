---
name: update-agents-md
description: Use when distilling lessons learned during a session into AGENTS.md. Categorize each lesson as a Guidelines item (process/workflow) or a Gotchas item (technical pitfalls), then integrate them into the existing numbered lists — never create a separate Lessons Learned section.
---

# Updating AGENTS.md with Lessons Learned

After completing a non-trivial refactoring, migration, or debugging session, lessons were likely learned. AGENTS.md is the right place to capture them so future sessions benefit. This skill explains **where** and **how** to add them.

## Categorization

Not every lesson belongs in the same section. Split them:

| Category | Section | What goes here |
|---|---|---|
| **Process / workflow** | `### Guidelines` (under `## Ccxt to CcxtGateway Migration`) | How to approach work — files to check, commands to run, things to verify before declaring done |
| **Technical pitfalls** | `### Gotchas` (under `## Ccxt to CcxtGateway Migration`) | Language/runtime surprises — `nothing` coercion, JSON parsing gotchas, Julia-specific footguns |

If a lesson could fit both, pick the more specific one. If it's a pure process lesson (e.g., "test with precompilation"), it goes in **Guidelines**. If it's a pure technical trap (e.g., "`get(dict, key, false)` returns `nothing` when value is JSON `null`"), it goes in **Gotchas**.

## Integration rules

1. **Never create a separate Lessons Learned section**. New sections fragment the document and get ignored. Always integrate into the existing numbered lists in `### Guidelines` (items 1–14) or `### Gotchas` (items 1–12).

2. **Append new items to the end of the list**, updating the numbering of all subsequent items. For example, adding a new gotcha after item 12 becomes item 13, and the old item 12 stays as item 12.

3. **Verify the lesson isn't already covered** by grepping the relevant section first (`rg "^[0-9]+\. "` in that section). If a close match exists, extend the existing item rather than duplicating.

4. **Write one sentence per item**, as concise as possible. Front-load the actionable takeaway (what to DO), then add context if needed. Examples:
   - ✅ *"Audit ALL files in the package: grep for Python/ccxt references across every `.jl` file before declaring migration done."*
   - ❌ *"There was once a time when we forgot to check precompile.jl..."*

5. **Do not change the existing review checklist** (`## CCXT Migration Review Checklist`) unless a lesson maps directly to a checklist item. That checklist has its own format and purpose.

## Verification

After writing the updates, tail-read the affected sections to confirm:
- Numbering is sequential (no gaps, no duplicates)
- No lesson is orphaned outside the two allowed sections
- The `Lessons Learned` heading was removed if it existed

## Example: previous edit

Previous session: the Fetch migration revealed 5 lessons. The correct action was:

1. `nothing` from JSON `null` in boolean context → append to **Gotchas** (item 12)
2. Audit ALL files → append to **Guidelines** (item 11)
3. Verify function bodies survive edit surgery → append to **Guidelines** (item 12)
4. Check file include order → append to **Guidelines** (item 13)
5. Test with normal precompilation → append to **Guidelines** (item 14)
