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
