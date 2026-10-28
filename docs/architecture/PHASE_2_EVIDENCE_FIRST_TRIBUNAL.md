# Patchwrit — Phase Two: Evidence-First Tribunal Architecture

**Status:** Proposed architecture for review with Muse Code; not implementation authorization  
**Date:** 2026-10-27  
**Scope:** Balanced hackathon milestone, designed to evolve into a maintainable product  
**Repositories:** Patchwrit/patchwrit-api (Phoenix/Elixir), Patchwrit/patchwrit-worker (Go)

## 1. Executive decision

Phase Two turns Patchwrit from a Maven dependency inventory and OSV finding pipeline into an **evidence-backed vulnerability assessment system**. The system assembles a durable dossier, runs an adversarial tribunal (Prosecutor, Defender, Judge), records a structured verdict with cited evidence and uncertainty, and enforces safety constraints in deterministic Phoenix code.

The tribunal's immediate purpose is to recommend **whether a finding merits remediation or human investigation**. It must distinguish three questions:

1. **Presence and relevance:** Is the affected dependency/version present, and is there evidence the application uses relevant functionality?
2. **Exploitability:** Is there evidence that attacker-controlled input can reach the vulnerable behavior under the advisory's conditions? Usually **unknown** at this stage.
3. **Remediation priority:** Given severity, exposure evidence, uncertainty, and upgrade options, what action is justified?

A model's persuasive prose must never be mistaken for proof of reachability or exploitability.

## 2. Current Phase One foundation and dependency

- Phoenix API, PostgreSQL, Oban, Fly Machine orchestration, OSV findings, and an initial deterministic Investigator are already present.
- Go worker clones pinned public GitHub SHAs and runs Maven dependency resolution, then calls back to Phoenix.
- The worker review confirmed a **multi-module reactor correctness defect**: one absolute dependency-tree.json output path is overwritten by subsequent modules, leaving the final module's graph despite Maven success.
- Graph completeness and provenance must be represented explicitly before the tribunal treats results as comprehensive.

**Related reviews:**
- Worker: https://github.com/Patchwrit/patchwrit-worker/pull/11
- API: https://github.com/Patchwrit/patchwrit-api/pull/27
- API schema/provenance backlog: https://github.com/Patchwrit/patchwrit-api/issues/32

**Pragmatic fallback:** If full reactor support cannot be delivered promptly, explicitly detect and reject unsupported multi-module layouts rather than silently claiming complete coverage. A known single-module repository can still support a truthful tribunal demonstration.

## 3. Architectural responsibilities

~~~text
GitHub repository + pinned commit SHA
               |
               v
Disposable Go worker (untrusted build boundary)
  - bounded checkout and Maven execution
  - dependency trees, module/POM provenance
  - completeness / structured errors
               |
      scoped callback (schema v2)
               v
Phoenix API (trusted orchestration boundary)
  - validate and persist worker evidence
  - OSV findings and evidence dossiers
  - Oban tribunal jobs and model-provider calls
  - schema validation, deterministic policy gates
  - audit trail, verdict presentation
               |
               v
PostgreSQL (versioned, durable records)
~~~

**Boundary rules:** Keep model-provider API keys, Fly API tokens, and general-purpose GitHub credentials on the trusted Phoenix side. Do not pass them to worker-side Maven/Git subprocesses. Worker outputs and repository text are **untrusted evidence**, not instructions to the model or Phoenix. Limit payload sizes, token budgets, job duration, and retry counts. Avoid making arbitrary model-generated commands executable.

## 4. Evidence contract: schema version 2

Adopt a **versioned worker/API contract**. Both sides must explicitly recognize v2; an absent graph block or unknown schema must **not** default to complete=true.

Proposed shape (illustrative, to be refined with Muse):

~~~json
{
  "schema_version": 2,
  "job_id": "analysis-uuid",
  "repository": "https://github.com/example/project",
  "commit_sha": "full-pinned-sha",
  "status": "completed",
  "graph": {
    "complete": true,
    "modules_total": 2,
    "modules_resolved": 2,
    "modules_failed": [],
    "dependency_limit_hit": false,
    "pom_inventory_truncated": false
  },
  "dependencies": [
    {
      "group_id": "org.example",
      "artifact_id": "library",
      "version": "1.2.3",
      "scope": "compile",
      "module": "org.example:app",
      "pom_path": "app/pom.xml",
      "introduced_via": ["org.example:app", "org.example:library"]
    }
  ]
}
~~~

**Semantics to settle:** modules_total counts unique effective reactor modules (not every POM file); modules_resolved counts uniquely verified parsed trees; module identity should include relative POM path to disambiguate duplicate coordinates. The contract should preserve **multiple introduction paths**, not just one introduced_via path; a production schema may use introduction_paths: [[...], [...]] instead. Keep POM inventory truncation distinct from dependency graph completeness. If at least one module resolves but others fail, record an explicit **partial** result; if none resolve, record categorized failure. All observed dependencies can still be OSV-scanned, with coverage clearly marked partial.

The callback must verify job_id against the route's analysis ID and its job-scoped token. Define version negotiation, limits, and invalid-payload behavior before coding.

## 5. Dossier and tribunal roles

### Investigator — deterministic first

For each vulnerability finding, create an immutable or versioned **evidence dossier** containing:
- Analysis ID, repository URL, pinned SHA, module/POM identity.
- Vulnerable dependency coordinates, version, scope, and all observed introduction paths.
- OSV identifier(s), affected ranges, advisory summary, and references with provenance.
- Graph completeness and known collection failures.
- Any source-level references, call sites, or reachability evidence **only when actually collected**.
- Explicit missing_context and reachability: unknown unless stronger evidence exists.

Do not equate package presence, import, invocation, reachable call path, and exploitability. These are separate evidence levels.

### Prosecutor — model-assisted

Construct the strongest **evidence-supported** argument that the finding deserves attention or remediation. Reference dossier evidence IDs. Separate established facts from plausible but unproven risk scenarios.

### Defender — model-assisted

Challenge unsupported assumptions, identify missing exploit preconditions, consider scope or exposure limitations, and assess whether the available dossier supports a lower priority. Do not invent mitigations or claim safety without evidence.

### Judge — model-assisted recommendation, bounded by policy

Compare both arguments and return a **structured recommendation**, evidence references, unresolved questions, and confidence/uncertainty rationale. The Judge does **not** independently grant permission to automate a change.

**Implementation note:** Four logical roles do not require four models or microservices. The Investigator can remain deterministic; Prosecutor, Defender, and Judge can use the same provider through distinct, structured calls orchestrated by Phoenix/Oban.

## 6. Structured output and deterministic policy

Proposed verdict envelope (illustrative):

~~~json
{
  "finding_id": "finding-id",
  "dossier_version": 1,
  "presence": "confirmed",
  "application_relevance": "unknown",
  "exploitability": "unknown",
  "remediation_priority": "needs_human_review",
  "recommended_action": "investigate_usage",
  "supporting_evidence_ids": ["ev-1", "ev-2"],
  "counter_evidence_ids": [],
  "missing_context": ["source_call_path_not_analyzed"],
  "rationale": "..."
}
~~~

The exact enum names should be settled with Muse, but the meanings must be unambiguous. A high CVSS score alone does not establish application exploitability.

**Non-negotiable Phoenix policy gate:**
- If graph.complete=false or graph completeness is unknown, **cap automated verdicts at needs_human_review** and prohibit autonomous remediation or PR creation. The cap forces `recommendation=needs_human_review` even when the Judge suggests dismissal or remediation — but it must **not** be read as evidence of low severity, non-use, or non-exploitability; it records that the evidence is incomplete, nothing more.
- Reject malformed outputs, fabricated evidence IDs, and references to evidence outside the dossier.
- Model-generated confidence cannot override deterministic incompleteness rules.
- In this milestone, **no automatic code changes or PRs** even for complete graphs; the output is advisory.
- Treat repository source, POM text, advisory text, and model outputs as untrusted content; explicitly resist prompt injection in retrieved evidence.

## 7. Durable workflow and lifecycle

Suggested sequence:

1. Worker callback validates schema v2 and persists graph provenance/completeness.
2. OSV scanning produces versioned findings over the observed graph.
3. Phoenix assembles a dossier per finding and records an evidence snapshot/version. **Retention requirement (audit trail):** a tribunal run must retain the *actual immutable evidence snapshot* it reasoned over — not only a version number or hash. Rescans can delete findings and cascade cases, so a decided verdict and the exact dossier behind it must remain readable afterward. Implementation may use an immutable snapshot column/table or a separately retained run record; choose the smallest durable design.
4. Oban schedules tribunal execution for selected findings.
5. Prosecutor and Defender produce separately persisted, validated arguments.
6. Judge produces a structured recommendation citing dossier evidence.
7. Phoenix validates the output and applies deterministic policy constraints.
8. UI displays the final recommendation, role arguments, evidence links, and missing context.

Record status (queued, running, completed, needs_human_review, failed as appropriate), attempts, model/provider/version, prompt template version, dossier version, timestamps, and categorized failures. Make retries idempotent and avoid duplicate tribunal records. Set timeouts and per-analysis cost/token ceilings.

**Important:** Existing Phoenix entities and Oban jobs should be reused where practical; this document does not prescribe new tables without first inspecting the current schema.

## 8. User interface and demo narrative

A single analysis page should show:
- Repository, pinned SHA, analysis status and graph completeness.
- OSV findings and affected dependency/module paths.
- Evidence dossier with source/advisory citations and unknowns.
- Prosecutor argument, Defender argument, Judge recommendation.
- Explicit banner for partial graphs and the enforced human-review cap.
- A traceable record of the reasoning inputs and structured outputs.

**Suggested demonstration:** A known single-module vulnerable Maven app → resolved dependency → OSV finding → dossier → prosecution and defense → bounded verdict. Optionally demonstrate a two-module fixture and show that completeness/provenance is correctly handled or explicitly rejected rather than silently misrepresented.

## 9. Balanced milestone acceptance criteria

- [ ] Worker/API agree on v2 completeness and module provenance (or explicit unsupported-reactor failure).
- [ ] Dossier references a pinned SHA, specific finding, module, and versioned evidence.
- [ ] Prosecutor and Defender provide distinct, structured, evidence-cited arguments.
- [ ] Judge returns a schema-validated recommendation with uncertainty.
- [ ] Deterministic policy prevents overconfident verdicts and automated action on partial evidence.
- [ ] Oban workflow persists each stage and handles retries/failures without duplicate conclusions.
- [ ] Phoenix UI exposes provenance, missing context, and tribunal outputs.
- [ ] Tests cover valid flow, partial graph, fabricated citation, malformed model output, and repeated job delivery.
- [ ] A complete end-to-end demo succeeds on a known repository.

## 10. Deliberately out of scope

- Autonomous code edits, dependency upgrade PRs, or auto-merge.
- Comprehensive Java source/bytecode call-graph analysis, dynamic exploit validation, or definitive reachability claims.
- A multi-provider ensemble, elaborate multi-round debates, or separate services for each role.
- Full user accounts and multi-tenant authorization solely to finish the local hackathon demo.
- Production-grade machine reconciliation and exhaustive security hardening (tracked in GitHub Issues).

These are future phases or backlog items, not implied deliverables for Phase Two.

## 11. Decisions requested from Muse Code

Please respond **before implementing** with:

1. Which existing Phoenix schemas, modules, and Oban jobs can support the dossier and tribunal with minimal changes?
2. Proposed final schema v2 payload and exact completeness/partial semantics, coordinated with worker changes.
3. Structured Prosecutor/Defender/Judge JSON contracts and evidence citation validation approach.
4. Proposed state transitions, retry/idempotency policy, and model cost limits.
5. Smallest viable end-to-end implementation sequence and rough risk assessment.
6. Any material disagreement with the deterministic policy gate or separation of relevance, exploitability, and remediation priority.

**Request:** Architecture feedback and a minimal implementation plan only. Do not start implementation based solely on this document.

## 12. Deployment context

Phoenix currently runs locally; a temporary cloudflared tunnel is used for Fly worker callbacks, **not as intended production ingress**. A custom domain is not required for deployment; Fly's default *.fly.dev hostname may be used later. Before any public hosting, protect browser/LiveView access and billable analysis actions independently from the worker callback route. See API issue [#29](https://github.com/Patchwrit/patchwrit-api/issues/29).
