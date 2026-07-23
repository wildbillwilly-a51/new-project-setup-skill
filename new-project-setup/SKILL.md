---
name: new-project-setup
description: Install or synchronize a lean local-first workflow for durable apps, projects, and repositories with progressive context, proportional validation, and scoped local Git saving. Use for explicit setup or sync requests, ordinary creation of a new durable project, and explicit global automatic/manual activation requests. Do not invoke for routine work inside an existing project unless the user enabled the skill's global automatic default and project workflow state is absent.
---

# New Project Setup

Install or synchronize one durable project workflow and keep normal completion
local, bounded, and resumable.

## Activation And Scope

A bare or primary `$new-project-setup` invocation applies or synchronizes the
workflow. Activate implicitly when creating a new durable app, project, or
repository. Ordinary implementation, fixes, review, and continuation inside an
existing project do not automatically reinstall setup in manual mode.

The global activation mode is a user-level choice, not a per-project setting.
Manual is the default and requires explicit skill invocation for each existing
project. Automatic mode is an explicit opt-in that installs a bounded managed
block in the user's global Codex `AGENTS.md`; it invokes this skill before
meaningful implementation in a Git repository whose workflow state is absent.
It does not trigger for read-only consultation or clearly disposable temporary
work, and it never broadens setup to sibling repositories.

Use `scripts/configure-default-activation.ps1` for explicit requests to enable,
disable, or inspect the global default. Skill installation or synchronization
must never silently select automatic mode. The helper owns only its marked
global block and preserves unrelated global instructions.

Resolve exactly one target from the request and active task subject. Never
update an accessible sibling project in bulk.

In this authoritative source project, update source first, validate it, then
transactionally synchronize the installed runtime. In every other project, use
the installed workflow for that target only; do not modify this source or the
installed runtime.

Questions about the skill are consultation-only and authorize no edits.

## Progressive Context

Orient with the smallest useful sequence:

1. Read `docs/project-summary.md` for stable project orientation.
2. Read `docs/codex-handoff.md` when continuing current work.
3. Inspect directly relevant files, diffs, and validation evidence.
4. Read or update `docs/development-log.md` only when durable reasoning has
   future maintenance value.
5. Broaden repository discovery only when evidence requires it.

Do not rediscover the whole repository at every session. Reconstruct stale or
missing context from Git and direct evidence only to the depth needed.

## Durable Context

`docs/project-summary.md` stores stable purpose, architecture, interfaces,
dependencies, commands, and constraints. `docs/codex-handoff.md` stores compact
current-work continuity and replaces obsolete task history instead of
accumulating a transcript. `docs/development-log.md` is conditional decision
memory, not a routine activity log. `.codex/new-project-setup.json` is
operational ownership state only.

Update durable context when objective state, decisions, blockers, validation,
or the next action materially changes. Keep machine-private details in ignored
local files.

## Apply Or Synchronize

Use the declared PowerShell launcher and active apply entry point. A default
application installs workflow version 7; `-Check` reports drift without writing.
Fresh targets receive only the lean declared payload and exact-root local Git
initialization when needed.

A recognized workflow-v6 target is migrated through the frozen bounded
contract described in `references/install-and-migration.md`. Its compatibility
export remains ignored and outside v7 ownership. Legacy target helpers are
preserved but inert.

Preserve project guidance outside managed markers, existing continuity,
history, and unrelated work. Recheck root, branch, `HEAD`, status, and scope at
write boundaries. Fail closed on modified ownership, redirected paths,
collisions, or concurrent change.

## Configure The Global Default

Map a clear user choice to one of these installed-skill operations:

```powershell
pwsh -NoProfile -File <installed-skill>/scripts/configure-default-activation.ps1 -Mode Automatic
pwsh -NoProfile -File <installed-skill>/scripts/configure-default-activation.ps1 -Mode Manual
pwsh -NoProfile -File <installed-skill>/scripts/configure-default-activation.ps1 -Status
```

Automatic and Manual mutate only the helper-owned block in the user-level
Codex `AGENTS.md`. `-Status` is read-only. A malformed or duplicated block,
unsafe path, invalid UTF-8 file, or concurrent change fails closed. Do not
reinterpret the global choice as per-project state, and do not change the mode
unless the user explicitly asks.

## Execution And Validation

Continue clear bounded work without routine questions. Preserve implementation
and reusable output; discard only disposable exploration created for the
current task and confirmed unused. Promote retained exploration automatically.

Validate proportionally to changed behavior and material risk. Reuse valid
evidence and rerun only failed or invalidated checks. When equivalent probes
repeat without material progress, change strategy and use a minimal
reproduction only when it can distinguish the remaining cause. Run no more than
one broad final matrix unless earlier evidence was invalidated.

Obtain authorization immediately before destructive actions, deployment,
machine-level installation, shared or production data changes, credentials,
paid services, or changes outside the resolved project. Routine bounded local
implementation, validation, and saving remain within scope.

Use `references/execution-and-continuity.md` for detailed execution, context,
validation, authorization, and durable-continuity rules.

## Local Saving And Completion

Save durable work through `scripts/save-local-work.ps1` using its accepted
`Prepare` then `Commit` protocol. Declare only whole-file or whole-directory
objective paths. Require its clean-index, exact-root, branch/HEAD, ownership,
content-scan, hook, and signing safety contracts. Preserve unrelated staged,
unstaged, and untracked work.

Update durable context before the scoped save when needed. Completion requires
current relevant validation, accurate continuity, and a successful local save
or an explicit accurate blocker. Ordinary scoped local saving is not remote
publication. A remote, GitHub repository, push, backup, transfer audit, or
remote CI result is never required for normal completion.

Use `references/local-saving.md` for protocol details and failure handling.

## Runtime

Active workflow automation requires PowerShell Core 7.6 or later through
`pwsh`. No Windows PowerShell fallback exists. Git is required for project
ownership and local saving. Application-stack selection remains outside this
skill.

## Reference Routes

- Prerequisites, target resolution, fresh installation, or v6 migration:
  `references/install-and-migration.md`
- Execution, context, validation, authorization, or continuity exceptions:
  `references/execution-and-continuity.md`
- Local Prepare/Commit protocol and failure handling:
  `references/local-saving.md`
- Final local setup and completion audit:
  `references/new-project-setup-checklist.md`
