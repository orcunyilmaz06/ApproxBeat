<#
.SYNOPSIS
  Download the MIT-BIH Arrhythmia Database (48 records) from PhysioNet and verify SHA-256 sums.

.DESCRIPTION
  Fetches <record>.hea / .dat / .atr for every record listed in PhysioNet's RECORDS file
  into data/mitdb (~98 MB). Files already present with a matching hash are skipped, so the
  script is safe to re-run after an interruption. The MATLAB loader additionally verifies
  the WFDB signal checksums stored in each .hea file on every read.

  PhysioNet throttles each connection to roughly 10-15 KB/s, so the files are fetched over
  several connections at once with curl.exe (shipped with Windows 10 1803+ and Windows 11).

  Data: Moody & Mark, MIT-BIH Arrhythmia Database v1.0.0, PhysioNet (ODC-By 1.0).
  Linux/WSL alternative:  wget -r -N -c -np https://physionet.org/files/mitdb/1.0.0/

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\get_mitdb.ps1
#>
param(
    [string]$Dest = (Join-Path $PSScriptRoot '..\data\mitdb'),
    [int]$Parallel = 8
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # the progress bar makes Invoke-WebRequest ~10x slower
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$base = 'https://physionet.org/files/mitdb/1.0.0'
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
$Dest = (Resolve-Path $Dest).Path

foreach ($f in 'RECORDS', 'SHA256SUMS.txt') {
    Invoke-WebRequest -Uri "$base/$f" -OutFile (Join-Path $Dest $f) -UseBasicParsing
}

$expected = @{}
foreach ($line in Get-Content (Join-Path $Dest 'SHA256SUMS.txt')) {
    $parts = $line.Trim() -split '\s+', 2
    if ($parts.Count -eq 2) { $expected[$parts[1]] = $parts[0].ToLower() }
}

function Test-Sha256([string]$name) {
    $path = Join-Path $Dest $name
    (Test-Path $path) -and ((Get-FileHash $path -Algorithm SHA256).Hash.ToLower() -eq $expected[$name])
}

$records = @(Get-Content (Join-Path $Dest 'RECORDS') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$names = @(foreach ($rec in $records) { foreach ($ext in 'hea', 'dat', 'atr') { "$rec.$ext" } })
foreach ($n in $names) { if (-not $expected[$n]) { throw "No SHA-256 entry for $n in SHA256SUMS.txt" } }
$todo = @($names | Where-Object { -not (Test-Sha256 $_) })

if ($todo.Count) {
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        $list = [IO.Path]::GetTempFileName()
        $todo | ForEach-Object { "url = `"$base/$_`"" } | Set-Content -Encoding ascii $list
        # -C - resumes partial files; PhysioNet sometimes drops connections mid-transfer
        & $curl.Source --http1.1 --parallel --parallel-max $Parallel --fail -C - `
            --retry 8 --retry-all-errors --retry-delay 3 -sS --remote-name-all --output-dir $Dest -K $list
        Remove-Item $list
    } else {
        foreach ($n in $todo) { Invoke-WebRequest -Uri "$base/$n" -OutFile (Join-Path $Dest $n) -UseBasicParsing }
    }
}

$failed = @($names | Where-Object { -not (Test-Sha256 $_) })
"{0} records, {1} files fetched, {2} missing or failing SHA-256 -> {3}" -f $records.Count, $todo.Count, $failed.Count, $Dest
if ($failed.Count) {
    # start these from scratch next time instead of resuming a possibly corrupt file
    $failed | ForEach-Object { Remove-Item (Join-Path $Dest $_) -ErrorAction SilentlyContinue; Write-Warning "missing or bad: $_" }
    Write-Warning 'Re-run the script to fetch the files above.'
    exit 1
}
