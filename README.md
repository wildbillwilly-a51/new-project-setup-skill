# New Project Setup for Codex

`new-project-setup` is a Codex skill for people who want Codex to handle the
routine project workflow without requiring them to remember Git commands,
documentation steps, or special prompt wording.

It keeps the local project as the working copy while adding durable development
memory, scoped local commits, private GitHub synchronization, and safety checks
for information that should not be published.

## What it does

- Infers whether work is lasting or exploratory from ordinary language.
- Preserves useful decisions, validation results, and continuation context.
- Maintains a development log, changelog, and concise cross-chat handoff.
- Makes focused local commits without mixing unrelated work.
- Audits committed files and history before GitHub synchronization.
- Creates private GitHub repositories by default when GitHub CLI is ready.
- Offers an isolated sanitized fallback when older source history cannot safely
  be synchronized.
- Keeps approval boundaries for deployment, credentials, security changes,
  destructive operations, production data, and other consequential work.

The detailed behavior is documented in
[`references/new-project-setup-checklist.md`](references/new-project-setup-checklist.md).

## Install

The easiest installation method is to give Codex this repository URL:

```text
https://github.com/wildbillwilly-a51/new-project-setup-skill
```

Then ask:

```text
Install the new-project-setup skill globally for this Codex installation from
this repository.
```

Codex can use its built-in skill installer to place the skill under the current
Codex installation's skills directory. Restart Codex if the installed skill is
not recognized immediately.

## Use

Open the project you want to configure and invoke:

```text
$new-project-setup
```

The workflow applies to that project only. It can also activate automatically
when Codex creates or initializes a new durable project. Merely opening an
existing project does not modify it.

Questions about the skill are consultation-only. Asking what it does or why it
behaved a certain way does not authorize project changes.

## Update

Give Codex this repository URL again and ask it to update the globally installed
`new-project-setup` skill from the repository.

Updating the installed skill changes the reusable workflow for future
invocations. Existing projects are updated individually when
`$new-project-setup` is invoked in each project.

## GitHub behavior

Repositories created by the workflow start private. Tracked content is kept
public-ready, but the skill never changes repository visibility automatically.
Making a project public remains a separate, explicit decision.

## Validate

From a PowerShell prompt in a clone of this repository:

```powershell
.\scripts\validate-skill.ps1
.\tests\run-tests.ps1
```

## License

Licensed under the [MIT License](LICENSE).
