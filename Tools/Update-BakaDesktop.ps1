#Requires -Version 5.1
<#
.SYNOPSIS
  Updates BAKA Desktop on a PC that runs BAKA Windows (R15 or later), without reinstalling Windows.

.DESCRIPTION
  Run it from the folder of the downloaded BakaDesktop-<version>.zip, after extracting the zip, through
  Install-BakaDesktop.cmd (which asks for administrator approval). It:
    1. checks that this PC has BAKA Windows (C:\ProgramData\BAKA\Desktop\BakaDesktop.exe),
    2. checks the new BakaDesktop.exe against the SHA-256 in SHA256.txt next to it,
    3. keeps the current one as BakaDesktop.exe.previous,
    4. closes BAKA Desktop, copies the new one in, pre-compiles it (NGen, as at first sign-in),
    5. starts BAKA Desktop again through its sign-in task.
  Nothing else on the PC is changed. Settings, wallpapers and pinned apps are kept.

  -Rollback puts BakaDesktop.exe.previous back. Each run is logged to C:\ProgramData\BAKA\Logs\Update-BakaDesktop.log.
#>
[CmdletBinding()]
param([switch]$Rollback)
$ErrorActionPreference = 'Stop'
$target = Join-Path $env:ProgramData 'BAKA\Desktop\BakaDesktop.exe'
$previous = "$target.previous"
$here = $PSScriptRoot

function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }
function Fail($text) { Say ""; Say $text 'Red'; Say ""; exit 1 }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Fail 'Run Install-BakaDesktop.cmd (it asks for administrator approval), not this script directly.' }
if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { Fail "BAKA Windows is not installed on this PC ($target not found). This update is for PCs installed from the BAKA Windows R15 ISO." }
# what happened stays readable after the window closes
try { Start-Transcript -LiteralPath (Join-Path $env:ProgramData 'BAKA\Logs\Update-BakaDesktop.log') -Append -ErrorAction Stop | Out-Null } catch {}

if ($Rollback) {
    if (-not (Test-Path -LiteralPath $previous -PathType Leaf)) { Fail 'There is no earlier BAKA Desktop to go back to.' }
    $source = $previous
    Say ("Going back to BAKA Desktop " + (Get-Item -LiteralPath $previous).VersionInfo.FileVersion)
} else {
    $source = Join-Path $here 'BakaDesktop.exe'
    $sumFile = Join-Path $here 'SHA256.txt'
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { Fail 'BakaDesktop.exe is not next to this script. Extract the whole zip first (right-click > Extract All).' }
    if (-not (Test-Path -LiteralPath $sumFile -PathType Leaf)) { Fail 'SHA256.txt is missing. Download the zip again from the release page.' }
    $want = (Get-Content -LiteralPath $sumFile | Where-Object { $_ -match '^\s*([0-9A-Fa-f]{64})\s+\*?BakaDesktop\.exe\s*$' } | ForEach-Object { $Matches[1] } | Select-Object -First 1)
    $have = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if (-not $want -or $have -ne $want.ToUpperInvariant()) { Fail "BakaDesktop.exe does not match SHA256.txt (got $have). Download the zip again; do not install a damaged file." }
    $newVersion = (Get-Item -LiteralPath $source).VersionInfo.FileVersion
    $oldVersion = (Get-Item -LiteralPath $target).VersionInfo.FileVersion
    Say "BAKA Desktop $oldVersion -> $newVersion (SHA-256 checked)"
    Copy-Item -LiteralPath $target -Destination $previous -Force
}

$copy = Join-Path ([IO.Path]::GetTempPath()) ('BakaDesktop-' + [Guid]::NewGuid().ToString('N') + '.exe')
Copy-Item -LiteralPath $source -Destination $copy -Force   # a rollback copies from the .previous it may replace
Say 'Closing BAKA Desktop...'
# A shell that Windows restarts by itself can lock the file again, so close and copy up to five times.
$copied = $false; $copyError = ''
for ($attempt = 1; $attempt -le 5 -and -not $copied; $attempt++) {
    Get-Process BakaDesktop -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Kill(); $_.WaitForExit(5000) | Out-Null } catch {} }
    Start-Sleep -Milliseconds 800
    try { Copy-Item -LiteralPath $copy -Destination $target -Force -ErrorAction Stop; $copied = $true } catch { $copyError = $_.Exception.Message }
}
Remove-Item -LiteralPath $copy -Force -ErrorAction SilentlyContinue
if ($copied) {
    Unblock-File -LiteralPath $target -ErrorAction SilentlyContinue  # the "downloaded from the internet" mark
    $ngen = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\ngen.exe'
    if (Test-Path -LiteralPath $ngen) { Say 'Pre-compiling (NGen)...'; & $ngen install $target /nologo /silent | Out-Null }
}

# Start BAKA Desktop again in every case, so a failed copy never leaves the PC without a desktop.
Say 'Starting BAKA Desktop...'
$started = $false
try { Start-ScheduledTask -TaskPath '\BAKA\' -TaskName 'BAKA Desktop' -ErrorAction Stop; $started = $true } catch {}
if (-not $started) {
    # no sign-in task: start it as the signed-in user, not as administrator (through Explorer)
    try { Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList ('"{0}"' -f $target); $started = $true } catch {}
}
for ($i = 0; $i -lt 20 -and -not (Get-Process BakaDesktop -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 500 }
if (-not $copied) { Fail "Could not replace BakaDesktop.exe ($copyError). BAKA Desktop was not changed. Restart the PC and run Install-BakaDesktop.cmd again." }
$now = (Get-Item -LiteralPath $target).VersionInfo.FileVersion
if (Get-Process BakaDesktop -ErrorAction SilentlyContinue) { Say ""; Say "Done. BAKA Desktop $now is running." 'Green' }
else { Say ""; Say "BAKA Desktop $now is installed. Sign out and back in to start it." 'Yellow' }
Say 'To go back to the previous version: Install-BakaDesktop.cmd rollback'
