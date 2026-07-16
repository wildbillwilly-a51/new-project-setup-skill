[CmdletBinding()]
param(
    [string]$ProjectRoot = ".",
    [string]$Repository,
    [string]$RemoteName,
    [switch]$Check
)

$ErrorActionPreference = "Stop"
$WorkflowVersion = 5
$resolvedRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$skillRoot = Split-Path -Parent $PSScriptRoot
$changes = New-Object Collections.Generic.List[string]
$managedHelperMarker = '# new-project-setup:managed-helper:v1'
$legacyManagedHelperHashes = @{
    'github-sync.ps1' = @('A45C8209D821F4B2A4CF4628F7D72D2CA993C3B7F76F2E58D6BF6B5F7AADDEEE')
    'github-backup.ps1' = @('C66D2E0D35950309D4ED0FAF774FFC07C50BEB8637FFA5BC456A373415DFAA50')
}

function Test-SamePath {
    param([string]$Left, [string]$Right)
    return [string]::Equals(
        [IO.Path]::GetFullPath($Left).TrimEnd('\', '/'),
        [IO.Path]::GetFullPath($Right).TrimEnd('\', '/'),
        [StringComparison]::OrdinalIgnoreCase
    )
}

function Test-RedirectedLink {
    param([object]$Item)
    if ($null -eq $Item) { return $false }
    $linkType = if ($Item.PSObject.Properties.Name -contains 'LinkType') { [string]$Item.LinkType } else { '' }
    $linkTargets = if ($Item.PSObject.Properties.Name -contains 'Target') {
        @($Item.Target | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    } else { @() }
    return -not [string]::IsNullOrWhiteSpace($linkType) -or $linkTargets.Count -gt 0
}

function Assert-TargetPath {
    param([string]$Path)

    $rootPath = [IO.Path]::GetFullPath($resolvedRoot).TrimEnd('\', '/')
    $fullPath = [IO.Path]::GetFullPath($Path)
    $rootPrefix = $rootPath + [IO.Path]::DirectorySeparatorChar
    if (-not (Test-SamePath $rootPath $fullPath) -and
        -not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Managed path escapes the resolved project root: $Path"
    }

    $rootItem = Get-Item -Force -LiteralPath $rootPath -ErrorAction SilentlyContinue
    if ($null -eq $rootItem -or -not $rootItem.PSIsContainer) {
        throw "Resolved project root is not a directory: $rootPath"
    }
    if (Test-RedirectedLink $rootItem) {
        throw "Resolved project root is a redirected link: $rootPath"
    }

    $relative = $fullPath.Substring($rootPath.Length).TrimStart('\', '/')
    $cursor = $rootPath
    $parts = @($relative -split '[\\/]' | Where-Object { $_ })
    for ($index = 0; $index -lt $parts.Count; $index++) {
        $cursor = Join-Path $cursor $parts[$index]
        $item = Get-Item -Force -LiteralPath $cursor -ErrorAction SilentlyContinue
        if (Test-RedirectedLink $item) {
            throw "Managed path crosses a redirected link: $cursor"
        }
        if ($null -ne $item -and $index -lt ($parts.Count - 1) -and -not $item.PSIsContainer) {
            throw "Managed path crosses a non-directory component: $cursor"
        }
    }
    return $fullPath
}

function Assert-ManagedHelperOwnership {
    param(
        [string]$TargetPath,
        [string]$SourcePath,
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $TargetPath)) { return }
    if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
        throw "Managed helper path is not a file: $TargetPath"
    }
    if (Test-SamePath $TargetPath $SourcePath) { return }
    if ((Get-FileHash -Algorithm SHA256 $TargetPath).Hash -eq (Get-FileHash -Algorithm SHA256 $SourcePath).Hash) { return }

    $content = Get-Content -Raw -LiteralPath $TargetPath
    $hash = (Get-FileHash -Algorithm SHA256 $TargetPath).Hash
    if ($content.Contains($managedHelperMarker) -or $legacyManagedHelperHashes[$Name] -contains $hash) { return }
    throw "Refusing to overwrite an unowned existing helper: $TargetPath"
}

function Get-ExistingManagedMarker {
    param(
        [string]$Content,
        [object[]]$Markers,
        [string]$Path
    )

    $found = New-Object Collections.Generic.List[object]
    foreach ($marker in $Markers) {
        $startCount = [Regex]::Matches($Content, [Regex]::Escape([string]$marker.Start)).Count
        $endCount = [Regex]::Matches($Content, [Regex]::Escape([string]$marker.End)).Count
        if ($startCount -ne $endCount -or $startCount -gt 1) {
            throw "Malformed or duplicate managed markers in $Path"
        }
        if ($startCount -eq 1) {
            $startIndex = $Content.IndexOf([string]$marker.Start, [StringComparison]::Ordinal)
            $endIndex = $Content.IndexOf([string]$marker.End, [StringComparison]::Ordinal)
            if ($endIndex -le $startIndex) {
                throw "Managed markers are out of order in $Path"
            }
            $found.Add($marker)
        }
    }
    if ($found.Count -gt 1) { throw "Conflicting managed marker versions in $Path" }
    if ($found.Count -eq 1) { return $found[0] }
    return $null
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

function Set-ManagedText {
    param(
        [string]$Path,
        [string]$StartMarker,
        [string]$EndMarker,
        [string]$Body
    )

    $Path = Assert-TargetPath $Path
    $block = "${StartMarker}`r`n${Body}`r`n${EndMarker}"
    $current = if (Test-Path -LiteralPath $Path) { Get-Content -Raw -LiteralPath $Path } else { "" }
    $pattern = "(?s)" + [Regex]::Escape($StartMarker) + ".*?" + [Regex]::Escape($EndMarker)
    $next = if ($current -match $pattern) {
        [Regex]::Replace($current, $pattern, [Text.RegularExpressions.MatchEvaluator]{ param($match) $block })
    } elseif ($current.Trim()) {
        $current.TrimEnd() + "`r`n`r`n" + $block + "`r`n"
    } else {
        $block + "`r`n"
    }

    if ($current.Replace("`r`n", "`n") -ne $next.Replace("`r`n", "`n")) {
        $changes.Add($Path.Substring($resolvedRoot.Length).TrimStart('\'))
        if (-not $Check) {
            $parent = Split-Path -Parent $Path
            if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
            Write-Utf8NoBom $Path $next
        }
    }
}

function Ensure-File {
    param([string]$Path, [string]$Content)
    $Path = Assert-TargetPath $Path
    $missingOrEmpty = -not (Test-Path -LiteralPath $Path -PathType Leaf)
    if (-not $missingOrEmpty) {
        $missingOrEmpty = [string]::IsNullOrWhiteSpace((Get-Content -Raw -LiteralPath $Path))
    }
    if ($missingOrEmpty) {
        $changes.Add($Path.Substring($resolvedRoot.Length).TrimStart('\'))
        if (-not $Check) {
            $parent = Split-Path -Parent $Path
            if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
            Write-Utf8NoBom $Path ($Content + "`r`n")
        }
    }
}

$inputRootItem = Get-Item -Force -LiteralPath $ProjectRoot
if (Test-RedirectedLink $inputRootItem) {
    throw "ProjectRoot must not be a redirected link: $ProjectRoot"
}

$syncInstalledSentinel = Join-Path $resolvedRoot 'scripts\sync-installed-skill.ps1'
$syncFromInstalledSentinel = Join-Path $resolvedRoot 'scripts\sync-from-installed-skill.ps1'
$skillSentinel = Join-Path $resolvedRoot 'SKILL.md'
$testSentinel = Join-Path $resolvedRoot 'tests\run-tests.ps1'
$isSourceProject =
    (Test-Path -LiteralPath $syncInstalledSentinel -PathType Leaf) -or
    (Test-Path -LiteralPath $syncFromInstalledSentinel -PathType Leaf) -or
    ((Test-Path -LiteralPath $skillSentinel -PathType Leaf) -and (Test-Path -LiteralPath $testSentinel -PathType Leaf))
if ($isSourceProject -and -not (Test-SamePath $resolvedRoot $skillRoot)) {
    throw 'Refusing to apply an installed runtime over the authoritative skill source. Run the source project apply script, then sync the installed runtime.'
}

foreach ($relativePath in @(
    'AGENTS.md',
    '.gitignore',
    '.gitattributes',
    'docs\development-log.md',
    'docs\codex-handoff.md',
    'CHANGELOG.md',
    '.codex\new-project-setup.json',
    'scripts\github-sync.ps1',
    'scripts\github-backup.ps1'
)) {
    Assert-TargetPath (Join-Path $resolvedRoot $relativePath) | Out-Null
}

$agentsBody = @'
### New project setup invocation

A bare or primary `$new-project-setup` invocation runs install/sync. Use the
invoked installed apply helper for a normal target; in this skill's source use
the source helper, then sync runtime. Never only load; questions are
consultation-only.

### Adaptive efficient execution

Infer durability, operational risk, and effort independently. State clear
classifications briefly and continue:

- Lasting work preserves revisions and memory. Exploration is disposable only
  for clear learning or feasibility; `quick`, `prototype`, and `MVP` do not
  imply it. Promote reused, incorporated, retained, continued, or depended-on
  work; never demote. Delete only current uncommitted Codex-created artifacts
  confirmed unused, never pre-existing, shared, promoted, or lasting output.
- Risk controls authorization, not routine local implementation authority.
- Effort controls context and evidence, not authority: focused checks direct
  effects; standard covers primary workflows and distinct risks;
  release-critical gathers broad deduplicated evidence.

Ask one preservation question only for ambiguous durability. Do not ask for
routine implementation, context expansion, or validation transitions. Bounded
local work authorizes architecture, a reasonable initial stack for an empty project,
established dependencies, tests, generated/demo data, and empty-DB schemas.

### Progressive context and evidence

Start file changes with Git status and relevant files; durable work adds
`docs/codex-handoff.md`. Read logs/changelog only when useful. Expand for
dependencies, failures, or risk; exclude unrelated roots and artifacts. Rebuild
stale handoffs from Git and evidence; ask only if the objective remains unsafe.

Keep a compact ledger of acceptance criteria, request-bounded distinct risks,
evidence, invalidators, and completion conditions. Add only direct dependencies
or shared causes; report unrelated discoveries. Another equivalent screenshot
is not new evidence. Reuse evidence and batch failures by cause. After targeted
risks pass, run one effort-appropriate final matrix; focused work may need one
check. On failure, preserve passing evidence and retest only failed/invalidated
cells; do not start another broad matrix. Two non-improving cycles require a
strategy change; two unproductive strategies require a minimal reproducer. If
two materially different root-cause attempts still fail, preserve diagnostics,
report an unresolved blocker, and do not claim completion. Finish when criteria
pass, no high-risk failure remains, records are current, and more work would
duplicate evidence. Never skip distinct safety checks.

### Proportional durable memory

Preserve every lasting change in Git. Log useful decisions, rationale, failures,
validation, or lessons; refresh the concise handoff at state boundaries with
valid and remaining evidence; update the changelog for notable behavior. Keep
private details in ignored `*.local.md` and recheck branch, HEAD, and scope.
Prepare the final handoff before its containing commit and record sync relative
to it; a matching push needs no bookkeeping-only commit.

After a safe commit, run `scripts/github-sync.ps1` for a complete audit and
private fast-forward push. Never force-push or change visibility. If blocked,
keep the commit and ask whether to use isolated `scripts/github-backup.ps1` or
remain local-only.

### Autonomous local work

Complete bounded objectives end-to-end through appropriate validation without
routine checkpoints.
Ask before deployment; credentials or live/paid services; auth/security changes;
global or native tool installation; framework or platform replacement;
consequential licensing changes; changes to existing, shared, or production
data; destructive operations; material product-direction expansion beyond the
request; or unrelated conflicting work. Internal refactoring, routine local
dependencies, and isolated local construction need no checkpoint.
Protected boundaries override implied authority. Obtain separate confirmation
immediately before deployment unless the user explicitly waived that checkpoint.
One confirmation may cover several protected effects only when it names them.

'@

$ignoreBody = @'
# Machine-local private documentation
*.local.md
.github-backup.local.json

# Generated dependencies and artifacts
node_modules/
dist/
build/
out/
.next/
coverage/
test-artifacts/
playwright-report/
'@

$attributesBody = @'
* text=auto
*.ps1 text eol=crlf
*.cmd text eol=crlf
*.bat text eol=crlf
*.sh text eol=lf
*.md text eol=lf
*.json text eol=lf
*.yaml text eol=lf
*.yml text eol=lf
'@

$managedFiles = @(
    @{ Path = (Join-Path $resolvedRoot 'AGENTS.md'); Previous = @(@{ Start = '<!-- new-project-setup:v2:start -->'; End = '<!-- new-project-setup:v2:end -->' }, @{ Start = '<!-- new-project-setup:v3:start -->'; End = '<!-- new-project-setup:v3:end -->' }, @{ Start = '<!-- new-project-setup:v4:start -->'; End = '<!-- new-project-setup:v4:end -->' }); NewStart = '<!-- new-project-setup:v5:start -->'; NewEnd = '<!-- new-project-setup:v5:end -->'; Body = $agentsBody.Trim() },
    @{ Path = (Join-Path $resolvedRoot '.gitignore'); Previous = @(@{ Start = '# new-project-setup:v2:start'; End = '# new-project-setup:v2:end' }, @{ Start = '# new-project-setup:v3:start'; End = '# new-project-setup:v3:end' }, @{ Start = '# new-project-setup:v4:start'; End = '# new-project-setup:v4:end' }); NewStart = '# new-project-setup:v5:start'; NewEnd = '# new-project-setup:v5:end'; Body = $ignoreBody.Trim() },
    @{ Path = (Join-Path $resolvedRoot '.gitattributes'); Previous = @(@{ Start = '# new-project-setup:v2:start'; End = '# new-project-setup:v2:end' }, @{ Start = '# new-project-setup:v3:start'; End = '# new-project-setup:v3:end' }, @{ Start = '# new-project-setup:v4:start'; End = '# new-project-setup:v4:end' }); NewStart = '# new-project-setup:v5:start'; NewEnd = '# new-project-setup:v5:end'; Body = $attributesBody.Trim() }
)
$sourceHelper = Join-Path $PSScriptRoot 'github-backup.ps1'
$sourceSync = Join-Path $PSScriptRoot 'github-sync.ps1'
$targetHelper = Assert-TargetPath (Join-Path $resolvedRoot 'scripts\github-backup.ps1')
$targetSync = Assert-TargetPath (Join-Path $resolvedRoot 'scripts\github-sync.ps1')
$statePath = Assert-TargetPath (Join-Path $resolvedRoot '.codex\new-project-setup.json')

foreach ($sourcePath in @($sourceSync, $sourceHelper)) {
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Bundled managed helper is missing: $sourcePath"
    }
    if (-not (Get-Content -Raw -LiteralPath $sourcePath).Contains($managedHelperMarker)) {
        throw "Bundled helper lacks its ownership marker: $sourcePath"
    }
}
Assert-ManagedHelperOwnership $targetSync $sourceSync 'github-sync.ps1'
Assert-ManagedHelperOwnership $targetHelper $sourceHelper 'github-backup.ps1'

foreach ($managed in $managedFiles) {
    $managed.Path = Assert-TargetPath $managed.Path
    if ((Test-Path -LiteralPath $managed.Path) -and -not (Test-Path -LiteralPath $managed.Path -PathType Leaf)) {
        throw "Managed marker path is not a file: $($managed.Path)"
    }
    $current = if (Test-Path -LiteralPath $managed.Path -PathType Leaf) { Get-Content -Raw -LiteralPath $managed.Path } else { '' }
    $allMarkers = @($managed.Previous) + @(@{ Start = $managed.NewStart; End = $managed.NewEnd })
    Get-ExistingManagedMarker $current $allMarkers $managed.Path | Out-Null
}

$existingState = if (Test-Path -LiteralPath $statePath) {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw "Workflow state path is not a file: $statePath" }
    $rawState = Get-Content -Raw -LiteralPath $statePath
    if ([string]::IsNullOrWhiteSpace($rawState)) { throw "Workflow state is empty: $statePath" }
    try { $rawState | ConvertFrom-Json } catch { throw "Workflow state is invalid JSON: $statePath" }
} else { $null }

foreach ($memoryPath in @(
    (Join-Path $resolvedRoot 'docs\development-log.md'),
    (Join-Path $resolvedRoot 'docs\codex-handoff.md'),
    (Join-Path $resolvedRoot 'CHANGELOG.md')
)) {
    $memoryPath = Assert-TargetPath $memoryPath
    if ((Test-Path -LiteralPath $memoryPath) -and -not (Test-Path -LiteralPath $memoryPath -PathType Leaf)) {
        throw "Project memory path is not a file: $memoryPath"
    }
}

foreach ($managed in $managedFiles) {
    $managed.Path = Assert-TargetPath $managed.Path
    $current = if (Test-Path -LiteralPath $managed.Path -PathType Leaf) { Get-Content -Raw -LiteralPath $managed.Path } else { '' }
    $allMarkers = @($managed.Previous) + @(@{ Start = $managed.NewStart; End = $managed.NewEnd })
    $existingMarker = Get-ExistingManagedMarker $current $allMarkers $managed.Path
    if ($null -ne $existingMarker) {
        $oldPattern = '(?s)' + [Regex]::Escape([string]$existingMarker.Start) + '.*?' + [Regex]::Escape([string]$existingMarker.End)
        $replacement = $managed.NewStart + "`r`n" + $managed.Body + "`r`n" + $managed.NewEnd
        $next = [Regex]::Replace($current, $oldPattern, $replacement)
        if ($current.Replace("`r`n", "`n") -ne $next.Replace("`r`n", "`n")) {
            $changes.Add($managed.Path.Substring($resolvedRoot.Length).TrimStart('\'))
            if (-not $Check) { Write-Utf8NoBom $managed.Path $next }
        }
    } else {
        Set-ManagedText $managed.Path $managed.NewStart $managed.NewEnd $managed.Body
    }
}
$effectiveRepository = if ($Repository) { $Repository } elseif ($existingState.repository) { [string]$existingState.repository } else { $null }
$effectiveRemote = if ($RemoteName) { $RemoteName } elseif ($existingState.remote) { [string]$existingState.remote } else { 'origin' }
$stateContent = ([ordered]@{
    format = 2
    workflow_version = $WorkflowVersion
    github_mode = 'private-public-ready'
    repository = $effectiveRepository
    remote = $effectiveRemote
    source_authority = 'source-first'
    target_path_policy = 'contained-no-reparse'
    managed_marker_policy = 'unique-fail-closed'
    apply_preflight = 'fail-before-write'
    helper_ownership = 'marker-or-known-hash'
    source_history_sync = $true
    audit_failure_action = 'ask'
    development_log = $true
    codex_handoff = 'always'
    handoff_presence = 'required'
    handoff_refresh = 'state-boundary'
    handoff_evidence = 'summary'
    handoff_sync_reference = 'containing-commit'
    execution_mode = 'adaptive'
    durability_ambiguity_action = 'ask'
    classification_notice = 'concise'
    routine_project_dependencies = 'allow'
    new_project_stack = 'allow'
    isolated_local_build = 'allow'
    exploration_cleanup = 'own-current-artifacts-only'
    deployment_confirmation = 'separate'
    documentation_detail = 'proportional'
    context_loading = 'progressive'
    effort_classification = 'adaptive'
    validation_strategy = 'risk-based'
    risk_set = 'bounded-to-objective'
    evidence_reuse = 'required'
    evidence_definition = 'distinct-risk'
    convergence_action = 'change-strategy'
    convergence_escalation = 'minimal-reproducer'
    final_validation_matrix = 'one-broad-pass-then-invalidated-only'
    final_validation_scope = 'effort-appropriate'
    unresolved_local_failure = 'preserve-and-report'
}) | ConvertTo-Json
$stateCurrent = if (Test-Path -LiteralPath $statePath) { (Get-Content -Raw -LiteralPath $statePath).Trim() } else { "" }
if ($stateCurrent -ne $stateContent.Trim()) {
    $changes.Add('.codex\new-project-setup.json')
    if (-not $Check) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $statePath) | Out-Null
        Write-Utf8NoBom $statePath ($stateContent + "`r`n")
    }
}

$copyNeeded = -not (Test-Path -LiteralPath $targetHelper)
if (-not $copyNeeded) {
    $copyNeeded = (Get-FileHash -Algorithm SHA256 $sourceHelper).Hash -ne (Get-FileHash -Algorithm SHA256 $targetHelper).Hash
}

$syncCopyNeeded = -not (Test-Path -LiteralPath $targetSync)
if (-not $syncCopyNeeded) {
    $syncCopyNeeded = (Get-FileHash -Algorithm SHA256 $sourceSync).Hash -ne (Get-FileHash -Algorithm SHA256 $targetSync).Hash
}
if ($syncCopyNeeded) {
    $changes.Add('scripts\github-sync.ps1')
    if (-not $Check) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetSync) | Out-Null
        $resolvedSourceSync = (Resolve-Path -LiteralPath $sourceSync).Path
        if (-not (Test-SamePath $resolvedSourceSync $targetSync)) {
            Copy-Item -LiteralPath $sourceSync -Destination $targetSync -Force
        }
    }
}
if ($copyNeeded) {
    $changes.Add('scripts\github-backup.ps1')
    if (-not $Check) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetHelper) | Out-Null
        $resolvedSourceHelper = (Resolve-Path -LiteralPath $sourceHelper).Path
        if (-not (Test-SamePath $resolvedSourceHelper $targetHelper)) {
            Copy-Item -LiteralPath $sourceHelper -Destination $targetHelper -Force
        }
    }
}

Ensure-File (Join-Path $resolvedRoot 'docs\development-log.md') "# Development Log`r`n`r`nKeep entries public-ready: completed work, decisions and rationale, useful failed approaches, validation, and durable lessons.`r`n"
Ensure-File (Join-Path $resolvedRoot 'CHANGELOG.md') "# Changelog`r`n"
Ensure-File (Join-Path $resolvedRoot 'docs\codex-handoff.md') "# Codex Handoff`r`n`r`n- Current objective: Complete project setup.`r`n- Current state: Managed workflow files are installed; project validation, commit, and GitHub synchronization remain.`r`n- Next action: Validate setup, then commit and synchronize it.`r`n- Blockers: None known.`r`n- Important decisions: GitHub history is private but public-ready.`r`n- Branch/commit/sync: Pending verification and completion.`r`n- Validation complete: Deterministic managed-payload application.`r`n- Validation remaining: Project checks, scoped commit, and GitHub result.`r`n"

if ($changes.Count -eq 0) {
    Write-Host "Project setup managed payload v${WorkflowVersion} is current. Review project-specific handoff content before claiming task completion."
    exit 0
}

if ($Check) {
    Write-Host "Project setup managed payload v${WorkflowVersion} is stale or incomplete:"
    $changes | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
    exit 2
}

Write-Host "Applied project setup workflow v${WorkflowVersion}:"
$changes | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
