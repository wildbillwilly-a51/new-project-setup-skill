$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }
$skillsRoot = Join-Path $codexHome "skills"
$installedRoot = Join-Path $skillsRoot "new-project-setup"
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

& (Join-Path $projectRoot "scripts\validate-skill.ps1") -SkillRoot $projectRoot
New-Item -ItemType Directory -Force -Path $skillsRoot | Out-Null
$stagingRoot = Join-Path $skillsRoot (".new-project-setup-stage-" + [Guid]::NewGuid().ToString('N'))
$previousRoot = Join-Path $skillsRoot (".new-project-setup-previous-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $stagingRoot | Out-Null

try {
  foreach ($relative in $payload) {
    $destination = Join-Path $stagingRoot $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot $relative) -Destination $destination -Force
  }
  & (Join-Path $stagingRoot "scripts\validate-skill.ps1") -SkillRoot $stagingRoot

  if (Test-Path -LiteralPath $installedRoot) {
    Move-Item -LiteralPath $installedRoot -Destination $previousRoot
  }
  try {
    Move-Item -LiteralPath $stagingRoot -Destination $installedRoot
  }
  catch {
    if (Test-Path -LiteralPath $previousRoot) { Move-Item -LiteralPath $previousRoot -Destination $installedRoot }
    throw
  }
  if (Test-Path -LiteralPath $previousRoot) { Remove-Item -LiteralPath $previousRoot -Force -Recurse }

  foreach ($relative in $payload) {
    $sourceHash = (Get-FileHash -Algorithm SHA256 (Join-Path $projectRoot $relative)).Hash
    $installedHash = (Get-FileHash -Algorithm SHA256 (Join-Path $installedRoot $relative)).Hash
    if ($sourceHash -ne $installedHash) { throw "Installed payload hash mismatch: $relative" }
  }
}
finally {
  if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Force -Recurse }
}

Write-Host "Synced exact installed skill payload to $installedRoot"
