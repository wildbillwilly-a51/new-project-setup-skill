#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$ProjectRoot = '.',
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [Version]'7.6.0') {
    throw 'PowerShell Core 7.6 or later (pwsh) is required for workflow version 7.'
}
$WorkflowVersion = 7
$StateFormat = 3
$Utf8NoBom = [Text.UTF8Encoding]::new($false)
$IsWindowsPlatform = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$PathComparison = if ($IsWindowsPlatform) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
$skillRoot = Split-Path -Parent $PSScriptRoot
$testFault = [Environment]::GetEnvironmentVariable('NEW_PROJECT_SETUP_TEST_FAULT')

function ConvertTo-LfText {
    param([AllowEmptyString()][string]$Text)

    $normalized = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    if ($normalized.Length -gt 0 -and -not $normalized.EndsWith("`n", [StringComparison]::Ordinal)) {
        $normalized += "`n"
    }
    return $normalized
}

function Get-TextBytes {
    param([AllowEmptyString()][string]$Text)

    return ,$Utf8NoBom.GetBytes((ConvertTo-LfText $Text))
}

function Get-BytesHash {
    param([byte[]]$Bytes)

    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Get-TextHash {
    param([AllowEmptyString()][string]$Text)

    return Get-BytesHash (Get-TextBytes $Text)
}

function Get-FileBytes {
    param([string]$Path)

    return ,[IO.File]::ReadAllBytes($Path)
}

function Get-FileHashLower {
    param([string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-SafeRelativePath {
    param([string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath)) {
        throw "Unsafe managed path: $RelativePath"
    }
    $segments = $RelativePath -split '[\\/]'
    if ($segments | Where-Object { $_ -in @('', '.', '..') }) {
        throw "Unsafe managed path: $RelativePath"
    }
}

function Get-PathItemClassification {
    param([object]$Item)

    try {
        if ($null -eq $Item) { return 'unknown' }

        $propertyNames = @($Item.PSObject.Properties.Name)
        if ($propertyNames -cnotcontains 'Attributes') { return 'unknown' }

        $attributes = [IO.FileAttributes]$Item.Attributes
        $isReparsePoint = ($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
        $metadataNames = @('LinkType', 'Target', 'LinkTarget')
        $metadataAvailable = $true
        $hasLinkMetadata = $false
        foreach ($name in $metadataNames) {
            if ($propertyNames -cnotcontains $name) {
                $metadataAvailable = $false
                continue
            }
            foreach ($value in @($Item.PSObject.Properties[$name].Value)) {
                if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
                    $hasLinkMetadata = $true
                }
            }
        }

        if (-not $isReparsePoint) {
            if ($hasLinkMetadata) { return 'unknown' }
            return 'ordinary'
        }
        if (-not $metadataAvailable) { return 'unknown' }
        if ($hasLinkMetadata) { return 'redirected' }
        return 'metadata_reparse'
    } catch {
        return 'unknown'
    }
}

function Test-IsAcceptableFileItem {
    param([object]$Item)

    if ($null -eq $Item -or $Item.PSIsContainer) { return $false }
    $classification = Get-PathItemClassification $Item
    return $classification -cin @('ordinary', 'metadata_reparse')
}

function Get-ContainedTargetPath {
    param(
        [string]$Root,
        [string]$RelativePath
    )

    Assert-SafeRelativePath $RelativePath
    $target = [IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
    $prefix = $Root.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $target.StartsWith($prefix, $PathComparison)) {
        throw "Managed path escapes the project root: $RelativePath"
    }

    $cursor = $Root
    foreach ($segment in ($RelativePath -split '[\\/]')) {
        $cursor = Join-Path $cursor $segment
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if ((Get-PathItemClassification $item) -cin @('redirected', 'unknown')) {
                throw "Managed path crosses a redirected path: $RelativePath"
            }
        }
    }
    return $target
}

function Read-JsonFile {
    param([string]$Path)

    try {
        return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 30
    } catch {
        throw "Invalid workflow state: $($_.Exception.Message)"
    }
}

function Get-ExistingPathItem {
    param([string]$Path)

    try {
        return Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    } catch [Management.Automation.ItemNotFoundException] {
        return $null
    } catch {
        if ($_.CategoryInfo.Category -eq [Management.Automation.ErrorCategory]::ObjectNotFound) {
            return $null
        }
        throw
    }
}

function Assert-OrdinaryFileOrMissing {
    param(
        [string]$Path,
        [string]$Description
    )

    $item = Get-ExistingPathItem $Path
    if ($null -eq $item) { return $null }
    if (-not (Test-IsAcceptableFileItem -Item $item)) {
        throw "$Description is not an ordinary file: $Path"
    }
    return $item
}

function Assert-ExactPropertySet {
    param(
        [object]$Value,
        [string[]]$Expected,
        [string]$Description
    )

    if ($null -eq $Value -or $Value -is [Array]) {
        throw "$Description must be a JSON object."
    }
    $actual = @($Value.PSObject.Properties.Name | Sort-Object)
    $wanted = @($Expected | Sort-Object)
    if (($actual -join '|') -cne ($wanted -join '|')) {
        throw "$Description has unexpected or missing fields."
    }
}

function Get-RequiredPropertyValue {
    param(
        [object]$Value,
        [string]$Name,
        [string]$Description
    )

    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) { throw "$Description is missing required field: $Name" }
    return $property.Value
}

function Expand-FrozenV6Text {
    param([string]$CompressedBase64)

    $compressed = [Convert]::FromBase64String($CompressedBase64)
    $input = [IO.MemoryStream]::new($compressed, $false)
    $output = [IO.MemoryStream]::new()
    $gzip = [IO.Compression.GzipStream]::new($input, [IO.Compression.CompressionMode]::Decompress)
    try {
        $gzip.CopyTo($output)
        return $Utf8NoBom.GetString($output.ToArray())
    } finally {
        $gzip.Dispose()
        $output.Dispose()
        $input.Dispose()
    }
}

function Get-FrozenV6Contract {
    return [pscustomobject]@{
        Blocks = [ordered]@{
            'AGENTS.md' = Expand-FrozenV6Text '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'
            '.gitignore' = Expand-FrozenV6Text 'H4sIAAAAAAACCm1PPU7FMAzefYpI3ZDSbAzvAkycAaWxaf1I7Shx+uD2WAgxMfmT/f15CUKP2LreqVgcZLPdrufbsNwNlvCay8FCsWrJNbTOVzYKqGWeJJaNVeBp/bmuJ8K6sx1zi1suH7P97u/DSe71QkLd5RiQGgmSFKYRsmDwMH7PxQaIIr2dirPSSIA8LME2uWICnY5XoU8fRS/32imB0bD4p0/Qav56dN4Pi52adicv///oFeAbU1XG6/8AAAA='
            '.gitattributes' = Expand-FrozenV6Text 'H4sIAAAAAAACCm3OSwqAIBSF4bmrEJwFBU0aCC3G9EaIqXivPXZfOCms4fnghyO4h72NKVjQ1CJQjnIbJJJKxBpOcNCoMgXWdBH7sjkEN7r5Fr2aR3QqNin6GC5V+O4KWAy+olOtrqZKxP958IZdIK0Fh9gAAAA='
        }
        Handoff = Expand-FrozenV6Text 'H4sIAAAAAAACCm2RQU/DMAyF7/sVlrh2273cGBLjwMRpdy9xV7M0iRy32/j1uGsZCHGp1OT5vc8vD7BJni6wxehT0ywWS9j0IhQV0uGDnPJAtWm6HEgJsqTxEAppn1e/xEVRTfiGEY/k4Zzk1IR0hoYDFUAh4GiaEMg/3l0GDOxROcUKXOo61gqMA15Yt/0ByjW6VlLkz5sGhDrkOKbu6KKAbjytYT+50ARVgbYUZ7ub24+NQeg4/hSSO5GUGnYpEpxiOt9sX7ucRNHW8eS4mLtJZpiWiya5AhfD58HybI/+ENgthdBzpFKgL7ZsUWGnJIC9n/MEDWE9Ma1HnhreKdrQEQYSbthNG464burafsfR/b2i7wtr+dm+0nE0JHbQTZ0vM15DQg+Yc5gN/zhMBVqqxc9P4Fpyp1JBcSmT/+8VhEofdLX4AiDS7QkqAgAA'
        LegacyHelperHashes = [ordered]@{
            'scripts/github-backup.ps1' = '60ac4a31c547a896cb07dbc9352fa1ef694e145880ad538bebaced4738b615b0'
            'scripts/github-sync.ps1' = 'cc178cd21e90cb37b447fe4b960e29ac3f4eaf687cc3827bdbac7a3bea70e304'
        }
    }
}

function Assert-ExactV6ManagedBlock {
    param(
        [string]$Root,
        [string]$RelativePath,
        [string]$ExpectedBlock
    )

    $target = Get-ContainedTargetPath $Root $RelativePath
    $item = Assert-OrdinaryFileOrMissing -Path $target -Description "Version-6 managed marker path $RelativePath"
    if ($null -eq $item) { throw "Managed version-6 block is missing from $RelativePath." }
    $text = ConvertTo-LfText (Get-Content -Raw -LiteralPath $target)
    $tokens = [regex]::Matches($text, 'new-project-setup:v(?<version>[^:\s>]+):(?<boundary>[A-Za-z0-9_-]+)')
    if ($tokens.Count -ne 2 -or
        @($tokens | Where-Object { $_.Groups['version'].Value -cne '6' }).Count -ne 0 -or
        @($tokens | Where-Object { $_.Groups['boundary'].Value -cnotin @('start', 'end') }).Count -ne 0 -or
        @($tokens | Where-Object { $_.Groups['boundary'].Value -ceq 'start' }).Count -ne 1 -or
        @($tokens | Where-Object { $_.Groups['boundary'].Value -ceq 'end' }).Count -ne 1) {
        throw "Unexpected, conflicting, or duplicate workflow marker in $RelativePath."
    }
    $lineComment = $RelativePath -cne 'AGENTS.md'
    $block = Get-ManagedBlock $text 'new-project-setup:v6' -LineComment:$lineComment
    if ($null -eq $block -or (ConvertTo-LfText $block) -cne (ConvertTo-LfText $ExpectedBlock)) {
        throw "Managed version-6 block was modified: $RelativePath"
    }
}

function Assert-V6MigrationCandidate {
    param(
        [object]$State,
        [string]$Root,
        [object]$Contract
    )

    $invariants = [ordered]@{
        format = 2
        workflow_version = 6
        github_mode = 'private-source-strict-public-readiness'
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
        helper_ownership = 'first-line-marker-with-versioned-state-or-known-release-hash'
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
    }
    $expectedTop = @($invariants.Keys) + @('repository', 'remote', 'managed_helpers')
    Assert-ExactPropertySet -Value $State -Expected $expectedTop -Description 'Version-6 migration candidate state'
    foreach ($entry in $invariants.GetEnumerator()) {
        $actual = Get-RequiredPropertyValue -Value $State -Name $entry.Key -Description 'Version-6 migration candidate state'
        if ($entry.Value -is [bool]) {
            if ($actual -isnot [bool] -or $actual -ne $entry.Value) { throw "Version-6 invariant is invalid: $($entry.Key)" }
        } elseif ($entry.Value -is [int]) {
            if ($actual -isnot [int] -and $actual -isnot [long]) { throw "Version-6 invariant type is invalid: $($entry.Key)" }
            if ([long]$actual -ne [long]$entry.Value) { throw "Version-6 invariant is invalid: $($entry.Key)" }
        } elseif ($actual -isnot [string] -or [string]$actual -cne [string]$entry.Value) {
            throw "Version-6 invariant is invalid: $($entry.Key)"
        }
    }

    $repository = Get-RequiredPropertyValue -Value $State -Name 'repository' -Description 'Version-6 migration candidate state'
    if ($null -ne $repository -and ($repository -isnot [string] -or $repository -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}/[A-Za-z0-9][A-Za-z0-9_.-]{0,99}$')) {
        throw 'Version-6 repository value is invalid.'
    }
    $remote = Get-RequiredPropertyValue -Value $State -Name 'remote' -Description 'Version-6 migration candidate state'
    if ($remote -isnot [string] -or [string]::IsNullOrWhiteSpace($remote) -or $remote.StartsWith('-', [StringComparison]::Ordinal) -or
        $remote -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*$' -or $remote.Contains('..', [StringComparison]::Ordinal) -or
        $remote.Contains('@{', [StringComparison]::Ordinal) -or $remote.EndsWith('/', [StringComparison]::Ordinal) -or
        $remote.EndsWith('.', [StringComparison]::Ordinal) -or $remote.EndsWith('.lock', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Version-6 remote value is invalid.'
    }

    $managedHelpers = Get-RequiredPropertyValue -Value $State -Name 'managed_helpers' -Description 'Version-6 migration candidate state'
    if ($null -eq $managedHelpers -or $managedHelpers -is [Array]) { throw 'Version-6 managed_helpers must be a JSON object.' }
    $allowedHelpers = @('scripts/github-backup.ps1', 'scripts/github-sync.ps1')
    foreach ($property in $managedHelpers.PSObject.Properties) {
        if ($property.Name -cnotin $allowedHelpers) { throw "Unexpected version-6 managed-helper key: $($property.Name)" }
        if ($null -ne $property.Value -and ($property.Value -isnot [string] -or [string]$property.Value -cnotmatch '^[0-9a-fA-F]{64}$')) {
            throw "Malformed version-6 managed-helper ownership value: $($property.Name)"
        }
    }

    foreach ($entry in $Contract.Blocks.GetEnumerator()) {
        Assert-ExactV6ManagedBlock -Root $Root -RelativePath $entry.Key -ExpectedBlock $entry.Value
    }
}

function New-Stage4Warning {
    param(
        [string]$Code,
        [string]$Path,
        [string]$Message
    )

    return [pscustomobject][ordered]@{
        code = $Code
        path = $Path
        message = $Message
    }
}

function Get-ManagedBlock {
    param(
        [AllowEmptyString()][string]$Text,
        [string]$Marker,
        [switch]$LineComment
    )

    $start = if ($LineComment) { "# ${Marker}:start" } else { "<!-- ${Marker}:start -->" }
    $end = if ($LineComment) { "# ${Marker}:end" } else { "<!-- ${Marker}:end -->" }
    $startMatches = [regex]::Matches($Text, [regex]::Escape($start))
    $endMatches = [regex]::Matches($Text, [regex]::Escape($end))
    if ($startMatches.Count -ne $endMatches.Count -or $startMatches.Count -gt 1) {
        throw "Malformed or duplicate managed marker: $Marker"
    }
    if ($startMatches.Count -eq 0) {
        return $null
    }
    if ($endMatches[0].Index -lt $startMatches[0].Index) {
        throw "Malformed managed marker order: $Marker"
    }
    $length = ($endMatches[0].Index + $end.Length) - $startMatches[0].Index
    return $Text.Substring($startMatches[0].Index, $length)
}

function Assert-NoUnexpectedWorkflowMarkers {
    param(
        [AllowEmptyString()][string]$Text,
        [string]$RelativePath
    )

    $starts = [regex]::Matches($Text, '(?m)^(?:<!-- |# )new-project-setup:v(?<version>\d+):start(?: -->)?$')
    $ends = [regex]::Matches($Text, '(?m)^(?:<!-- |# )new-project-setup:v(?<version>\d+):end(?: -->)?$')
    if ($starts.Count -ne $ends.Count -or $starts.Count -gt 1) {
        throw "Malformed or duplicate workflow marker in $RelativePath"
    }
    if ($starts.Count -eq 1 -and $starts[0].Groups['version'].Value -ne $ends[0].Groups['version'].Value) {
        throw "Contradictory workflow markers in $RelativePath"
    }
    if ($starts.Count -eq 1 -and $starts[0].Groups['version'].Value -notin @('6', '7')) {
        throw "Unsupported workflow marker in $RelativePath"
    }
}

function Set-ManagedBlock {
    param(
        [AllowEmptyString()][string]$Text,
        [string]$NewBlock,
        [switch]$LineComment
    )

    $normalized = ConvertTo-LfText $Text
    $v7 = Get-ManagedBlock $normalized 'new-project-setup:v7' -LineComment:$LineComment
    $v6 = Get-ManagedBlock $normalized 'new-project-setup:v6' -LineComment:$LineComment
    if ($v7 -and $v6) {
        throw 'Version-6 and version-7 managed blocks cannot coexist.'
    }
    $oldBlock = if ($v7) { $v7 } else { $v6 }
    if ($oldBlock) {
        return ConvertTo-LfText ($normalized.Remove($normalized.IndexOf($oldBlock, [StringComparison]::Ordinal), $oldBlock.Length).Insert($normalized.IndexOf($oldBlock, [StringComparison]::Ordinal), $NewBlock.TrimEnd("`n")))
    }
    if ($normalized.Length -eq 0) {
        return ConvertTo-LfText $NewBlock
    }
    return ConvertTo-LfText ($normalized.TrimEnd("`n") + "`n`n" + $NewBlock.TrimEnd("`n"))
}

function New-MarkerBlock {
    param(
        [string]$Marker,
        [string[]]$Lines,
        [switch]$LineComment
    )

    $start = if ($LineComment) { "# ${Marker}:start" } else { "<!-- ${Marker}:start -->" }
    $end = if ($LineComment) { "# ${Marker}:end" } else { "<!-- ${Marker}:end -->" }
    return ConvertTo-LfText ((@($start) + $Lines + @($end)) -join "`n")
}

function Test-ExactGitRoot {
    param([string]$Root)

    $gitRoot = & git -C $Root rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $false
    }
    $actual = [IO.Path]::GetFullPath(($gitRoot | Select-Object -First 1).Trim())
    return $actual.Equals($Root, $PathComparison)
}

function Assert-V7State {
    param([object]$State)

    if ($null -eq $State -or $State -is [Array] -or
        $State.format -isnot [int] -and $State.format -isnot [long] -or
        $State.workflow_version -isnot [int] -and $State.workflow_version -isnot [long] -or
        [int]$State.format -ne $StateFormat -or [int]$State.workflow_version -ne $WorkflowVersion) {
        throw 'The existing version-7 state identity is invalid.'
    }
    $leanTop = @('format', 'managed_blocks', 'managed_files', 'text_eol', 'workflow_version')
    $oldTop = @('continuity_paths') + $leanTop
    $actualTop = @($State.PSObject.Properties.Name | Sort-Object)
    $isLean = ($actualTop -join '|') -ceq (($leanTop | Sort-Object) -join '|')
    $isLegacyV7State = ($actualTop -join '|') -ceq (($oldTop | Sort-Object) -join '|')
    if (-not $isLean -and -not $isLegacyV7State) {
        throw 'The existing version-7 state has unexpected fields.'
    }
    if ($State.text_eol -isnot [string] -or $State.text_eol -cne 'lf') {
        throw 'The existing version-7 text policy is invalid.'
    }
    $expectedBlocks = @('.gitattributes', '.gitignore', 'AGENTS.md')
    Assert-ExactPropertySet -Value $State.managed_blocks -Expected $expectedBlocks -Description 'Existing version-7 managed-block ownership'
    $actualBlocks = @($State.managed_blocks.PSObject.Properties.Name | Sort-Object)
    if (($actualBlocks -join '|') -ne (($expectedBlocks | Sort-Object) -join '|')) {
        throw 'The existing version-7 managed-block ownership is invalid.'
    }
    foreach ($relativePath in $expectedBlocks) {
        $record = $State.managed_blocks.PSObject.Properties[$relativePath].Value
        Assert-ExactPropertySet -Value $record -Expected @('marker', 'sha256') -Description "Existing version-7 managed-block record $relativePath"
        if ($record.marker -isnot [string] -or $record.marker -cne 'new-project-setup:v7' -or
            $record.sha256 -isnot [string] -or $record.sha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw "The existing version-7 managed-block record is invalid: $relativePath"
        }
    }
    $expectedFiles = @(
        '.codex/new-project-setup/execution-and-continuity.md',
        '.codex/new-project-setup/local-saving.md',
        'scripts/save-local-work.ps1'
    )
    Assert-ExactPropertySet -Value $State.managed_files -Expected $expectedFiles -Description 'Existing version-7 managed-file ownership'
    $actualFiles = @($State.managed_files.PSObject.Properties.Name | Sort-Object)
    if (($actualFiles -join '|') -ne (($expectedFiles | Sort-Object) -join '|')) {
        throw 'The existing version-7 managed-file ownership is invalid.'
    }
    foreach ($relativePath in $expectedFiles) {
        $hash = $State.managed_files.PSObject.Properties[$relativePath].Value
        if ($hash -isnot [string] -or $hash -cnotmatch '^[0-9a-f]{64}$') {
            throw "The existing version-7 managed-file ownership is invalid: $relativePath"
        }
    }
    if ($isLegacyV7State) {
        Assert-ExactPropertySet -Value $State.continuity_paths -Expected @('project_summary', 'handoff', 'development_log') -Description 'Legacy version-7 continuity_paths'
        if ($State.continuity_paths.project_summary -cne 'docs/project-summary.md' -or
            $State.continuity_paths.handoff -cne 'docs/codex-handoff.md' -or
            $State.continuity_paths.development_log -cne 'docs/development-log.md') {
            throw 'The legacy version-7 continuity_paths value is invalid.'
        }
        return 'v7-reconcile'
    }
    return 'v7'
}

function New-Snapshot {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return [pscustomobject]@{ Exists = $true; Bytes = Get-FileBytes $Path }
    }
    if (Test-Path -LiteralPath $Path) {
        throw "Managed target is not a regular file: $Path"
    }
    return [pscustomobject]@{ Exists = $false; Bytes = $null }
}

function Test-SnapshotMatches {
    param(
        [string]$Path,
        [object]$Snapshot
    )

    if (-not $Snapshot.Exists) {
        return -not (Test-Path -LiteralPath $Path)
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    return (Get-FileHashLower $Path) -eq (Get-BytesHash $Snapshot.Bytes)
}

function Write-AtomicBytes {
    param(
        [string]$Path,
        [byte[]]$Bytes
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $temp = Join-Path $parent ('.nps7-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllBytes($temp, $Bytes)
        Move-Item -LiteralPath $temp -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temp) {
            Remove-Item -LiteralPath $temp -Force
        }
    }
}

function Restore-Snapshot {
    param(
        [string]$Path,
        [object]$Snapshot
    )

    if ($Snapshot.Exists) {
        Write-AtomicBytes -Path $Path -Bytes $Snapshot.Bytes
    } elseif (Test-Path -LiteralPath $Path -PathType Leaf) {
        Remove-Item -LiteralPath $Path -Force
    }
}

function Remove-EmptyManagedParents {
    param(
        [string]$Root,
        [string]$Path
    )

    $parent = Split-Path -Parent $Path
    while ($parent -and -not $parent.Equals($Root, $PathComparison)) {
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            $parent = Split-Path -Parent $parent
            continue
        }
        if (@(Get-ChildItem -LiteralPath $parent -Force).Count -ne 0) {
            break
        }
        Remove-Item -LiteralPath $parent -Force
        $parent = Split-Path -Parent $parent
    }
}

function Test-Fault {
    param([string]$Name)

    if ($testFault -eq $Name) {
        throw "Injected version-7 apply fault: $Name"
    }
}

if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) {
    throw 'Git is required for workflow version 7.'
}
if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "Project root does not exist: $ProjectRoot"
}

$inputRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$rootItem = Get-Item -LiteralPath $inputRoot -Force
if ((Get-PathItemClassification $rootItem) -cin @('redirected', 'unknown')) {
    throw 'The project root cannot be a redirected path.'
}
$resolvedRoot = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $inputRoot).Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)

$lockHash = Get-TextHash $resolvedRoot.ToLowerInvariant()
$lockPath = Join-Path ([IO.Path]::GetTempPath()) "new-project-setup-v7-$lockHash.lock"
$lock = $null
$stageRoot = $null
$createdGit = $false
try {
    try {
        $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch {
        throw 'Another project-setup operation is active for this project.'
    }

    $stateRelative = '.codex/new-project-setup.json'
    $statePath = Get-ContainedTargetPath $resolvedRoot $stateRelative
    $stateItem = Assert-OrdinaryFileOrMissing -Path $statePath -Description 'Workflow state path'
    $existingStateBytes = if ($null -ne $stateItem) { Get-FileBytes $statePath } else { $null }
    $existingState = if ($null -ne $stateItem) { Read-JsonFile $statePath } else { $null }
    $mode = 'fresh'
    if ($existingState) {
        $identityFormat = $existingState.PSObject.Properties['format']
        $identityVersion = $existingState.PSObject.Properties['workflow_version']
        if ($null -ne $identityVersion -and ($identityVersion.Value -is [int] -or $identityVersion.Value -is [long])) {
            if ([int]$identityVersion.Value -eq 7) {
                $mode = Assert-V7State $existingState
            } elseif ([int]$identityVersion.Value -eq 6) {
                $mode = 'v6-migration'
            } else {
                throw 'Only a managed version-6 target or valid version-7 target can be updated.'
            }
        } else {
            throw 'The existing workflow state identity is malformed.'
        }
        if ($mode -eq 'v6-migration' -and
            ($null -eq $identityFormat -or ($identityFormat.Value -isnot [int] -and $identityFormat.Value -isnot [long]) -or [int]$identityFormat.Value -ne 2)) {
            throw 'The existing version-6 workflow state identity is malformed.'
        }
    }

    $sourceFiles = [ordered]@{
        '.codex/new-project-setup/execution-and-continuity.md' = Join-Path $skillRoot 'references/execution-and-continuity.md'
        '.codex/new-project-setup/local-saving.md' = Join-Path $skillRoot 'references/local-saving.md'
        'scripts/save-local-work.ps1' = Join-Path $skillRoot 'scripts/save-local-work.ps1'
    }
    foreach ($source in @($sourceFiles.Values)) {
        $sourceItem = Assert-OrdinaryFileOrMissing -Path $source -Description 'Workflow source file'
        if ($null -eq $sourceItem) {
            throw "Workflow source file is missing: $source"
        }
    }

    $agentsSource = Join-Path $skillRoot 'templates/agents-workflow-block.md'
    $summarySource = Join-Path $skillRoot 'templates/project-summary.md'
    $handoffSource = Join-Path $skillRoot 'templates/codex-handoff.md'
    foreach ($source in @($agentsSource, $summarySource, $handoffSource)) {
        $sourceItem = Assert-OrdinaryFileOrMissing -Path $source -Description 'Workflow template'
        if ($null -eq $sourceItem) {
            throw "Workflow template is missing: $source"
        }
    }

    $v6Contract = Get-FrozenV6Contract
    if ($mode -eq 'v6-migration') {
        Assert-V6MigrationCandidate -State $existingState -Root $resolvedRoot -Contract $v6Contract
    }

    $warnings = [Collections.Generic.List[object]]::new()
    $legacyHelperRecords = [Collections.Generic.List[object]]::new()
    $migrationExportRelative = '.codex/migrations/new-project-setup-v6-github.local.json'
    $migrationExportPath = $null
    if ($mode -eq 'v6-migration') {
        $migrationExportPath = Get-ContainedTargetPath $resolvedRoot $migrationExportRelative
        if ($null -ne (Get-ExistingPathItem $migrationExportPath)) {
            throw "The one-time migration export path is already occupied: $migrationExportRelative"
        }

        $declaredHelpers = $existingState.managed_helpers
        foreach ($relativePath in @($v6Contract.LegacyHelperHashes.Keys | Sort-Object)) {
            $target = Get-ContainedTargetPath $resolvedRoot $relativePath
            $targetItem = Assert-OrdinaryFileOrMissing -Path $target -Description "Legacy helper path $relativePath"
            $declaredProperty = $declaredHelpers.PSObject.Properties[$relativePath]
            $declaredHash = if ($null -ne $declaredProperty -and $null -ne $declaredProperty.Value) { ([string]$declaredProperty.Value).ToLowerInvariant() } else { $null }
            $recognizedHash = [string]$v6Contract.LegacyHelperHashes[$relativePath]
            $declarationRecognized = $null -ne $declaredHash -and $declaredHash -ceq $recognizedHash
            $actualHash = if ($null -ne $targetItem) { Get-FileHashLower $target } else { $null }
            $disposition = if ($null -eq $targetItem) {
                'missing'
            } elseif ($declarationRecognized -and $actualHash -ceq $declaredHash) {
                'owned_exact'
            } elseif ($declarationRecognized) {
                'modified_preserved'
            } else {
                'unowned_preserved'
            }
            $legacyHelperRecords.Add([pscustomobject][ordered]@{
                path = $relativePath
                disposition = $disposition
                declared_sha256 = $declaredHash
                actual_sha256 = $actualHash
            })
            switch ($disposition) {
                'modified_preserved' {
                    $warnings.Add((New-Stage4Warning 'legacy_helper_modified_preserved' $relativePath 'Preserved the modified legacy helper byte-for-byte; version 7 does not manage or execute it.'))
                }
                'unowned_preserved' {
                    $warnings.Add((New-Stage4Warning 'legacy_helper_unowned_preserved' $relativePath 'Preserved the unowned legacy helper byte-for-byte; version 7 does not manage or execute it.'))
                }
                'missing' {
                    $warnings.Add((New-Stage4Warning 'legacy_helper_missing' $relativePath 'The legacy helper is absent; version 7 does not create or manage it.'))
                }
            }
        }
    }

    $agentsBlock = ConvertTo-LfText (Get-Content -Raw -LiteralPath $agentsSource)
    if (-not $agentsBlock.Contains('<!-- new-project-setup:v7:start -->') -or -not $agentsBlock.Contains('<!-- new-project-setup:v7:end -->')) {
        throw 'The workflow AGENTS.md template has invalid markers.'
    }
    $ignoreBlock = New-MarkerBlock 'new-project-setup:v7' @(
        '# Machine-local private documentation',
        '*.local.md',
        '.github-backup.local.json',
        '.codex/migrations/new-project-setup-v6-github.local.json',
        '',
        '# Generated dependencies and build output',
        'node_modules/',
        '.venv/',
        'venv/',
        '__pycache__/',
        '*.py[cod]',
        'dist/',
        'build/',
        'out/',
        '.next/',
        'coverage/',
        'test-artifacts/',
        'playwright-report/',
        '.pytest_cache/',
        '.mypy_cache/',
        '.DS_Store',
        'Thumbs.db'
    ) -LineComment
    $attributesBlock = New-MarkerBlock 'new-project-setup:v7' @(
        '* text=auto',
        '*.md text eol=lf',
        '*.json text eol=lf',
        '*.yaml text eol=lf',
        '*.yml text eol=lf',
        '*.ps1 text eol=lf',
        '*.psm1 text eol=lf',
        '*.psd1 text eol=lf',
        '*.sh text eol=lf',
        '*.cmd text eol=crlf',
        '*.bat text eol=crlf'
    ) -LineComment
    $managedBlocks = [ordered]@{
        'AGENTS.md' = $agentsBlock
        '.gitignore' = $ignoreBlock
        '.gitattributes' = $attributesBlock
    }

    $desiredBytes = [ordered]@{}
    foreach ($entry in $managedBlocks.GetEnumerator()) {
        $target = Get-ContainedTargetPath $resolvedRoot $entry.Key
        $current = if (Test-Path -LiteralPath $target -PathType Leaf) { ConvertTo-LfText (Get-Content -Raw -LiteralPath $target) } else { '' }
        Assert-NoUnexpectedWorkflowMarkers -Text $current -RelativePath $entry.Key
        $lineComment = $entry.Key -ne 'AGENTS.md'
        $v7Block = Get-ManagedBlock $current 'new-project-setup:v7' -LineComment:$lineComment
        $v6Block = Get-ManagedBlock $current 'new-project-setup:v6' -LineComment:$lineComment

        if ($mode -eq 'fresh' -and ($v6Block -or $v7Block)) {
            throw "Managed markers exist without matching state in $($entry.Key)."
        }
        if ($mode -eq 'v6-migration' -and -not $v6Block) {
            throw "Managed version-6 block is missing from $($entry.Key)."
        }
        if ($mode -in @('v7', 'v7-reconcile')) {
            if (-not $v7Block) {
                throw "Managed version-7 block is missing from $($entry.Key)."
            }
            $stateBlock = $existingState.managed_blocks.PSObject.Properties[$entry.Key]
            if (-not $stateBlock -or $stateBlock.Value.marker -ne 'new-project-setup:v7') {
                throw "Managed block ownership is missing for $($entry.Key)."
            }
            if ((Get-TextHash $v7Block) -ne ([string]$stateBlock.Value.sha256).ToLowerInvariant()) {
                throw "Managed block was modified: $($entry.Key)"
            }
        }
        $desiredBytes[$entry.Key] = Get-TextBytes (Set-ManagedBlock -Text $current -NewBlock $entry.Value -LineComment:$lineComment)
    }

    $managedFileHashes = [ordered]@{}
    foreach ($entry in $sourceFiles.GetEnumerator()) {
        $sourceText = ConvertTo-LfText (Get-Content -Raw -LiteralPath $entry.Value)
        $bytes = Get-TextBytes $sourceText
        $sourceHash = Get-BytesHash $bytes
        $target = Get-ContainedTargetPath $resolvedRoot $entry.Key
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $currentHash = Get-FileHashLower $target
            if ($mode -in @('v7', 'v7-reconcile')) {
                $stateHashProperty = $existingState.managed_files.PSObject.Properties[$entry.Key]
                if (-not $stateHashProperty -or $currentHash -ne ([string]$stateHashProperty.Value).ToLowerInvariant()) {
                    throw "Managed file was modified: $($entry.Key)"
                }
            } elseif ($currentHash -ne $sourceHash) {
                throw "Managed path is occupied by an unowned file: $($entry.Key)"
            }
        }
        $desiredBytes[$entry.Key] = $bytes
        $managedFileHashes[$entry.Key] = $sourceHash
    }

    $continuityTemplates = [ordered]@{
        'docs/project-summary.md' = $summarySource
        'docs/codex-handoff.md' = $handoffSource
    }
    foreach ($entry in $continuityTemplates.GetEnumerator()) {
        $target = Get-ContainedTargetPath $resolvedRoot $entry.Key
        $targetItem = Assert-OrdinaryFileOrMissing -Path $target -Description "Continuity path $($entry.Key)"
        if ($null -eq $targetItem -or $targetItem.Length -eq 0) {
            $desiredBytes[$entry.Key] = Get-TextBytes (Get-Content -Raw -LiteralPath $entry.Value)
        } elseif ($entry.Key -ceq 'docs/codex-handoff.md' -and $mode -eq 'v6-migration') {
            $currentHandoff = ConvertTo-LfText (Get-Content -Raw -LiteralPath $target)
            $v7Handoff = ConvertTo-LfText (Get-Content -Raw -LiteralPath $entry.Value)
            if ($currentHandoff -ceq $v6Contract.Handoff) {
                $desiredBytes[$entry.Key] = Get-TextBytes $v7Handoff
            } elseif ($currentHandoff -cne $v7Handoff) {
                $warnings.Add((New-Stage4Warning 'handoff_preserved_existing' $entry.Key 'Preserved the existing customized handoff byte-for-byte during version-6 migration.'))
            }
        }
    }

    $stateObject = [ordered]@{
        format = $StateFormat
        workflow_version = $WorkflowVersion
        managed_blocks = [ordered]@{
            'AGENTS.md' = [ordered]@{ marker = 'new-project-setup:v7'; sha256 = Get-TextHash $agentsBlock }
            '.gitignore' = [ordered]@{ marker = 'new-project-setup:v7'; sha256 = Get-TextHash $ignoreBlock }
            '.gitattributes' = [ordered]@{ marker = 'new-project-setup:v7'; sha256 = Get-TextHash $attributesBlock }
        }
        managed_files = $managedFileHashes
        text_eol = 'lf'
    }
    $stateText = ConvertTo-LfText ($stateObject | ConvertTo-Json -Depth 10)
    $desiredBytes[$stateRelative] = Get-TextBytes $stateText

    $sortedWarnings = @($warnings | Sort-Object code, path)
    if ($mode -eq 'v6-migration') {
        $githubKeys = @(
            'github_mode', 'repository', 'remote', 'source_authority', 'helper_ownership',
            'source_history_sync', 'precommit_audit', 'precommit_attestation',
            'normal_history_audit', 'public_readiness_audit', 'sync_cadence',
            'focused_sync_commit_threshold', 'focused_sync_time_trigger',
            'source_history_recovery', 'legacy_history_preservation', 'recovery_destination',
            'recovery_retry', 'audit_failure_action'
        )
        $githubState = [ordered]@{}
        foreach ($key in $githubKeys) { $githubState[$key] = $existingState.PSObject.Properties[$key].Value }
        $exportObject = [ordered]@{
            format = 1
            migration = 'new-project-setup-v6-github'
            source_workflow_version = 6
            target_workflow_version = 7
            created_utc = [DateTimeOffset]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'", [Globalization.CultureInfo]::InvariantCulture)
            source_state_sha256 = Get-BytesHash $existingStateBytes
            github_state = $githubState
            legacy_helpers = [object[]]@($legacyHelperRecords)
            warnings = [object[]]@($sortedWarnings)
        }
        $desiredBytes[$migrationExportRelative] = Get-TextBytes (ConvertTo-LfText ($exportObject | ConvertTo-Json -Depth 10))
    }

    $snapshots = [ordered]@{}
    $changes = [Collections.Generic.List[string]]::new()
    foreach ($relativePath in $desiredBytes.Keys) {
        $target = Get-ContainedTargetPath $resolvedRoot $relativePath
        $snapshots[$relativePath] = New-Snapshot $target
        $desiredHash = Get-BytesHash $desiredBytes[$relativePath]
        $currentHash = if ($snapshots[$relativePath].Exists) { Get-BytesHash $snapshots[$relativePath].Bytes } else { $null }
        if ($desiredHash -ne $currentHash) {
            $changes.Add($relativePath)
        }
    }

    $hasExactGitRoot = Test-ExactGitRoot $resolvedRoot
    if (-not $hasExactGitRoot) {
        $changes.Add('.git/')
    }

    $stageRoot = Join-Path ([IO.Path]::GetTempPath()) ('new-project-setup-v7-stage-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stageRoot | Out-Null
    foreach ($relativePath in $desiredBytes.Keys) {
        $stagePath = Join-Path $stageRoot $relativePath
        $stageParent = Split-Path -Parent $stagePath
        if (-not (Test-Path -LiteralPath $stageParent -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $stageParent | Out-Null
        }
        [IO.File]::WriteAllBytes($stagePath, $desiredBytes[$relativePath])
        if ((Get-FileHashLower $stagePath) -ne (Get-BytesHash $desiredBytes[$relativePath])) {
            throw "Staged workflow payload failed validation: $relativePath"
        }
    }
    Test-Fault 'v7-apply-after-stage'

    if ($Check) {
        [pscustomobject]@{
            outcome = if ($changes.Count -eq 0) { 'current' } else { 'changes-required' }
            workflow_version = 7
            mode = $mode
            changes = @($changes)
            warnings = [object[]]@($sortedWarnings)
        } | ConvertTo-Json -Compress
        if ($changes.Count -eq 0) { exit 0 } else { exit 2 }
    }

    $applied = [Collections.Generic.List[string]]::new()
    try {
        foreach ($relativePath in $changes) {
            if ($relativePath -eq '.git/') {
                continue
            }
            $target = Get-ContainedTargetPath $resolvedRoot $relativePath
            if (-not (Test-SnapshotMatches -Path $target -Snapshot $snapshots[$relativePath])) {
                throw "Managed target changed after preflight: $relativePath"
            }
            $applied.Add($relativePath)
            Write-AtomicBytes -Path $target -Bytes $desiredBytes[$relativePath]
            if ($applied.Count -eq 1) {
                Test-Fault 'v7-apply-after-first-replace'
            }
            if ($relativePath -ceq $migrationExportRelative) {
                Test-Fault 'v7-apply-after-migration-export'
            }
        }
        Test-Fault 'v7-apply-before-final-validation'

        foreach ($relativePath in $desiredBytes.Keys) {
            $target = Get-ContainedTargetPath $resolvedRoot $relativePath
            if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or (Get-FileHashLower $target) -ne (Get-BytesHash $desiredBytes[$relativePath])) {
                throw "Final workflow payload validation failed: $relativePath"
            }
        }

        if (-not $hasExactGitRoot) {
            if (Test-Path -LiteralPath (Join-Path $resolvedRoot '.git')) {
                throw 'Git state changed after workflow preflight.'
            }
            & git -C $resolvedRoot init --quiet
            $createdGit = Test-Path -LiteralPath (Join-Path $resolvedRoot '.git') -PathType Container
            if ($LASTEXITCODE -ne 0 -or -not $createdGit -or -not (Test-ExactGitRoot $resolvedRoot)) {
                throw 'Git initialization failed for the exact project root.'
            }
        }

        if ($mode -eq 'v6-migration') {
            & git -C $resolvedRoot check-ignore --quiet -- $migrationExportRelative *> $null
            if ($LASTEXITCODE -ne 0) {
                throw 'The private migration export could not be proved ignored by Git.'
            }
        }
    } catch {
        $originalFailure = $_.Exception.Message
        $rollbackUnsafe = [Collections.Generic.List[string]]::new()
        $rollbackPaths = @($applied)
        [array]::Reverse($rollbackPaths)
        foreach ($relativePath in $rollbackPaths) {
            $target = Get-ContainedTargetPath $resolvedRoot $relativePath
            if (Test-SnapshotMatches -Path $target -Snapshot $snapshots[$relativePath]) {
                if (-not $snapshots[$relativePath].Exists) {
                    Remove-EmptyManagedParents -Root $resolvedRoot -Path $target
                }
                continue
            }
            if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or (Get-FileHashLower $target) -ne (Get-BytesHash $desiredBytes[$relativePath])) {
                $rollbackUnsafe.Add($relativePath)
                continue
            }
            Restore-Snapshot -Path $target -Snapshot $snapshots[$relativePath]
            if (-not $snapshots[$relativePath].Exists) {
                Remove-EmptyManagedParents -Root $resolvedRoot -Path $target
            }
        }
        if ($createdGit) {
            $gitPath = Join-Path $resolvedRoot '.git'
            if (Test-Path -LiteralPath $gitPath -PathType Container) {
                Remove-Item -LiteralPath $gitPath -Recurse -Force
            }
        }
        if ($rollbackUnsafe.Count -gt 0) {
            throw "Workflow apply failed and externally changed targets were preserved; cleanup is required for: $($rollbackUnsafe -join ', '). Original failure: $originalFailure"
        }
        throw
    }

    [pscustomobject]@{
        outcome = if ($changes.Count -eq 0) { 'current' } else { 'applied' }
        workflow_version = 7
        mode = $mode
        changes = @($changes)
        warnings = [object[]]@($sortedWarnings)
    } | ConvertTo-Json -Compress
    exit 0
} finally {
    if ($stageRoot -and (Test-Path -LiteralPath $stageRoot)) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force
    }
    if ($lock) {
        $lock.Dispose()
    }
}
