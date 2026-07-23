#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$ProjectRoot = '.',
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$WorkflowVersion = 7

if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [Version]'7.6.0') {
    throw 'PowerShell Core 7.6 or later (pwsh) is required for workflow version 7.'
}

$activeApply = Join-Path $PSScriptRoot 'apply-project-setup-v7.ps1'
if (-not (Test-Path -LiteralPath $activeApply -PathType Leaf)) {
    throw 'The workflow version-7 apply implementation is missing.'
}

& $activeApply -ProjectRoot $ProjectRoot -Check:$Check
exit $LASTEXITCODE
