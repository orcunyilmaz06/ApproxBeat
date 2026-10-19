<#
.SYNOPSIS
  Run make for a testbench inside WSL (Ubuntu-24.04), with the project venv on PATH.

.DESCRIPTION
  Sources stay in this (Windows) repo; WSL reads them through /mnt/c, and the build
  output goes to ~/.cache/approxbeat inside Linux, out of the OneDrive-synced folder.
  Extra arguments are passed to make.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\wsl_make.ps1 tb\toolcheck
#>
param(
    [Parameter(Mandatory = $true)] [string]$Dir,
    [Parameter(ValueFromRemainingArguments = $true)] [string[]]$MakeArgs
)
$repo = Split-Path -Parent $PSScriptRoot
$target = (Resolve-Path (Join-Path $repo $Dir)).Path
$env:WSL_UTF8 = '1'
wsl.exe -d Ubuntu-24.04 --cd $target -- env PATH=/opt/approxbeat/venv/bin:/usr/local/bin:/usr/bin:/bin make @MakeArgs
exit $LASTEXITCODE
