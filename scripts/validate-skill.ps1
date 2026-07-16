[CmdletBinding()]
param([string]$SkillRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $SkillRoot).Path
$required = @(
    'SKILL.md',
    'agents\openai.yaml',
    'references\new-project-setup-checklist.md',
    'references\install-and-migration.md',
    'references\execution-and-memory.md',
    'references\github-history.md',
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
if ($skill.Length -gt 10000) { throw "SKILL.md exceeds the progressive-context size ceiling." }

$yaml = Get-Content -Raw -LiteralPath (Join-Path $root 'agents\openai.yaml')
foreach ($key in @('display_name', 'short_description', 'default_prompt')) {
    $pattern = '(?m)^\s+' + [Regex]::Escape($key) + ': "[^"]+"\s*$'
    if ($yaml -notmatch $pattern) { throw "agents/openai.yaml is missing quoted $key." }
}
if ($yaml -notmatch '\$new-project-setup') { throw "default_prompt must name `$new-project-setup." }
if ($yaml -notmatch '(?m)^\s+allow_implicit_invocation: true\s*$') { throw "New-project setup skill must allow implicit invocation." }
if ($skill -notmatch 'Do not trigger merely because an existing repository') {
    throw "Implicit invocation must remain limited to genuine setup requests."
}

$checklist = Get-Content -Raw -LiteralPath (Join-Path $root 'references\new-project-setup-checklist.md')
if ($checklist -notmatch '(?m)^## Reference Routing\s*$') { throw "Completion checklist must route conditional references." }

foreach ($relative in @('scripts\apply-project-setup.ps1', 'scripts\github-backup.ps1', 'scripts\github-sync.ps1', 'scripts\validate-skill.ps1')) {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile((Join-Path $root $relative), [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count) { throw "$relative parse failure: $($errors.Message -join '; ')" }
}

$apply = Get-Content -Raw -LiteralPath (Join-Path $root 'scripts\apply-project-setup.ps1')
foreach ($marker in @('WorkflowVersion = 5', 'new-project-setup:v5:start', 'docs\development-log.md', 'docs\codex-handoff.md', 'source_authority', 'target_path_policy', 'managed_marker_policy', 'apply_preflight', 'helper_ownership', 'execution_mode', 'durability_ambiguity_action', 'routine_project_dependencies', 'new_project_stack', 'isolated_local_build', 'exploration_cleanup', 'deployment_confirmation', 'documentation_detail', 'handoff_presence', 'handoff_refresh', 'handoff_evidence', 'handoff_sync_reference', 'context_loading', 'effort_classification', 'validation_strategy', 'risk_set', 'evidence_reuse', 'evidence_definition', 'convergence_action', 'convergence_escalation', 'final_validation_matrix', 'final_validation_scope', 'unresolved_local_failure', 'Assert-TargetPath', 'Get-ExistingManagedMarker', 'Assert-ManagedHelperOwnership', 'Refusing to apply an installed runtime')) {
    if ($apply -notmatch [Regex]::Escape($marker)) { throw "Version-5 apply helper is missing marker: $marker" }
}
$adaptiveText = $skill + "`n" + $checklist + "`n" + (Get-Content -Raw -LiteralPath (Join-Path $root 'references\execution-and-memory.md')) + "`n" + $apply
foreach ($marker in @('genuinely ambiguous', 'project-local dependencies', 'new empty local database', 'initial framework', 'never demote', 'confirmed are not reused', 'proportional', 'progressive context', 'compact ledger', 'change diagnostic strategy', 'effort-appropriate broad final matrix', 'bookkeeping-only')) {
    if ($adaptiveText -notmatch [Regex]::Escape($marker)) { throw "Adaptive execution guidance is missing marker: $marker" }
}
if ($skill -match 'Read `references/new-project-setup-checklist.md` before changing') {
    throw "SKILL.md must not require unconditional full-checklist loading."
}
foreach ($reference in @('install-and-migration.md', 'execution-and-memory.md', 'github-history.md')) {
    if ($skill -notmatch [Regex]::Escape($reference)) { throw "SKILL.md does not route conditional reference: $reference" }
}
$installText = Get-Content -Raw -LiteralPath (Join-Path $root 'references\install-and-migration.md')
$historyText = Get-Content -Raw -LiteralPath (Join-Path $root 'references\github-history.md')
$behaviorText = $adaptiveText + "`n" + $installText + "`n" + $historyText
$invariants = [ordered]@{
    'bare invocation executes' = 'bare or primary.*invocation.*runs install/sync'
    'implicit activation is new-project only' = 'activate implicitly only.*create,\s+start,\s+initialize, or\s+bootstrap'
    'consultation does not edit' = 'consultation-only.*authorizes no edits'
    'single target isolation' = 'Never update an accessible sibling project'
    'source and target maintenance are separated' = 'In another project,.*do not modify this source or runtime'
    'source maintenance is source first' = 'In this skill.*source.*run the source copy.*Never apply an older.*installed helper over source'
    'durability and risk remain independent' = 'Durability:.*Operational risk:'
    'routine work does not prompt' = 'Do not ask for routine implementation, context expansion, or.*validation transitions'
    'quick does not mean disposable' = 'Quick.*prototype.*MVP.*do not.*mean disposable'
    'exploration promotes and lasting work does not demote' = 'Promote useful exploration automatically; never.*demote lasting work'
    'bounded local build authority remains' = 'bounded local build authorizes architecture'
    'protected boundaries remain' = 'Ask before deployment; credentials or live/paid services'
    'lasting revisions remain in Git' = 'Preserve every lasting revision in Git'
    'durable memory remains proportional' = 'public-ready memory only where.*future value'
    'handoff bookkeeping converges' = 'successful push.*does not require a.*bookkeeping-only'
    'new project stack is locally authorized' = 'new empty project.*initial framework and dependencies.*architecture'
    'final evidence is effort appropriate' = 'effort-appropriate broad final matrix'
    'source history remains private and fast-forward only' = 'private.*fast-forward push'
    'isolated fallback remains explicit' = 'ask whether to use the.*fallback or remain local-only'
}
foreach ($entry in $invariants.GetEnumerator()) {
    if ($behaviorText -notmatch ('(?is)' + $entry.Value)) { throw "Behavior invariant missing: $($entry.Key)" }
}
$sync = Get-Content -Raw -LiteralPath (Join-Path $root 'scripts\github-sync.ps1')
foreach ($marker in @('AuditSourceHistory', 'Initialize', 'PublicReadiness', 'PRIVATE', 'merge-base', 'Source HEAD changed')) {
    if ($sync -notmatch [Regex]::Escape($marker)) { throw "GitHub sync helper is missing safety marker: $marker" }
}
foreach ($relative in @('scripts\github-sync.ps1', 'scripts\github-backup.ps1')) {
    if ((Get-Content -Raw -LiteralPath (Join-Path $root $relative)) -notmatch '(?m)^# new-project-setup:managed-helper:v1$') {
        throw "Managed helper ownership marker is missing: $relative"
    }
}

Write-Host "Validated new-project-setup skill payload at $root"
