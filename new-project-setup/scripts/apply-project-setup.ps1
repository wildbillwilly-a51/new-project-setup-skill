#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$ProjectRoot = ".",
    [string]$Repository,
    [string]$RemoteName,
    [switch]$Check
)

$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7 or Windows PowerShell 5.1 is required.'
}
$WorkflowVersion = 6
$StateFormat = 2
$IsWindowsPlatform = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$PathComparison = if ($IsWindowsPlatform) {
    [StringComparison]::OrdinalIgnoreCase
} else {
    [StringComparison]::Ordinal
}
$resolvedRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$skillRoot = Split-Path -Parent $PSScriptRoot
$changes = New-Object Collections.Generic.List[string]
$managedHelperMarker = '# new-project-setup:managed-helper:v1'
$managedHelperOwnershipPolicy = 'first-line-marker-with-versioned-state-or-known-release-hash'
$releasedManagedHelperHashes = @{
    # Exact LF and CRLF identities from released v3 and v4 helpers.
    'github-sync.ps1' = @(
        'FE833DDDB28839D1EB9A337524245E2E640DDBAA6151268B768D7780E9B06E2E',
        '61C038964E49D95C4174B0D446FAAB3EFACFB33ADC8D5C142FC704F6FB379700',
        'A45C8209D821F4B2A4CF4628F7D72D2CA993C3B7F76F2E58D6BF6B5F7AADDEEE',
        '7743F465C1B2393817C63B4660FDA6A25D0EE1149A31E41B7F9DC7E09F47A36C'
    )
    # Version 2 shipped only github-backup; v3 and v4 shared its later identity.
    'github-backup.ps1' = @(
        '794B178920F327FB71C43043D351407C6CEE309DB41763479A82C2E7655C8A2B',
        'E0B2990E5F9BC95C90219F722BD4E6454D5DCA102AF11562EF8E9F32AD1D5CB7',
        'C66D2E0D35950309D4ED0FAF774FFC07C50BEB8637FFA5BC456A373415DFAA50',
        '1F3D75A15EACE0E5B21E7928810F492762581309FA2BF7449A42EFC7756DBC98'
    )
}
$supportedWorkflowVersions = @(2, 3, 4, 5, 6)
$testFaultPoints = @(
    'apply-after-stage',
    'apply-after-first-replace',
    'apply-before-final-validation'
)

function Get-NormalizedFullPath {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    if ($full.Length -gt $root.Length) {
        $full = $full.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    }
    return $full
}

function Get-DescendantPathPrefix {
    param([Parameter(Mandatory = $true)][string]$Path)
    $normalized = Get-NormalizedFullPath $Path
    $separator = [string][IO.Path]::DirectorySeparatorChar
    $alternate = [string][IO.Path]::AltDirectorySeparatorChar
    if ($normalized.EndsWith($separator) -or $normalized.EndsWith($alternate)) { return $normalized }
    return $normalized + $separator
}

function Test-SamePath {
    param([string]$Left, [string]$Right)
    $leftFull = Get-NormalizedFullPath $Left
    $rightFull = Get-NormalizedFullPath $Right
    if ([string]::Equals($leftFull, $rightFull, $PathComparison)) { return $true }
    if (-not $IsWindowsPlatform -and (Test-Path -LiteralPath $leftFull) -and (Test-Path -LiteralPath $rightFull)) {
        $testCommand = if (Test-Path -LiteralPath '/usr/bin/test' -PathType Leaf) { '/usr/bin/test' } else { '/bin/test' }
        & $testCommand $leftFull '-ef' $rightFull
        return $LASTEXITCODE -eq 0
    }
    return $false
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

function Get-StringSha256 {
    param([string]$Value)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Test-ExistingPathsSameIdentity {
    param([string]$Left, [string]$Right)
    if ($IsWindowsPlatform) { return [string]::Equals($Left, $Right, [StringComparison]::OrdinalIgnoreCase) }
    $testCommand = if (Test-Path -LiteralPath '/usr/bin/test' -PathType Leaf) { '/usr/bin/test' } else { '/bin/test' }
    & $testCommand $Left '-ef' $Right
    return $LASTEXITCODE -eq 0
}

function Test-FileSystemCaseInsensitive {
    param([string]$Path)
    $probe = Get-NormalizedFullPath $Path
    while (-not (Test-Path -LiteralPath $probe)) {
        $parent = Split-Path -Parent $probe
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -ceq $probe) { return $false }
        $probe = $parent
    }
    for ($index = $probe.Length - 1; $index -ge 0; $index--) {
        $character = $probe[$index]
        if (-not [char]::IsLetter($character)) { continue }
        $replacement = if ([char]::IsUpper($character)) { [char]::ToLowerInvariant($character) } else { [char]::ToUpperInvariant($character) }
        $variant = $probe.Substring(0, $index) + $replacement + $probe.Substring($index + 1)
        return (Test-Path -LiteralPath $variant) -and (Test-ExistingPathsSameIdentity $probe $variant)
    }
    return $false
}

function Get-OperationLockPath {
    param([string]$Path)
    $userProfile = if (-not $IsWindowsPlatform -and -not [string]::IsNullOrWhiteSpace([string]$env:HOME)) {
        [string]$env:HOME
    } else {
        [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    }
    if ([string]::IsNullOrWhiteSpace($userProfile)) { throw 'Unable to resolve the current user for workflow locking.' }
    $userKey = (Get-StringSha256 ((Get-NormalizedFullPath $userProfile).ToUpperInvariant())).Substring(0, 16)
    $lockRoot = Join-Path ([IO.Path]::GetTempPath()) "codex-new-project-setup-locks-$userKey"
    New-Item -ItemType Directory -Force -Path $lockRoot | Out-Null
    $lockRootItem = Get-Item -Force -LiteralPath $lockRoot
    if (-not $lockRootItem.PSIsContainer -or (Test-RedirectedLink $lockRootItem)) { throw 'Workflow lock root is not a safe directory.' }
    $identity = Get-NormalizedFullPath $Path
    if ($IsWindowsPlatform -or (Test-FileSystemCaseInsensitive $identity)) { $identity = $identity.ToUpperInvariant() }
    return Join-Path $lockRoot ((Get-StringSha256 $identity) + '.lock')
}

function Enter-OperationLocks {
    param([string[]]$Paths)

    $locks = New-Object Collections.Generic.List[object]
    $lockPaths = @($Paths | ForEach-Object { Get-OperationLockPath $_ } | Sort-Object -Unique)

    try {
        foreach ($lockPath in $lockPaths) {
            $deadline = [DateTime]::UtcNow.AddSeconds(30)
            $stream = $null
            while ($null -eq $stream -and [DateTime]::UtcNow -lt $deadline) {
                try {
                    $stream = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
                } catch [IO.IOException] {
                    Start-Sleep -Milliseconds 100
                }
            }
            if ($null -eq $stream) { throw "Timed out waiting for workflow operation lock: $lockPath" }
            if (Test-RedirectedLink (Get-Item -Force -LiteralPath $lockPath)) {
                $stream.Dispose()
                throw "Workflow operation lock is redirected: $lockPath"
            }
            $locks.Add($stream)
        }
        return $locks.ToArray()
    }
    catch {
        for ($index = $locks.Count - 1; $index -ge 0; $index--) {
            $locks[$index].Dispose()
        }
        throw
    }
}

function Exit-OperationLocks {
    param([object[]]$Locks)

    for ($index = $Locks.Count - 1; $index -ge 0; $index--) {
        $Locks[$index].Dispose()
    }
}

function Assert-TestFaultConfiguration {
    param([string[]]$AllowedPoints)

    $requested = [Environment]::GetEnvironmentVariable('NEW_PROJECT_SETUP_TEST_FAULT', 'Process')
    if (-not [string]::IsNullOrWhiteSpace($requested) -and -not ($AllowedPoints -contains $requested)) {
        throw "Unknown NEW_PROJECT_SETUP_TEST_FAULT point for apply: $requested"
    }
}

function Invoke-TestFault {
    param([string]$Point)

    if ([Environment]::GetEnvironmentVariable('NEW_PROJECT_SETUP_TEST_FAULT', 'Process') -eq $Point) {
        throw "Injected new-project-setup test fault: $Point"
    }
}

function Assert-TargetPath {
    param([string]$Path)

    $rootPath = Get-NormalizedFullPath $resolvedRoot
    $fullPath = Get-NormalizedFullPath $Path
    $rootPrefix = Get-DescendantPathPrefix $rootPath
    if (-not (Test-SamePath $rootPath $fullPath) -and
        -not $fullPath.StartsWith($rootPrefix, $PathComparison)) {
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

function Get-FileSnapshot {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Kind = 'missing'; Hash = $null }
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Expected file path is not a file: $Path"
    }
    return [pscustomobject]@{
        Kind = 'file'
        Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
    }
}

function Assert-FileSnapshot {
    param(
        [string]$Path,
        [object]$Snapshot,
        [string]$Description = 'Input'
    )

    $current = Get-FileSnapshot $Path
    if ($current.Kind -ne $Snapshot.Kind -or $current.Hash -ne $Snapshot.Hash) {
        throw "$Description changed during the locked operation: $Path"
    }
}

function Get-FirstLine {
    param([string]$Path)

    $reader = New-Object IO.StreamReader($Path, [Text.UTF8Encoding]::new($false), $true)
    try { return $reader.ReadLine() } finally { $reader.Dispose() }
}

function Test-ExactManagedHelperMarker {
    param([string]$Path)
    return [string]::Equals((Get-FirstLine $Path), $managedHelperMarker, [StringComparison]::Ordinal)
}

function Get-StateProperty {
    param([object]$State, [string]$Name)

    if ($null -eq $State) { return $null }
    $property = $State.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Read-WorkflowState {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Workflow state path is not a file: $Path"
    }
    $rawState = Get-Content -Raw -LiteralPath $Path
    if ([string]::IsNullOrWhiteSpace($rawState)) { throw "Workflow state is empty: $Path" }
    try { $state = $rawState | ConvertFrom-Json } catch { throw "Workflow state is invalid JSON: $Path" }
    if ($null -eq $state -or $state -is [Array]) { throw "Workflow state must be a JSON object: $Path" }

    $formatValue = Get-StateProperty $state 'format'
    $versionValue = Get-StateProperty $state 'workflow_version'
    if (-not ($formatValue -is [int] -or $formatValue -is [long]) -or
        -not ($versionValue -is [int] -or $versionValue -is [long])) {
        throw "Workflow state format and workflow_version must be integers: $Path"
    }
    $format = [int]$formatValue
    $version = [int]$versionValue
    if ($version -gt $WorkflowVersion) {
        throw "Workflow state uses future workflow version $version; helper supports v${WorkflowVersion}: $Path"
    }
    if (-not ($supportedWorkflowVersions -contains $version)) {
        throw "Workflow state uses unsupported workflow version ${version}: $Path"
    }
    $validPair = ($format -eq 1 -and $version -eq 2) -or
        ($format -eq 2 -and $version -ge 3 -and $version -le $WorkflowVersion)
    if (-not $validPair) {
        throw "Workflow state format $format is unsupported for workflow version ${version}: $Path"
    }
    return $state
}

function Test-StateOwnsManagedHelper {
    param(
        [object]$State,
        [string]$RelativePath,
        [string]$Hash
    )

    if ($null -eq $State) { return $false }
    $version = [int](Get-StateProperty $State 'workflow_version')
    $policy = [string](Get-StateProperty $State 'helper_ownership')
    if ($version -eq 5 -and $policy -eq 'marker-or-known-hash') { return $true }
    if ($version -ne 6 -or $policy -ne $managedHelperOwnershipPolicy) { return $false }

    $managedHelpers = Get-StateProperty $State 'managed_helpers'
    if ($null -eq $managedHelpers) { return $false }
    $pathKeys = @($RelativePath, $RelativePath.Replace('/', '\'), $RelativePath.Replace('\', '/')) | Select-Object -Unique
    foreach ($pathKey in $pathKeys) {
        $hashProperty = $managedHelpers.PSObject.Properties[$pathKey]
        if ($null -ne $hashProperty -and
            [string]::Equals([string]$hashProperty.Value, $Hash, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Assert-ManagedHelperOwnership {
    param(
        [string]$TargetPath,
        [string]$SourcePath,
        [string]$Name,
        [string]$RelativePath,
        [object]$ExistingState
    )

    if (-not (Test-Path -LiteralPath $TargetPath)) { return }
    if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
        throw "Managed helper path is not a file: $TargetPath"
    }
    if (Test-SamePath $TargetPath $SourcePath) { return }
    if ((Get-FileHash -Algorithm SHA256 $TargetPath).Hash -eq (Get-FileHash -Algorithm SHA256 $SourcePath).Hash) { return }

    $hash = (Get-FileHash -Algorithm SHA256 $TargetPath).Hash
    if ($releasedManagedHelperHashes[$Name] -contains $hash) { return }
    if ((Test-ExactManagedHelperMarker $TargetPath) -and
        (Test-StateOwnsManagedHelper $ExistingState $RelativePath $hash)) { return }
    throw "Refusing to overwrite an unowned existing helper: $TargetPath"
}

function Assert-NoUnknownManagedMarkers {
    param([string]$Content, [string]$Path)

    $matches = [Regex]::Matches(
        $Content,
        'new-project-setup:v(?<version>[^:\s>]+):(?<boundary>[A-Za-z0-9_-]+)',
        [Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
    foreach ($match in $matches) {
        $versionText = $match.Groups['version'].Value
        $boundary = $match.Groups['boundary'].Value
        $version = 0
        if (-not [int]::TryParse($versionText, [ref]$version) -or
            -not ($supportedWorkflowVersions -contains $version) -or
            -not (@('start', 'end') -contains $boundary)) {
            throw "Unknown managed marker in ${Path}: $($match.Value)"
        }
    }
}

function Get-ExistingManagedMarker {
    param(
        [string]$Content,
        [object[]]$Markers,
        [string]$Path
    )

    Assert-NoUnknownManagedMarkers $Content $Path
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

function Remove-SafeStageRoot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return }
    $tempRoot = Get-NormalizedFullPath ([IO.Path]::GetTempPath())
    $fullPath = Get-NormalizedFullPath $Path
    if (-not $fullPath.StartsWith((Get-DescendantPathPrefix $tempRoot), $PathComparison) -or
        -not ([IO.Path]::GetFileName($fullPath).StartsWith('new-project-setup-apply-stage-', [StringComparison]::Ordinal))) {
        throw "Refusing to remove unexpected apply staging path: $Path"
    }
    $item = Get-Item -Force -LiteralPath $fullPath
    if (Test-RedirectedLink $item) { throw "Apply staging root is redirected: $fullPath" }
    Remove-Item -LiteralPath $fullPath -Force -Recurse
}

function Ensure-TransactionDirectory {
    param(
        [string]$Path,
        [Collections.Generic.List[string]]$CreatedDirectories
    )

    $missing = New-Object Collections.Generic.List[string]
    $cursor = $Path
    while (-not (Test-Path -LiteralPath $cursor)) {
        $missing.Add($cursor)
        $parent = Split-Path -Parent $cursor
        if ([string]::IsNullOrWhiteSpace($parent) -or (Test-SamePath $parent $cursor)) { break }
        $cursor = $parent
    }
    if (Test-Path -LiteralPath $cursor) {
        $item = Get-Item -Force -LiteralPath $cursor
        if (-not $item.PSIsContainer -or (Test-RedirectedLink $item)) {
            throw "Transaction parent is not a safe directory: $cursor"
        }
    }
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    for ($index = $missing.Count - 1; $index -ge 0; $index--) {
        $CreatedDirectories.Add([IO.Path]::GetFullPath($missing[$index]))
    }
}

function Invoke-FileTransaction {
    param(
        [object[]]$Entries,
        [scriptblock]$FinalValidation
    )

    $changedEntries = @($Entries | Where-Object { $_.Changed })
    if ($changedEntries.Count -eq 0) { return }
    foreach ($entry in $changedEntries) {
        Assert-FileSnapshot $entry.Target $entry.Snapshot 'Managed target input'
    }

    $applied = New-Object Collections.Generic.List[object]
    $createdDirectories = New-Object Collections.Generic.List[string]
    $rollbackSucceeded = $false
    $commitValidated = $false
    try {
        foreach ($entry in $changedEntries) {
            $target = Assert-TargetPath $entry.Target
            Assert-FileSnapshot $target $entry.Snapshot 'Managed target input'
            $parent = Split-Path -Parent $target
            Ensure-TransactionDirectory $parent $createdDirectories
            $token = [Guid]::NewGuid().ToString('N')
            $temporary = Join-Path $parent ('.nps6-write-' + $token)
            $backup = Join-Path $parent ('.nps6-rollback-' + $token)
            try {
                Copy-Item -LiteralPath $entry.Stage -Destination $temporary -Force
                if ((Get-FileHash -Algorithm SHA256 -LiteralPath $temporary).Hash -ne $entry.StageHash) {
                    throw "Transaction temporary hash mismatch: $($entry.Relative)"
                }
                if ($entry.Snapshot.Kind -eq 'file') {
                    [IO.File]::Replace($temporary, $target, $backup, $true)
                } else {
                    [IO.File]::Move($temporary, $target)
                }
            }
            finally {
                if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
            }
            $applied.Add([pscustomobject]@{
                Target = $target
                Backup = $backup
                Existed = $entry.Snapshot.Kind -eq 'file'
                Snapshot = $entry.Snapshot
            })
            if ($applied.Count -eq 1) { Invoke-TestFault 'apply-after-first-replace' }
        }

        Invoke-TestFault 'apply-before-final-validation'
        & $FinalValidation
        foreach ($entry in $changedEntries) {
            if ((Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Target).Hash -ne $entry.StageHash) {
                throw "Applied payload hash mismatch: $($entry.Relative)"
            }
        }
        $commitValidated = $true
        foreach ($item in $applied) {
            if ($item.Existed -and (Test-Path -LiteralPath $item.Backup)) {
                Remove-Item -LiteralPath $item.Backup -Force
            }
        }
        $rollbackSucceeded = $true
    }
    catch {
        $failure = $_
        if ($commitValidated) { throw $failure }
        $rollbackErrors = New-Object Collections.Generic.List[string]
        for ($index = $applied.Count - 1; $index -ge 0; $index--) {
            $item = $applied[$index]
            try {
                if ($item.Existed) {
                    if (-not (Test-Path -LiteralPath $item.Backup -PathType Leaf)) {
                        throw "Rollback backup is missing: $($item.Backup)"
                    }
                    if (Test-Path -LiteralPath $item.Target -PathType Leaf) {
                        $discard = Join-Path (Split-Path -Parent $item.Target) ('.nps6-discard-' + [Guid]::NewGuid().ToString('N'))
                        [IO.File]::Replace($item.Backup, $item.Target, $discard, $true)
                        if (Test-Path -LiteralPath $discard) { Remove-Item -LiteralPath $discard -Force }
                    } else {
                        [IO.File]::Move($item.Backup, $item.Target)
                    }
                } elseif (Test-Path -LiteralPath $item.Target) {
                    Remove-Item -LiteralPath $item.Target -Force
                }
                Assert-FileSnapshot $item.Target $item.Snapshot 'Rolled-back target'
            }
            catch {
                $rollbackErrors.Add($_.Exception.Message)
            }
        }
        foreach ($directory in @($createdDirectories | Sort-Object Length -Descending)) {
            try {
                if ((Test-Path -LiteralPath $directory -PathType Container) -and
                    @(Get-ChildItem -Force -LiteralPath $directory).Count -eq 0) {
                    Remove-Item -LiteralPath $directory -Force
                }
            }
            catch {
                $rollbackErrors.Add($_.Exception.Message)
            }
        }
        if ($rollbackErrors.Count -gt 0) {
            throw "Apply failed: $($failure.Exception.Message). Rollback also failed: $($rollbackErrors -join '; ')"
        }
        throw $failure
    }
    finally {
        if (-not $rollbackSucceeded) {
            foreach ($item in $applied) {
                if (Test-Path -LiteralPath $item.Backup) {
                    Write-Warning "Retained rollback backup after failed apply: $($item.Backup)"
                }
            }
        }
    }
}

function Assert-ApplyPayload {
    param(
        [string]$Root,
        [object[]]$ManagedFiles,
        [hashtable]$ExpectedHelperHashes
    )

    foreach ($managed in $ManagedFiles) {
        $path = Join-Path $Root $managed.Relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Staged managed file is missing: $($managed.Relative)"
        }
        $content = Get-Content -Raw -LiteralPath $path
        $marker = Get-ExistingManagedMarker $content $managed.AllMarkers $path
        if ($null -eq $marker -or [int]$marker.Version -ne $WorkflowVersion) {
            throw "Staged managed file does not contain exactly one v${WorkflowVersion} block: $($managed.Relative)"
        }
    }

    $statePath = Join-Path $Root '.codex/new-project-setup.json'
    $state = Read-WorkflowState $statePath
    if ($null -eq $state -or [int](Get-StateProperty $state 'format') -ne $StateFormat -or
        [int](Get-StateProperty $state 'workflow_version') -ne $WorkflowVersion -or
        [string](Get-StateProperty $state 'helper_ownership') -ne $managedHelperOwnershipPolicy) {
        throw "Staged workflow state is not the exact v${WorkflowVersion} format."
    }

    foreach ($relative in @('scripts/github-sync.ps1', 'scripts/github-backup.ps1')) {
        $path = Join-Path $Root $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Staged managed helper is missing: $relative"
        }
        if (-not (Test-ExactManagedHelperMarker $path)) {
            throw "Staged managed helper lacks the exact first-line ownership marker: $relative"
        }
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
        if ($hash -ne $ExpectedHelperHashes[$relative] -or
            -not (Test-StateOwnsManagedHelper $state $relative $hash)) {
            throw "Staged managed helper identity does not match workflow state: $relative"
        }
        $tokens = $null
        $errors = $null
        [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
        if ($errors.Count) { throw "Staged managed helper parse failure for ${relative}: $($errors.Message -join '; ')" }
    }

    foreach ($relative in @('docs/development-log.md', 'docs/codex-handoff.md', 'CHANGELOG.md')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $relative) -PathType Leaf)) {
            throw "Staged project memory file is missing: $relative"
        }
    }
}

$inputRootItem = Get-Item -Force -LiteralPath $ProjectRoot
if (Test-RedirectedLink $inputRootItem) {
    throw "ProjectRoot must not be a redirected link: $ProjectRoot"
}

Assert-TestFaultConfiguration $testFaultPoints
$operationLocks = @(Enter-OperationLocks @($resolvedRoot, $skillRoot))
$stageRoot = $null
$scriptExitCode = 0
try {
$syncInstalledSentinel = Join-Path $resolvedRoot 'scripts/sync-installed-skill.ps1'
$syncFromInstalledSentinel = Join-Path $resolvedRoot 'scripts/sync-from-installed-skill.ps1'
$skillSentinel = Join-Path $resolvedRoot 'SKILL.md'
$testSentinel = Join-Path $resolvedRoot 'tests/run-tests.ps1'
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
    'docs/development-log.md',
    'docs/codex-handoff.md',
    'CHANGELOG.md',
    '.codex/new-project-setup.json',
    'scripts/github-sync.ps1',
    'scripts/github-backup.ps1'
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

Infer durability, operational risk, and effort independently. State them
briefly and continue:

- Lasting work preserves revisions and memory. Exploration is disposable only
  for clear learning or feasibility; `quick`, `prototype`, and `MVP` do not
  imply it. Promote reused or retained work; never demote. Delete only current
  uncommitted Codex-created artifacts confirmed unused, never pre-existing,
  shared, or lasting output.
- Risk controls authorization, not routine local implementation authority.
- Effort controls context and evidence, not authority: focused checks direct
  effects; standard covers primary workflows and distinct risks;
  release-critical gathers broad deduplicated evidence.

Ask one preservation question only for ambiguous durability. Do not ask for
routine implementation, context expansion, or validation transitions. Bounded
local work authorizes architecture, a reasonable initial stack for an empty project,
dependencies, tests, demo data, and empty-DB schemas.

### Progressive context and evidence

Start file changes with Git status and relevant files; durable work adds
`docs/codex-handoff.md`. Read logs only when useful. Expand for dependencies,
failures, or risk; exclude unrelated roots and artifacts. Rebuild stale
handoffs from Git and evidence; ask only if the objective remains unsafe.

Keep a compact ledger of acceptance criteria, material risks, boundaries,
evidence, invalidators, and completion conditions. Claim
completion only when every criterion passes, every material risk or protected
boundary has distinct evidence, no unresolved high-risk failure remains, and
durable records are current. Evidence is distinct only for a materially
different risk or protected boundary; code-path or presentation variation
alone is equivalent evidence.

Reuse valid evidence and batch failures by cause. After targeted checks pass,
run one effort-appropriate final matrix. On failure, preserve passing evidence,
retest only failed or invalidated checks, and do not restart a broad matrix.
Non-improving cycles require a different strategy, then a minimal reproducer;
they do not stop productive debugging. Stop unresolved
only when the latest strategy made no material progress and no credible bounded
probe remains. Preserve diagnostics and report the blocker.

### Proportional durable memory

Preserve every lasting change in Git. Log useful decisions, failures, validation,
or lessons; refresh the concise handoff at state boundaries with
valid and remaining evidence; update the changelog for notable behavior. Keep
private details in ignored `*.local.md` and recheck branch, HEAD, and scope.
Prepare the final handoff before its containing commit and record sync relative
to it; a matching push needs no bookkeeping-only commit.

Before every lasting commit, stage only the scoped files and run
`scripts/github-sync.ps1 -PreCommit -CommitMessage '<exact message>'`. Commit
that exact audited staged tree and public-ready message immediately. Missing or
mismatched audit evidence fails safe to immediate synchronization.

After a focused small-change commit, run `scripts/github-sync.ps1
-BatchEligible`: one through nine verified local commits may remain local, and
the tenth synchronizes the complete batch. There is no time trigger. Initial
setup, standard or substantial work, milestones, releases, explicit sync
requests, and absent remote branches synchronize immediately with the normal
command. Normal private sync audits the current snapshot and every commit after
the verified private remote tip, using private-source rules that block
high-confidence secrets and unsafe Git objects without treating operational
metadata as a push blocker. Exact findings inherited unchanged from that tip
are already transferred; changed, re-added, or new findings block. Empty
remotes use the same private-source rules across full ancestry.
Public-readiness and isolated fallback use stricter public-metadata review.
Never force-push or change visibility.

Existing unsafe ancestry already transferred to the exact private destination
is not a reason to use fallback. For local-only legacy ancestry and an empty
destination, offer the guarded one-time clean-baseline recovery only with
explicit approval; it preserves the old history in local hidden refs and never
force-pushes. Otherwise keep the commit and ask whether to use isolated
`scripts/github-backup.ps1` or remain local-only. Fallback never modifies the
normal source remote.

### Autonomous local work

Complete bounded objectives end-to-end through appropriate validation without
routine checkpoints.
Ask before deployment; credentials or live/paid services; auth/security changes;
global or native tool installation; framework or platform replacement;
consequential licensing changes; changes to existing, shared, or production
data; destructive operations; material product-direction expansion beyond the
request; or unrelated conflicting work. Internal refactoring, routine local
dependencies, and isolated local construction need no checkpoint.
Protected boundaries override implied authority. Deployment requires
confirmation immediately before the action unless the current request explicitly
names the target and effect and waives that checkpoint; that explicit waiver is
the confirmation. Merely asking to deploy is not a waiver. One confirmation may
cover several protected effects only when it names them all.

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
*.ps1 text eol=lf
*.cmd text eol=crlf
*.bat text eol=crlf
*.sh text eol=lf
*.md text eol=lf
*.json text eol=lf
*.yaml text eol=lf
*.yml text eol=lf
'@

$managedFiles = @(
    @{ Relative = 'AGENTS.md'; Path = (Join-Path $resolvedRoot 'AGENTS.md'); Previous = @(@{ Version = 2; Start = '<!-- new-project-setup:v2:start -->'; End = '<!-- new-project-setup:v2:end -->' }, @{ Version = 3; Start = '<!-- new-project-setup:v3:start -->'; End = '<!-- new-project-setup:v3:end -->' }, @{ Version = 4; Start = '<!-- new-project-setup:v4:start -->'; End = '<!-- new-project-setup:v4:end -->' }, @{ Version = 5; Start = '<!-- new-project-setup:v5:start -->'; End = '<!-- new-project-setup:v5:end -->' }); NewStart = '<!-- new-project-setup:v6:start -->'; NewEnd = '<!-- new-project-setup:v6:end -->'; Body = $agentsBody.Trim() },
    @{ Relative = '.gitignore'; Path = (Join-Path $resolvedRoot '.gitignore'); Previous = @(@{ Version = 2; Start = '# new-project-setup:v2:start'; End = '# new-project-setup:v2:end' }, @{ Version = 3; Start = '# new-project-setup:v3:start'; End = '# new-project-setup:v3:end' }, @{ Version = 4; Start = '# new-project-setup:v4:start'; End = '# new-project-setup:v4:end' }, @{ Version = 5; Start = '# new-project-setup:v5:start'; End = '# new-project-setup:v5:end' }); NewStart = '# new-project-setup:v6:start'; NewEnd = '# new-project-setup:v6:end'; Body = $ignoreBody.Trim() },
    @{ Relative = '.gitattributes'; Path = (Join-Path $resolvedRoot '.gitattributes'); Previous = @(@{ Version = 2; Start = '# new-project-setup:v2:start'; End = '# new-project-setup:v2:end' }, @{ Version = 3; Start = '# new-project-setup:v3:start'; End = '# new-project-setup:v3:end' }, @{ Version = 4; Start = '# new-project-setup:v4:start'; End = '# new-project-setup:v4:end' }, @{ Version = 5; Start = '# new-project-setup:v5:start'; End = '# new-project-setup:v5:end' }); NewStart = '# new-project-setup:v6:start'; NewEnd = '# new-project-setup:v6:end'; Body = $attributesBody.Trim() }
)
foreach ($managed in $managedFiles) {
    $managed.AllMarkers = @($managed.Previous) + @(@{ Version = 6; Start = $managed.NewStart; End = $managed.NewEnd })
}
$sourceHelper = Join-Path $PSScriptRoot 'github-backup.ps1'
$sourceSync = Join-Path $PSScriptRoot 'github-sync.ps1'
$targetHelper = Assert-TargetPath (Join-Path $resolvedRoot 'scripts/github-backup.ps1')
$targetSync = Assert-TargetPath (Join-Path $resolvedRoot 'scripts/github-sync.ps1')
$statePath = Assert-TargetPath (Join-Path $resolvedRoot '.codex/new-project-setup.json')

foreach ($sourcePath in @($sourceSync, $sourceHelper)) {
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Bundled managed helper is missing: $sourcePath"
    }
    if ((Test-RedirectedLink (Get-Item -Force -LiteralPath $PSScriptRoot)) -or
        (Test-RedirectedLink (Get-Item -Force -LiteralPath $sourcePath))) {
        throw "Bundled managed helper path is redirected: $sourcePath"
    }
    if (-not (Test-ExactManagedHelperMarker $sourcePath)) {
        throw "Bundled helper lacks the exact first-line ownership marker: $sourcePath"
    }
}

$markerVersions = New-Object Collections.Generic.List[int]
foreach ($managed in $managedFiles) {
    $managed.Path = Assert-TargetPath $managed.Path
    if ((Test-Path -LiteralPath $managed.Path) -and -not (Test-Path -LiteralPath $managed.Path -PathType Leaf)) {
        throw "Managed marker path is not a file: $($managed.Path)"
    }
    $current = if (Test-Path -LiteralPath $managed.Path -PathType Leaf) { Get-Content -Raw -LiteralPath $managed.Path } else { '' }
    $managed.ExistingMarker = Get-ExistingManagedMarker $current $managed.AllMarkers $managed.Path
    if ($null -ne $managed.ExistingMarker) { $markerVersions.Add([int]$managed.ExistingMarker.Version) }
}

$existingState = Read-WorkflowState $statePath
$distinctMarkerVersions = @($markerVersions | Sort-Object -Unique)
if ($distinctMarkerVersions.Count -gt 1) {
    throw "Managed files contain conflicting workflow marker versions: $($distinctMarkerVersions -join ', ')"
}
if ($distinctMarkerVersions.Count -gt 0 -and $null -eq $existingState) {
    throw 'Managed workflow markers exist without versioned workflow state.'
}
if ($null -ne $existingState -and $distinctMarkerVersions.Count -gt 0 -and
    $distinctMarkerVersions[0] -ne [int](Get-StateProperty $existingState 'workflow_version')) {
    throw "Managed marker version does not match workflow state version: $statePath"
}

Assert-ManagedHelperOwnership $targetSync $sourceSync 'github-sync.ps1' 'scripts/github-sync.ps1' $existingState
Assert-ManagedHelperOwnership $targetHelper $sourceHelper 'github-backup.ps1' 'scripts/github-backup.ps1' $existingState

$memoryDefaults = [ordered]@{
    'docs/development-log.md' = "# Development Log`n`nKeep entries public-ready: completed work, decisions and rationale, useful failed approaches, validation, and durable lessons.`n"
    'CHANGELOG.md' = "# Changelog`n"
    'docs/codex-handoff.md' = "# Codex Handoff`n`n- Current objective: Complete project setup.`n- Current state: Managed workflow files are installed; project validation, commit, and GitHub synchronization remain.`n- Next action: Validate setup, then commit and synchronize it.`n- Blockers: None known.`n- Important decisions: GitHub history is private; public-readiness uses stricter audit.`n- Branch/commit/sync: Pending verification and completion.`n- Validation complete: Deterministic managed-payload application.`n- Validation remaining: Project checks, scoped commit, and GitHub result.`n"
}
foreach ($relative in $memoryDefaults.Keys) {
    $memoryPath = Assert-TargetPath (Join-Path $resolvedRoot $relative)
    if ((Test-Path -LiteralPath $memoryPath) -and -not (Test-Path -LiteralPath $memoryPath -PathType Leaf)) {
        throw "Project memory path is not a file: $memoryPath"
    }
}

$sourceInputs = [ordered]@{
    'scripts/github-sync.ps1' = $sourceSync
    'scripts/github-backup.ps1' = $sourceHelper
}
$sourceSnapshots = @{}
$expectedHelperHashes = @{}
foreach ($relative in $sourceInputs.Keys) {
    $sourceSnapshots[$relative] = Get-FileSnapshot $sourceInputs[$relative]
    $expectedHelperHashes[$relative] = $sourceSnapshots[$relative].Hash
}

$targetPaths = [ordered]@{}
foreach ($managed in $managedFiles) { $targetPaths[$managed.Relative] = $managed.Path }
$targetPaths['.codex/new-project-setup.json'] = $statePath
$targetPaths['scripts/github-sync.ps1'] = $targetSync
$targetPaths['scripts/github-backup.ps1'] = $targetHelper
foreach ($relative in $memoryDefaults.Keys) {
    $targetPaths[$relative] = Assert-TargetPath (Join-Path $resolvedRoot $relative)
}
$targetSnapshots = @{}
foreach ($relative in $targetPaths.Keys) {
    $targetSnapshots[$relative] = Get-FileSnapshot $targetPaths[$relative]
}

$effectiveRepository = if ($Repository) { $Repository } elseif (Get-StateProperty $existingState 'repository') { [string](Get-StateProperty $existingState 'repository') } else { $null }
$effectiveRemote = if ($RemoteName) { $RemoteName } elseif (Get-StateProperty $existingState 'remote') { [string](Get-StateProperty $existingState 'remote') } else { 'origin' }
$stateContent = ([ordered]@{
    format = $StateFormat
    workflow_version = $WorkflowVersion
    github_mode = 'private-source-strict-public-readiness'
    repository = $effectiveRepository
    remote = $effectiveRemote
    source_authority = 'source-first'
    automation_runtime = 'pwsh-preferred-windows-powershell-fallback'
    platform_support = 'windows-macos-linux'
    path_comparison = 'filesystem-aware-existing-paths'
    text_eol = 'lf'
    target_path_policy = 'contained-no-reparse'
    managed_marker_policy = 'unique-fail-closed'
    apply_preflight = 'locked-stage-validate-immutable-before-write'
    operation_lock = 'path-keyed-cross-session-file-lock'
    input_immutability = 'sha256-recheck'
    apply_transaction = 'atomic-file-replace-with-retained-rollback'
    helper_ownership = $managedHelperOwnershipPolicy
    managed_helpers = [ordered]@{
        'scripts/github-sync.ps1' = $expectedHelperHashes['scripts/github-sync.ps1']
        'scripts/github-backup.ps1' = $expectedHelperHashes['scripts/github-backup.ps1']
    }
    source_history_sync = $true
    precommit_audit = 'exact-index-candidate-and-metadata'
    precommit_attestation = 'local-fail-safe'
    normal_history_audit = 'verified-private-remote-boundary-plus-local-delta'
    public_readiness_audit = 'full-ancestry'
    sync_cadence = 'focused-batched-standard-immediate'
    focused_sync_commit_threshold = 10
    focused_sync_time_trigger = 'none'
    source_history_recovery = 'explicit-one-time-clean-root'
    legacy_history_preservation = 'local-hidden-ref'
    recovery_destination = 'private-absent-branch'
    recovery_retry = 'normal-sync-only'
    audit_failure_action = 'classify-recover-or-ask-fallback'
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
    completion_invariant = 'criteria_and_risk_boundary_records'
    evidence_equivalence = 'material_risk_or_protected_boundary'
    convergence_action = 'change-strategy'
    convergence_escalation = 'minimal-reproducer'
    convergence_terminal = 'no-material-progress-and-no-credible-bounded-probe'
    final_validation_matrix = 'one-broad-pass-then-invalidated-only'
    final_validation_scope = 'effort-appropriate'
    unresolved_local_failure = 'preserve-and-report'
    deployment_waiver = 'explicit-target-effect-waiver-is-confirmation'
    deployment_request_alone = 'not-waiver'
}) | ConvertTo-Json -Depth 4

$stageRoot = Join-Path ([IO.Path]::GetTempPath()) ('new-project-setup-apply-stage-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stageRoot | Out-Null
$entries = New-Object Collections.Generic.List[object]
$addEntry = {
    param([string]$Relative)
    $stagePath = Join-Path $stageRoot $Relative
    $stageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $stagePath).Hash
    $snapshot = $targetSnapshots[$Relative]
    $changed = $snapshot.Kind -eq 'missing' -or $snapshot.Hash -ne $stageHash
    $entries.Add([pscustomobject]@{
        Relative = $Relative
        Target = $targetPaths[$Relative]
        Stage = $stagePath
        StageHash = $stageHash
        Snapshot = $snapshot
        Changed = $changed
    })
    if ($changed) { $changes.Add($Relative) }
}

foreach ($managed in $managedFiles) {
    $stagePath = Join-Path $stageRoot $managed.Relative
    $stageParent = Split-Path -Parent $stagePath
    if ($stageParent) { New-Item -ItemType Directory -Force -Path $stageParent | Out-Null }
    $current = if (Test-Path -LiteralPath $managed.Path -PathType Leaf) { Get-Content -Raw -LiteralPath $managed.Path } else { '' }
    $existingMarker = Get-ExistingManagedMarker $current $managed.AllMarkers $managed.Path
    $replacement = $managed.NewStart + "`n" + $managed.Body + "`n" + $managed.NewEnd
    if ($null -ne $existingMarker) {
        $oldPattern = '(?s)' + [Regex]::Escape([string]$existingMarker.Start) + '.*?' + [Regex]::Escape([string]$existingMarker.End)
        $next = [Regex]::Replace($current, $oldPattern, $replacement)
    } elseif ($current.Trim()) {
        $next = $current.TrimEnd() + "`n`n" + $replacement + "`n"
    } else {
        $next = $replacement + "`n"
    }
    if ((Test-Path -LiteralPath $managed.Path -PathType Leaf) -and
        $current.Replace("`r`n", "`n") -eq $next.Replace("`r`n", "`n")) {
        Copy-Item -LiteralPath $managed.Path -Destination $stagePath -Force
    } else {
        Write-Utf8NoBom $stagePath $next
    }
    & $addEntry $managed.Relative
}

$stagedState = Join-Path $stageRoot '.codex/new-project-setup.json'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stagedState) | Out-Null
Write-Utf8NoBom $stagedState ($stateContent + "`n")
& $addEntry '.codex/new-project-setup.json'

foreach ($relative in $sourceInputs.Keys) {
    $stagePath = Join-Path $stageRoot $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stagePath) | Out-Null
    Copy-Item -LiteralPath $sourceInputs[$relative] -Destination $stagePath -Force
    & $addEntry $relative
}

foreach ($relative in $memoryDefaults.Keys) {
    $stagePath = Join-Path $stageRoot $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stagePath) | Out-Null
    $targetPath = $targetPaths[$relative]
    if ((Test-Path -LiteralPath $targetPath -PathType Leaf) -and
        -not [string]::IsNullOrWhiteSpace((Get-Content -Raw -LiteralPath $targetPath))) {
        Copy-Item -LiteralPath $targetPath -Destination $stagePath -Force
    } else {
        Write-Utf8NoBom $stagePath $memoryDefaults[$relative]
    }
    & $addEntry $relative
}

Assert-ApplyPayload $stageRoot $managedFiles $expectedHelperHashes
Invoke-TestFault 'apply-after-stage'
foreach ($relative in $sourceInputs.Keys) {
    Assert-FileSnapshot $sourceInputs[$relative] $sourceSnapshots[$relative] 'Bundled helper input'
}
foreach ($relative in $targetPaths.Keys) {
    Assert-FileSnapshot $targetPaths[$relative] $targetSnapshots[$relative] 'Managed target input'
}

if ($changes.Count -eq 0) {
    Write-Host "Project setup managed payload v${WorkflowVersion} is current. Review project-specific handoff content before claiming task completion."
} elseif ($Check) {
    Write-Host "Project setup managed payload v${WorkflowVersion} is stale or incomplete:"
    $changes | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
    $scriptExitCode = 2
} else {
    $finalValidation = {
        foreach ($relative in $sourceInputs.Keys) {
            Assert-FileSnapshot $sourceInputs[$relative] $sourceSnapshots[$relative] 'Bundled helper input'
        }
        Assert-ApplyPayload $resolvedRoot $managedFiles $expectedHelperHashes
    }
    Invoke-FileTransaction $entries.ToArray() $finalValidation
    Write-Host "Applied project setup workflow v${WorkflowVersion}:"
    $changes | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
}
}
finally {
    if ($null -ne $stageRoot) { Remove-SafeStageRoot $stageRoot }
    Exit-OperationLocks $operationLocks
}

if ($scriptExitCode -ne 0) { exit $scriptExitCode }
