# Patchwrit — Design System & Tribunal UX

**Version:** 1.0 (proposed)  
**Status:** Design specification; not all components are implemented  
**Updated:** 2026-10-28  
**Applies to:** `Patchwrit/patchwrit-api`

## Purpose and design thesis

Patchwrit is an evidence-first vulnerability tribunal for Java/Maven projects. Its interface should resemble an **evidence ledger**: precise, restrained, editorial, and auditable—not a generic SaaS or neon cybersecurity dashboard.

**Verdict before evidence. Unknowns always visible. Failures never hidden. Policy outranks model opinion. Spend is instrumentation.**

This document is a **target specification**, not a claim that all proposed features exist. It should evolve alongside implementation changes.

### Existing implementation (inspected on main)

- `priv/static/patchwrit.css` defines a standalone `pw-*` semantic system with paper/ink/burnt-orange tokens, panels, lifecycle badges, forms, and responsive rules. Extend it rather than replacing it with daisyUI defaults.
- `lib/patchwrit_api_web/live/analysis_live/index.ex` currently prioritizes repository setup in a 350px left column; tracked repositories and recent analyses are on the right.
- `lib/patchwrit_api_web/live/analysis_live/show.ex` currently shows run metadata, checkout, dependency graph, OSV findings, timings, and raw worker result. Tribunal verdict presentation is the desired next layer.
- Existing graph completeness, OSV scan timestamps, failure messages, and worker cleanup states are valuable signals to preserve.

## 1. Theme direction — Evidence Ledger

**Keep and refine paper, ink, burnt orange.** Warm neutral backgrounds evoke records and annotations; dark ink communicates seriousness; burnt orange establishes brand identity and interactive emphasis. Reserve semantic colors for actual risk and lifecycle meaning. Avoid gradients-for-decoration, glows, generic purple, heavy shadows, and colored agent personas.

### Foundation tokens

| Token | Value | Use |
|---|---|---|
| `--pw-paper` | `#EDF1EC` | App background |
| `--pw-panel` | `#FFFFFF` | Primary surfaces |
| `--pw-panel-subtle` | `#F7F9F6` | Secondary surfaces |
| `--pw-panel-inset` | `#E7ECE6` | Nested evidence |
| `--pw-ink` | `#18201C` | Primary text |
| `--pw-ink-soft` | `#3F4F46` | Secondary text |
| `--pw-muted` | `#63736A` | Supplementary metadata |
| `--pw-line` | `#CFD9D1` | Borders and dividers |
| `--pw-line-strong` | `#89998E` | Strong rules |
| `--pw-field-line` | `#A9BBAE` | Form boundaries |
| `--pw-accent` | `#B5441F` | Brand and primary action |
| `--pw-accent-hover` | `#8F3213` | Hover |
| `--pw-accent-subtle` | `#FBECE5` | Brand tint |
| `--pw-mono` | `ui-monospace, "SF Mono", SFMono-Regular, Menlo, Consolas, monospace` | Technical identifiers |

### Semantic tokens

| Meaning | Background | Foreground |
|---|---|---|
| Danger | `#FDE7E2` | `#8C2418` |
| Warning | `#FFF0C2` | `#714B00` |
| Success | `#DFF3E2` | `#14532D` |
| Information | `#DCEEF8` | `#174F6B` |
| Neutral / unknown | `#E7EBE7` | `#405047` |
| Policy override | `#18201C` | `#FFFFFF` |

Use the existing sans-serif stack (Avenir Next → Segoe UI → system). Use monospace for SHAs, Maven coordinates, file paths, evidence IDs, numeric figures, token counts, and costs. Body text 14–16px with ≥1.5 line-height; section titles 20–24px; page titles 32–44px. Spacing scale 4/8/12/16/24/32px. Panels have 6–8px radius, 1px rules, no default shadow. Max dashboard width approximately 1280–1360px.

## 2. Recommendation and policy states

| Effective recommendation | Background | Text | Explicit label |
|---|---|---|---|
| `remediate_now` | `#FDE7E2` | `#8C2418` | Remediate now |
| `schedule_remediation` | `#FFF0C2` | `#714B00` | Schedule remediation |
| `investigate_usage` | `#DCEEF8` | `#174F6B` | Investigate usage |
| `needs_human_review` | `#E7EBE7` | `#18201C` | Needs human review |
| `dismiss` | `#DFF3E2` | `#14532D` | Dismiss |

**Never equate `dismiss`, a completed analysis, a clean scan, and an unassessed finding.** Execution status, security recommendation, and evidence confidence are distinct dimensions.

### Policy cap presentation

When a deterministic gate caps the Judge recommendation:

1. Show a **full-width dark policy banner** with an orange leading rule: **POLICY OVERRIDE — HUMAN REVIEW REQUIRED**.
2. Show the **effective** `needs_human_review` recommendation prominently.
3. Preserve the **original Judge recommendation** with a subordinate “Judge proposed” label; never silently overwrite it.
4. State the exact gate trigger, e.g. “Dependency graph incomplete: 3/5 modules resolved.”
5. Link to completeness evidence and show what is missing.
6. Do not make the cap look like success, nor merely display an ordinary gray badge.

Policy is authoritative in the backend. LiveView must **render**, not recalculate, the effective recommendation.

### Accessibility

Target WCAG 2.2 AA: ≥4.5:1 contrast for normal text, ≥3:1 for large text and meaningful non-text indicators; verify all rendered combinations in automated tests. Pair colors with text and icons. Visible keyboard focus should use a sufficiently strong outline, not only a low-opacity glow. Respect reduced motion. Do not hide key findings behind hover. Test mobile touch targets, long coordinates, and screen-reader announcements.

## 3. Dashboard: “What needs my attention?”

Priority from top to bottom:

1. Header, product identity, compact “Track repository” action.
2. **Attention stat strip**: Remediate now / Human review / Investigate usage / Active or failed analyses.
3. **Needs-attention queue**: actionable cases, worst first.
4. **Tracked repositories**: latest known risk posture, coverage, latest successful evaluation, current run state.
5. **Recent analyses**: actual pipeline progress and failures.
6. **Repository setup**: secondary expandable panel or separate page; prominent only for an empty workspace.

Illustrative wireframe (fictional data):

```text
PATCHWRIT                       Analyses  Repositories  [+ Track repo]
─────────────────────────────────────────────────────────────────────
Your security docket
What needs your attention across tracked repositories

[ Remediate now 03 ] [ Human review 02 ] [ Investigate 07 ] [ Active 04 ]

NEEDS ATTENTION                                                View all
! service-a · CVE-... · group:artifact:version      REMEDIATE NOW
! service-b · GHSA-... · graph 3/5 modules         POLICY: HUMAN REVIEW
? service-c · CVE-... · relevance unknown          INVESTIGATE USAGE

TRACKED REPOSITORIES
service-a  2 urgent          Complete    Last evaluated …     View / Run
service-b  Review required   Partial     Last evaluated …     View / Run
service-c  Unknown           Running     Last evaluated …     View / Run

RECENT ANALYSES
service-c   Checkout ✓ → Maven ✓ → OSV ✓ → Tribunal running
service-b   Graph partial → Policy cap
service-a   Complete → 3 verdicts

REPOSITORY SETUP
[ + Track another repository ]
```

### Aggregation and sorting

The attention strip and queue should be based on the **latest relevant known analysis per repository**, not cumulative historical runs. Do not double-count the same unresolved case across runs. Document stale posture explicitly when newer runs fail.

Queue ordering: `remediate_now`; policy-capped `needs_human_review`; other human review; `investigate_usage`; time-sensitive scheduled remediation; failed/stale coverage needing operator action. Within categories use severity, evidence certainty, exposure, age, and stable tie-breakers. If operational failures warrant a separate urgent queue, surface them with equivalent visibility, not at the bottom of history.

Each attention row: repository, vulnerability ID, package/version, **effective** recommendation, one-line why, graph completeness, last evaluated time, and “View case” link.

Tracked repository rows: name, pinned SHA, attention count, latest **known** posture, coverage, last successful evaluation, current execution state, actions. Failed newer runs must not erase previous known posture or imply safety.

Recent analyses show real persisted stages where available: Queued → Provisioning → Checkout → Maven graph → OSV → Dossier → Prosecutor → Defender → Judge → Policy → Complete. Never fabricate per-stage progress. Worker cleanup is a separate operational dimension.

Preserve existing branch discovery, manual ref fallback, and JDK selection when demoting the setup form.

## 4. Component vocabulary

| Component | Role | States |
|---|---|---|
| `pw-stat-card` | Attention metric | Value, zero, unavailable |
| `pw-attention-row` | Case queue item | Open, capped, stale, failed |
| `pw-verdict-badge` | Recommendation label | Five recommendation values |
| `pw-policy-banner` | Gate override | Capped, not capped |
| `pw-stage-progress` | Pipeline progress | Pending, running, completed, failed, blocked |
| `pw-argument-panel` | Prosecutor/Defender | Pending, running, completed, failed |
| `pw-evidence-block` | Cited dossier material | Available, partial, missing |
| `pw-spend-figure` | Tokens and cost | Measured, partial, unavailable |

Rules: **Pending** is neutral; **running** is informational with stage and timestamp; **completed** means execution succeeded, not that the project is safe; **failed** shows category and available diagnostic/retry action; **capped** is a dominant policy intervention; **unknown** explains missing evidence. Never render unknown numeric measurements as zero.

Keep execution badges (`pw-badge--completed`, `pw-badge--failed`, `pw-badge--destroyed`) semantically distinct from tribunal outcome badges. The existing `destroyed` cleanup badge is not a vulnerability verdict.

## 5. Analysis detail: verdict first

Top-level order: repository/commit and run status → graph completeness and failures → finding summary → tribunal case panels → technical checkout/dependency evidence → timings and raw worker payload.

Expanded case:

```text
CASE 03 · CVE-... · group:artifact:version
[POLICY OVERRIDE — HUMAN REVIEW REQUIRED]
Graph incomplete: 3 of 5 modules resolved
Judge proposed: Schedule remediation
Effective: NEEDS HUMAN REVIEW

JUDGE VERDICT
Presence              Confirmed
Application relevance  Unknown
Exploitability         Not established
Priority               High
Recommendation         Needs human review (policy-capped)

Judge rationale
Evidence-linked explanation and explicit limitations.

PROSECUTOR                           DEFENDER
Position and claims                  Position and counterclaims
[E-012] [E-019]                      [E-019] [E-027]
Limitations                          Limitations

EVIDENCE DOSSIER [expand]
Advisory | Dependency provenance | Source references |
Invocation/call paths | Completeness and missing evidence

MODEL / SPEND INSTRUMENTATION
Prosecutor  muse-spark-1.3   tokens · latency · estimated cost
Defender    muse-spark-1.3   tokens · latency · estimated cost
Judge       muse-wonder-1.0  tokens · latency · estimated cost
Total                         measured or partial
```

The Judge's five dimensions—`presence`, `application_relevance`, `exploitability`, `priority`, and `recommendation`—must be individually legible. Never collapse them into one synthetic risk score. “Present” does not mean “exploitable.”

The Judge rationale appears immediately below the verdict. Prosecutor and Defender are equal-width peers on desktop and stack on mobile. **Do not color Prosecutor red and Defender green**: their roles are arguments, not good/bad outcomes. Every supported claim links to a stable evidence ID. Clearly distinguish observed evidence, model inference, and unknowns.

The dossier is collapsed below the argument panels but shows its count/completeness even when closed. Include advisory and affected versions, Maven introduction paths, source references, invocation paths where supported, and missing coverage. Keep raw JSON in a technical disclosure section, not the primary reading path.

The instrumentation footer lists model/version, status, input/output/total tokens, duration, estimated cost where available, and missing usage telemetry. Partial totals must be labeled **partial**; never silently substitute zero for unavailable spend.

## 6. Responsive design

- **≥1200px:** Four stat cards; full-width attention queue; tables; side-by-side argument panels.
- **768–1199px:** Two stat columns; condensed repository rows; side-by-side arguments only when legible.
- **<768px:** Stacked attention cards and arguments; full-width policy banner; accessible evidence disclosures; no hover-only information.

## 7. Implementation phases

**A. Foundations:** Extend `patchwrit.css` tokens, shared `pw-*` components, focus states, contrast tests. Preserve existing forms and lifecycle states.

**B. Dashboard:** Refactor `AnalysisLive.Index` to attention-first hierarchy. Supply backend-derived latest-posture summaries and deduplicated current cases; do not fabricate data that the backend does not yet persist.

**C. Tribunal detail:** Refactor `AnalysisLive.Show` to show effective verdict, policy cap, Judge dimensions/rationale, paired arguments, linked evidence, and usage instrumentation. Move raw worker output below.

**D. Hardening:** Test empty, loading, pending, failed, partial graph, capped, missing agent response, missing usage, stale result, mobile, keyboard, and screen reader states. Verify that visible claims always reflect persisted evidence.

## 8. Acceptance criteria

1. Highest-priority actionable findings are apparent immediately on dashboard entry.
2. Policy-capped verdicts are unmistakable and preserve original Judge output.
3. Unknown relevance/exploitability never appears as confirmed safety.
4. Failed analyses remain visible beside last known successful risk posture.
5. A user can understand a case's effective verdict before opening evidence.
6. Model claims can be traced to cited dossier records when available.
7. Spend is visible without overwhelming the verdict.
8. Empty, partial, failed, and unavailable states are honest and usable.
9. Existing tracking and analysis workflows continue to work.
10. UI remains visually coherent with the existing Patchwrit design system.

## 9. Change management

This document is the design source of truth **for intended UX**, while actual code and persisted schema remain the source of truth for implemented behavior. When altering UI behavior, update this specification in the same PR and describe intentional deviations. Avoid changing semantics merely to match visuals. Record major design decisions below.

### Decision log

- **2026-10-28 — v1.0 proposed:** Evolve paper/ink/burnt-orange, introduce evidence-led tribunal presentation, attention-first dashboard, explicit policy overrides, and visible model usage. No application code changes in this document-only proposal.
