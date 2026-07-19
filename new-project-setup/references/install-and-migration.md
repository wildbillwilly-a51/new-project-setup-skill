# Installation And Migration

Read this reference only for prerequisite, initialization, target-resolution,
or migration exceptions. The normal path is the deterministic apply helper.

## Resolve And Inspect

Resolve exactly one target in this order:

1. Explicit path in the current request.
2. Active chat or task project.
3. Current repository when unambiguous.
4. Ask which single project is intended.

An ordinary request to create or build a new durable app activates setup when
it needs a new project. Ordinary implementation, fixes, review, or continuation
inside an existing project does not. A bare skill invocation still runs setup.

Never update sibling roots in bulk. This source project uses maintenance mode:
run its source `scripts/apply-project-setup.ps1`, validate source changes, then
synchronize the installed runtime. Never run an older installed apply helper
over the source. Any other target receives the installed workflow without
modifying the source or runtime skill.

Inspect only what setup needs:

- Git root, identity, status, branch, `HEAD`, remotes, and upstream
- PowerShell 7 (`pwsh`) or Windows PowerShell 5.1 on Windows, plus `tar`, GitHub
  CLI, and `gh auth status`
- cloud-synchronized path warnings
- managed markers and `.codex/new-project-setup.json`
- concise handoff, directly relevant setup files, and overlapping dirty work

Target-project setup has no Python dependency. Source maintenance and release
validation additionally require Python 3 with PyYAML for metadata validation;
detect them automatically and ask before any global/native installation.

Do not load broad project history, dependency trees, generated output, or old
logs unless an observed exception requires them.

## Prerequisites And Local Git

Detect prerequisites automatically. Ask before global/native installation or a
machine-level Git identity change, run the approved command, recheck, and
continue. Established project-local dependencies for a bounded objective are
not prerequisite installation and need no routine checkpoint.

Prefer `pwsh` on Windows, macOS, and Linux. Fall back to `powershell.exe` only
on Windows. When the current shell is not PowerShell, use
`scripts/invoke-powershell.ps1` from PowerShell on Windows or
`sh scripts/invoke-powershell.sh` on macOS/Linux. These launchers select the
runtime; never make the user remember the platform-specific command. If no
supported runtime exists, ask before installing PowerShell 7.

After resolving one new-project path, create that directory when absent; do not
create speculative alternatives. Initialize Git only when absent. Establish
ignore and line-ending rules before staging. Warn when the Git root is in
OneDrive or another synchronized folder; GitHub, not folder synchronization, is
repository transport.

Before each scoped lasting commit, record branch, `HEAD`, and intended paths.
Recheck immediately before staging, stage only those paths, and run the exact
staged-tree and commit-message precommit audit described in
`github-history.md`. Commit that tree and message immediately. Stop only for
overlapping concurrent changes or unsafe state; never stage unrelated work.

## Apply Or Synchronize

For a normal target, run the helper from the invoked installed skill. From an
existing supported PowerShell host (PowerShell 7 on any platform, or Windows
PowerShell 5.1 on Windows):

```powershell
& <installed-skill>\scripts\apply-project-setup.ps1 -ProjectRoot <project>
```

When runtime selection is needed, pass that helper to the platform launcher:

```text
Windows PowerShell: & "<installed-skill>\scripts\invoke-powershell.ps1" "<installed-skill>\scripts\apply-project-setup.ps1" -ProjectRoot "<project>"
Windows non-PowerShell shell: powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "<installed-skill>\scripts\invoke-powershell.ps1" "<installed-skill>\scripts\apply-project-setup.ps1" -ProjectRoot "<project>"
macOS/Linux: sh "<installed-skill>/scripts/invoke-powershell.sh" "<installed-skill>/scripts/apply-project-setup.ps1" -ProjectRoot "<project>"
```

Pass `-Repository owner/name` and `-RemoteName <name>` when known. Use `-Check`
only for a non-mutating managed-payload drift report. The helper owns
managed-block replacement, workflow state, memory-file creation, and helper
synchronization; Codex still reviews project-specific handoff content. The
helper rejects redirected managed paths, malformed or duplicate markers, and an
installed-runtime attempt to overwrite the authoritative skill source. It
preflights all managed paths, markers, state, and helper ownership before its
first write; an unrelated script at a helper path is preserved and blocks setup.

## Version-6 Migration

Version 6 creates or refreshes:

- managed v6 blocks in `AGENTS.md`, `.gitignore`, and `.gitattributes`
- public-ready `docs/development-log.md`, `docs/codex-handoff.md`, and
  `CHANGELOG.md` when absent
- both GitHub helpers
- format-2 `.codex/new-project-setup.json` with private public-ready GitHub
  history, adaptive execution, progressive context, adaptive effort,
  risk-based validation, evidence reuse, convergence strategy, and
  proportional documentation
- exact staged-tree precommit auditing, verified-private-remote history
  boundaries, ten-commit focused-work batching, and guarded legacy recovery

When migrating v2, v3, v4, or v5:

- replace only the prior managed blocks
- preserve project-specific instructions outside markers
- preserve repository/remote state, existing memory, legacy files, and history
- never delete, untrack, sanitize, amend, or rewrite prior history during normal
  migration; the separate clean-baseline recovery requires explicit
  authorization and preserves the old exact tip in local hidden refs
- summarize legacy knowledge only after reviewing it for public readiness
- audit full ancestry for an absent destination with private-source rules and
  for public-readiness assessment with strict public-metadata rules; an existing
  exact private destination uses its verified tip as the boundary

If old history still blocks an empty destination on high-confidence secret or
unsafe Git findings, follow the guarded recovery or explicit fallback choices
in `github-history.md`; do not weaken policy to make migration pass.

Setup completion uses the single completion/evidence invariant in
`execution-and-memory.md`; migration does not define a weaker evidence unit or
terminal condition.
