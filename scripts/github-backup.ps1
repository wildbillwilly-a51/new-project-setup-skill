[CmdletBinding()]
param(
    [string]$ProjectRoot = ".",
    [string]$ConfigPath = ".github-backup.json",
    [string]$Repository,
    [string]$RemoteName = "github-backup",
    [switch]$ScanOnly,
    [switch]$AuditSourceHistory
)

$ErrorActionPreference = "Stop"
$BackupFormat = 2
$BackupAuthorName = "Codex Sanitized Backup"
$BackupAuthorEmail = "codex-sanitized-backup@users.noreply.github.com"
$MaxTextBytes = 5MB
$RegexTimeout = [TimeSpan]::FromSeconds(2)

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
    finally {
        $ErrorActionPreference = $previousPreference
    }

    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "$Command failed with exit code ${exitCode}: $($output -join [Environment]::NewLine)"
    }

    return [pscustomobject]@{ ExitCode = $exitCode; Output = @($output) }
}

function Convert-GlobToRegex {
    param([Parameter(Mandatory = $true)][string]$Glob)

    $normalized = $Glob.Replace('\', '/').TrimStart('/')
    $escaped = [Regex]::Escape($normalized)
    $escaped = $escaped.Replace('\*\*/', '(?:.*/)?').Replace('\*\*', '.*')
    $escaped = $escaped.Replace('\*', '[^/]*').Replace('\?', '[^/]')
    return "^${escaped}$"
}

function Test-GlobMatch {
    param([string]$Path, [string]$Glob)
    return $Path -match (Convert-GlobToRegex -Glob $Glob)
}

function Get-Sha256Bytes {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-Sha256Text {
    param([Parameter(Mandatory = $true)][string]$Value)
    return Get-Sha256Bytes -Bytes ([Text.Encoding]::UTF8.GetBytes($Value))
}

function Get-RepositoryFromUrl {
    param([Parameter(Mandatory = $true)][string]$Url)

    if ($Url -match '^(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+/[^/]+?)(?:\.git)?$') {
        return $Matches[1]
    }
    return $null
}

function New-CompiledRegex {
    param([string]$Id, [string]$Pattern)

    try {
        $compiled = [Regex]::new(
            $Pattern,
            [Text.RegularExpressions.RegexOptions]::CultureInvariant,
            $RegexTimeout
        )
    }
    catch {
        throw "Invalid confidential scan rule ${Id}: $($_.Exception.Message)"
    }
    return [pscustomobject]@{ Id = $Id; Regex = $compiled; Pattern = $Pattern }
}

function Get-ScanRules {
    param([object[]]$CustomRules)

    $rules = @(
        (New-CompiledRegex 'private-key' '-----BEGIN (?:RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----'),
        (New-CompiledRegex 'bearer-token' '(?i)authorization\s*[:=]\s*["'']?bearer\s+[A-Za-z0-9._~+/=-]{8,}'),
        (New-CompiledRegex 'credential-assignment' '(?i)(?:api[_-]?key|client[_-]?secret|password|passwd|token|secret)\s*[:=]\s*["'']?(?!example|placeholder|replace|changeme)[A-Za-z0-9_./+=-]{8,}'),
        (New-CompiledRegex 'known-token-format' '(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16})'),
        (New-CompiledRegex 'connection-string' '(?i)(?:mongodb(?:\+srv)?|postgres(?:ql)?|mysql|redis|amqp)://[^\s"'']+:[^\s"'']+@'),
        (New-CompiledRegex 'private-network' '(?<!\d)(?:10(?:\.\d{1,3}){3}|192\.168(?:\.\d{1,3}){2}|172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2}|100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])(?:\.\d{1,3}){2})(?!\d)'),
        (New-CompiledRegex 'machine-user-path' '(?i)(?:[A-Z]:\\Users\\[^\\\r\n]+|/home/[^/\s]+|/Users/[^/\s]+)'),
        (New-CompiledRegex 'operational-endpoint' '(?i)(?:root@[A-Za-z0-9._-]+|/srv/[A-Za-z0-9._/-]+)'),
        (New-CompiledRegex 'git-lfs-pointer' '(?m)^version https://git-lfs\.github\.com/spec/v1\s*$')
    )

    foreach ($custom in @($CustomRules)) {
        if (-not $custom.id -or -not $custom.regex) {
            throw "Each confidential_patterns entry requires id and regex."
        }
        $rules += New-CompiledRegex -Id ([string]$custom.id) -Pattern ([string]$custom.regex)
    }
    return $rules
}

function Get-TextContent {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    if ($Bytes.Length -gt $MaxTextBytes) {
        return [pscustomobject]@{ Kind = 'oversize'; Content = $null }
    }
    if ($Bytes.Length -eq 0) {
        return [pscustomobject]@{ Kind = 'text'; Content = '' }
    }

    try {
        if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xff -and $Bytes[1] -eq 0xfe) {
            return [pscustomobject]@{ Kind = 'text'; Content = [Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2) }
        }
        if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xfe -and $Bytes[1] -eq 0xff) {
            return [pscustomobject]@{ Kind = 'text'; Content = [Text.Encoding]::BigEndianUnicode.GetString($Bytes, 2, $Bytes.Length - 2) }
        }
        if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xef -and $Bytes[1] -eq 0xbb -and $Bytes[2] -eq 0xbf) {
            return [pscustomobject]@{ Kind = 'text'; Content = [Text.UTF8Encoding]::new($false, $true).GetString($Bytes, 3, $Bytes.Length - 3) }
        }

        $sampleLength = [Math]::Min($Bytes.Length, 8192)
        $evenNull = 0
        $oddNull = 0
        for ($index = 0; $index -lt $sampleLength; $index++) {
            if ($Bytes[$index] -eq 0) {
                if ($index % 2 -eq 0) { $evenNull++ } else { $oddNull++ }
            }
        }
        if ($oddNull -gt ($sampleLength / 8) -and $evenNull -eq 0) {
            return [pscustomobject]@{ Kind = 'text'; Content = [Text.Encoding]::Unicode.GetString($Bytes) }
        }
        if ($evenNull -gt ($sampleLength / 8) -and $oddNull -eq 0) {
            return [pscustomobject]@{ Kind = 'text'; Content = [Text.Encoding]::BigEndianUnicode.GetString($Bytes) }
        }
        if ($evenNull + $oddNull -gt 0) {
            return [pscustomobject]@{ Kind = 'binary'; Content = $null }
        }

        return [pscustomobject]@{ Kind = 'text'; Content = [Text.UTF8Encoding]::new($false, $true).GetString($Bytes) }
    }
    catch {
        return [pscustomobject]@{ Kind = 'binary'; Content = $null }
    }
}

function Test-FingerprintedAllowance {
    param([object[]]$Entries, [string]$Rule, [string]$Path, [string]$Sha256)

    foreach ($entry in @($Entries)) {
        if ($entry.rule -eq $Rule -and $entry.sha256 -eq $Sha256 -and (Test-GlobMatch $Path ([string]$entry.path))) {
            return $true
        }
    }
    return $false
}

function Get-CommittedConfig {
    param([string]$RepoRoot, [string]$RelativePath)

    if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath.Replace('\', '/') -match '(^|/)\.\.(/|$)') {
        throw "ConfigPath must be a project-relative committed path."
    }
    $path = $RelativePath.Replace('\', '/').TrimStart('/')
    $defaults = [pscustomobject]@{
        repository = $null
        exclude = @()
        allow_findings = @()
        allow_binary = @()
        confidential_patterns = @()
    }

    $show = Invoke-External 'git' @('-C', $RepoRoot, 'show', "HEAD:$path") -AllowFailure
    if ($show.ExitCode -eq 0) {
        $loaded = ($show.Output -join [Environment]::NewLine) | ConvertFrom-Json
        foreach ($property in @('repository', 'exclude', 'allow_findings', 'allow_binary', 'confidential_patterns')) {
            if ($null -ne $loaded.$property) { $defaults.$property = $loaded.$property }
        }
    }

    $worktreePath = Join-Path $RepoRoot $path.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (Test-Path -LiteralPath $worktreePath) {
        $worktreeText = Get-Content -Raw -LiteralPath $worktreePath
        $committedText = if ($show.ExitCode -eq 0) { $show.Output -join [Environment]::NewLine } else { $null }
        if ($worktreeText.TrimEnd() -ne ([string]$committedText).TrimEnd()) {
            Write-Warning "Ignoring dirty or untracked $path; backup policy comes only from committed HEAD."
        }
    }
    return $defaults
}

function Get-TreeEntries {
    param([string]$RepoRoot, [string]$Commit)

    $result = Invoke-External 'git' @('-C', $RepoRoot, 'ls-tree', '-r', '--full-tree', $Commit)
    $entries = New-Object Collections.Generic.List[object]
    foreach ($line in $result.Output) {
        if ([string]$line -notmatch '^(\d+)\s+(blob|commit)\s+([0-9a-f]+)\t(.+)$') {
            throw "Unable to parse Git tree entry without risking an incomplete snapshot."
        }
        $entries.Add([pscustomobject]@{
            Mode = $Matches[1]
            Type = $Matches[2]
            ObjectId = $Matches[3]
            Path = $Matches[4].Replace('\', '/')
        })
    }
    return $entries
}

function Test-CommitSnapshot {
    param(
        [string]$RepoRoot,
        [string]$Commit,
        [object]$Config,
        [object[]]$Rules,
        [string]$TempParent,
        [switch]$HistoryAudit,
        [switch]$SourceAudit,
        [switch]$KeepSnapshot
    )

    $defaultExcludes = @(
        [pscustomobject]@{ Id = 'secret-or-runtime-path'; Regex = '(^|/)(\.env($|\.)|[^/]+\.(key|pem|p12|pfx|crt|cer|cookie|db|sqlite|sqlite3)$)' },
        [pscustomobject]@{ Id = 'generated-path'; Regex = '(^|/)(logs?|uploads?|screenshots?|videos?|test-artifacts|playwright-report|node_modules|dist|build|out|\.next|coverage|\.cache|cache)(/|$)' },
        [pscustomobject]@{ Id = 'private-work-log'; Regex = '(^|/)docs/work-log\.md$' },
        [pscustomobject]@{ Id = 'local-private-doc'; Regex = '(^|/)[^/]+\.local\.md$' }
    )

    $entries = Get-TreeEntries $RepoRoot $Commit
    $included = New-Object Collections.Generic.List[object]
    $excluded = New-Object Collections.Generic.List[object]
    $findings = New-Object Collections.Generic.List[object]

    foreach ($entry in $entries) {
        $reason = $null
        foreach ($rule in $defaultExcludes) {
            if ($entry.Path -match $rule.Regex) { $reason = $rule.Id; break }
        }
        if (-not $reason -and (-not $HistoryAudit -or $SourceAudit)) {
            foreach ($glob in @($Config.exclude)) {
                if (Test-GlobMatch $entry.Path ([string]$glob)) { $reason = 'project-exclude'; break }
            }
        }

        if ($reason) {
            if ($HistoryAudit) {
                $findings.Add([pscustomobject]@{ Rule = 'forbidden-history-path'; Path = $entry.Path })
            } else {
                $excluded.Add([pscustomobject]@{ Path = $entry.Path; Reason = $reason })
            }
            continue
        }
        if ($entry.Type -ne 'blob' -or $entry.Mode -notin @('100644', '100755')) {
            $findings.Add([pscustomobject]@{ Rule = 'unsupported-git-object'; Path = $entry.Path })
            continue
        }
        $included.Add($entry)
    }

    if ($included.Count -eq 0) {
        $findings.Add([pscustomobject]@{ Rule = 'empty-snapshot'; Path = '.' })
    }

    $snapshotRoot = Join-Path $TempParent ("snapshot-" + [Guid]::NewGuid().ToString('N'))
    $archivePath = "${snapshotRoot}.tar"
    New-Item -ItemType Directory -Force -Path $snapshotRoot | Out-Null
    Invoke-External 'git' @('-C', $RepoRoot, 'archive', '--format=tar', "--output=$archivePath", $Commit) | Out-Null
    Invoke-External 'tar' @('-xf', $archivePath, '-C', $snapshotRoot) | Out-Null
    Remove-Item -LiteralPath $archivePath -Force

    foreach ($entry in $excluded) {
        $excludedPath = Join-Path $snapshotRoot $entry.Path.Replace('/', [IO.Path]::DirectorySeparatorChar)
        if (Test-Path -LiteralPath $excludedPath) { Remove-Item -LiteralPath $excludedPath -Force -Recurse }
    }

    foreach ($entry in $included) {
        $localPath = Join-Path $snapshotRoot $entry.Path.Replace('/', [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
            $findings.Add([pscustomobject]@{ Rule = 'missing-snapshot-entry'; Path = $entry.Path })
            continue
        }
        $bytes = [IO.File]::ReadAllBytes($localPath)
        $sha256 = Get-Sha256Bytes $bytes
        $decoded = Get-TextContent $bytes
        if ($decoded.Kind -eq 'oversize') {
            $findings.Add([pscustomobject]@{ Rule = 'oversize-file'; Path = $entry.Path })
            continue
        }
        if ($decoded.Kind -eq 'binary') {
            if (-not (Test-FingerprintedAllowance $Config.allow_binary 'binary-file' $entry.Path $sha256)) {
                $findings.Add([pscustomobject]@{ Rule = 'unreviewed-binary'; Path = $entry.Path })
            }
            continue
        }

        foreach ($rule in $Rules) {
            $content = if ($entry.Path -eq 'scripts/github-backup.ps1') {
                $decoded.Content.Replace([string]$rule.Pattern, '')
            } else {
                $decoded.Content
            }
            try { $matched = $rule.Regex.IsMatch($content) }
            catch [Text.RegularExpressions.RegexMatchTimeoutException] {
                $findings.Add([pscustomobject]@{ Rule = 'regex-timeout'; Path = $entry.Path })
                continue
            }
            if ($matched -and -not (Test-FingerprintedAllowance $Config.allow_findings $rule.Id $entry.Path $sha256)) {
                $findings.Add([pscustomobject]@{ Rule = $rule.Id; Path = $entry.Path })
            }
        }
    }

    $includedPaths = [string[]]($included | ForEach-Object { $_.Path })
    $excludedItems = [object[]]($excluded | ForEach-Object { $_ })
    $findingItems = [object[]]($findings | Sort-Object Rule, Path -Unique)
    $result = [pscustomobject]@{
        Included = $includedPaths
        Excluded = $excludedItems
        Findings = $findingItems
        SnapshotRoot = $snapshotRoot
    }
    if (-not $KeepSnapshot) { Remove-Item -LiteralPath $snapshotRoot -Force -Recurse }
    return $result
}

function Write-AuditManifest {
    param([string]$AuditPath, [string]$SourceHead, [object]$Result)

    $manifest = [ordered]@{
        format = 1
        source_head = $SourceHead
        included = @($Result.Included)
        excluded = @($Result.Excluded)
        findings = @($Result.Findings)
    } | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $AuditPath -Value $manifest -Encoding utf8
}

function Assert-SourceHead {
    param([string]$RepoRoot, [string]$Expected)
    $current = ((Invoke-External 'git' @('-C', $RepoRoot, 'rev-parse', 'HEAD')).Output | Select-Object -First 1).Trim()
    if ($current -ne $Expected) { throw "Source HEAD changed during backup. No push was made." }
}

function Test-BackupHistory {
    param([string]$RepoRoot, [object]$Config, [object[]]$Rules, [string]$TempParent)

    $findings = New-Object Collections.Generic.List[object]
    $roots = @((Invoke-External 'git' @('-C', $RepoRoot, 'rev-list', '--max-parents=0', 'main')).Output | Where-Object { $_ })
    if ($roots.Count -ne 1) { $findings.Add([pscustomobject]@{ Rule = 'invalid-history-roots'; Path = '.' }) }
    $merges = @((Invoke-External 'git' @('-C', $RepoRoot, 'rev-list', '--min-parents=2', 'main')).Output | Where-Object { $_ })
    if ($merges.Count -gt 0) { $findings.Add([pscustomobject]@{ Rule = 'merge-history'; Path = '.' }) }

    if ($roots.Count -eq 1) {
        $marker = Invoke-External 'git' @('-C', $RepoRoot, 'show', "$($roots[0]):.codex-sanitized-backup.json") -AllowFailure
        if ($marker.ExitCode -ne 0) {
            $findings.Add([pscustomobject]@{ Rule = 'missing-root-marker'; Path = '.codex-sanitized-backup.json' })
        } else {
            try { $markerData = ($marker.Output -join [Environment]::NewLine) | ConvertFrom-Json }
            catch { $markerData = $null }
            if (-not $markerData -or [int]$markerData.format -ne $BackupFormat) {
                $findings.Add([pscustomobject]@{ Rule = 'invalid-root-marker'; Path = '.codex-sanitized-backup.json' })
            }
        }
    }

    foreach ($identity in (Invoke-External 'git' @('-C', $RepoRoot, 'log', 'main', '--format=%an|%ae')).Output) {
        if ([string]$identity -ne "${BackupAuthorName}|${BackupAuthorEmail}") {
            $findings.Add([pscustomobject]@{ Rule = 'unsafe-commit-identity'; Path = '.' })
            break
        }
    }

    foreach ($commit in (Invoke-External 'git' @('-C', $RepoRoot, 'rev-list', '--reverse', 'main')).Output) {
        $scan = Test-CommitSnapshot $RepoRoot ([string]$commit) $Config $Rules $TempParent -HistoryAudit
        foreach ($finding in $scan.Findings) { $findings.Add($finding) }
    }
    return @($findings | Sort-Object Rule, Path -Unique)
}

function Test-SourceHistory {
    param([string]$RepoRoot, [object]$Config, [object[]]$Rules, [string]$TempParent, [string]$BaseCommit)

    $findings = New-Object Collections.Generic.List[object]
    $revision = if ($BaseCommit) { "${BaseCommit}..HEAD" } else { 'HEAD' }
    foreach ($commit in (Invoke-External 'git' @('-C', $RepoRoot, 'rev-list', '--reverse', $revision)).Output) {
        $scan = Test-CommitSnapshot $RepoRoot ([string]$commit) $Config $Rules $TempParent -HistoryAudit -SourceAudit
        foreach ($finding in $scan.Findings) { $findings.Add($finding) }
    }
    return @($findings | Sort-Object Rule, Path -Unique)
}

$resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
if (-not (Test-Path -LiteralPath (Join-Path $resolvedProjectRoot '.git'))) {
    throw "ProjectRoot must be a Git repository root: $resolvedProjectRoot"
}
foreach ($required in @('git', 'tar')) {
    if (-not (Get-Command $required -ErrorAction SilentlyContinue)) { throw "Required command is unavailable: $required" }
}
if ($resolvedProjectRoot -match '(?i)[\\/](OneDrive|Dropbox|Google Drive)[\\/]') {
    Write-Warning "The Git root is cloud-synchronized. Use GitHub, not folder synchronization, between computers."
}

$sourceHead = ((Invoke-External 'git' @('-C', $resolvedProjectRoot, 'rev-parse', 'HEAD')).Output | Select-Object -First 1).Trim()
$projectName = Split-Path -Leaf $resolvedProjectRoot
$projectKey = (Get-Sha256Text $resolvedProjectRoot).Substring(0, 16)
$localData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path ([IO.Path]::GetTempPath()) 'CodexLocalData' }
$auditRoot = Join-Path $localData 'Codex\github-backup-audits'
New-Item -ItemType Directory -Force -Path $auditRoot | Out-Null
$auditPath = Join-Path $auditRoot "${projectName}-${projectKey}.json"
$sourceHistoryCachePath = Join-Path $auditRoot "${projectName}-${projectKey}-source-history.json"

$config = Get-CommittedConfig $resolvedProjectRoot $ConfigPath
$rules = Get-ScanRules $config.confidential_patterns
$scriptHash = (Get-FileHash -Algorithm SHA256 $MyInvocation.MyCommand.Path).Hash
$policyHash = Get-Sha256Text (($config | ConvertTo-Json -Depth 8 -Compress) + '|' + $scriptHash)
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("codex-github-backup-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$lockStream = $null

try {
    $sourceScan = Test-CommitSnapshot $resolvedProjectRoot 'HEAD' $config $rules $tempRoot -KeepSnapshot
    Write-AuditManifest $auditPath $sourceHead $sourceScan
    if ($sourceScan.Findings.Count -gt 0) {
        Write-Host "GitHub backup blocked. Matched values are not displayed:"
        $sourceScan.Findings | ForEach-Object { Write-Host "  [$($_.Rule)] $($_.Path)" }
        throw "Sanitized snapshot verification failed. Local audit: $auditPath"
    }
    Write-Host "Sanitized snapshot passed: $($sourceScan.Included.Count) included, $($sourceScan.Excluded.Count) excluded."
    if ($AuditSourceHistory) {
        $historyBase = $null
        $cachedSourceAudit = if (Test-Path -LiteralPath $sourceHistoryCachePath) {
            try { Get-Content -Raw -LiteralPath $sourceHistoryCachePath | ConvertFrom-Json } catch { $null }
        } else { $null }
        if ($cachedSourceAudit -and $cachedSourceAudit.policy_hash -eq $policyHash -and $cachedSourceAudit.tip) {
            $tipExists = Invoke-External 'git' @('-C', $resolvedProjectRoot, 'cat-file', '-e', "$($cachedSourceAudit.tip)^{commit}") -AllowFailure
            $tipIsAncestor = if ($tipExists.ExitCode -eq 0) {
                Invoke-External 'git' @('-C', $resolvedProjectRoot, 'merge-base', '--is-ancestor', [string]$cachedSourceAudit.tip, 'HEAD') -AllowFailure
            } else { $null }
            if ($tipIsAncestor -and $tipIsAncestor.ExitCode -eq 0) { $historyBase = [string]$cachedSourceAudit.tip }
        }
        $historyFindings = @(Test-SourceHistory $resolvedProjectRoot $config $rules $tempRoot $historyBase)
        if ($historyFindings.Count -gt 0) {
            Write-Host "Source history audit blocked. Matched values are not displayed:"
            $historyFindings | ForEach-Object { Write-Host "  [$($_.Rule)] $($_.Path)" }
            throw "Source history is not safe to push. Local audit: $auditPath"
        }
        Set-Content -LiteralPath $sourceHistoryCachePath -Encoding utf8 -Value (([ordered]@{ tip = $sourceHead; policy_hash = $policyHash }) | ConvertTo-Json)
        if ($historyBase) { Write-Host "Incremental source history audit passed from $historyBase." }
        else { Write-Host "Full source history audit passed." }
    }
    if ($ScanOnly) { return }

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "GitHub CLI is unavailable; backup is pending." }
    if ((Invoke-External 'gh' @('auth', 'status') -AllowFailure).ExitCode -ne 0) { throw "GitHub authentication is unavailable; run gh auth login." }

    $targetRepository = if ($Repository) { $Repository } elseif ($config.repository) { [string]$config.repository } else { $null }
    if (-not $targetRepository) {
        $targetRepository = "${projectName}-sanitized-backup-v2"
        $view = Invoke-External 'gh' @('repo', 'view', $targetRepository, '--json', 'nameWithOwner', '--jq', '.nameWithOwner') -AllowFailure
        if ($view.ExitCode -ne 0) {
            Invoke-External 'gh' @('repo', 'create', $targetRepository, '--private') | Out-Null
            $view = Invoke-External 'gh' @('repo', 'view', $targetRepository, '--json', 'nameWithOwner', '--jq', '.nameWithOwner')
        }
        $targetRepository = ($view.Output | Select-Object -First 1).Trim()
    }

    $repoView = Invoke-External 'gh' @('repo', 'view', $targetRepository, '--json', 'url,visibility')
    $repoInfo = ($repoView.Output -join [Environment]::NewLine) | ConvertFrom-Json
    if ($repoInfo.visibility -ne 'PRIVATE') { throw "Backup repository must be private: $targetRepository" }
    $targetUrl = [string]$repoInfo.url
    $remoteHeads = Invoke-External 'git' @('ls-remote', '--heads', $targetUrl) -AllowFailure
    $remoteHasHistory = $remoteHeads.ExitCode -eq 0 -and $remoteHeads.Output.Count -gt 0

    $backupKey = (Get-Sha256Text "${resolvedProjectRoot}|${targetRepository}").Substring(0, 16)
    $backupRoot = Join-Path $localData "Codex\github-backups\${projectName}-${backupKey}"
    $backupParent = Split-Path -Parent $backupRoot
    New-Item -ItemType Directory -Force -Path $backupParent | Out-Null
    $lockPath = "${backupRoot}.lock"
    try { $lockStream = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
    catch { throw "Another backup run owns the staging lock: $lockPath" }

    if (-not (Test-Path -LiteralPath (Join-Path $backupRoot '.git'))) {
        if (Test-Path -LiteralPath $backupRoot) { throw "Unexpected non-Git backup staging path: $backupRoot" }
        if ($remoteHasHistory) {
            Invoke-External 'git' @('clone', $targetUrl, $backupRoot) | Out-Null
        } else {
            New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
            Invoke-External 'git' @('-C', $backupRoot, 'init', '-b', 'main') | Out-Null
            Invoke-External 'git' @('-C', $backupRoot, 'remote', 'add', 'origin', $targetUrl) | Out-Null
        }
    }

    $origin = ((Invoke-External 'git' @('-C', $backupRoot, 'remote', 'get-url', 'origin')).Output | Select-Object -First 1).Trim()
    if ($origin -notin @($targetUrl, "${targetUrl}.git")) { throw "Backup staging origin mismatch: $backupRoot" }

    $status = (Invoke-External 'git' @('-C', $backupRoot, 'status', '--porcelain')).Output
    if ($status.Count -gt 0) {
        $head = Invoke-External 'git' @('-C', $backupRoot, 'rev-parse', '--verify', 'HEAD') -AllowFailure
        if ($head.ExitCode -eq 0) { Invoke-External 'git' @('-C', $backupRoot, 'restore', '--staged', '--worktree', '--source=HEAD', '--', '.') | Out-Null }
        else { Invoke-External 'git' @('-C', $backupRoot, 'read-tree', '--empty') | Out-Null }
        Get-ChildItem -Force -LiteralPath $backupRoot | Where-Object { $_.Name -ne '.git' } | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -Recurse }
    }

    if ($remoteHasHistory) {
        Invoke-External 'git' @('-C', $backupRoot, 'fetch', 'origin', 'main') | Out-Null
        $localHead = Invoke-External 'git' @('-C', $backupRoot, 'rev-parse', '--verify', 'HEAD') -AllowFailure
        if ($localHead.ExitCode -eq 0) { Invoke-External 'git' @('-C', $backupRoot, 'merge', '--ff-only', 'origin/main') | Out-Null }
        else { Invoke-External 'git' @('-C', $backupRoot, 'checkout', '-b', 'main', 'origin/main') | Out-Null }
        $auditCachePath = Join-Path $backupRoot '.git\codex-history-audit.json'
        $remoteAuditTip = ((Invoke-External 'git' @('-C', $backupRoot, 'rev-parse', 'origin/main')).Output | Select-Object -First 1).Trim()
        $cachedAudit = if (Test-Path -LiteralPath $auditCachePath) {
            try { Get-Content -Raw -LiteralPath $auditCachePath | ConvertFrom-Json } catch { $null }
        } else { $null }
        if (-not $cachedAudit -or $cachedAudit.tip -ne $remoteAuditTip -or $cachedAudit.policy_hash -ne $policyHash) {
            $historyFindings = @(Test-BackupHistory $backupRoot $config $rules $tempRoot)
            if ($historyFindings.Count -gt 0) {
                Write-Host "Existing backup history failed audit:"
                $historyFindings | ForEach-Object { Write-Host "  [$($_.Rule)] $($_.Path)" }
                throw "Refusing to extend unverified backup history."
            }
            Set-Content -LiteralPath $auditCachePath -Encoding utf8 -Value (([ordered]@{ tip = $remoteAuditTip; policy_hash = $policyHash }) | ConvertTo-Json)
        }
    }

    $sourceRemote = Invoke-External 'git' @('-C', $resolvedProjectRoot, 'remote', 'get-url', $RemoteName) -AllowFailure
    if ($sourceRemote.ExitCode -eq 0) {
        $configuredUrl = ($sourceRemote.Output | Select-Object -First 1).Trim()
        if ($configuredUrl -notin @($targetUrl, "${targetUrl}.git")) {
            $legacyName = "${RemoteName}-legacy"
            $suffix = 1
            while ((Invoke-External 'git' @('-C', $resolvedProjectRoot, 'remote', 'get-url', $legacyName) -AllowFailure).ExitCode -eq 0) {
                $suffix++
                $legacyName = "${RemoteName}-legacy-${suffix}"
            }
            Invoke-External 'git' @('-C', $resolvedProjectRoot, 'remote', 'rename', $RemoteName, $legacyName) | Out-Null
            Invoke-External 'git' @('-C', $resolvedProjectRoot, 'remote', 'add', $RemoteName, $targetUrl) | Out-Null
        }
    } else {
        Invoke-External 'git' @('-C', $resolvedProjectRoot, 'remote', 'add', $RemoteName, $targetUrl) | Out-Null
    }

    $originUrl = Invoke-External 'git' @('-C', $resolvedProjectRoot, 'remote', 'get-url', 'origin') -AllowFailure
    if ($originUrl.ExitCode -eq 0 -and (Get-RepositoryFromUrl (($originUrl.Output | Select-Object -First 1).Trim())) -and (($originUrl.Output | Select-Object -First 1).Trim()) -notin @($targetUrl, "${targetUrl}.git")) {
        Invoke-External 'git' @('-C', $resolvedProjectRoot, 'remote', 'set-url', '--push', 'origin', 'DISABLED') | Out-Null
        $branch = ((Invoke-External 'git' @('-C', $resolvedProjectRoot, 'branch', '--show-current')).Output | Select-Object -First 1).Trim()
        $upstreamRemote = Invoke-External 'git' @('-C', $resolvedProjectRoot, 'config', '--get', "branch.${branch}.remote") -AllowFailure
        if ($upstreamRemote.ExitCode -eq 0 -and (($upstreamRemote.Output | Select-Object -First 1).Trim()) -eq 'origin') {
            Invoke-External 'git' @('-C', $resolvedProjectRoot, 'branch', '--unset-upstream') | Out-Null
        }
        Write-Warning "Disabled push and upstream tracking for unverified legacy origin."
    }

    Get-ChildItem -Force -LiteralPath $backupRoot | Where-Object { $_.Name -ne '.git' } | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -Recurse }
    Get-ChildItem -Force -LiteralPath $sourceScan.SnapshotRoot | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $backupRoot -Force -Recurse }
    Set-Content -LiteralPath (Join-Path $backupRoot '.codex-sanitized-backup.json') -Encoding utf8 -Value (([ordered]@{ format = $BackupFormat; source_project = $projectName }) | ConvertTo-Json)

    Invoke-External 'git' @('-C', $backupRoot, 'config', 'user.name', $BackupAuthorName) | Out-Null
    Invoke-External 'git' @('-C', $backupRoot, 'config', 'user.email', $BackupAuthorEmail) | Out-Null
    Assert-SourceHead $resolvedProjectRoot $sourceHead
    Invoke-External 'git' @('-C', $backupRoot, 'add', '--all') | Out-Null
    Invoke-External 'git' @('-C', $backupRoot, 'diff', '--cached', '--check') | Out-Null

    $staged = Invoke-External 'git' @('-C', $backupRoot, 'diff', '--cached', '--quiet') -AllowFailure
    if ($staged.ExitCode -eq 1) {
        Assert-SourceHead $resolvedProjectRoot $sourceHead
        Invoke-External 'git' @('-C', $backupRoot, 'commit', '-m', "Update sanitized backup for $projectName") | Out-Null
        $newCommitScan = Test-CommitSnapshot $backupRoot 'HEAD' $config $rules $tempRoot -HistoryAudit
        if ($newCommitScan.Findings.Count -gt 0) { throw "Generated backup commit failed its own history audit." }
    } elseif ($staged.ExitCode -ne 0) {
        throw "Unable to determine staged backup changes."
    }

    Assert-SourceHead $resolvedProjectRoot $sourceHead
    $localTip = ((Invoke-External 'git' @('-C', $backupRoot, 'rev-parse', 'HEAD')).Output | Select-Object -First 1).Trim()
    $remoteTipResult = Invoke-External 'git' @('ls-remote', $targetUrl, 'refs/heads/main') -AllowFailure
    $remoteTip = if ($remoteTipResult.Output.Count -gt 0) { (($remoteTipResult.Output | Select-Object -First 1) -split '\s+')[0] } else { $null }
    if ($localTip -ne $remoteTip) { Invoke-External 'git' @('-C', $backupRoot, 'push', '-u', 'origin', 'HEAD:main') | Out-Null }
    Set-Content -LiteralPath (Join-Path $backupRoot '.git\codex-history-audit.json') -Encoding utf8 -Value (([ordered]@{ tip = $localTip; policy_hash = $policyHash }) | ConvertTo-Json)
    Write-Host "Isolated sanitized backup is current at $targetRepository. Local audit: $auditPath"
}
finally {
    if ($lockStream) { $lockStream.Dispose() }
    if ($lockPath -and (Test-Path -LiteralPath $lockPath)) { Remove-Item -LiteralPath $lockPath -Force }
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Force -Recurse }
}
