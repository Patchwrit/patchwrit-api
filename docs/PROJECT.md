# Patchwrit — Project Charter

**Status:** Greenfield, planned prototype. **Date:** 2026-10-26.

Patchwrit is an open-source, evidence-driven dependency vulnerability investigation and remediation platform. The initial ecosystem is public GitHub repositories built with **Java/Maven**; the architecture should permit other ecosystems later.

## Hackathon
Submission deadline: **November 4, 2026, 6 PM Pacific**. Public, working OSS project; three-minute demo. Rubric supplied by event: impact 30%, Meta AI tooling 25%, technical depth 20%, demo 25%.

## MVP
1. Accept public GitHub Maven repository and pin commit SHA.
2. Run ephemeral worker to resolve effective Maven dependency graph, including transitive relationships, and query OSV.
3. Persist findings and evidence with provenance.
4. Use meaningful Meta-powered Investigator, Prosecutor, Defender, Judge reasoning on an actual finding. Distinguish dependency presence from demonstrated reachability.
5. Propose a justified remediation; GitHub PR creation only after explicit authorization and if schedule permits.
6. Terminate the Machine reliably and retain an audit trail.

## Test repositories
- https://github.com/spring-petclinic/spring-framework-petclinic (Maven smoke test)
- https://github.com/ryanmcmorrowsnyk/vulnerable-java-app (vulnerability demo)

Pin SHA for analyses. Do not hardcode tests as the only supported inputs.

## Non-goals for first vertical slice
Full Java build-system coverage; private artifact registries; perfect exploitability proofs; running Java app by default; elaborate front end; large distributed infrastructure.

## Success
A three-minute demo shows real clone, graph, OSV finding, evidence-backed agent deliberation, remediation recommendation, and disposal of worker. Features not yet built must not be advertised as implemented.

License remains to be chosen; recheck current event terms before submission.
