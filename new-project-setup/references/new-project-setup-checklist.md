# New Project Setup Checklist

Use this checklist for a final local setup audit or troubleshooting. Load the
specialized references first when only one area is uncertain.

## Target And Runtime

- exactly one project root is resolved
- the root is an ordinary, nonredirected directory
- PowerShell Core 7.6 or later is available through `pwsh`
- Git is available
- application-stack selection remains project-specific

## Application

- default invocation selects workflow version 7
- `-Check` is read-only and returns current or changes-required accurately
- fresh application initializes Git at the exact project root when absent
- existing unrelated files and content outside managed markers are preserved
- managed targets, parents, and state contain no unsafe links or collisions
- format-3 state owns exactly the declared v7 blocks and managed files

## Global Activation Choice

- the skill defaults to Manual and never silently enables Automatic mode
- `-Status` reports the global mode without writing
- Automatic installs exactly one helper-owned global `AGENTS.md` block
- Manual removes only that block and preserves unrelated global instructions
- the choice belongs to the Codex installation, not individual projects
- automatic setup targets one qualifying Git repository and never siblings
- malformed markers, unsafe paths, invalid UTF-8, and concurrent change fail closed

## Bounded V6 Migration

- only the exact frozen v6 state and managed blocks are recognized
- the one-time compatibility export is created transactionally and is
  effectively ignored by normal tracked-aware Git behavior
- migration failure removes the export and restores changed targets exactly
- legacy target GitHub helpers are preserved byte-for-byte but remain inert and
  unowned by v7
- generated-v6 handoff normalization occurs only for the exact frozen default
- migration executes no GitHub helper and contacts no remote

## Lean Payload And Continuity

- `docs/project-summary.md` provides stable orientation
- `docs/codex-handoff.md` contains compact current continuity
- `docs/development-log.md` is updated only for durable reasoning
- active references route execution/context and local-saving details
- `scripts/save-local-work.ps1` is installed
- no predecessor-only GitHub helper or history reference is installed

## Validation And Saving

- directly affected checks pass under PowerShell Core 7.6 or later
- valid evidence is reused and only invalidated risks are rerun
- no more than one broad final matrix is run without invalidation
- durable context is current before saving
- Prepare receives only declared whole-file or whole-directory objective paths
- Prepare returns a valid expected branch, `HEAD`, tree, and scope
- Commit rechecks the prepared identities and reports the exact local outcome
- unrelated staged, unstaged, and untracked work remains untouched

## Completion

- current acceptance criteria and material local risks have evidence
- continuity accurately records completed and remaining validation
- the scoped local save succeeded, or an explicit accurate blocker is recorded
- no remote service or remote CI result is required for normal completion
- protected actions received authorization immediately before execution
