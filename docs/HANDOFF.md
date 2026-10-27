# Patchwrit — Muse Code / AI Handoff

**Updated:** 2026-10-26. **Do not assume plans are implemented. Verify Git state.**

## Confirmed at documentation time
- Public GitHub repo `Patchwrit/patchwrit-api` exists.
- `main` was initialized with README.
- Documentation branch `docs/project-foundation` is intended to contain the founding plan.
- **No Phoenix code, Go worker, database schemas, Fly integration, Oban jobs, OSV scanner, agent logic or tests have been verified implemented.**
- Proposed second repository: `patchwrit-worker` — check whether it has been created.

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
