---
name: new-project-setup
description: Install or sync an efficient low-intervention durable project workflow with adaptive execution, progressive context, proportional public-ready memory, and audited private GitHub history. Use automatically for ordinary requests to create or build a new durable app, or to create, start, initialize, or bootstrap a durable project or repository, and for explicit requests to apply, install, update, refresh, or sync this workflow. A bare or primary invocation runs install/sync. Questions about the skill are consultation-only. Do not trigger for ordinary implementation, fixes, or review inside an existing project.
---

# New Project Setup

Install or synchronize the durable workflow and complete clear bounded work
end-to-end with low intervention.

## Activation And Scope

A bare or primary `$new-project-setup` invocation runs install/sync; do not stop
after loading or require another action word. Activate implicitly for an
ordinary request to create or build a new durable app when that work requires a
new project, and for requests to create, start, initialize, or bootstrap a
durable project or repository.

Do not activate for implementation, fixes, review, or continuation inside an
existing project. A question about the skill, its behavior, or prior changes is
consultation-only and authorizes no edits.

Resolve exactly one target from the current request or active task subject.
Never update an accessible sibling project in bulk. In this source project,
maintain source first and synchronize the installed runtime. In another
project, apply the installed workflow only there; do not modify this source or
runtime.

## Reference Routes

Use deterministic scripts directly on the normal path. Load only the reference
needed for an exception or interpretation:

- Prerequisites, initialization, target resolution, or migration:
  `references/install-and-migration.md`
- Classification, context, evidence, convergence, memory, or protected action:
  `references/execution-and-memory.md`
- GitHub initialization, audit, divergence, push, or fallback:
  `references/github-history.md`
- Final troubleshooting or a complete setup audit:
  `references/new-project-setup-checklist.md`

Expand relevant context when evidence requires it; do not make context growth
or validation transitions into routine user checkpoints.

## Install Or Sync

1. Resolve one target. For a new project, create its directory and initialize
   Git through `install-and-migration.md`; record root, branch, committed
   `HEAD`, status, remotes, setup state, handoff, and dirty work.
2. For a normal target, run the invoked installed
   `scripts/apply-project-setup.ps1 -ProjectRoot <target>`. In this source, run
   the source helper, validate it, then sync runtime. Never apply an older
   installed helper over source.
3. Preserve guidance outside managed markers, memory, history, and unrelated
   work. Recheck branch, `HEAD`, and scope before staging or committing; stop
   for overlapping concurrent changes or unsafe state.
4. When no GitHub destination is recorded, initialize a private repository
   with `scripts/github-sync.ps1 -Initialize`, then commit recorded state.
5. Validate proportionally, commit only scoped lasting changes, and run
   `scripts/github-sync.ps1` against committed `HEAD`.
6. If source audit blocks, keep the local commit and ask whether to use the
   isolated sanitized fallback or remain local-only. Never rewrite history,
   force-push, expose matched values, or change visibility automatically.
7. In this source project, synchronize the installed skill, validate it, and
   hash-check exact payload parity before the source commit.

## Adaptive Execution

Infer durability, operational risk, and effort independently. Applications,
features, fixes, and reusable output are lasting. `Quick`, `prototype`, and
`MVP` do not mean disposable. Promote useful exploration automatically and
never demote lasting work. Ask one preservation question only when durability
is genuinely ambiguous.

Operational risk controls authorization. Effort is focused, standard, or
release-critical and controls context and evidence depth, not authority. State
a clear classification briefly and continue without routine implementation or
validation questions.

Start durable changes with Git status, the concise handoff, and relevant files.
Read other memory only when useful; broaden automatically for dependencies,
failures, or risk. Clearly exploratory work may stay local, but only current
uncommitted artifacts created by Codex and confirmed unused may be removed.

A bounded local build authorizes architecture and implementation choices,
established project-local dependencies, tests, generated files, demo data, and
new empty-database schemas or migrations. A reasonable initial stack for a new
empty project is locally authorized; replacing an existing platform is not.

## Completion And Evidence

Use one completion/evidence invariant: claim completion only when every
acceptance criterion passes, every material risk or protected boundary has
distinct evidence, no unresolved high-risk failure remains, and durable records
are current. Evidence is distinct only when it covers a materially different
risk or protected boundary; a different code path, screenshot, value, viewport,
theme, or view alone is equivalent evidence.

Keep a compact risk/evidence ledger, reuse valid evidence, and retest only what
failed or became invalid. Run one effort-appropriate final matrix after targeted
checks pass; do not restart a broad matrix after failure. Non-improving cycles
trigger a different strategy and then a minimal reproducer, not automatic
termination. If completion cannot be reached, stop unresolved only when the
latest strategy made no material progress and no credible bounded probe
remains; preserve diagnostics and report the blocker. The routed execution
reference defines these mechanics.

## Durable Memory

Preserve every lasting revision in Git. Update public-ready memory only when it
adds future value: decisions and lessons in `docs/development-log.md`, current
state and valid/remaining evidence in `docs/codex-handoff.md`, and notable
reader-facing changes in `CHANGELOG.md`. Keep private data in ignored
`*.local.md` or approved secret storage.

Refresh the handoff at objective, package, blocker, handoff, or commit/sync
boundaries. Prepare it before its containing commit and describe state relative
to that commit. A matching push needs no bookkeeping-only follow-up commit.

## Protected Boundaries

Ask before credentials or live/paid services; auth/security changes; global or
native installation; framework/platform replacement; consequential licensing;
existing, shared, or production data changes; destructive operations; material
product expansion; unrelated conflicting work; unsafe state; or deployment.

Deployment requires confirmation immediately before the action unless the
current request explicitly names the deployment target and effect and waives
that additional checkpoint; that explicit waiver is the confirmation. A
request that merely asks for deployment is not a waiver. One confirmation may
cover multiple protected effects only when it explicitly identifies all of
them.
