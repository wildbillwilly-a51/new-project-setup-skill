# New Project Setup Completion Checklist

Use this compact checklist only for final setup troubleshooting or a complete
install/sync audit. Normal execution routes directly through the bundled
scripts and loads a conditional reference only when an exception requires it.

## Reference Routing

- Prerequisites, initialization, target inspection, and v2-v6 migration:
  `install-and-migration.md`
- Adaptive effort, progressive context, durable memory, convergence, and
  protected boundaries: `execution-and-memory.md`
- Private GitHub initialization, source audit, fast-forward synchronization,
  and sanitized fallback: `github-history.md`

## Behavior Contract

- A bare invocation runs install/sync; a question changes nothing.
- Implicit activation includes ordinary creation of a new durable app or
  project, but excludes ordinary work inside an existing project.
- Exactly one target is resolved; sibling projects remain untouched.
- Source maintenance synchronizes the installed runtime; target use does not
  modify the source skill. Source maintenance runs the source helper first and
  never applies an older installed helper over source files.
- Workflow automation prefers PowerShell 7 on every platform, falls back to
  Windows PowerShell 5.1 only on Windows, and selects the runtime without user
  command memorization. It does not constrain the project's application stack.
- Durability, operational risk, and effort are inferred independently.
- Clear bounded work continues without routine user questions.
- Useful exploration is promoted; lasting work is never silently demoted.
- Progressive context expands automatically when evidence requires it.
- The completion/evidence invariant requires every acceptance criterion to
  pass, distinct evidence for every material risk or protected boundary, no
  unresolved high-risk failure, and current durable records. Code-path
  variation alone is equivalent evidence.
- Validation reuses valid evidence, changes strategy when loops make no
  material progress, runs at most one broad final matrix, and then retests only
  failed or invalidated cells. An unresolved stop requires both no material
  progress and no credible bounded probe.
- Every lasting revision is preserved; development memory remains proportional
  and public-ready.
- Every lasting Codex commit receives an exact staged-tree and intended-message
  precommit audit, then commits that exact audited input immediately. Missing or
  mismatched attestation fails safe to immediate synchronization.
- Focused small work may defer private transfer for one through nine verified
  local commits and synchronizes all on the tenth, with no time trigger. Initial
  setup, standard/substantial work, milestones, releases, explicit requests,
  empty destinations, and uncertain state synchronize immediately.
- Protected boundaries, private visibility, source-history audit, and
  fast-forward-only synchronization remain mandatory.
- Deployment requires confirmation immediately before the action unless the
  current request explicitly names the deployment target and effect and waives
  that additional checkpoint; that explicit waiver is the confirmation. A
  request that merely asks for deployment is not a waiver.
- Normal private sync audits the current snapshot plus every commit after the
  fetched verified destination tip with private-source rules that block
  high-confidence secrets and unsafe Git objects without treating operational
  metadata as a push blocker. Exact findings inherited unchanged from that tip
  are already transferred, while changed, re-added, or new findings always
  block. Empty destinations use the same private-source rules across full
  ancestry; public-readiness assessments use strict public-metadata rules.
- Legacy ancestry already on the exact private destination is a transferred
  boundary, not automatic fallback. Local-only legacy ancestry may use one
  explicitly authorized guarded clean-baseline recovery that preserves its old
  tip in local hidden refs; otherwise fallback or local-only remains explicit.
- Fallback is isolated, never normal, and never modifies the normal source
  remote. History is never rewritten automatically and pushes are never forced.

## Completion Gate

Before treating setup or synchronization as complete, verify:

- prerequisites and Git identity are ready or clearly reported pending
- the platform launcher selects `pwsh` on Windows/macOS/Linux and uses
  `powershell.exe` only as the Windows fallback
- the version-6 apply helper is idempotent in `-Check` mode
- managed markers are unique and complete, and managed paths do not cross
  reparse points outside the resolved target
- preflight completes before mutation, and existing helper scripts are updated
  only when marked as managed or matched to an exact known legacy hash
- project-specific content and existing memory survived migration
- managed `AGENTS.md`, ignore rules, attributes, development log, handoff,
  changelog, both GitHub helpers, and workflow state exist
- workflow state records progressive context, adaptive effort, risk-based
  validation, evidence reuse, strategy change on non-convergence, and
  proportional documentation
- precommit mode audits the exact staged tree and intended metadata, and changed
  staged input cannot reuse an attestation
- focused batching defers only verified commits one through nine, synchronizes
  the tenth, has no time trigger, and every immediate-sync exception bypasses it
- normal private synchronization audits every commit after the fetched exact
  private-remote tip; empty private-source paths and public-readiness paths
  still audit full ancestry, including unsafe commits later removed from the
  tip, with public-readiness retaining stricter operational-metadata blocking
- guarded legacy recovery requires explicit authorization, a safe current tree,
  clean named branch, expected `HEAD`, no active Git operation, and an absent
  private destination branch; it preserves the exact old tip in local hidden
  refs and never force-pushes
- isolated fallback leaves the configured normal remote unchanged
- policy surfaces use the same risk or protected boundary evidence unit and the
  same no-progress/no-bounded-probe terminal rule
- bounded scenarios require no routine questions and protected scenarios still
  require authorization unless an explicit deployment waiver supplies it
- helper scripts parse and the automated regression/evaluation suites pass in
  Windows PowerShell 5.1 and PowerShell 7, with Linux/macOS PowerShell 7 covered
  whenever those platforms are release targets
- the applicable boundary or full source-history audit passes or reports only
  the exact safe blocker
- any GitHub destination remains private and fast-forward-only
- source and installed runtime payload hashes match after source maintenance
- the final handoff is accurate relative to its containing commit without a
  bookkeeping-only commit/sync loop
- scoped local commit and final GitHub result are reported
