# Pre-Tribunal Readiness: Dependency Intelligence, Safety, and Evidence

**Status:** Architectural review / prospective gates, not a claim of implementation.
**Recorded:** 2026-10-27.
**Owner:** Patchwrit engineering.
**Relevant code reviewed at:** API `main` commit `80973e9409` and the existing handoff (review findings should be revalidated against current code before implementing).

## Purpose and timing

Patchwrit's Fly Machine lifecycle, custom worker dispatch, authenticated callback, and tracked-repository UI have been established. The upcoming milestone is **Maven dependency graph extraction + OSV vulnerability discovery** (OSV, not “OVS”). This document captures risks that may be tolerable for a trusted smoke run but become consequential once we analyze arbitrary public repositories and then ask AI agents to judge findings.

**Delivery principle:** Don't pause the current discovery milestone to build an enterprise security platform. Finish a small real dependency-to-OSV vertical slice, then satisfy the clearly identified gates below **before general untrusted execution, agent verdicts, or automated remediation**.

## Phases and release gates

| Phase | Deliverable | Required gate |
| --- | --- | --- |
| A: Worker integration (demonstrated) | Digest-pinned image, scoped callback, persisted outcome and Machine cleanup | Keep smoke worker narrow; verify no-orphan cleanup in tested lifecycle |
| B: Maven + OSV prototype | Pinned repo SHA → effective dependency graph → OSV lookup → persisted/displayed findings | Constrain untrusted Maven execution and secrets **before** processing arbitrary repositories; validate results against known examples |
| C: Investigator + tribunal | Dependency provenance, code references, risk arguments, adjudication | Typed evidence, explicit uncertainty and reproducible source citations; fail closed on missing evidence |
| D: Remediation / PR | Proposed update, sandboxed verification, authorized PR | User approval, least-privilege GitHub App/credentials, audit trail, and explicit scope of changes |

## Observations from current code (verify again after new commits)

1. `PatchwritApi.Dispatch.poll/2` sleeps for one second while a single Oban dispatch job remains active until terminal callback or timeout. This is acceptable at low concurrency but occupies an Oban execution slot; server interruption or callback race deserves coverage.
2. `PatchwritApi.Dispatch.worker_attrs/3` passes `PATCHWRIT_CALLBACK_TOKEN` as a Fly Machine environment variable. The token is analysis-scoped and only its SHA-256 hash is stored by Phoenix; however, if later Maven/plugin execution inherits that environment, untrusted build code can read it. **Do not run untrusted Maven with that token or other callback credentials in its environment.**
3. `PatchwritApi.Git.resolve_sha/2` calls `git ls-remote` and chooses the first whitespace-delimited SHA. Ref disambiguation, peeled annotated tags, full 40-character SHA validation and bounded subprocess execution need work before trusting arbitrary input.
4. `PatchwritApi.Dispatch.cleanup/1` records destroyed/failed independently of analysis status—good. However, live sessions have already encountered Machines surviving interrupted server processes, subsequently deleted manually. An independent periodic **orphan reconciler** is needed before wider traffic.
5. `WorkerCallbackController` authenticates using a hash comparison and acknowledges callbacks after terminal status—good baseline. Token *expiration* and atomic/idempotent single-winner transitions are not established merely by hashing the token; test concurrent callbacks, timeout races and cleanup retries.
6. Worker images are selected using a configured digest (good). Worker Machine `env` and resources should be server-validated, not derived from arbitrary user-provided keys.
7. The current UI tracks public GitHub URLs and selects branches. This is an intake surface, not proof the actual remote or ref is safe or immutable; canonicalize and restrict upstream hosts, validate ref values, and pin a commit.

## Gate 1 — Untrusted Maven execution (highest priority)

**Why:** Even `mvn dependency:tree`, `help:effective-pom` or parent resolution may load extensions/plugins and execute attacker-controlled logic. “Not running the application” is not a full security boundary.

Minimum prototype safeguards:
- Treat cloned repository content, Maven scripts/config, project extensions, plugins and custom repositories as hostile. Never blindly run `./mvnw` or download arbitrary wrapper binaries.
- Run Git/Maven in a **separate unprivileged subprocess context** from the worker's callback client. Remove callback token and any other secret from the child environment; set explicit `HOME`, Maven repo location and `JAVA_HOME`. Do not expose cloud/Fly token, DB credentials or GitHub write tokens to Machine.
- Pin worker image digests, trust-approved Maven distributions, resolve/record target commit SHA, and restrict allowed repo protocols and artifact URLs where feasible.
- Enforce process-group termination, timeout, CPU/RAM/disk limits and no privileged container capabilities. Avoid uncontrolled child processes surviving worker termination.
- Apply outbound network restrictions where practical (necessary Maven repositories and OSV); recognize that unrestricted internet egress increases exfiltration risk even when primary secrets are removed.
- Classify errors: clone unavailable, private artifact, unsupported repository, runtime mismatch, Maven resolution failure, OSV unavailable, timeout and policy violation.

**Prototype acceptance:** run a benign repo successfully; attempt a test Maven plugin that reads process environment and verify callback/Fly secrets are absent; force timeouts and verify Machine deletion.

## Gate 2 — Accurate dependency and OSV interpretation

Maven graph and OSV lookup are not yet the AI tribunal. We must distinguish:
- **Declared** dependencies vs **resolved** version selected by Maven, including BOM/parent/dependencyManagement/property/profile effects.
- Direct vs transitive dependencies, their **introduction paths** and Maven module/scope (compile, runtime, provided, test, etc.).
- Artifact identity as Maven `groupId:artifactId:version` / Maven ecosystem, not a package-name guess.
- OSV advisory matches vs **reachability** or practical exploitability. An advisory match alone must never be labeled “confirmed exploitable.”

Required evidence shape (proposal, version contract with worker/API):
```json
{
  "schema_version": 1,
  "source": {
    "repository": "https://github.com/owner/repo",
    "commit_sha": "<40-hex>",
    "module": "root"
  },
  "artifact": {
    "ecosystem": "Maven",
    "group_id": "example.group",
    "artifact_id": "example-artifact",
    "resolved_version": "1.2.3",
    "scope": "compile",
    "direct": false,
    "introduction_paths": [["root:app", "parent:lib", "example.group:example-artifact"]]
  },
  "advisories": [{
    "source": "OSV",
    "id": "OSV-EXAMPLE",
    "aliases": [],
    "references": [],
    "affected": "reported",
    "reachability": "unknown"
  }],
  "collection": {
    "tool": "maven-dependency-plugin",
    "jdk": "17",
    "maven": "3.x",
    "runtime_image_digest": "sha256:...",
    "observed_at": "<timestamp>"
  }
}
```
Example only; field names and types must be mutually agreed and schema-validated. Never synthesize a graph from a list of dependencies. Capture graph extraction warnings/failures. OSV query results must be attributable to an exact artifact and version; support unknown/no-result states rather than equating them with safety.

Acceptance tests: PetClinic resolves effective dependencies on its pinned SHA; intentionally vulnerable example yields a real OSV advisory whose artifact and resolved version can be checked independently; test one transitive introduction path and one no-match case. Record exact command, runtime, commit and API result.

## Gate 3 — Agent evidence standards (the make-or-break)

The agents must reason over **structured facts** rather than over an unverified blob of repository text:
- **Investigator:** establish dependency provenance, imported/referenced symbols with locations, actual invoked methods, and bounded call path from an entry point where evidence permits. Missing call graph = unknown reachability, not safe or exploitable.
- **Prosecutor:** strongest supported actionable-risk case, citing advisory and source evidence.
- **Defender:** challenge version match, scope, dead code, threat prerequisites, false positives and proposed fix.
- **Judge:** render `actionable`, `not_actionable`, `inconclusive`, or `needs_human_review` with reasons. Distinguish model opinions from tool-observed facts.
- **Remediator:** propose minimum-change version upgrade and verification plan; never mutate upstream without approval.

Evidence records should include tool, exact repo SHA, module/path/line or bytecode symbol, artifact version, advisory ID, timestamp, provenance chain and confidence/limitation. Preserve both supporting and contradicting evidence. Include missing-context flags. User-provided source code, comments, README and upstream advisories are **untrusted content**, not instructions to the model or control plane.

**Demo standard:** select one real finding and show its advisory evidence, dependency introduction path, competing agent interpretations, grounded ruling and a feasible remediation. The demo should clearly say whether code-path reachability is proven, suspected or unknown.

## Gate 4 — Reliability and authorization

- Move from long-polling Oban jobs toward a separate dispatch phase and independent timeout/reconciliation mechanism if concurrency or restarts demand it. Don't block the discovery MVP solely for architectural purity.
- Ensure callbacks are idempotent under concurrent delivery: terminal transition, result write and cleanup scheduling must be coordinated/atomic, with safe retry on cleanup failure. Reject payload job IDs that do not match the routed analysis; bound body size at the HTTP layer, not only after JSON decode.
- Add expiry/replay policy for job tokens; revoke or make irrelevant once terminal. Avoid logging token, full env, signed URL, or other secrets.
- Make orphan reconciliation independent of callbacks and Oban worker process lifetime; use persisted Machine ID and cleanup status to enumerate/delete stranded Machines.
- Restrict request origin/allowed hosts and validate all external URL and ref inputs. Recheck HEAD/ref-to-SHA under immutable target workflow.
- Before granting any write access to repository remediator: explicit human approval, short-lived scoped identity, branch/PR scope restriction, audit log, and refusal to push unreviewed modifications.
- Bound request rates, cost and concurrency, and handle Fly 429/5xx with capped backoff and idempotency-aware behavior.

## Ordered near-term actions for Muse Code

1. **Do not interrupt** the current objective: first real Maven effective graph and OSV advisory through the UI and callback.
2. Before invoking untrusted Maven, isolate the Maven child environment from callback credentials, resource-limit it, use pinned/approved tools and define explicit timeouts. Add one secret-exposure regression test.
3. Nail the dependency graph/OSV payload contract and persist result provenance, including unresolved/partial results. Verify on both planned test repositories.
4. Harden Git ref pinning and callback job-ID/expiry behavior before offering arbitrary public use.
5. Add orphan reconciliation and concurrency tests before increasing throughput.
6. Then implement *one* complete evidence-backed Investigator → Prosecutor → Defender → Judge → Remediator suggestion cycle; prioritize explainability and a truthful demo over adding agents by name alone.

## Tracking and handoff

This document is a **risk register and readiness gate**, not a list of shipped features. Link it from the next Muse Code handoff update. For every item, record the implementing PR/commit, actual test evidence, residual risk and owner. Reassess before inviting third parties to analyze arbitrary repositories or granting workers GitHub write authority.

**No changes to existing runtime code are proposed in this documentation PR.**
