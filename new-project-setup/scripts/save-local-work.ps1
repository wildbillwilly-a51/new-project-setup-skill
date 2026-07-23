#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Prepare', 'Commit')]
    [string]$Operation,

    [Parameter(Mandatory = $true)]
    [string]$Repository,

    [Alias('ObjectivePaths')]
    [string[]]$ObjectivePath = @(),

    [string]$ObjectivePathsJson,

    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$CommitMessage,

    [string]$ExpectedBranch,
    [AllowNull()][string]$ExpectedHead,
    [switch]$ExpectedUnborn,
    [string]$ExpectedTree
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [Version]'7.6.0') {
    throw 'PowerShell Core 7.6 or later (pwsh) is required. No legacy-host fallback is supported.'
}
$script:IsWindowsPlatform = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$script:PathComparison = if ($script:IsWindowsPlatform) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
$script:RepositoryRoot = $null
$script:GitDirectory = $null
$script:GitExecutable = $null
$script:LockStream = $null
$script:ObjectivePathInput = @()
$script:PrepareInitialIndex = $null
$script:PrepareStagedIndex = $null
$script:PrepareExpectedState = $null
$script:PrepareIndexPhase = 'before_staging'
$script:ContentScanLimitBytes = 8MB
$script:Result = [ordered]@{
    contract_version = 1
    operation = $Operation.ToLowerInvariant()
    outcome = $null
    failure_category = $null
    repository = $null
    branch = $null
    expected_head = $null
    previous_head = $null
    commit = $null
    expected_tree = $null
    actual_tree = $null
    paths = @()
    change_summary = @()
    warnings = @()
    blockers = @()
    head_advanced = $false
    prepare_cleanup = [ordered]@{
        status = 'not_needed'
        index_changed_by_helper = $false
        index_clean_afterward = $null
        reason = $null
        staged_paths = @()
    }
    commit_message_verification = [ordered]@{
        status = 'not_checked'
        expected_sha256 = $null
        actual_sha256 = $null
        expected_characters = $null
        actual_characters = $null
        sensitive_content_detected = $false
    }
}

function Write-Diagnostic {
    param([string]$Message)
    [Console]::Error.WriteLine($Message)
}

function Stop-LocalSave {
    param(
        [string]$Category,
        [string]$Message,
        [object[]]$Blockers = @(),
        [ValidateSet('failed_before_commit', 'indeterminate')]
        [string]$Outcome = 'failed_before_commit'
    )
    $exception = [InvalidOperationException]::new($Message)
    $exception.Data['local_save_category'] = $Category
    $exception.Data['local_save_outcome'] = $Outcome
    $exception.Data['local_save_blockers'] = [object[]]@($Blockers)
    throw $exception
}

function ConvertTo-ResultJson {
    param([object]$Value)
    return ($Value | ConvertTo-Json -Depth 10 -Compress)
}

function Get-NormalizedFullPath {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    if ($full.Length -gt $root.Length) {
        $full = $full.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    }
    return $full
}

function Test-SamePath {
    param([string]$Left, [string]$Right)
    return [string]::Equals((Get-NormalizedFullPath $Left), (Get-NormalizedFullPath $Right), $script:PathComparison)
}

function Get-StringSha256 {
    param([string]$Value)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant()
}

function Invoke-Git {
    param(
        [string[]]$Arguments,
        [string]$Root = $script:RepositoryRoot,
        [int]$TimeoutSeconds = 120
    )
    if ([string]::IsNullOrWhiteSpace($script:GitExecutable)) {
        Stop-LocalSave 'git_unavailable' 'Git is required for local saving.'
    }
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $script:GitExecutable
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.CreateNoWindow = $true
    if (-not [string]::IsNullOrWhiteSpace($Root)) {
        $startInfo.ArgumentList.Add('-C')
        $startInfo.ArgumentList.Add($Root)
    }
    foreach ($argument in @($Arguments)) { $startInfo.ArgumentList.Add([string]$argument) }
    $startInfo.Environment['LC_ALL'] = 'C'
    $startInfo.Environment['LANG'] = 'C'

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { Stop-LocalSave 'git_failed' 'Git could not be started.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill($true) } catch {}
            Stop-LocalSave 'git_timeout' 'A bounded local Git operation timed out.'
        }
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut = [string]$stdoutTask.GetAwaiter().GetResult()
            StdErr = [string]$stderrTask.GetAwaiter().GetResult()
        }
    }
    finally { $process.Dispose() }
}

function Invoke-GitChecked {
    param(
        [string[]]$Arguments,
        [string]$Description,
        [string]$Category = 'git_failed',
        [string]$Root = $script:RepositoryRoot
    )
    $result = Invoke-Git -Arguments $Arguments -Root $Root
    if ($result.ExitCode -ne 0) { Stop-LocalSave $Category "Git failed while $Description." }
    return $result
}

function Split-NulText {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return @() }
    return @($Value.Split([char]0, [StringSplitOptions]::RemoveEmptyEntries))
}

function Resolve-RepositoryRoot {
    if (-not [IO.Path]::IsPathRooted($Repository)) {
        Stop-LocalSave 'invalid_repository' 'The repository path must be absolute.'
    }
    $requested = Get-NormalizedFullPath $Repository
    if (-not (Test-Path -LiteralPath $requested -PathType Container)) {
        Stop-LocalSave 'invalid_repository' 'The repository path is not an existing directory.'
    }
    $item = Get-Item -Force -LiteralPath $requested
    if (($item.PSObject.Properties.Name -contains 'LinkType' -and -not [string]::IsNullOrWhiteSpace([string]$item.LinkType)) -or
        ($item.PSObject.Properties.Name -contains 'Target' -and
            @($item.Target | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0)) {
        Stop-LocalSave 'ambiguous_repository' 'The repository root must not be a redirected path.'
    }
    foreach ($name in @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR')) {
        if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, 'Process'))) {
            Stop-LocalSave 'alternate_git_environment' "The $name environment override is not supported."
        }
    }
    if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('GIT_INDEX_FILE', 'Process'))) {
        Stop-LocalSave 'alternate_index' 'Alternate Git indexes are not supported.'
    }

    $inside = Invoke-Git -Arguments @('rev-parse', '--is-inside-work-tree') -Root $requested
    if ($inside.ExitCode -ne 0 -or $inside.StdOut.Trim() -cne 'true') {
        Stop-LocalSave 'invalid_repository' 'The target is not a Git worktree.'
    }
    $rootResult = Invoke-GitChecked -Arguments @('rev-parse', '--show-toplevel') -Description 'resolving the worktree root' -Category 'invalid_repository' -Root $requested
    $actual = Get-NormalizedFullPath $rootResult.StdOut.Trim()
    if (-not (Test-SamePath $requested $actual)) {
        Stop-LocalSave 'repository_root_mismatch' 'The target path is not the exact Git worktree root.'
    }
    $expectedGitDirectory = Get-NormalizedFullPath (Join-Path $actual '.git')
    if (-not (Test-Path -LiteralPath $expectedGitDirectory -PathType Container)) {
        Stop-LocalSave 'unsupported_git_layout' 'Local saving requires a real repository-local .git directory.'
    }
    $gitItem = Get-Item -Force -LiteralPath $expectedGitDirectory
    $redirectedGitDirectory =
        ($gitItem.PSObject.Properties.Name -contains 'LinkType' -and -not [string]::IsNullOrWhiteSpace([string]$gitItem.LinkType)) -or
        ($gitItem.PSObject.Properties.Name -contains 'Target' -and
            @($gitItem.Target | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0)
    if ($redirectedGitDirectory) {
        Stop-LocalSave 'unsupported_git_layout' 'Redirected Git metadata is not supported.'
    }
    $absoluteGitResult = Invoke-GitChecked -Arguments @('rev-parse', '--absolute-git-dir') -Description 'resolving the Git directory' -Category 'unsupported_git_layout' -Root $actual
    $commonGitResult = Invoke-GitChecked -Arguments @('rev-parse', '--git-common-dir') -Description 'resolving the common Git directory' -Category 'unsupported_git_layout' -Root $actual
    $reportedGitDirectory = Get-NormalizedFullPath $absoluteGitResult.StdOut.Trim()
    $reportedCommonDirectory = $commonGitResult.StdOut.Trim()
    if (-not [IO.Path]::IsPathRooted($reportedCommonDirectory)) {
        $reportedCommonDirectory = Join-Path $actual $reportedCommonDirectory
    }
    $reportedCommonDirectory = Get-NormalizedFullPath $reportedCommonDirectory
    if (-not (Test-SamePath $reportedGitDirectory $expectedGitDirectory) -or
        -not (Test-SamePath $reportedCommonDirectory $expectedGitDirectory)) {
        Stop-LocalSave 'unsupported_git_layout' 'Linked, external, or shared Git metadata is not supported.'
    }
    $script:GitDirectory = $expectedGitDirectory
    return $actual
}

function Enter-LocalSaveLock {
    $lockRoot = Join-Path ([IO.Path]::GetTempPath()) 'codex-local-save-locks'
    New-Item -ItemType Directory -Force -Path $lockRoot | Out-Null
    $lockRootItem = Get-Item -Force -LiteralPath $lockRoot
    if (-not $lockRootItem.PSIsContainer -or
        ($lockRootItem.PSObject.Properties.Name -contains 'LinkType' -and -not [string]::IsNullOrWhiteSpace([string]$lockRootItem.LinkType))) {
        Stop-LocalSave 'unsafe_lock_root' 'The local-save lock root is not a safe directory.'
    }
    $identity = if ($script:IsWindowsPlatform) { $script:RepositoryRoot.ToUpperInvariant() } else { $script:RepositoryRoot }
    $lockPath = Join-Path $lockRoot ((Get-StringSha256 $identity) + '.lock')
    try {
        $script:LockStream = [IO.FileStream]::new(
            $lockPath,
            [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None,
            1,
            [IO.FileOptions]::DeleteOnClose
        )
    }
    catch [IO.IOException] { Stop-LocalSave 'lock_unavailable' 'Another local-save operation holds the repository lock.' }
}

function Invoke-TestPause {
    param([string]$Point)
    if ([Environment]::GetEnvironmentVariable('NPS_LOCAL_SAVE_TEST_MODE', 'Process') -cne '1' -or
        [Environment]::GetEnvironmentVariable('NPS_LOCAL_SAVE_TEST_PAUSE_AT', 'Process') -cne $Point) { return }
    $readyPath = [Environment]::GetEnvironmentVariable('NPS_LOCAL_SAVE_TEST_READY_PATH', 'Process')
    $continuePath = [Environment]::GetEnvironmentVariable('NPS_LOCAL_SAVE_TEST_CONTINUE_PATH', 'Process')
    if (-not [IO.Path]::IsPathRooted($readyPath) -or -not [IO.Path]::IsPathRooted($continuePath)) {
        Stop-LocalSave 'test_control_invalid' 'Local-save test synchronization paths are invalid.'
    }
    [IO.File]::WriteAllText($readyPath, $Point, [Text.UTF8Encoding]::new($false))
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while (-not (Test-Path -LiteralPath $continuePath -PathType Leaf)) {
        if ([DateTime]::UtcNow -ge $deadline) { Stop-LocalSave 'test_control_timeout' 'Local-save test synchronization timed out.' }
        Start-Sleep -Milliseconds 50
    }
}

function Invoke-TestFailure {
    param([string]$Point)
    if ([Environment]::GetEnvironmentVariable('NPS_LOCAL_SAVE_TEST_MODE', 'Process') -ceq '1' -and
        [Environment]::GetEnvironmentVariable('NPS_LOCAL_SAVE_TEST_FAIL_AT', 'Process') -ceq $Point) {
        Stop-LocalSave 'injected_prepare_failure' 'An injected Prepare failure occurred.'
    }
}

function Get-GitPath {
    param([string]$Name)
    $result = Invoke-GitChecked -Arguments @('rev-parse', '--git-path', $Name) -Description 'resolving Git operation state'
    $path = $result.StdOut.Trim()
    if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path $script:RepositoryRoot $path }
    return Get-NormalizedFullPath $path
}

function Assert-NoActiveGitOperation {
    $markers = [ordered]@{
        'merge' = 'MERGE_HEAD'
        'rebase-merge' = 'rebase-merge'
        'rebase-apply' = 'rebase-apply'
        'cherry-pick' = 'CHERRY_PICK_HEAD'
        'revert' = 'REVERT_HEAD'
        'bisect-log' = 'BISECT_LOG'
        'bisect-start' = 'BISECT_START'
        'sequencer' = 'sequencer'
    }
    $active = New-Object Collections.Generic.List[object]
    foreach ($entry in $markers.GetEnumerator()) {
        if (Test-Path -LiteralPath (Get-GitPath ([string]$entry.Value))) {
            $active.Add([ordered]@{ rule = 'active-git-operation'; operation = [string]$entry.Key })
        }
    }
    if ($active.Count -gt 0) { Stop-LocalSave 'active_git_operation' 'An active Git operation blocks local saving.' $active.ToArray() }
    $unmerged = Invoke-GitChecked -Arguments @('ls-files', '-u', '-z') -Description 'checking for unmerged index entries'
    if (-not [string]::IsNullOrEmpty($unmerged.StdOut)) {
        Stop-LocalSave 'unmerged_index' 'Unmerged index entries block local saving.'
    }
}

function Get-BranchState {
    $branchResult = Invoke-Git -Arguments @('symbolic-ref', '--quiet', '--short', 'HEAD')
    if ($branchResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($branchResult.StdOut)) {
        Stop-LocalSave 'detached_head' 'Local saving requires a named branch.'
    }
    $headResult = Invoke-Git -Arguments @('rev-parse', '--verify', 'HEAD')
    return [pscustomobject]@{
        Branch = $branchResult.StdOut.Trim()
        Unborn = $headResult.ExitCode -ne 0
        Head = if ($headResult.ExitCode -eq 0) { $headResult.StdOut.Trim().ToLowerInvariant() } else { $null }
    }
}

function Normalize-ObjectivePaths {
    if ($script:ObjectivePathInput.Count -eq 0) { Stop-LocalSave 'invalid_objective_path' 'At least one objective path is required.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $normalized = New-Object Collections.Generic.List[string]
    foreach ($raw in @($script:ObjectivePathInput)) {
        $value = [string]$raw
        if ([string]::IsNullOrWhiteSpace($value) -or [IO.Path]::IsPathRooted($value) -or $value -match '^[A-Za-z]:' -or
            $value.Contains('\') -or $value.Contains(':') -or $value.IndexOfAny([char[]]@([char]0, [char]10, [char]13)) -ge 0) {
            Stop-LocalSave 'invalid_objective_path' 'An objective path uses an unsupported or non-relative form.'
        }
        $segments = @($value.Split('/'))
        if ($segments.Count -eq 0 -or @($segments | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
            Stop-LocalSave 'path_escape' 'An objective path is empty, non-normalized, or escaping.'
        }
        if (@($segments | Where-Object { $_ -ieq '.git' }).Count -gt 0) {
            Stop-LocalSave 'git_metadata_path' 'Git metadata paths cannot be selected for local saving.'
        }
        if (-not $seen.Add($value)) { Stop-LocalSave 'case_collision' 'Objective paths contain a duplicate or case collision.' }
        $normalized.Add($value)
    }
    return @($normalized.ToArray() | Sort-Object)
}

function Resolve-ObjectivePathInput {
    if (-not [string]::IsNullOrWhiteSpace($ObjectivePathsJson)) {
        if (@($ObjectivePath).Count -gt 0) { Stop-LocalSave 'invalid_objective_path' 'Use either ObjectivePath or ObjectivePathsJson, not both.' }
        if (-not $ObjectivePathsJson.TrimStart().StartsWith('[', [StringComparison]::Ordinal)) {
            Stop-LocalSave 'invalid_objective_path' 'ObjectivePathsJson must be a JSON array of strings.'
        }
        try { $parsed = ConvertFrom-Json -InputObject $ObjectivePathsJson -NoEnumerate }
        catch { Stop-LocalSave 'invalid_objective_path' 'ObjectivePathsJson is not valid JSON.' }
        $values = @($parsed)
        foreach ($value in $values) {
            if ($value -isnot [string]) { Stop-LocalSave 'invalid_objective_path' 'ObjectivePathsJson must contain only strings.' }
        }
        return [string[]]$values
    }
    return [string[]]@($ObjectivePath)
}

function Test-PathInScope {
    param([string]$Path, [string[]]$Objectives)
    foreach ($objective in $Objectives) {
        if ([string]::Equals($Path, $objective, $script:PathComparison) -or
            $Path.StartsWith($objective + '/', $script:PathComparison)) { return $true }
    }
    return $false
}

function Assert-ObjectivePathsResolvable {
    param([string[]]$Objectives)
    $alreadyStaged = @(Get-StagedPaths)
    foreach ($objective in $Objectives) {
        $nativePath = Join-Path $script:RepositoryRoot $objective
        if (Test-Path -LiteralPath $nativePath) { continue }
        if (@($alreadyStaged | Where-Object {
            [string]::Equals($_, $objective, $script:PathComparison) -or $_.StartsWith($objective + '/', $script:PathComparison)
        }).Count -gt 0) { continue }
        $tracked = Invoke-Git -Arguments @('--literal-pathspecs', 'ls-files', '-z', '--', $objective)
        if ($tracked.ExitCode -ne 0 -or [string]::IsNullOrEmpty($tracked.StdOut)) {
            Stop-LocalSave 'invalid_objective_path' "An objective path does not exist and has no tracked deletion: $objective"
        }
    }
}

function Get-StageableObjectivePaths {
    param([string[]]$Objectives)
    $stageable = New-Object Collections.Generic.List[string]
    foreach ($objective in $Objectives) {
        if (Test-Path -LiteralPath (Join-Path $script:RepositoryRoot $objective)) {
            $stageable.Add($objective)
            continue
        }
        $tracked = Invoke-Git -Arguments @('--literal-pathspecs', 'ls-files', '-z', '--', $objective)
        if ($tracked.ExitCode -eq 0 -and -not [string]::IsNullOrEmpty($tracked.StdOut)) { $stageable.Add($objective) }
    }
    return $stageable.ToArray()
}

function Assert-NoIntentToAdd {
    $result = Invoke-GitChecked -Arguments @('ls-files', '--debug') -Description 'checking intent-to-add entries'
    $currentPath = $null
    foreach ($line in @($result.StdOut -split "`r?`n")) {
        if ($line -notmatch '^\s') { $currentPath = $line; continue }
        if ($line -match '\bflags:\s*(?<flags>[0-9A-Fa-f]+)\s*$') {
            $flags = [Convert]::ToInt64($Matches.flags, 16)
            if (($flags -band 0x20000000) -ne 0) {
                Stop-LocalSave 'intent_to_add' 'Intent-to-add index entries are not supported.' @([ordered]@{ rule = 'intent-to-add'; path = $currentPath })
            }
        }
    }
}

function Get-SubmoduleRoots {
    $result = Invoke-GitChecked -Arguments @('ls-files', '--stage', '-z') -Description 'checking submodule roots'
    $roots = New-Object Collections.Generic.List[string]
    foreach ($entry in @(Split-NulText $result.StdOut)) {
        if ($entry -match '^160000 [0-9a-f]+ \d\t(?<path>.*)$') { $roots.Add([string]$Matches.path) }
    }
    return $roots.ToArray()
}

function Assert-NoSubmoduleScope {
    param([string[]]$Objectives)
    foreach ($submodule in @(Get-SubmoduleRoots)) {
        foreach ($objective in $Objectives) {
            if ([string]::Equals($submodule, $objective, $script:PathComparison) -or
                $submodule.StartsWith($objective + '/', $script:PathComparison) -or
                $objective.StartsWith($submodule + '/', $script:PathComparison)) {
                Stop-LocalSave 'submodule_root' 'Submodule roots are outside the supported local-save scope.' @([ordered]@{ rule = 'submodule-root'; path = $submodule })
            }
        }
    }
}

function Get-StagedPaths {
    $result = Invoke-GitChecked -Arguments @('diff', '--cached', '--name-only', '-z', '--no-renames', '--') -Description 'reading staged paths'
    return @((Split-NulText $result.StdOut) | Sort-Object -Unique)
}

function Get-IndexSnapshot {
    $indexPath = Join-Path $script:GitDirectory 'index'
    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
        return [pscustomobject]@{ Exists = $false; Hash = $null; Length = 0L; Bytes = $null }
    }
    $bytes = [IO.File]::ReadAllBytes($indexPath)
    return [pscustomobject]@{
        Exists = $true
        Hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        Length = [long]$bytes.Length
        Bytes = $bytes
    }
}

function Test-IndexSnapshotMatch {
    param([object]$Left, [object]$Right)
    if ($null -eq $Left -or $null -eq $Right -or $Left.Exists -ne $Right.Exists) { return $false }
    if (-not $Left.Exists) { return $true }
    return $Left.Length -eq $Right.Length -and [string]$Left.Hash -ceq [string]$Right.Hash
}

function Get-SafeStagedPaths {
    try { return @(Get-StagedPaths) } catch { return @() }
}

function Get-PrepareCleanupStateIssue {
    param([object]$ExpectedState, [object]$ExpectedIndex)
    try {
        Assert-NoActiveGitOperation
        $state = Get-BranchState
        if ($state.Branch -cne $ExpectedState.Branch) { return 'branch-changed' }
        if ($state.Unborn -ne $ExpectedState.Unborn -or
            (-not $state.Unborn -and $state.Head -cne $ExpectedState.Head)) { return 'head-changed' }
        $index = Get-IndexSnapshot
        if (-not (Test-IndexSnapshotMatch $index $ExpectedIndex)) { return 'index-changed' }
        return $null
    }
    catch { return 'repository-state-unavailable' }
}

function Restore-PrepareIndex {
    $cleanup = [ordered]@{
        status = 'not_safe'
        index_changed_by_helper = $true
        index_clean_afterward = $false
        reason = $null
        staged_paths = [object[]]@(Get-SafeStagedPaths)
    }
    $issue = Get-PrepareCleanupStateIssue $script:PrepareExpectedState $script:PrepareStagedIndex
    if ($issue) {
        $cleanup.reason = $issue
        return $cleanup
    }

    $indexPath = Join-Path $script:GitDirectory 'index'
    $indexLockPath = Join-Path $script:GitDirectory 'index.lock'
    $indexLock = $null
    $ownsIndexLock = $false
    try {
        try {
            $indexLock = [IO.FileStream]::new(
                $indexLockPath,
                [IO.FileMode]::CreateNew,
                [IO.FileAccess]::Write,
                [IO.FileShare]::None
            )
            $ownsIndexLock = $true
        }
        catch [IO.IOException] {
            $cleanup.reason = 'index-lock-unavailable'
            return $cleanup
        }

        $issue = Get-PrepareCleanupStateIssue $script:PrepareExpectedState $script:PrepareStagedIndex
        if ($issue) {
            $cleanup.reason = $issue
            return $cleanup
        }
        if ([Environment]::GetEnvironmentVariable('NPS_LOCAL_SAVE_TEST_MODE', 'Process') -ceq '1' -and
            [Environment]::GetEnvironmentVariable('NPS_LOCAL_SAVE_TEST_FAIL_CLEANUP', 'Process') -ceq '1') {
            throw 'Injected cleanup failure.'
        }

        if ($script:PrepareInitialIndex.Exists) {
            $indexLock.Write($script:PrepareInitialIndex.Bytes, 0, $script:PrepareInitialIndex.Bytes.Length)
            $indexLock.Flush($true)
            $indexLock.Dispose()
            $indexLock = $null
            [IO.File]::Move($indexLockPath, $indexPath, $true)
            $ownsIndexLock = $false
        }
        else {
            $indexLock.Dispose()
            $indexLock = $null
            if (Test-Path -LiteralPath $indexPath -PathType Leaf) { Remove-Item -LiteralPath $indexPath -Force }
            Remove-Item -LiteralPath $indexLockPath -Force
            $ownsIndexLock = $false
        }

        $restoredIndex = Get-IndexSnapshot
        $remainingStaged = @(Get-StagedPaths)
        if (-not (Test-IndexSnapshotMatch $restoredIndex $script:PrepareInitialIndex) -or $remainingStaged.Count -ne 0) {
            throw 'The restored index did not match the initial clean index.'
        }
        $cleanup.status = 'restored'
        $cleanup.index_clean_afterward = $true
        $cleanup.reason = $null
        $cleanup.staged_paths = @()
        return $cleanup
    }
    catch {
        $cleanup.status = 'failed'
        $cleanup.reason = 'restore-failed'
        $cleanup.staged_paths = [object[]]@(Get-SafeStagedPaths)
        try {
            $cleanup.index_clean_afterward = @(Get-StagedPaths).Count -eq 0
        }
        catch { $cleanup.index_clean_afterward = $false }
        return $cleanup
    }
    finally {
        if ($null -ne $indexLock) { $indexLock.Dispose() }
        if ($ownsIndexLock -and (Test-Path -LiteralPath $indexLockPath -PathType Leaf)) {
            Remove-Item -LiteralPath $indexLockPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Assert-StagedScope {
    param([string[]]$StagedPaths, [string[]]$Objectives, [string]$Category = 'unrelated_staged_paths')
    $outside = @($StagedPaths | Where-Object { -not (Test-PathInScope $_ $Objectives) })
    if ($outside.Count -gt 0) {
        $blockers = @($outside | ForEach-Object { [ordered]@{ rule = 'staged-path-outside-objective'; path = $_ } })
        Stop-LocalSave $Category 'The index contains staged paths outside the objective scope.' $blockers
    }
}

function Get-StagedTree {
    $result = Invoke-GitChecked -Arguments @('write-tree') -Description 'capturing the staged tree' -Category 'invalid_index'
    return $result.StdOut.Trim().ToLowerInvariant()
}

function Get-ChangeSummary {
    $result = Invoke-GitChecked -Arguments @('diff', '--cached', '--name-status', '-z', '--find-renames', '--') -Description 'summarizing staged changes'
    $tokens = @(Split-NulText $result.StdOut)
    $summary = New-Object Collections.Generic.List[object]
    $index = 0
    while ($index -lt $tokens.Count) {
        $status = [string]$tokens[$index++]
        if ($status -match '^(?<kind>[RC])(?<score>\d+)$') {
            if ($index + 1 -ge $tokens.Count) { Stop-LocalSave 'invalid_index' 'Git returned an incomplete rename/copy summary.' }
            $oldPath = [string]$tokens[$index++]
            $newPath = [string]$tokens[$index++]
            $summary.Add([ordered]@{
                type = if ($Matches.kind -eq 'R') { 'rename' } else { 'copy' }
                status = $status
                old_path = $oldPath
                path = $newPath
            })
            continue
        }
        if ($index -ge $tokens.Count) { Stop-LocalSave 'invalid_index' 'Git returned an incomplete change summary.' }
        $path = [string]$tokens[$index++]
        $type = switch -Regex ($status) {
            '^A' { 'addition'; break }
            '^M' { 'modification'; break }
            '^D' { 'deletion'; break }
            '^T' { 'type_change'; break }
            default { 'other' }
        }
        $summary.Add([ordered]@{ type = $type; status = $status; path = $path })
    }
    return $summary.ToArray()
}

function Get-TreeChangeSummary {
    param([string]$ExpectedTree, [string]$ActualTree)
    $result = Invoke-GitChecked -Arguments @('diff', '--name-status', '-z', '--find-renames', $ExpectedTree, $ActualTree, '--') -Description 'summarizing the committed tree difference'
    $tokens = @(Split-NulText $result.StdOut)
    $summary = New-Object Collections.Generic.List[object]
    $index = 0
    while ($index -lt $tokens.Count) {
        $status = [string]$tokens[$index++]
        if ($status -match '^(?<kind>[RC])(?<score>\d+)$') {
            if ($index + 1 -ge $tokens.Count) { Stop-LocalSave 'post_commit_verification_failed' 'Git returned an incomplete committed-tree rename summary.' @() 'indeterminate' }
            $oldPath = [string]$tokens[$index++]
            $newPath = [string]$tokens[$index++]
            $summary.Add([ordered]@{ type = if ($Matches.kind -eq 'R') { 'rename' } else { 'copy' }; status = $status; old_path = $oldPath; path = $newPath })
            continue
        }
        if ($index -ge $tokens.Count) { Stop-LocalSave 'post_commit_verification_failed' 'Git returned an incomplete committed-tree summary.' @() 'indeterminate' }
        $path = [string]$tokens[$index++]
        $type = switch -Regex ($status) {
            '^A' { 'addition'; break }
            '^M' { 'modification'; break }
            '^D' { 'deletion'; break }
            '^T' { 'type_change'; break }
            default { 'other' }
        }
        $summary.Add([ordered]@{ type = $type; status = $status; path = $path })
    }
    return $summary.ToArray()
}

function Test-SecretLikeValue {
    param([string]$Value)
    if ($Value.Length -lt 12 -or $Value -match '(?i)placeholder|example|sample|changeme|notasecret|redacted|dummy|\$\{|<[^>]+>') { return $false }
    return $Value -match '[A-Za-z]' -and $Value -match '\d' -and $Value -match '[^A-Za-z0-9]'
}

function Find-HighConfidenceCredentials {
    param([string]$Text, [string]$Location, [string]$Kind)
    $findings = New-Object Collections.Generic.List[object]
    $rules = [ordered]@{
        'private-key-material' = '-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY(?: BLOCK)?-----'
        'github-token' = '(?<![A-Za-z0-9_])(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,})(?![A-Za-z0-9_])'
        'aws-access-key' = '(?<![A-Z0-9])(?:AKIA|ASIA)[A-Z0-9]{16}(?![A-Z0-9])'
        'slack-token' = '(?<![A-Za-z0-9])xox[baprs]-[A-Za-z0-9-]{20,}(?![A-Za-z0-9])'
        'stripe-live-secret' = '(?<![A-Za-z0-9_])sk_live_[A-Za-z0-9]{16,}(?![A-Za-z0-9])'
        'openai-api-key' = '(?<![A-Za-z0-9_-])sk-(?:proj-)?[A-Za-z0-9_-]{20,}(?![A-Za-z0-9_-])'
        'google-api-key' = '(?<![A-Za-z0-9_-])AIza[0-9A-Za-z_-]{35}(?![A-Za-z0-9_-])'
    }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $lines = @($Text -split "`n", -1)
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index].TrimEnd("`r")
        foreach ($rule in $rules.GetEnumerator()) {
            if ($line -match [string]$rule.Value) {
                $key = "$($rule.Key)|$($index + 1)"
                if ($seen.Add($key)) { $findings.Add([ordered]@{ rule = [string]$rule.Key; location = $Location; kind = $Kind; line = $index + 1 }) }
            }
        }
        $assignmentPattern = '(?i)\b(?:password|passwd|pwd|secret|token|api[_-]?key|client[_-]?secret)\b\s*[:=]\s*["''](?<value>[^"''\r\n]{8,})["'']'
        foreach ($match in [Regex]::Matches($line, $assignmentPattern)) {
            if (Test-SecretLikeValue ([string]$match.Groups['value'].Value)) {
                $key = "quoted-secret-assignment|$($index + 1)"
                if ($seen.Add($key)) { $findings.Add([ordered]@{ rule = 'quoted-secret-assignment'; location = $Location; kind = $Kind; line = $index + 1 }) }
            }
        }
        foreach ($match in [Regex]::Matches($line, '(?i)\b(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis|amqps?|https?)://[^\s/:@]+:(?<value>[^\s@]+)@')) {
            if (Test-SecretLikeValue ([string]$match.Groups['value'].Value)) {
                $key = "credential-url|$($index + 1)"
                if ($seen.Add($key)) { $findings.Add([ordered]@{ rule = 'credential-url'; location = $Location; kind = $Kind; line = $index + 1 }) }
            }
        }
        if ($line -match '(?i)\b(?:server|data source|host)\s*=' -and
            $line -match '(?i)\b(?:password|pwd)\s*=\s*(?<value>[^;\r\n]{8,})') {
            if (Test-SecretLikeValue ([string]$Matches.value)) {
                $key = "credential-connection-string|$($index + 1)"
                if ($seen.Add($key)) { $findings.Add([ordered]@{ rule = 'credential-connection-string'; location = $Location; kind = $Kind; line = $index + 1 }) }
            }
        }
    }
    return $findings.ToArray()
}

function Get-IndexBlobInfo {
    param([string]$Path)
    $result = Invoke-GitChecked -Arguments @('--literal-pathspecs', 'ls-files', '--stage', '-z', '--', $Path) -Description 'resolving a staged blob'
    $entries = @(Split-NulText $result.StdOut)
    if ($entries.Count -ne 1 -or $entries[0] -notmatch '^(?<mode>\d+) (?<hash>[0-9a-f]+) 0\t') {
        Stop-LocalSave 'invalid_index' 'A staged path could not be resolved unambiguously.'
    }
    $hash = [string]$Matches.hash
    $sizeResult = Invoke-GitChecked -Arguments @('cat-file', '-s', $hash) -Description 'reading a staged blob size'
    return [pscustomobject]@{ Hash = $hash; Mode = [string]$Matches.mode; Size = [long]$sizeResult.StdOut.Trim() }
}

function Get-RiskyFileWarnings {
    param([string]$Path, [long]$Size, [bool]$Binary)
    $warnings = New-Object Collections.Generic.List[object]
    $name = [IO.Path]::GetFileName($Path)
    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    $category = if ($name -ieq '.env' -or $name.StartsWith('.env.', [StringComparison]::OrdinalIgnoreCase)) { 'environment-file' }
        elseif ($extension -in @('.zip', '.tar', '.gz', '.tgz', '.7z', '.rar')) { 'archive' }
        elseif ($extension -in @('.exe', '.dll', '.msi', '.so', '.dylib', '.com')) { 'executable' }
        elseif ($extension -in @('.sql', '.sqlite', '.sqlite3', '.db', '.dump', '.bak')) { 'database-export' }
        elseif ($extension -in @('.pfx', '.p12', '.jks', '.keystore', '.pem', '.key', '.crt', '.cer')) { 'credential-or-certificate-file' }
        else { $null }
    if ($category) { $warnings.Add([ordered]@{ rule = 'risky-file'; path = $Path; category = $category }) }
    if ($Binary -and $Size -ge 1MB) { $warnings.Add([ordered]@{ rule = 'large-binary'; path = $Path; size_bytes = $Size }) }
    return $warnings.ToArray()
}

function Inspect-StagedContent {
    param([object[]]$Summary, [string]$Message)
    $warnings = New-Object Collections.Generic.List[object]
    $blockers = New-Object Collections.Generic.List[object]
    $scanPaths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($change in $Summary) {
        if ([string]$change.type -in @('addition', 'modification', 'rename', 'copy', 'type_change')) { [void]$scanPaths.Add([string]$change.path) }
    }
    foreach ($path in @($scanPaths | Sort-Object)) {
        $blob = Get-IndexBlobInfo $path
        if ($blob.Mode -eq '160000') { Stop-LocalSave 'submodule_root' 'Submodule entries are outside the supported local-save scope.' }
        $text = ''
        $binary = $false
        if ($blob.Size -le $script:ContentScanLimitBytes) {
            $content = Invoke-GitChecked -Arguments @('cat-file', 'blob', $blob.Hash) -Description 'scanning staged content'
            $text = [string]$content.StdOut
            $binary = $text.IndexOf([char]0) -ge 0
            if (-not $binary) {
                foreach ($finding in @(Find-HighConfidenceCredentials $text $path 'file')) { $blockers.Add($finding) }
            }
        }
        else {
            $warnings.Add([ordered]@{
                rule = 'content-scan-skipped'
                reason = 'size-limit'
                path = $path
                size_bytes = $blob.Size
                scan_limit_bytes = $script:ContentScanLimitBytes
            })
        }
        foreach ($warning in @(Get-RiskyFileWarnings $path $blob.Size $binary)) { $warnings.Add($warning) }
    }
    foreach ($finding in @(Find-HighConfidenceCredentials $Message 'commit_message' 'message')) { $blockers.Add($finding) }
    return [pscustomobject]@{ Warnings = $warnings.ToArray(); Blockers = $blockers.ToArray() }
}

function Normalize-CommitMessage {
    param([string]$Value)
    return (($Value -replace "`r`n", "`n") -replace "`r", "`n").TrimEnd("`n")
}

function Assert-StateMatches {
    param([string]$Branch, [AllowNull()][string]$Head, [bool]$Unborn)
    Assert-NoActiveGitOperation
    $state = Get-BranchState
    if ($state.Branch -cne $Branch) { Stop-LocalSave 'branch_changed' 'The current branch changed.' }
    if ($state.Unborn -ne $Unborn -or (-not $Unborn -and $state.Head -cne $Head)) {
        Stop-LocalSave 'head_changed' 'HEAD changed.'
    }
    return $state
}

function Invoke-Prepare {
    $objectives = Normalize-ObjectivePaths
    Assert-NoActiveGitOperation
    $state = Get-BranchState
    $script:Result.branch = $state.Branch
    $script:Result.expected_head = $state.Head
    $script:Result.previous_head = $state.Head
    Assert-NoIntentToAdd
    Assert-ObjectivePathsResolvable $objectives
    Assert-NoSubmoduleScope $objectives

    $preStaged = @(Get-StagedPaths)
    if ($preStaged.Count -gt 0) {
        $blockers = @($preStaged | ForEach-Object { [ordered]@{ rule = 'preexisting-staged-change'; path = $_ } })
        Stop-LocalSave 'preexisting_staged_changes' 'Prepare requires a clean Git index.' $blockers
    }
    $script:PrepareExpectedState = $state
    $script:PrepareInitialIndex = Get-IndexSnapshot
    $stageable = @(Get-StageableObjectivePaths $objectives)
    if ($stageable.Count -gt 0) {
        $stageArguments = @('--literal-pathspecs', 'add', '-A', '--') + @($stageable)
        $script:PrepareIndexPhase = 'post_stage_snapshot_pending'
        Invoke-GitChecked -Arguments $stageArguments -Description 'staging objective paths' -Category 'staging_failed' | Out-Null
        Invoke-TestFailure 'first-post-stage-index-snapshot'
    }
    $script:PrepareStagedIndex = Get-IndexSnapshot
    $script:PrepareIndexPhase = 'post_stage_snapshot_valid'
    $indexChangedByHelper = -not (Test-IndexSnapshotMatch $script:PrepareInitialIndex $script:PrepareStagedIndex)
    $script:Result.prepare_cleanup.index_changed_by_helper = $indexChangedByHelper
    if ($indexChangedByHelper) { $script:Result.prepare_cleanup.index_clean_afterward = $false }
    Invoke-TestPause 'prepare-after-staging'
    Invoke-TestFailure 'after-staging'

    $staged = @(Get-StagedPaths)
    Assert-StagedScope $staged $objectives 'staged_scope_changed'
    if ($staged.Count -eq 0) { Stop-LocalSave 'empty_staged_tree' 'The objective produced no staged changes.' }
    $tree = Get-StagedTree
    $summary = @(Get-ChangeSummary)
    $inspection = Inspect-StagedContent $summary (Normalize-CommitMessage $CommitMessage)
    $script:Result.paths = [object[]]$staged
    $script:Result.change_summary = [object[]]$summary
    $script:Result.warnings = [object[]]$inspection.Warnings
    $script:Result.expected_tree = $tree
    $script:Result.actual_tree = $tree

    Invoke-TestPause 'prepare-before-final-check'
    Assert-StateMatches $state.Branch $state.Head $state.Unborn | Out-Null
    $finalPaths = @(Get-StagedPaths)
    Assert-StagedScope $finalPaths $objectives 'staged_scope_changed'
    $finalTree = Get-StagedTree
    if ($finalTree -cne $tree) { Stop-LocalSave 'tree_changed' 'The staged tree changed before Prepare completed.' }
    if (($finalPaths -join "`n") -cne ($staged -join "`n")) { Stop-LocalSave 'staged_scope_changed' 'The staged path set changed before Prepare completed.' }
    # Read-only Git checks can refresh index metadata without changing the staged tree.
    $script:PrepareStagedIndex = Get-IndexSnapshot
    if (@($inspection.Blockers).Count -gt 0) {
        Stop-LocalSave 'credential_detected' 'High-confidence credential material blocks local saving.' @($inspection.Blockers)
    }
    $script:Result.outcome = 'ready'
}

function Test-HashValue {
    param([AllowNull()][string]$Value)
    return -not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$'
}

function Get-CommitFailureCategory {
    param([string]$StandardError)
    if ($StandardError -match '(?i)gpg failed to sign|failed to write commit object|signing failed|could not sign') { return 'signing_failed' }
    $signing = Invoke-Git -Arguments @('config', '--bool', '--get', 'commit.gpgSign')
    if ($signing.ExitCode -eq 0 -and $signing.StdOut.Trim() -ceq 'true') { return 'signing_failed' }
    foreach ($hook in @('pre-commit', 'prepare-commit-msg', 'commit-msg')) {
        if (Test-Path -LiteralPath (Get-GitPath "hooks/$hook") -PathType Leaf) { return 'hook_failed' }
    }
    return 'commit_failed'
}

function Invoke-Commit {
    $objectives = Normalize-ObjectivePaths
    if ([string]::IsNullOrWhiteSpace($ExpectedBranch)) { Stop-LocalSave 'invalid_expectation' 'Commit requires an expected branch.' }
    if (-not (Test-HashValue $ExpectedTree)) { Stop-LocalSave 'invalid_expectation' 'Commit requires a valid expected tree.' }
    if ($ExpectedUnborn) {
        if (-not [string]::IsNullOrWhiteSpace($ExpectedHead)) { Stop-LocalSave 'invalid_expectation' 'An unborn expectation cannot include an expected HEAD.' }
    } elseif (-not (Test-HashValue $ExpectedHead)) { Stop-LocalSave 'invalid_expectation' 'Commit requires a valid expected HEAD or explicit unborn state.' }

    $normalizedMessage = Normalize-CommitMessage $CommitMessage
    if ([string]::IsNullOrWhiteSpace($normalizedMessage)) { Stop-LocalSave 'invalid_commit_message' 'The commit message must not be empty.' }
    $expectedHeadNormalized = if ($ExpectedUnborn) { $null } else { $ExpectedHead.ToLowerInvariant() }
    $expectedTreeNormalized = $ExpectedTree.ToLowerInvariant()
    $script:Result.branch = $ExpectedBranch
    $script:Result.expected_head = $expectedHeadNormalized
    $script:Result.previous_head = $expectedHeadNormalized
    $script:Result.expected_tree = $expectedTreeNormalized
    Assert-NoIntentToAdd
    Assert-NoSubmoduleScope $objectives
    Assert-StateMatches $ExpectedBranch $expectedHeadNormalized $ExpectedUnborn.IsPresent | Out-Null
    $staged = @(Get-StagedPaths)
    Assert-StagedScope $staged $objectives 'staged_scope_changed'
    if ($staged.Count -eq 0) { Stop-LocalSave 'empty_staged_tree' 'No staged changes remain for Commit.' }
    $tree = Get-StagedTree
    $script:Result.actual_tree = $tree
    $script:Result.paths = [object[]]$staged
    if ($tree -cne $expectedTreeNormalized) { Stop-LocalSave 'tree_changed' 'The staged tree no longer matches Prepare.' }
    $summary = @(Get-ChangeSummary)
    $script:Result.change_summary = [object[]]$summary
    $inspection = Inspect-StagedContent $summary $normalizedMessage
    $script:Result.warnings = [object[]]$inspection.Warnings
    if (@($inspection.Blockers).Count -gt 0) {
        Stop-LocalSave 'credential_detected' 'High-confidence credential material blocks local saving.' @($inspection.Blockers)
    }
    $expectedMessageHash = Get-StringSha256 $normalizedMessage
    $script:Result.commit_message_verification.expected_sha256 = $expectedMessageHash
    $script:Result.commit_message_verification.expected_characters = $normalizedMessage.Length

    Invoke-TestPause 'commit-before-git'
    Assert-StateMatches $ExpectedBranch $expectedHeadNormalized $ExpectedUnborn.IsPresent | Out-Null
    $finalPaths = @(Get-StagedPaths)
    Assert-StagedScope $finalPaths $objectives 'staged_scope_changed'
    if ((Get-StagedTree) -cne $expectedTreeNormalized) { Stop-LocalSave 'tree_changed' 'The staged tree changed immediately before Commit.' }

    $messagePath = Join-Path ([IO.Path]::GetTempPath()) ('codex-local-save-message-' + [Guid]::NewGuid().ToString('N') + '.txt')
    try {
        [IO.File]::WriteAllText($messagePath, $CommitMessage, [Text.UTF8Encoding]::new($false))
        $commitResult = Invoke-Git -Arguments @('commit', '-F', $messagePath) -TimeoutSeconds 180
    }
    finally {
        if (Test-Path -LiteralPath $messagePath -PathType Leaf) { Remove-Item -LiteralPath $messagePath -Force }
    }

    $after = Get-BranchState
    $advanced = -not $after.Unborn -and ($ExpectedUnborn -or $after.Head -cne $expectedHeadNormalized)
    $script:Result.head_advanced = $advanced
    if (-not $advanced) {
        $category = Get-CommitFailureCategory $commitResult.StdErr
        Stop-LocalSave $category 'Git did not create a commit.'
    }

    $script:Result.commit = $after.Head
    try {
        $identity = Invoke-GitChecked -Arguments @('rev-list', '--parents', '-n', '1', $after.Head) -Description 'verifying the resulting commit'
        $parts = @($identity.StdOut.Trim().Split(' ', [StringSplitOptions]::RemoveEmptyEntries))
        $parentMatches = if ($ExpectedUnborn) { $parts.Count -eq 1 } else { $parts.Count -eq 2 -and $parts[1] -ceq $expectedHeadNormalized }
        $actualTree = (Invoke-GitChecked -Arguments @('show', '-s', '--format=%T', $after.Head) -Description 'verifying the resulting tree').StdOut.Trim().ToLowerInvariant()
        $actualMessage = Normalize-CommitMessage ((Invoke-GitChecked -Arguments @('show', '-s', '--format=%B', $after.Head) -Description 'verifying the resulting message').StdOut)
        $script:Result.actual_tree = $actualTree
        $actualMessageFindings = @(Find-HighConfidenceCredentials $actualMessage 'commit-message' 'message')
        $actualMessageHash = Get-StringSha256 $actualMessage
        $script:Result.commit_message_verification.actual_sha256 = $actualMessageHash
        $script:Result.commit_message_verification.actual_characters = $actualMessage.Length
        $script:Result.commit_message_verification.sensitive_content_detected = $actualMessageFindings.Count -gt 0
        $script:Result.commit_message_verification.status = if ($actualMessageFindings.Count -gt 0) { 'changed_with_sensitive_content' }
            elseif ($actualMessage -ceq $normalizedMessage) { 'match' }
            else { 'changed' }
        if (-not $parentMatches) {
            Stop-LocalSave 'post_commit_parent_mismatch' 'HEAD advanced, but the resulting parent could not be attributed safely.' @() 'indeterminate'
        }
        $postWarnings = New-Object Collections.Generic.List[object]
        foreach ($warning in @($script:Result.warnings)) { $postWarnings.Add($warning) }
        if ($actualTree -cne $expectedTreeNormalized) {
            $treeChanges = @(Get-TreeChangeSummary $expectedTreeNormalized $actualTree)
            $postWarnings.Add([ordered]@{ rule = 'commit-tree-changed'; expected_tree = $expectedTreeNormalized; actual_tree = $actualTree; changes = [object[]]$treeChanges })
            $outsidePaths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            foreach ($change in $treeChanges) {
                foreach ($path in @([string]$change.path, [string]$change.old_path)) {
                    if (-not [string]::IsNullOrWhiteSpace($path) -and -not (Test-PathInScope $path $objectives)) { [void]$outsidePaths.Add($path) }
                }
            }
            if ($outsidePaths.Count -gt 0) {
                $postWarnings.Add([ordered]@{ rule = 'commit-scope-changed'; paths = [object[]]@($outsidePaths | Sort-Object) })
            }
        }
        if ($actualMessage -cne $normalizedMessage) {
            $postWarnings.Add([ordered]@{
                rule = 'commit-message-changed'
                expected_sha256 = $expectedMessageHash
                actual_sha256 = $actualMessageHash
                expected_characters = $normalizedMessage.Length
                actual_characters = $actualMessage.Length
                sensitive_content_detected = $actualMessageFindings.Count -gt 0
            })
        }
        if ($commitResult.ExitCode -ne 0) { $postWarnings.Add([ordered]@{ rule = 'git-commit-nonzero'; exit_code = $commitResult.ExitCode }) }
        $script:Result.warnings = $postWarnings.ToArray()
        $script:Result.outcome = if ($postWarnings.Count -gt 0) { 'committed_with_warning' } else { 'committed' }
    }
    catch {
        if ($_.Exception.Data.Contains('local_save_outcome')) { throw }
        Stop-LocalSave 'post_commit_verification_failed' 'HEAD advanced, but post-commit verification failed.' @() 'indeterminate'
    }
}

$exitCode = 0
try {
    if ($PSVersionTable.PSEdition -cne 'Core' -or $PSVersionTable.PSVersion -lt [Version]'7.6.0') {
        Stop-LocalSave 'unsupported_runtime' 'PowerShell 7.6 or later through pwsh is required.'
    }
    $gitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $gitCommand) { Stop-LocalSave 'git_unavailable' 'Git is required for local saving.' }
    $script:GitExecutable = $gitCommand.Source
    $normalizedMessage = Normalize-CommitMessage $CommitMessage
    if ([string]::IsNullOrWhiteSpace($normalizedMessage)) { Stop-LocalSave 'invalid_commit_message' 'The commit message must not be empty.' }
    $script:ObjectivePathInput = @(Resolve-ObjectivePathInput)
    $script:RepositoryRoot = Resolve-RepositoryRoot
    $script:Result.repository = $script:RepositoryRoot
    Enter-LocalSaveLock
    Invoke-TestPause 'after-lock'
    if ($Operation -ceq 'Prepare') { Invoke-Prepare } else { Invoke-Commit }
}
catch {
    $category = if ($_.Exception.Data.Contains('local_save_category')) { [string]$_.Exception.Data['local_save_category'] } else { 'internal_error' }
    $outcome = if ($_.Exception.Data.Contains('local_save_outcome')) { [string]$_.Exception.Data['local_save_outcome'] } else { 'failed_before_commit' }
    $blockers = @()
    if ($_.Exception.Data.Contains('local_save_blockers')) {
        $blockers = @($_.Exception.Data['local_save_blockers'] | Where-Object { $null -ne $_ })
    }
    if ($Operation -ceq 'Prepare' -and $script:PrepareIndexPhase -ceq 'post_stage_snapshot_pending') {
        $safeStagedPaths = [object[]]@(Get-SafeStagedPaths)
        $script:Result.prepare_cleanup = [ordered]@{
            status = 'not_safe'
            index_changed_by_helper = $null
            index_clean_afterward = $null
            reason = 'post_stage_snapshot_unavailable'
            staged_paths = $safeStagedPaths
        }
        $category = 'prepare_cleanup_required'
        $outcome = 'indeterminate'
        $cleanupBlockers = [Collections.Generic.List[object]]::new()
        $cleanupBlockers.Add([ordered]@{
            rule = 'prepare-cleanup-required'
            reason = 'post_stage_snapshot_unavailable'
        })
        foreach ($path in $safeStagedPaths) {
            $cleanupBlockers.Add([ordered]@{ rule = 'staged-path-requires-review'; path = [string]$path })
        }
        $blockers = @($cleanupBlockers)
    } elseif ($Operation -ceq 'Prepare' -and
        $script:PrepareIndexPhase -ceq 'post_stage_snapshot_valid' -and
        $script:Result.prepare_cleanup.index_changed_by_helper) {
        $cleanup = Restore-PrepareIndex
        $script:Result.prepare_cleanup = $cleanup
        if ([string]$cleanup.status -cne 'restored') {
            $category = 'prepare_cleanup_required'
            $outcome = 'indeterminate'
            $cleanupBlockers = New-Object Collections.Generic.List[object]
            $cleanupBlockers.Add([ordered]@{
                rule = 'prepare-cleanup-required'
                reason = [string]$cleanup.reason
            })
            foreach ($path in @($cleanup.staged_paths)) {
                $cleanupBlockers.Add([ordered]@{ rule = 'staged-path-requires-review'; path = [string]$path })
            }
            $blockers = @($cleanupBlockers.ToArray())
        }
    }
    $script:Result.outcome = $outcome
    $script:Result.failure_category = $category
    $script:Result.blockers = @($blockers)
    Write-Diagnostic "$category`: $($_.Exception.Message)"
    $exitCode = if ($outcome -ceq 'indeterminate') { 2 } else { 1 }
}
finally {
    if ($null -ne $script:LockStream) { $script:LockStream.Dispose() }
}

[Console]::Out.WriteLine((ConvertTo-ResultJson $script:Result))
exit $exitCode
