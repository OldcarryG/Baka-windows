[CmdletBinding()]
param([int]$TimeoutSeconds=60)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$runtime=Join-Path $root 'Scripts\Runtime\BakaCompanion.ps1'
if(-not(Test-Path -LiteralPath $runtime -PathType Leaf)){throw "BAKA companion is missing: $runtime"}
$source=Get-Content -LiteralPath $runtime -Raw -ErrorAction Stop
$sourceGuards=@(
    [pscustomobject]@{Name='smoke timer initialized before cleanup';Pattern='\$script:smokeTimer=\$null'},
    [pscustomobject]@{Name='game polling tolerates unopened Quick Panel';Pattern='\$script:windows\.Quick -and \$script:windows\.Quick\.IsVisible'},
    [pscustomobject]@{Name='action buttons render supplied glyphs';Pattern='IsNullOrWhiteSpace\(\$Glyph\)'},
    [pscustomobject]@{Name='settings import reports invalid files';Pattern='Settings import failed'},
    [pscustomobject]@{Name='manual profiles stop automatic process polling';Pattern='if\(\$script:manualOverride\)\{Update-BakaProfileStatus;return\}' }
)
foreach($guard in $sourceGuards){if($source -notmatch $guard.Pattern){throw "Companion reliability guard failed: $($guard.Name)"}}
$engine=Get-Command powershell.exe -ErrorAction SilentlyContinue
if(-not $engine){$engine=Get-Command pwsh.exe -ErrorAction Stop}
$existing=@(Get-ChildItem -LiteralPath $env:TEMP -Directory -Filter 'BAKA-Liquid-Preview-*' -ErrorAction SilentlyContinue|ForEach-Object FullName)
$started=Get-Date
$arguments=@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $runtime),'-Preview','-SmokeTest')
$process=Start-Process -FilePath $engine.Source -ArgumentList $arguments -WindowStyle Hidden -PassThru
$timer=[Diagnostics.Stopwatch]::StartNew()
$completed=$process.WaitForExit([math]::Max(10,$TimeoutSeconds)*1000)
if(-not $completed){Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue;throw "BAKA companion preview did not exit within $TimeoutSeconds seconds."}
$timer.Stop()
$previewRoot=Get-ChildItem -LiteralPath $env:TEMP -Directory -Filter 'BAKA-Liquid-Preview-*' -ErrorAction SilentlyContinue|Where-Object {$_.FullName -notin $existing -and $_.CreationTime -ge $started.AddSeconds(-2)}|Sort-Object LastWriteTime -Descending|Select-Object -First 1
if(-not $previewRoot){throw 'The preview did not create its isolated temporary data directory.'}
$logPath=Join-Path $previewRoot.FullName 'Logs\Companion.log'
if(-not(Test-Path -LiteralPath $logPath -PathType Leaf)){throw 'The preview did not write a runtime log.'}
$logLines=@(Get-Content -LiteralPath $logPath)
$requiredStages=@('ui-smoke-stage=surfaces-visible','ui-smoke-stage=liquid-glass-motion','ui-smoke-stage=glass-surface-coverage','ui-animation=liquid-glint','ui-animation=dock-wave','ui-smoke-stage=gaming-profile','ui-smoke-stage=gaming-profile-motion-suppressed','ui-smoke-stage=benchmark-profile','ui-smoke-stage=benchmark-profile-motion-suppressed','ui-smoke-stage=desktop-restore-and-themes','ui-smoke-stage=widget-and-settings-check','ui-smoke-passed metricsCaptured=true','companion-exit-cleanup-complete')
$missingStages=@($requiredStages|Where-Object {-not ($logLines -match [regex]::Escape($_))})
$runtimeErrors=@($logLines|Where-Object {$_ -match 'ui-smoke-failed|ui-exception|companion-fatal|shutdown-restore-failed'})
$metricsCaptured=[bool]($logLines|Where-Object {$_ -match 'metrics-query-complete'})
$result=if($process.ExitCode -eq 0 -and -not $missingStages.Count -and -not $runtimeErrors.Count -and $metricsCaptured){'Passed'}else{'Failed'}
$record=[pscustomobject]@{
    schemaVersion=1
    test='BAKA Liquid WPF preview smoke'
    result=$result
    completedAt=(Get-Date).ToString('o')
    processExitCode=$process.ExitCode
    durationSeconds=[math]::Round($timer.Elapsed.TotalSeconds,2)
    isolatedPreview=$true
    simulatedRegistry=$true
    systemMetricsCaptured=$metricsCaptured
    stages=$requiredStages
    missingStages=$missingStages
    runtimeErrors=$runtimeErrors
    dwmOpaqueFallbackObserved=[bool]($logLines|Where-Object {$_ -match 'backdrop-fallback'})
    physicalHardwareTested=$false
    gamePerformanceMeasured=$false
}
$logDirectory=Join-Path $root 'Logs'
if(-not(Test-Path -LiteralPath $logDirectory -PathType Container)){New-Item -ItemType Directory -Path $logDirectory -Force|Out-Null}
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$reportPath=Join-Path $logDirectory "BAKA-Liquid-Preview-Smoke-$stamp.json"
[IO.File]::WriteAllText($reportPath,($record|ConvertTo-Json -Depth 6)+[Environment]::NewLine,[Text.UTF8Encoding]::new($true))
Write-Output ("{0}: {1} stages passed; exit={2}; report={3}" -f $record.result,($requiredStages.Count-$missingStages.Count),$process.ExitCode,$reportPath)
if($result -ne 'Passed'){throw ('BAKA UI preview smoke failed. Missing stages: '+($missingStages -join ', ')+'. Runtime errors: '+($runtimeErrors -join ' | '))}
