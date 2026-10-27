# Implementation Plan and Contracts — Draft

**Not yet implemented. All paths and shapes are provisional.**

## Milestone 1 — Fly lifecycle
Test Fly Machines API directly with an approved minimal image. Then create **development-only or authenticated** Phoenix routes:
- `POST /api/v1/test-machines` creates a constrained Machine.
- `GET /api/v1/test-machines/:id` inspects state.
- `DELETE /api/v1/test-machines/:id` destroys and confirms removal.

API token is configured only in Phoenix environment/secrets. Never offer unauthenticated public arbitrary VM creation. Success: Machine ID received, command runs, state observed, Machine destroyed, timing collected, no orphan left.

## Milestone 2 — Go worker loop
`POST /api/v1/analyses` (future) accepts public repo, ref and optional JDK/Maven override. Resolve ref to immutable Git SHA, persist analysis, enqueue Oban job. Provision image using scoped control-plane token. Worker receives only minimal analysis info and short-lived callback credential. Worker executes a trivial Go command and reports bounded structured result to deployed reachable Phoenix API (or authenticated polling alternative). Persist callback and independently finalize cleanup.

Example **provisional** request:
```json
{"repository":"https://github.com/spring-petclinic/spring-framework-petclinic","ref":"main","runtime":{"jdk":"auto","maven":"auto"}}
```

Record timestamps for provisioning, worker startup, clone, Maven, callback, cleanup. Persist `analysis_status` and `machine_cleanup_status` separately. Implement timeout, cancellation and orphan reconciliation.

## Milestone 3 — Maven graph / OSV
Clone pinned SHA, detect effective multi-module graph and transitive dependency introduction paths, run selected trusted Maven, query OSV for resolved coordinates+versions, store source IDs, references, graph and error classification. Missing private artifact vs invalid POM vs incompatible JDK are distinct failures.

## Milestone 4 — Tribunal
Investigator gathers file/line imports and invocations; deeper entry-point path when available. Prosecutor and Defender cite structured evidence. Judge may rule actionable, not actionable, inconclusive or human review. Do not present static import detection as proven exploitability.

## Milestone 5 — Remediation
Remediator proposes safe minimal update; bounded build/tests on isolated Machine; authorized scoped GitHub PR creation only with approval and audit log.

## Worker security
No broad secrets in Machine. Untrusted Maven plugin execution must be isolated with bounded CPU/memory/timeout and network policies. Validate OSV inputs and callback payloads. Lock SHA and image digest.
