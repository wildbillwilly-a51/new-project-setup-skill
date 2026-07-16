$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }
$installedRoot = Join-Path $codexHome "skills\new-project-setup"
$payload = @(
  "SKILL.md",
  "agents\openai.yaml",
  "references\new-project-setup-checklist.md",
  "references\install-and-migration.md",
  "references\execution-and-memory.md",
  "references\github-history.md",
  "scripts\apply-project-setup.ps1",
  "scripts\github-backup.ps1",
  "scripts\github-sync.ps1",
  "scripts\validate-skill.ps1"
)

if (-not (Test-Path -LiteralPath $installedRoot)) { throw "Installed skill not found: $installedRoot" }
& (Join-Path $installedRoot "scripts\validate-skill.ps1") -SkillRoot $installedRoot

foreach ($relative in $payload) {
  $source = Join-Path $installedRoot $relative
  $destination = Join-Path $projectRoot $relative
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
  Copy-Item -LiteralPath $source -Destination $destination -Force
  if ((Get-FileHash -Algorithm SHA256 $source).Hash -ne (Get-FileHash -Algorithm SHA256 $destination).Hash) {
    throw "Source back-sync hash mismatch: $relative"
  }
}

& (Join-Path $projectRoot "scripts\validate-skill.ps1") -SkillRoot $projectRoot
Write-Host "Validated and synced source project from $installedRoot"
