# Fly Machines API Integration — Design Contract

**Status:** Design only (Phase 2). No Fly client or test-machine routes are implemented yet.

## Purpose

Prove the smallest reliable Fly Machine lifecycle from Phoenix before any
analysis, Maven, OSV, or agent work:

create -> list/inspect -> start/stop -> destroy -> confirm no orphan remains.

This supports Milestone 1 in `IMPLEMENTATION.md`.

## Non-goals

- Persisting analyses or Machine records in PostgreSQL.
- Oban jobs or background reconciliation.
- Running the Go worker, Maven, OSV, or a user repository.
- Creating GitHub PRs or mutating any analyzed repository.
- Exposing unauthenticated public VM creation.

Those arrive in later phases on top of this contract.

## Upstream: Fly Machines API

- Public base URL: `https://api.machines.dev/v1`
- Authentication: `Authorization: Bearer <FLY_API_TOKEN>`
- Every Machine belongs to one Fly App, named by `FLY_APP_NAME`.
- Official client libraries: Fly documents `fly-go` for Go and recommends
  generating other clients from its OpenAPI spec. There is no official
  Elixir Machines client, so Phoenix will call the REST API directly with
  `Req` (already a dependency in `mix.exs`).
- Fly Sprites has an Elixir package, but Sprites is a separate API/product
  and must not be confused with the Machines API.
- Rate limits are per action: roughly 1 request/second for create, start,
  and stop, with short bursts. The client must surface `429`/retry timing
  rather than hammering the API.

## Local Phoenix API

These routes are the only surface this design adds:

| Action | Route |
| --- | --- |
| Create | `POST /api/v1/test-machines` |
| List | `GET /api/v1/test-machines` |
| Inspect | `GET /api/v1/test-machines/:id` |
| Start | `POST /api/v1/test-machines/:id/start` |
| Stop | `POST /api/v1/test-machines/:id/stop` |
| Destroy | `DELETE /api/v1/test-machines/:id` |

### Create request

Clients may send only `image`, `region`, and `name`. Everything else is
fixed server-side.

```json
{
  "image": "busybox",
  "region": "iad",
  "name": "patchwrit-test-1"
}
```

Provisional defaults, to be verified live in Phase 5 before being treated
as correct:

- `image`: a server-side allowlist key such as `busybox`, mapped to a full
  image reference. Raw arbitrary image strings are rejected.
- `region`: `iad` unless a three-letter region code is supplied.
- Size: shared CPU, 1 vCPU, 256 MB memory.
- Init command: a long sleep so the Machine stays inspectable until we
  destroy it.

### Responses

- Success: Fly's Machine JSON, trimmed to stable fields (`id`, `name`,
  `state`, `region`, plus the created config echo), with an added
  `duration_ms` measured around the upstream call.
- Error: `{"error": {"status": <int>, "message": "<string>"}}`.
  Tokens and full upstream headers are never returned.

Indicative mapping (final mapping is a Phase 4 decision):

- Missing Fly configuration -> `503`
- Invalid local input -> `422`, with no upstream call made
- Upstream auth/app errors (`401`/`403`/`404`) -> surfaced, sanitized
- Upstream `5xx`/timeouts -> `502`

## Phoenix client design (Phase 3)

One module owns all Fly HTTP:

```elixir
PatchwritApi.Fly.Client
  create_machine(attrs) :: {:ok, result} | {:error, error}
  list_machines()       :: {:ok, result} | {:error, error}
  get_machine(id)       :: {:ok, result} | {:error, error}
  start_machine(id)     :: {:ok, result} | {:error, error}
  stop_machine(id)      :: {:ok, result} | {:error, error}
  delete_machine(id)    :: {:ok, result} | {:error, error}
```

Rules:

- Base URL, token, and app name come from application config, populated by
  `config/runtime.exs` from `FLY_API_TOKEN` and `FLY_APP_NAME`.
- Validation happens before any HTTP request. An invalid image key,
  region, name, or Machine ID never reaches Fly.
- The HTTP layer is injectable so tests use `Req.Test` stubs. Automated
  tests never call the real Fly API.
- Every call returns `duration_ms` and a normalized error shape.

## Security gate (Phase 4)

- Routes are enabled only in the dev environment, or when a
  `TEST_MACHINES_TOKEN` is configured and presented as a Bearer token.
- The Fly token is read only by Phoenix. It is never committed, never
  returned in responses, and never passed into a created Machine.
- Create inputs are allowlisted and size-capped. This endpoint must never
  become "run any image, any size, anywhere."

## Cleanup invariant

Destroy is a first-class outcome, tracked separately from any later
analysis status (per `ARCHITECTURE.md`):

- A failed create that may have created a Machine must still attempt
  destroy.
- Phase 5 ends with `fly machines list -a <app>` (or the equivalent API
  list) showing no leftover test Machines.
- Machine IDs, timings, and failures are recorded honestly. No fabricated
  benchmarks.

## Delivery sequence

1. **This PR:** design contract only. No code changes.
2. **Next PR:** `PatchwritApi.Fly.Client` with mocked tests. No routes,
   no live calls.
3. **Following PR:** gated `/api/v1/test-machines` routes with controller
   tests.
4. **Phase 5:** live create/inspect/start/stop/destroy smoke test against
   a dedicated Fly app, with cleanup evidence recorded in `HANDOFF.md`.

## Open decisions

- Dedicated Fly app name (proposed: `patchwrit-machines`) and whether to
  create it via `fly apps create` or the Apps API.
- Token strategy for local dev: a deploy token scoped to the one app is
  preferred over a broad personal token. Exact `flyctl` syntax to be
  confirmed locally.
- Exact allowlisted image references and init command. Must be proven in
  the Phase 5 live run, not assumed from this document.
- Whether list is needed long-term or is only a cleanup/debugging aid.

## Sources

- https://docs.fly.io/machines/api
- https://docs.fly.io/machines/api/working-with-machines-api.md
