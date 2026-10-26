[CmdletBinding()]
param([string]$ReportPath)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Modules\BAKA.Common.psm1') -Force
$config = Import-BakaJson -Path (Join-Path $root 'Config\BaseImage.json')
$os = Get-CimInstance Win32_OperatingSystem
$isWindows11 = ($os.Caption -match 'Windows 11') -and ([version]$os.Version -ge [version]'10.0.22000')
$is64Bit = [Environment]::Is64BitOperatingSystem
$isElevated = Test-BakaAdministrator
$requiredAdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Assessment and Deployment Kit'
$oscdimg = Join-Path $requiredAdkRoot 'Deployment Tools\amd64\Oscdimg\oscdimg.exe'
$winPeMake = Join-Path $requiredAdkRoot 'Windows Preinstallation Environment\MakeWinPEMedia.cmd'
$wsimCandidates = @(
    (Join-Path $requiredAdkRoot 'Deployment Tools\WSIM\amd64\imgmgr.exe'),
    (Join-Path $requiredAdkRoot 'Deployment Tools\WSIM\imgmgr.exe')
)
$wsim = $wsimCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$dism = Join-Path $env:WINDIR 'System32\Dism.exe'
$volumeRoot = [IO.Path]::GetPathRoot($root)
$driveId = $volumeRoot.TrimEnd('\')
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$driveId'"
$freeGiB = if ($disk) { [math]::Round($disk.FreeSpace / 1GB, 1) } else { 0 }
$checks = @(
    [pscustomobject]@{ Name='Windows 11 technician host'; Passed=$isWindows11; Detail="$($os.Caption), build $($os.BuildNumber)" },
    [pscustomobject]@{ Name='64-bit Windows'; Passed=$is64Bit; Detail=$os.OSArchitecture },
    [pscustomobject]@{ Name='Elevated session'; Passed=$isElevated; Detail='DISM servicing requires administrator rights.' },
    [pscustomobject]@{ Name='DISM'; Passed=(Test-Path -LiteralPath $dism); Detail=$dism },
    [pscustomobject]@{ Name='OSCDIMG'; Passed=(Test-Path -LiteralPath $oscdimg); Detail=$oscdimg },
    [pscustomobject]@{ Name='Windows PE add-on'; Passed=(Test-Path -LiteralPath $winPeMake); Detail=$winPeMake },
    [pscustomobject]@{ Name='Windows System Image Manager'; Passed=(Test-Path -LiteralPath $wsim); Detail=$wsim },
    [pscustomobject]@{ Name='Free space'; Passed=($freeGiB -ge [double]$config.minimumFreeSpaceGiB); Detail="$freeGiB GiB free; $($config.minimumFreeSpaceGiB) GiB required." }
)
$result = [pscustomobject]@{
    CapturedAt=(Get-Date).ToString('o')
    Host=[pscustomobject]@{ OS=$os.Caption; Version=$os.Version; Build=$os.BuildNumber; Architecture=$os.OSArchitecture; FreeSpaceGiB=$freeGiB }
    Checks=$checks
    Passed=(@($checks | Where-Object { -not $_.Passed }).Count -eq 0)
}
if (-not $ReportPath) { $ReportPath = Join-Path $root ("Logs\BuildHost-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date)) }
$parent = Split-Path -Parent $ReportPath
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
$checks | Format-Table Name,Passed,Detail -AutoSize
Write-Host "Report: $ReportPath"
if (-not $result.Passed) { throw 'Build-host preflight failed. Resolve the listed checks before servicing an image.' }
