---
name: new-project-setup
description: Install or sync an efficient low-intervention durable project workflow with adaptive execution, progressive context, proportional public-ready memory, and audited private GitHub history. Use automatically when the user asks Codex to create, start, initialize, or bootstrap a new durable project or repository, and when the user asks to apply, install, update, refresh, or sync the new project setup workflow. A bare or primary invocation must run install/sync for the resolved target, not merely load context. Questions about the skill are consultation-only. Also use when specifically asked to configure this workflow's Git/GitHub prerequisites, project memory, source-history synchronization, or sanitized fallback. Do not trigger merely because an existing repository was opened or received ordinary implementation work.
---

# New Project Setup

Install or synchronize the durable workflow and complete clear bounded work
end-to-end with low intervention.

## Activation And Scope

A bare or primary `$new-project-setup` invocation runs install/sync; do not stop
after loading or require another action word. Activate implicitly only to
create, start, initialize, or bootstrap a durable project or repository.

Do not activate for ordinary implementation in an existing repository. A
question about the skill, its behavior, or prior changes is consultation-only
and authorizes no edits.

A request to build an app activates implicitly only when project context shows
that a new durable project or repository must be created. The same request in
an existing project remains ordinary implementation governed by that project's
installed guidance.

Resolve exactly one target from the current request or active task subject.
Never update an accessible sibling project in bulk. In this source project,
maintain the source and synchronize the installed runtime. In another project,
apply the installed workflow only there; do not modify this source or runtime.

## Progressive Disclosure

Use the deterministic scripts directly on the normal path. Do not read their
source or load every reference merely because the skill triggered.

- Normal target: run installed
  `scripts/apply-project-setup.ps1 -ProjectRoot <target>`. In this skill's
  source, run the source copy, validate, then sync runtime. Never apply an older
  installed helper over source.
- Prerequisite, initialization, or migration exception: read
  `references/install-and-migration.md`.
- Execution, memory, ambiguity, or protected-boundary question: read
  `references/execution-and-memory.md`.
- GitHub initialization, source audit, divergence, or fallback: read
  `references/github-history.md`.
- Final setup troubleshooting or completeness audit: read
  `references/new-project-setup-checklist.md`.

Read only the relevant reference. Expand context automatically when evidence
requires it; do not turn ordinary context expansion into a user checkpoint.

## Install Or Sync

1. Resolve one target path. For a new project, create that directory and
   initialize Git through `install-and-migration.md`; then record root, branch,
   committed `HEAD`, status, remotes, setup state, handoff, and dirty work.
2. Run the authoritative apply helper selected above. Pass a known repository
   slug and remote. Use `-Check` only for consultation or drift; it verifies the
   managed payload, while Codex still reviews project-specific handoff content.
3. Preserve project guidance outside managed markers, existing memory, local
   history, and unrelated work. Recheck branch, `HEAD`, and scoped paths before
   staging or committing; stop on overlapping concurrent changes.
4. When no GitHub destination is recorded, initialize a private repository
   with `scripts/github-sync.ps1 -Initialize`, then commit the recorded state.
5. Validate proportionally, commit only scoped lasting changes, and run
   `scripts/github-sync.ps1` against committed `HEAD`.
6. If the source audit blocks, keep the local commit and ask whether to use the
   isolated `scripts/github-backup.ps1` fallback or remain local-only. Never
   rewrite or force-push history, expose matched values, or change visibility.
7. When maintaining this source project, run
   `scripts/sync-installed-skill.ps1`, validate, and hash-check the exact
   installed runtime payload before the source commit.

## Adaptive Efficient Execution

Infer three independent properties from ordinary intent and project evidence:

- **Durability:** lasting or exploratory. Applications, features, fixes, and
  reusable output are lasting. `Quick`, `prototype`, and `MVP` do not by
  themselves mean disposable. Promote useful exploration automatically; never
  demote lasting work or discard it.
- **Operational risk:** ordinary local work or a protected boundary. Risk
  controls authorization, not how much useful local work Codex completes.
- **Effort:** focused, standard, or release-critical. Effort controls context
  and validation depth, not authority.

For clear work, give one short non-blocking classification and continue. Ask
one plain-language preservation question only when durability is genuinely
ambiguous. Do not ask for routine implementation, context expansion, or
validation transitions.

Use progressive context:

1. Start with Git status, the concise handoff, and directly relevant files.
2. Read development-log or changelog excerpts only when they answer a current
   question or need an update.
3. Broaden searches automatically when dependencies, failures, or risk justify
   it. Exclude siblings, dependencies, generated output, and verbose historical
   artifacts unless relevant.
4. If the handoff is missing, stale, or contradictory, reconstruct it from Git
   and relevant project evidence. Ask only when the bounded objective cannot be
   resolved safely.

Clearly exploratory file-changing work starts with Git status and directly
relevant files; durable memory is read when needed to avoid conflicts or when
the work promotes. Promotion occurs when output is reused, incorporated,
requested to be kept or continued, or becomes a dependency of lasting work.
Codex may clean up only uncommitted artifacts it created during the current
clearly exploratory package and confirmed are not reused. Never remove
pre-existing, shared, promoted, or lasting output without authorization.

Before implementation, keep a compact ledger of acceptance criteria, a risk set
bounded to the request and materially different code paths, required evidence,
invalidators, and completion conditions. Add only a direct dependency or shared
cause and record why; report unrelated discoveries instead of expanding scope.
Another equivalent screenshot is not new evidence.

Batch related failures and diagnose shared causes before patching. Reuse valid
evidence and retest only invalidated risks. After targeted risks pass, run one
effort-appropriate broad final matrix; focused work may need only one direct
check. If it fails, preserve passing evidence and retest only failed or
invalidated cells; do not start another broad candidate matrix. After two
equivalent cycles without fewer unresolved risks, change strategy. After two
unproductive strategies, isolate a minimal reproducer. If two materially
different root-cause attempts still fail, preserve diagnostics, report an
unresolved blocker, and do not claim completion. Finish when acceptance criteria
pass, no high-risk failure remains, durable records are current, and more work
would duplicate evidence. Never trade away safety validation for token savings.

## Durable Memory

Preserve every lasting revision in Git. Update public-ready memory only where
it adds future value:

- `docs/development-log.md`: decisions, rationale, useful failed approaches,
  validation, and durable lessons.
- `docs/codex-handoff.md`: current objective and state, one next action,
  blockers, decisions, branch/commit/sync status, and remaining validation.
- `CHANGELOG.md`: notable reader-facing changes.

Keep credentials, regulated information, machine details, and private
operational data in ignored `*.local.md` or approved secret storage. Preserve
durable conclusions before compacting verbose working context. Refresh the
handoff at objective changes, completed packages, blockers, intentional
handoffs, and commit/sync completion; summarize valid and remaining evidence so
the next task does not repeat checks. Prepare the final handoff before the
containing commit and describe commit/sync state relative to that commit. A
successful push matching the recorded intended state does not require a
bookkeeping-only follow-up commit; edit again only when objective, blockers,
next action, evidence, or outcome changed.

## Authority And Boundaries

A bounded local build authorizes architecture and implementation choices,
established project-local dependencies, tests, generated files, demo data, and
schemas or migrations for a new empty local database. For a new empty project,
choosing a reasonable initial framework and dependencies is an architecture
choice; replacing an existing framework or platform remains protected.

Ask before deployment; credentials or live/paid services; auth/security
changes; global or native tool installation; framework or platform replacement;
consequential licensing changes; existing/shared/production data changes;
destructive operations; material product-direction expansion; unrelated
conflicting work; or unsafe state. Continue without routine checkpoints inside
the bounded objective. Protected boundaries override implied authority: obtain
a separate confirmation immediately before deployment even when deployment is
named in the objective. One confirmation may cover several protected effects
only when it explicitly identifies all of them.
