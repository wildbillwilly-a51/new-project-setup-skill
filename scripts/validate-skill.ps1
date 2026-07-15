[CmdletBinding()]
param([string]$SkillRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $SkillRoot).Path
$required = @(
    'SKILL.md',
    'agents\openai.yaml',
    'references\new-project-setup-checklist.md',
    'scripts\apply-project-setup.ps1',
    'scripts\github-backup.ps1',
    'scripts\github-sync.ps1',
    'scripts\validate-skill.ps1'
)

foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)) {
        throw "Missing required skill payload: $relative"
    }
}

$skill = Get-Content -Raw -LiteralPath (Join-Path $root 'SKILL.md')
if ($skill -notmatch '(?s)^---\r?\nname: new-project-setup\r?\ndescription: [^\r\n]+\r?\n---\r?\n') {
    throw "SKILL.md frontmatter is invalid."
}
if ((Get-Content -LiteralPath (Join-Path $root 'SKILL.md')).Count -ge 500) {
    throw "SKILL.md must remain under 500 lines."
}

$yaml = Get-Content -Raw -LiteralPath (Join-Path $root 'agents\openai.yaml')
foreach ($key in @('display_name', 'short_description', 'default_prompt')) {
    $pattern = '(?m)^\s+' + [Regex]::Escape($key) + ': "[^"]+"\s*$'
    if ($yaml -notmatch $pattern) { throw "agents/openai.yaml is missing quoted $key." }
}
if ($yaml -notmatch '\$new-project-setup') { throw "default_prompt must name `$new-project-setup." }
if ($yaml -notmatch '(?m)^\s+allow_implicit_invocation: true\s*$') { throw "New-project setup skill must allow implicit invocation." }
if ($skill -notmatch 'Do not trigger merely because Codex opened an existing repository') {
    throw "Implicit invocation must remain limited to genuine setup requests."
}

$checklist = Get-Content -Raw -LiteralPath (Join-Path $root 'references\new-project-setup-checklist.md')
if ($checklist -notmatch '(?m)^## Contents\s*$') { throw "Long checklist must contain a table of contents." }

foreach ($relative in @('scripts\apply-project-setup.ps1', 'scripts\github-backup.ps1', 'scripts\github-sync.ps1', 'scripts\validate-skill.ps1')) {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile((Join-Path $root $relative), [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count) { throw "$relative parse failure: $($errors.Message -join '; ')" }
}

$apply = Get-Content -Raw -LiteralPath (Join-Path $root 'scripts\apply-project-setup.ps1')
foreach ($marker in @('WorkflowVersion = 4', 'new-project-setup:v4:start', 'docs\development-log.md', 'docs\codex-handoff.md', 'execution_mode', 'durability_ambiguity_action', 'routine_project_dependencies', 'isolated_local_build', 'documentation_detail')) {
    if ($apply -notmatch [Regex]::Escape($marker)) { throw "Version-4 apply helper is missing marker: $marker" }
}
$adaptiveText = $skill + "`n" + (Get-Content -Raw -LiteralPath (Join-Path $root 'references\new-project-setup-checklist.md')) + "`n" + $apply
foreach ($marker in @('genuinely ambiguous', 'project-local dependencies', 'new empty local database', 'never demote', 'proportional')) {
    if ($adaptiveText -notmatch [Regex]::Escape($marker)) { throw "Adaptive execution guidance is missing marker: $marker" }
}
$sync = Get-Content -Raw -LiteralPath (Join-Path $root 'scripts\github-sync.ps1')
foreach ($marker in @('AuditSourceHistory', 'Initialize', 'PublicReadiness', 'PRIVATE', 'merge-base', 'Source HEAD changed')) {
    if ($sync -notmatch [Regex]::Escape($marker)) { throw "GitHub sync helper is missing safety marker: $marker" }
}

Write-Host "Validated new-project-setup skill payload at $root"
