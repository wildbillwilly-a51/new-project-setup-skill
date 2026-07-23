#requires -Version 5.1

$ErrorActionPreference = 'Stop'

function ConvertTo-WindowsCommandLineArgument {
    param([AllowEmptyString()][string]$Value)

    $result = New-Object Text.StringBuilder
    [void]$result.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $slashes++
            continue
        }
        if ($character -eq '"') {
            if ($slashes -gt 0) { [void]$result.Append((('\' * (($slashes * 2) + 1)) -join '')) }
            else { [void]$result.Append('\') }
            [void]$result.Append('"')
            $slashes = 0
            continue
        }
        if ($slashes -gt 0) { [void]$result.Append((('\' * $slashes) -join '')) }
        [void]$result.Append($character)
        $slashes = 0
    }
    if ($slashes -gt 0) { [void]$result.Append((('\' * ($slashes * 2)) -join '')) }
    [void]$result.Append('"')
    return $result.ToString()
}

if ($args.Count -lt 1 -or [string]::IsNullOrWhiteSpace([string]$args[0])) {
    [Console]::Error.WriteLine('Usage: invoke-powershell.ps1 <script.ps1> [arguments...]')
    exit 64
}

$ScriptPath = [string]$args[0]
$scriptArguments = @()
if ($args.Count -gt 1) { $scriptArguments = [object[]]@($args[1..($args.Count - 1)]) }
$resolvedScript = (Resolve-Path -LiteralPath $ScriptPath -ErrorAction Stop).Path
if ([IO.Path]::GetExtension($resolvedScript) -ine '.ps1') {
    [Console]::Error.WriteLine('The launcher target must be a PowerShell script.')
    exit 64
}
$runningOnWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$hostExecutable = $null
$candidateNames = if ($runningOnWindows) { @('pwsh.exe', 'pwsh') } else { @('pwsh') }

foreach ($name in $candidateNames) {
    $candidate = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $candidate) { continue }
    & $candidate.Source -NoLogo -NoProfile -NonInteractive -Command "if (`$PSVersionTable.PSEdition -eq 'Core' -and `$PSVersionTable.PSVersion -ge [Version]'7.6.0') { exit 0 }; exit 1" *> $null
    if ($LASTEXITCODE -eq 0) {
        $hostExecutable = $candidate.Source
        break
    }
}

if (-not $hostExecutable) {
    [Console]::Error.WriteLine('PowerShell Core 7.6 or later (pwsh) is required. No legacy-host fallback is supported.')
    exit 127
}

$hostArguments = @('-NoLogo', '-NoProfile', '-NonInteractive')
if ($runningOnWindows) { $hostArguments += @('-ExecutionPolicy', 'Bypass') }
$childArguments = New-Object Collections.Generic.List[string]
foreach ($argument in $hostArguments) { $childArguments.Add([string]$argument) }
$childArguments.Add('-File')
$childArguments.Add($resolvedScript)
foreach ($argument in $scriptArguments) { $childArguments.Add([string]$argument) }

$startInfo = New-Object Diagnostics.ProcessStartInfo
$startInfo.FileName = $hostExecutable
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
if ($startInfo.PSObject.Properties.Name -contains 'ArgumentList') {
    foreach ($argument in $childArguments) { $startInfo.ArgumentList.Add($argument) }
} elseif ($runningOnWindows) {
    $startInfo.Arguments = (@($childArguments | ForEach-Object { ConvertTo-WindowsCommandLineArgument $_ }) -join ' ')
} else {
    throw 'This PowerShell runtime cannot preserve native arguments on this platform.'
}

$child = [Diagnostics.Process]::Start($startInfo)
if ($null -eq $child) { throw 'Unable to start the selected PowerShell runtime.' }
$stdoutTask = $child.StandardOutput.ReadToEndAsync()
$stderrTask = $child.StandardError.ReadToEndAsync()
$child.WaitForExit()
$stdoutTask.Wait()
$stderrTask.Wait()
$standardOutput = [string]$stdoutTask.Result
$standardError = [string]$stderrTask.Result
if ($standardOutput.Length -gt 0) { Write-Output $standardOutput }
if ($standardError.Length -gt 0) { Write-Error -Message $standardError -ErrorAction Continue }
exit $child.ExitCode
