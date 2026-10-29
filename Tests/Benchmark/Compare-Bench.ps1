# Compares bench-Stock.json, bench-Baka.json (BAKA Desktop mode) and, if present, bench-BakaGaming.json
# (the same BAKA VM after BakaDesktop.exe --profile gaming). Writes compare.md and compare.json.
# Score: for each metric, ratio = stock/baka when lower is better, baka/stock when higher is better.
# Performance score = 100 x geometric mean of the ratios (100 = same as stock Windows, 110 = 10% better on average).
param([string]$ResultDir=$PSScriptRoot)
$vm=$ResultDir
$s=Get-Content (Join-Path $vm 'bench-Stock.json') -Raw|ConvertFrom-Json
$b=Get-Content (Join-Path $vm 'bench-Baka.json') -Raw|ConvertFrom-Json
$gPath=Join-Path $vm 'bench-BakaGaming.json'
$g=if(Test-Path $gPath){Get-Content $gPath -Raw|ConvertFrom-Json}else{$null}
function Num($lines,$pattern){ foreach($l in @($lines)){ if($l -match $pattern -and $l -match '([\d\.]+)\s*(MB/s|MB/sec|s)?\s*$'){ return [double]$Matches[1] } }; $null }
$metrics=@(
  @{n='Boot time (Windows boot event, s)';f='bootTimeSec';low=$true;score=$true;boot=$true},
  @{n='Main boot path (s)';f='bootMainPathSec';low=$true;score=$false;boot=$true},
  @{n='Memory in use at idle (MB)';f='memoryInUseMB';low=$true;score=$true},
  @{n='Memory committed (MB)';f='memoryCommittedMB';low=$true;score=$true},
  @{n='Processes';f='processes';low=$true;score=$true},
  @{n='Threads';f='threads';low=$true;score=$false},
  @{n='Running services';f='servicesRunning';low=$true;score=$true},
  @{n='Idle CPU, 60 s average (%)';f='idleCpuAvgPercent';low=$true;score=$true},
  @{n='BAKA shell memory (MB)';f='bakaDesktopMB';low=$true;score=$false},
  @{n='BAKA shell CPU, 60 s average (%)';f='bakaDesktopCpuPercent';low=$true;score=$false},
  @{n='Disk used on C: (GB)';f='diskUsedGB';low=$true;score=$true},
  @{n='Ready scheduled tasks';f='scheduledTasksReady';low=$true;score=$false},
  @{n='CPU: SHA-256, one core (MB/s)';f='cpuSha256MBps';low=$false;score=$true},
  @{n='Memory copy, 256 MB (MB/s)';f='memCopyMBps';low=$false;score=$true},
  @{n='Disk write, 1 GB write-through (MB/s)';f='diskWriteMBps';low=$false;score=$true}
)
function Val($o,$f){ if($null -eq $o){return $null}; $p=$o.PSObject.Properties[$f]; if($p){$p.Value}else{$null} }
function Cmp($r,$sv,$xv){
  if($null -eq $sv -or $null -eq $xv -or [double]$sv -le 0 -or [double]$xv -le 0){return @{t='';ratio=$null}}
  $ratio=if($r.low){[double]$sv/[double]$xv}else{[double]$xv/[double]$sv}
  $pct=[math]::Round(($ratio-1)*100,1)
  $t=if([math]::Abs($pct) -lt 2){'same'}elseif($pct -gt 0){"BAKA +$pct%"}else{"stock +$([math]::Abs($pct))%"}
  @{t=$t;ratio=$ratio}
}
$head='| Measurement | Stock Windows 11 | BAKA Desktop mode | vs stock |'
$sep='|---|---:|---:|---|'
if($g){$head+=' BAKA Gaming mode | vs stock |';$sep+='---:|---|'}
$md=@($head,$sep)
$sumB=0.0;$kB=0;$sumG=0.0;$kG=0
foreach($r in $metrics){
  $sv=Val $s $r.f;$bv=Val $b $r.f
  $cb=Cmp $r $sv $bv
  if($r.score -and $null -ne $cb.ratio){$sumB+=[math]::Log($cb.ratio);$kB++}
  $line="| $($r.n) | $sv | $bv | $($cb.t) |"
  if($g){
    # Gaming mode is switched on after boot, so boot time is the same machine state; show it as n/a.
    $gv=if($r.boot){$null}else{Val $g $r.f}
    $cg=Cmp $r $sv $gv
    if($r.score -and -not $r.boot -and $null -ne $cg.ratio){$sumG+=[math]::Log($cg.ratio);$kG++}
    $line+=" $(if($r.boot){'n/a'}else{$gv}) | $($cg.t) |"
  }
  $md+=$line
}
$perf=if($kB){[math]::Round(100*[math]::Exp($sumB/$kB),1)}else{$null}
$perfG=if($kG){[math]::Round(100*[math]::Exp($sumG/$kG),1)}else{$null}
# privacy checklist: each item is 1 point when the privacy-friendly value is set
function P($p){ $c=0;$t=0
  $t++;if($p.DiagTrackService -eq 'Disabled'){$c++}
  $t++;if($p.dmwappushservice -eq 'Disabled'){$c++}
  $t++;if($p.AllowTelemetryPolicy -eq 0 -or $p.AllowTelemetryPolicy -eq 1){$c++}
  $t++;if($p.AdvertisingIdPolicy -eq 1){$c++}
  $t++;if($p.CopilotOff -eq 1){$c++}
  $t++;if($p.RecallOff -eq 1){$c++}
  $t++;if($p.WebSearchInStartOff -eq 1){$c++}
  $t++;if($p.ActivityHistoryOff -eq 0){$c++}
  $t++;if($p.ConsumerFeaturesOff -eq 1){$c++}
  $t++;if($p.TelemetryTasksEnabled -eq 0){$c++}
  $t++;if($p.InventoryOff -eq 1){$c++}
  $t++;if(@($p.TelemetryServicesRunning).Count -eq 0){$c++}
  [pscustomobject]@{Passed=$c;Total=$t} }
$ps=P $s.privacy;$pb=P $b.privacy
$o=[ordered]@{
  performanceScoreDesktop=$perf; metricsInScoreDesktop=$kB
  performanceScoreGaming=$perfG; metricsInScoreGaming=$kG
  adStock="$($s.adTestBlocked)/$($s.adTestTotal) = $($s.adTestScore)%"; adBaka="$($b.adTestBlocked)/$($b.adTestTotal) = $($b.adTestScore)%"; adBakaMissed=$b.adTestMissed
  privacyStock="$($ps.Passed)/$($ps.Total)"; privacyBaka="$($pb.Passed)/$($pb.Total)"
  privacyStockRaw=$s.privacy; privacyBakaRaw=$b.privacy
  appsStock=$s.apps; appsBaka=$b.apps
  appx="$($s.appxPackages) vs $($b.appxPackages)"; startApps="$($s.startApps) vs $($b.startApps)"
  power="$($s.powerPlan) vs $($b.powerPlan)$(if($g){' vs gaming '+$g.powerPlan})"
  bakaDesktopMB="$($b.bakaDesktopMB)$(if($g){' / gaming '+$g.bakaDesktopMB})"
  topStock=$s.topMemory; topBaka=$b.topMemory; topGaming=$(if($g){$g.topMemory})
  windows="$($s.windows) | $($b.windows)"; uptime="$($s.uptimeMinutes) / $($b.uptimeMinutes) min"
  dnsBaka=$b.dnsServers; dohBaka=$b.dohServers
}
($md -join "`n")|Set-Content (Join-Path $vm 'compare.md') -Encoding UTF8
$o|ConvertTo-Json -Depth 5|Set-Content (Join-Path $vm 'compare.json') -Encoding UTF8
