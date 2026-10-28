$ErrorActionPreference='Stop'
$scriptPath=Join-Path $env:ProgramData 'BAKA\Scripts\Apply-FirstLogonSystemSetup.ps1'
if(-not(Test-Path -LiteralPath $scriptPath -PathType Leaf)){throw "First-logon system setup script not found: $scriptPath"}
$powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$scriptPath+'"'
$action=New-ScheduledTaskAction -Execute $powershell -Argument $arguments
$trigger=New-ScheduledTaskTrigger -AtLogOn
$principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 60) -StartWhenAvailable
Register-ScheduledTask -TaskName 'BAKA-InitializeAfterOobe' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force|Out-Null
# Register the per-user first-logon step now, so it already runs during the very first sign-in
# instead of waiting for the SYSTEM task to create it.
$activeSetup='HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{D7C6DA30-92B6-4B30-A4E0-26A2B2602A10}'
if(-not(Test-Path -LiteralPath $activeSetup)){New-Item -Path $activeSetup -Force|Out-Null}
$firstLogon=Join-Path $env:ProgramData 'BAKA\Scripts\FirstLogon.ps1'
New-ItemProperty -LiteralPath $activeSetup -Name 'StubPath' -PropertyType String -Value ('"'+$powershell+'" -NoProfile -ExecutionPolicy Bypass -File "'+$firstLogon+'"') -Force|Out-Null
New-ItemProperty -LiteralPath $activeSetup -Name 'Version' -PropertyType String -Value '1,0,0,0' -Force|Out-Null
New-ItemProperty -LiteralPath $activeSetup -Name 'IsInstalled' -PropertyType DWord -Value 1 -Force|Out-Null
