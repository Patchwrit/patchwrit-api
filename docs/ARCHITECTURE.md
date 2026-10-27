# Architecture — Design, Not Yet Implemented

## Components
- **patchwrit-api**: one Phoenix/Elixir application with REST, LiveView, PostgreSQL, Oban, policy engine, AI/Meta-model agent orchestration, Fly Machines lifecycle.
- **patchwrit-worker** (planned separate repository): Go executable, containerized with Git, Maven, JDK and optional static/bytecode analyzers; run on ephemeral Fly Machines.

## Data flow
```
Client/LiveView -> Phoenix REST -> PostgreSQL + Oban
                                   |
                                   v
                            Fly Machines API
                                   |
                                   v
                     disposable Go worker (untrusted repo)
                         clone SHA -> Maven -> OSV
                                   |
                                   v
                          scoped authenticated callback
                                   |
                                   v
                       Phoenix persists evidence/results
                                   |
                                   v
                        reconcile/destroy Machine
```

## Two phases
**Phase 1 Discovery**: pin SHA, clone, resolve effective dependency graph incl. transitive and multiple modules where supported, query OSV, persist findings, destroy Machine. No need to launch Java application. Maven itself may execute arbitrary plugins and must run isolated.

**Phase 2 Investigation/Remediation**: launch new ephemeral worker for evidence gathering (imports, actual invocations, source/bytecode reachability) and bounded test of approved proposed change. Agents coordinate in Phoenix.

## Agents
- **Investigator:** dependency-tree introduction paths, source imports/references, actual method invocations with file/line, call-path analysis when possible. No assertion of reachability without evidence.
- **Prosecutor:** evidence-supported case for action.
- **Defender:** challenge reachability, versions, assumptions and applicability.
- **Judge:** verdict including inconclusive/not-actionable; cite evidence.
- **Remediator:** propose and, only with authorization, validate change and create PR.

Structured evidence (repo SHA, coordinates, files/lines, source/tool, confidence), repeatable outputs and uncertainty are foundational.

## Runtime versions
Default automatic JDK and Maven inference based on POM(s), inherited config, wrapper metadata, CI, toolchains, with runtime validation. Explicit user overrides allowed. Distinguish build JDK, bytecode target, and application runtime. Start with **prebuilt JDK 17/21 images**, add 8/11/25 as needed. Runtime image **selection** is dynamic, image **building** need not happen per request. Default Maven 3.9.x, or validated approved wrapper distribution. Never blindly execute repo `mvnw` or arbitrary download URL.

## Security and reliability
Treat fetched repos and Maven build/plugins as untrusted execution. Restrict resources, identity, networking and credentials. Never give Fly control-plane credentials, broad GitHub tokens or database secrets to workers. Authenticate callbacks using short-lived analysis-scoped credentials; require reachable service or alternative result polling. Persist Machine ID and cleanup state independent of analysis outcome; bound timeouts, reconcile orphans. Pin repository SHA and image digest. Rate-limit and budget requests. Do not retry JDK for arbitrary errors. Human authorization before any PR/write to analyzed repository.

## Implementation philosophy
Phoenix owns orchestration; Go owns isolated execution. Prove smallest end-to-end path before agents and UI polish.
