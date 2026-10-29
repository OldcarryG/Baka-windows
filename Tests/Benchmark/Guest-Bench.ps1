# Runs INSIDE a test VM through PowerShell Direct. Measures the same things on stock Windows and BAKA:
# boot time, idle memory/CPU/processes/services, disk use, WinSAT CPU/memory/disk scores, ad and tracker
# blocking (the public d3ward test list, resolved the way the browser would), privacy settings and apps.
param([string[]]$Domains)
$ErrorActionPreference='Continue'
$r=[ordered]@{}
$os=Get-CimInstance Win32_OperatingSystem
$r.windows="$($os.Caption) $((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion) build $($os.BuildNumber)"
$r.uptimeMinutes=[math]::Round(((Get-Date)-$os.LastBootUpTime).TotalMinutes,1)
# boot time as Windows records it (Diagnostics-Performance event 100, last boot)
try{$e=Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' -FilterXPath '*[System[EventID=100]]' -MaxEvents 1 -ErrorAction Stop
    $x=[xml]$e.ToXml();$d=@{};$x.Event.EventData.Data|ForEach-Object {$d[$_.Name]=$_.'#text'}
    $r.bootTimeSec=[math]::Round([double]$d.BootTime/1000,1);$r.bootMainPathSec=[math]::Round([double]$d.MainPathBootTime/1000,1);$r.bootPostBootSec=[math]::Round([double]$d.BootPostBootTime/1000,1);$r.bootEventTime=$e.TimeCreated.ToString('o')}catch{$r.bootTimeSec=$null}
# idle footprint
$os=Get-CimInstance Win32_OperatingSystem
$r.memoryInUseMB=[math]::Round(($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)/1024)
$perf=Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
$r.memoryCommittedMB=[math]::Round($perf.CommittedBytes/1MB)
$r.processes=@(Get-Process).Count
$r.threads=(Get-CimInstance Win32_PerfFormattedData_PerfOS_System).Threads
$r.handles=(Get-Process|Measure-Object HandleCount -Sum).Sum
$r.servicesRunning=@(Get-Service|Where-Object Status -eq 'Running').Count
$cpu0=@{};Get-Process|ForEach-Object {try{$cpu0["$($_.Id)"]=@($_.ProcessName,$_.TotalProcessorTime.TotalMilliseconds)}catch{}}
$sw0=[Diagnostics.Stopwatch]::StartNew()
$samples=@();for($i=0;$i -lt 30;$i++){$samples+=(Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime;Start-Sleep 2}
$r.idleCpuAvgPercent=[math]::Round(($samples|Measure-Object -Average).Average,1)
# CPU used by each process during the same window, as % of all cores
$wallMs=$sw0.Elapsed.TotalMilliseconds*[Environment]::ProcessorCount
$svcByPid=@{};Get-CimInstance Win32_Service|Where-Object ProcessId -gt 0|ForEach-Object {$svcByPid["$($_.ProcessId)"]+=@($_.Name)}
$use=@{};Get-Process|ForEach-Object {$k="$($_.Id)";if($cpu0.ContainsKey($k)){try{$d=$_.TotalProcessorTime.TotalMilliseconds-$cpu0[$k][1];$n=$cpu0[$k][0]
  if($n -eq 'svchost' -and $svcByPid.ContainsKey($k)){$use["svchost("+(($svcByPid[$k]|Select-Object -First 3) -join ',')+")"]=$d}
  $use[$n]=[double]$use[$n]+$d}catch{}}}
$r.topCpu=@($use.GetEnumerator()|Sort-Object Value -Descending|Select-Object -First 14|ForEach-Object {"$($_.Key) $([math]::Round(100*$_.Value/$wallMs,2))%"})
$r.bakaDesktopCpuPercent=if($use.ContainsKey('BakaDesktop')){[math]::Round(100*$use['BakaDesktop']/$wallMs,2)}else{$null}
$r.benchHostCpuPercent=[math]::Round(100*([double]$use['powershell']+[double]$use['WmiPrvSE']+[double]$use['wsmprovhost'])/$wallMs,2)
$c=Get-PSDrive C;$r.diskUsedGB=[math]::Round($c.Used/1GB,1)
$r.appxPackages=@(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue|Where-Object {-not $_.IsFramework -and $_.SignatureKind -ne 'System'}).Count
$r.startApps=@(Get-StartApps).Count
$r.scheduledTasksReady=@(Get-ScheduledTask|Where-Object State -eq 'Ready').Count
# top memory users
$r.topMemory=@(Get-Process|Sort-Object WorkingSet64 -Descending|Select-Object -First 8|ForEach-Object {"$($_.ProcessName) $([math]::Round($_.WorkingSet64/1MB))MB"})
$baka=@(Get-Process BakaDesktop -ErrorAction SilentlyContinue)
$r.bakaDesktopMB=if($baka){[math]::Round(($baka|Measure-Object WorkingSet64 -Sum).Sum/1MB)}else{$null}
# WinSAT refuses to run inside a VM, so the same small benchmarks run on both systems (best of 3):
#  CPU: SHA-256 of 64 MB (one core), memory: copying a 256 MB array, disk: writing and reading back a 1 GB file
function Best([scriptblock]$s){ $b=0; for($i=0;$i -lt 3;$i++){ $v=& $s; if($v -gt $b){$b=$v} }; [math]::Round($b,1) }
$buf=New-Object byte[] (64MB); (New-Object Random 7).NextBytes($buf)
$r.cpuSha256MBps=Best { $h=[Security.Cryptography.SHA256]::Create(); $sw=[Diagnostics.Stopwatch]::StartNew(); [void]$h.ComputeHash($buf); 64/$sw.Elapsed.TotalSeconds }
$src=New-Object byte[] (256MB); $dst=New-Object byte[] (256MB)
$r.memCopyMBps=Best { $sw=[Diagnostics.Stopwatch]::StartNew(); [Array]::Copy($src,$dst,$src.Length); 256/$sw.Elapsed.TotalSeconds }
$f=Join-Path $env:TEMP 'baka-bench.bin'; $chunk=New-Object byte[] (8MB); (New-Object Random 3).NextBytes($chunk)
$r.diskWriteMBps=Best { $sw=[Diagnostics.Stopwatch]::StartNew(); $fs=[IO.FileStream]::new([string]$f,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None,[int]1048576,[IO.FileOptions]::WriteThrough); for($i=0;$i -lt 128;$i++){$fs.Write($chunk,0,$chunk.Length)}; $fs.Close(); 1024/$sw.Elapsed.TotalSeconds }
Remove-Item $f -ErrorAction SilentlyContinue
$buf=$null;$src=$null;$dst=$null;[GC]::Collect()
# ad and tracker blocking: every domain of the public d3ward ad-block test, resolved through Windows
$blocked=0;$miss=@()
foreach($d in $Domains){
  $ips=@();try{$ips=@(Resolve-DnsName -Name $d -Type A -ErrorAction Stop|Where-Object Type -eq 'A'|ForEach-Object IPAddress)}catch{}
  if(-not $ips.Count -or ($ips|Where-Object {$_ -in @('0.0.0.0','127.0.0.1','94.140.14.35','94.140.14.36')})){$blocked++}else{$miss+=$d}
}
$r.adTestTotal=$Domains.Count;$r.adTestBlocked=$blocked;$r.adTestScore=[math]::Round(100*$blocked/[math]::Max(1,$Domains.Count),1);$r.adTestMissed=$miss
$r.dnsServers=@(Get-DnsClientServerAddress -AddressFamily IPv4|Where-Object {$_.ServerAddresses}|ForEach-Object {"$($_.InterfaceAlias)=$($_.ServerAddresses -join ',')"})
$r.dohServers=@(Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue|ForEach-Object {"$($_.ServerAddress) $($_.DohTemplate)"})
# privacy: what Windows sends and shows
function V($p,$n){try{(Get-ItemProperty -LiteralPath $p -Name $n -ErrorAction Stop).$n}catch{$null}}
$r.privacy=[ordered]@{
  DiagTrackService=(Get-Service DiagTrack -ErrorAction SilentlyContinue).StartType.ToString()
  dmwappushservice=(Get-Service dmwappushservice -ErrorAction SilentlyContinue).StartType.ToString()
  AllowTelemetryPolicy=V 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'
  AdvertisingIdPolicy=V 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy'
  CopilotOff=V 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot'
  RecallOff=V 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis'
  WebSearchInStartOff=V 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'DisableWebSearch'
  ActivityHistoryOff=V 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed'
  ConsumerFeaturesOff=V 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures'
  # Named telemetry tasks only. PcaPatchDbTask and SdbinstMergeDbTask (the app-compatibility database) are not counted.
  TelemetryTasksEnabled=@(@(
    '\Microsoft\Windows\Application Experience\|Microsoft Compatibility Appraiser','\Microsoft\Windows\Application Experience\|Microsoft Compatibility Appraiser Exp',
    '\Microsoft\Windows\Application Experience\|ProgramDataUpdater','\Microsoft\Windows\Application Experience\|StartupAppTask','\Microsoft\Windows\Application Experience\|MareBackup',
    '\Microsoft\Windows\Customer Experience Improvement Program\|Consolidator','\Microsoft\Windows\Customer Experience Improvement Program\|UsbCeip',
    '\Microsoft\Windows\Autochk\|Proxy','\Microsoft\Windows\DiskDiagnostic\|Microsoft-Windows-DiskDiagnosticDataCollector',
    '\Microsoft\Windows\Feedback\Siuf\|DmClient','\Microsoft\Windows\Feedback\Siuf\|DmClientOnScenarioDownload',
    '\Microsoft\Windows\Flighting\FeatureConfig\|UsageDataReporting','\Microsoft\Windows\Flighting\FeatureConfig\|UsageDataFlushing',
    '\Microsoft\Windows\Flighting\FeatureConfig\|UsageDataReceiver','\Microsoft\Windows\Flighting\FeatureConfig\|BootstrapUsageDataReporting',
    '\Microsoft\Windows\PI\|Sqm-Tasks')|ForEach-Object {$p,$n=$_ -split '\|';Get-ScheduledTask -TaskPath $p -TaskName $n -ErrorAction SilentlyContinue}|Where-Object State -ne 'Disabled').Count
  InventoryOff=V 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableInventory'
  TelemetryServicesRunning=@(Get-Service DiagTrack,dmwappushservice,InventorySvc,whesvc,WSAIFabricSvc,TrkWks -ErrorAction SilentlyContinue|Where-Object Status -eq 'Running'|ForEach-Object Name)
}
$r.apps=[ordered]@{
  Edge=Test-Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
  WebView2=Test-Path "${env:ProgramFiles(x86)}\Microsoft\EdgeWebView\Application"
  Store=[bool](Get-AppxPackage -AllUsers Microsoft.WindowsStore -ErrorAction SilentlyContinue)
  MediaPlayer=[bool](Get-AppxPackage -AllUsers Microsoft.ZuneMusic -ErrorAction SilentlyContinue)
  MoviesTV=[bool](Get-AppxPackage -AllUsers Microsoft.ZuneVideo -ErrorAction SilentlyContinue)
  LegacyWMP=@(Get-WindowsCapability -Online -Name 'Media.WindowsMediaPlayer*' -ErrorAction SilentlyContinue|Where-Object State -eq 'Installed').Count -gt 0
  WordPad=@(Get-WindowsCapability -Online -Name 'Microsoft.Windows.WordPad*' -ErrorAction SilentlyContinue|Where-Object State -eq 'Installed').Count -gt 0
  BakaBrowser=@(Get-ChildItem 'C:\Users\*\AppData\Local\BakaBrowser\current\baka.exe' -ErrorAction SilentlyContinue).Count -gt 0
  BakaDesktop=Test-Path "$env:ProgramData\BAKA\Desktop\BakaDesktop.exe"
}
$r.powerPlan=(powercfg /getactivescheme) -replace '^.*\((.*)\).*$','$1'
$r|ConvertTo-Json -Depth 5
