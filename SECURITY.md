# Security

## Supported Workflow

Security fixes target the active workflow V7 payload. V6 is predecessor-only
migration evidence and is not an active runtime.

## Secret Handling

- Do not place credentials, tokens, private keys, or private migration exports
  in tracked files, prompts, issue reports, or release packages.
- `scripts/save-local-work.ps1` scans staged content for high-confidence secret
  and private-key patterns before local commit. Findings identify rules and
  paths without returning matched values.
- Files larger than the scan limit are reported as unscanned; review them
  manually before committing or packaging.
- The V6 compatibility export is machine-local, ignored, never consumed by V7,
  and must not be distributed.

## Trust Boundaries

Normal V7 operation is local-only. It requires no GitHub repository, remote,
network service, ACF catalogue, external memory, backup, or remote CI. Legacy
V6 GitHub helpers may remain in migrated projects, but V7 does not own or
execute them.

The workflow refuses redirected roots, unsafe managed links, ownership
collisions, modified predecessor files, dirty indexes, ambiguous staged state,
and concurrent identity changes. Do not bypass these refusals to force setup or
saving.

## Reporting A Vulnerability

Use a private reporting channel offered by the distribution host or maintainer.
Do not include live secrets or private export contents. Include the affected
commit, workflow version, platform, PowerShell version, minimal reproduction,
and redacted observed result.
