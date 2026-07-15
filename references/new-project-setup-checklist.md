# New Project Setup Checklist

## Contents

- [Install or sync](#1-install-or-sync)
- [Prerequisites and local Git](#2-prerequisites-and-local-git)
- [Durable project memory](#3-durable-project-memory)
- [Adaptive work execution](#4-adaptive-work-execution)
- [Private public-ready GitHub history](#5-private-public-ready-github-history)
- [Audit failure and sanitized fallback](#6-audit-failure-and-sanitized-fallback)
- [Migration and public readiness](#7-migration-and-public-readiness)
- [Protected boundaries](#8-protected-boundaries)
- [Completion check](#9-completion-check)

Use this checklist to install or synchronize a low-intervention workflow in one
resolved target project. Codex owns routine Git, documentation, validation,
commit, audit, and synchronization steps so the user does not need to remember
them.

Every GitHub repository starts private, but all pushed source, commit messages,
development memory, and changelog content must be suitable for possible public
release. Local Git remains the working copy. The private GitHub repository is
the normal off-site revision history.

A bare `$new-project-setup` invocation applies or synchronizes this workflow.
A question about the skill is consultation-only and changes nothing. The skill
may activate implicitly for a request that creates or initializes a new durable
project, but not merely because an existing repository was opened.

## 1. Install Or Sync

Resolve exactly one target in this order:

1. Explicit path in the current request.
2. Active chat or task project.
3. Current repository when unambiguous.
4. Ask which single project is intended.

Never update sibling workspace roots in bulk. When the target is this skill
source project, use maintenance mode and synchronize the installed runtime copy
after changing reusable behavior. For any other target, apply the installed
workflow without modifying the skill source or runtime installation.

Inspect before editing:

- Git, Git identity, PowerShell, `tar`, GitHub CLI, and `gh auth status`
- repository root, status, branch, `HEAD`, remotes, and upstream
- cloud-synchronized folder location
- existing managed markers and `.codex/new-project-setup.json`
- `AGENTS.md`, ignore/attributes rules, changelog, development log, and handoff
- unrelated or overlapping dirty work

Use install mode when workflow state is absent. Use sync mode when managed
markers, workflow state, or prior setup history exists. Run:

```powershell
& <installed-skill>\scripts\apply-project-setup.ps1 -ProjectRoot <project>
```

Pass `-Repository owner/name` and `-RemoteName <name>` when known. Use `-Check`
only for non-mutating drift reporting. Preserve project-specific content outside
managed markers.

## 2. Prerequisites And Local Git

Detect prerequisites automatically. Ask before installing packages or changing
machine-level Git identity, run approved setup commands, recheck, and continue.

Initialize Git only when absent. Establish safe ignore rules before staging and
use a line-ending policy appropriate for cross-platform work. Warn when Git is
inside OneDrive, Dropbox, Google Drive, or another synchronized folder; GitHub,
not folder synchronization, is the repository transport.

Before each scoped commit, record branch, `HEAD`, and intended paths. Recheck
them immediately before staging and committing. Stop if another session changes
the branch, `HEAD`, or overlapping files. Never stage unrelated work.

## 3. Durable Project Memory

Create and track `docs/development-log.md`. Keep entries public-ready and
human-readable. At completed work-package boundaries, record:

- objective and completed work
- important decisions and rationale
- useful failed approaches or experiments
- validation performed or why it was skipped
- durable lessons that should guide later work

Create and track `docs/codex-handoff.md` for every durable project. Keep it
concise and replace-in-place with:

- current objective and state
- one next action
- blockers or required user input
- important recent decisions
- branch, commit, and GitHub synchronization status
- completed and remaining validation

At the start of each durable task, read `AGENTS.md`, the handoff, the three most
recent development-log entries, relevant changelog entries, and Git status.
Preserve every lasting change in revision history, but keep other records
proportional:

- update the development log only for useful decisions, rationale, failed
  approaches, validation, or durable lessons
- refresh the handoff when objective, state, blockers, next action, or
  continuation context changes
- update the changelog only for notable reader-facing changes

Do not update every memory file mechanically after a trivial edit.

Use `CHANGELOG.md` for notable reader-facing additions, changes, fixes,
documentation, setup, releases, and version history. Preserve an existing
version scheme. When none exists, Git commits are the revision history; do not
invent release numbers or tags before an explicit milestone.

Credentials, regulated data, machine paths, internal endpoints, and other
information that cannot safely become public belong in ignored `*.local.md` or
approved external secret storage. Never weaken this rule because a repository
is currently private.

## 4. Adaptive Work Execution

Classify durability and operational risk independently. Use project context and
ordinary user intent, not magic phrases, rigid file counts, or time thresholds.
When classification is clear, state it in one short non-blocking sentence and
continue:

- **Small lasting change:** preserve the revision, validate narrowly, and use
  proportional records.
- **Normal lasting work:** use for applications, features, fixes, continued
  project work, and reusable output. Complete the bounded objective end-to-end.
- **Exploration:** use only when the goal clearly centers on learning,
  comparison, or disposable feasibility. Keep outputs local while exploratory.

`Quick`, `prototype`, `proof of concept`, and `MVP` can describe desired speed
or maturity. None alone authorizes disposable treatment. If durability is
genuinely ambiguous, ask one plain-language question: whether the user may want
to keep and continue the result or wants only an experiment. Recommend
preservation. Do not require the user to know workflow terms.

Reassess after meaningful changes. Automatically promote exploration when its
output becomes useful, reusable, or continued. Once promoted, apply normal
memory and completion rules. Never demote lasting work, delete output, or
discard history automatically.

A bounded request such as `build this app` authorizes routine isolated local
construction. Codex may choose architecture and implementation details, create
project structure, add established project-local dependencies, generate files,
write tests, create demo data, and create schemas or migrations for a new empty
local database. These are normal implementation choices, not separate approval
boundaries.

For normal file-changing work:

1. Complete the bounded objective within the authority reasonably implied by
   the request and any explicit approvals.
2. Validate after meaningful chunks and fix clearly in-scope failures.
3. Update durable records only where they add the proportional context defined
   above.
4. Review status and diff, then stage only scoped paths.
5. Run `git diff --cached --check` and the smallest final validation.
6. Recheck branch and `HEAD`, then create one clear local commit.
7. Run `scripts/github-sync.ps1` against committed `HEAD`.
8. Report validation, commit, synchronization, and unresolved gaps.

Clearly exploratory work receives focused smoke validation and may skip routine
memory, commits, and synchronization while it remains exploratory. It does not
authorize consequential actions listed under protected boundaries.

## 5. Private Public-Ready GitHub History

`scripts/github-sync.ps1` is the normal off-site workflow. It must use the real
source branch and meaningful source commits, not reconstructed snapshots.

Before the first push:

- read workflow state from committed `HEAD`
- audit the complete current snapshot and every reachable source commit
- block forbidden tracked paths, credentials, private keys, tokens, connection
  strings, private networks, machine-user paths, operational endpoints,
  unsupported Git objects, LFS pointers, oversized text, and unreviewed binaries
- report finding rule IDs and paths only, never matched values
- verify `gh` authentication and repository visibility

When no GitHub remote exists, create a private repository under the currently
authenticated GitHub account. Use `origin` if no remote exists. Preserve a
non-GitHub `origin` and use `github` instead. Record the repository slug and
remote in version-4 state before the setup commit and first push. Run
`scripts/github-sync.ps1 -Initialize` during setup when the destination is not
already recorded; commit the updated workflow state before synchronization.

For every push:

- audit committed source history through the shared scanner
- recheck source `HEAD`
- verify the destination remains private
- fetch the target branch
- require the remote tip to be an ancestor of local `HEAD`
- allow only a fast-forward push
- never force-push, rewrite history, resolve divergence automatically, or
  change visibility

Dirty or untracked files remain local-only until intentionally committed. They
do not alter the audit of committed `HEAD` and must never be staged merely to
make synchronization appear complete.

## 6. Audit Failure And Sanitized Fallback

If source-history audit fails:

1. Keep the local commit.
2. Do not push, rewrite, scrub, or amend history automatically.
3. Report only finding rule IDs and paths.
4. Ask whether to run `scripts/github-backup.ps1` or remain local-only.
5. Ask again for each future blocked audit; do not persist the answer.

The sanitized helper remains an isolated-history fallback. It builds a complete
snapshot from committed `HEAD`, applies committed policy and exclusions, scans
all included files, audits every reachable fallback commit, uses a neutral
identity, and pushes to a separate private repository. It must exclude legacy
`docs/work-log.md` and `*.local.md` by default.

Fallback configuration remains in committed `.github-backup.json`. Dirty policy
cannot weaken scanning. Fingerprinted allowances must bind rule, path, and exact
file SHA-256. Never add an allowance merely to make a scan pass.

## 7. Migration And Public Readiness

Version-4 setup creates:

- managed version-4 blocks in `AGENTS.md`, `.gitignore`, and `.gitattributes`
- `docs/development-log.md`
- `docs/codex-handoff.md`
- `CHANGELOG.md` when absent
- both GitHub helpers
- format-2 `.codex/new-project-setup.json` with workflow version 4,
  `github_mode: private-public-ready`, source-history sync enabled,
  `audit_failure_action: ask`, durable memory enabled, and these adaptive fields:
  `execution_mode: adaptive`, `durability_ambiguity_action: ask`,
  `classification_notice: concise`, `routine_project_dependencies: allow`,
  `isolated_local_build: allow`, and `documentation_detail: proportional`

When migrating version 2 or version 3:

- replace only managed blocks from the prior workflow version
- preserve all project-specific guidance and legacy files
- never delete, untrack, sanitize, or rewrite old history automatically
- create new public-ready development memory
- summarize useful legacy knowledge only after reviewing and sanitizing it
- audit all source ancestry before enabling normal GitHub push
- if legacy history blocks, offer fallback or a separately authorized history
  remediation plan

`scripts/github-sync.ps1 -PublicReadiness` performs a read-only full-history
assessment. Making a repository public is a separate explicit action requiring
another visibility, licensing, ownership, and confidentiality review.

## 8. Protected Boundaries

Ask before deployment; credentials or live/paid services; auth/security
changes; global or native tool installation; framework or platform replacement;
consequential licensing changes; changes to existing, shared, or production
data; destructive operations; material product-direction expansion beyond the
request; unrelated conflicting work; or any unsafe state.

Do not stop for internal refactoring, established project-local dependencies,
or isolated local structure, generated files, tests, demo data, and new empty
local-database schemas that remain inside the bounded objective. Risk is an
overlay on the work classification, not a reason to turn ordinary local app
construction into a checkpoint-heavy process.

Never transfer source ancestry that failed audit. Never assume private GitHub
visibility makes secrets acceptable. Never use matched secret values in output.
Never update another project merely because it is accessible.

## 9. Completion Check

Before treating setup or sync as complete, verify:

- the correct single target was resolved
- consultation-only questions made no changes
- prerequisites and Git identity are ready or clearly reported pending
- version-4 apply is idempotent in `-Check` mode
- project-specific content outside managed markers is preserved
- development log, handoff, changelog, and both helpers exist
- workflow state contains the required version-4 public-ready and adaptive settings
- AGENTS guidance reads memory at task start and updates it at package end
- adaptive classification, promotion, proportional memory, local-build
  authority, and protected-boundary rules remain explicit
- helper scripts parse successfully
- full source-history scan passes, or the exact safe blocker is reported
- GitHub destination is private and fast-forward-only when synchronization runs
- audit failure asks before fallback and never rewrites history
- installed runtime skill is synchronized when this source project changed
- scoped local commit and final GitHub result are reported
