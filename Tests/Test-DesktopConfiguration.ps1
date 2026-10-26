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

    $passed|ForEach-Object { Write-Output ('PASS: '+$_) }
    Write-Output ('RESULT: {0}/{0} desktop-configuration regression checks passed.' -f $passed.Count)
} finally {
    $fullRoot=[IO.Path]::GetFullPath($testRoot)
    $tempRoot=[IO.Path]::GetFullPath($env:TEMP)
    if($fullRoot.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and $fullRoot -match 'BAKA-ConfigTests-[0-9a-f]{32}$') { Remove-Item -LiteralPath $fullRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
