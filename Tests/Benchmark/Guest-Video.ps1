# Runs INSIDE the BAKA VM in the signed-in BAKA user's session. Checks the 4K video wallpaper on the real
# desktop: it starts, it pauses when a maximized window covers the desktop and plays again after, it is
# closed while a game runs and comes back after, and each 4K format plays in the player test.
# The 4K files are copied next to this script (Run-InUserSession copies only the script; the host wrapper copies the videos).
param([string]$Out)
$ErrorActionPreference='Continue'
New-Item -ItemType Directory -Path $Out -Force | Out-Null
$log=Join-Path $Out 'video.txt'
$results=[ordered]@{}
function L($m){Add-Content -LiteralPath $log -Value ('{0} {1}' -f (Get-Date -Format s),$m)}
function Res($name,$ok,$detail){$results[$name]=[ordered]@{ok=[bool]$ok;detail=[string]$detail};L ("{0} {1}: {2}" -f $(if($ok){'PASS'}else{'FAIL'}),$name,$detail)}
$exe="$env:ProgramData\BAKA\Desktop\BakaDesktop.exe"
$dlog="$env:LOCALAPPDATA\BAKA\Logs\Desktop.log"
$vids=Split-Path $Out
function LogSince([datetime]$t){ @(Get-Content $dlog -ErrorAction SilentlyContinue | Where-Object { $_ -match '^(\S+) (video-\S+.*)$' -and ([datetime]::Parse($Matches[1]) -ge $t) } | ForEach-Object { $_ }) }
function Cpu([int]$sec){ $p=@(Get-Process BakaDesktop -ErrorAction SilentlyContinue); $a=0;$p|ForEach-Object{$a+=$_.TotalProcessorTime.TotalMilliseconds}; Start-Sleep $sec; $b=0;@(Get-Process BakaDesktop -ErrorAction SilentlyContinue)|ForEach-Object{$b+=$_.TotalProcessorTime.TotalMilliseconds}; [math]::Round(100*($b-$a)/($sec*1000*[Environment]::ProcessorCount),2) }
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
function Shot($name){ try{ $s=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds; $b=New-Object System.Drawing.Bitmap $s.Width,$s.Height; $g=[System.Drawing.Graphics]::FromImage($b); $g.CopyFromScreen($s.Left,$s.Top,0,0,$b.Size); $b.Save((Join-Path $Out "$name.png")); $g.Dispose(); $b.Dispose() }catch{ L "shot failed $($_.Exception.Message)" } }
L "start user=$env:USERNAME cores=$([Environment]::ProcessorCount) decoders=$((Get-AppxPackage *VideoExtension* | ForEach-Object Name) -join ',')"
L ("gpu: "+((Get-CimInstance Win32_VideoController|ForEach-Object Name) -join '; '))

# 1. each format in the player test (window in the corner, 20 s)
foreach($f in 'loop-h264-4k-6s.mp4','earth-hevc-4k.mp4','earth-vp9-4k.webm','artemis-av1-4k.webm'){
  $file=Join-Path $vids $f; $res=Join-Path $Out ($f+'.json')
  if(-not (Test-Path $file)){ Res "format-$f" $false 'file not copied'; continue }
  $p=Start-Process $exe -ArgumentList '--video-test',"`"$file`"","`"$res`"",'20' -PassThru
  if(-not $p.WaitForExit(70000)){ Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; Res "format-$f" $false 'timeout'; continue }
  $j=Get-Content $res -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
  Res "format-$f" ($p.ExitCode -eq 0) ("{0}x{1} advanced {2} s in {3} s, cpu {4}% of all cores, loops {5} {6}" -f $j.videoWidth,$j.videoHeight,$j.positionAdvanced,$j.playedSeconds,$j.cpuPercentOfAllCores,$j.loops,$j.error)
}

# 2. the real desktop wallpaper
$wall=Join-Path $vids 'loop-h264-4k-6s.mp4'
$t0=Get-Date
& $exe --wallpaper $wall; Start-Sleep 10
$lines=LogSince $t0
Res 'wallpaper-starts' (($lines -match 'video-ready size=3840x2160').Count -gt 0 -and ($lines -match 'video-wallpaper-failed').Count -eq 0) ($lines -join ' / ')
Shot 'desktop-video-wallpaper'
$cpuPlay=Cpu 10
Res 'wallpaper-cpu-playing' $true "BAKA Desktop CPU while the 4K video plays: $cpuPlay% of all cores (no GPU in this VM: software decoding)"

# 3. covered by a maximized window -> paused
$t1=Get-Date
$np=Start-Process notepad.exe -WindowStyle Maximized -PassThru; Start-Sleep 5
$cpuCovered=Cpu 8
$lines=LogSince $t1
Res 'wallpaper-pauses-when-covered' (($lines -match 'video-wallpaper-paused reason=covered').Count -gt 0) ("cpu while covered $cpuCovered% :: "+($lines -join ' / '))
Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 4
$lines=LogSince $t1
Res 'wallpaper-plays-again' (($lines -match 'video-wallpaper-playing').Count -gt 0) ($lines -join ' / ')

# 4. game -> closed, after -> back
$t2=Get-Date
& $exe --profile gaming; Start-Sleep 5
$cpuGame=Cpu 8
$lines=LogSince $t2
Res 'wallpaper-closed-in-game' (($lines -match 'suspended reason=game').Count -gt 0) ("cpu in game mode $cpuGame% :: "+($lines -join ' / '))
& $exe --profile desktop; Start-Sleep 8
$lines=LogSince $t2
Res 'wallpaper-back-after-game' (($lines -match 'video-wallpaper-resumed').Count -gt 0 -and ($lines -match 'video-ready').Count -gt 0) ($lines -join ' / ')
Shot 'desktop-video-after-game'

# 5. a VP9 4K wallpaper too, then back to the BAKA picture
$t3=Get-Date
& $exe --wallpaper (Join-Path $vids 'earth-vp9-4k.webm'); Start-Sleep 10
$lines=LogSince $t3
Res 'wallpaper-vp9' (($lines -match 'video-ready size=3840x2160').Count -gt 0) ($lines -join ' / ')
Shot 'desktop-video-vp9'
# back to the default BAKA picture, so later benchmarks do not measure a playing 4K video
$pic=Get-ChildItem "$env:ProgramData\BAKA\Assets" -Recurse -Include 'BAKA-Stealth-4K.png','BAKA-BlackGlass-4K.png','*.png' -ErrorAction SilentlyContinue | Select-Object -First 1
if($pic){ & $exe --wallpaper $pic.FullName; Start-Sleep 4; L "wallpaper reset to $($pic.FullName)" } else { L 'FAIL no BAKA picture found to reset the wallpaper' }

$results | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $Out 'video.json') -Encoding UTF8
L 'DONE'
'done' | Set-Content (Join-Path $Out 'done.txt')
