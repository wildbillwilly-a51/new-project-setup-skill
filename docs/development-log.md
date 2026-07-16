# Development Log

Keep entries public-ready: completed work, decisions and rationale, useful failed approaches, validation, and durable lessons.

## 2026-07-15

- Implemented workflow version 3 so durable projects keep public-ready
  development memory and an always-current Codex handoff in normal Git history.
- Added private GitHub destination initialization and audited synchronization of
  real source commits. The complete current snapshot is scanned every run;
  reachable history is fully scanned on first use or policy/history changes and
  incrementally scanned afterward. Pushes require private visibility,
  unchanged source `HEAD`, and fast-forward remote ancestry.
- Preserved the isolated sanitized repository as a user-selected fallback after
  a blocked source audit. Audit failure never chooses fallback, rewrites
  history, force-pushes, or changes repository visibility automatically.
- Migrated deterministic target setup to version 3 while preserving legacy
  logs and project-specific content. A Windows PowerShell UTF-8 BOM issue in
  generated `.gitattributes` was found during regression testing and fixed.
- Validation: source structure and PowerShell parsing passed; version-3 apply
  and check mode were idempotent; the complete regression suite passed clean
  source-history, incremental, visibility, divergence, migration, initialization,
  blocked-history, and isolated-fallback fixtures. Installed runtime validation
  and seven-file SHA-256 parity passed. The generic skill-creator Python
  validator could not run because PyYAML is unavailable; the checked-in
  validator performed equivalent frontmatter, interface, inventory, marker,
  and PowerShell parse checks.
- Operational result: the real source-history audit correctly blocked the
  legacy ancestry on `forbidden-history-path` and `machine-user-path` findings.
  No source history was pushed or rewritten. The user selected the sanitized
  fallback; its first authenticated run passed the safety scan and then found
  extra blank lines at EOF in two documentation files, which were corrected
  before retrying the isolated backup.
- The corrected fallback completed successfully. The isolated sanitized backup
  is current in its private GitHub repository; 18 files were included and one
  private file was excluded. The original source ancestry was not pushed or
  rewritten.
- Implemented workflow version 4 so Codex infers small-lasting, normal-lasting,
  or exploratory treatment from ordinary intent and project context. Clear
  classifications receive a one-line notice; genuinely ambiguous durability
  produces one plain-language preservation question. `Quick`, `prototype`, and
  `MVP` no longer imply disposable work, and useful exploration is promoted
  automatically without automatic demotion or deletion.
- Separated durability from operational risk. A bounded local app request now
  authorizes architecture choices, established project-local dependencies,
  generated files, tests, demo data, and schemas or migrations for a new empty
  local database. Consequential boundaries remain for deployment, live or paid
  services, credentials, auth/security, global/native tools, framework changes,
  licensing, existing/shared/production data, destructive work, and material
  product-direction expansion.
- Made documentation proportional: every lasting revision is preserved, while
  the development log, handoff, and changelog update only when they add useful
  future context. Added deterministic version-2 and version-3 migration to the
  version-4 managed policy and its six machine-readable adaptive state fields.
- Validation: source and installed validators, v4 apply/check idempotency,
  PowerShell parsing, seven-file SHA-256 runtime parity, and the complete
  regression suite passed. Five fresh-agent scenarios confirmed fast reusable
  app autonomy, one-question ambiguity handling, protected live/auth/deployment
  boundaries, proportional typo handling, and automatic exploration promotion.
  An independent review found one potentially restrictive `approved` phrase;
  replacing it with authority reasonably implied by the request resolved the
  concern on recheck. The generic skill-creator validator remains unavailable
  because PyYAML is not installed; no global dependency was added, and the
  checked-in validator covers frontmatter, interface, inventory, adaptive
  markers, and PowerShell parsing.
- Operational result: the committed version-4 source audit blocked only on the
  known legacy `forbidden-history-path` and `machine-user-path` findings. No
  source ancestry was pushed or rewritten. After the required fresh user
  choice, the isolated sanitized fallback passed with 18 files included and one
  private file excluded and became current in its private GitHub repository.
- Published the audited skill payload separately at
  `https://github.com/wildbillwilly-a51/new-project-setup-skill` under the MIT
  License. The public repository has isolated history, public installation and
  update instructions, and a verified installable payload. It is maintained
  only when the user requests a manual update; this does not change the
  reusable workflow or its private GitHub behavior.
- Established a version-4 efficiency baseline at source commit `6b25bc5`: an
  estimated 3,282 tokens in `SKILL.md`, 3,489 tokens in the mandatory checklist,
  6,770 tokens on the routine mandatory path, and 958 tokens in the generated
  managed policy. Source and installed validators, all PowerShell parser checks,
  exact runtime parity, and the complete regression suite passed before edits.
- Implemented workflow version 5 with progressive disclosure. Routine setup
  executes deterministic scripts without reading their source; prerequisite,
  execution/memory, GitHub-history, and final-audit details are now separate
  conditional references. Durable work starts with status, the concise handoff,
  and directly relevant files rather than unconditional log and checklist reads.
- Added an effort axis independent of durability and operational authority,
  compact distinct-risk evidence ledgers, evidence invalidation and reuse,
  shared-cause failure batching, one broad final validation matrix, and a
  bounded convergence path ending in preserved diagnostics and an honest local
  blocker when materially different root-cause attempts fail.
- Preserved low-intervention behavior and protected boundaries. The final policy
  clarifies new-project versus existing-project activation, safe exploratory
  cleanup, handoff evidence carryover, and separate confirmation immediately
  before deployment. Independent raw-artifact reviews drove these clarifications
  without exposing regression assertions or intended answers.
- Added deterministic version-4 migration, custom guidance and memory
  preservation fixtures, a frozen behavior baseline, nine automated behavior
  scenarios, and exact ten-file installed-payload manifests. No production
  project or manual user testing is used for evaluation.
- Measured the current routine mandatory path at approximately 2,450 tokens, a
  63.8% reduction from the version-4 baseline. The generated managed policy is
  approximately 1,064 tokens, 11.1% above baseline and within the explicit 15%
  guard while carrying the new effort, evidence, convergence, handoff, cleanup,
  and deployment rules. Tool-call and exact model-token telemetry are not
  exposed by the deterministic fixture, so those remain reported limitations.
- Final clean-agent reviews confirmed the scenario classifications and finite
  convergence behavior, then exposed source/runtime direction, redirected-path,
  malformed-marker, cleanup, and handoff-bookkeeping gaps. The apply helper now
  refuses installed-runtime overwrite of an authoritative source project,
  rejects links or junctions on managed paths before writing, fails closed on
  incomplete or duplicate markers, repairs empty memory files, and records
  handoff sync state relative to the containing commit.
- A final raw-artifact review found that unrelated scripts at the two managed
  helper paths could be overwritten and that a later preflight failure could
  leave partial setup. Helpers now carry ownership markers, exact known legacy
  hashes remain migratable, unowned collisions fail closed, and paths, markers,
  state JSON, bundled helpers, and helper ownership are all checked before the
  first write. Initial handoff creation now occurs only after managed state and
  helper writes succeed.
- Preserved the deliberate local-history security model: local Git may retain
  private content, while committed source-history audit blocks that ancestry
  from GitHub and routes only through explicit isolated sanitized fallback or a
  separate history-remediation task. A pre-commit gate that would prevent local
  preservation was therefore not added.
- Final validation passed the source and installed validators, eight PowerShell
  parser checks, apply/check idempotency, nine deterministic behavior scenarios,
  the complete adversarial regression suite, and exact inventory plus SHA-256
  parity for the ten-file installed runtime payload. The separate manually
  maintained public distribution was not inspected or changed.
