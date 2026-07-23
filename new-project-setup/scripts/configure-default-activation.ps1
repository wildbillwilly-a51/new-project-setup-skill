#requires -Version 7.6

[CmdletBinding(DefaultParameterSetName = 'Set')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Set')]
    [ValidateSet('Automatic', 'Manual')]
    [string]$Mode,

    [Parameter(Mandatory = $true, ParameterSetName = 'Status')]
    [switch]$Status,

    [string]$CodexHome
)

$ErrorActionPreference = 'Stop'
$marker = 'new-project-setup:automatic-default'
$startMarker = "<!-- ${marker}:start -->"
$endMarker = "<!-- ${marker}:end -->"

function Get-DefaultCodexHome {
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        return $env:CODEX_HOME
    }
    $profile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    if ([string]::IsNullOrWhiteSpace($profile)) {
        throw 'Unable to resolve the user profile for the default Codex home.'
    }
    return (Join-Path $profile '.codex')
}

function Assert-OrdinaryItem {
    param([string]$Path, [string]$Label, [switch]$Directory)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    if ($Directory -and -not $item.PSIsContainer) { throw "$Label is not a directory: $Path" }
    if (-not $Directory -and $item.PSIsContainer) { throw "$Label is not a file: $Path" }
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label must not be a symbolic link, junction, or redirected path: $Path"
    }
}

function Get-FileFingerprint {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'absent' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-Utf8File {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ Text = ''; HasBom = $false }
    }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $offset = if ($hasBom) { 3 } else { 0 }
    $encoding = [Text.UTF8Encoding]::new($false, $true)
    try {
        $text = $encoding.GetString($bytes, $offset, $bytes.Length - $offset)
    }
    catch {
        throw "Global AGENTS.md must be valid UTF-8: $Path"
    }
    return [pscustomobject]@{ Text = $text; HasBom = $hasBom }
}

function Get-NewLine {
    param([AllowEmptyString()][string]$Text)
    if ($Text.Contains("`r`n", [StringComparison]::Ordinal)) { return "`r`n" }
    if ($Text.Contains("`n", [StringComparison]::Ordinal)) { return "`n" }
    return [Environment]::NewLine
}

function Get-ManagedBlock {
    param([AllowEmptyString()][string]$Text)
    $starts = [regex]::Matches($Text, [regex]::Escape($startMarker))
    $ends = [regex]::Matches($Text, [regex]::Escape($endMarker))
    if ($starts.Count -ne $ends.Count -or $starts.Count -gt 1) {
        throw 'The global automatic-activation markers are malformed or duplicated.'
    }
    if ($starts.Count -eq 0) { return $null }
    if ($ends[0].Index -lt $starts[0].Index) {
        throw 'The global automatic-activation markers are in the wrong order.'
    }
    $length = ($ends[0].Index + $endMarker.Length) - $starts[0].Index
    $block = $Text.Substring($starts[0].Index, $length)
    $metadata = [regex]::Match($block, '<!-- new-project-setup:automatic-default:separator-newlines=(?<count>[012]) -->')
    if (-not $metadata.Success) {
        throw 'The global automatic-activation block has invalid boundary metadata.'
    }
    return [pscustomobject]@{
        Index = $starts[0].Index
        Length = $length
        Text = $block
        SeparatorNewLines = [int]$metadata.Groups['count'].Value
    }
}

function New-AutomaticBlock {
    param([string]$NewLine, [int]$SeparatorNewLines)
    return @(
        $startMarker
        "<!-- ${marker}:separator-newlines=$SeparatorNewLines -->"
        '## New Project Setup Automatic Default'
        ''
        'The user opted into automatic activation of the `new-project-setup` skill.'
        ''
        '- Before meaningful implementation in a Git repository, check for `.codex/new-project-setup.json`.'
        '- When that state is absent, invoke the installed `new-project-setup` skill for exactly that repository before implementation.'
        '- Read-only consultation, explanation, review, and clearly disposable temporary work do not trigger setup.'
        '- Never scan or update sibling repositories, configure a remote, push, publish, or deploy as part of automatic activation.'
        '- When workflow state already exists, follow the project workflow without routinely reinstalling it.'
        '- Protected or materially out-of-scope actions still require their normal authorization.'
        $endMarker
    ) -join $NewLine
}

function Write-AtomicUtf8 {
    param(
        [string]$Path,
        [AllowEmptyString()][string]$Text,
        [bool]$HasBom,
        [string]$ExpectedFingerprint
    )
    if ((Get-FileFingerprint $Path) -cne $ExpectedFingerprint) {
        throw 'Global AGENTS.md changed concurrently; no activation change was written.'
    }
    $encoding = [Text.UTF8Encoding]::new($false)
    $content = $encoding.GetBytes($Text)
    if ($HasBom) {
        $bytes = [byte[]]::new($content.Length + 3)
        $bytes[0] = 0xEF; $bytes[1] = 0xBB; $bytes[2] = 0xBF
        [Array]::Copy($content, 0, $bytes, 3, $content.Length)
    }
    else {
        $bytes = $content
    }
    $parent = Split-Path -Parent $Path
    $temporary = Join-Path $parent ('.AGENTS.md.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllBytes($temporary, $bytes)
        [IO.File]::Move($temporary, $Path, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

if ([string]::IsNullOrWhiteSpace($CodexHome)) { $CodexHome = Get-DefaultCodexHome }
$homePath = [IO.Path]::GetFullPath($CodexHome)
$agentsPath = Join-Path $homePath 'AGENTS.md'
Assert-OrdinaryItem $homePath 'Codex home' -Directory
Assert-OrdinaryItem $agentsPath 'Global AGENTS.md'

$initialFingerprint = Get-FileFingerprint $agentsPath
$file = Read-Utf8File $agentsPath
$text = [string]$file.Text
$newLine = Get-NewLine $text
$existing = Get-ManagedBlock $text
$currentMode = if ($null -eq $existing) { 'manual' } else { 'automatic' }

if ($Status) {
    [ordered]@{
        outcome = 'status'
        mode = $currentMode
        agents_path = $agentsPath
        managed_block_present = $null -ne $existing
    } | ConvertTo-Json -Compress
    exit 0
}

if ($Mode -ceq 'Automatic') {
    if (-not (Test-Path -LiteralPath $homePath)) {
        New-Item -ItemType Directory -Path $homePath | Out-Null
        Assert-OrdinaryItem $homePath 'Codex home' -Directory
    }
    if ($null -eq $existing) {
        $separatorCount = if ($text.Length -eq 0) { 0 } elseif ($text.EndsWith($newLine, [StringComparison]::Ordinal)) { 1 } else { 2 }
        $block = New-AutomaticBlock -NewLine $newLine -SeparatorNewLines $separatorCount
        $newText = $text + ($newLine * $separatorCount) + $block + $newLine
    }
    else {
        $block = New-AutomaticBlock -NewLine $newLine -SeparatorNewLines $existing.SeparatorNewLines
        $newText = $text.Remove($existing.Index, $existing.Length).Insert($existing.Index, $block)
    }
    $outcome = if ($newText -ceq $text) { 'unchanged' } elseif ($null -eq $existing) { 'enabled' } else { 'updated' }
    if ($newText -cne $text) {
        Write-AtomicUtf8 -Path $agentsPath -Text $newText -HasBom ([bool]$file.HasBom) -ExpectedFingerprint $initialFingerprint
    }
    [ordered]@{ outcome = $outcome; mode = 'automatic'; agents_path = $agentsPath; managed_block_present = $true } | ConvertTo-Json -Compress
    exit 0
}

if ($null -eq $existing) {
    [ordered]@{ outcome = 'unchanged'; mode = 'manual'; agents_path = $agentsPath; managed_block_present = $false } | ConvertTo-Json -Compress
    exit 0
}

$prefix = $text.Substring(0, $existing.Index)
$separator = $newLine * $existing.SeparatorNewLines
if ($separator.Length -gt 0) {
    if (-not $prefix.EndsWith($separator, [StringComparison]::Ordinal)) {
        throw 'The global automatic-activation boundary changed unexpectedly; no activation change was written.'
    }
    $prefix = $prefix.Substring(0, $prefix.Length - $separator.Length)
}
$suffix = $text.Substring($existing.Index + $existing.Length)
if ($suffix.StartsWith($newLine, [StringComparison]::Ordinal)) {
    $suffix = $suffix.Substring($newLine.Length)
}
if ($prefix.Length -gt 0 -and $suffix.Length -gt 0 -and
    -not $prefix.EndsWith($newLine, [StringComparison]::Ordinal) -and
    -not $suffix.StartsWith($newLine, [StringComparison]::Ordinal)) {
    $suffix = $newLine + $suffix
}
$newText = $prefix + $suffix
Write-AtomicUtf8 -Path $agentsPath -Text $newText -HasBom ([bool]$file.HasBom) -ExpectedFingerprint $initialFingerprint
[ordered]@{ outcome = 'disabled'; mode = 'manual'; agents_path = $agentsPath; managed_block_present = $false } | ConvertTo-Json -Compress
