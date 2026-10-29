# Runs INSIDE the BAKA VM in the BAKA user's session. Which part of BAKA Desktop adds key latency on the
# desktop? Measures key latency (Guest-Latency.ps1, Desktop mode part) with BAKA Desktop in several states.
param([string]$Out,[int]$Rounds=2)
$ErrorActionPreference='Continue'
New-Item -ItemType Directory -Path $Out -Force | Out-Null
$log=Join-Path $Out 'variants.txt'
function L($m){Add-Content -LiteralPath $log -Value ('{0} {1}' -f (Get-Date -Format s),$m)}
$exe="$env:ProgramData\BAKA\Desktop\BakaDesktop.exe"
$settings=Join-Path $env:LOCALAPPDATA 'BAKA\Settings\desktop-settings.json'
$original=[IO.File]::ReadAllText($settings)
$here=Split-Path -Parent $MyInvocation.MyCommand.Path
function SetIntegration([bool]$keys,[bool]$buttons){
  $j=$original | ConvertFrom-Json
  if(-not $j.integration){ $j | Add-Member -NotePropertyName integration -NotePropertyValue ([pscustomobject]@{}) }
  $j.integration | Add-Member -NotePropertyName winKeyOpensLaunchpad -NotePropertyValue $keys -Force
  $j.integration | Add-Member -NotePropertyName captionButtons -NotePropertyValue $buttons -Force
  [IO.File]::WriteAllText($settings,($j | ConvertTo-Json -Depth 30))
}
function StopBaka{ Get-Process BakaDesktop -EA SilentlyContinue | Stop-Process -Force; Start-Sleep 2 }
function StartBaka{ Start-Process $exe; Start-Sleep 10 }
function Get-VariantLatency($name){
  $d=Join-Path $Out $name; Remove-Item $d -Recurse -Force -EA SilentlyContinue
  & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $here 'Guest-Latency.ps1') -Out $d | Out-Null
  $j=Get-Content (Join-Path $d 'latency.json') -Raw -EA SilentlyContinue | ConvertFrom-Json
  $i=$j.'desktop-input'
  L ("{0}: p50={1} p99={2} max={3} n={4} fg={5} running={6}" -f $name,$i.keyP50Ms,$i.keyP99Ms,$i.keyMaxMs,$i.keySamples,$i.foreground,@(Get-Process BakaDesktop -EA SilentlyContinue).Count)
}
L 'start'
trap { L "error: $($_.Exception.Message) at $($_.InvocationInfo.ScriptLineNumber)"; continue }
try{
  for($r=1;$r -le $Rounds;$r++){
    foreach($v in @(@{n='all-on';k=$true;b=$true},@{n='keys-off';k=$false;b=$true},@{n='buttons-off';k=$true;b=$false},@{n='both-off';k=$false;b=$false})){
      StopBaka; try{ SetIntegration $v.k $v.b }catch{ L "settings failed: $($_.Exception.Message)" }; StartBaka; Get-VariantLatency "$($v.n)-$r"
    }
    StopBaka; Get-VariantLatency "not-running-$r"
  }
}finally{
  [IO.File]::WriteAllText($settings,$original); StopBaka; StartBaka; L 'restored'
}
'done' | Set-Content (Join-Path $Out 'done.txt')
