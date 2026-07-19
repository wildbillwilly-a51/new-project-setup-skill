# Efficient Execution And Durable Memory

Read this reference only when execution classification, context depth,
documentation, convergence, or a protected boundary needs interpretation.

## Three Independent Axes

Infer from ordinary intent and project evidence rather than magic phrases,
file counts, time thresholds, or routine questions.

### Durability

- **Lasting:** applications, features, fixes, continued project work, and
  reusable output. Preserve revisions and durable memory.
- **Exploratory:** work clearly centered on learning, comparison, or disposable
  feasibility. Keep it local while it remains exploratory.

`Quick`, `prototype`, `proof of concept`, and `MVP` describe speed or maturity,
not disposability. If durability is genuinely ambiguous, ask one plain-language
preservation question and recommend preservation. Promote useful or continued
exploration automatically. Never demote lasting work, delete output, or discard
history automatically. Promotion occurs when output is reused, incorporated,
requested to be kept or continued, or becomes a dependency of lasting work.

### Operational Risk

Risk determines whether authorization is needed. It does not reduce ordinary
local implementation authority or force routine checkpoints.

### Effort And Validation Depth

- **Focused:** a narrow change with directly affected checks and no broad
  release consequence.
- **Standard:** a feature or multi-file change requiring primary workflows,
  distinct edge risks, and representative integration coverage.
- **Release-critical:** deployment preparation or high-impact change requiring
  broad, deduplicated release evidence, health, backup, or rollback checks that
  are inside approved scope.

State a clear classification briefly and continue. Effort controls context and
evidence depth, not authority. Reclassify automatically when failures or scope
show a materially different risk surface.

## Progressive Context

For durable work:

1. Start with Git status, `docs/codex-handoff.md`, and directly relevant files.
2. Read development-log or changelog excerpts only when they answer a current
   question or need an update.
3. Expand automatically when dependencies, failures, architecture, or risk
   require it; do not ask merely to inspect more relevant context.
4. Exclude sibling roots, dependencies, generated files, old artifacts, and
   verbose logs unless evidence makes them relevant.
5. Keep command output targeted and preserve conclusions rather than carrying
   superseded logs through later phases.
6. If the handoff is missing, stale, or contradictory, reconstruct objective
   and state from Git plus directly relevant project evidence. Ask only when a
   safe bounded objective still cannot be resolved.

Clearly exploratory work starts with directly relevant files only. Read Git
status before changing files; read durable memory when needed to avoid
conflicting work, and apply the durable context sequence immediately when
exploration promotes. Codex may remove only uncommitted artifacts it created in
the current clearly exploratory package and confirmed are not reused. Never
remove pre-existing, shared, promoted, or lasting output without authorization.

## Evidence And Convergence

Before implementation, identify internally:

- acceptance criteria
- changed risk dimensions
- evidence required for each material risk
- evidence already available and what would invalidate it
- completion conditions

Keep this as a compact working ledger, not a new user approval step. Establish
the initial distinct-risk set before broad validation and bound it to requested
acceptance criteria, material risks, and protected boundaries. Add only a
direct dependency or shared cause discovered inside that boundary and record
why. Report unrelated defects separately instead of expanding scope.

Evidence is distinct only when it covers a materially different risk or
protected boundary. A different code path, screenshot, data value, viewport,
theme, or view alone does not make evidence distinct. Several code paths may
support one risk claim, while one code path may require separate evidence for
different risks or protected boundaries.

Batch related failures and diagnose likely shared causes before patching. After
a change, retest invalidated areas first. Once targeted evidence passes, run one
broad final matrix appropriate to the effort tier and distinct risks; a focused
change may require only one direct check. If it fails, preserve passing evidence
and return to targeted diagnosis. Retest only failed or invalidated cells
afterward; do not create a new candidate to justify another broad matrix.

If two equivalent repair/review cycles make no material progress, change
diagnostic strategy: inspect a different layer, use a more deterministic probe,
or revisit the shared cause. If two strategy changes still make no material
progress, isolate a minimal reproducer. These thresholds force a strategy
change; they are not terminal attempt limits.

Material progress means resolving or narrowing a remaining criterion, risk, or
boundary with new valid evidence. A credible bounded probe is a finite check or
root-cause attempt inside the requested risk boundary with a reasonable chance
of producing that progress. Continue while either material progress is being
made or such a probe remains. When neither remains, preserve diagnostics, mark
an unresolved local blocker, stop broad work, and do not claim completion.
External-state, credential, and protected-action blockers are reported normally.

Use one completion/evidence invariant: claim completion only when every
acceptance criterion passes, every material risk or protected boundary has
distinct evidence, no unresolved high-risk failure remains, and durable records
are current. Evidence is distinct only when it covers a materially different
risk or protected boundary; code-path variation alone is equivalent evidence.
If completion cannot be reached, stop unresolved only when the latest strategy
made no material progress and no credible bounded probe remains. Preserve
diagnostics and report the blocker. Never skip distinct safety or release risks
to reduce token use.

## Durable Memory

Every lasting change belongs in scoped Git history. Other records are
proportional to future value:

- `docs/development-log.md` records useful decisions, rationale, failed
  approaches, validation, and durable lessons.
- `docs/codex-handoff.md` is concise and replace-in-place: objective, state,
  one next action, blockers, recent decisions, branch/commit/sync status, and
  completed/remaining validation.
- `CHANGELOG.md` records notable reader-facing changes and preserves any
  existing release scheme.

Do not mechanically update every memory file for a trivial edit. Preserve
important conclusions before compacting verbose context. Keep credentials,
regulated data, machine paths, internal endpoints, and private operations in
ignored `*.local.md` or approved secret storage.

Before every lasting Codex commit, stage only scoped work and audit the exact
staged tree and intended public-ready message through the precommit mode in
`github-history.md`; then commit them immediately without substitution. A
missing or mismatched attestation cannot qualify for deferred transfer and
fails safe to immediate normal audit and synchronization.

Focused small changes may accumulate locally through the verified ten-commit
cadence: one through nine local commits may defer the private push, and the
tenth synchronizes all. There is no time trigger. Initial setup, standard or
substantial work, milestones, releases, explicit sync requests, absent or empty
destinations, and uncertainty synchronize immediately. This cadence changes
only off-site timing; it never weakens local preservation, evidence, audit, or
completion requirements.

Refresh the handoff when the objective changes, a work package completes, work
blocks, an intentional handoff occurs, or commit/synchronization state changes.
Summarize valid evidence, invalidated evidence, and remaining validation at
those boundaries so a new task does not repeat completed checks. Prepare the
final handoff before its containing commit and describe commit/sync state as of
that commit. When a successful push matches the recorded intended state, report
it without creating a bookkeeping-only handoff commit. Edit the handoff again
only if objective, blockers, next action, evidence, or outcome changed.

## Protected Boundaries

Ask before deployment; credentials or live/paid services; auth/security
changes; global or native tool installation; framework or platform replacement;
consequential licensing changes; existing/shared/production data changes;
destructive operations; material product-direction expansion; unrelated
conflicting work; or unsafe state.

Protected boundaries override authority implied by the objective. Deployment
requires confirmation immediately before the action unless the current request
explicitly names the deployment target and effect and waives that additional
checkpoint; that explicit waiver is the confirmation. A request that merely
asks for deployment is not a waiver. Other protected actions still require
authorization. One confirmation may cover several protected effects only when
it explicitly identifies all of them.

A bounded local build authorizes architecture, implementation, established
project-local dependencies, tests, generated files, demo data, and schemas or
migrations for a new empty local database. Choosing a reasonable initial
framework and dependencies for a new empty project is an architecture choice;
replacing an existing framework or platform remains protected. Continue through
routine local steps without user checkpoints.
