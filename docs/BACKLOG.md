# Backlog — Prioritized

**Deadline: Nov 4, 2026 at 18:00 Pacific.** Boxes represent *verified work*, not plans.

## P0 — Bootstrap
- [ ] Select OSS license.
- [x] Initialize Phoenix app in existing `patchwrit-api` repository, preserve README/docs.
- [x] Create separate `patchwrit-worker` Go repository. (Exists separately; owner-handled, integrated later.)
- [x] Configure Fly worker app and scoped token. (App `patchwrit-machines`; 30-day deploy token held by owner, env-only.)
- [x] Create/inspect/destroy Machine with direct API, then authenticated Phoenix API.
- [x] Record durations, failures and cleanup evidence. (See HANDOFF.md session log.)

## P0 — Vertical slice
- [x] PostgreSQL analyses state, Oban job.
- [x] Pin SHA and worker image digest.
- [x] Go worker executes and returns scoped authenticated callback.
- [ ] Maven transitive dependency graph on PetClinic.
- [ ] OSV scan, persisted findings and minimal view.
- [ ] Vulnerable Java example produces meaningful reproducible finding.

## P1 — AI
- [ ] Investigator's structured dependency provenance and source evidence.
- [ ] Meta-powered Prosecutor/Defender/Judge reason over actual evidence, acknowledge uncertainty.
- [ ] Remediator proposes evidence-backed update.

## P1/P2 — Action and delivery
- [ ] Controlled patch test within ephemeral VM.
- [ ] Human-authorized GitHub PR, only if reliable.
- [ ] Readme/setup/license/security review.
- [ ] Three-minute reproducible demo and submission.

## Stretch
Additional JDK versions; bytecode call graphs; deeper policy configuration; more ecosystems and private repositories.
