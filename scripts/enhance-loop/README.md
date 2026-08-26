# Enhance Loop

Loop: audit → triage → fix (≤1 pillar per PR) → verify (baselines, Pkg.test, pytest, coverage ≥80%) → report (reports/enhance-loop/STATUS.md)

Run: `julia --project=scripts/enhance-loop scripts/enhance-loop/run.jl [pillar]`
Pillars: ergonomics, perf, security, maintainability

Artifacts: `reports/enhance-loop/<pillar>-report.md` + baseline `reports/enhance-loop-baseline.json`

Schedule: `.github/workflows/enhance-loop.yml` manual dispatch + weekly cron uploads reports as artifact.
