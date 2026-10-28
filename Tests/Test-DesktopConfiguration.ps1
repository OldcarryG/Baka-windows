[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Modules\DesktopConfiguration.psm1') -Force
$testRoot=Join-Path $env:TEMP ('BAKA-ConfigTests-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force|Out-Null
$passed=[System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
try {
    $defaultPath=Join-Path $root 'Config\DesktopSettings.default.json'
    $path=Join-Path $testRoot 'desktop-settings.json'
    $config=Read-BakaDesktopConfiguration -Path $path -DefaultPath $defaultPath
    Assert-True ((Test-BakaDesktopConfiguration $config).Valid) 'Fresh defaults did not validate.'
    Assert-True ((Test-Path $path) -and $config.Dock.Magnification -and @($config.Widgets.Items).Count -ge 3) 'Fresh defaults were not persisted with the expected visual options.'
    $passed.Add('First-run configuration is validated and created from reviewed defaults.')

    $config.Appearance.AccentColor='#8765C2'
    Save-BakaDesktopConfiguration -Path $path -Configuration $config|Out-Null
    $config.Appearance.AccentColor='#AFA3D1'
    Save-BakaDesktopConfiguration -Path $path -Configuration $config|Out-Null
    Assert-True (Test-Path ($path+'.bak')) 'Saving did not retain a previous-settings backup.'
    Set-Content -LiteralPath $path -Value '{ malformed' -Encoding UTF8
    $recovered=Read-BakaDesktopConfiguration -Path $path -DefaultPath $defaultPath
    Assert-True ($recovered.Appearance.AccentColor -eq '#8765C2') 'Malformed primary config did not recover the prior valid backup.'
    Assert-True ((Get-Content $path -Raw|ConvertFrom-Json).Appearance.AccentColor -eq '#8765C2') 'Recovered configuration was not restored to the primary file.'
    $passed.Add('Malformed settings recover from the previous valid backup and preserve the invalid file.')

    $bad=Get-BakaDefaultDesktopConfiguration
    $bad.Dock.IconSize=1000
    $invalidRejected=$false
    try { Save-BakaDesktopConfiguration -Path $path -Configuration $bad|Out-Null } catch { $invalidRejected=$true }
    Assert-True $invalidRejected 'Out-of-range settings were accepted for saving.'
    $passed.Add('Invalid appearance values are rejected before persistence.')

    $export=Join-Path $testRoot 'export.json'
    Export-BakaDesktopConfiguration -Path $export -Configuration $recovered|Out-Null
    $importPath=Join-Path $testRoot 'imported.json'
    $imported=Import-BakaDesktopConfiguration -Path $export -DestinationPath $importPath
    Assert-True ($imported.Appearance.AccentColor -eq '#8765C2') 'Validated export/import did not preserve settings.'
    $passed.Add('Settings export and import preserve valid user preferences.')

    $legacyPath=Join-Path $testRoot 'legacy.json'
    $legacy=Get-Content -LiteralPath $defaultPath -Raw|ConvertFrom-Json
    $legacy.PSObject.Properties.Remove('wallpaper');$legacy.PSObject.Properties.Remove('taskbar')
    foreach($app in @($legacy.pinnedApps)){$app.PSObject.Properties.Remove('iconPath')}
    [IO.File]::WriteAllText($legacyPath,($legacy|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($true))
    $upgraded=Read-BakaDesktopConfiguration -Path $legacyPath -DefaultPath $defaultPath
    Assert-True ($upgraded.Wallpaper.Mode -eq 'Image' -and [string]$upgraded.Wallpaper.Path -like '*BAKA-Stealth-4K.png' -and $upgraded.Taskbar.AutoHideWindowsTaskbar -eq $true -and @($upgraded.PinnedApps|Where-Object {$null -eq $_.PSObject.Properties['IconPath']}).Count -eq 0) 'Settings saved before wallpaper/taskbar support were not upgraded with defaults.'
    $passed.Add('Settings saved by earlier releases gain wallpaper, taskbar, and icon defaults without losing values.')

    $custom=Complete-BakaDesktopConfiguration (Get-BakaDefaultDesktopConfiguration)
    $custom.Wallpaper.Mode='Video';$custom.Wallpaper.Path='D:\Media\loop.mp4'
    Assert-True ((Test-BakaDesktopConfiguration $custom).Valid) 'A video wallpaper was rejected.'
    $custom.Wallpaper.Mode='Image';$custom.Wallpaper.Path='D:\Media\photo.webp'
    Assert-True ((Test-BakaDesktopConfiguration $custom).Valid) 'An image wallpaper was rejected.'
    $custom.Wallpaper.Path='D:\Media\loop.mp4'
    Assert-True (-not (Test-BakaDesktopConfiguration $custom).Valid) 'A video file was accepted as an image wallpaper.'
    $custom.Wallpaper.Mode='Color';$custom.Wallpaper.Color='blue'
    Assert-True (-not (Test-BakaDesktopConfiguration $custom).Valid) 'An invalid wallpaper color was accepted.'
    $custom.Wallpaper.Color='#101820';$custom.PinnedApps[0].IconPath='D:\Icons\browser.png'
    Assert-True ((Test-BakaDesktopConfiguration $custom).Valid) 'A custom dock icon was rejected.'
    $custom.PinnedApps[0].IconPath='D:\Icons\browser.exe'
    Assert-True (-not (Test-BakaDesktopConfiguration $custom).Valid) 'An executable was accepted as a dock icon image.'
    $passed.Add('Wallpaper image/video/color choices and custom dock icons are validated.')

    $passed|ForEach-Object { Write-Output ('PASS: '+$_) }
    Write-Output ('RESULT: {0}/{0} desktop-configuration regression checks passed.' -f $passed.Count)
} finally {
    $fullRoot=[IO.Path]::GetFullPath($testRoot)
    $tempRoot=[IO.Path]::GetFullPath($env:TEMP)
    if($fullRoot.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and $fullRoot -match 'BAKA-ConfigTests-[0-9a-f]{32}$') { Remove-Item -LiteralPath $fullRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
