# Analysis Contract — API ⇄ Worker (W1)

**Status:** Agreed design (W1). No analyses, UI, dispatch, or Go code implemented yet.
This document is canonical. The worker repo carries a short mirror
(`patchwrit-worker/docs/ANALYSIS_CONTRACT.md`); if they disagree, this file wins
and the mirror must be fixed.

## Flow

```
LiveView form ──> Analysis (queued) ──> Oban dispatch job
                                              │ pin ref -> SHA
                                              v
                                    Fly Machine (worker image)
                                              │ clone SHA, run checks
                                              v
                          POST /api/v1/worker-callbacks/:analysis_id
                                              │
                                              v
                          result persisted ──> Machine destroyed
```

Phoenix owns state, provisioning, persistence, and cleanup. The worker owns
bounded execution inside the Machine and can never delete its own VM.

## Analysis record (persisted by Phoenix, W3)

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUID | Also the `job_id` given to the worker |
| `repository_url` | string | Public GitHub URL, validated on create |
| `requested_ref` | string | Branch/tag/ref as entered; default `HEAD` |
| `resolved_sha` | string | Immutable commit pinned by Phoenix before dispatch |
| `status` | enum | See lifecycle below |
| `machine_id` | string, null | Fly Machine id once provisioned |
| `machine_cleanup_status` | enum | `pending → destroyed \| failed`, independent of `status` |
| `worker_image` | string | Image reference used, pinned to a digest at dispatch |
| `runtime` | map (JSONB) | `{"jdk": "auto"\|"17"\|"21", "maven": "auto"}` selections/overrides |
| `callback_token_hash` | string | Hash of the job-scoped callback token; plaintext never stored |
| `result` | map (JSONB), null | Raw worker callback payload, kept for provenance |
| `error_category` / `error_message` | string, null | Terminal failure summary |
| `timings` | map (JSONB) | Stage durations (provision, clone, execution, callback, cleanup) |

### Analysis lifecycle

`queued → provisioning → running → completed | failed | cancelled`

- `queued`: persisted, waiting for the dispatch job.
- `provisioning`: ref pinned, Machine being created.
- `running`: worker executing; Phoenix has a Machine id.
- Terminal states are written once. A late or duplicate callback never
  resurrects a terminal Analysis.

### Cleanup lifecycle (independent)

`pending → destroyed | failed`

Cleanup runs whatever the analysis outcome — success, worker failure, lost
callback, or timeout. `failed` cleanup is surfaced for reconciliation, never
hidden inside a "successful" analysis.

## Worker input (Phoenix → Machine)

Delivered as Machine environment variables at creation time. Secrets are
never placed in command-line arguments or logs.

| Variable | Meaning |
| --- | --- |
| `PATCHWRIT_JOB_ID` | Analysis UUID |
| `PATCHWRIT_REPOSITORY_URL` | Public repository URL |
| `PATCHWRIT_PINNED_SHA` | Immutable commit to clone (Phoenix pins; worker trusts and verifies the checkout matches) |
| `PATCHWRIT_CALLBACK_URL` | Full callback URL for this job |
| `PATCHWRIT_CALLBACK_TOKEN` | Short-lived, job-scoped bearer token (plaintext exists only here and in the dispatching process) |
| `PATCHWRIT_TIMEOUT_SECONDS` | Hard execution budget; worker must self-terminate inside it |
| `PATCHWRIT_JDK` / `PATCHWRIT_MAVEN` | Selected versions or `auto` |

Only the callback token is sensitive. No Fly control-plane token, database
secret, or GitHub write credential is ever placed in a Machine.

## Worker output (Worker → Phoenix callback)

`POST /api/v1/worker-callbacks/:analysis_id` with
`Authorization: Bearer <PATCHWRIT_CALLBACK_TOKEN>`, JSON body, bounded
(max 256 KB; Phoenix rejects larger payloads).

```json
{
  "schema_version": 1,
  "job_id": "analysis-uuid",
  "status": "completed",
  "worker_version": "0.1.0",
  "environment": {
    "go_version": "go1.26.2",
    "git_version": "2.x",
    "java_version": null,
    "maven_version": null
  },
  "timings_ms": {"execution": 0},
  "errors": []
}
```

- `status` is the *worker job* outcome: `completed | failed`. Phoenix maps it
  onto the Analysis lifecycle; the two enums are deliberately not identical.
- `errors[]` entries are `{"category": "...", "message": "..."}` with
  categories: `toolchain_missing`, `clone_failed`, `invalid_pom`,
  `private_artifact`, `jdk_incompatible`, `network`, `timeout`, `internal`.
  Distinct categories are a requirement, not polish (see `ARCHITECTURE.md`).
- The callback is idempotent: Phoenix stores the first terminal result and
  acknowledges duplicates with `200` without changing the record.
- The worker must still exit 0 on a successfully *reported* failure
  (`status: "failed"` sent, then exit 0); a non-zero exit means the worker
  itself crashed and Phoenix will classify from exit/timeout evidence.

## Images and registry

- Public repos publish to **GHCR** (`ghcr.io/patchwrit/patchwrit-worker`);
  public images pull without credentials and public-repo CI is free.
- **Smoke image (W2):** one small image with the Go worker binary only.
- **JDK images (W6 prep):** prebuilt variants such as
  `patchwrit-worker:jdk17` and `patchwrit-worker:jdk21`, each containing the
  worker binary + git + JDK + Maven 3.9.x. Phoenix *selects* the image per
  analysis; images are never built per request.
- Phoenix records and uses the image **digest**, not a floating tag, at
  dispatch time.

## Reachability (development)

Fly Machines cannot reach a developer laptop's `localhost`. Therefore:

- Automated tests always stub the callback; no test needs Fly or a tunnel.
- Live local runs require Phoenix to be publicly reachable — an HTTPS
  tunnel to the local server for development, or a deployed Phoenix in
  production. `PATCHWRIT_CALLBACK_BASE_URL` config decides which; the
  callback URL given to the worker is built from it.
- If no reachable base URL is configured, dispatch must refuse to start
  rather than strand a Machine waiting to report.

## Sequencing

W2 worker smoke binary → W3 analyses DB → W4 LiveView UI → W5 Oban dispatch
+ callback + live smoke → W6 Maven/OSV. Each step is one PR in one repo.
