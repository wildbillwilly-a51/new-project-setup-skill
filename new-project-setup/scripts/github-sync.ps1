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
$PathComparison = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    [StringComparison]::OrdinalIgnoreCase
} else {
    [StringComparison]::Ordinal
}

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

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    if ($full.Length -gt $root.Length) {
        $full = $full.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    }
    return $full
}

function Test-SamePath {
    param([string]$Left, [string]$Right)
    return [string]::Equals((Get-NormalizedFullPath $Left), (Get-NormalizedFullPath $Right), $PathComparison)
}

function Assert-ContainedPath {
    param([string]$Path, [string]$Parent, [string]$Label)

    $fullPath = Get-NormalizedFullPath $Path
    $fullParent = Get-NormalizedFullPath $Parent
    $prefix = $fullParent + [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($prefix, $PathComparison)) {
        throw "$Label must remain inside its expected parent."
    }
    return $fullPath
}

function Test-RedirectedItem {
    param([object]$Item)

    if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { return $false }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return $true }
    $linkType = if ($Item.PSObject.Properties['LinkType']) { [string]$Item.LinkType } else { '' }
    $targets = if ($Item.PSObject.Properties['Target']) { @($Item.Target) } else { @() }
    return -not [string]::IsNullOrWhiteSpace($linkType) -or $targets.Count -gt 0
}

function Assert-NoRedirectedPath {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Label)

    $full = Get-NormalizedFullPath $Path
    $pathRoot = [IO.Path]::GetPathRoot($full)
    $cursor = $pathRoot
    $relative = $full.Substring($pathRoot.Length)
    foreach ($segment in $relative.Split(@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar), [StringSplitOptions]::RemoveEmptyEntries)) {
        $cursor = Join-Path $cursor $segment
        if (-not (Test-Path -LiteralPath $cursor)) { break }
        $item = Get-Item -Force -LiteralPath $cursor
        if (Test-RedirectedItem $item) {
            throw "$Label crosses a redirected path component."
        }
    }
    return $full
}

function Resolve-SafeProjectRoot {
    param([string]$Path)

    $candidate = Assert-NoRedirectedPath (Get-NormalizedFullPath $Path) 'ProjectRoot'
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
        throw "ProjectRoot must be an existing directory."
    }
    $resolved = (Resolve-Path -LiteralPath $candidate).Path
    if (-not (Test-SamePath $candidate $resolved)) {
        throw "ProjectRoot must not be a redirected link."
    }
    $gitRoot = ((Invoke-External 'git' @('-C', $resolved, 'rev-parse', '--show-toplevel')).Output | Select-Object -First 1).Trim()
    if (-not (Test-SamePath $resolved $gitRoot)) {
        throw "ProjectRoot must be the Git repository root."
    }
    Assert-NoRedirectedPath $resolved 'ProjectRoot' | Out-Null
    return Get-NormalizedFullPath $resolved
}

function Get-SafeRelativePath {
    param([string]$RepoRoot, [string]$RelativePath, [string]$Label)

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath)) {
        throw "$Label must be project-relative."
    }
    $normalized = $RelativePath.Replace('\', '/')
    if ($normalized.StartsWith('/') -or $normalized -match '(^|/)\.\.(/|$)' -or $normalized.IndexOf([char]0) -ge 0) {
        throw "$Label must be project-relative."
    }
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and $normalized -match ':') {
        throw "$Label must not use an alternate data stream."
    }
    $full = Get-NormalizedFullPath (Join-Path $RepoRoot $normalized.Replace('/', [IO.Path]::DirectorySeparatorChar))
    Assert-ContainedPath $full $RepoRoot $Label | Out-Null
    return [pscustomobject]@{ Relative = $normalized; FullPath = $full }
}

function Invoke-TestFault {
    param([string]$Name, [string]$ContextPath)

    if ([string]$env:NEW_PROJECT_SETUP_TEST_FAULT -cne $Name) { return }
    $action = [string]$env:NEW_PROJECT_SETUP_TEST_ACTION
    if ([string]::IsNullOrWhiteSpace($action)) {
        throw "Injected test fault at $Name."
    }
    if (-not [IO.Path]::IsPathRooted($action) -or [IO.Path]::GetExtension($action) -ine '.ps1') {
        throw "The injected test action must be an absolute local PowerShell script path."
    }
    $actionPath = Assert-NoRedirectedPath $action 'Injected test action'
    if (-not (Test-Path -LiteralPath $actionPath -PathType Leaf)) {
        throw "The injected test action is unavailable."
    }
    & $actionPath $Name $ContextPath | Out-Null
}

function Get-RepositoryFromUrl {
    param([Parameter(Mandatory = $true)][string]$Url)

    $trimmed = $Url.Trim()
    if ($trimmed -match '^(?i:https://github\.com/|git@github\.com:|ssh://git@github\.com/)([^/\s]+/[^/\s]+?)(?:\.git)?/?$') {
        return $Matches[1]
    }
    return $null
}

function Test-SameRepository {
    param([string]$Left, [string]$Right)
    return -not [string]::IsNullOrWhiteSpace($Left) -and
        -not [string]::IsNullOrWhiteSpace($Right) -and
        [string]::Equals($Left.TrimEnd('/'), $Right.TrimEnd('/'), [StringComparison]::OrdinalIgnoreCase)
}

function Resolve-GitHubRepository {
    param([Parameter(Mandatory = $true)][string]$RepositoryValue, [switch]$AllowMissing)

    $view = Invoke-External 'gh' @('repo', 'view', $RepositoryValue, '--json', 'nameWithOwner,url,visibility,isEmpty') -AllowFailure
    if ($view.ExitCode -ne 0) {
        if ($AllowMissing) { return $null }
        throw "Unable to resolve the configured GitHub repository."
    }
    try { $data = ($view.Output -join [Environment]::NewLine) | ConvertFrom-Json }
    catch { throw "GitHub returned invalid repository metadata." }
    $canonical = [string]$data.nameWithOwner
    $url = [string]$data.url
    $urlRepository = Get-RepositoryFromUrl $url
    if ($canonical -notmatch '^[^/\s]+/[^/\s]+$' -or -not (Test-SameRepository $canonical $urlRepository)) {
        throw "GitHub returned inconsistent repository identity metadata."
    }
    if ([string]$data.visibility -cne 'PRIVATE') {
        throw "GitHub repository must remain private: $canonical"
    }
    return [pscustomobject]@{
        Repository = $canonical
        Url = $url
        Visibility = [string]$data.visibility
        IsEmpty = [bool]$data.isEmpty
    }
}

function Get-ExactRemoteNames {
    param([string]$RepoRoot)
    return [string[]]@((Invoke-External 'git' @('-C', $RepoRoot, 'remote')).Output | ForEach-Object { [string]$_ })
}

function Test-ExactRemoteName {
    param([string[]]$Names, [string]$Name)
    foreach ($candidate in $Names) {
        if ([string]::Equals($candidate, $Name, [StringComparison]::Ordinal)) { return $true }
    }
    return $false
}

function Get-RemoteUrlState {
    param([string]$RepoRoot, [string]$Name)

    $fetchResult = Invoke-External 'git' @('-C', $RepoRoot, 'remote', 'get-url', '--all', $Name)
    $pushResult = Invoke-External 'git' @('-C', $RepoRoot, 'remote', 'get-url', '--push', '--all', $Name)
    return [pscustomobject]@{
        Fetch = [string[]]@($fetchResult.Output | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
        Push = [string[]]@($pushResult.Output | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    }
}

function Get-CanonicalRemoteRepository {
    param([object]$UrlState, [switch]$AllowDisabledPush)

    $repository = $null
    foreach ($url in @($UrlState.Fetch) + @($UrlState.Push)) {
        if ($AllowDisabledPush -and $url -ceq 'DISABLED') { continue }
        $candidate = Get-RepositoryFromUrl ([string]$url)
        if (-not $candidate) { return $null }
        if ($repository -and -not (Test-SameRepository $repository $candidate)) { return $null }
        $repository = $candidate
    }
    return $repository
}

function Assert-RemoteMatchesRepository {
    param([string]$RepoRoot, [string]$Name, [string]$ExpectedRepository, [switch]$AllowDisabledPush)

    $state = Get-RemoteUrlState $RepoRoot $Name
    if ($state.Fetch.Count -eq 0 -or $state.Push.Count -eq 0) {
        throw "Remote $Name has incomplete URL configuration."
    }
    foreach ($url in @($state.Fetch) + @($state.Push)) {
        if ($AllowDisabledPush -and $url -ceq 'DISABLED') { continue }
        $actual = Get-RepositoryFromUrl ([string]$url)
        if (-not (Test-SameRepository $actual $ExpectedRepository)) {
            throw "Remote $Name contains a URL for a different or unrecognized repository."
        }
    }
    return $state
}

function Get-RemoteBranchTip {
    param([string]$Url, [string]$Branch)

    if ((Invoke-External 'git' @('check-ref-format', '--branch', $Branch) -AllowFailure).ExitCode -ne 0) {
        throw "The local branch name is not safe for synchronization."
    }
    $ref = "refs/heads/$Branch"
    $result = Invoke-External 'git' @('ls-remote', '--exit-code', '--heads', $Url, $ref) -AllowFailure
    if ($result.ExitCode -eq 2) { return [pscustomobject]@{ Exists = $false; Sha = $null; Ref = $ref } }
    if ($result.ExitCode -ne 0) { throw "Unable to inspect the exact remote branch."
    }
    $lines = @($result.Output | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($lines.Count -ne 1 -or [string]$lines[0] -notmatch '^([0-9a-fA-F]{40,64})\s+(.+)$' -or $Matches[2] -cne $ref) {
        throw "Remote branch inspection returned an ambiguous result."
    }
    return [pscustomobject]@{ Exists = $true; Sha = $Matches[1].ToLowerInvariant(); Ref = $ref }
}

function Assert-SourceState {
    param([string]$RepoRoot, [string]$ExpectedHead, [string]$ExpectedBranch)

    $currentHead = ((Invoke-External 'git' @('-C', $RepoRoot, 'rev-parse', '--verify', 'HEAD^{commit}')).Output | Select-Object -First 1).Trim()
    $currentBranch = ((Invoke-External 'git' @('-C', $RepoRoot, 'branch', '--show-current')).Output | Select-Object -First 1).Trim()
    if ($currentHead -cne $ExpectedHead -or ($ExpectedBranch -and $currentBranch -cne $ExpectedBranch)) {
        throw "Source HEAD or branch changed during GitHub synchronization. No push was made."
    }
}

function Set-ObjectProperty {
    param([object]$Object, [string]$Name, [object]$Value)
    if ($Object.PSObject.Properties[$Name]) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Write-StateAtomically {
    param([string]$RepoRoot, [string]$StateFile, [string]$ExpectedText, [string]$NewText)

    Assert-ContainedPath $StateFile $RepoRoot 'StatePath' | Out-Null
    Assert-NoRedirectedPath $StateFile 'StatePath' | Out-Null
    $currentText = Get-Content -Raw -LiteralPath $StateFile
    if ($currentText -cne $ExpectedText) {
        throw "Workflow state changed during initialization. No state or remote update was made."
    }
    $directory = Split-Path -Parent $StateFile
    Assert-NoRedirectedPath $directory 'StatePath parent' | Out-Null
    $operationId = [Guid]::NewGuid().ToString('N')
    $tempPath = Join-Path $directory ('.' + [IO.Path]::GetFileName($StateFile) + '.codex-' + $operationId + '.tmp')
    $backupPath = Join-Path $directory ('.' + [IO.Path]::GetFileName($StateFile) + '.codex-' + $operationId + '.bak')
    Assert-ContainedPath $tempPath $RepoRoot 'Temporary state path' | Out-Null
    Assert-ContainedPath $backupPath $RepoRoot 'State rollback path' | Out-Null
    try {
        [IO.File]::WriteAllText($tempPath, $NewText, [Text.UTF8Encoding]::new($false))
        Invoke-TestFault 'sync-before-state-replace' $StateFile
        Assert-NoRedirectedPath $StateFile 'StatePath' | Out-Null
        Assert-NoRedirectedPath $tempPath 'Temporary state path' | Out-Null
        Assert-ContainedPath $StateFile $RepoRoot 'StatePath' | Out-Null
        Assert-ContainedPath $tempPath $RepoRoot 'Temporary state path' | Out-Null
        [IO.File]::Replace($tempPath, $StateFile, $backupPath)
        Assert-NoRedirectedPath $backupPath 'State rollback path' | Out-Null
        Assert-ContainedPath $backupPath $RepoRoot 'State rollback path' | Out-Null
        Remove-Item -LiteralPath $backupPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) {
            Assert-NoRedirectedPath $tempPath 'Temporary state path' | Out-Null
            Assert-ContainedPath $tempPath $RepoRoot 'Temporary state path' | Out-Null
            Remove-Item -LiteralPath $tempPath -Force
        }
        if (Test-Path -LiteralPath $backupPath) {
            Assert-NoRedirectedPath $backupPath 'State rollback path' | Out-Null
            Assert-ContainedPath $backupPath $RepoRoot 'State rollback path' | Out-Null
            Remove-Item -LiteralPath $backupPath -Force
        }
    }
}

foreach ($required in @('git', 'tar')) {
    if (-not (Get-Command $required -ErrorAction SilentlyContinue)) { throw "Required command is unavailable: $required" }
}

$root = Resolve-SafeProjectRoot $ProjectRoot
$stateLocation = Get-SafeRelativePath $root $StatePath 'StatePath'
$stateRelative = $stateLocation.Relative
$stateWorktreePath = $stateLocation.FullPath
Assert-NoRedirectedPath $stateWorktreePath 'StatePath' | Out-Null

if ($Initialize) {
    if (-not (Test-Path -LiteralPath $stateWorktreePath -PathType Leaf)) { throw "Workflow state is missing: $stateRelative" }
    $stateText = Get-Content -Raw -LiteralPath $stateWorktreePath
    try { $state = $stateText | ConvertFrom-Json }
    catch { throw "Workflow state is invalid JSON: $stateRelative" }
} else {
    $sourceHead = ((Invoke-External 'git' @('-C', $root, 'rev-parse', '--verify', 'HEAD^{commit}')).Output | Select-Object -First 1).Trim()
    $stateResult = Invoke-External 'git' @('-C', $root, 'show', "${sourceHead}:$stateRelative") -AllowFailure
    if ($stateResult.ExitCode -ne 0) { throw "Committed workflow state is missing: $stateRelative" }
    try { $state = ($stateResult.Output -join [Environment]::NewLine) | ConvertFrom-Json }
    catch { throw "Committed workflow state is invalid JSON: $stateRelative" }
}
if ([int]$state.workflow_version -lt 3 -or [string]$state.github_mode -ne 'private-public-ready') {
    throw "Project setup workflow v3-or-later private-public-ready state is required before GitHub synchronization."
}

$remoteNames = Get-ExactRemoteNames $root
$requestedRemote = if ($RemoteName) { $RemoteName } elseif ($state.remote) { [string]$state.remote } else { $null }
if ($requestedRemote) {
    $effectiveRemote = $requestedRemote
} elseif (Test-ExactRemoteName $remoteNames 'origin') {
    $originState = Get-RemoteUrlState $root 'origin'
    $effectiveRemote = if (Get-CanonicalRemoteRepository $originState -AllowDisabledPush) { 'origin' } else { 'github' }
} else {
    $effectiveRemote = 'origin'
}
$remoteExists = Test-ExactRemoteName $remoteNames $effectiveRemote
$effectiveRepository = if ($Repository) { $Repository } elseif ($state.repository) { [string]$state.repository } else { $null }

if ($Initialize) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "GitHub CLI is unavailable; repository initialization is pending." }
    if ((Invoke-External 'gh' @('auth', 'status') -AllowFailure).ExitCode -ne 0) { throw "GitHub authentication is unavailable; run gh auth login." }

    $remoteCandidate = $null
    if ($remoteExists) {
        $remoteCandidate = Get-CanonicalRemoteRepository (Get-RemoteUrlState $root $effectiveRemote) -AllowDisabledPush
        if (-not $remoteCandidate) { throw "Remote $effectiveRemote does not have one canonical GitHub repository identity." }
        if (-not $effectiveRepository) { $effectiveRepository = $remoteCandidate }
    }

    $autoSelected = -not $effectiveRepository
    if ($autoSelected) {
        $loginResult = Invoke-External 'gh' @('api', 'user', '--jq', '.login')
        $login = (($loginResult.Output | Select-Object -First 1)).Trim()
        if ($login -notmatch '^[A-Za-z0-9-]+$') { throw "Unable to determine the authenticated GitHub owner." }
        $projectName = Split-Path -Leaf $root
        $candidate = "$login/$projectName"
        $repoInfo = Resolve-GitHubRepository $candidate -AllowMissing
        if (-not $repoInfo) {
            Invoke-External 'gh' @('repo', 'create', $candidate, '--private') | Out-Null
            $repoInfo = Resolve-GitHubRepository $candidate
        } elseif (-not $repoInfo.IsEmpty) {
            throw "The automatically selected same-name GitHub repository is not empty. Specify a repository explicitly or configure its matching remote."
        }
    } else {
        $repoInfo = Resolve-GitHubRepository $effectiveRepository
    }

    $effectiveRepository = $repoInfo.Repository
    if ($remoteCandidate -and -not (Test-SameRepository $remoteCandidate $effectiveRepository)) {
        throw "Remote $effectiveRemote points to a different repository."
    }
    if ($remoteExists) {
        Assert-RemoteMatchesRepository $root $effectiveRemote $effectiveRepository -AllowDisabledPush | Out-Null
    }

    Set-ObjectProperty $state 'repository' $effectiveRepository
    Set-ObjectProperty $state 'remote' $effectiveRemote
    $newStateText = ($state | ConvertTo-Json -Depth 6) + "`r`n"
    Write-StateAtomically $root $stateWorktreePath $stateText $newStateText

    if (-not $remoteExists) {
        Invoke-External 'git' @('-C', $root, 'remote', 'add', $effectiveRemote, [string]$repoInfo.Url) | Out-Null
    } else {
        $pushState = Get-RemoteUrlState $root $effectiveRemote
        if ($pushState.Push.Count -eq 1 -and $pushState.Push[0] -ceq 'DISABLED') {
            Invoke-External 'git' @('-C', $root, 'remote', 'set-url', '--push', $effectiveRemote, [string]$repoInfo.Url) | Out-Null
        }
    }
    Write-Host "Initialized private public-ready GitHub destination $effectiveRepository on remote $effectiveRemote. Commit workflow state before synchronization."
    return
}

if (-not $effectiveRepository) { throw "Committed workflow state must record a GitHub repository before synchronization. Run github-sync.ps1 -Initialize during setup." }
$branch = ((Invoke-External 'git' @('-C', $root, 'branch', '--show-current')).Output | Select-Object -First 1).Trim()
if (-not $branch) { throw "A named local branch is required for GitHub synchronization." }
if ((Invoke-External 'git' @('check-ref-format', '--branch', $branch) -AllowFailure).ExitCode -ne 0) {
    throw "The local branch name is not safe for synchronization."
}
Assert-SourceState $root $sourceHead $branch

$auditScript = Join-Path $PSScriptRoot 'github-backup.ps1'
& $auditScript -ProjectRoot $root -SourceCommit $sourceHead -ScanOnly -AuditSourceHistory
Invoke-TestFault 'sync-after-source-audit' $root
Assert-SourceState $root $sourceHead $branch

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

$repoInfo = Resolve-GitHubRepository $effectiveRepository
$effectiveRepository = $repoInfo.Repository
$remoteNames = Get-ExactRemoteNames $root
if (Test-ExactRemoteName $remoteNames $effectiveRemote) {
    Assert-RemoteMatchesRepository $root $effectiveRemote $effectiveRepository -AllowDisabledPush | Out-Null
} else {
    Invoke-External 'git' @('-C', $root, 'remote', 'add', $effectiveRemote, [string]$repoInfo.Url) | Out-Null
}

$initialRemote = Get-RemoteBranchTip ([string]$repoInfo.Url) $branch
$auditRef = "refs/codex/github-sync/$([Guid]::NewGuid().ToString('N'))"
$fetchedTip = $null
try {
    if ($initialRemote.Exists) {
        Invoke-External 'git' @('-C', $root, 'fetch', '--no-tags', '--no-write-fetch-head', [string]$repoInfo.Url, "$($initialRemote.Ref):$auditRef") | Out-Null
        $fetchedTip = ((Invoke-External 'git' @('-C', $root, 'rev-parse', '--verify', "${auditRef}^{commit}")).Output | Select-Object -First 1).Trim()
        if ($fetchedTip -cne $initialRemote.Sha) { throw "Remote branch changed while it was being captured. No push was made." }
        $ancestor = Invoke-External 'git' @('-C', $root, 'merge-base', '--is-ancestor', $fetchedTip, $sourceHead) -AllowFailure
        if ($ancestor.ExitCode -ne 0) { throw "Remote history is diverged or ahead. No push was made." }
    }

    Invoke-TestFault 'sync-before-push-recheck' $root
    Assert-SourceState $root $sourceHead $branch
    $repoBeforePush = Resolve-GitHubRepository $effectiveRepository
    if (-not (Test-SameRepository $repoBeforePush.Repository $effectiveRepository)) {
        throw "GitHub repository identity changed during synchronization. No push was made."
    }
    $currentRemote = Get-RemoteBranchTip ([string]$repoBeforePush.Url) $branch
    if ($currentRemote.Exists -ne $initialRemote.Exists -or ($currentRemote.Exists -and $currentRemote.Sha -cne $fetchedTip)) {
        throw "Remote branch changed after validation. No push was made."
    }

    Assert-SourceState $root $sourceHead $branch
    Invoke-External 'git' @('-C', $root, 'push', [string]$repoBeforePush.Url, "${sourceHead}:refs/heads/${branch}") | Out-Null
    Assert-SourceState $root $sourceHead $branch
}
finally {
    if ($fetchedTip) { Invoke-External 'git' @('-C', $root, 'update-ref', '-d', $auditRef) -AllowFailure | Out-Null }
}
Write-Host "Private public-ready GitHub history is current at $effectiveRepository ($branch $sourceHead)."
