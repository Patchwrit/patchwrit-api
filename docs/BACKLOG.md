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
- [ ] Case grouping: group related findings (same package/version/advisory across modules) into tribunal case families before model spend. (See `docs/FUTURE_VISION.md`.)
- [ ] Meta-powered Prosecutor/Defender/Judge reason over actual evidence, acknowledge uncertainty.
- [ ] Remediator proposes evidence-backed update.

## Future vision (post-tribunal)

- [ ] Source Investigator: source-level usage/reachability evidence at the pinned SHA.
- [ ] Librarian: deterministic advisory enrichment (exploit signals, fixed-version and upgrade-distance facts).
- [ ] Context Keeper: human-supplied deployment, exposure, sensitivity, and criticality context per tracked repository.
- [ ] Verifier: test proposed updates in an ephemeral environment and confirm the vulnerable version disappears.
- [ ] Human override/appeal records and case reopening on materially new evidence.
- [ ] Auditor/Historian: case lifecycle and rescan deltas (new, still present, fixed, reintroduced, superseded).
- [ ] Tribunal evaluation set: citation validity, unsupported-claim rate, repeatability, latency, and cost per verdict.
- [ ] Policy Officer: versioned organizational policy (scope/exposure/criticality SLAs, expiring risk acceptances, escalation) enforced deterministically by Phoenix.
- [ ] Conversational interface: chatbot over persisted cases/verdicts/history/policy with cited evidence; actions flow through the same APIs, permissions, and audit trail. Interface, not decision-maker.
- [ ] Surrounding roles, ad hoc as time allows: Intake Concierge (rescan triggers), Portfolio Risk Manager (cross-repo patterns), Benchmark Judge (tribunal self-evaluation), Release Manager (approved-PR shepherding to confirmed fix), Incident Responder (blast-radius mode for major CVEs), Explainer (per-audience verdict translation).

## P1/P2 — Action and delivery
- [ ] Controlled patch test within ephemeral VM.
- [ ] Human-authorized GitHub PR, only if reliable.
- [ ] Readme/setup/license/security review.
- [ ] Three-minute reproducible demo and submission.

## Stretch
Additional JDK versions; bytecode call graphs; deeper policy configuration; more ecosystems and private repositories.
