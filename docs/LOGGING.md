# Logging

Patchwrit logs **aggressively and consistently** across Phoenix and the
Go worker. One structured event per line:

```text
patchwrit event=<event> analysis_id=<uuid> job_id=<uuid> status=<status> duration_ms=<n>
```

- Phoenix emits through `PatchwritApi.Log`; the worker emits through
  `internal/observe` to stderr. Fly captures worker stderr, so
  `fly logs -a patchwrit-machines` shows clone, Maven, module, and
  callback events live. Maven/Git human output streams unchanged
  around the structured lines.
- Field names are shared: `analysis_id` (Phoenix) and `job_id`
  (worker) carry the same UUID; `duration_ms`, `dependencies`,
  `modules_total`, `modules_resolved`, `graph_complete`,
  `payload_bytes`, and `error_category` mean the same on both sides.
- Log stage boundaries and outcomes, not polls or heartbeats:
  `dispatch.*`, `repository.sha_resolved`, `machine.*`,
  `checkout.*`, `maven.*` (including one event per module),
  `callback.*` (including rejections with reason and payload size),
  `scan.*`, and `investigate.*`.
- **Never** log callback tokens, API keys, authorization headers,
  full payloads, model prompts, or repository contents. URLs, SHAs,
  image digests, counts, sizes, durations, statuses, and categories
  are expected.

Logs are the first diagnostic for a failed run: check the last
`patchwrit event=` line before checking the database. Persisting and
broadcasting these events into the analysis page (Jenkins-style
console) is follow-up work; console emission is the current contract.
