[CmdletBinding()]
param(
    [string]$ProjectRoot = ".",
    [string]$Repository,
    [string]$RemoteName,
    [switch]$Check
)

$ErrorActionPreference = "Stop"
$WorkflowVersion = 4
$resolvedRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$skillRoot = Split-Path -Parent $PSScriptRoot
$changes = New-Object Collections.Generic.List[string]

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
    if (-not (Test-Path -LiteralPath $Path)) {
        $changes.Add($Path.Substring($resolvedRoot.Length).TrimStart('\'))
        if (-not $Check) {
            $parent = Split-Path -Parent $Path
            if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
            Write-Utf8NoBom $Path ($Content + "`r`n")
        }
    }
}

$agentsBody = @'
### New project setup invocation

A bare or primary `$new-project-setup` invocation runs install/sync for this
project. Inspect first, then run the installed skill's
`scripts/apply-project-setup.ps1` against this project. Do not stop after merely
loading the skill. Questions about the skill are consultation-only.

### Adaptive execution

Classify task durability and operational risk independently from the user's
ordinary wording. When classification is clear, state the chosen treatment in
one short non-blocking sentence, then continue:

- Small lasting change: preserve the revision, use focused validation, and keep
  documentation proportional.
- Normal lasting work: use for applications, features, fixes, and reusable
  output; complete the bounded objective end-to-end and maintain durable memory.
- Exploration: use only when the context clearly indicates learning,
  comparison, or disposable feasibility work. Words such as `quick`,
  `prototype`, and `MVP` describe speed or maturity and do not by themselves
  make work disposable.

If durability is genuinely ambiguous, ask in plain language whether to preserve
the work or treat it as an experiment, with preservation recommended. Promote
exploratory work automatically when it becomes useful or continues growing.
Never demote lasting work, discard output, or require special user phrasing.

A bounded request such as `build this app` authorizes normal isolated local
construction: choose implementation details, project structure, established
project-local dependencies, tests, generated files, demo data, and schemas or
migrations for a new empty local database. Do not ask for routine implementation
transitions that remain within that objective.

### Proportional work tracking

At the start of each durable task, inspect Git status and read
`docs/codex-handoff.md`, the three most recent entries in
`docs/development-log.md`, and relevant `CHANGELOG.md` entries. Preserve every
lasting change in revision history. Update the public-ready development log only
when it adds useful decisions, rationale, failed approaches, validation, or
lessons. Refresh the handoff when objective, state, blockers, next action, or
continuation context changes. Update the changelog only for notable reader-facing
changes. Recheck branch, HEAD, and scoped paths immediately before committing.

After a safe commit, run `scripts/github-sync.ps1`. It audits the complete
public-ready source history before fast-forwarding the real branch to a private
GitHub repository. Never force-push or change visibility automatically. If the
audit blocks, keep the local commit and ask whether to run the isolated
`scripts/github-backup.ps1` fallback or remain local-only for that failure.

### Autonomous local work

Complete bounded objectives end-to-end within the authority reasonably implied
by the request and any explicit approvals. Continue through implementation and
focused validation without routine checkpoints.
Ask before deployment; credentials or live/paid services; auth/security changes;
global or native tool installation; framework or platform replacement;
consequential licensing changes; changes to existing, shared, or production
data; destructive operations; material product-direction expansion beyond the
request; or unrelated conflicting work. Internal refactoring, routine local
dependencies, and isolated local construction inside the bounded objective do
not require a separate checkpoint.

### Portable resume

Keep public-ready `docs/codex-handoff.md` current for every durable project so a
new Codex chat can recover the objective, current state, one next action,
blockers, decisions, branch/commit/sync status, and remaining validation. Keep
credentials and machine-specific or regulated detail in ignored `*.local.md`.
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

foreach ($managed in @(
    @{ Path = (Join-Path $resolvedRoot 'AGENTS.md'); Previous = @(@{ Start = '<!-- new-project-setup:v2:start -->'; End = '<!-- new-project-setup:v2:end -->' }, @{ Start = '<!-- new-project-setup:v3:start -->'; End = '<!-- new-project-setup:v3:end -->' }); NewStart = '<!-- new-project-setup:v4:start -->'; NewEnd = '<!-- new-project-setup:v4:end -->'; Body = $agentsBody.Trim() },
    @{ Path = (Join-Path $resolvedRoot '.gitignore'); Previous = @(@{ Start = '# new-project-setup:v2:start'; End = '# new-project-setup:v2:end' }, @{ Start = '# new-project-setup:v3:start'; End = '# new-project-setup:v3:end' }); NewStart = '# new-project-setup:v4:start'; NewEnd = '# new-project-setup:v4:end'; Body = $ignoreBody.Trim() },
    @{ Path = (Join-Path $resolvedRoot '.gitattributes'); Previous = @(@{ Start = '# new-project-setup:v2:start'; End = '# new-project-setup:v2:end' }, @{ Start = '# new-project-setup:v3:start'; End = '# new-project-setup:v3:end' }); NewStart = '# new-project-setup:v4:start'; NewEnd = '# new-project-setup:v4:end'; Body = $attributesBody.Trim() }
)) {
    $current = if (Test-Path -LiteralPath $managed.Path) { Get-Content -Raw -LiteralPath $managed.Path } else { '' }
    $previous = @($managed.Previous | Where-Object { $current -match [Regex]::Escape($_.Start) } | Select-Object -First 1)
    if ($previous.Count) {
        $oldPattern = '(?s)' + [Regex]::Escape($previous[0].Start) + '.*?' + [Regex]::Escape($previous[0].End)
        $replacement = $managed.NewStart + "`r`n" + $managed.Body + "`r`n" + $managed.NewEnd
        if (-not $Check) { Write-Utf8NoBom $managed.Path ([Regex]::Replace($current, $oldPattern, $replacement)) }
        $changes.Add($managed.Path.Substring($resolvedRoot.Length).TrimStart('\'))
    } else {
        Set-ManagedText $managed.Path $managed.NewStart $managed.NewEnd $managed.Body
    }
}
Ensure-File (Join-Path $resolvedRoot 'docs\development-log.md') "# Development Log`r`n`r`nKeep entries public-ready: completed work, decisions and rationale, useful failed approaches, validation, and durable lessons.`r`n"
Ensure-File (Join-Path $resolvedRoot 'docs\codex-handoff.md') "# Codex Handoff`r`n`r`n- Current objective: Project setup complete.`r`n- Current state: Ready for the next durable work package.`r`n- Next action: Define the next project objective.`r`n- Blockers: None.`r`n- Important decisions: GitHub history is private but public-ready.`r`n- Branch/commit/sync: Verify with Git before resuming.`r`n- Validation complete: Project setup validation.`r`n- Validation remaining: None.`r`n"
Ensure-File (Join-Path $resolvedRoot 'CHANGELOG.md') "# Changelog`r`n"

$statePath = Join-Path $resolvedRoot '.codex\new-project-setup.json'
$existingState = if (Test-Path -LiteralPath $statePath) {
    try { Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json } catch { $null }
} else { $null }
$effectiveRepository = if ($Repository) { $Repository } elseif ($existingState.repository) { [string]$existingState.repository } else { $null }
$effectiveRemote = if ($RemoteName) { $RemoteName } elseif ($existingState.remote) { [string]$existingState.remote } else { 'origin' }
$stateContent = ([ordered]@{
    format = 2
    workflow_version = $WorkflowVersion
    github_mode = 'private-public-ready'
    repository = $effectiveRepository
    remote = $effectiveRemote
    source_history_sync = $true
    audit_failure_action = 'ask'
    development_log = $true
    codex_handoff = 'always'
    execution_mode = 'adaptive'
    durability_ambiguity_action = 'ask'
    classification_notice = 'concise'
    routine_project_dependencies = 'allow'
    isolated_local_build = 'allow'
    documentation_detail = 'proportional'
}) | ConvertTo-Json
$stateCurrent = if (Test-Path -LiteralPath $statePath) { (Get-Content -Raw -LiteralPath $statePath).Trim() } else { "" }
if ($stateCurrent -ne $stateContent.Trim()) {
    $changes.Add('.codex\new-project-setup.json')
    if (-not $Check) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $statePath) | Out-Null
        Write-Utf8NoBom $statePath ($stateContent + "`r`n")
    }
}

$sourceHelper = Join-Path $PSScriptRoot 'github-backup.ps1'
$targetHelper = Join-Path $resolvedRoot 'scripts\github-backup.ps1'
$copyNeeded = -not (Test-Path -LiteralPath $targetHelper)
if (-not $copyNeeded) {
    $copyNeeded = (Get-FileHash -Algorithm SHA256 $sourceHelper).Hash -ne (Get-FileHash -Algorithm SHA256 $targetHelper).Hash
}

$sourceSync = Join-Path $PSScriptRoot 'github-sync.ps1'
$targetSync = Join-Path $resolvedRoot 'scripts\github-sync.ps1'
$syncCopyNeeded = -not (Test-Path -LiteralPath $targetSync)
if (-not $syncCopyNeeded) {
    $syncCopyNeeded = (Get-FileHash -Algorithm SHA256 $sourceSync).Hash -ne (Get-FileHash -Algorithm SHA256 $targetSync).Hash
}
if ($syncCopyNeeded) {
    $changes.Add('scripts\github-sync.ps1')
    if (-not $Check) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetSync) | Out-Null
        $resolvedSourceSync = (Resolve-Path -LiteralPath $sourceSync).Path
        $resolvedTargetSync = [IO.Path]::GetFullPath($targetSync)
        if ($resolvedSourceSync -ne $resolvedTargetSync) {
            Copy-Item -LiteralPath $sourceSync -Destination $targetSync -Force
        }
    }
}
if ($copyNeeded) {
    $changes.Add('scripts\github-backup.ps1')
    if (-not $Check) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetHelper) | Out-Null
        $resolvedSourceHelper = (Resolve-Path -LiteralPath $sourceHelper).Path
        $resolvedTargetHelper = [IO.Path]::GetFullPath($targetHelper)
        if ($resolvedSourceHelper -ne $resolvedTargetHelper) {
            Copy-Item -LiteralPath $sourceHelper -Destination $targetHelper -Force
        }
    }
}

if ($changes.Count -eq 0) {
    Write-Host "Project setup workflow v${WorkflowVersion} is current."
    exit 0
}

if ($Check) {
    Write-Host "Project setup workflow v${WorkflowVersion} is stale or incomplete:"
    $changes | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
    exit 2
}

Write-Host "Applied project setup workflow v${WorkflowVersion}:"
$changes | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
