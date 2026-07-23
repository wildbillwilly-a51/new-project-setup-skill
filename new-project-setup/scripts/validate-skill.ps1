#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$SkillRoot,
    [string]$PayloadManifestPath,
    [ValidateSet('Auto', 'Source', 'Installed')]
    [string]$PayloadRole = 'Auto',
    [switch]$ManifestOnly
)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [Version]'7.6.0') {
    throw 'PowerShell Core 7.6 or later (pwsh) is required. No legacy-host fallback is supported.'
}

$root = (Resolve-Path -LiteralPath $(if ($SkillRoot) { $SkillRoot } else { Split-Path -Parent $PSScriptRoot })).Path
$defaultManifestPath = Join-Path $root 'scripts/skill-payload.json'
$manifestPath = if ($PayloadManifestPath) {
    [IO.Path]::GetFullPath($PayloadManifestPath)
} elseif (Test-Path -LiteralPath $defaultManifestPath -PathType Leaf) {
    $defaultManifestPath
} else { $null }

function Assert-ObjectKeys {
    param([object]$Value, [string[]]$Expected, [string]$Label)
    if ($null -eq $Value -or $null -eq $Value.PSObject) { throw "$Label must be an object." }
    $actual = @($Value.PSObject.Properties.Name | Sort-Object)
    $wanted = @($Expected | Sort-Object)
    if (($actual -join "`n") -cne ($wanted -join "`n")) {
        throw "$Label has invalid keys. Expected: $($wanted -join ', '). Found: $($actual -join ', ')."
    }
}

function Assert-RelativePath {
    param([string]$Path, [string]$Label)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*$') {
        throw "$Label is not a safe normalized relative path: $Path"
    }
    if (@($Path.Split('/') | Where-Object { $_ -in @('.', '..') }).Count) {
        throw "$Label escapes its payload root: $Path"
    }
}

function Assert-Hash {
    param([string]$Hash, [string]$Label)
    if ([string]::IsNullOrWhiteSpace($Hash) -or $Hash -cnotmatch '^[0-9a-f]{64}$') {
        throw "$Label must be a lowercase SHA-256 value."
    }
}

function Get-Definition {
    param([object]$Manifest, [int]$Version)
    $matches = @($Manifest.payloads | Where-Object { [int]$_.workflow_version -eq $Version })
    if ($matches.Count -ne 1) { throw "Payload manifest has no unique workflow v${Version} definition." }
    return $matches[0]
}

function Get-FileSha256 {
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-TextSha256 {
    param([string]$Text)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()
}

function Test-AllowedHash {
    param([string]$Hash, [object[]]$Allowed)
    return @($Allowed | Where-Object { [string]$_ -ceq $Hash }).Count -gt 0
}

function Assert-DefinitionPaths {
    param([object]$Definition, [string]$Label)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($Definition.required_paths)) {
        Assert-ObjectKeys $entry @('path', 'source_hash', 'owned_hashes') "$Label required path"
        Assert-RelativePath ([string]$entry.path) "$Label required path"
        if (-not $seen.Add([string]$entry.path)) { throw "$Label repeats required path: $($entry.path)" }
        Assert-Hash ([string]$entry.source_hash) "$Label source hash for $($entry.path)"
        $owned = @($entry.owned_hashes)
        if (-not $owned.Count) { throw "$Label has no owned hashes for $($entry.path)." }
        foreach ($hash in $owned) { Assert-Hash ([string]$hash) "$Label owned hash for $($entry.path)" }
        if (-not (Test-AllowedHash ([string]$entry.source_hash) $owned)) {
            throw "$Label source hash is not included in owned hashes: $($entry.path)"
        }
    }
}

function Read-Manifest {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'A payload manifest is required.' }
    try { $manifest = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json }
    catch { throw "Payload manifest JSON is invalid: $($_.Exception.Message)" }

    Assert-ObjectKeys $manifest @('format', 'active_workflow_version', 'allowed_transitions', 'payloads') 'Payload manifest'
    if ([int]$manifest.format -ne 1) { throw 'Payload manifest format must be 1.' }
    if ([int]$manifest.active_workflow_version -ne 7) { throw 'Workflow v7 must be the active payload.' }
    if (@($manifest.payloads).Count -ne 2) { throw 'Payload manifest must contain exactly v6 and v7.' }

    $v6 = Get-Definition $manifest 6
    $v7 = Get-Definition $manifest 7
    Assert-ObjectKeys $v6 @('workflow_version','state','runtime','hash_policy','required_paths','predecessor_only_owned_paths') 'Workflow v6'
    Assert-ObjectKeys $v7 @('workflow_version','state','runtime','hash_policy','same_version_additions','required_paths','predecessor_only_owned_paths') 'Workflow v7'
    foreach ($pair in @(@{ Value=$v6; Version=6; State='predecessor' }, @{ Value=$v7; Version=7; State='active' })) {
        if ([int]$pair.Value.workflow_version -ne $pair.Version -or [string]$pair.Value.state -cne $pair.State) {
            throw "Workflow v$($pair.Version) must be $($pair.State)."
        }
        Assert-ObjectKeys $pair.Value.runtime @('executable','minimum_version','fallback_policy','fallback_executable','fallback_minimum_version') "Workflow v$($pair.Version) runtime"
        Assert-ObjectKeys $pair.Value.hash_policy @('algorithm','mechanism') "Workflow v$($pair.Version) hash policy"
        if ([string]$pair.Value.hash_policy.algorithm -cne 'sha256' -or [string]$pair.Value.hash_policy.mechanism -cne 'declared-source-and-owned-hashes') {
            throw "Workflow v$($pair.Version) must use declared SHA-256 source and ownership hashes."
        }
        Assert-DefinitionPaths $pair.Value "Workflow v$($pair.Version)"
    }

    if ([string]$v6.runtime.executable -cne 'pwsh' -or [string]$v6.runtime.minimum_version -cne '7.0.0' -or
        [string]$v6.runtime.fallback_policy -cne 'windows-powershell-5.1-on-windows' -or
        [string]$v6.runtime.fallback_executable -cne 'powershell.exe' -or [string]$v6.runtime.fallback_minimum_version -cne '5.1') {
        throw 'Workflow v6 runtime history changed.'
    }
    if ([string]$v7.runtime.executable -cne 'pwsh' -or [string]$v7.runtime.minimum_version -cne '7.6.0' -or
        [string]$v7.runtime.fallback_policy -cne 'none' -or $null -ne $v7.runtime.fallback_executable -or
        $null -ne $v7.runtime.fallback_minimum_version) {
        throw 'Workflow v7 must require pwsh 7.6 or later with no fallback.'
    }

    $transitionSet = @($manifest.allowed_transitions | ForEach-Object {
        Assert-ObjectKeys $_ @('from','to') 'Allowed transition'
        "{0}>{1}" -f [int]$_.from,[int]$_.to
    } | Sort-Object)
    if (($transitionSet -join ',') -cne '6>6,6>7,7>7') { throw 'Allowed transitions must be exactly 6>6, 6>7, and 7>7.' }

    $v6Canonical = $v6 | ConvertTo-Json -Depth 20 -Compress
    if ((Get-TextSha256 $v6Canonical) -cne 'ada75a6f34735f94b4235c51e70c69a897be4ce69ed97682c57b83b6f2934ff7') {
        throw 'Frozen workflow v6 predecessor declaration changed.'
    }

    $expectedV7Paths = @(
        'SKILL.md','agents/openai.yaml','references/new-project-setup-checklist.md',
        'references/install-and-migration.md','references/execution-and-continuity.md',
        'references/local-saving.md','templates/agents-workflow-block.md','templates/project-summary.md',
        'templates/codex-handoff.md','scripts/apply-project-setup.ps1','scripts/apply-project-setup-v7.ps1',
        'scripts/configure-default-activation.ps1','scripts/save-local-work.ps1',
        'scripts/invoke-powershell.ps1','scripts/invoke-powershell.sh',
        'scripts/validate-skill.ps1'
    ) | Sort-Object
    $actualV7Paths = @($v7.required_paths | ForEach-Object { [string]$_.path } | Sort-Object)
    if (($actualV7Paths -join "`n") -cne ($expectedV7Paths -join "`n")) { throw 'Workflow v7 required-path surface changed.' }
    $sameVersionAdditions = @($v7.same_version_additions)
    if ($sameVersionAdditions.Count -ne 1) { throw 'Workflow v7 same-version addition declaration changed.' }
    Assert-ObjectKeys $sameVersionAdditions[0] @('path') 'Workflow v7 same-version addition'
    Assert-RelativePath ([string]$sameVersionAdditions[0].path) 'Workflow v7 same-version addition'
    if ([string]$sameVersionAdditions[0].path -cne 'scripts/configure-default-activation.ps1' -or
        $actualV7Paths -cnotcontains [string]$sameVersionAdditions[0].path) {
        throw 'Workflow v7 same-version addition is not the declared activation controller.'
    }

    $expectedPredecessor = [ordered]@{
        'references/execution-and-memory.md' = '33dc541a40d51d4b310c35c9b40c8b6d0ac9df99e543da49c7b988b12fc6561f'
        'references/github-history.md' = '39d3d5b08f30386c97b819970136a7cafde01a34533606b2b7356cad5203066d'
        'scripts/github-backup.ps1' = '60ac4a31c547a896cb07dbc9352fa1ef694e145880ad538bebaced4738b615b0'
        'scripts/github-sync.ps1' = 'cc178cd21e90cb37b447fe4b960e29ac3f4eaf687cc3827bdbac7a3bea70e304'
    }
    if (@($v7.predecessor_only_owned_paths).Count -ne $expectedPredecessor.Count) { throw 'Workflow v7 predecessor-only path count changed.' }
    foreach ($entry in @($v7.predecessor_only_owned_paths)) {
        Assert-ObjectKeys $entry @('path','from_version','owned_hashes') 'Workflow v7 predecessor-only path'
        $relative = [string]$entry.path
        Assert-RelativePath $relative 'Workflow v7 predecessor-only path'
        if (-not $expectedPredecessor.Contains($relative) -or [int]$entry.from_version -ne 6 -or @($entry.owned_hashes).Count -ne 1 -or
            [string]$entry.owned_hashes[0] -cne [string]$expectedPredecessor[$relative]) {
            throw "Workflow v7 predecessor-only ownership changed: $relative"
        }
    }
    if (@($v6.predecessor_only_owned_paths).Count) { throw 'Workflow v6 predecessor-only list must remain empty.' }
    return $manifest
}

$manifest = Read-Manifest $manifestPath
if ($ManifestOnly) {
    Write-Host "Validated active workflow v7 payload manifest at $manifestPath"
    return
}

$role = if ($PayloadRole -eq 'Auto') {
    if ([string]::Equals($manifestPath, $defaultManifestPath, [StringComparison]::OrdinalIgnoreCase)) { 'Source' } else { 'Installed' }
} else { $PayloadRole }
$active = Get-Definition $manifest 7
foreach ($entry in @($active.required_paths)) {
    $relative = [string]$entry.path
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing active workflow v7 payload: $relative" }
    $actual = Get-FileSha256 $path
    if ($role -eq 'Source' -and $actual -cne [string]$entry.source_hash) { throw "Active source hash mismatch: $relative" }
    if ($role -eq 'Installed' -and -not (Test-AllowedHash $actual @($entry.owned_hashes))) { throw "Installed payload is not owned: $relative" }
}
if ($role -eq 'Installed') {
    foreach ($entry in @($active.predecessor_only_owned_paths)) {
        $path = Join-Path $root ([string]$entry.path)
        if ((Test-Path -LiteralPath $path -PathType Leaf) -and (Test-AllowedHash (Get-FileSha256 $path) @($entry.owned_hashes))) {
            throw "Exact predecessor-only payload remains active: $($entry.path)"
        }
    }
}

$skillPath = Join-Path $root 'SKILL.md'
$agentPath = Join-Path $root 'agents/openai.yaml'
$skill = Get-Content -Raw -LiteralPath $skillPath
$agent = Get-Content -Raw -LiteralPath $agentPath
if ($skill -notmatch '(?s)^---\r?\nname: new-project-setup\r?\ndescription: [^\r\n]+\r?\n---\r?\n') { throw 'SKILL.md frontmatter is invalid.' }
if ((Get-Content -LiteralPath $skillPath).Count -ge 300 -or $skill.Length -gt 8500) { throw 'SKILL.md exceeds its release size ceiling.' }
foreach ($key in @('display_name','short_description','default_prompt')) {
    if ($agent -notmatch ('(?m)^\s+' + [Regex]::Escape($key) + ': "[^"]+"\s*$')) { throw "agents/openai.yaml is missing quoted $key." }
}
if ($agent -notmatch '\$new-project-setup' -or $agent -notmatch '(?m)^\s+allow_implicit_invocation: true\s*$') {
    throw 'agents/openai.yaml activation metadata is invalid.'
}

$python = $null
foreach ($name in @('python3','python','py')) {
    $candidate = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $candidate) { continue }
    $prefix = if ($name -eq 'py') { @('-3') } else { @() }
    & $candidate.Source @prefix -c 'import sys, yaml; raise SystemExit(0 if sys.version_info.major == 3 else 1)' *> $null
    if ($LASTEXITCODE -eq 0) { $python = [pscustomobject]@{ Path=$candidate.Source; Prefix=$prefix }; break }
}
if (-not $python) { throw 'Release validation requires Python 3 with PyYAML; target setup does not.' }
$yamlCheck = @'
import copy, re, sys, yaml
from pathlib import Path

class ContractError(Exception): pass
def require(value, message):
    if not value: raise ContractError(message)
class UniqueLoader(yaml.SafeLoader): pass
def unique_mapping(loader, node, deep=False):
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in result: raise ContractError(f"duplicate YAML key: {key}")
        result[key] = loader.construct_object(value_node, deep=deep)
    return result
UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, unique_mapping)
def load(text, label):
    try: value = yaml.load(text, Loader=UniqueLoader)
    except Exception as exc: raise ContractError(f"{label}: {exc}") from exc
    require(type(value) is dict, f"{label}: root must be a mapping")
    return value
def skill_ok(value):
    require(set(value) == {"name","description"}, "skill keys")
    require(value["name"] == "new-project-setup", "skill name")
    text = value["description"].lower()
    require("ordinary creation of a new durable project" in text, "implicit durable-project activation")
    require("do not invoke" in text and "existing project" in text, "existing-project exclusion")
    require("global automatic/manual activation" in text, "global activation choice")
def agent_ok(value):
    require(set(value) == {"interface","policy"}, "agent keys")
    require(set(value["interface"]) == {"display_name","short_description","default_prompt"}, "interface keys")
    require(set(value["policy"]) == {"allow_implicit_invocation"}, "policy keys")
    require(value["policy"]["allow_implicit_invocation"] is True, "implicit invocation boolean")
    require(len(value["interface"]["short_description"]) <= 80, "short description")
    prompt = value["interface"]["default_prompt"].lower()
    require("$new-project-setup" in prompt and "durable project" in prompt, "default prompt activation")
    require("do not reinstall" in prompt and "existing project" in prompt, "default prompt exclusion")
    require("automatic" in prompt and "manual" in prompt, "default prompt global activation choice")
def rejects(action):
    try: action()
    except ContractError: return
    raise ContractError("semantic mutation accepted")
root = Path(sys.argv[1])
skill_text = (root / "SKILL.md").read_text(encoding="utf-8-sig")
match = re.match(r"\A---\r?\n(.*?)\r?\n---\r?\n", skill_text, re.S)
require(match is not None, "frontmatter missing")
skill = load(match.group(1), "skill")
agent = load((root / "agents/openai.yaml").read_text(encoding="utf-8-sig"), "agent")
skill_ok(skill); agent_ok(agent)
mutant = copy.deepcopy(agent); mutant["policy"]["allow_implicit_invocation"] = "true"; rejects(lambda: agent_ok(mutant))
mutant = copy.deepcopy(skill); mutant["description"] = mutant["description"].replace("ordinary creation of a new durable project", "manual setup"); rejects(lambda: skill_ok(mutant))
mutant = copy.deepcopy(agent); mutant["interface"]["default_prompt"] = "Use $new-project-setup for a durable project."; rejects(lambda: agent_ok(mutant))
rejects(lambda: load("policy:\n  allow_implicit_invocation: true\npolicy:\n  allow_implicit_invocation: true\n", "duplicate"))
print("semantic-yaml-ok mutations=4")
'@
$arguments = @($python.Prefix) + @('-', $root)
$output = $yamlCheck | & $python.Path @arguments 2>&1
if ($LASTEXITCODE -ne 0 -or ($output -join "`n") -notmatch 'semantic-yaml-ok mutations=4') { throw "Semantic YAML validation failed: $($output -join ' ')" }

foreach ($relative in @('scripts/apply-project-setup.ps1','scripts/apply-project-setup-v7.ps1','scripts/configure-default-activation.ps1','scripts/save-local-work.ps1','scripts/invoke-powershell.ps1','scripts/validate-skill.ps1')) {
    $path = Join-Path $root $relative
    $tokens = $null; $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count) { throw "$relative parse failure: $($errors.Message -join '; ')" }
}

$psLauncher = Get-Content -Raw -LiteralPath (Join-Path $root 'scripts/invoke-powershell.ps1')
$shLauncher = Get-Content -Raw -LiteralPath (Join-Path $root 'scripts/invoke-powershell.sh')
if ($psLauncher -notmatch '7\.6\.0' -or $psLauncher -notmatch "'pwsh\.exe', 'pwsh'" -or $psLauncher -match 'powershell\.exe' -or
    $psLauncher -notmatch 'UseShellExecute\s*=\s*\$false' -or $psLauncher -notmatch 'ConvertTo-WindowsCommandLineArgument') {
    throw 'PowerShell launcher must select pwsh 7.6 or later and provide no legacy-host fallback.'
}
if ($shLauncher -notmatch 'command -v pwsh' -or $shLauncher -notmatch '7\.6\.0' -or
    $shLauncher -match '(?i)powershell\.exe' -or $shLauncher -match '(?im)^\s*(?:exec\s+)?powershell\b') {
    throw 'POSIX launcher must select pwsh 7.6 or later and provide no legacy-host fallback.'
}

$wrapper = Get-Content -Raw -LiteralPath (Join-Path $root 'scripts/apply-project-setup.ps1')
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($wrapper, [ref]$tokens, [ref]$errors)
$parameters = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
if (($parameters -join ',') -cne 'ProjectRoot,Check') { throw "Active apply wrapper parameters changed: $($parameters -join ', ')" }
if (@([Regex]::Matches($wrapper, '\$WorkflowVersion\s*=\s*7\b')).Count -ne 1 -or
    $wrapper -match '(?i)AllowProspective|ProspectiveDispatch|\$Repository\b|\$RemoteName\b|\[ValidateSet\(6,\s*7\)\]') {
    throw 'Active apply wrapper must expose only workflow v7 ProjectRoot/Check behavior.'
}
$helper = Get-Content -Raw -LiteralPath (Join-Path $root 'scripts/apply-project-setup-v7.ps1')
foreach ($marker in @('$StateFormat = 3','new-project-setup:v7','v6-migration','v7-apply-after-first-replace','Expand-FrozenV6Text','Get-FrozenV6Contract')) {
    if ($helper -notmatch [Regex]::Escape($marker)) { throw "Active apply helper is missing marker: $marker" }
}
foreach ($forbidden in @('ProspectiveDispatch','AllowProspective','references/execution-and-memory.md'' -PathType Leaf','scripts/github-sync.ps1'' -PathType Leaf')) {
    if ($helper -match [Regex]::Escape($forbidden)) { throw "Active apply helper retains a source predecessor dependency: $forbidden" }
}

$activeTextPaths = @('SKILL.md','agents/openai.yaml','references/new-project-setup-checklist.md','references/install-and-migration.md','references/execution-and-continuity.md','references/local-saving.md','templates/agents-workflow-block.md','templates/project-summary.md','templates/codex-handoff.md')
$policy = @($activeTextPaths | ForEach-Object { Get-Content -Raw -LiteralPath (Join-Path $root $_) }) -join "`n"
foreach ($marker in @('local-first','progressive context','proportional','PowerShell Core 7.6','No Windows PowerShell fallback','Prepare','Commit','bounded v6')) {
    if ($policy -notmatch [Regex]::Escape($marker)) { throw "Active workflow v7 policy is missing marker: $marker" }
}
if ($policy -match '(?is)(must|required to|always)\s+(?:use\s+)?(?:a\s+)?(?:GitHub|remote)') {
    throw 'Active workflow v7 policy must not require ordinary remote or hosted-repository behavior.'
}

Write-Host "Validated active new-project-setup workflow v7 payload at $root (semantic YAML mutations: 4)"
