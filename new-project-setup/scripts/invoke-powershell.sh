#!/bin/sh
set -eu

if [ "$#" -lt 1 ]; then
  echo "Usage: invoke-powershell.sh <script.ps1> [arguments...]" >&2
  exit 64
fi

if command -v pwsh >/dev/null 2>&1 &&
  pwsh -NoLogo -NoProfile -NonInteractive -Command 'if ($PSVersionTable.PSEdition -eq "Core" -and $PSVersionTable.PSVersion -ge [Version]"7.6.0") { exit 0 } else { exit 1 }' >/dev/null 2>&1; then
  exec pwsh -NoLogo -NoProfile -NonInteractive -File "$@"
fi

echo "PowerShell Core 7.6 or later (pwsh) is required. No legacy-host fallback is supported." >&2
exit 127
