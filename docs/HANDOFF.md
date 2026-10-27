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

## Session log — 2026-10-26 (W1–W5, worker integration)

**Working:** joint analysis contract in both repos; Go worker smoke binary with
callback delivery; analyses DB + lifecycle context; LiveView submit/list/detail UI;
Oban dispatch (pin ref→SHA via `git ls-remote`, job-scoped callback token hashed at
rest, worker Machine from digest-pinned image, timeout + failure cleanup);
authenticated idempotent worker callback persisting the raw result and destroying
the Machine. Worker images publish to GHCR on merge; live runs used the Fly
registry (`registry.fly.io/patchwrit-machines`) because GHCR package visibility
required owner-admin action.

**Live end-to-end proof (2026-10-27):** analysis `2d40b6ba-27c0-4e7c-8699-f3a3cd845211`
(PetClinic `main`): SHA pinned to `cf392920cdbe9cd07689f1f4b603271940bac957`, Machine
`811169dc4e1e08` ran worker image `…@sha256:d26ab32e…`, callback persisted
(`worker_version 0.1.0`, schema 1), analysis `completed`, cleanup `destroyed`,
`fly machines list` empty afterward. Callback reached local Phoenix through a
Cloudflare quick tunnel (`CALLBACK_BASE_URL`).

**Failures that taught us (all cleaned up, honestly recorded in the DB):**
- arm64 image on amd64 Fly VMs: crash-loop `exit_code=-1`. Build `--platform linux/amd64`.
- `scratch` runtime has no CA roots: callback failed `x509` unknown authority.
  Fixed by alpine + `ca-certificates` (worker PR #5).
- Two runs interrupted by server restarts left stopped Machines; each was deleted
  through the test-machines API and its analysis reconciled to `failed/destroyed`
  with an explanatory error. Follow-up worth building: an orphan reconciler and
  a Machine `restart: no` policy for one-shot jobs.

**Tests:** API 30 tests, 0 failures; worker `go test ./...` green.

**Next:** merge worker PR #5 (CA certs) so GHCR publishes the fixed runtime; then
W6 — JDK worker images with clone + Maven graph + OSV. OSS license still pending.

## Session log — 2026-10-27 (tracked repositories + JDK 17 toolchain)

**Working:** tracked repositories (API PR #13): users add a public GitHub repo on the
one-page console, branches load from the GitHub API on entry with the default branch
preselected, and the user manually specifies JDK 17 or 21. Each run snapshots repo
URL, branch, and JDK into the Analysis; dispatch maps the snapshot to a digest-pinned
worker image (`WORKER_IMAGE_JDK17` etc.), failing closed when unconfigured.

**JDK 17 image (worker PR #6):** `Dockerfile.jdk17` — Go worker + Git + OpenJDK 17 +
Maven 3.9.11 on a digest-pinned Maven/Temurin amd64 runtime. GHCR published
`ghcr.io/patchwrit/patchwrit-worker@sha256:c455e1fe055c35d8697f73ff66dcb3b7cb1dac1408a7701c2c16cf84c6983084`
(linux/amd64 manifest).

**Live proof:** analysis `8b7630d6-3307-45db-828f-0407131ce27f` (tracked PetClinic,
branch `main`, JDK 17): pinned SHA `cf392920cdbe9cd07689f1f4b603271940bac957`,
callback reported Git 2.43.0, OpenJDK 17.0.17, Maven 3.9.11; analysis `completed`,
cleanup `destroyed`, `fly machines list` empty afterward. The worker does not yet
clone the repo or resolve Maven dependencies — toolchain presence only.

**Next:** W6c — worker clones the pinned SHA inside the JDK image, verifies HEAD,
and reports POM/module structure. Then Maven dependency graph, then OSV findings.
OSS license still pending.

## Session log — 2026-10-27 (W6c clone + POM inventory)

**Working:** worker PR #7 and API PR #16. When repository input is present, the Go
worker clones it, checks out the pinned SHA, verifies `HEAD` equals the pin, and
reports `repository` evidence (checked-out SHA, POM files, root modules) in the
callback. Clone failures are reported results (`clone_failed`/`timeout`), never
silent crashes. The analysis page renders a Repository checkout section.

**Live proof:** analysis `6ac188ac-3bd0-464e-8ad2-a406b1199a64` on image
`ghcr.io/patchwrit/patchwrit-worker@sha256:4371206a…`: inside the Fly Machine the
worker cloned PetClinic, `checked_out_sha` == pinned `cf392920…`, `pom_files`
== `["pom.xml"]`; analysis `completed`, cleanup `destroyed`, Fly app empty after.

**Next:** W6d Maven dependency graph. Read `docs/PRE_TRIBUNAL_READINESS.md` first:
in particular, untrusted Maven/plugin execution must not inherit
`PATCHWRIT_CALLBACK_TOKEN` in its environment — scrub child-process env in the
worker (or poll for results) before running `mvn` on arbitrary repositories.
OSS license still pending.
