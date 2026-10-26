[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Modules\UpdateControl.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw "Update-control module not found: $modulePath" }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
    Start-Process -FilePath $powershell -Verb RunAs -ArgumentList $arguments -Wait
    return
}
Import-Module $modulePath -Force
$status = Invoke-BakaWindowsUpdateControl -Mode Status
if (-not $status.BackupPresent) { throw 'No saved BAKA policy backup is available; no policy was changed.' }
Invoke-BakaWindowsUpdateControl -Mode Restore -Confirm:$false | Out-Null
try { & (Join-Path $env:WINDIR 'System32\gpupdate.exe') /target:computer /force | Out-Null } catch { Write-Warning "Policy refresh did not complete. Restart Windows before checking for updates. $($_.Exception.Message)" }
[System.Windows.Forms.MessageBox]::Show('The saved Windows Update policy settings were restored. Restart Windows, then open Settings > Windows Update to check for updates.','Windows Update restored','OK','Information') | Out-Null
