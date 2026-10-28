# Phase One — Phoenix API First-Pass Risk Review

**Status:** Preliminary, documentation-only, hackathon-scoped review. **Date:** 2026-10-27. **Reviewed:** `main` via static GitHub source inspection. **No Elixir tests or Fly runtime tests executed by reviewer.**

## Purpose and exit rule

Record concrete risks and make a small set of safety decisions **without blocking the hackathon's Phase Two tribunal work for a comprehensive audit**. This is not a production security certification, a claim of exploitation, or authorization to modify code. Review with Muse Code; distinguish public-demo blockers from post-hackathon backlog. Revisit priorities if deployment exposure changes.

## Strengths observed

- Job-scoped callback bearer tokens are hashed at rest; verification uses constant-time comparison.
- Worker images are selected server-side and must be digest-pinned.
- Analysis and Machine cleanup statuses are represented separately.
- Test Machine endpoints are behind a configuration/token gate.
- Investigator packets conservatively report reachability as `unknown`, with missing-context flags, rather than claiming exploitation from package presence.
- Pinned repository SHA and worker-result provenance are represented in analysis records.

## Findings (static review; proposed priorities)

### P1-A001 — Analysis LiveViews lack an application-user authorization boundary — HIGH for public deployment; accepted limitation for private demo
**Files:** `lib/patchwrit_api_web/router.ex`, `lib/patchwrit_api_web/live/analysis_live/index.ex`.
The browser pipeline handles sessions and CSRF, but no login/authorization plug is present on `/analyses` or `/analyses/:id`. The index lists tracked repositories and permits creating and dispatching analyses. **Risk:** if exposed publicly, visitors could view project data and initiate billable worker jobs. **Hackathon action:** keep access private or put an authenticated ingress gate in front; do not build full multi-tenant accounts solely for the demo. **Later:** user/org ownership and per-action authorization.

### P1-A002 — Callback terminal result and lifecycle transition are non-atomic — HIGH (integrity/concurrency)
**Files:** `lib/patchwrit_api_web/controllers/worker_callback_controller.ex`, `lib/patchwrit_api/analyses.ex`.
The callback reads an analysis, checks its status, updates the result, and then transitions status through a separate update. `transition/2` checks the previously loaded struct, not a database-conditional update. Concurrent callbacks or a failure between writes can leave inconsistent state, and the documented 'first terminal wins' guarantee is not enforced atomically. **Action:** transactional conditional terminal write (e.g., `UPDATE ... WHERE status='running'` with rows-affected check), with one winner and idempotent acknowledgements. Test concurrent duplicate/different callbacks.

### P1-A003 — Machine creation precedes durable Machine-ID persistence — HIGH (resource leakage)
**File:** `lib/patchwrit_api/dispatch.ex` (`dispatch/1`).
After `Client.create_worker_machine` succeeds, the Machine ID is saved in a separate database operation. If that write fails, the fallback cleanup reloads an analysis that may have no Machine ID; the created Machine could remain running. **Action:** compensate immediately with `created.data.id` on persistence failure, plus periodic reconciliation by bounded app/analysis labels. Test injected database failure after successful creation.

### P1-A004 — Callback payload job identity not cross-checked — MEDIUM (contract validation)
**File:** `lib/patchwrit_api_web/controllers/worker_callback_controller.ex`.
The URL analysis ID and token are validated, but `params["job_id"]` is not explicitly checked against the analysis ID. This is not an unauthenticated cross-job write by itself; the job-scoped bearer token remains a strong boundary. **Action:** require matching `job_id`, schema and expected field types; reject malformed payloads.

### P1-A005 — Investigator collapses duplicate coordinates into first provenance path — MEDIUM (evidence integrity)
**File:** `lib/patchwrit_api/tribunal/investigator.ex` (`find_dependency/2`).
`Enum.find` returns the first matching group/artifact/version; packet emits one `introduction_paths` element. Different reactor modules and alternate introduction paths may be lost. **Action:** coordinate with worker W007/W003 to preserve module identity and all observed paths; do not present the first match as exhaustive.

### P1-A006 — Cleanup depends on callback or live dispatch polling; no verified orphan sweeper — MEDIUM (resilience)
**Files:** `lib/patchwrit_api/dispatch.ex`, `lib/patchwrit_api/workers/dispatch_analysis.ex`.
Timeout cleanup occurs in a running Oban dispatch process, but process/node termination or persistence failure can bypass it. No reconciliation worker was identified in the first-pass repository tree. **Action:** periodic Machine inventory reconciliation and persisted dispatch deadlines; treat unknown/orphan cleanup separately from analysis status. **Hackathon:** manual cleanup procedure plus limits may be acceptable if deployment is private and monitored.

### P1-A007 — API Git subprocess inherits process environment and has no explicit command timeout — MEDIUM (operational hardening)
**File:** `lib/patchwrit_api/git.ex`.
`System.cmd("git", ["ls-remote", ...])` inherits the API process environment unless overridden and does not visibly bound execution time. This is a separate process boundary from worker-side Git. **Action:** bounded task/port execution, minimal environment, safe Git config and validated refs. Treat as hardening, not a demonstrated exploit.

### P1-A008 — Investigator worker pattern-matches success and can retry on unexpected errors — LOW/MEDIUM (reliability)
**File:** `lib/patchwrit_api/workers/investigate_analysis.ex`.
`{:ok, _cases} = Investigator.investigate_analysis(analysis)` raises on `{:error, reason}`; Oban retries up to its configured attempts. This may be intentional retry semantics, but errors should be classified and logged without obscuring the underlying failure. **Action:** add explicit error handling/telemetry if operationally useful.

## Hackathon exit criteria (minimal, not a full fix list)

1. **If publicly reachable:** gate analysis pages and run actions behind authentication/ingress controls; otherwise document the private-demo-only boundary.
2. Ensure callback terminal writes are consistent and job-scoped, or explicitly constrain the demo and track the residual risk.
3. Ensure worker Machine creation/cleanup is recoverable, with an operator procedure for orphan Machines.
4. Keep model-provider credentials on the trusted Phoenix side, not inside untrusted Maven/Git worker execution.
5. Preserve `reachability=unknown` until actual source/bytecode evidence supports a stronger conclusion.

**Defer unless needed for demo:** full account system, exhaustive race hardening, generalized multi-tenant policy, production-grade orphan sweeper, comprehensive telemetry. Prioritize the worker's dependency completeness and tribunal evidence demo.

## Validation needed / limits

- No `mix test` or live Fly exercises were run by this reviewer.
- Confirm API callback test coverage, Fly Machine runtime configuration, public ingress, deployment authentication, and idempotent behavior with Muse Code.
- Severity is conditional on actual deployment exposure and may be adjusted after implementation-side evidence.
- The review PR must remain **draft and documentation-only**; no automatic implementation requested.

**Related worker review:** https://github.com/Patchwrit/patchwrit-worker/pull/11

**Phase Two:** review concerns should inform scope, but this document does not define or authorize a Phase Two implementation plan.
