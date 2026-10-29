# Builds, signs, installs and launches the Tizen app on a Samsung TV in Developer Mode (docs/testing.md).
#   .\tools\tv.ps1 -TvIp 192.168.1.50 -Profile MyProject-Samsung -SelfTest
# -Profile is a Tizen security profile. A retail TV needs a Samsung certificate that lists its DUID; the
# YouPipeTV-dev author profile only packages (useful to check the build).
# -SelfTest relaunches the app with the Web Inspector and runs the self test from this PC (tv-selftest.mjs).
param(
    [string]$TvIp,
    [string]$Profile = 'YouPipeTV-dev',
    [switch]$PackageOnly,
    [switch]$SelfTest
)
$ErrorActionPreference = 'Stop'
$tizen = 'C:\tizen-studio\tools\ide\bin\tizen.bat'
$sdb = 'C:\tizen-studio\tools\sdb.exe'
$app = Join-Path $PSScriptRoot '..\app' | Resolve-Path
$out = Join-Path $app '.buildResult'
$appId = 'YouPipeTV1.YouPipe'

& $tizen build-web -- $app | Out-Null
& $tizen package -t wgt -s $Profile -- $out | Select-String 'Package File Location|ERROR|error'
if ($PackageOnly) { return }
if (-not $TvIp) { throw 'Pass -TvIp (the TV must be in Developer Mode with this PC''s IP).' }

& $sdb connect $TvIp
$serial = "${TvIp}:26101"
& $tizen install -n YouPipe.wgt -s $serial -- $out
if (-not $SelfTest) {
    & $tizen run -p $appId -s $serial
    Write-Host "Running. Web Inspector: .\tools\tv.ps1 -TvIp $TvIp -Profile $Profile -SelfTest, or see docs/testing.md"
    return
}

# `debug` hangs if the app is already running, so stop it first.
& $sdb -s $serial shell 0 was_kill ($appId.Split('.')[0]) | Out-Null
$debug = & $sdb -s $serial shell 0 debug $appId
if ("$debug" -notmatch 'port: (\d+)') { throw "No inspector port from the TV: $debug" }
$port = $Matches[1]
& $sdb -s $serial forward "tcp:$port" "tcp:$port" | Out-Null
Write-Host "Inspector on http://127.0.0.1:$port (open it in Chrome to debug)"
node (Join-Path $PSScriptRoot 'tv-selftest.mjs') $port
exit $LASTEXITCODE
