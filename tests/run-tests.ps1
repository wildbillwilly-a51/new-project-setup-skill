$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$backupScript = Join-Path $projectRoot 'scripts\github-backup.ps1'
$githubSyncScript = Join-Path $projectRoot 'scripts\github-sync.ps1'
$applyScript = Join-Path $projectRoot 'scripts\apply-project-setup.ps1'
$syncScript = Join-Path $projectRoot 'scripts\sync-installed-skill.ps1'
$behaviorScript = Join-Path $projectRoot 'tests\run-behavior-evaluations.ps1'
$testRoot = Join-Path $env:TEMP ("new-project-setup-tests-" + [Guid]::NewGuid().ToString('N'))

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Initialize-TestRepo {
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    git -C $Path init -b main | Out-Null
    git -C $Path config user.name Fixture
    git -C $Path config user.email fixture@example.invalid
}

function Commit-All {
    param([string]$Path, [string]$Message = 'fixture')
    git -C $Path add --all
    git -C $Path commit -m $Message | Out-Null
}

function Invoke-BackupChild {
    param([string]$Path, [string]$Repository, [switch]$ScanOnly)
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $backupScript, '-ProjectRoot', $Path)
    if ($Repository) { $arguments += @('-Repository', $Repository) }
    if ($ScanOnly) { $arguments += '-ScanOnly' }
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & powershell @arguments *> $null
        return $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Invoke-SyncChild {
    param([string]$Path, [switch]$ScanOnly, [switch]$PublicReadiness)
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $githubSyncScript, '-ProjectRoot', $Path)
    if ($ScanOnly) { $arguments += '-ScanOnly' }
    if ($PublicReadiness) { $arguments += '-PublicReadiness' }
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & powershell @arguments *> $null
        return $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
}

function Invoke-ApplyChild {
    param([string]$Path, [string]$ScriptPath = $applyScript, [switch]$Check)
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath, '-ProjectRoot', $Path)
    if ($Check) { $arguments += '-Check' }
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & powershell @arguments *> $null
        return $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
}

function New-FakeGh {
    param([string]$BinPath, [string]$RemotePath, [string]$Visibility = 'PRIVATE')
    New-Item -ItemType Directory -Force -Path $BinPath | Out-Null
    $json = '{"url":"' + ($RemotePath -replace '\\', '\\') + '","visibility":"' + $Visibility + '","nameWithOwner":"owner/repo"}'
    Set-Content -LiteralPath (Join-Path $BinPath 'gh.cmd') -Encoding ascii -Value @(
        '@echo off',
        'if "%1 %2"=="auth status" exit /b 0',
        'if "%1 %2 %5"=="repo view nameWithOwner" echo owner/repo& exit /b 0',
        ('if "%1 %2"=="repo view" echo {0}& exit /b 0' -f $json),
        'if "%1 %2"=="repo create" exit /b 0',
        'exit /b 1'
    )
}

New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
try {
    $scripts = @(
        'scripts\apply-project-setup.ps1',
        'scripts\github-backup.ps1',
        'scripts\github-sync.ps1',
        'scripts\sync-installed-skill.ps1',
        'scripts\sync-from-installed-skill.ps1',
        'scripts\validate-skill.ps1',
        'tests\run-behavior-evaluations.ps1'
    )
    foreach ($relative in $scripts) {
        $tokens = $null
        $errors = $null
        [Management.Automation.Language.Parser]::ParseFile((Join-Path $projectRoot $relative), [ref]$tokens, [ref]$errors) | Out-Null
        Assert-True ($errors.Count -eq 0) "PowerShell parse failed: $relative"
    }

    $applyRepo = Join-Path $testRoot 'apply'
    Initialize-TestRepo $applyRepo
    Set-Content -LiteralPath (Join-Path $applyRepo 'AGENTS.md') -Value "# Project`r`n`r`n- Preserve this rule."
    & powershell -NoProfile -ExecutionPolicy Bypass -File $applyScript -ProjectRoot $applyRepo *> $null
    Assert-True ($LASTEXITCODE -eq 0) 'Target apply failed.'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $applyScript -ProjectRoot $applyRepo -Check *> $null
    Assert-True ($LASTEXITCODE -eq 0) 'Target apply is not idempotent.'
    $agents = Get-Content -Raw -LiteralPath (Join-Path $applyRepo 'AGENTS.md')
    $normalizedAgents = ($agents -replace '\s+', ' ').ToLowerInvariant()
    Assert-True $agents.Contains('Preserve this rule') 'Target apply removed project-specific guidance.'
    Assert-True $agents.Contains('new-project-setup:v5:start') 'Target apply marker missing.'
    foreach ($marker in @(
        'ambiguous durability',
        'do not imply it',
        'reasonable initial stack',
        'confirmed unused',
        'never demote',
        'Proportional durable memory',
        'operational risk, and effort independently',
        'Do not ask for routine implementation, context expansion, or validation transitions',
        'another equivalent screenshot is not new evidence',
        'retest only failed/invalidated cells',
        'run one effort-appropriate final matrix',
        'do not start another broad matrix',
        'strategy change',
        'report an unresolved blocker',
        'valid and remaining evidence',
        'bookkeeping-only commit',
        'obtain separate confirmation immediately before deployment',
        'source helper, then sync runtime'
    )) {
        Assert-True $normalizedAgents.Contains($marker.ToLowerInvariant()) "Adaptive target guidance is missing: $marker"
    }
    Assert-True (Test-Path -LiteralPath (Join-Path $applyRepo 'docs\development-log.md')) 'Development log was not installed.'
    Assert-True (Test-Path -LiteralPath (Join-Path $applyRepo 'docs\codex-handoff.md')) 'Codex handoff was not installed.'
    $initialHandoff = Get-Content -Raw -LiteralPath (Join-Path $applyRepo 'docs\codex-handoff.md')
    Assert-True ($initialHandoff -match 'validation, commit, and GitHub synchronization remain') 'Initial handoff falsely reports completed setup.'
    Assert-True ($initialHandoff -notmatch 'Project setup complete') 'Initial handoff claims completion before validation.'
    Assert-True (Test-Path -LiteralPath (Join-Path $applyRepo 'scripts\github-sync.ps1')) 'GitHub sync helper was not installed.'
    $state = Get-Content -Raw -LiteralPath (Join-Path $applyRepo '.codex\new-project-setup.json') | ConvertFrom-Json
    Assert-True ([int]$state.workflow_version -eq 5 -and $state.github_mode -eq 'private-public-ready') 'Version-5 workflow state is invalid.'
    Assert-True ($state.audit_failure_action -eq 'ask' -and $state.codex_handoff -eq 'always') 'Version-5 interaction or memory state is invalid.'
    Assert-True ($state.handoff_presence -eq 'required' -and $state.handoff_refresh -eq 'state-boundary') 'Handoff presence or refresh state is invalid.'
    Assert-True ($state.handoff_evidence -eq 'summary' -and $state.handoff_sync_reference -eq 'containing-commit') 'Handoff evidence or sync-reference state is invalid.'
    Assert-True ($state.execution_mode -eq 'adaptive' -and $state.durability_ambiguity_action -eq 'ask') 'Adaptive classification state is invalid.'
    Assert-True ($state.classification_notice -eq 'concise' -and $state.documentation_detail -eq 'proportional') 'Adaptive communication or documentation state is invalid.'
    Assert-True ($state.routine_project_dependencies -eq 'allow' -and $state.new_project_stack -eq 'allow' -and $state.isolated_local_build -eq 'allow') 'Routine local build authority is invalid.'
    Assert-True ($state.exploration_cleanup -eq 'own-current-artifacts-only' -and $state.deployment_confirmation -eq 'separate') 'Exploration cleanup or deployment confirmation state is invalid.'
    Assert-True ($state.context_loading -eq 'progressive' -and $state.effort_classification -eq 'adaptive') 'Progressive context or adaptive effort state is invalid.'
    Assert-True ($state.validation_strategy -eq 'risk-based' -and $state.evidence_reuse -eq 'required') 'Validation or evidence-reuse state is invalid.'
    Assert-True ($state.convergence_action -eq 'change-strategy' -and $state.final_validation_matrix -eq 'one-broad-pass-then-invalidated-only' -and $state.final_validation_scope -eq 'effort-appropriate') 'Convergence or final-matrix state is invalid.'
    Assert-True ($state.evidence_definition -eq 'distinct-risk' -and $state.convergence_escalation -eq 'minimal-reproducer') 'Evidence definition or convergence escalation state is invalid.'
    Assert-True ($state.risk_set -eq 'bounded-to-objective' -and $state.unresolved_local_failure -eq 'preserve-and-report') 'Risk-set or unresolved-failure state is invalid.'
    Assert-True ($state.source_authority -eq 'source-first' -and $state.target_path_policy -eq 'contained-no-reparse' -and $state.managed_marker_policy -eq 'unique-fail-closed') 'Source authority, target containment, or marker state is invalid.'
    Assert-True ($state.apply_preflight -eq 'fail-before-write' -and $state.helper_ownership -eq 'marker-or-known-hash') 'Apply preflight or helper ownership state is invalid.'
    $attributeCheck = git -C $applyRepo check-attr text -- README.md 2>&1
    Assert-True ($LASTEXITCODE -eq 0) "Generated .gitattributes is invalid: $($attributeCheck -join ' ')"

    $emptyMemoryRepo = Join-Path $testRoot 'empty-memory'
    Initialize-TestRepo $emptyMemoryRepo
    New-Item -ItemType Directory -Force -Path (Join-Path $emptyMemoryRepo 'docs') | Out-Null
    foreach ($relative in @('docs\development-log.md', 'docs\codex-handoff.md', 'CHANGELOG.md')) {
        [IO.File]::WriteAllText((Join-Path $emptyMemoryRepo $relative), '')
    }
    Assert-True ((Invoke-ApplyChild $emptyMemoryRepo) -eq 0) 'Empty memory-file repair failed.'
    Assert-True ((Get-Content -Raw -LiteralPath (Join-Path $emptyMemoryRepo 'docs\development-log.md')) -match '# Development Log') 'Empty development log was not initialized.'
    Assert-True ((Get-Content -Raw -LiteralPath (Join-Path $emptyMemoryRepo 'docs\codex-handoff.md')) -match 'Validation remaining') 'Empty handoff was not initialized.'
    Assert-True ((Get-Content -Raw -LiteralPath (Join-Path $emptyMemoryRepo 'CHANGELOG.md')) -match '# Changelog') 'Empty changelog was not initialized.'

    $malformedRepo = Join-Path $testRoot 'malformed-marker'
    Initialize-TestRepo $malformedRepo
    Set-Content -LiteralPath (Join-Path $malformedRepo 'AGENTS.md') -Value @(
        '# Existing guidance',
        '<!-- new-project-setup:v5:start -->',
        'unterminated managed block'
    )
    $malformedBefore = Get-Content -Raw -LiteralPath (Join-Path $malformedRepo 'AGENTS.md')
    Assert-True ((Invoke-ApplyChild $malformedRepo) -ne 0) 'Incomplete managed markers were accepted.'
    Assert-True ((Get-Content -Raw -LiteralPath (Join-Path $malformedRepo 'AGENTS.md')) -eq $malformedBefore) 'Incomplete marker failure modified project guidance.'

    $duplicateRepo = Join-Path $testRoot 'duplicate-marker'
    Initialize-TestRepo $duplicateRepo
    Set-Content -LiteralPath (Join-Path $duplicateRepo 'AGENTS.md') -Value @(
        '<!-- new-project-setup:v5:start -->',
        'first block',
        '<!-- new-project-setup:v5:end -->',
        '<!-- new-project-setup:v5:start -->',
        'second block',
        '<!-- new-project-setup:v5:end -->'
    )
    $duplicateBefore = Get-Content -Raw -LiteralPath (Join-Path $duplicateRepo 'AGENTS.md')
    Assert-True ((Invoke-ApplyChild $duplicateRepo) -ne 0) 'Duplicate managed markers were accepted.'
    Assert-True ((Get-Content -Raw -LiteralPath (Join-Path $duplicateRepo 'AGENTS.md')) -eq $duplicateBefore) 'Duplicate marker failure modified project guidance.'

    $lateMarkerRepo = Join-Path $testRoot 'late-malformed-marker'
    Initialize-TestRepo $lateMarkerRepo
    Set-Content -LiteralPath (Join-Path $lateMarkerRepo 'AGENTS.md') -Value @(
        '<!-- new-project-setup:v4:start -->',
        'legacy agents block',
        '<!-- new-project-setup:v4:end -->'
    )
    Set-Content -LiteralPath (Join-Path $lateMarkerRepo '.gitignore') -Value @(
        '# new-project-setup:v4:start',
        'unterminated ignore block'
    )
    $lateAgentsBefore = Get-Content -Raw -LiteralPath (Join-Path $lateMarkerRepo 'AGENTS.md')
    Assert-True ((Invoke-ApplyChild $lateMarkerRepo) -ne 0) 'Late malformed markers were accepted.'
    Assert-True ((Get-Content -Raw -LiteralPath (Join-Path $lateMarkerRepo 'AGENTS.md')) -eq $lateAgentsBefore) 'Marker preflight failed after partially migrating AGENTS.md.'

    $invalidStateRepo = Join-Path $testRoot 'invalid-state'
    Initialize-TestRepo $invalidStateRepo
    New-Item -ItemType Directory -Force -Path (Join-Path $invalidStateRepo '.codex') | Out-Null
    Set-Content -LiteralPath (Join-Path $invalidStateRepo '.codex\new-project-setup.json') -Value '{invalid-json'
    Assert-True ((Invoke-ApplyChild $invalidStateRepo) -ne 0) 'Invalid workflow state was overwritten.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $invalidStateRepo 'AGENTS.md'))) 'Invalid state failure occurred after partial managed writes.'

    $redirectRepo = Join-Path $testRoot 'redirected-target'
    $redirectOutside = Join-Path $testRoot 'redirected-outside'
    Initialize-TestRepo $redirectRepo
    New-Item -ItemType Directory -Force -Path $redirectOutside | Out-Null
    New-Item -ItemType Junction -Path (Join-Path $redirectRepo 'docs') -Target $redirectOutside | Out-Null
    Assert-True ((Invoke-ApplyChild $redirectRepo) -ne 0) 'Redirected managed directory was accepted.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $redirectOutside 'development-log.md'))) 'Apply escaped the resolved target through a junction.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $redirectRepo 'AGENTS.md'))) 'Redirect failure occurred after partial managed writes.'

    $rootTarget = Join-Path $testRoot 'redirected-root-target'
    $rootLink = Join-Path $testRoot 'redirected-root-link'
    Initialize-TestRepo $rootTarget
    New-Item -ItemType Junction -Path $rootLink -Target $rootTarget | Out-Null
    Assert-True ((Invoke-ApplyChild $rootLink) -ne 0) 'Redirected project root was accepted.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $rootTarget 'AGENTS.md'))) 'Root-link refusal occurred after managed writes.'

    $customHelperRepo = Join-Path $testRoot 'custom-helper-collision'
    Initialize-TestRepo $customHelperRepo
    New-Item -ItemType Directory -Force -Path (Join-Path $customHelperRepo 'scripts') | Out-Null
    $customHelperPath = Join-Path $customHelperRepo 'scripts\github-sync.ps1'
    Set-Content -LiteralPath $customHelperPath -Value 'Write-Host "project-owned helper"'
    $customHelperBefore = Get-Content -Raw -LiteralPath $customHelperPath
    Assert-True ((Invoke-ApplyChild $customHelperRepo) -ne 0) 'Unowned existing helper was overwritten.'
    Assert-True ((Get-Content -Raw -LiteralPath $customHelperPath) -eq $customHelperBefore) 'Helper collision changed the project-owned script.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $customHelperRepo 'AGENTS.md'))) 'Helper collision occurred after partial managed writes.'

    $legacyHelperRepo = Join-Path $testRoot 'legacy-helper-migration'
    Initialize-TestRepo $legacyHelperRepo
    New-Item -ItemType Directory -Force -Path (Join-Path $legacyHelperRepo 'scripts') | Out-Null
    $legacyHelpers = [ordered]@{
        'github-sync.ps1' = 'A45C8209D821F4B2A4CF4628F7D72D2CA993C3B7F76F2E58D6BF6B5F7AADDEEE'
        'github-backup.ps1' = 'C66D2E0D35950309D4ED0FAF774FFC07C50BEB8637FFA5BC456A373415DFAA50'
    }
    foreach ($entry in $legacyHelpers.GetEnumerator()) {
        $sourcePath = Join-Path $projectRoot "scripts\$($entry.Key)"
        $targetPath = Join-Path $legacyHelperRepo "scripts\$($entry.Key)"
        $bytes = [IO.File]::ReadAllBytes($sourcePath)
        $lineEnd = [Array]::IndexOf($bytes, [byte]10)
        Assert-True ($lineEnd -gt 0) "Managed helper marker line is missing: $($entry.Key)"
        $legacyBytes = New-Object byte[] ($bytes.Length - $lineEnd - 1)
        [Array]::Copy($bytes, $lineEnd + 1, $legacyBytes, 0, $legacyBytes.Length)
        [IO.File]::WriteAllBytes($targetPath, $legacyBytes)
        Assert-True ((Get-FileHash -Algorithm SHA256 $targetPath).Hash -eq $entry.Value) "Legacy helper fixture hash changed: $($entry.Key)"
    }
    Assert-True ((Invoke-ApplyChild $legacyHelperRepo) -eq 0) 'Known legacy helpers did not migrate.'
    foreach ($name in $legacyHelpers.Keys) {
        Assert-True ((Get-Content -Raw -LiteralPath (Join-Path $legacyHelperRepo "scripts\$name")).Contains('# new-project-setup:managed-helper:v1')) "Managed helper marker missing after migration: $name"
    }

    $sourceLikeRepo = Join-Path $testRoot 'source-authority'
    Initialize-TestRepo $sourceLikeRepo
    New-Item -ItemType Directory -Force -Path (Join-Path $sourceLikeRepo 'scripts') | Out-Null
    Set-Content -LiteralPath (Join-Path $sourceLikeRepo 'scripts\sync-installed-skill.ps1') -Value 'source sentinel'
    Set-Content -LiteralPath (Join-Path $sourceLikeRepo 'AGENTS.md') -Value 'authoritative guidance'
    Assert-True ((Invoke-ApplyChild $sourceLikeRepo) -ne 0) 'Installed-style apply was allowed to overwrite a partial source project.'
    Assert-True ((Get-Content -Raw -LiteralPath (Join-Path $sourceLikeRepo 'AGENTS.md')).Trim() -eq 'authoritative guidance') 'Source-authority refusal modified source guidance.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $sourceLikeRepo '.codex\new-project-setup.json'))) 'Source-authority refusal modified workflow state.'

    $migrationRepo = Join-Path $testRoot 'migration-v2'
    New-Item -ItemType Directory -Force -Path (Join-Path $migrationRepo 'docs') | Out-Null
    Set-Content -LiteralPath (Join-Path $migrationRepo 'AGENTS.md') -Value @(
        '# Existing guidance',
        '',
        '<!-- new-project-setup:v2:start -->',
        'legacy managed text',
        '<!-- new-project-setup:v2:end -->',
        '',
        '- Preserve this project rule.'
    )
    Set-Content -LiteralPath (Join-Path $migrationRepo 'docs\work-log.md') -Value '# Legacy private work log'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $applyScript -ProjectRoot $migrationRepo *> $null
    Assert-True ($LASTEXITCODE -eq 0) 'Version-2 migration failed.'
    $migratedAgents = Get-Content -Raw -LiteralPath (Join-Path $migrationRepo 'AGENTS.md')
    Assert-True ($migratedAgents.Contains('new-project-setup:v5:start') -and -not $migratedAgents.Contains('new-project-setup:v2:start')) 'Version-2 marker was not migrated.'
    Assert-True $migratedAgents.Contains('Preserve this project rule') 'Version-2 migration removed project-specific guidance.'
    Assert-True (Test-Path -LiteralPath (Join-Path $migrationRepo 'docs\work-log.md')) 'Version-2 migration removed the legacy work log.'

    $migrationV3Repo = Join-Path $testRoot 'migration-v3'
    New-Item -ItemType Directory -Force -Path (Join-Path $migrationV3Repo '.codex') | Out-Null
    Set-Content -LiteralPath (Join-Path $migrationV3Repo 'AGENTS.md') -Value @(
        '# Existing version-3 guidance',
        '',
        '<!-- new-project-setup:v3:start -->',
        'legacy version-3 managed text',
        '<!-- new-project-setup:v3:end -->',
        '',
        '- Preserve this version-3 project rule.'
    )
    Set-Content -LiteralPath (Join-Path $migrationV3Repo '.codex\new-project-setup.json') -Value '{"format":2,"workflow_version":3,"repository":"owner/existing","remote":"github"}'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $applyScript -ProjectRoot $migrationV3Repo *> $null
    Assert-True ($LASTEXITCODE -eq 0) 'Version-3 migration failed.'
    $migratedV3Agents = Get-Content -Raw -LiteralPath (Join-Path $migrationV3Repo 'AGENTS.md')
    Assert-True ($migratedV3Agents.Contains('new-project-setup:v5:start') -and -not $migratedV3Agents.Contains('new-project-setup:v3:start')) 'Version-3 marker was not migrated.'
    Assert-True $migratedV3Agents.Contains('Preserve this version-3 project rule') 'Version-3 migration removed project-specific guidance.'
    $migratedV3State = Get-Content -Raw -LiteralPath (Join-Path $migrationV3Repo '.codex\new-project-setup.json') | ConvertFrom-Json
    Assert-True ([int]$migratedV3State.workflow_version -eq 5) 'Version-3 state was not upgraded.'
    Assert-True ($migratedV3State.repository -eq 'owner/existing' -and $migratedV3State.remote -eq 'github') 'Version-3 migration lost repository state.'

    $migrationV4Repo = Join-Path $testRoot 'migration-v4'
    New-Item -ItemType Directory -Force -Path (Join-Path $migrationV4Repo '.codex') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $migrationV4Repo 'docs') | Out-Null
    Set-Content -LiteralPath (Join-Path $migrationV4Repo 'AGENTS.md') -Value @(
        '# Existing version-4 guidance',
        '',
        '<!-- new-project-setup:v4:start -->',
        'legacy version-4 managed text',
        '<!-- new-project-setup:v4:end -->',
        '',
        '- Preserve this version-4 project rule.'
    )
    Set-Content -LiteralPath (Join-Path $migrationV4Repo '.gitignore') -Value @(
        'project-private/',
        '# new-project-setup:v4:start',
        'legacy-ignore',
        '# new-project-setup:v4:end'
    )
    Set-Content -LiteralPath (Join-Path $migrationV4Repo '.gitattributes') -Value @(
        '*.fixture binary',
        '# new-project-setup:v4:start',
        'legacy-attributes',
        '# new-project-setup:v4:end'
    )
    Set-Content -LiteralPath (Join-Path $migrationV4Repo 'docs\development-log.md') -Value '# Existing Development Log'
    Set-Content -LiteralPath (Join-Path $migrationV4Repo 'docs\codex-handoff.md') -Value '# Existing Codex Handoff'
    Set-Content -LiteralPath (Join-Path $migrationV4Repo '.codex\new-project-setup.json') -Value '{"format":2,"workflow_version":4,"repository":"owner/v4","remote":"github","execution_mode":"adaptive"}'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $applyScript -ProjectRoot $migrationV4Repo *> $null
    Assert-True ($LASTEXITCODE -eq 0) 'Version-4 migration failed.'
    $migratedV4Agents = Get-Content -Raw -LiteralPath (Join-Path $migrationV4Repo 'AGENTS.md')
    Assert-True ($migratedV4Agents.Contains('new-project-setup:v5:start') -and -not $migratedV4Agents.Contains('new-project-setup:v4:start')) 'Version-4 marker was not migrated.'
    Assert-True $migratedV4Agents.Contains('Preserve this version-4 project rule') 'Version-4 migration removed project-specific guidance.'
    $migratedV4Ignore = Get-Content -Raw -LiteralPath (Join-Path $migrationV4Repo '.gitignore')
    Assert-True ($migratedV4Ignore.Contains('project-private/') -and $migratedV4Ignore.Contains('new-project-setup:v5:start') -and -not $migratedV4Ignore.Contains('new-project-setup:v4:start')) 'Version-4 migration damaged ignore policy.'
    $migratedV4Attributes = Get-Content -Raw -LiteralPath (Join-Path $migrationV4Repo '.gitattributes')
    Assert-True ($migratedV4Attributes.Contains('*.fixture binary') -and $migratedV4Attributes.Contains('new-project-setup:v5:start') -and -not $migratedV4Attributes.Contains('new-project-setup:v4:start')) 'Version-4 migration damaged attributes policy.'
    Assert-True ((Get-Content -Raw (Join-Path $migrationV4Repo 'docs\development-log.md')) -match 'Existing Development Log') 'Version-4 migration replaced development memory.'
    Assert-True ((Get-Content -Raw (Join-Path $migrationV4Repo 'docs\codex-handoff.md')) -match 'Existing Codex Handoff') 'Version-4 migration replaced handoff state.'
    $migratedV4State = Get-Content -Raw -LiteralPath (Join-Path $migrationV4Repo '.codex\new-project-setup.json') | ConvertFrom-Json
    Assert-True ([int]$migratedV4State.workflow_version -eq 5) 'Version-4 state was not upgraded.'
    Assert-True ($migratedV4State.repository -eq 'owner/v4' -and $migratedV4State.remote -eq 'github') 'Version-4 migration lost repository state.'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $applyScript -ProjectRoot $migrationV4Repo -Check *> $null
    Assert-True ($LASTEXITCODE -eq 0) 'Version-4 migration is not idempotent after upgrade.'

    $initializeRepo = Join-Path $testRoot 'initialize-github'
    $initializeRemote = Join-Path $testRoot 'initialize-github.git'
    $initializeBin = Join-Path $testRoot 'initialize-github-bin'
    Initialize-TestRepo $initializeRepo
    git init --bare $initializeRemote | Out-Null
    & powershell -NoProfile -ExecutionPolicy Bypass -File $applyScript -ProjectRoot $initializeRepo -RemoteName github *> $null
    New-FakeGh $initializeBin $initializeRemote
    $oldPath = $env:PATH
    $env:PATH = "${initializeBin};${oldPath}"
    try { & powershell -NoProfile -ExecutionPolicy Bypass -File $githubSyncScript -ProjectRoot $initializeRepo -Initialize *> $null }
    finally { $env:PATH = $oldPath }
    Assert-True ($LASTEXITCODE -eq 0) 'Private GitHub destination initialization failed.'
    $initializedState = Get-Content -Raw -LiteralPath (Join-Path $initializeRepo '.codex\new-project-setup.json') | ConvertFrom-Json
    Assert-True ($initializedState.repository -eq 'owner/repo' -and $initializedState.remote -eq 'github') 'Initialized GitHub destination was not recorded in workflow state.'
    Assert-True ((git -C $initializeRepo remote get-url github) -eq $initializeRemote) 'Initialized GitHub remote URL is incorrect.'

    $configRepo = Join-Path $testRoot 'config-bypass'
    Initialize-TestRepo $configRepo
    Set-Content -LiteralPath (Join-Path $configRepo 'README.md') -Value ('Private ' + '10.' + '22.33.44')
    Commit-All $configRepo
    Set-Content -LiteralPath (Join-Path $configRepo '.github-backup.json') -Value '{"exclude":["**"]}'
    Assert-True ((Invoke-BackupChild $configRepo $null -ScanOnly) -ne 0) 'Untracked config weakened committed backup policy.'

    $utfRepo = Join-Path $testRoot 'utf16'
    Initialize-TestRepo $utfRepo
    [IO.File]::WriteAllText((Join-Path $utfRepo 'private.txt'), ('Private ' + '10.' + '55.66.77'), [Text.Encoding]::Unicode)
    Commit-All $utfRepo
    Assert-True ((Invoke-BackupChild $utfRepo $null -ScanOnly) -ne 0) 'UTF-16 confidential content bypassed scanning.'

    $emptyRepo = Join-Path $testRoot 'empty'
    Initialize-TestRepo $emptyRepo
    Set-Content -LiteralPath (Join-Path $emptyRepo 'README.md') -Value safe
    Set-Content -LiteralPath (Join-Path $emptyRepo '.github-backup.json') -Value '{"exclude":["**"]}'
    Commit-All $emptyRepo
    Assert-True ((Invoke-BackupChild $emptyRepo $null -ScanOnly) -ne 0) 'Empty sanitized snapshot was accepted.'

    $gitlinkRepo = Join-Path $testRoot 'gitlink'
    Initialize-TestRepo $gitlinkRepo
    Set-Content -LiteralPath (Join-Path $gitlinkRepo 'README.md') -Value safe
    Commit-All $gitlinkRepo
    $objectId = git -C $gitlinkRepo rev-parse HEAD
    git -C $gitlinkRepo update-index --add --cacheinfo "160000,$objectId,vendor/dependency"
    git -C $gitlinkRepo commit -m gitlink | Out-Null
    Assert-True ((Invoke-BackupChild $gitlinkRepo $null -ScanOnly) -ne 0) 'Gitlink was treated as complete backup content.'

    $lfsRepo = Join-Path $testRoot 'lfs'
    Initialize-TestRepo $lfsRepo
    Set-Content -LiteralPath (Join-Path $lfsRepo 'asset.bin') -Encoding ascii -Value @(
        'version https://git-lfs.github.com/spec/v1',
        'oid sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'size 42'
    )
    Commit-All $lfsRepo
    Assert-True ((Invoke-BackupChild $lfsRepo $null -ScanOnly) -ne 0) 'LFS pointer was treated as complete backup content.'

    $source = Join-Path $testRoot 'source'
    $remote = Join-Path $testRoot 'remote.git'
    $bin = Join-Path $testRoot 'bin'
    $localData = Join-Path $testRoot 'local-data'
    Initialize-TestRepo $source
    New-Item -ItemType Directory -Force -Path (Join-Path $source 'docs') | Out-Null
    Set-Content -LiteralPath (Join-Path $source 'README.md') -Value 'safe one'
    Set-Content -LiteralPath (Join-Path $source 'docs\work-log.md') -Value 'private operational narrative'
    Commit-All $source
    git init --bare $remote | Out-Null
    New-FakeGh $bin $remote
    $oldPath = $env:PATH
    $oldLocalData = $env:LOCALAPPDATA
    $env:PATH = "${bin};${oldPath}"
    $env:LOCALAPPDATA = $localData
    try {
        Assert-True ((Invoke-BackupChild $source 'owner/repo') -eq 0) 'Initial isolated backup failed.'
        Set-Content -LiteralPath (Join-Path $source 'README.md') -Value 'safe two'
        Commit-All $source 'second'
        Assert-True ((Invoke-BackupChild $source 'owner/repo') -eq 0) 'Incremental isolated backup failed.'
        Remove-Item -LiteralPath (Join-Path $localData 'Codex\github-backups') -Force -Recurse
        Assert-True ((Invoke-BackupChild $source 'owner/repo') -eq 0) 'Fresh-machine history audit failed.'
    }
    finally {
        $env:PATH = $oldPath
        $env:LOCALAPPDATA = $oldLocalData
    }
    $files = git --git-dir=$remote ls-tree -r --name-only main
    Assert-True ($files -notcontains 'docs/work-log.md') 'Private work log reached backup.'
    $identities = @(git --git-dir=$remote log main --format='%an|%ae' | Select-Object -Unique)
    Assert-True ($identities.Count -eq 1 -and $identities[0] -eq 'Codex Sanitized Backup|codex-sanitized-backup@users.noreply.github.com') 'Backup identity is not neutral.'
    Assert-True ([int](git --git-dir=$remote rev-list --count main) -eq 2) 'No-change run created an extra backup commit.'

    $syncSource = Join-Path $testRoot 'source-sync'
    $syncRemote = Join-Path $testRoot 'source-sync.git'
    $syncBin = Join-Path $testRoot 'source-sync-bin'
    $syncLocalData = Join-Path $testRoot 'source-sync-local-data'
    Initialize-TestRepo $syncSource
    git init --bare $syncRemote | Out-Null
    & powershell -NoProfile -ExecutionPolicy Bypass -File $applyScript -ProjectRoot $syncSource -Repository 'owner/repo' -RemoteName github *> $null
    Set-Content -LiteralPath (Join-Path $syncSource 'README.md') -Value 'public-ready source one'
    Commit-All $syncSource 'initial public-ready source'
    New-FakeGh $syncBin $syncRemote
    $oldPath = $env:PATH
    $oldLocalData = $env:LOCALAPPDATA
    $env:PATH = "${syncBin};${oldPath}"
    $env:LOCALAPPDATA = $syncLocalData
    try {
        Assert-True ((Invoke-SyncChild $syncSource -ScanOnly) -eq 0) 'Clean source-history scan failed.'
        $readinessStatus = @((git -C $syncSource status --porcelain))
        $readinessRemotes = @((git -C $syncSource remote -v))
        Assert-True ((Invoke-SyncChild $syncSource -PublicReadiness) -eq 0) 'Read-only public-readiness audit failed.'
        Assert-True (-not (Compare-Object $readinessStatus @((git -C $syncSource status --porcelain)))) 'Public-readiness audit changed the source worktree.'
        Assert-True (-not (Compare-Object $readinessRemotes @((git -C $syncSource remote -v)))) 'Public-readiness audit changed Git remotes.'
        Assert-True ((Invoke-SyncChild $syncSource) -eq 0) 'Initial full source-history synchronization failed.'
        Assert-True ((git --git-dir=$syncRemote rev-parse main) -eq (git -C $syncSource rev-parse HEAD)) 'Remote does not match real source history.'
        Add-Content -LiteralPath (Join-Path $syncSource 'README.md') -Value 'public-ready source two'
        Commit-All $syncSource 'second meaningful source commit'
        Assert-True ((Invoke-SyncChild $syncSource) -eq 0) 'Incremental source-history synchronization failed.'
        Assert-True ([int](git --git-dir=$syncRemote rev-list --count main) -eq 2) 'Real source commit history was not preserved.'
        Assert-True (((git --git-dir=$syncRemote show 'main:docs/development-log.md') -join "`n") -match 'Development Log') 'Development log was not synchronized.'
        Assert-True (((git --git-dir=$syncRemote show 'main:docs/codex-handoff.md') -join "`n") -match 'Codex Handoff') 'Codex handoff was not synchronized.'
        Assert-True ((Invoke-SyncChild $syncSource) -eq 0) 'No-change source synchronization failed.'
        Assert-True ([int](git --git-dir=$syncRemote rev-list --count main) -eq 2) 'No-change source synchronization created a commit.'
        New-FakeGh $syncBin $syncRemote -Visibility PUBLIC
        Assert-True ((Invoke-SyncChild $syncSource) -ne 0) 'Public repository visibility was accepted.'
        New-FakeGh $syncBin $syncRemote

        $divergeClone = Join-Path $testRoot 'source-sync-diverge'
        git clone --quiet $syncRemote $divergeClone
        git -C $divergeClone checkout -b main origin/main | Out-Null
        git -C $divergeClone config user.name Fixture
        git -C $divergeClone config user.email fixture@example.invalid
        Set-Content -LiteralPath (Join-Path $divergeClone 'remote-only.txt') -Value safe
        Commit-All $divergeClone 'remote-only commit'
        git -C $divergeClone push origin main | Out-Null
        Set-Content -LiteralPath (Join-Path $syncSource 'local-only.txt') -Value safe
        Commit-All $syncSource 'local-only commit'
        Assert-True ((Invoke-SyncChild $syncSource) -ne 0) 'Diverged remote history was pushed.'
    }
    finally {
        $env:PATH = $oldPath
        $env:LOCALAPPDATA = $oldLocalData
    }

    $blockedSource = Join-Path $testRoot 'blocked-source-sync'
    $blockedRemote = Join-Path $testRoot 'blocked-source-sync.git'
    $blockedBin = Join-Path $testRoot 'blocked-source-sync-bin'
    $blockedLocalData = Join-Path $testRoot 'blocked-source-sync-local-data'
    Initialize-TestRepo $blockedSource
    git init --bare $blockedRemote | Out-Null
    & powershell -NoProfile -ExecutionPolicy Bypass -File $applyScript -ProjectRoot $blockedSource -Repository 'owner/repo' -RemoteName github *> $null
    Set-Content -LiteralPath (Join-Path $blockedSource 'historical.txt') -Value ('authorization: bearer ' + ('a' * 24))
    Commit-All $blockedSource 'unsafe historical source'
    Remove-Item -LiteralPath (Join-Path $blockedSource 'historical.txt')
    Set-Content -LiteralPath (Join-Path $blockedSource 'README.md') -Value 'safe current source'
    Commit-All $blockedSource 'safe current source'
    New-FakeGh $blockedBin $blockedRemote
    $oldPath = $env:PATH
    $oldLocalData = $env:LOCALAPPDATA
    $env:PATH = "${blockedBin};${oldPath}"
    $env:LOCALAPPDATA = $blockedLocalData
    try { $blockedExit = Invoke-SyncChild $blockedSource }
    finally {
        $env:PATH = $oldPath
        $env:LOCALAPPDATA = $oldLocalData
    }
    Assert-True ($blockedExit -ne 0) 'Unsafe reachable source history was pushed.'
    Assert-True (-not (git --git-dir=$blockedRemote show-ref)) 'Blocked source audit changed the remote.'
    Assert-True (-not ((git -C $blockedSource remote) -contains 'github-backup')) 'Audit failure automatically chose the sanitized fallback.'

    $spoofSource = Join-Path $testRoot 'spoof-source'
    $spoofRemote = Join-Path $testRoot 'spoof-remote.git'
    $spoofSeed = Join-Path $testRoot 'spoof-seed'
    $spoofBin = Join-Path $testRoot 'spoof-bin'
    $spoofLocal = Join-Path $testRoot 'spoof-local'
    git init --bare $spoofRemote | Out-Null
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        git clone --quiet $spoofRemote $spoofSeed 2>$null | Out-Null
        $cloneExit = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    Assert-True ($cloneExit -eq 0) 'Unable to create spoof-history fixture.'
    git -C $spoofSeed config user.name 'Codex Sanitized Backup'
    git -C $spoofSeed config user.email 'codex-sanitized-backup@users.noreply.github.com'
    Set-Content -LiteralPath (Join-Path $spoofSeed '.codex-sanitized-backup.json') -Value '{"format":2,"source_project":"spoof-source"}'
    Set-Content -LiteralPath (Join-Path $spoofSeed 'private-history.txt') -Value ('Private ' + '10.' + '44.55.66')
    Commit-All $spoofSeed 'unsafe-root'
    git -C $spoofSeed branch -M main
    git -C $spoofSeed push origin main | Out-Null
    Remove-Item -LiteralPath (Join-Path $spoofSeed 'private-history.txt')
    Commit-All $spoofSeed 'hide-value'
    git -C $spoofSeed push origin main | Out-Null
    $spoofCount = [int](git --git-dir=$spoofRemote rev-list --count main)
    Initialize-TestRepo $spoofSource
    Set-Content -LiteralPath (Join-Path $spoofSource 'README.md') -Value safe
    Commit-All $spoofSource
    New-FakeGh $spoofBin $spoofRemote
    $oldPath = $env:PATH
    $oldLocalData = $env:LOCALAPPDATA
    $env:PATH = "${spoofBin};${oldPath}"
    $env:LOCALAPPDATA = $spoofLocal
    try { $spoofExit = Invoke-BackupChild $spoofSource 'owner/spoof' }
    finally {
        $env:PATH = $oldPath
        $env:LOCALAPPDATA = $oldLocalData
    }
    Assert-True ($spoofExit -ne 0) 'Marker-only trust accepted unsafe historical content.'
    Assert-True ([int](git --git-dir=$spoofRemote rev-list --count main) -eq $spoofCount) 'Blocked history audit changed the remote.'

    $tempCodex = Join-Path $testRoot 'codex-home'
    $stalePath = Join-Path $tempCodex 'skills\new-project-setup\scripts\stale.ps1'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stalePath) | Out-Null
    Set-Content -LiteralPath $stalePath -Value '# stale'
    $oldCodexHome = $env:CODEX_HOME
    $env:CODEX_HOME = $tempCodex
    try { & $syncScript *> $null }
    finally { $env:CODEX_HOME = $oldCodexHome }
    Assert-True (-not (Test-Path -LiteralPath $stalePath)) 'Exact sync retained stale installed payload.'
    $installedFixture = Join-Path $tempCodex 'skills\new-project-setup'
    foreach ($reference in @('install-and-migration.md', 'execution-and-memory.md', 'github-history.md')) {
        Assert-True (Test-Path -LiteralPath (Join-Path $installedFixture "references\$reference")) "Installed payload omitted conditional reference: $reference"
    }
    Assert-True (@(Get-ChildItem -LiteralPath $installedFixture -File -Recurse).Count -eq 10) 'Installed runtime payload inventory is not exact.'

    & powershell -NoProfile -ExecutionPolicy Bypass -File $behaviorScript *> $null
    Assert-True ($LASTEXITCODE -eq 0) 'Behavior contract evaluation failed.'

    Write-Host 'All new-project-setup regression tests passed.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Force -Recurse }
}
