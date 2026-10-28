[CmdletBinding()]
param([int]$TimeoutSeconds=120)
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
    [pscustomobject]@{Name='manual profiles stop automatic process polling';Pattern='if\(\$script:manualOverride\)\{Update-BakaProfileStatus;return\}' },
    [pscustomobject]@{Name='BAKA Files workspace is implemented';Pattern='function New-BakaFileExplorer'},
    [pscustomobject]@{Name='video wallpaper is hosted behind desktop icons';Pattern='Set-BakaWindowAsWallpaper'},
    [pscustomobject]@{Name='native taskbar auto-hide is restored on exit';Pattern='Restore-BakaTaskbarMode'},
    [pscustomobject]@{Name='video wallpaper pauses during games';Pattern='function Update-BakaVideoWallpaperPlayback'},
    [pscustomobject]@{Name='Windows taskbar is fully hidden, not only auto-hidden';Pattern='Set-BakaTaskbarVisibility -Visible \$false'},
    [pscustomobject]@{Name='menu bar and dock reserve their screen edges';Pattern='Register-BakaAppBar -Handle \$handle -Edge Top'},
    [pscustomobject]@{Name='app bars are released on exit';Pattern='Remove-BakaTopBarReservation'},
    [pscustomobject]@{Name='BAKA windows are per-pixel transparent';Pattern='\$window\.AllowsTransparency=\$true'},
    [pscustomobject]@{Name='preview never changes the real power plan';Pattern="power-plan-preview"},
    [pscustomobject]@{Name='shell mode draws its own desktop';Pattern='function New-BakaDesktopWindow'},
    [pscustomobject]@{Name='shell mode starts Run-key and Startup apps once per session';Pattern='function Invoke-BakaStartupApps'},
    [pscustomobject]@{Name='Windows key opens the BAKA launcher in shell mode';Pattern='\[BakaShellKeys\]::Install\(\)'},
    [pscustomobject]@{Name='Ctrl+Alt+Shift+E recovery hotkey restores Explorer';Pattern='RegisterHotKey\(\$source\.Handle,0xBA6A,7,0x45\)'},
    [pscustomobject]@{Name='exiting the shell hands the session back to Explorer';Pattern='if\(\$script:shellMode\)\{Restore-BakaWindowsShell -Quiet;return\}'},
    [pscustomobject]@{Name='preview never changes the real shell';Pattern='shell-restore-preview'},
    [pscustomobject]@{Name='Arena is built on first use, not at startup';Pattern='\$script:windows\.Dashboard=\$null'},
    [pscustomobject]@{Name='desktop memory is trimmed after startup and at game start';Pattern="Optimize-BakaFootprint 'game-start'"},
    [pscustomobject]@{Name='desktop drops below normal priority during games';Pattern='ProcessPriorityClass\]::BelowNormal'},
    [pscustomobject]@{Name='foreground app lookup only runs when the window changes';Pattern='\$script:lastForegroundWindow=\$foreground'},
    [pscustomobject]@{Name='the Windows shell is the windowless launcher, never powershell.exe';Pattern="Scripts\\BakaShell\.exe"},
    [pscustomobject]@{Name='a rejected second launch exits with code 3 for the launcher';Pattern="second-launch-rejected';exit 3"}
)
$launcherSource=Get-Content -LiteralPath (Join-Path $root 'Scripts\Runtime\BakaShell.cs') -Raw
foreach($needle in @('CreateNoWindow = true','UseShellExecute = false','failures.Count >= 3','StartExplorer("repeated-failures")','code == 3')){if(-not $launcherSource.Contains($needle)){throw "BAKA shell launcher guard failed: $needle"}}
$firstLogonSource=Get-Content -LiteralPath (Join-Path $root 'Scripts\Runtime\FirstLogon.ps1') -Raw
if($firstLogonSource -match "Name 'Shell'[^\r\n]*powershell" -or $firstLogonSource -notmatch "shellCommand = '`"\{0\}`"' -f \`$shellLauncher"){throw 'First logon must register the native launcher as the shell.'}
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
$requiredStages=@('ui-smoke-stage=surfaces-visible','ui-smoke-stage=liquid-glass-motion','ui-smoke-stage=glass-surface-coverage','ui-smoke-stage=liquid-glass-desktop','ui-smoke-stage=window-chrome','ui-smoke-stage=control-center','ui-smoke-stage=menu-bar','ui-animation=dock-launch-bounce','variant=glide','ui-animation=liquid-glint','ui-animation=dock-wave','ui-smoke-stage=gaming-profile','ui-smoke-stage=gaming-profile-motion-suppressed','ui-smoke-stage=benchmark-profile','ui-smoke-stage=benchmark-profile-motion-suppressed','ui-smoke-stage=desktop-restore-and-themes','ui-smoke-stage=widget-and-settings-check','ui-smoke-stage=wallpaper-and-taskbar','wallpaper-preview mode=Image','taskbar-preview autoHide=','ui-smoke-stage=files-surface','ui-smoke-stage=files-close','ui-smoke-stage=launchpad','ui-smoke-passed metricsCaptured=true','companion-exit-cleanup-complete')
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
