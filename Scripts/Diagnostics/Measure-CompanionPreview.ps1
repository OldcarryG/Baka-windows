[CmdletBinding()]
param(
    [ValidateRange(3,60)][int]$SampleCount=15,
    [ValidateRange(1,30)][int]$IntervalSeconds=2,
    [ValidateRange(1,60)][int]$StartupWaitSeconds=5,
    # Measures the everyday desktop (dock + menu bar, no Arena welcome) after the startup memory trim.
    [switch]$IdleDesktop
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime=Join-Path $root 'Scripts\Runtime\BakaCompanion.ps1'
$engine=Get-Command powershell.exe -ErrorAction SilentlyContinue
if(-not $engine){$engine=Get-Command pwsh.exe -ErrorAction Stop}
$companionArgs=@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $runtime),'-Preview')
if($IdleDesktop){$companionArgs+='-IdleDesktop';if(-not $PSBoundParameters.ContainsKey('StartupWaitSeconds')){$StartupWaitSeconds=30}}
$process=Start-Process -FilePath $engine.Source -ArgumentList $companionArgs -WorkingDirectory $root -WindowStyle Hidden -PassThru
$samples=[System.Collections.Generic.List[object]]::new()
try {
    Start-Sleep -Seconds $StartupWaitSeconds
    $process.Refresh()
    if($process.HasExited){throw 'The preview companion exited before sampling began.'}
    $previousCpu=$process.TotalProcessorTime
    $previousAt=Get-Date
    for($i=0;$i -lt $SampleCount;$i++){
        Start-Sleep -Seconds $IntervalSeconds
        $process.Refresh()
        if($process.HasExited){break}
        $now=Get-Date
        $wall=($now-$previousAt).TotalSeconds
        $cpuDelta=($process.TotalProcessorTime-$previousCpu).TotalSeconds
        $cpuPercent=if($wall -gt 0){[math]::Round(100*$cpuDelta/($wall*[Environment]::ProcessorCount),3)}else{0}
        $samples.Add([pscustomobject]@{Sample=$i+1;CpuPercent=$cpuPercent;WorkingSetMiB=[math]::Round($process.WorkingSet64/1MB,2);PrivateMiB=[math]::Round($process.PrivateMemorySize64/1MB,2)})
        $previousCpu=$process.TotalProcessorTime
        $previousAt=$now
    }
} finally {
    if(-not $process.HasExited){Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue}
    $process.Dispose()
}
if($samples.Count -eq 0){throw 'No companion resource samples were captured.'}
$cpuStats=$samples|Measure-Object -Property CpuPercent -Average -Maximum
$workingStats=$samples|Measure-Object -Property WorkingSetMiB -Average -Maximum
$record=[pscustomobject]@{
    SchemaVersion=1
    Test='BAKA Liquid host preview resource sample'
    CompletedAt=(Get-Date).ToString('o')
    HostEnvironment='Development host preview; not installed-image acceptance'
    Scenario=if($IdleDesktop){'Idle desktop: dock + menu bar after startup trim'}else{'First run: Arena welcome open'}
    SampleCount=$samples.Count
    IntervalSeconds=$IntervalSeconds
    StartupWaitSeconds=$StartupWaitSeconds
    AverageCpuPercent=[math]::Round($cpuStats.Average,3)
    MaximumCpuPercent=[math]::Round($cpuStats.Maximum,3)
    AverageWorkingSetMiB=[math]::Round($workingStats.Average,2)
    MaximumWorkingSetMiB=[math]::Round($workingStats.Maximum,2)
    CpuTarget='Average <= 1%'
    WorkingSetTarget='Average <= 150 MiB'
    CpuTargetMet=($cpuStats.Average -le 1)
    WorkingSetTargetMet=($workingStats.Average -le 150)
    Samples=@($samples)
}
$logDirectory=Join-Path $root 'Logs'
if(-not(Test-Path -LiteralPath $logDirectory -PathType Container)){New-Item -ItemType Directory -Path $logDirectory -Force|Out-Null}
$reportPath=Join-Path $logDirectory ('HostPreviewResource-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json')
$record|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $reportPath -Encoding UTF8
$record|Select-Object Test,Scenario,SampleCount,AverageCpuPercent,MaximumCpuPercent,AverageWorkingSetMiB,MaximumWorkingSetMiB,CpuTargetMet,WorkingSetTargetMet|Format-List
Write-Output "Report: $reportPath"
