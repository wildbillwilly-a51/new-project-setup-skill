# New Project Setup for Codex

`new-project-setup` is a Codex skill for durable, low-intervention project work.
It lets Codex handle routine implementation, validation, project memory, local
Git commits, and audited private GitHub synchronization without requiring the
user to remember special commands or workflow prompts.

## What It Does

- Applies or refreshes the workflow when `$new-project-setup` is invoked by
  itself in a resolved project.
- Activates automatically when Codex creates a new durable application or
  project, but not for ordinary work inside an existing project.
- Infers durability, operational risk, and effort independently, then completes
  bounded local work without routine approval checkpoints.
- Uses progressive context, proportional development memory, distinct-risk
  evidence, and progress-aware debugging to avoid repeated broad review loops.
- Maintains public-ready source history while keeping credentials and private
  operational details local.
- Creates private GitHub repositories when needed and audits every source commit
  before fast-forward synchronization.
- Preserves a separately authorized isolated sanitized fallback when legacy
  source history cannot pass the full audit.

Deployment, credentials, security changes, destructive operations, existing or
production data, global tool installation, and other protected effects retain
explicit authorization boundaries.

## Install

Give Codex this exact skill-directory URL:

```text
https://github.com/wildbillwilly-a51/new-project-setup-skill/tree/main/new-project-setup
```

Then ask:

```text
Install the new-project-setup skill globally for this Codex installation from
that GitHub path.
```

The `new-project-setup/` directory is the exact ten-file installable payload.
Restart Codex if the installed skill is not recognized immediately.

## Use

Open the intended project and invoke:

```text
$new-project-setup
```

The workflow applies to that project only. Questions about the skill remain
consultation-only and do not modify a project.

## Update

Give Codex the same skill-directory URL and ask it to update the globally
installed `new-project-setup` skill. Existing projects adopt the updated
workflow when `$new-project-setup` is invoked in each project.

## Validate

From a PowerShell prompt in a clone of this repository:

```powershell
.\new-project-setup\scripts\validate-skill.ps1 -SkillRoot .\new-project-setup
```

## License

Licensed under the [MIT License](LICENSE).
