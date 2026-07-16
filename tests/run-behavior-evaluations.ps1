[CmdletBinding()]
param([string]$OutputPath)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$applyScript = Join-Path $projectRoot 'scripts\apply-project-setup.ps1'
$baseline = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'v4-baseline.json') | ConvertFrom-Json
$contract = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'behavior-scenarios.json') | ConvertFrom-Json
$testRoot = Join-Path $env:TEMP ("new-project-setup-behavior-" + [Guid]::NewGuid().ToString('N'))

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    git -C $testRoot init -b main | Out-Null
    git -C $testRoot config user.name Fixture
    git -C $testRoot config user.email fixture@example.invalid
    & powershell -NoProfile -ExecutionPolicy Bypass -File $applyScript -ProjectRoot $testRoot *> $null
    Assert-True ($LASTEXITCODE -eq 0) 'Unable to apply workflow to behavior fixture.'

    $agentsPath = Join-Path $testRoot 'AGENTS.md'
    $agents = Get-Content -Raw -LiteralPath $agentsPath
    $state = Get-Content -Raw -LiteralPath (Join-Path $testRoot '.codex\new-project-setup.json') | ConvertFrom-Json
    $skill = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'SKILL.md')
    $checklist = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'references\new-project-setup-checklist.md')

    $start = $agents.IndexOf('<!-- new-project-setup:v5:start -->')
    $end = $agents.IndexOf('<!-- new-project-setup:v5:end -->')
    Assert-True ($start -ge 0 -and $end -gt $start) 'Version-5 managed block is missing.'
    $managed = $agents.Substring($start, $end - $start)
    $normalizedManaged = ($managed -replace '\s+', ' ').ToLowerInvariant()

    foreach ($marker in @(
        'durability, operational risk, and effort independently',
        'Do not ask for routine implementation, context expansion, or validation transitions',
        'Start file changes with Git status',
        'confirmed unused',
        'another equivalent screenshot is not new evidence',
        'retest only failed/invalidated cells',
        'effort-appropriate final matrix',
        'do not start another broad matrix',
        'strategy change',
        'minimal reproducer',
        'two materially different root-cause attempts still fail',
        'report an unresolved blocker',
        'Finish when criteria pass',
        'Preserve every lasting change in Git',
        'valid and remaining evidence',
        'bookkeeping-only commit',
        'Ask before deployment',
        'Obtain separate confirmation immediately before deployment',
        'source helper, then sync runtime',
        'reasonable initial stack'
    )) {
        Assert-True ($normalizedManaged.Contains($marker.ToLowerInvariant())) "Managed behavior marker missing: $marker"
    }

    Assert-True ([int]$state.workflow_version -eq 5) 'Behavior fixture is not workflow version 5.'
    Assert-True ($state.context_loading -eq 'progressive') 'Progressive context state is missing.'
    Assert-True ($state.effort_classification -eq 'adaptive') 'Adaptive effort state is missing.'
    Assert-True ($state.validation_strategy -eq 'risk-based') 'Risk-based validation state is missing.'
    Assert-True ($state.evidence_reuse -eq 'required') 'Evidence reuse state is missing.'
    Assert-True ($state.convergence_action -eq 'change-strategy') 'Convergence strategy state is missing.'
    Assert-True ($state.final_validation_matrix -eq 'one-broad-pass-then-invalidated-only' -and $state.final_validation_scope -eq 'effort-appropriate') 'Final-matrix state is missing.'
    Assert-True ($state.evidence_definition -eq 'distinct-risk') 'Distinct-risk evidence state is missing.'
    Assert-True ($state.convergence_escalation -eq 'minimal-reproducer') 'Convergence escalation state is missing.'
    Assert-True ($state.risk_set -eq 'bounded-to-objective') 'Bounded risk-set state is missing.'
    Assert-True ($state.unresolved_local_failure -eq 'preserve-and-report') 'Unresolved local-failure state is missing.'
    Assert-True ($state.handoff_evidence -eq 'summary' -and $state.handoff_sync_reference -eq 'containing-commit') 'Handoff evidence state is missing.'
    Assert-True ($state.exploration_cleanup -eq 'own-current-artifacts-only') 'Exploration cleanup state is missing.'
    Assert-True ($state.deployment_confirmation -eq 'separate') 'Separate deployment confirmation state is missing.'
    Assert-True ($state.source_authority -eq 'source-first') 'Source authority state is missing.'
    Assert-True ($state.target_path_policy -eq 'contained-no-reparse' -and $state.managed_marker_policy -eq 'unique-fail-closed') 'Target or marker safety state is missing.'
    Assert-True ($state.apply_preflight -eq 'fail-before-write' -and $state.helper_ownership -eq 'marker-or-known-hash') 'Apply preflight or helper ownership state is missing.'
    Assert-True ($state.new_project_stack -eq 'allow') 'New-project stack authority state is missing.'

    $scenarios = @($contract.scenarios)
    Assert-True ($scenarios.Count -ge 9) 'Behavior contract does not cover all required scenarios.'
    Assert-True (@($scenarios.id | Sort-Object -Unique).Count -eq $scenarios.Count) 'Behavior scenario IDs are not unique.'
    foreach ($scenario in $scenarios) {
        Assert-True (-not [string]::IsNullOrWhiteSpace($scenario.prompt)) "Scenario prompt missing: $($scenario.id)"
        Assert-True ($scenario.expected_user_questions -in @(0, 1)) "Invalid question count: $($scenario.id)"
        if ($scenario.id -notin @('ambiguous-durability', 'protected-deployment')) {
            Assert-True ([int]$scenario.expected_user_questions -eq 0) "Clear bounded scenario asks a routine question: $($scenario.id)"
        }
        if ($null -ne $scenario.maximum_equivalent_final_matrices) {
            Assert-True ([int]$scenario.maximum_equivalent_final_matrices -le 1) "Scenario permits repeated final matrices: $($scenario.id)"
        }
    }
    Assert-True (@($scenarios | Where-Object { [int]$_.expected_user_questions -eq 0 }).Count -eq 7) 'Clear-scenario no-question coverage changed.'
    Assert-True (@($scenarios | Where-Object { [int]$_.expected_user_questions -eq 1 }).Count -eq 2) 'Protected or ambiguous question coverage changed.'

    Assert-True ($skill -notmatch 'Read `references/new-project-setup-checklist.md` before changing') 'Full checklist is still mandatory.'
    foreach ($reference in @('install-and-migration.md', 'execution-and-memory.md', 'github-history.md')) {
        Assert-True $skill.Contains($reference) "Conditional reference routing missing: $reference"
    }

    $skillTokens = [math]::Round($skill.Length / 4)
    $checklistTokens = [math]::Round($checklist.Length / 4)
    $managedTokens = [math]::Round($managed.Length / 4)
    $reduction = [math]::Round((1 - ($skillTokens / [double]$baseline.mandatory_total_approx_tokens)) * 100, 1)
    $managedGrowth = [math]::Round((($managedTokens / [double]$baseline.managed_block_approx_tokens) - 1) * 100, 1)
    Assert-True ($reduction -ge 30) "Routine mandatory context reduction is only ${reduction}%."
    Assert-True ($managedTokens -le [math]::Ceiling([double]$baseline.managed_block_approx_tokens * 1.15)) 'Generated managed policy grew more than 15%.'

    $result = [ordered]@{
        format = 1
        scenarios = $scenarios.Count
        clear_scenario_questions = @($scenarios | Where-Object { [int]$_.expected_user_questions -eq 0 }).Count
        protected_or_ambiguous_questions = @($scenarios | Where-Object { [int]$_.expected_user_questions -eq 1 }).Count
        baseline_mandatory_approx_tokens = [int]$baseline.mandatory_total_approx_tokens
        current_skill_approx_tokens = $skillTokens
        completion_checklist_approx_tokens = $checklistTokens
        routine_context_reduction_percent = $reduction
        baseline_managed_approx_tokens = [int]$baseline.managed_block_approx_tokens
        current_managed_approx_tokens = $managedTokens
        managed_growth_percent = $managedGrowth
        mandatory_reference_reads = 0
        initial_context_sources = 3
        unconditional_history_reads = 0
        maximum_equivalent_final_matrices = 1
        unresolved_local_failure_terminal = 'preserve-and-report'
        deployment_confirmation = 'separate'
        exploratory_cleanup = 'own-current-artifacts-only'
        source_authority = 'source-first'
        target_path_policy = 'contained-no-reparse'
        marker_policy = 'unique-fail-closed'
        apply_preflight = 'fail-before-write'
        helper_ownership = 'marker-or-known-hash'
        handoff_sync_reference = 'containing-commit'
        durable_documentation_surfaces = 3
        tool_call_measurement = 'not exposed by deterministic policy fixture'
    }
    $json = $result | ConvertTo-Json
    if ($OutputPath) {
        [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $json + "`r`n", [Text.UTF8Encoding]::new($false))
    }
    Write-Host 'All new-project-setup behavior contract evaluations passed.'
    Write-Output $json
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Force -Recurse }
}
