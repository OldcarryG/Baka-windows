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

$detection = $profiles.gameDetection
function New-TestProcess([string]$Name,[string]$Path,[bool]$Fullscreen=$false) { [pscustomobject]@{ ProcessName=$Name; Path=$Path; IsForegroundFullscreen=$Fullscreen } }
$steamGame = Resolve-BakaAnyGame -Processes @((New-TestProcess 'steam' 'C:\Program Files (x86)\Steam\steam.exe'),(New-TestProcess 'eldenring' 'D:\SteamLibrary\steamapps\common\ELDEN RING\Game\eldenring.exe')) -Detection $detection
if (-not $steamGame -or $steamGame.ProcessName -ne 'eldenring' -or $steamGame.Reason -ne 'GameLibrary') { throw 'A Steam library game was not detected.' }
$epicGame = Resolve-BakaAnyGame -Processes @((New-TestProcess 'FortniteClient-Win64-Shipping' 'C:\Program Files\Epic Games\Fortnite\FortniteGame\Binaries\Win64\FortniteClient-Win64-Shipping.exe')) -Detection $detection
if (-not $epicGame -or $epicGame.Reason -ne 'GameLibrary') { throw 'An Epic Games library game was not detected.' }
$helpers = Resolve-BakaAnyGame -Processes @((New-TestProcess 'UnityCrashHandler64' 'D:\SteamLibrary\steamapps\common\Game\UnityCrashHandler64.exe'),(New-TestProcess 'EpicGamesLauncher' 'C:\Program Files\Epic Games\Launcher\EpicGamesLauncher.exe'),(New-TestProcess 'steamwebhelper' 'C:\Program Files (x86)\Steam\bin\cef\steamwebhelper.exe')) -Detection $detection
if ($null -ne $helpers) { throw 'A launcher or crash helper was treated as a game.' }
$fullscreen = Resolve-BakaAnyGame -Processes @((New-TestProcess 'IndieGame' 'C:\Users\Player\Desktop\IndieGame\IndieGame.exe' $true)) -Detection $detection
if (-not $fullscreen -or $fullscreen.Reason -ne 'Fullscreen') { throw 'A fullscreen game outside a library was not detected.' }
$video = Resolve-BakaAnyGame -Processes @((New-TestProcess 'vlc' 'C:\Program Files\VideoLAN\VLC\vlc.exe' $true),(New-TestProcess 'msedge' 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' $true)) -Detection $detection
if ($null -ne $video) { throw 'A fullscreen video player or browser was treated as a game.' }
$excludedAny = Resolve-BakaAnyGame -Processes @((New-TestProcess 'VALORANT-Win64-Shipping' 'C:\Riot Games\VALORANT\live\ShooterGame\Binaries\Win64\VALORANT-Win64-Shipping.exe' $true)) -Detection $detection
if ($null -ne $excludedAny) { throw 'An excluded game was detected by the all-games resolver.' }
$named = Resolve-BakaAnyGame -Processes @((New-TestProcess 'cs2' $null)) -Detection $detection
if (-not $named -or $named.Reason -ne 'Named') { throw 'Named detection did not take priority.' }

Write-Output 'Game detection checks passed: CS2, TF2, case-insensitivity, VALORANT exclusion, Steam/Epic library games, fullscreen games, launcher/helper and video-player rejection.'
