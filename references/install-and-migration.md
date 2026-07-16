# Installation And Migration

Read this reference only for prerequisite, initialization, target-resolution,
or migration exceptions. The normal path is the deterministic apply helper.

## Resolve And Inspect

Resolve exactly one target in this order:

1. Explicit path in the current request.
2. Active chat or task project.
3. Current repository when unambiguous.
4. Ask which single project is intended.

Never update sibling roots in bulk. This source project uses maintenance mode:
run its source `scripts/apply-project-setup.ps1`, validate source changes, then
synchronize the installed runtime. Never run an older installed apply helper
over the source. Any other target receives the installed workflow without
modifying the source or runtime skill.

Inspect only what setup needs:

- Git root, identity, status, branch, `HEAD`, remotes, and upstream
- PowerShell, `tar`, GitHub CLI, and `gh auth status`
- cloud-synchronized path warnings
- managed markers and `.codex/new-project-setup.json`
- concise handoff, directly relevant setup files, and overlapping dirty work

Do not load broad project history, dependency trees, generated output, or old
logs unless an observed exception requires them.

## Prerequisites And Local Git

Detect prerequisites automatically. Ask before global/native installation or a
machine-level Git identity change, run the approved command, recheck, and
continue. Established project-local dependencies for a bounded objective are
not prerequisite installation and need no routine checkpoint.

After resolving one new-project path, create that directory when absent; do not
create speculative alternatives. Initialize Git only when absent. Establish
ignore and line-ending rules before staging. Warn when the Git root is in
OneDrive or another synchronized folder; GitHub, not folder synchronization, is
repository transport.

Before each scoped commit, record branch, `HEAD`, and intended paths. Recheck
immediately before staging and committing. Stop only for overlapping concurrent
changes or unsafe state; never stage unrelated work.

## Apply Or Synchronize

For a normal target, run the helper from the invoked installed skill:

```powershell
& <installed-skill>\scripts\apply-project-setup.ps1 -ProjectRoot <project>
```

Pass `-Repository owner/name` and `-RemoteName <name>` when known. Use `-Check`
only for a non-mutating managed-payload drift report. The helper owns
managed-block replacement, workflow state, memory-file creation, and helper
synchronization; Codex still reviews project-specific handoff content. The
helper rejects redirected managed paths, malformed or duplicate markers, and an
installed-runtime attempt to overwrite the authoritative skill source. It
preflights all managed paths, markers, state, and helper ownership before its
first write; an unrelated script at a helper path is preserved and blocks setup.

## Version-5 Migration

Version 5 creates or refreshes:

- managed v5 blocks in `AGENTS.md`, `.gitignore`, and `.gitattributes`
- public-ready `docs/development-log.md`, `docs/codex-handoff.md`, and
  `CHANGELOG.md` when absent
- both GitHub helpers
- format-2 `.codex/new-project-setup.json` with private public-ready GitHub
  history, adaptive execution, progressive context, adaptive effort,
  risk-based validation, evidence reuse, convergence strategy, and
  proportional documentation

When migrating v2, v3, or v4:

- replace only the prior managed blocks
- preserve project-specific instructions outside markers
- preserve repository/remote state, existing memory, legacy files, and history
- never delete, untrack, sanitize, amend, or rewrite prior history
- summarize legacy knowledge only after reviewing it for public readiness
- audit all ancestry before normal source-history synchronization

If old history blocks audit, follow `github-history.md`; do not weaken policy to
make migration pass.
