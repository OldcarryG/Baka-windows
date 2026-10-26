[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Stock','BAKA')]
    [string]$Profile,
    [ValidateRange(1,1440)]
    [int]$SampleCount=120,
    [ValidateRange(1,300)]
    [int]$IntervalSeconds=5,
    [string]$OutputDirectory=(Join-Path $env:LOCALAPPDATA 'BAKA\AB-Metrics')
)

$ErrorActionPreference='Stop'
$counterDefinitions=@(
    [pscustomobject]@{Path='\Processor(_Total)\% Processor Time';Name='CpuTotalPercent';Required=$true},
    [pscustomobject]@{Path='\Memory\Available MBytes';Name='AvailableMemoryMB';Required=$true},
    [pscustomobject]@{Path='\Memory\Committed Bytes';Name='CommittedMemoryBytes';Required=$false},
    [pscustomobject]@{Path='\PhysicalDisk(_Total)\Disk Bytes/sec';Name='DiskBytesPerSecond';Required=$false}
)

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$available=@()
$unsupported=@()
foreach($definition in $counterDefinitions){
    try{
        Get-Counter -Counter $definition.Path -SampleInterval 1 -MaxSamples 1 -ErrorAction Stop | Out-Null
        $available+=$definition
    }catch{
        $unsupported+=([pscustomobject]@{Counter=$definition.Path;Reason=$_.Exception.Message})
        if($definition.Required){throw "Required performance counter is unavailable: $($definition.Path). $($_.Exception.Message)"}
    }
}

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$safeProfile=$Profile.ToLowerInvariant()
$csvPath=Join-Path $OutputDirectory "BAKA-AB-$safeProfile-$stamp.csv"
$jsonPath=Join-Path $OutputDirectory "BAKA-AB-$safeProfile-$stamp.json"
$counterPaths=@($available|ForEach-Object {$_.Path})
$rows=New-Object System.Collections.Generic.List[object]
$started=Get-Date
$system=Get-CimInstance Win32_ComputerSystem
$previousProcessState=@{Baka=$null;Game=$null;Timestamp=$null}
$processNamesSeen=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
for($sampleIndex=0;$sampleIndex -lt $SampleCount;$sampleIndex++){
    $cycle=[System.Diagnostics.Stopwatch]::StartNew()
    $counterSet=Get-Counter -Counter $counterPaths -SampleInterval 1 -MaxSamples 1 -ErrorAction Stop
    $counterTimestamp=$counterSet.Timestamp
    $values=@{}
    foreach($sample in $counterSet.CounterSamples){
        foreach($definition in $available){
            if($sample.Path -match ([regex]::Escape($definition.Path)+'$')){
                $values[$definition.Name]=[double]$sample.CookedValue
                break
            }
        }
    }

    $processSnapshot=Get-Process -ErrorAction SilentlyContinue
    $bakaIds=@()
    try{
        $bakaIds=@(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {$_.CommandLine -match '(?i)BakaCompanion\.ps1'} | ForEach-Object {[int]$_.ProcessId})
    }catch{}
    $bakaProcesses=@($processSnapshot | Where-Object {$_.Id -in $bakaIds})
    $gameProcesses=@($processSnapshot | Where-Object {$_.ProcessName -match '^(?i:cs2|tf_win64|hl2)$'})
    foreach($processName in @($bakaProcesses.ProcessName)+@($gameProcesses.ProcessName)){if($processName){[void]$processNamesSeen.Add([string]$processName)}}

    $processTimestamp=Get-Date
    $elapsedSeconds=$IntervalSeconds
    if($previousProcessState.Timestamp){$elapsedSeconds=[math]::Max(0.1,($processTimestamp-$previousProcessState.Timestamp).TotalSeconds)}
    $bakaCpuSeconds=($bakaProcesses | Measure-Object -Property CPU -Sum).Sum
    $gameCpuSeconds=($gameProcesses | Measure-Object -Property CPU -Sum).Sum
    $bakaCpuPercent=$null
    $gameCpuPercent=$null
    if($null -ne $bakaCpuSeconds -and $null -ne $previousProcessState.Baka){$bakaCpuPercent=[math]::Round((([double]$bakaCpuSeconds-[double]$previousProcessState.Baka)/$elapsedSeconds/[math]::Max(1,[int]$system.NumberOfLogicalProcessors))*100,3)}
    if($null -ne $gameCpuSeconds -and $null -ne $previousProcessState.Game){$gameCpuPercent=[math]::Round((([double]$gameCpuSeconds-[double]$previousProcessState.Game)/$elapsedSeconds/[math]::Max(1,[int]$system.NumberOfLogicalProcessors))*100,3)}
    $previousProcessState=@{Baka=$bakaCpuSeconds;Game=$gameCpuSeconds;Timestamp=$processTimestamp}
    $cycle.Stop()

    $rows.Add([pscustomobject]@{
        Timestamp=$counterTimestamp.ToString('o')
        Profile=$Profile
        CpuTotalPercent=$values['CpuTotalPercent']
        AvailableMemoryMB=$values['AvailableMemoryMB']
        CommittedMemoryBytes=$values['CommittedMemoryBytes']
        DiskBytesPerSecond=$values['DiskBytesPerSecond']
        BakaProcessCpuPercent=$bakaCpuPercent
        BakaProcessWorkingSetMB=if($bakaProcesses.Count){[math]::Round((($bakaProcesses | Measure-Object -Property WorkingSet64 -Sum).Sum/1MB),1)}else{$null}
        GameProcessCpuPercent=$gameCpuPercent
        GameProcessWorkingSetMB=if($gameProcesses.Count){[math]::Round((($gameProcesses | Measure-Object -Property WorkingSet64 -Sum).Sum/1MB),1)}else{$null}
        CollectorElapsedMilliseconds=[math]::Round($cycle.Elapsed.TotalMilliseconds,1)
    })

    $remainingMilliseconds=($IntervalSeconds*1000)-$cycle.Elapsed.TotalMilliseconds
    if($sampleIndex -lt ($SampleCount-1) -and $remainingMilliseconds -gt 0){Start-Sleep -Milliseconds ([int]$remainingMilliseconds)}
}

if($rows.Count -ne $SampleCount){throw "Expected $SampleCount performance samples but received $($rows.Count)."}
$rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

function Get-MedianValue([double[]]$Values){
    $sorted=@($Values|Sort-Object)
    if($sorted.Count -eq 0){return $null}
    $mid=[int][math]::Floor($sorted.Count/2)
    if(($sorted.Count%2) -eq 1){return [double]$sorted[$mid]}
    return ([double]$sorted[$mid-1]+[double]$sorted[$mid])/2
}

$cpu=@($rows|ForEach-Object {[double]$_.CpuTotalPercent})
$availableMemory=@($rows|ForEach-Object {[double]$_.AvailableMemoryMB})
$cpuAverage=($cpu|Measure-Object -Average).Average
$memoryMedian=Get-MedianValue $availableMemory
$bakaCpu=@($rows|Where-Object {$null -ne $_.BakaProcessCpuPercent}|ForEach-Object {[double]$_.BakaProcessCpuPercent})
$gameCpu=@($rows|Where-Object {$null -ne $_.GameProcessCpuPercent}|ForEach-Object {[double]$_.GameProcessCpuPercent})
$bakaWorkingSet=@($rows|Where-Object {$null -ne $_.BakaProcessWorkingSetMB}|ForEach-Object {[double]$_.BakaProcessWorkingSetMB})
$gameWorkingSet=@($rows|Where-Object {$null -ne $_.GameProcessWorkingSetMB}|ForEach-Object {[double]$_.GameProcessWorkingSetMB})
$os=Get-CimInstance Win32_OperatingSystem
$processor=Get-CimInstance Win32_Processor|Select-Object -First 1
$metadata=[ordered]@{
    schemaVersion=1
    profile=$Profile
    capturedAt=$started.ToString('o')
    completedAt=(Get-Date).ToString('o')
    sampleCount=$rows.Count
    intervalSeconds=$IntervalSeconds
    guest=$system.Name
    os=$os.Caption
    osVersion=$os.Version
    osBuild=$os.BuildNumber
    cpu=$processor.Name
    logicalProcessors=$system.NumberOfLogicalProcessors
    totalMemoryBytes=$system.TotalPhysicalMemory
    counterPaths=$counterPaths
    unsupportedCounters=$unsupported
    observedProcessNames=@($processNamesSeen|Sort-Object)
    summary=[ordered]@{
        meanCpuTotalPercent=[math]::Round([double]$cpuAverage,3)
        medianAvailableMemoryMB=[math]::Round([double]$memoryMedian,1)
        meanDiskBytesPerSecond=if($available.Name -contains 'DiskBytesPerSecond'){[math]::Round([double](($rows|Measure-Object -Property DiskBytesPerSecond -Average).Average),1)}else{$null}
        meanBakaProcessCpuPercent=if($bakaCpu.Count){[math]::Round([double](($bakaCpu|Measure-Object -Average).Average),3)}else{$null}
        medianBakaProcessWorkingSetMB=if($bakaWorkingSet.Count){[math]::Round([double](Get-MedianValue $bakaWorkingSet),1)}else{$null}
        meanGameProcessCpuPercent=if($gameCpu.Count){[math]::Round([double](($gameCpu|Measure-Object -Average).Average),3)}else{$null}
        medianGameProcessWorkingSetMB=if($gameWorkingSet.Count){[math]::Round([double](Get-MedianValue $gameWorkingSet),1)}else{$null}
    }
    csvFile=(Split-Path -Leaf $csvPath)
}
$metadata|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $jsonPath -Encoding UTF8

[pscustomobject]@{Profile=$Profile;Samples=$rows.Count;Csv=$csvPath;SummaryJson=$jsonPath;MeanCpuPct=$metadata.summary.meanCpuTotalPercent;MedianAvailableMemoryMB=$metadata.summary.medianAvailableMemoryMB}
