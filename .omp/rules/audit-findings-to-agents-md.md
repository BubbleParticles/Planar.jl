---
name: audit-findings-to-agents-md
description: "When an audit finds a bug that should have been prevented, record it as a gotcha/guideline in AGENTS.md and periodically de-duplicate/trim"
condition: ["fix\\((?:Lang|TimeTicks|Misc|Instruments|Instances|Collections|OrderTypes|Ccxt|ExchangeTypes|Exchanges|Fetch|Watchers|Cli|Data|Processing|Strategies|Metrics|Pbar|Stubs|Opt|Plotting|Remote|Engine|Planar|PlanarDev|PlanarOptim|Python|StrategyTools|StrategyStats|FeatureSelection|DownloadTool)\\): .*", "Audit .* found .* bug", "root-cause fix"]
scope: "text"
---

When you fix a bug that *shouldn't have been there* (a recurring class, not a one-off typo), record it in AGENTS.md as a Gotcha or Guideline immediately after committing the fix. Periodically maintain AGENTS.md: de-duplicate overlapping entries, merge related ones, and if the list grows too large keep the most important gotchas/guidelines inline and move the rest to a subfile referenced from AGENTS.md. This turns each audit into durable prevention, not just a one-time patch.