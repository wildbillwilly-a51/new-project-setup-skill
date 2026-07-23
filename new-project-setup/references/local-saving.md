# Local Saving

Use this reference when durable work is ready for a local commit or when
`scripts/save-local-work.ps1` returns a warning, refusal, or indeterminate
result. The helper requires PowerShell 7.6 or later and an ordinary local Git
worktree.

## Scope Selection

Codex selects objective paths using project context and review of current Git
status. Paths are whole-file or whole-directory staging units. Do not use the
automatic helper for a file that contains known unrelated edits. Preserve all
unrelated staged, unstaged, and untracked work.

`Prepare` requires a clean index. Existing staged paths are a safe refusal and
must be resolved deliberately before retrying.

## Prepare And Commit

1. Refresh continuity files when objective state, validation, blockers, or the
   continuation action changed.
2. Call `Prepare` with explicit objective paths and the intended message.
3. Review its exact branch, expected `HEAD`, staged tree, paths, change summary,
   warnings, and blockers. A `ready` result leaves that exact tree staged.
4. Call `Commit` with the expectations returned by `Prepare`, the same objective
   paths, and the intended message.
5. Review the resulting commit, tree, paths, message-verification hashes, and
   outcome. Do not reset, amend, or rewrite a commit created with warnings.

### Native Command Example

When calling the helper through `pwsh -File`, pass multiple objective paths as
JSON. Native command parsing does not preserve PowerShell array expressions as
separate path values reliably.

```powershell
$repository = (Get-Location).Path
$objectivePaths = '["src/status.txt","docs/codex-handoff.md"]'
$message = 'Complete the bounded status change'

pwsh -NoProfile -File scripts/save-local-work.ps1 `
  -Operation Prepare `
  -Repository $repository `
  -ObjectivePathsJson $objectivePaths `
  -CommitMessage $message
```

Use the returned `branch`, `expected_head` or unborn state, and `expected_tree`
with the same repository, objective-path JSON, and message for `Commit`.

`Prepare` and `Commit` recheck branch, `HEAD`, staged tree, and staged scope.
Changes between operations fail safely. A failed `Prepare` restores
helper-created staging only when repository and index identity still prove that
restoration safe. An indeterminate cleanup result preserves the current index
for manual review.

## Security And Warnings

High-confidence credential or private-key findings block preparation. Result
metadata identifies rules and paths without returning matched values.

Staged blob content is inspected up to 8 MiB. Larger blobs receive
`content-scan-skipped` with a size-limit reason and are not claimed to be
credential-safe or binary. A `large-binary` warning means binary content was
actually detected within the inspected range. Risky file warnings require
review but do not automatically block a local commit.

Ordinary Git hooks and configured signing remain enabled. A hook or signing
failure is reported without bypassing it. If a hook creates a commit whose tree
or message differs from the prepared expectation, the helper returns
`committed_with_warning` with content-free change metadata. Review that commit
and its objective scope; do not conceal the outcome by rewriting it.

Safe refusals mean no commit was created. An `indeterminate` result means state
may have changed and requires direct Git inspection before another save attempt.
Abrupt process termination can prevent in-process cleanup, so a later `Prepare`
continues to reject and report remaining staged paths.

Local saving requires no remote, GitHub component, network service, `tar`,
transfer audit, publication state, or persistent transfer attestation.
