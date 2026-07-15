---
name: new-project-setup
description: Install or sync a low-intervention durable project workflow with adaptive execution, proportional public-ready development memory, and audited private GitHub source history. Use automatically when the user asks Codex to create, start, initialize, or bootstrap a new durable project or repository, and when the user asks to apply, install, update, refresh, or sync the new project setup workflow. A bare or primary invocation is a mandatory request to run install/sync for the resolved target project, not context-only loading. If the user is asking a question about the skill, its behavior, whether it changed docs, or why it acted a certain way, answer the question and do not edit. Also use for Git/GitHub CLI prerequisites, local Git, development logs, Codex handoffs, changelogs, scoped commits, full source-history audits, private public-ready GitHub repositories, or sanitized fallback backups. Do not trigger merely because Codex opened an existing repository or received an ordinary implementation task there.
---

# New Project Setup

Use this skill to install or sync the user's reusable low-intervention project
workflow in a target project. The central requirement is that the user should
not need to remember Git commands, PowerShell helper commands, checklist paths,
GitHub synchronization commands, changelog updates, or durable project-memory
bookkeeping.

Mandatory invocation behavior: if the user's message is only or primarily a
`new-project-setup` skill invocation, that invocation is the user's explicit
request to run this install/sync workflow for the resolved target project. Do
not treat the skill link as passive context. Do not stop after merely loading
the skill. Do not say that no edits or actions happen without a separate update
request. If a target project can be resolved safely, inspect it, choose install
or sync mode, update the target project's setup files when needed, validate,
log, commit, and back up according to this workflow.

This skill may activate implicitly only when the current request creates,
starts, initializes, or bootstraps a new durable project or repository, or
directly asks to install, apply, update, refresh, or sync this setup workflow.
Do not activate merely because Codex opened an existing repository or received
an ordinary implementation task there. Apply the workflow only to the resolved
active target project, never to sibling projects in bulk.

Question/consultation exception: if the user asks a question about the skill,
asks whether the skill updated files or docs, asks why the skill behaved a
certain way, asks what invoking the skill means, or otherwise frames the turn as
consultation, answer that question directly and do not edit files. Do not infer
permission to modify the skill or a project from a question mark, a quoted skill
link used as context, or an accountability/debugging question about a prior
turn. After answering, wait for an explicit apply/install/sync/update request
before changing files.

A second central requirement is walk-away execution without special user
phrasing. Infer task durability and operational risk from ordinary language and
project context. Preserve Codex's freedom to choose implementation details,
tools, architecture, sequencing, and validation within a bounded objective.
Classify clear work, give a one-line non-blocking notice, and continue. If
durability is genuinely ambiguous, ask in plain language whether the work
should be preserved or treated as an experiment, with preservation recommended.

Treat applications, features, fixes, and reusable output as lasting work. Treat
work as exploratory only when the context clearly centers on learning,
comparison, or disposable feasibility. Words such as `quick`, `prototype`, and
`MVP` do not by themselves make work disposable. Promote exploration
automatically when it becomes useful or continues growing; never demote lasting
work, discard output, or require the user to remember workflow vocabulary.

## Source Checklist

Read `references/new-project-setup-checklist.md` before changing a project. It
is the bundled checklist and should be treated as the source procedure for this
skill. Run bundled `scripts/apply-project-setup.ps1` against the resolved target
for deterministic managed-block and version synchronization. Use bundled
`scripts/github-sync.ps1` for audited, fast-forward-only private GitHub source
synchronization. Use `scripts/github-backup.ps1` only as the sanitized fallback
after a source-history audit blocks and the user chooses that fallback.

## Workflow

1. Resolve the target project folder before inspecting or editing files:
   - Treat a bare or primary `new-project-setup` skill invocation as a
     mandatory request to run install/sync for the resolved target project, not
     as context-only loading.
   - If the current message is a question about the skill, its prior behavior,
     or whether it updated project docs, answer in consultation mode and do not
     edit any files.
   - Use an explicit project path from the user's current message first.
   - Otherwise use the active chat/session project, not every available
     workspace root.
   - If this source project is the active chat/session project, treat the skill
     invocation as sync/maintenance mode for this source project and the
     installed runtime skill. In this mode, behavior changes made in the
     source project must be synced to the installed runtime skill as part of
     the same user-invoked workflow, so the user does not need to run or know
     the sync command.
   - If any other project is the target, treat the invocation as install/sync
     for that target project only. Apply the currently installed workflow to
     that project; do not modify this source project or the installed runtime
     skill unless the user explicitly asks to maintain the skill itself.
   - If multiple workspace roots are available and the target project is not
     clear from the current message or active chat/session subject, ask which
     single project to update before editing anything.
   - Never update a sibling or secondary workspace root merely because it is
     accessible.
2. Inspect the target before editing: Git identity and status, branch and
   committed `HEAD`, remotes, GitHub CLI/authentication, PowerShell and `tar`,
   cloud-synchronized paths, setup state, managed instructions, development
   memory, and unrelated dirty work.
3. Choose install or sync mode, then run the installed
   `scripts/apply-project-setup.ps1 -ProjectRoot <target>`. Pass the repository
   slug and remote when already known. Use `-Check` only for consultation or
   drift reporting. Version-2 or version-3 migration must preserve existing
   project guidance and legacy logs; never rewrite or delete history
   automatically.
4. Protect existing work: record branch, `HEAD`, and scoped paths before edits;
   do not mix unrelated changes; recheck immediately before commit; stop on
   overlapping concurrent changes. Dirty files outside committed `HEAD` do not
   alter the source-history audit, but they must not be staged or pushed.
5. Install or refresh the version-4 workflow:
   - managed `AGENTS.md`, ignore, and line-ending guidance
   - adaptive small-lasting, normal-lasting, and exploratory treatment without
     phrase triggers or rigid implementation thresholds
   - public-ready `docs/development-log.md` containing decisions, rationale,
     useful failed attempts, validation, and durable lessons
   - required public-ready `docs/codex-handoff.md` containing current objective,
     state, one next action, blockers, decisions, branch/commit/sync status, and
     remaining validation
   - public-ready `CHANGELOG.md` for notable reader-facing history
   - `scripts/github-sync.ps1` for audited real source-history synchronization
   - `scripts/github-backup.ps1` as an explicit audit-failure fallback
   - `.codex/new-project-setup.json` version-4 adaptive state
6. Preserve project conventions and update only reusable workflow pieces. If no
   GitHub remote exists, create a private repository under the authenticated
   account with `scripts/github-sync.ps1 -Initialize`, record its slug and
   remote, then commit workflow state before the first push. Preserve a
   non-GitHub `origin` and use `github` for GitHub synchronization. Never change
   visibility automatically.
7. Validate helpers and setup state. Run `scripts/github-sync.ps1 -ScanOnly`
   against committed `HEAD`; it must audit the complete current snapshot and
   every reachable source commit. Use `-PublicReadiness` only for a read-only
   assessment before a separately authorized visibility change.
8. Complete coherent work packages with low intervention:
   - at task start, read the handoff, three most recent development-log entries,
     relevant changelog entries, and Git status
   - classify durability and risk independently; announce a confident treatment
     briefly, and ask only when durability is genuinely ambiguous
   - treat a bounded local build as authority for routine structure, established
     project-local dependencies, tests, generated files, demo data, and a new
     empty local database schema
   - keep records proportional: preserve every lasting revision, but update the
     development log, handoff, and changelog only when each adds useful context
   - run focused validation and commit only scoped paths
   - run the source-sync helper, which must fetch, verify a private destination,
     recheck `HEAD`, and allow only a fast-forward push of the real branch
   - if the audit blocks, keep the local commit, do not push or rewrite history,
     report rule IDs and paths only, and ask whether to run the sanitized
     fallback or remain local-only for that failure; ask again for each failure
   - when maintaining this source project, sync and hash-check the installed
     runtime payload before committing
   - report validation, commit, synchronization, and unresolved gaps

## User Interaction Standard

Do not ask the user to remember or paste the checklist path. If this skill is
triggered, use the bundled reference file.

Do not require the user to add words like "apply", "sync", or "update" after a
skill link. A bare skill invocation should run the target project's setup sync
when a target can be resolved safely. A response such as "Loaded
`new-project-setup`; no edits or actions taken" is incorrect for a bare
invocation unless the target is unresolved or the user explicitly requested
consultation only.

When the user asks a question about the skill, answer the question. Examples:
`Did that skill update the appropriate project docs?`, `Why did invoking the
skill edit files?`, and `What does this skill do?` are consultation turns, not
authorization to edit. In those cases, do not run install/sync and do not change
the source project, installed runtime skill, or current target project unless
the same message also contains an explicit instruction to apply, update, sync,
or maintain the workflow.

Ask only for decisions that cannot be inferred from the target project. Create
the default private repository under the authenticated GitHub account when
safe. Ask after each blocked source-history audit whether to use the isolated
fallback or remain local-only, and ask whether to create a ChatGPT export when
no export convention exists and long-term ChatGPT usage is unclear.

Global or native tool installation and machine-level Git identity changes
require explicit approval. Established project-local dependencies directly
needed by a bounded implementation objective do not require a separate routine
checkpoint. Explain missing prerequisites, ask when required, run the approved
command, and continue after rechecking the tool state.

Autonomous work does not weaken consequential boundaries. Ask before deployment;
credentials or live/paid services; auth/security changes; global or native tool
installation; framework or platform replacement; consequential licensing
changes; changes to existing, shared, or production data; destructive
operations; material product-direction expansion beyond the request; unrelated
conflicting work; or any unsafe state. Do not interrupt for internal refactoring,
routine project-local dependencies, or isolated local construction that remains
inside the bounded objective.

Scale durable memory to future value. A trivial lasting change can rely on its
revision and focused validation. Update the development log only for useful
decisions, rationale, failed approaches, validation, or lessons. Refresh the
handoff only when objective, state, blockers, next action, or continuation
context changes. Update the changelog only for notable reader-facing changes.

Maintain one public-ready, replace-in-place handoff for every durable project.
Refresh it at completed package or intentional handoff boundaries, not after
every small edit. On a new chat, read it and recent development-log entries
before acting. Use fast-forward only when clean and stop on dirty, diverged, or
concurrently changed state.
