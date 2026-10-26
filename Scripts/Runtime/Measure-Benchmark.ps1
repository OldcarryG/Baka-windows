[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Start','Stop')][string]$Mode,
    [string]$RunId,
    [string]$Scenario,
    [string]$Notes,
    [Nullable[double]]$AverageFps,
    [Nullable[double]]$OnePercentLowFps,
    [Nullable[double]]$InputLatencyMs,
    [string]$MeasurementTool
)
$ErrorActionPreference='Stop'
$dataRoot=Split-Path -Parent $PSScriptRoot
$profileModule=Join-Path $dataRoot 'Modules\GamingProfiles.psm1'
$hardwareModule=Join-Path $dataRoot 'Modules\HardwareDetection.psm1'
Import-Module $profileModule -Force
Import-Module $hardwareModule -Force
$root=Join-Path $env:LOCALAPPDATA 'BAKA\Benchmarks'
if(-not(Test-Path -LiteralPath $root)){New-Item -ItemType Directory -Path $root -Force|Out-Null}
if($Mode -eq 'Start'){
    if(-not $Scenario){$Scenario=Read-Host 'Benchmark scenario (game/map/resolution/settings)'}
    if(-not $Notes){$Notes=Read-Host 'Change from baseline (or leave blank)'}
    $RunId=('{0:yyyyMMdd-HHmmss}-{1}' -f (Get-Date),(Get-Random -Minimum 1000 -Maximum 9999))
    $directory=Join-Path $root $RunId
    New-Item -ItemType Directory -Path $directory -Force|Out-Null
    $power=(& (Join-Path $env:WINDIR 'System32\powercfg.exe') /getactivescheme 2>&1 | Out-String).Trim()
    $condition=[pscustomobject]@{
        RunId=$RunId; Scenario=$Scenario; Notes=$Notes; StartedAt=(Get-Date).ToString('o')
        Hardware=Get-BakaHardwareInventory; ActivePowerScheme=$power
        Profile='Benchmark'; WindowsBuild=(Get-CimInstance Win32_OperatingSystem).BuildNumber
        Metrics=@{AverageFps=$null;OnePercentLowFps=$null;InputLatencyMs=$null;FrametimeEvidence=$null}
        MeasurementTool=$null;ResultsStatus='Pending manual measurements'
    }
    $condition|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $directory 'benchmark.json') -Encoding UTF8
    [void](Set-BakaGamingProfile -Profile 'Benchmark')
    Write-Host "Benchmark started: $RunId`nConditions: $directory\benchmark.json`nUse the same conditions for the baseline and candidate runs."
    return
}
if(-not $RunId){throw 'RunId is required for Stop.'}
$resultFile=Join-Path (Join-Path $root $RunId) 'benchmark.json'
if(-not(Test-Path -LiteralPath $resultFile -PathType Leaf)){throw "Benchmark record not found: $resultFile"}
$result=Get-Content -LiteralPath $resultFile -Raw|ConvertFrom-Json
$result.FinishedAt=(Get-Date).ToString('o')
$result.Metrics=[pscustomobject]@{AverageFps=$AverageFps;OnePercentLowFps=$OnePercentLowFps;InputLatencyMs=$InputLatencyMs;FrametimeEvidence=$null}
$result.MeasurementTool=$MeasurementTool
$result.Notes=if($Notes){$Notes}else{$result.Notes}
$result.ResultsStatus=if($null -ne $AverageFps -or $null -ne $OnePercentLowFps -or $null -ne $InputLatencyMs){'Measured; review repeatability and regressions'}else{'No metric supplied; incomplete'}
$result|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $resultFile -Encoding UTF8
[void](Set-BakaGamingProfile -Profile 'Desktop')
Write-Host "Benchmark record closed and baseline user settings restored: $resultFile"
