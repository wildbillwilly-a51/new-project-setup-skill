# new-project-setup:managed-helper:v1
[CmdletBinding()]
param(
    [string]$ProjectRoot = ".",
    [string]$StatePath = ".codex/new-project-setup.json",
    [string]$Repository,
    [string]$RemoteName,
    [switch]$Initialize,
    [switch]$ScanOnly,
    [switch]$PublicReadiness
)

$ErrorActionPreference = "Stop"

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $Command @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }

    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "$Command failed with exit code ${exitCode}: $($output -join [Environment]::NewLine)"
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = @($output) }
}

function Get-RepositoryFromUrl {
    param([Parameter(Mandatory = $true)][string]$Url)
    if ($Url -match '^(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+/[^/]+?)(?:\.git)?$') {
        return $Matches[1]
    }
    return $null
}

function Assert-SourceHead {
    param([string]$RepoRoot, [string]$Expected)
    $current = ((Invoke-External 'git' @('-C', $RepoRoot, 'rev-parse', 'HEAD')).Output | Select-Object -First 1).Trim()
    if ($current -ne $Expected) { throw "Source HEAD changed during GitHub synchronization. No push was made." }
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
if (-not (Test-Path -LiteralPath (Join-Path $root '.git'))) { throw "ProjectRoot must be a Git repository root: $root" }
foreach ($required in @('git', 'tar')) {
    if (-not (Get-Command $required -ErrorAction SilentlyContinue)) { throw "Required command is unavailable: $required" }
}

$stateRelative = $StatePath.Replace('\', '/').TrimStart('/')
if ([IO.Path]::IsPathRooted($StatePath) -or $stateRelative -match '(^|/)\.\.(/|$)') {
    throw "StatePath must be project-relative."
}
$stateWorktreePath = Join-Path $root $stateRelative.Replace('/', [IO.Path]::DirectorySeparatorChar)
if ($Initialize) {
    if (-not (Test-Path -LiteralPath $stateWorktreePath -PathType Leaf)) { throw "Workflow state is missing: $stateRelative" }
    try { $state = Get-Content -Raw -LiteralPath $stateWorktreePath | ConvertFrom-Json }
    catch { throw "Workflow state is invalid JSON: $stateRelative" }
} else {
    $stateResult = Invoke-External 'git' @('-C', $root, 'show', "HEAD:$stateRelative") -AllowFailure
    if ($stateResult.ExitCode -ne 0) { throw "Committed workflow state is missing: $stateRelative" }
    try { $state = ($stateResult.Output -join [Environment]::NewLine) | ConvertFrom-Json }
    catch { throw "Committed workflow state is invalid JSON: $stateRelative" }
}
if ([int]$state.workflow_version -lt 3 -or [string]$state.github_mode -ne 'private-public-ready') {
    throw "Project setup workflow v3-or-later private-public-ready state is required before GitHub synchronization."
}

$effectiveRemote = if ($RemoteName) { $RemoteName } elseif ($state.remote) { [string]$state.remote } else { 'origin' }
$effectiveRepository = if ($Repository) { $Repository } elseif ($state.repository) { [string]$state.repository } else { $null }

if ($Initialize) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "GitHub CLI is unavailable; repository initialization is pending." }
    if ((Invoke-External 'gh' @('auth', 'status') -AllowFailure).ExitCode -ne 0) { throw "GitHub authentication is unavailable; run gh auth login." }
    if (-not $effectiveRepository) {
        $projectName = Split-Path -Leaf $root
        $view = Invoke-External 'gh' @('repo', 'view', $projectName, '--json', 'nameWithOwner', '--jq', '.nameWithOwner') -AllowFailure
        if ($view.ExitCode -ne 0) {
            Invoke-External 'gh' @('repo', 'create', $projectName, '--private') | Out-Null
            $view = Invoke-External 'gh' @('repo', 'view', $projectName, '--json', 'nameWithOwner', '--jq', '.nameWithOwner')
        }
        $effectiveRepository = ($view.Output | Select-Object -First 1).Trim()
    }
    $viewResult = Invoke-External 'gh' @('repo', 'view', $effectiveRepository, '--json', 'url,visibility')
    $viewData = ($viewResult.Output -join [Environment]::NewLine) | ConvertFrom-Json
    if ($viewData.visibility -ne 'PRIVATE') { throw "GitHub repository must remain private: $effectiveRepository" }
    $existingRemote = Invoke-External 'git' @('-C', $root, 'remote', 'get-url', $effectiveRemote) -AllowFailure
    if ($existingRemote.ExitCode -eq 0) {
        $existingUrl = ($existingRemote.Output | Select-Object -First 1).Trim()
        if ($existingUrl -notin @([string]$viewData.url, "$($viewData.url).git")) { throw "Remote $effectiveRemote points to a different repository." }
    } else {
        Invoke-External 'git' @('-C', $root, 'remote', 'add', $effectiveRemote, [string]$viewData.url) | Out-Null
    }
    $state.repository = $effectiveRepository
    $state.remote = $effectiveRemote
    [IO.File]::WriteAllText($stateWorktreePath, (($state | ConvertTo-Json -Depth 6) + "`r`n"), [Text.UTF8Encoding]::new($false))
    Write-Host "Initialized private public-ready GitHub destination $effectiveRepository on remote $effectiveRemote. Commit workflow state before synchronization."
    return
}

if (-not $effectiveRepository) { throw "Committed workflow state must record a GitHub repository before synchronization. Run github-sync.ps1 -Initialize during setup." }
$sourceHead = ((Invoke-External 'git' @('-C', $root, 'rev-parse', 'HEAD')).Output | Select-Object -First 1).Trim()
$branch = ((Invoke-External 'git' @('-C', $root, 'branch', '--show-current')).Output | Select-Object -First 1).Trim()
if (-not $branch) { throw "A named local branch is required for GitHub synchronization." }

$auditScript = Join-Path $PSScriptRoot 'github-backup.ps1'
& $auditScript -ProjectRoot $root -ScanOnly -AuditSourceHistory

if ($PublicReadiness) {
    Write-Host "Public-readiness audit passed for committed source history at $sourceHead. Repository visibility was not changed."
    return
}
if ($ScanOnly) {
    Write-Host "GitHub source synchronization scan passed for $sourceHead."
    return
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "GitHub CLI is unavailable; source synchronization is pending." }
if ((Invoke-External 'gh' @('auth', 'status') -AllowFailure).ExitCode -ne 0) { throw "GitHub authentication is unavailable; run gh auth login." }

$remoteResult = Invoke-External 'git' @('-C', $root, 'remote', 'get-url', $effectiveRemote) -AllowFailure
if ($remoteResult.ExitCode -eq 0) {
    $remoteUrl = ($remoteResult.Output | Select-Object -First 1).Trim()
    $remoteRepository = Get-RepositoryFromUrl $remoteUrl
    if (-not $remoteRepository -and -not $effectiveRepository) { throw "Remote $effectiveRemote is not a recognized GitHub repository: $remoteUrl" }
    if ($effectiveRepository -and $remoteRepository -and $remoteRepository -ne $effectiveRepository) {
        throw "Remote $effectiveRemote does not match committed repository $effectiveRepository."
    }
    if ($remoteRepository) { $effectiveRepository = $remoteRepository }
} else {
    $repoUrl = Invoke-External 'gh' @('repo', 'view', $effectiveRepository, '--json', 'url,visibility')
    $repoData = ($repoUrl.Output -join [Environment]::NewLine) | ConvertFrom-Json
    if ($repoData.visibility -ne 'PRIVATE') { throw "GitHub repository must remain private: $effectiveRepository" }
    $remoteUrl = [string]$repoData.url
    Invoke-External 'git' @('-C', $root, 'remote', 'add', $effectiveRemote, $remoteUrl) | Out-Null
}

$repoView = Invoke-External 'gh' @('repo', 'view', $effectiveRepository, '--json', 'url,visibility')
$repoInfo = ($repoView.Output -join [Environment]::NewLine) | ConvertFrom-Json
if ($repoInfo.visibility -ne 'PRIVATE') { throw "GitHub repository must remain private: $effectiveRepository" }
if ($remoteResult.ExitCode -eq 0 -and $remoteUrl -notin @([string]$repoInfo.url, "$($repoInfo.url).git")) {
    throw "Remote $effectiveRemote URL does not match private repository $effectiveRepository."
}
$pushUrlResult = Invoke-External 'git' @('-C', $root, 'remote', 'get-url', '--push', $effectiveRemote) -AllowFailure
if ($pushUrlResult.ExitCode -eq 0) {
    $pushUrl = ($pushUrlResult.Output | Select-Object -First 1).Trim()
    if ($pushUrl -eq 'DISABLED') {
        Invoke-External 'git' @('-C', $root, 'remote', 'set-url', '--push', $effectiveRemote, [string]$repoInfo.url) | Out-Null
    } elseif ($pushUrl -notin @([string]$repoInfo.url, "$($repoInfo.url).git")) {
        throw "Remote $effectiveRemote push URL does not match private repository $effectiveRepository."
    }
}

Assert-SourceHead $root $sourceHead
$remoteHeads = Invoke-External 'git' @('ls-remote', '--heads', [string]$repoInfo.url) -AllowFailure
if ($remoteHeads.ExitCode -ne 0) { throw "Unable to inspect remote branches for $effectiveRepository." }
if ($remoteHeads.Output.Count -gt 0) {
    Invoke-External 'git' @('-C', $root, 'fetch', $effectiveRemote, $branch) | Out-Null
    $remoteTip = ((Invoke-External 'git' @('-C', $root, 'rev-parse', "refs/remotes/${effectiveRemote}/${branch}")).Output | Select-Object -First 1).Trim()
    $ancestor = Invoke-External 'git' @('-C', $root, 'merge-base', '--is-ancestor', $remoteTip, $sourceHead) -AllowFailure
    if ($ancestor.ExitCode -ne 0) { throw "Remote history is diverged or ahead. No push was made." }
}

Assert-SourceHead $root $sourceHead
Invoke-External 'git' @('-C', $root, 'push', '-u', $effectiveRemote, "${sourceHead}:refs/heads/${branch}") | Out-Null
Assert-SourceHead $root $sourceHead
Write-Host "Private public-ready GitHub history is current at $effectiveRepository ($branch $sourceHead)."
