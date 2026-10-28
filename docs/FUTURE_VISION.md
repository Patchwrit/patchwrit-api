# Patchwrit — Future Vision

**Status:** Owner-discussed direction, 2026-10-28. This records ideas
that are essential to the long-term product but are **not** all part of
the current hackathon tribunal milestone.

Patchwrit's long-term shape is not merely a vulnerability scanner. It
is a supply-chain evidence and decision system:

```text
Resolve → Find → Investigate → Enrich → Debate → Decide
        → Propose → Verify → Human approval → Monitor
```

The current bounded milestone remains:

```text
Evidence dossier → Prosecutor → Defender → Judge
                 → Phoenix policy → human-readable recommendation
```

## Near-term design refinement: case grouping

Investigator cases are currently one per OSV finding. Real reactors
can produce many findings for the same package, version, or advisory
across modules. Before the tribunal engine spends model calls, group
related findings into a **case family** — for example, same package +
version + advisory across modules — while preserving each module's
provenance. This affects tribunal cost, data modelling, and verdict
quality, so it must be decided before or during tribunal design.

## Future evidence roles

### Source Investigator

Extend the deterministic Investigator beyond dependency provenance.
Collect source-level evidence at the pinned SHA only when actually
observed: imports, class or method references, relevant configuration,
production/test usage, and possible call paths. This improves the
relevance debate but must never be presented as proof of
exploitability without stronger evidence.

### Librarian

Deterministically enrich cases with advisory intelligence beyond the
initial OSV match, where reliable sources exist: known-exploited
status, exploit maturity or probability signals, fixed-version release
information, upgrade distance (patch/minor/major), and advisory
changes since a previous scan. The Librarian supplies facts; it does
not argue the case.

### Context Keeper

Technical evidence is not organizational risk. Tracked repositories
should eventually carry human-supplied context: internet exposure,
production/internal status, data sensitivity, service criticality,
ownership, and policy deadlines. Agents may use this context but must
not invent it.

## Future action loop

### Remediator

After a Judge recommendation, a Remediator may propose a concrete,
evidence-backed dependency update. A proposal is only an opinion
until it is tested.

### Verifier

Apply a proposed change only inside an ephemeral environment, resolve
the graph again, run feasible build/test checks, and confirm the
vulnerable version disappeared without obvious breakage. Remediation
without verification is not a completed action.

### Human decision, override, and appeal

A Judge verdict is advisory. Record human decisions and overrides,
including the reason. Allow a case to be reopened when new evidence,
advisory changes, deployment context, or source analysis materially
changes the picture.

## Lifecycle and audit

An **Auditor/Historian** function should track each case over time:
newly disclosed, still present, fixed, reintroduced, advisory changed,
new fixed version available, dependency removed, human-accepted, or
superseded. Scheduled rescans should show deltas rather than treating
every run as an unrelated snapshot.

## Evaluation

The tribunal needs a known-answer evaluation set before its language
is trusted at scale. Measure citation validity, unsupported
reachability or exploitability claims, inappropriate dismissals,
repeatability, latency, and cost per verdict. Persuasive prose is not
quality unless it survives these checks.

## Operating principle

Models argue from evidence. Deterministic systems establish facts,
group and enrich cases, validate citations, enforce budgets and
policy, verify proposed changes, and preserve history. Humans remain
responsible for action.
