# Deploy Planar.jl docs to PlanarWebsite (planar.pages.dev/docs)

## Context

`master` HEAD (`f03702ac`) has all CI red:
- `docs` (#85) passes docs-tests #65 fails at *Run link check*: `check-links.sh` reports a "broken external link" to `https://github.com/BubbleParticles/PlanarRegistry.git"`. The repo is actually valid (301→200). Root cause: `check-links.sh` `sed 's/[.,;)]$//'` does NOT strip a trailing `"`, so the Julia string terminator `"` is included in the URL passed to `curl`, producing a 404. Pre-existing false-positive.
- `docs` (#85) — fails at *Build docs*: Documenter `makedocs` error `invalid local link/image: path pointing to a file outside of build directory in docs/src/getting-started/installation.md`. The culprit is the local link `[PACKAGING.md](../../../PACKAGING.md)` (installation.md:86), which escapes the Documenter build root. Pre-existing.
- `run-tests` (#80) — `run-tests` job failed (cause not yet inspected).

The user's explicit ask: "update the docs publishing script, such that instead of deploying them to bubbleparticles website, they are included in the planetary build (planar.pages.dev/docs) which repository is at https://github.com/defnlnotme/planarwebsite".

The new `logo_small.png` (200×109, derived from the new `planar_logo.png` 1381×752) is already regenerated in the working tree.

## Ground-truth findings (verified this session)

- `git remote -v` → origin `https://defnlnotme:ghp_...@github.com/BubbleParticles/Planar.jl`. Operator identity = `defnlnotme`.
- `planarwebsite` default branch = `main` (verified `git ls-remote --symref ... HEAD` → `ref: refs/heads/main`).
- `planarwebsite` is a **Next.js static-export app**: `next.config.ts` `output: 'export'`; `wrangler.toml` `pages_build_output_dir = "./out"`. Cloudflare Pages serves `out/`. No `public/` dir exists in the planetarysite root today.
- Next.js `output: 'export'` copies anything in `public/` into `out/` verbatim, so `public/docs/...` → served at `planar.pages.dev/docs/...`.
- Repo secrets (`gh secret list -R BubbleParticles/Planar.jl`): CODECOV_TOKEN, DOCKERHUB_TOKEN, PLANAR_BINANCE/BITMEX/BYBIT/PHEMEX_SANDBOX_*, PLANAR_CMC_APIKEY. **No deploy token secret for defnlnotme/planarwebsite exists.**
- GitHub `GITHUB_TOKEN` (even `permissions: write-all`) is scoped to the repo the workflow runs in; it cannot push to another repo.
- `docs.yml` deploy currently: checkout `gh-pages` (this repo) into `ghpages/`, `rm -rf ./*`, `cp -r ../docs/build/* .`, `.nojekyll`, commit, `git push origin gh-pages`.
- Link checker (`scripts/validation/check-links.sh`): `grep -o 'https\?://[^)]*'`, then `clean_url=$(echo "$url" | sed 's/[.,;)]$//')`; trailing `"` (Julia string terminator before `))`) is not stripped → curl 404.

## Approach

### Step 1 — Fix docs-tests link check (#65): trailing-quote false positive
- Edit `scripts/validation/check-links.sh` `clean_url=...` sed to also strip a trailing `"` and `'`: `s/[.,;)]$/"; s/'$//`.
- Why checker not docs line: URL is valid; checker is buggy; fixes all code-block `url = "..."` false-positives repo-wide. A URL ending `"` is never valid → safe strip.

### Step 2 — Fix docs build (#85): Documenter cross-reference escape
- Edit `docs/src/getting-started/installation.md:86`: `[PACKAGING.md](../../../PACKAGING.md)` → `[PACKAGING.md](https://github.com/defnlnotme/Planar.jl/blob/main/PACKAGING.md)` (absolute GitHub URL; file exists → 200; Documenter doesn't flag absolute URLs).

### Step 3 — Update deploy to PlanarWebsite (user's explicit request)
- Rewrite "Checkout gh-pages branch" + "Deploy docs" in `.github/workflows/docs.yml`.
- Target: `defnlnotme/planarwebsite`, branch `main`, destination `public/docs/` (→ `out/docs/` → `planar.pages.dev/docs/`). Destination keeps `docs/blueprint.md` intact (public/ is distinct).
- Auth: new secret `PLANARWEBSITE_TOKEN` (operator adds a PAT for cross-repo `main` push).
- Green-safety gate (no secret today → must stay green):
  - Job env `PLANARWEBSITE_TOKEN: ${{ secrets.PLANARWEBSITE_TOKEN }}`.
  - Step "Deploy docs to PlanarWebsite" `if: ${{ env.PLANARWEBSITE_TOKEN != '' }}`: clone planetarysite@main, `rm -rf public/docs && mkdir -p public/docs && cp -r ../docs/build/* public/docs/`, `.nojekyll`, commit as `github-actions[bot]`, `git push origin main`.
  - Keep gh-pages step under `if: ${{ env.PLANARWEBSITE_TOKEN == '' }}` as fallback → deploy stays green today (no regression); planetary path wired but dormant until token added.
- Permissions: keep `permissions: write-all` (gh-pages fallback uses GITHUB_TOKEN); planetary step uses the PAT.

### Step 4 — Inspect run-tests (#80) failure
- `gh run view 31263299612 --json jobs` + `--log`; find failing step before editing. Decide if a code fix is needed. Deploy-script change (Step 3) is independent.
- Run #80: if environmental (ccxt-gateway PyPI/network, secrets unreachable by tooling), do NOT fabricate a code fix — keep Steps 1–3 (green-able) and surface run-tests status.

### Step 5 — Commit + re-watch
- Commit Steps 1–3 (logo_small.png staged). Push to master. Poll `gh run list --branch master`; expect docs (#85) green (Build docs ✓ + gh-pages deploy ✓) and docs-tests (#65) green (link check ✓ + doc tests ✓). Planetary gated step skipped (token absent) → no red.

## Critical files & anchors
- `.github/workflows/docs.yml` 69–85 (gh-pages checkout + Deploy docs).
- `docs/src/getting-started/installation.md:86` (`[PACKAGING.md](../../../PACKAGING.md)`).
- `scripts/validation/check-links.sh` `clean_url=...` line.
- `docs/src/assets/planar_logo.png` (1381×752) → `logo_small.png` (200×109) (done).
- `docs/make.jl` — `Comparison` nav entry already present (728306dc); do not touch.

## Verification
- `bash scripts/validation/check-links.sh` exits 0 → "Link check completed successfully".
- `julia --project=docs docs/test/runtests.jl --verbose` exits 0.
- `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/docs.yml'))"` exits 0.
- `ls docs/src/assets/logo_small.png` → 200×109.
- Post-push: `gh run view <docs-run-id>` "Build docs" ✓ + deploy ✓; `gh run view <docs-tests-run-id>` "Run link check" ✓ + "Run documentation tests" ✓.