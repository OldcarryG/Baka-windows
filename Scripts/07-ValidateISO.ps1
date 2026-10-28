[CmdletBinding()]
param([string]$IsoPath)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Modules\BAKA.Common.psm1') -Force
$base = Import-BakaJson -Path (Join-Path $root 'Config\BaseImage.json')
if (-not $IsoPath) { $IsoPath = Join-Path $root 'Output\BAKA-Windows-Gaming-Edition-26H2-x64.iso' }
if (-not (Test-Path -LiteralPath $IsoPath -PathType Leaf)) { throw "ISO not found: $IsoPath" }
$isoHash = Get-BakaSha256 -Path $IsoPath
$diskImage = $null
try {
    $diskImage = Mount-DiskImage -ImagePath (Resolve-Path -LiteralPath $IsoPath).Path -PassThru -Access ReadOnly
    $volume = Get-Volume -DiskImage $diskImage | Where-Object DriveLetter | Select-Object -First 1
    if (-not $volume) { throw 'ISO cannot be mounted as a readable filesystem.' }
    $media = "$($volume.DriveLetter):\"
    $required = @(
        'setup.exe','bootmgr','bootmgr.efi','sources\boot.wim','sources\install.wim',
        'sources\$OEM$\$$\Setup\Scripts\SetupComplete.cmd',
        'sources\$OEM$\$1\ProgramData\BAKA\Scripts\FirstLogon.ps1',
        'sources\$OEM$\$1\ProgramData\BAKA\Scripts\BakaCompanion.ps1',
        'sources\$OEM$\$1\ProgramData\BAKA\Scripts\Apply-FirstLogonSystemSetup.ps1',
        'sources\$OEM$\$1\ProgramData\BAKA\Modules\GamingProfiles.psm1',
        'sources\$OEM$\$1\ProgramData\BAKA\Modules\DesktopConfiguration.psm1',
        'sources\$OEM$\$1\ProgramData\BAKA\Modules\CompanionInstance.psm1',
        'sources\$OEM$\$1\ProgramData\BAKA\Modules\SystemMonitoring.psm1',
        'sources\$OEM$\$1\ProgramData\BAKA\Modules\UpdateControl.psm1',
        'sources\$OEM$\$1\ProgramData\BAKA\Modules\DesktopShell.psm1',
        'sources\$OEM$\$1\ProgramData\BAKA\Modules\PowerPlan.psm1',
        'sources\$OEM$\$1\ProgramData\BAKA\Scripts\BakaShell.exe',
        'sources\$OEM$\$1\ProgramData\BAKA\Assets\BAKA-Stealth-4K.png',
        'sources\$OEM$\$1\ProgramData\BAKA\Modules\SystemTuning.psm1',
        'sources\$OEM$\$1\ProgramData\BAKA\Scripts\Restore-SystemTuning.ps1',
        'sources\$OEM$\$1\ProgramData\BAKA\Scripts\Enable-AutoSignIn.ps1',
        'sources\$OEM$\$1\ProgramData\BAKA\SystemTuning.json',
        'sources\$OEM$\$1\ProgramData\BAKA\GamePerformance.json',
        'sources\$OEM$\$1\ProgramData\BAKA\Debloat.json',
        'sources\$OEM$\$1\ProgramData\BAKA\AccountSetup.json',
        'sources\$OEM$\$1\ProgramData\BAKA\DefaultAssociations.xml',
        'Autounattend.xml',
        'sources\$OEM$\$1\ProgramData\BAKA\DesktopSettings.default.json',
        'sources\$OEM$\$1\ProgramData\BAKA\DesktopThemes.json',
        'sources\$OEM$\$1\ProgramData\BAKA\PerformanceProfiles.json',
        'sources\$OEM$\$1\ProgramData\BAKA\Applications.json',
        'sources\$OEM$\$1\ProgramData\BAKA\Assets\BAKA-Liquid-Ribbon.png',
        'sources\$OEM$\$1\ProgramData\BAKA\Assets\BAKA-BlackGlass-4K.png'
    )
    foreach ($relative in $required) { if (-not (Test-Path -LiteralPath (Join-Path $media $relative) -PathType Leaf)) { throw "ISO is missing required file: $relative" } }
    $setupSignature = Get-AuthenticodeSignature -LiteralPath (Join-Path $media 'setup.exe')
    if ($setupSignature.Status -ne 'Valid' -or $setupSignature.SignerCertificate.Subject -notmatch 'Microsoft') { throw "ISO setup.exe does not have a valid Microsoft signature (status $($setupSignature.Status))." }
    $setupSignatureStatus = $setupSignature.Status.ToString()
    Import-Module Dism -ErrorAction Stop
    $imagePath = Join-Path $media 'sources\install.wim'
    $imageIndexes = @(Get-WindowsImage -ImagePath $imagePath)
    $images = @($imageIndexes | ForEach-Object { Get-WindowsImage -ImagePath $imagePath -Index $_.ImageIndex })
    if ($images.Count -ne 1 -or $images[0].EditionId -ne 'Professional') { throw 'ISO must contain exactly one Windows 11 Pro image.' }
    if ($images[0].Version -ne $base.latestKnownServicing.build) { throw "ISO image build $($images[0].Version) does not match the pinned serviced build $($base.latestKnownServicing.build)." }
    $browser = Join-Path $media 'sources\$OEM$\$1\ProgramData\BAKA\Apps\BakaBrowser-win-Setup-1.2.0.exe'
    $browserHash = if (Test-Path -LiteralPath $browser) { Get-BakaSha256 -Path $browser } else { $null }
    if ($browserHash -ne 'E381B835A0607EE2006A9A89588161DA2125518398AEBDB8FFE0CCFB1C342488') { throw 'Pinned Baka Browser package is missing or has a hash mismatch.' }
    $gameTestScope = [pscustomobject]@{ CS2='Not run'; TeamFortress2='Not run'; VALORANT='Excluded by user instruction' }
    $result = [pscustomobject]@{ ValidatedAt=(Get-Date).ToString('o'); IsoPath=(Resolve-Path -LiteralPath $IsoPath).Path; Sha256=$isoHash; SetupSignature=$setupSignatureStatus; Edition=$images[0].ImageName; ImageBuild=$images[0].Version; BrowserPackageSha256=$browserHash; StructuralChecks='Passed'; VmBootTest='Not run'; PhysicalInstallTest='Not run'; GameTestScope=$gameTestScope }
    $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $root 'Logs\ISO-Validation.json') -Encoding UTF8
    $result
} finally {
    if ($diskImage) { Dismount-DiskImage -ImagePath (Resolve-Path -LiteralPath $IsoPath).Path -ErrorAction SilentlyContinue | Out-Null }
}
