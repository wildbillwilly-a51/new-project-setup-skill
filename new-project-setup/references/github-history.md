# Private GitHub History

Read this reference only for GitHub initialization, audit, divergence,
synchronization, or sanitized fallback.

GitHub work uses the single completion/evidence invariant in
`execution-and-memory.md`. Audit, destination visibility, and fast-forward
status are distinct protected-boundary evidence; this reference does not define
an alternate completion rule.

## Before Every Lasting Codex Commit

Codex performs this automatically; the user does not need to remember commands.
Stage only the scoped changes, choose the exact public-ready commit message, and
run:

```powershell
scripts/github-sync.ps1 -PreCommit -CommitMessage '<exact message>'
```

This audits a candidate made from the exact staged tree and intended metadata.
Commit immediately with that exact tree and message. If either changes, stage
again and repeat the precommit audit. A missing, stale, or mismatched attestation
is never accepted for batching; post-commit handling fails safe to an immediate
normal audit and synchronization.

## Normal Source-History Synchronization

`scripts/github-sync.ps1` is the normal off-site workflow. It pushes meaningful
real source commits to a private repository rather than rebuilding snapshots.
Normal private synchronization blocks high-confidence secrets, credentials,
keys, connection strings, unsafe Git objects, and unreviewed risky file types.
Operational metadata such as private routes, LAN examples, machine paths, and
SSH endpoint notes is allowed on the private source route and remains part of
strict public-readiness or isolated sanitized-backup review.

Before a push, the helper verifies the exact destination, confirms private
visibility, fetches its branch, and captures its immutable tip. The audit then
covers the complete current snapshot and every local commit after that verified
tip. The tip must be an ancestor of local `HEAD`, which permits only a
fast-forward push.

An exact path, mode, object, or finding inherited unchanged from that tip is
already transferred; it may remain on this private route without being treated
as new exposure. Any addition, modification, removal-and-readdition, or new
metadata finding after the boundary is audited and can block, even when a later
commit removes it. Legacy state on that exact private destination does not by
itself invoke fallback and is never an exception for another destination or a
public-readiness assessment.

An absent or empty destination branch has no transferred boundary, so the
helper audits the complete current snapshot and every reachable source commit.
Before its first push it also:

- read destination state from committed `HEAD`
- audit the complete current snapshot and every reachable source commit
- block forbidden secret/runtime paths, credentials, keys, tokens, connection
  strings, unsupported Git objects, LFS pointers, oversized text, and
  unreviewed binaries
- report rule IDs and paths only, never matched values
- verify `gh` authentication and private visibility

When no destination exists, run `scripts/github-sync.ps1 -Initialize`. Use
`origin` when no remote exists; preserve a non-GitHub `origin` and use `github`
instead. Record repository and remote state, then commit it before the first
push. Never change visibility automatically.

For every push:

- audit committed source history through the shared scanner at the applicable
  full-ancestry or verified-remote boundary
- recheck source `HEAD`
- verify private visibility
- fetch the target branch
- require the remote tip to be an ancestor of local `HEAD`
- allow only a fast-forward push
- never force-push, rewrite history, resolve divergence automatically, or
  transfer dirty/untracked files

`-PublicReadiness` is a read-only assessment. Public visibility remains a
separate explicit action requiring licensing, ownership, and confidentiality
review, and this assessment always audits full ancestry rather than using a
private-remote boundary. Public-readiness and isolated sanitized-backup audits
also block operational metadata such as private networks, machine-user paths,
and operational endpoints.

## Small-Change Cadence

After a focused small commit, Codex runs `scripts/github-sync.ps1
-BatchEligible`. Only commits verified by the precommit contract qualify. While
the branch is one through nine verified local commits ahead of its fetched
private destination, the helper may leave them safely in local Git. The tenth
commit synchronizes the whole accumulated batch. There is no time-based trigger.

Initial setup, standard or substantial work, milestones, releases, explicit
synchronization requests, absent or empty remote branches, and any uncertainty
use immediate normal synchronization. Calling the helper without
`-BatchEligible` is always an immediate request.

## Local-Only Legacy Recovery

If unsafe legacy ancestry exists only locally and blocks the first transfer to
an empty private branch, Codex may offer one explicit clean-baseline recovery.
It is never automatic. Recovery requires the user's authorization, a safe
current tree, a clean named branch at the exact expected `HEAD`, no Git
operation in progress, and a verified private destination whose target branch
is absent.

The recovery creates a parentless public-ready commit with the identical current
tree, preserves the old exact tip under local hidden refs, and moves the named
branch only with a guarded compare-and-swap. It then uses normal audited
fast-forward synchronization. It never force-pushes, deletes the preserved
history, or runs against a nonempty destination. A retry after a network failure
uses normal synchronization; recovery is not repeated. If any safeguard fails,
or the user declines, offer isolated fallback or local-only operation.

## Audit Failure

Local Git preservation precedes the committed-history audit by design. Local
history may intentionally retain private material that GitHub must not receive.
Classify a failure before offering fallback: ancestry already on the verified
private destination is handled by its transfer boundary; qualifying local-only
legacy ancestry may use the explicitly authorized clean-baseline recovery;
unsafe current or post-boundary commits remain blocked.

If source-history audit fails:

1. Keep the local commit.
2. Do not push, amend, rewrite, scrub, or weaken policy.
3. Report only finding rule IDs and paths.
4. When the guarded legacy recovery is not applicable or chosen, ask whether
   to run `scripts/github-backup.ps1` or remain local-only.
5. Ask again after each future blocked audit; do not persist the choice.

## Isolated Sanitized Fallback

The fallback builds a complete snapshot from committed `HEAD`, applies only
committed exclusions and fingerprinted allowances, scans every included file,
audits every reachable fallback commit, uses a neutral identity, and pushes to
a separate private repository. It excludes legacy `docs/work-log.md` and
`*.local.md` by default.

Dirty policy cannot weaken scanning. Any allowance must bind rule, path, and
exact file SHA-256. Never add an allowance simply to make a scan pass. Never
transfer source ancestry that failed a strict public-readiness or fallback
audit or assume private visibility makes publishable content acceptable.
Fallback is explicit and isolated, never the normal cadence, and it must not
disable, replace, or otherwise modify the normal source remote.
