[CmdletBinding()]
param([switch]$Quiet)
# Restores every service start type, scheduled task, privacy policy, and the default-browser policy
# that BAKA changed, using the backups written when they were applied.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$dataRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $dataRoot 'Modules\SystemTuning.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw "System-tuning module not found: $modulePath" }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Start-Process -FilePath $powershell -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath) -Wait
    return
}
if (-not $Quiet) {
    $answer = [System.Windows.Forms.MessageBox]::Show('Restore the Windows services, scheduled tasks, privacy settings, and default-browser policy that BAKA changed? Removed apps can be reinstalled from Microsoft Store.','Restore BAKA System Tuning','YesNo','Question')
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
}
Import-Module $modulePath -Force
$messages = [System.Collections.Generic.List[string]]::new()
foreach ($state in @(@{Label='System';Path=(Join-Path $dataRoot 'SystemTuningBackup.json')},@{Label='This user';Path=(Join-Path $env:LOCALAPPDATA 'BAKA\UserTuningBackup.json')})) {
    if (-not (Test-Path -LiteralPath $state.Path -PathType Leaf)) { $messages.Add("$($state.Label): nothing to restore."); continue }
    try {
        $result = Invoke-BakaSystemTuning -Mode Restore -StatePath $state.Path -Confirm:$false
        $messages.Add("$($state.Label): restored $(@($result.Changed).Count) item(s).")
    } catch { $messages.Add("$($state.Label): $($_.Exception.Message)") }
}
try { & (Join-Path $env:WINDIR 'System32\gpupdate.exe') /force | Out-Null } catch { $messages.Add('Policy refresh did not complete; restart Windows.') }
if (-not $Quiet) { [System.Windows.Forms.MessageBox]::Show((($messages -join "`r`n") + "`r`n`r`nRestart Windows to finish."),'BAKA System Tuning restored','OK','Information') | Out-Null } else { $messages }
