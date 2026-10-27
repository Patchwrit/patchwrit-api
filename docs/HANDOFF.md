# Patchwrit — Muse Code / AI Handoff

**Updated:** 2026-10-26. **Do not assume plans are implemented. Verify Git state.**

## Confirmed at documentation time
- Public GitHub repo `Patchwrit/patchwrit-api` exists.
- `main` was initialized with README.
- Documentation branch `docs/project-foundation` is intended to contain the founding plan.
- **Implemented and verified (2026-10-26):** Phoenix app, Fly Machines client, gated test-machine routes, live create/inspect/start/stop/destroy with cleanup proof. **Not yet implemented:** database schemas for analyses, Oban jobs, OSV scanner, agent logic.
- Second repository `patchwrit-worker` exists separately (owner-confirmed); integration comes in a later milestone.

## Read first
`PROJECT.md` (mission), `ARCHITECTURE.md` (architecture/security), `DECISIONS.md` (accepted choices), `IMPLEMENTATION.md` (milestones), `BACKLOG.md` (priority).

## Immediate assignment for Muse Code

**Goal:** smallest functional Fly Machine lifecycle integration.

1. Inspect repository, branches, existing files; do not overwrite README/docs.
2. Initialize standard Phoenix project in existing repo with PostgreSQL and LiveView (`mix phx.new .` or safe equivalent after checking generator options). Install dependencies and verify application boots locally.
3. Configure `FLY_API_TOKEN` and `FLY_APP_NAME` **outside Git**; create dedicated Fly worker app if needed.
4. Smoke test direct Fly Machines API with minimal permitted image; verify create, inspect, destroy (even on error).
5. Implement a minimal Phoenix Fly client with authenticated outbound calls and strict input constraints; add temporary dev-only or authenticated create/get/delete test routes.
6. Add tests for happy/error responses and cleanup behavior, then conduct a real smoke test.
7. Record Machine IDs, exact commands, observed timing, failures, and verified cleanup. No fabricated benchmarks.
8. Commit only working changes on a feature branch; update this HANDOFF.md and BACKLOG.md.

## Future milestones
Go worker -> authenticated result callback -> persisted Oban analysis -> clone pinned Git SHA -> Maven graph -> OSV -> Meta AI tribunal -> authorized remediation.

## Two test repositories
- https://github.com/spring-petclinic/spring-framework-petclinic
- https://github.com/ryanmcmorrowsnyk/vulnerable-java-app

## Engineering rules
Do not treat docs as implemented code. Phoenix coordinates and persists; Go executes isolated tasks. Treat Maven/plugins and user repositories as untrusted. Machine cleanup state must be separate from analysis status. Never commit tokens/secrets. Pin SHA/image digest for reproducibility. Keep PR changes isolated and tested.

## At end of every session
Update: date, branch/commit SHA, files changed, commands/tests actually run and their results, current working/not-working features, blockers, next smallest testable task. This file is the relay between ChatGPT and Muse Code.

## Session log — 2026-10-26 (Phases 0–5, Fly lifecycle)

**Working:** Phoenix 1.8.7 API boots locally with PostgreSQL; `PatchwritApi.Fly.Client`
(create/list/get/start/stop/delete over Req, allowlist validation, normalized
`{:ok | :error}` results with `duration_ms`); gated `/api/v1/test-machines` routes
(dev-enabled or `TEST_MACHINES_TOKEN` bearer, else 404); live Fly lifecycle verified
end to end. PRs merged: #2 design contract, #3 Fly client, #4 gated routes.

**Live smoke evidence (app `patchwrit-machines`, region `iad`, image busybox, 1 vCPU/256 MB):**
Machine `8715e0f0470998` (`patchwrit-smoke-1`, instance `01M5XXGJQ0P50Z31PXCDADRRWG`).
Create 201 in 1232 ms (state `created`, auto-transitioned to `started`); inspect 200;
stop 200, inspected `stopped`; start 200 (1391 ms), inspected `started`; destroy 200
in 1001 ms. Post-destroy: Phoenix list `[]` and `fly machines list -a patchwrit-machines`
reported no machines — no orphans. Token: 30-day deploy token scoped to the app,
held by the owner and exported only in their shell; never committed.

**Findings / follow-ups:**
- Fly start/stop return no Machine body, so action responses currently render
  null fields; state was proven by follow-up inspect. Candidate fix: enrich
  action responses with a subsequent GET.
- A destroyed Machine id still returns a `destroyed` tombstone on GET briefly;
  list (not GET) is the orphan check.
- Tailwind binary is killed (`Killed: 9`) inside the agent sandbox only; assets
  build normally in a user terminal. API unaffected.

**Tests:** 15 tests, 0 failures (`mix test`); `mix compile --warnings-as-errors` clean.

**Next smallest testable task:** Milestone 2 — `POST /api/v1/analyses` with PostgreSQL
analyses state + Oban job, pinning repo ref to SHA (separate PR). OSS license still pending.
