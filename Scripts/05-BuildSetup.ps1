[CmdletBinding()]
param([string]$BuildRoot)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Modules\BAKA.Common.psm1') -Force
if (-not $BuildRoot) { $BuildRoot = Join-Path $root 'Work\CurrentBuild' }
$BuildRoot = [IO.Path]::GetFullPath($BuildRoot)
if (-not (Test-BakaPathWithinRoot -Path $BuildRoot -Root (Join-Path $root 'Work'))) { throw 'BuildRoot must be inside this project Work directory.' }
$media = Join-Path $BuildRoot 'Media'
$image = Join-Path $media 'sources\install.wim'
if (-not (Test-Path -LiteralPath $image -PathType Leaf)) { throw "Prepared Pro image not found: $image" }
$answerTemplate=Join-Path $root 'Config\Autounattend.template.xml'
if(-not(Test-Path -LiteralPath $answerTemplate -PathType Leaf)){throw 'Unattend template is missing.'}
Copy-Item -LiteralPath $answerTemplate -Destination (Join-Path $media 'Autounattend.xml') -Force
$applications = Import-BakaJson -Path (Join-Path $root 'Config\Applications.json')
$oemRoot = Join-Path $media 'sources\$OEM$'
$targetRoot = Join-Path $oemRoot '$1\ProgramData\BAKA'
$targetScripts = Join-Path $targetRoot 'Scripts'
$targetModules = Join-Path $targetRoot 'Modules'
$targetApps = Join-Path $targetRoot 'Apps'
$targetAssets = Join-Path $targetRoot 'Assets'
foreach ($dir in @($targetScripts,$targetModules,$targetApps,$targetAssets)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$wallpapers = @(
    @{ Source = (Join-Path $root 'Assets\Wallpapers\BAKA-BlackGlass-4K.png'); Name = 'BAKA-BlackGlass-4K.png' },
    @{ Source = (Join-Path $root 'Assets\Wallpapers\BAKA-Liquid-Ribbon.png'); Name = 'BAKA-Liquid-Ribbon.png' }
)
foreach ($wallpaper in $wallpapers) {
    if (-not (Test-Path -LiteralPath $wallpaper.Source -PathType Leaf)) { throw "Required BAKA wallpaper is missing: $($wallpaper.Source)" }
    Copy-Item -LiteralPath $wallpaper.Source -Destination (Join-Path $targetAssets $wallpaper.Name) -Force
}
$runtimeFiles = @('Install-SelectedApps.ps1','Install-SelectedDrivers.ps1','Restore-WindowsUpdate.ps1','Set-GamingProfile.ps1','BakaCompanion.ps1','FirstLogon.ps1','SetupComplete.ps1','Register-FirstLogonTask.ps1','Apply-FirstLogonSystemSetup.ps1','Restore-SystemTuning.ps1','Measure-Benchmark.ps1')
foreach ($file in $runtimeFiles) {
    $source = Join-Path $PSScriptRoot "Runtime\$file"
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Runtime script missing: $source" }
    Copy-Item -LiteralPath $source -Destination (Join-Path $targetScripts $file) -Force
}
foreach ($modulePath in @('UpdateControl\UpdateControl.psm1','GamingProfiles\GamingProfiles.psm1','Recovery\Recovery.psm1','HardwareDetection\HardwareDetection.psm1','DesktopConfiguration.psm1','DesktopShell.psm1','SystemTuning.psm1','CompanionInstance.psm1','SystemMonitoring.psm1')) {
    $source = Join-Path $root "Modules\$modulePath"
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Runtime module missing: $source" }
    $destination = Join-Path $targetModules (Split-Path -Leaf $modulePath)
    Copy-Item -LiteralPath $source -Destination $destination -Force
}
$appConfigPath = Join-Path $root 'Config\Applications.json'
Copy-Item -LiteralPath $appConfigPath -Destination (Join-Path $targetRoot 'Applications.json') -Force
Copy-Item -LiteralPath (Join-Path $root 'Config\PrivacySettings.json') -Destination (Join-Path $targetRoot 'PrivacySettings.json') -Force
Copy-Item -LiteralPath (Join-Path $root 'Config\Drivers.json') -Destination (Join-Path $targetRoot 'Drivers.json') -Force
Copy-Item -LiteralPath (Join-Path $root 'Config\PerformanceProfiles.json') -Destination (Join-Path $targetRoot 'PerformanceProfiles.json') -Force
Copy-Item -LiteralPath (Join-Path $root 'Config\DesktopSettings.default.json') -Destination (Join-Path $targetRoot 'DesktopSettings.default.json') -Force
Copy-Item -LiteralPath (Join-Path $root 'Config\DesktopThemes.json') -Destination (Join-Path $targetRoot 'DesktopThemes.json') -Force
foreach ($runtimeConfig in @('SystemTuning.json','GamePerformance.json','Debloat.json','AccountSetup.json','DefaultAssociations.xml')) {
    Copy-Item -LiteralPath (Join-Path $root "Config\$runtimeConfig") -Destination (Join-Path $targetRoot $runtimeConfig) -Force
}
foreach ($app in @($applications.applications | Where-Object selected)) {
    if (-not $app.relativePath -or -not $app.sha256) { throw "Selected app '$($app.id)' must have an on-disk package and SHA-256." }
    $package = Join-Path $root ($app.relativePath -replace '/', '\')
    if (-not (Test-Path -LiteralPath $package -PathType Leaf)) { throw "Selected app package missing: $package" }
    if ((Get-BakaSha256 -Path $package) -ne ([string]$app.sha256).ToUpperInvariant()) { throw "Selected app package SHA-256 mismatch: $package" }
    Copy-Item -LiteralPath $package -Destination (Join-Path $targetApps (Split-Path -Leaf $package)) -Force
}
$setupScriptPath = Join-Path $PSScriptRoot 'Runtime\SetupComplete.ps1'
Copy-Item -LiteralPath $setupScriptPath -Destination (Join-Path $targetScripts 'SetupComplete.ps1') -Force
$setupCmd = Join-Path $oemRoot '$$\Setup\Scripts\SetupComplete.cmd'
New-Item -ItemType Directory -Path (Split-Path -Parent $setupCmd) -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Runtime\SetupComplete.cmd') -Destination $setupCmd -Force
$contextPath = Join-Path $BuildRoot 'build-context.json'
$context = Get-Content -LiteralPath $contextPath -Raw | ConvertFrom-Json
$context | Add-Member -NotePropertyName SetupCustomizedAt -NotePropertyValue (Get-Date).ToString('o') -Force
$context | Add-Member -NotePropertyName SelectedApplications -NotePropertyValue @($applications.applications | Where-Object selected | ForEach-Object id) -Force
$context | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $contextPath -Encoding UTF8
Write-BakaLog -Message 'SetupComplete, reversible update-control restoration shortcut, and selected app staging configured.'
