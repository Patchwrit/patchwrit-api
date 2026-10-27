# Architecture Decision Record

All decisions accepted for prototype on **2026-10-26**, subject to later written revision.

1. **Phoenix/Elixir + PostgreSQL + Oban + LiveView:** a unified control plane with REST API and agent coordination, no premature frontend split.
2. **Ephemeral Fly Machines + Go:** delegate Git/Maven/untrusted work to disposable workers; Phoenix provisions, tracks, destroys them.
3. **Discovery before investigation:** Maven graph/OSV scan in Phase 1; source/bytecode/patch tests only for relevant findings in Phase 2.
4. **Prebuilt JDK images:** select appropriate approved image at runtime; initial JDK 17/21, additional supported versions when validated. Maven selection inside worker from trusted distributions.
5. **Evidence-based agent tribunal:** Investigator, Prosecutor, Defender, Judge and Remediator; importing a package does not demonstrate exploitability.
6. **Human-gated changes:** never open GitHub PRs without authorized workflow.
7. **Milestones over breadth:** smoke test create/inspect/destroy before Go callback, then Maven+OSV, then agents.

## Decisions pending
OSS license, concrete Fly resources/regions and image registries, exact API/database schemas, model access/cost, security constraints, finding scoring, GitHub App permissions.
