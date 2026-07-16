# New Project Setup Completion Checklist

Use this compact checklist only for final setup troubleshooting or a complete
install/sync audit. Normal execution routes directly through the bundled
scripts and loads a conditional reference only when an exception requires it.

## Reference Routing

- Prerequisites, initialization, target inspection, and v2-v5 migration:
  `install-and-migration.md`
- Adaptive effort, progressive context, durable memory, convergence, and
  protected boundaries: `execution-and-memory.md`
- Private GitHub initialization, source audit, fast-forward synchronization,
  and sanitized fallback: `github-history.md`

## Behavior Contract

- A bare invocation runs install/sync; a question changes nothing.
- Implicit activation is limited to creating or initializing a durable project.
- Exactly one target is resolved; sibling projects remain untouched.
- Source maintenance synchronizes the installed runtime; target use does not
  modify the source skill. Source maintenance runs the source helper first and
  never applies an older installed helper over source files.
- Durability, operational risk, and effort are inferred independently.
- Clear bounded work continues without routine user questions.
- Useful exploration is promoted; lasting work is never silently demoted.
- Progressive context expands automatically when evidence requires it.
- Validation addresses distinct risks, reuses valid evidence, changes strategy
  when loops stop converging, runs at most one broad final matrix, and then
  retests only failed or invalidated cells.
- Every lasting revision is preserved; development memory remains proportional
  and public-ready.
- Protected boundaries, private visibility, source-history audit, and
  fast-forward-only synchronization remain mandatory.
- Audit failure preserves the local commit and requires an explicit fallback or
  local-only choice; history is never rewritten automatically.

## Completion Gate

Before treating setup or synchronization as complete, verify:

- prerequisites and Git identity are ready or clearly reported pending
- the version-5 apply helper is idempotent in `-Check` mode
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
- bounded scenarios require no routine questions and protected scenarios still
  require authorization
- helper scripts parse and the automated regression/evaluation suites pass
- full source-history audit passes or reports only the exact safe blocker
- any GitHub destination remains private and fast-forward-only
- source and installed runtime payload hashes match after source maintenance
- the final handoff is accurate relative to its containing commit without a
  bookkeeping-only commit/sync loop
- scoped local commit and final GitHub result are reported
