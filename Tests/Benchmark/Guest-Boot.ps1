# Runs INSIDE a test VM over PowerShell Direct (admin). Reports what the last boot cost and what slowed it.
param([string]$Since)
$ErrorActionPreference='SilentlyContinue'
$since=if($Since){[datetime]$Since}else{(Get-CimInstance Win32_OperatingSystem).LastBootUpTime}
$r=[ordered]@{}
$os=Get-CimInstance Win32_OperatingSystem
$r.lastBootUpTime=$os.LastBootUpTime.ToString('o')
$r.user=(Get-CimInstance Win32_ComputerSystem).UserName
# boot type of the newest boot: 0 = full boot, 1 = hybrid (Fast Startup), 2 = resume from hibernate
$kb=Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-Kernel-Boot';Id=27} -MaxEvents 1
if($kb){$x=[xml]$kb.ToXml();$r.bootType=($x.Event.EventData.Data|Where-Object Name -eq 'BootType').'#text';$r.bootTypeTime=$kb.TimeCreated.ToString('o')}
# Windows' own boot measurement (only written for full boots, a few minutes after the desktop is idle)
$e=Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' -FilterXPath '*[System[EventID=100]]' -MaxEvents 1
if($e -and $e.TimeCreated -gt $since){$x=[xml]$e.ToXml();$d=[ordered]@{};$x.Event.EventData.Data|ForEach-Object {$d[$_.Name]=$_.'#text'};$d['eventTime']=$e.TimeCreated.ToString('o');$r.boot100=$d}else{$r.boot100=$null}
# what Windows says slowed this boot (101 app, 102 driver, 103 service, 106 background, 109 device, 110 session)
$r.degradations=@(Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' -MaxEvents 80 | Where-Object { $_.Id -ge 101 -and $_.Id -le 110 -and $_.TimeCreated -gt $since } | ForEach-Object {
  $x=[xml]$_.ToXml();$d=@{};$x.Event.EventData.Data|ForEach-Object {$d[$_.Name]=$_.'#text'}
  "$($_.Id) $($d.Name) $($d.FriendlyName) total=$($d.TotalTime) degradation=$($d.DegradationTime)" })
# when things started in the user's session
$sess=(Get-Process explorer -IncludeUserName | Where-Object UserName -notmatch 'SYSTEM' | Sort-Object StartTime | Select-Object -First 1)
$r.explorerStart=if($sess){$sess.StartTime.ToString('o')}else{$null}
foreach($n in 'BakaDesktop','StartMenuExperienceHost','SearchHost','ShellExperienceHost','sihost','userinit','MsMpEng'){ $p=Get-Process $n | Sort-Object StartTime | Select-Object -First 1; if($p){$r["start_$n"]=$p.StartTime.ToString('o')} }
$log=Get-ChildItem 'C:\Users\*\AppData\Local\BAKA\Logs\Desktop.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if($log){ $lines=@(Get-Content $log.FullName | ForEach-Object { "$_" })
  $r.bakaReadyLine=($lines | Where-Object { $_ -match 'desktop-ready' } | Select-Object -Last 1)
  $r.bakaKeyboard=($lines | Where-Object { $_ -match 'keyboard mode=' } | Select-Object -Last 1)
  $r.bakaSessionEnd=@($lines | Where-Object { $_ -match 'session-ending|ended-with-session|desktop-crashed' } | Select-Object -Last 3) }
# Winlogon / logon timings
$r.winlogon=@(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Winlogon/Operational';StartTime=$since} -MaxEvents 60 | Sort-Object TimeCreated | ForEach-Object { "$($_.TimeCreated.ToString('HH:mm:ss.fff')) $($_.Id) $(($_.Message -split "`n")[0])" } | Select-Object -First 25)
$r.shellCore=@(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Shell-Core/Operational';StartTime=$since} -MaxEvents 200 | Where-Object { $_.Id -in 9705,9706,9707,9708,62170,62171 } | Sort-Object TimeCreated | ForEach-Object { "$($_.TimeCreated.ToString('HH:mm:ss.fff')) $($_.Id) $(($_.Message -split "`n")[0])" } | Select-Object -First 30)
$r.firstLogonTask=[bool](Get-ScheduledTask -TaskName 'BAKA-InitializeAfterOobe')
$r.autoSignInTask=@(Get-ScheduledTask | Where-Object TaskName -match 'AutoSignIn|BAKA' | ForEach-Object { "$($_.TaskName) $($_.State)" })
$r.runKeys=@('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' | ForEach-Object { $k=Get-ItemProperty $_; if($k){ $k.PSObject.Properties | Where-Object Name -notmatch '^PS' | ForEach-Object { "$($_.Name)=$($_.Value)" } } })
$r.hiberbootEnabled=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power').HiberbootEnabled
$r.hibernateFile=Test-Path 'C:\hiberfil.sys' -PathType Leaf
$r | ConvertTo-Json -Depth 4
