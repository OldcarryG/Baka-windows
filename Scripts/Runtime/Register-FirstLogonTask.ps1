$ErrorActionPreference='Stop'
$scriptPath=Join-Path $env:ProgramData 'BAKA\Scripts\Apply-FirstLogonSystemSetup.ps1'
if(-not(Test-Path -LiteralPath $scriptPath -PathType Leaf)){throw "First-logon system setup script not found: $scriptPath"}
$powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$scriptPath+'"'
$action=New-ScheduledTaskAction -Execute $powershell -Argument $arguments
$trigger=New-ScheduledTaskTrigger -AtLogOn
$principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -StartWhenAvailable
Register-ScheduledTask -TaskName 'BAKA-InitializeAfterOobe' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force|Out-Null
