$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$profiles = Get-Content -LiteralPath (Join-Path $root 'Config\PerformanceProfiles.json') -Raw | ConvertFrom-Json
Import-Module (Join-Path $root 'Modules\GamingProfiles\GamingProfiles.psm1') -Force

$cs2 = Resolve-BakaDetectedGame -RunningProcessNames @('powershell','CS2') -Definitions $profiles.gameDetection.processes
if (-not $cs2 -or $cs2.DisplayName -ne 'CS2' -or $cs2.ProcessName -ne 'cs2') { throw 'CS2 process detection failed.' }

$tf2 = Resolve-BakaDetectedGame -RunningProcessNames @('TF_WIN64') -Definitions $profiles.gameDetection.processes
if (-not $tf2 -or $tf2.DisplayName -ne 'TF2' -or $tf2.ProcessName -ne 'tf_win64') { throw 'Team Fortress 2 process detection failed.' }

$unrelated = Resolve-BakaDetectedGame -RunningProcessNames @('VALORANT-Win64-Shipping') -Definitions $profiles.gameDetection.processes
if ($null -ne $unrelated) { throw 'An excluded game was detected.' }

Write-Output 'Game detection checks passed: CS2, TF2, case-insensitivity, and VALORANT exclusion.'
