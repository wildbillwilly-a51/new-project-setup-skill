#!/bin/sh
set -eu

if [ "$#" -lt 1 ]; then
  echo "Usage: invoke-powershell.sh <script.ps1> [arguments...]" >&2
  exit 64
fi

if command -v pwsh >/dev/null 2>&1 &&
  pwsh -NoLogo -NoProfile -NonInteractive -Command 'if ($PSVersionTable.PSVersion.Major -ge 7) { exit 0 } else { exit 1 }' >/dev/null 2>&1; then
  exec pwsh -NoLogo -NoProfile -NonInteractive -File "$@"
fi

echo "PowerShell 7 (pwsh) is required on macOS and Linux." >&2
exit 127
