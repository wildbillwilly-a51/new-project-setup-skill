# Execution And Continuity

Use this reference when ordinary project instructions are insufficient for an
execution, validation, authorization, or memory exception.

## Preservation Decisions

Treat implementation and retained reusable output as durable. Investigation is
disposable only when its purpose is clearly learning and no output is retained.
Ask one short preservation question when the distinction remains genuinely
ambiguous and affects the result. Promote exploration automatically when it is
reused, continued, incorporated into durable work, or requested for retention.

Temporary artifacts created for the current investigation may be removed after
confirming they are unused and uncommitted. Do not remove prior, unrelated, or
uncertain artifacts.

## Context Routes

For continuation, read the managed project instructions, current handoff, and
directly relevant files. Read the project summary only when broader orientation
is needed.

For a new objective, read the managed instructions, project summary, directly
relevant files, and the handoff only when unresolved or overlapping work is
relevant.

For another project, read its project summary first. Read its handoff only when
in-progress work matters; do not scan the other repository by default.

Read `docs/development-log.md` only when the current objective depends on prior
rationale, a known failed approach, a previously discovered constraint, or
historical validation evidence. It is not part of default orientation.

When memory is missing, stale, or contradictory, reconstruct only the state
needed for the objective from Git and relevant evidence. Refresh the affected
summary or handoff. Broaden discovery only when the remaining contradiction or
risk requires it.

## Validation And Diagnosis

Identify completion conditions and material risks internally. Select the
smallest checks that cover the changed risks, including integration boundaries
when those boundaries changed. Existing passing evidence remains usable until
the implementation, dependency, environment, configuration, or expected
behavior it covers changes.

After a failure, preserve unaffected evidence and rerun only failed or
invalidated checks. Do not repeat an equivalent failing command without a new
hypothesis or changed conditions. Change strategy first. Create a minimal
reproduction only when isolating the behavior is likely to distinguish causes
or reduce the search space.

If work remains unresolved, record the blocker, useful diagnostics, completed
validation, remaining validation, and one concrete next action in the handoff.
Do not claim completion while a material blocker remains.

## Protected Actions

Request authorization immediately before a destructive operation, deployment,
production or shared-data change, credential or authentication change, paid
service use, global or native installation, external side effect, or material
expansion beyond the objective.

When deployment is requested, confirm the target and effect immediately before
deployment unless the current request already names both and explicitly
authorizes that effect. Authorization for analysis or implementation does not
implicitly authorize deployment.

## Durable Memory

Keep `docs/project-summary.md` stable and task-independent. Replace obsolete
task history in `docs/codex-handoff.md`; do not accumulate a transcript.

Create or update `docs/development-log.md` only when a non-obvious decision and
rationale has future maintenance value, a failed approach is likely to recur,
validation revealed an important constraint, or a durable lesson would
otherwise require rediscovery.

Maintain `CHANGELOG.md` only when the project already uses one or a change
materially affects users, setup, compatibility, operation, or public behavior.
Do not create a changelog mechanically for every project, task, or commit.
