param([switch]$Enable,[switch]$Disable)
# Turns system-wide ad and tracker blocking (encrypted AdGuard DNS) on or off. Asks for administrator
# approval when started from BAKA Settings; no console window is left open.
$ErrorActionPreference='Stop'
$principal=[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
    $flag=if($Disable){'-Disable'}else{'-Enable'}
    Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -Verb RunAs -WindowStyle Hidden -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath),$flag)
    return
}
$root=Join-Path $env:ProgramData 'BAKA'
$module=Join-Path $root 'Modules\AdBlockDns.psm1'
if(-not (Test-Path -LiteralPath $module)){$module=Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Modules\AdBlockDns.psm1'}
Import-Module $module -Force
$log=Join-Path $root 'Logs\AdBlockDns.log'
New-Item -ItemType Directory -Path (Split-Path -Parent $log) -Force|Out-Null
$result=if($Disable){Disable-BakaAdBlockDns -Confirm:$false}else{Enable-BakaAdBlockDns -Confirm:$false}
Add-Content -LiteralPath $log -Value ('{0} {1}' -f (Get-Date -Format o),($result|ConvertTo-Json -Compress))
