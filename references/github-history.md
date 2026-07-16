# Private GitHub History

Read this reference only for GitHub initialization, audit, divergence,
synchronization, or sanitized fallback.

## Normal Source-History Synchronization

`scripts/github-sync.ps1` is the normal off-site workflow. It pushes meaningful
real source commits to a private, public-ready repository rather than rebuilding
snapshots.

Before the first push:

- read destination state from committed `HEAD`
- audit the complete current snapshot and every reachable source commit
- block forbidden paths, credentials, keys, tokens, connection strings,
  private networks, machine-user paths, operational endpoints, unsupported Git
  objects, LFS pointers, oversized text, and unreviewed binaries
- report rule IDs and paths only, never matched values
- verify `gh` authentication and private visibility

When no destination exists, run `scripts/github-sync.ps1 -Initialize`. Use
`origin` when no remote exists; preserve a non-GitHub `origin` and use `github`
instead. Record repository and remote state, then commit it before the first
push. Never change visibility automatically.

For every push:

- audit committed source history through the shared scanner
- recheck source `HEAD`
- verify private visibility
- fetch the target branch
- require the remote tip to be an ancestor of local `HEAD`
- allow only a fast-forward push
- never force-push, rewrite history, resolve divergence automatically, or
  transfer dirty/untracked files

`-PublicReadiness` is a read-only assessment. Public visibility remains a
separate explicit action requiring licensing, ownership, and confidentiality
review.

## Audit Failure

Local Git preservation precedes the committed-history audit by design. Local
history may intentionally retain private material that GitHub must not receive.
If that blocks source synchronization, the commit remains local and the
isolated sanitized fallback is the intended off-site route unless a separate
explicit history-remediation task is authorized.

If source-history audit fails:

1. Keep the local commit.
2. Do not push, amend, rewrite, scrub, or weaken policy.
3. Report only finding rule IDs and paths.
4. Ask whether to run `scripts/github-backup.ps1` or remain local-only.
5. Ask again after each future blocked audit; do not persist the choice.

## Isolated Sanitized Fallback

The fallback builds a complete snapshot from committed `HEAD`, applies only
committed exclusions and fingerprinted allowances, scans every included file,
audits every reachable fallback commit, uses a neutral identity, and pushes to
a separate private repository. It excludes legacy `docs/work-log.md` and
`*.local.md` by default.

Dirty policy cannot weaken scanning. Any allowance must bind rule, path, and
exact file SHA-256. Never add an allowance simply to make a scan pass. Never
transfer source ancestry that failed audit or assume private visibility makes
confidential content acceptable.
