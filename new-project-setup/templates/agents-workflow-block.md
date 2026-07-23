<!-- new-project-setup:v7:start -->
## Project Workflow

1. Orient from Git status, `docs/codex-handoff.md`, and files directly relevant
   to the objective. Expand context only for dependencies, contradictions,
   failures, or material risks. For a new objective, use
   `docs/project-summary.md` before the handoff; when referencing another
   project, read its summary first and do not scan that repository by default.
2. Preserve implementation and retained reusable output. Clearly disposable
   investigation may remain lightweight, but preserve it when it is reused,
   continued, incorporated, or requested for retention.
3. Determine completion conditions and material risks internally. Ask only
   when ambiguity affects preservation, authorization, or the requested result.
4. Run the smallest checks that cover changed material risks. Reuse evidence
   that remains valid and rerun only checks that failed or were invalidated.
5. Do not repeat an equivalent failed check. Change diagnostic strategy and
   create a minimal reproduction when it is likely to clarify the cause.
6. Preserve unrelated staged, unstaged, and untracked work. Do not include an
   objective file in automatic saving when it contains known unrelated edits.
7. When durable work is complete, update continuity state when needed, stage
   only objective-related whole-file or whole-directory paths, verify the exact
   staged tree, and create a clear local commit. Local completion depends only
   on local Git.

The current handoff always contains Objective, Current State, and Validation
Completed. Include Relevant Decisions, Validation Remaining, and Blockers only
when they contain useful state. Include one Next Action only while work remains;
a completed objective does not need a fabricated continuation action. Keep the
handoff compact and replace obsolete task history rather than accumulating it.

Use `.codex/new-project-setup/execution-and-continuity.md` for exceptional
execution or memory cases and `.codex/new-project-setup/local-saving.md` for
local-save details.

Authorization is required before destructive operations, deployment,
production or shared-data changes, credential or authentication changes, paid
services, global or native installation, external side effects, or material
expansion beyond the objective.
<!-- new-project-setup:v7:end -->
