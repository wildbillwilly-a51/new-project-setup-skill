# New Project Setup for Codex

`new-project-setup` installs a lean, local-first workflow for durable apps,
projects, and repositories. Workflow V7 keeps continuity in a stable project
summary and compact handoff, validates in proportion to risk, and saves only
explicitly scoped work to local Git.

V7 is active/default. V6 is retained only as frozen ownership evidence for a
bounded migration. The installable directory is an exact standalone 16-file
payload and contains no V6 GitHub helpers or predecessor-only references.

## What V7 Provides

- exact-root local Git initialization when a target is not already a repository
- progressive context instead of repeated broad project scans
- proportional validation and progress-aware debugging
- compact durable project continuity
- scoped, verified local commits
- transactional migration from an exact recognized V6 project
- local completion with no GitHub, remote, CI, ACF, external memory, or backup
  dependency
- a skill-owned global Manual/Automatic activation choice

Migrated V6 projects may retain legacy GitHub helpers byte-for-byte as inert,
unowned files. V7 neither invokes nor requires them.

## Requirements

- PowerShell Core 7.6 or later, invoked as `pwsh`
- Git

Windows PowerShell 5.1 fallback is not supported. The release has been
validated on Windows and Linux. macOS has not been directly validated, so no
macOS support result is claimed.

## Install or Update

Give Codex this exact skill-directory URL:

```text
https://github.com/wildbillwilly-a51/new-project-setup-skill/tree/main/new-project-setup
```

Then ask Codex to install, or update, the `new-project-setup` skill globally
from that GitHub path. Installing or updating the skill never changes the
user's activation choice.

## Use Manually

Open the intended project and invoke:

```text
$new-project-setup
```

Manual is the default. In Manual mode, existing projects are changed only when
the skill is explicitly invoked for that project. Questions about the skill
remain consultation-only.

## Choose the Global Default

The activation choice belongs to the Codex installation, not to each project.
Use the installed helper only when you explicitly want to change or inspect it:

```powershell
# Opt in once to bounded automatic activation for qualifying Git repositories.
pwsh -NoProfile -File <installed-skill>/scripts/configure-default-activation.ps1 `
  -Mode Automatic

# Return to explicit skill invocation for each project.
pwsh -NoProfile -File <installed-skill>/scripts/configure-default-activation.ps1 `
  -Mode Manual

# Read the current choice without writing.
pwsh -NoProfile -File <installed-skill>/scripts/configure-default-activation.ps1 `
  -Status
```

Automatic mode adds only the skill's marked block to the user-level Codex
`AGENTS.md` and preserves unrelated instructions. It invokes setup before
meaningful implementation in a Git repository whose workflow state is absent;
it does not trigger for read-only consultation or clearly disposable temporary
work. Updating the skill preserves the selected mode.

## Apply from the Installed Skill

```powershell
pwsh -NoProfile -File <installed-skill>/scripts/apply-project-setup.ps1 `
  -ProjectRoot <project>
```

Use `-Check` for a read-only drift check.

## Validate a Checkout

Source validation additionally requires Python 3 with PyYAML:

```powershell
pwsh -NoProfile -File .\new-project-setup\scripts\validate-skill.ps1 `
  -SkillRoot .\new-project-setup `
  -PayloadManifestPath .\skill-payload.json `
  -PayloadRole Installed
```

The manifest is distribution metadata outside the 16-file installable
directory.

## Security and License

See [SECURITY.md](SECURITY.md) for local-only trust boundaries and responsible
reporting guidance. This project is licensed under the [MIT License](LICENSE).
