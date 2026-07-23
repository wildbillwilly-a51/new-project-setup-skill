# Installation And Migration

Use this reference for prerequisites, target resolution, exact-root Git
initialization, fresh workflow-v7 application, or bounded v6 migration.

## Resolve One Target

Resolve exactly one target from the explicit path, named project, or active task
subject. Normalize the absolute path and reject redirected roots, unsafe
ancestors, ambiguous candidates, or sibling-project expansion.

When the target is this authoritative source project, maintain source first,
validate it, and use the committed source synchronization helper for the
installed runtime. In another project, use only the installed workflow against
that target.

## Prerequisites

Require:

- PowerShell Core 7.6 or later through `pwsh`
- Git
- an ordinary target directory

The PowerShell launchers select only a qualifying `pwsh`. An older Windows host
may run `invoke-powershell.ps1` solely as a bootstrap that locates and launches
Core 7.6 or later; it never executes the target workflow under Windows
PowerShell. Ask before machine-level installation when a prerequisite is
missing.

## Exact-Root Local Git

Resolve the target and its current Git top-level path. If no repository exists,
initialize Git quietly at the exact target root. If Git resolves to a different
root or the target crosses a redirected path, stop. Setup never rewrites
history, configures a remote, or requires network access.

## Active Application

Run the installed launcher and ordinary active entry point:

```powershell
pwsh -NoProfile -File <installed-skill>/scripts/apply-project-setup.ps1 -ProjectRoot <project>
```

Use `-Check` for a read-only drift report. The entry point exposes only
`ProjectRoot` and `Check`, requires Core 7.6 or later, and dispatches workflow 7
without a version selector or opt-in flag.

Fresh application installs only the declared lean payload: v7 managed blocks,
format-3 operational state, project-local execution and saving references,
stable summary and replace-in-place handoff templates, and the local-save
helper. Existing nonempty continuity and unrelated files are preserved.

## Choose The Global Activation Mode

The activation choice is global to one Codex installation, not stored in each
project. Installing or synchronizing the skill leaves **Manual** mode in place
unless the user explicitly opts into **Automatic** mode.

Use the installed helper:

```powershell
pwsh -NoProfile -File <installed-skill>/scripts/configure-default-activation.ps1 -Mode Automatic
pwsh -NoProfile -File <installed-skill>/scripts/configure-default-activation.ps1 -Mode Manual
pwsh -NoProfile -File <installed-skill>/scripts/configure-default-activation.ps1 -Status
```

Automatic mode adds one managed block to the user-level Codex `AGENTS.md`.
That block directs Codex to invoke this skill before meaningful implementation
in a Git repository when project workflow state is absent. Manual mode removes
only that block. Read-only consultation and disposable temporary work do not
trigger automatic setup. Neither mode changes a project by itself.

The helper resolves `CODEX_HOME`, falling back to the platform-default Codex
home. It preserves unrelated global instructions and their UTF-8 BOM and line
endings, is idempotent, and fails closed on unsafe paths, invalid text,
malformed or duplicate markers, or concurrent change.

## Bounded V6 Target Migration

The active helper contains a frozen recognition contract for the accepted v6
state invariants, normalized managed blocks, generated handoff, and recognized
legacy-helper hashes. It does not require or execute predecessor source files.

Only an exact recognized v6 candidate migrates. During migration:

- custom content outside exact managed blocks is preserved
- legacy target `scripts/github-sync.ps1` and `scripts/github-backup.ps1` files
  are classified and preserved byte-for-byte; v7 neither owns nor executes them
- the bounded legacy GitHub state is written once to
  `.codex/migrations/new-project-setup-v6-github.local.json`
- the export is private compatibility output that v7 never consumes
- normal tracked-aware `git check-ignore` must prove the export effectively
  ignored before success
- only the exact generated-v6 handoff is normalized to the v7 template
- the final workflow state is lean format 3

Target writes, export creation, and exact-root Git initialization share one
transaction. Any failure restores eligible paths, removes a newly created
export, removes Git when this operation created it, and preserves externally
changed paths under the rollback-safety rules.

## Failure Boundaries

Stop without mutation for malformed or expanded predecessor state, modified
managed blocks, unsafe links, occupied managed paths, target collisions,
concurrent changes, an occupied export path, inability to prove the export
ignored, or missing Core 7.6 runtime. Report the exact bounded blocker without
printing private export contents.
