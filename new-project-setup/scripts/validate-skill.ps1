#requires -Version 5.1

[CmdletBinding()]
param([string]$SkillRoot)

$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7 or Windows PowerShell 5.1 is required.'
}
$effectiveSkillRoot = if ($SkillRoot) { $SkillRoot } else { Split-Path -Parent $PSScriptRoot }
$root = (Resolve-Path -LiteralPath $effectiveSkillRoot).Path
$required = @(
    'SKILL.md',
    'agents/openai.yaml',
    'references/new-project-setup-checklist.md',
    'references/install-and-migration.md',
    'references/execution-and-memory.md',
    'references/github-history.md',
    'scripts/apply-project-setup.ps1',
    'scripts/github-backup.ps1',
    'scripts/github-sync.ps1',
    'scripts/invoke-powershell.ps1',
    'scripts/invoke-powershell.sh',
    'scripts/validate-skill.ps1'
)

foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)) {
        throw "Missing required skill payload: $relative"
    }
}

$skillPath = Join-Path $root 'SKILL.md'
$agentPath = Join-Path $root 'agents/openai.yaml'
$skill = Get-Content -Raw -LiteralPath $skillPath
$yaml = Get-Content -Raw -LiteralPath $agentPath
if ($skill -notmatch '(?s)^---\r?\nname: new-project-setup\r?\ndescription: [^\r\n]+\r?\n---\r?\n') {
    throw "SKILL.md frontmatter is invalid."
}
if ((Get-Content -LiteralPath $skillPath).Count -ge 300) {
    throw "SKILL.md must remain comfortably under 300 lines."
}
if ($skill.Length -gt 8500) {
    throw "SKILL.md exceeds the 8,500-character release ceiling."
}

foreach ($key in @('display_name', 'short_description', 'default_prompt')) {
    $pattern = '(?m)^\s+' + [Regex]::Escape($key) + ': "[^"]+"\s*$'
    if ($yaml -notmatch $pattern) { throw "agents/openai.yaml is missing quoted $key." }
}
if ($yaml -notmatch '\$new-project-setup') { throw "default_prompt must name `$new-project-setup." }
if ($yaml -notmatch '(?m)^\s+allow_implicit_invocation: true\s*$') { throw "New-project setup skill must allow implicit invocation." }

# PyYAML is a release-validation dependency only. The target apply helper does
# not call this script and therefore does not acquire a Python dependency.
$pythonCandidates = New-Object Collections.Generic.List[object]
foreach ($name in @('python3', 'python')) {
    $pythonCommand = Get-Command $name -ErrorAction SilentlyContinue
    if ($pythonCommand -and -not @($pythonCandidates | Where-Object Executable -eq $pythonCommand.Source).Count) {
        $pythonCandidates.Add([pscustomobject]@{ Executable = $pythonCommand.Source; Prefix = @() })
    }
}
$pyCommand = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { Get-Command py -ErrorAction SilentlyContinue } else { $null }
if ($pyCommand -and -not @($pythonCandidates | Where-Object Executable -eq $pyCommand.Source).Count) {
    $pythonCandidates.Add([pscustomobject]@{ Executable = $pyCommand.Source; Prefix = @('-3') })
}
$pythonRuntime = $null
foreach ($candidate in $pythonCandidates) {
    $probeArgs = @($candidate.Prefix) + @('-c', 'import sys, yaml; raise SystemExit(0 if sys.version_info.major == 3 else 1)')
    try {
        & $candidate.Executable @probeArgs *> $null
        if ($LASTEXITCODE -eq 0) {
            $pythonRuntime = $candidate
            break
        }
    }
    catch {}
}
if ($null -eq $pythonRuntime) {
    throw "Release validation requires an available Python runtime with PyYAML; normal target setup does not."
}

$semanticYamlValidator = @'
import copy
import re
import sys
from pathlib import Path

import yaml


class ContractError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise ContractError(message)


class UniqueKeyLoader(yaml.SafeLoader):
    pass


def construct_unique_mapping(loader, node, deep=False):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise ContractError(f"duplicate YAML key: {key}")
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
    construct_unique_mapping,
)


def load_unique(text, label):
    try:
        data = yaml.load(text, Loader=UniqueKeyLoader)
    except (yaml.YAMLError, ContractError) as exc:
        raise ContractError(f"{label}: {exc}") from exc
    require(type(data) is dict, f"{label}: root must be a mapping")
    return data


def require_exact_keys(data, expected, label):
    require(set(data) == set(expected), f"{label}: expected keys {sorted(expected)}, got {sorted(data)}")


def validate_skill_metadata(data):
    require_exact_keys(data, {"name", "description"}, "SKILL.md frontmatter")
    require(data["name"] == "new-project-setup", "SKILL.md frontmatter: invalid name")
    require(type(data["description"]) is str and data["description"].strip(), "SKILL.md frontmatter: description must be text")
    description = data["description"].lower()
    require("ordinary requests to create or build a new durable app" in description, "SKILL.md frontmatter: new durable app activation is missing")
    require("do not trigger" in description and "inside an existing project" in description, "SKILL.md frontmatter: existing-project exclusion is missing")


def validate_agent_metadata(data):
    require_exact_keys(data, {"interface", "policy"}, "agents/openai.yaml")
    require(type(data["interface"]) is dict, "agents/openai.yaml: interface must be a mapping")
    require(type(data["policy"]) is dict, "agents/openai.yaml: policy must be a mapping")
    require_exact_keys(data["interface"], {"display_name", "short_description", "default_prompt"}, "agents/openai.yaml interface")
    require_exact_keys(data["policy"], {"allow_implicit_invocation"}, "agents/openai.yaml policy")
    for key in ("display_name", "short_description", "default_prompt"):
        require(type(data["interface"][key]) is str and data["interface"][key].strip(), f"agents/openai.yaml: {key} must be non-empty text")
    require(len(data["interface"]["short_description"]) <= 80, "agents/openai.yaml: short_description exceeds 80 characters")
    prompt = data["interface"]["default_prompt"].lower()
    require("$new-project-setup" in prompt, "agents/openai.yaml: default_prompt must name the skill")
    require("creating a new durable app or project" in prompt, "agents/openai.yaml: new-app activation is missing")
    require("do not invoke" in prompt and "inside an existing project" in prompt, "agents/openai.yaml: existing-project exclusion is missing")
    require(data["policy"]["allow_implicit_invocation"] is True, "agents/openai.yaml: allow_implicit_invocation must be boolean true")


def expect_rejection(action, label):
    try:
        action()
    except ContractError:
        return
    raise ContractError(f"semantic mutation was accepted: {label}")


root = Path(sys.argv[1])
skill_text = (root / "SKILL.md").read_text(encoding="utf-8-sig")
agent_text = (root / "agents" / "openai.yaml").read_text(encoding="utf-8-sig")
frontmatter_match = re.match(r"\A---\r?\n(.*?)\r?\n---\r?\n", skill_text, re.DOTALL)
require(frontmatter_match is not None, "SKILL.md: frontmatter block is missing")
skill_metadata = load_unique(frontmatter_match.group(1), "SKILL.md frontmatter")
agent_metadata = load_unique(agent_text, "agents/openai.yaml")
validate_skill_metadata(skill_metadata)
validate_agent_metadata(agent_metadata)

implicit_string = copy.deepcopy(agent_metadata)
implicit_string["policy"]["allow_implicit_invocation"] = "true"
expect_rejection(lambda: validate_agent_metadata(implicit_string), "implicit invocation string instead of boolean")

missing_app_activation = copy.deepcopy(skill_metadata)
missing_app_activation["description"] = missing_app_activation["description"].replace("new durable app", "durable workflow")
expect_rejection(lambda: validate_skill_metadata(missing_app_activation), "missing new durable app activation")

missing_existing_exclusion = copy.deepcopy(agent_metadata)
missing_existing_exclusion["interface"]["default_prompt"] = "Use $new-project-setup when creating a new durable app or project."
expect_rejection(lambda: validate_agent_metadata(missing_existing_exclusion), "missing existing-project exclusion")

expect_rejection(
    lambda: load_unique("policy:\n  allow_implicit_invocation: true\npolicy:\n  allow_implicit_invocation: true\n", "duplicate-key mutant"),
    "duplicate top-level YAML key",
)

print("semantic-yaml-ok mutations=4")
'@

$semanticArgs = @($pythonRuntime.Prefix) + @('-', $root)
$previousErrorPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $semanticOutput = $semanticYamlValidator | & $pythonRuntime.Executable @semanticArgs 2>&1
}
finally {
    $ErrorActionPreference = $previousErrorPreference
}
if ($LASTEXITCODE -ne 0) {
    throw "Semantic YAML validation failed: $($semanticOutput -join ' ')"
}
if (($semanticOutput -join "`n") -notmatch 'semantic-yaml-ok mutations=4') {
    throw "Semantic YAML validation did not report all mutation checks."
}

$checklist = Get-Content -Raw -LiteralPath (Join-Path $root 'references/new-project-setup-checklist.md')
$installText = Get-Content -Raw -LiteralPath (Join-Path $root 'references/install-and-migration.md')
$executionText = Get-Content -Raw -LiteralPath (Join-Path $root 'references/execution-and-memory.md')
$historyText = Get-Content -Raw -LiteralPath (Join-Path $root 'references/github-history.md')
if ($checklist -notmatch '(?m)^## Reference Routing\s*$') { throw "Completion checklist must route conditional references." }

foreach ($relative in @(
    'scripts/apply-project-setup.ps1',
    'scripts/github-backup.ps1',
    'scripts/github-sync.ps1',
    'scripts/invoke-powershell.ps1',
    'scripts/validate-skill.ps1'
)) {
    $tokens = $null
    $errors = $null
    $scriptPath = Join-Path $root $relative
    [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count) { throw "$relative parse failure: $($errors.Message -join '; ')" }
    if (@([IO.File]::ReadAllBytes($scriptPath) | Where-Object { $_ -gt 127 }).Count -gt 0) {
        throw "$relative must remain ASCII-compatible UTF-8 without BOM for Windows PowerShell 5.1 and PowerShell 7."
    }
}

$psLauncher = Get-Content -Raw -LiteralPath (Join-Path $root 'scripts/invoke-powershell.ps1')
$shLauncher = Get-Content -Raw -LiteralPath (Join-Path $root 'scripts/invoke-powershell.sh')
if ($psLauncher -notmatch 'Get-Command\s+\$name' -or $psLauncher -notmatch "'pwsh\.exe', 'pwsh'" -or
    $psLauncher -notmatch 'powershell\.exe' -or
    $psLauncher -notmatch 'PSVersionTable\.PSVersion\.Major -ge 7' -or
    $psLauncher -notmatch 'UseShellExecute\s*=\s*\$false' -or
    $psLauncher -notmatch 'ConvertTo-WindowsCommandLineArgument' -or
    $psLauncher -match '%\*') {
    throw 'PowerShell launcher must prefer PowerShell 7, retain the Windows fallback, and avoid cmd.exe argument replay.'
}
if ($shLauncher -notmatch 'command -v pwsh' -or $shLauncher -notmatch 'PSVersionTable\.PSVersion\.Major -ge 7' -or
    $shLauncher -match '(?im)^\s*powershell(?:\.exe)?\b') {
    throw 'POSIX launcher must require PowerShell 7 without a Windows PowerShell fallback.'
}

$apply = Get-Content -Raw -LiteralPath (Join-Path $root 'scripts/apply-project-setup.ps1')
foreach ($marker in @(
    'WorkflowVersion = 6', 'new-project-setup:v6:start',
    'docs/development-log.md', 'docs/codex-handoff.md',
    'source_authority', 'automation_runtime', 'platform_support',
    'path_comparison', 'text_eol', 'target_path_policy', 'managed_marker_policy',
    'apply_preflight', 'operation_lock', 'input_immutability',
    'apply_transaction', 'helper_ownership', 'managed_helpers',
    'execution_mode', 'durability_ambiguity_action',
    'routine_project_dependencies', 'new_project_stack',
    'isolated_local_build', 'exploration_cleanup',
    'deployment_confirmation', 'documentation_detail',
    'handoff_presence', 'handoff_refresh', 'handoff_evidence',
    'handoff_sync_reference', 'context_loading',
    'effort_classification', 'validation_strategy', 'risk_set',
    'precommit_audit', 'precommit_attestation',
    'normal_history_audit', 'public_readiness_audit',
    'sync_cadence', 'focused_sync_commit_threshold',
    'focused_sync_time_trigger', 'source_history_recovery',
    'legacy_history_preservation', 'recovery_destination',
    'recovery_retry',
    'evidence_reuse', 'evidence_definition', 'convergence_action',
    'convergence_escalation', 'final_validation_matrix',
    'final_validation_scope', 'unresolved_local_failure',
    'Assert-TargetPath', 'Get-ExistingManagedMarker',
    'Assert-ManagedHelperOwnership',
    'Refusing to apply an installed runtime'
)) {
    if ($apply -notmatch [Regex]::Escape($marker)) { throw "Version-6 apply helper is missing marker: $marker" }
}

$policyText = $skill + "`n" + $checklist + "`n" + $installText + "`n" + $executionText + "`n" + $historyText
$normalizedPolicy = ($policyText -replace '\s+', ' ').ToLowerInvariant()
$normalizedSkill = ($skill -replace '\s+', ' ').ToLowerInvariant()
$normalizedChecklist = ($checklist -replace '\s+', ' ').ToLowerInvariant()
$normalizedExecution = ($executionText -replace '\s+', ' ').ToLowerInvariant()
$completionCore = 'claim completion only when every acceptance criterion passes, every material risk or protected boundary has distinct evidence, no unresolved high-risk failure remains, and durable records are current.'
$deploymentCore = 'deployment requires confirmation immediately before the action unless the current request explicitly names the deployment target and effect and waives that additional checkpoint; that explicit waiver is the confirmation. a request that merely asks for deployment is not a waiver.'

foreach ($surface in @(
    @{ Name = 'SKILL.md'; Text = $normalizedSkill },
    @{ Name = 'references/execution-and-memory.md'; Text = $normalizedExecution }
)) {
    if (-not $surface.Text.Contains($completionCore)) { throw "$($surface.Name) does not use the shared completion/evidence invariant." }
    if (-not $surface.Text.Contains('stop unresolved only when the latest strategy made no material progress and no credible bounded probe remains')) {
        throw "$($surface.Name) does not use the shared unresolved terminal condition."
    }
}
foreach ($surface in @(
    @{ Name = 'SKILL.md'; Text = $normalizedSkill },
    @{ Name = 'references/execution-and-memory.md'; Text = $normalizedExecution },
    @{ Name = 'references/new-project-setup-checklist.md'; Text = $normalizedChecklist }
)) {
    if (-not $surface.Text.Contains($deploymentCore)) { throw "$($surface.Name) does not use the shared deployment-waiver semantics." }
}
if ($installText -notmatch 'single completion/evidence invariant' -or $historyText -notmatch 'single completion/evidence invariant') {
    throw "Conditional references must route to the single completion/evidence invariant."
}

foreach ($marker in @(
    'new durable app', 'inside an existing project', 'genuinely ambiguous',
    'project-local dependencies', 'new empty local database', 'initial stack',
    'never demote', 'confirmed unused', 'proportional', 'progressive context',
    'risk/evidence ledger', 'materially different risk or protected boundary',
    'different code path', 'credible bounded probe', 'no material progress',
    'one effort-appropriate final matrix', 'bookkeeping-only',
    'explicit waiver is the confirmation'
)) {
    if (-not $normalizedPolicy.Contains($marker.ToLowerInvariant())) { throw "Adaptive policy guidance is missing marker: $marker" }
}
if ($skill -match 'Read `references/new-project-setup-checklist.md` before changing') {
    throw "SKILL.md must not require unconditional full-checklist loading."
}
foreach ($reference in @('install-and-migration.md', 'execution-and-memory.md', 'github-history.md', 'new-project-setup-checklist.md')) {
    if ($skill -notmatch [Regex]::Escape($reference)) { throw "SKILL.md does not route conditional reference: $reference" }
}

$invariants = [ordered]@{
    'bare invocation executes' = 'bare or primary.*invocation.*runs install/sync'
    'ordinary new app creation activates' = 'ordinary request.*create or build a new durable app.*new project'
    'existing project work does not activate' = 'Do not activate for.*inside an\s+existing project'
    'consultation does not edit' = 'consultation-only.*authorizes no edits'
    'single target isolation' = 'Never update an accessible sibling project'
    'source and target maintenance are separated' = 'In another\s+project,.*do not modify this source or\s+runtime'
    'runtime selection is automatic and stack neutral' = 'PowerShell-first.*without choosing an application\s+stack.*Prefer PowerShell 7.*Windows\s+PowerShell 5\.1 on Windows.*user\s+should not need to select a runtime'
    'durability and risk remain independent' = 'durability, operational risk, and effort independently'
    'routine work does not prompt' = 'without routine implementation or\s+validation questions'
    'quick does not mean disposable' = 'Quick.*prototype.*MVP.*do not mean disposable'
    'exploration promotes and lasting work does not demote' = 'Promote useful exploration automatically.*never demote lasting work'
    'bounded local build authority remains' = 'bounded local build authorizes architecture'
    'lasting revisions remain in Git' = 'Preserve every lasting revision in Git'
    'durable memory remains proportional' = 'public-ready memory only when it\s+adds future value'
    'evidence is risk or boundary based' = 'Evidence is distinct only when.*materially different\s+risk or protected boundary'
    'code path alone is equivalent evidence' = 'different code path.*alone.*equivalent evidence|different code path.*alone does not make evidence distinct'
    'terminal stop requires no progress and no probe' = 'stop unresolved only when.*no material progress.*no credible bounded probe'
    'deployment waiver is immediate and explicit' = 'Deployment requires confirmation immediately.*waives.*explicit waiver is the confirmation.*merely asks for deployment is not a waiver'
    'source history remains private and fast-forward only' = 'private.*fast-forward push'
    'staged snapshot is audited before commit' = 'PreCommit.*CommitMessage.*exact (?:audited )?staged tree'
    'focused changes batch at ten commits' = 'one through nine.*local commits.*tenth.*synchronizes'
    'focused batching has no time trigger' = 'no time trigger'
    'material and requested sync remains immediate' = 'initial setup.*standard or\s+substantial.*milestones.*releases.*explicit sync.*immediate'
    'normal history audit uses verified remote boundary' = 'verified (?:private remote|destination) tip.*current snapshot.*every.*commit|current snapshot.*every commit after.*verified private remote tip'
    'public readiness retains full ancestry' = 'public-readiness.*full ancestry|full ancestry.*public-readiness'
    'legacy recovery is explicit and preserves history' = '(?:explicit|authorized).*clean-baseline recovery.*local hidden refs|clean-baseline recovery.*explicit.*local hidden refs'
    'isolated fallback remains explicit' = 'ask (?:whether )?(?:to use|to run|for).*fallback.*remain local-only|fallback or local-only.*explicit'
    'fallback does not alter normal remote' = 'fallback.*(?:never|must not).*(?:modify|disable|replace).*normal.*remote'
}
foreach ($entry in $invariants.GetEnumerator()) {
    if ($policyText -notmatch ('(?is)' + $entry.Value)) { throw "Behavior invariant missing: $($entry.Key)" }
}

$sync = Get-Content -Raw -LiteralPath (Join-Path $root 'scripts/github-sync.ps1')
foreach ($marker in @(
    'AuditSourceHistory', 'Initialize', 'PublicReadiness', 'PRIVATE',
    'merge-base', 'Source HEAD or branch changed', 'PreCommit',
    'CommitMessage', 'BatchEligible', 'HistoryBaseCommit',
    'FullSourceHistory',
    'RecoverLegacyAncestry', 'ExpectedLegacyHead',
    'private-source-strict-public-readiness',
    'refs/codex/legacy-history', '10'
)) {
    if ($sync -notmatch [Regex]::Escape($marker)) { throw "GitHub sync helper is missing safety marker: $marker" }
}
$backup = Get-Content -Raw -LiteralPath (Join-Path $root 'scripts/github-backup.ps1')
foreach ($marker in @('CandidateCommit', 'HistoryBaseCommit', 'FullSourceHistory')) {
    if ($backup -notmatch [Regex]::Escape($marker)) { throw "GitHub backup helper is missing audit marker: $marker" }
}
foreach ($marker in @('PrivateSourceSync', 'operational-metadata', 'Get-LineNumberForIndex')) {
    if ($backup -notmatch [Regex]::Escape($marker)) { throw "GitHub backup helper is missing private-source audit marker: $marker" }
}
if ($sync -notmatch 'PrivateSourceSync') { throw 'GitHub sync helper must use private-source audit mode for normal synchronization.' }
foreach ($auditScript in @($sync, $backup)) {
    if ($auditScript -match 'FileAttributes\]::ReparsePoint') {
        throw 'Audit helpers must distinguish actual link targets from nonredirecting cloud reparse metadata.'
    }
}
foreach ($relative in @('scripts/github-sync.ps1', 'scripts/github-backup.ps1')) {
    if ((Get-Content -Raw -LiteralPath (Join-Path $root $relative)) -notmatch '(?m)^# new-project-setup:managed-helper:v1$') {
        throw "Managed helper ownership marker is missing: $relative"
    }
}

Write-Host "Validated new-project-setup skill payload at $root (semantic YAML mutations: 4)"
