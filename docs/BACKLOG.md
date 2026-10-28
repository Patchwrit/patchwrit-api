# Backlog — Prioritized

**Deadline: Nov 4, 2026 at 18:00 Pacific.** Boxes represent *verified work*, not plans.

## P0 — Bootstrap
- [x] Select OSS license. (Apache-2.0; see `LICENSE`.)
- [x] Initialize Phoenix app in existing `patchwrit-api` repository, preserve README/docs.
- [x] Create separate `patchwrit-worker` Go repository. (Exists separately; owner-handled, integrated later.)
- [x] Configure Fly worker app and scoped token. (App `patchwrit-machines`; 30-day deploy token held by owner, env-only.)
- [x] Create/inspect/destroy Machine with direct API, then authenticated Phoenix API.
- [x] Record durations, failures and cleanup evidence. (See HANDOFF.md session log.)

## P0 — Vertical slice
- [x] PostgreSQL analyses state, Oban job.
- [x] Pin SHA and worker image digest.
- [x] Go worker executes and returns scoped authenticated callback.
- [x] Maven transitive dependency graph on PetClinic. (77 dependencies live, analysis `152c8728…`; see HANDOFF.md.)
- [x] OSV scan, persisted findings and minimal view. (PRs #20/#21; findings render on the analysis page.)
- [x] Vulnerable Java example produces meaningful reproducible finding. (DVJA analysis `aedef0a5…`: 93 findings; see HANDOFF.md.)

## P1 — AI
- [ ] Investigator's structured dependency provenance and source evidence.
- [ ] Meta-powered Prosecutor/Defender/Judge reason over actual evidence, acknowledge uncertainty.
- [ ] Remediator proposes evidence-backed update.

## P1/P2 — Action and delivery
- [ ] Controlled patch test within ephemeral VM.
- [ ] Human-authorized GitHub PR, only if reliable.
- [ ] Readme/setup/license/security review.
- [ ] Three-minute reproducible demo and submission.

## Independent Phase One review (2026-10-28) — post-phase backlog

Worker review register: [worker PR #11](https://github.com/Patchwrit/patchwrit-worker/pull/11) (draft, docs-only).
API review register: [API PR #27](https://github.com/Patchwrit/patchwrit-api/pull/27) (draft, docs-only).
Nothing here blocks the tribunal demo on proven single-module repos; all items are tracked as worker issues:

- [ ] Per-module reactor dependency graphs, contract v2 — [worker #12](https://github.com/Patchwrit/patchwrit-worker/issues/12)
- [ ] Explicit incomplete-state instead of silent truncation — [worker #13](https://github.com/Patchwrit/patchwrit-worker/issues/13)
- [ ] Git/Maven subprocess environment allowlist — [worker #14](https://github.com/Patchwrit/patchwrit-worker/issues/14)
- [ ] CI test gate before image publishing — [worker #15](https://github.com/Patchwrit/patchwrit-worker/issues/15)
- [ ] Callback retries + payload-size contract — [worker #16](https://github.com/Patchwrit/patchwrit-worker/issues/16)
- [ ] Non-root worker / subprocess-tree isolation — [worker #17](https://github.com/Patchwrit/patchwrit-worker/issues/17)
- [ ] Worker docs reconciliation — [worker #18](https://github.com/Patchwrit/patchwrit-worker/issues/18)

Agreed rule from the review: a partial dependency graph caps tribunal
verdicts at `needs_human_review` and blocks automated remediation
(deterministic Phoenix policy, not a prompt instruction).

## Stretch
Additional JDK versions; bytecode call graphs; deeper policy configuration; more ecosystems and private repositories.
