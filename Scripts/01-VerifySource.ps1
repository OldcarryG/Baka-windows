[CmdletBinding()]
param([string]$SourceIso)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Modules\BAKA.Common.psm1') -Force
$base = Import-BakaJson -Path (Join-Path $root 'Config\BaseImage.json')
if (-not $SourceIso) { $SourceIso = Join-Path $root ($base.sourceIsoRelativePath -replace '/', '\') }
if (-not (Test-Path -LiteralPath $SourceIso -PathType Leaf)) { throw "Official Windows ISO not found: $SourceIso" }
if (-not $base.requireSourceSha256 -or [string]::IsNullOrWhiteSpace([string]$base.sourceSha256)) {
    throw 'SourceSha256 is unset. Verify the ISO against Microsoft-published release information, then pin its SHA-256 in Config/BaseImage.json.'
}
$actualHash = Get-BakaSha256 -Path $SourceIso
if ($actualHash -ne ([string]$base.sourceSha256).ToUpperInvariant()) { throw "Source SHA-256 mismatch. Expected $($base.sourceSha256); received $actualHash." }
$diskImage = $null
try {
    $diskImage = Mount-DiskImage -ImagePath (Resolve-Path -LiteralPath $SourceIso).Path -PassThru -Access ReadOnly
    $volume = Get-Volume -DiskImage $diskImage | Where-Object DriveLetter | Select-Object -First 1
    if (-not $volume) { throw 'Mounted ISO has no readable drive volume.' }
    $mediaRoot = "$($volume.DriveLetter):\"
    $setupPath = Join-Path $mediaRoot 'setup.exe'
    if (-not (Test-Path -LiteralPath $setupPath)) { throw 'ISO does not contain root setup.exe.' }
    $signature = Get-AuthenticodeSignature -LiteralPath $setupPath
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft') {
        throw "Windows setup signature is not valid Microsoft code (status: $($signature.Status))."
    }
    $imagePath = @('install.wim','install.esd','install.swm') | ForEach-Object { Join-Path $mediaRoot "sources\$_" } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $imagePath -or $imagePath.EndsWith('.swm',[StringComparison]::OrdinalIgnoreCase)) { throw 'Expected sources\install.wim or install.esd; split SWM images require separate review.' }
    Import-Module Dism -ErrorAction Stop
    # DISM on older supported host builds can return only summary fields when
    # enumerating an entire WIM. Query each index explicitly for full metadata.
    $imageIndexes = @(Get-WindowsImage -ImagePath $imagePath)
    $images = @($imageIndexes | ForEach-Object { Get-WindowsImage -ImagePath $imagePath -Index $_.ImageIndex })
    $pro = @($images | Where-Object { $_.EditionId -eq $base.expectedEditionId -and $_.ImageName -match 'Windows 11 Pro' })
    if ($pro.Count -ne 1) { throw "Expected exactly one Windows 11 Pro image (EditionId '$($base.expectedEditionId)'), found $($pro.Count)." }
    if ($pro[0].Architecture -notin @(9,'x64','amd64')) { throw "The selected image is not x64 (architecture: $($pro[0].Architecture))." }
    if ($base.sourceBuild -and [string]$pro[0].Version -ne [string]$base.sourceBuild) { throw "Source build mismatch. Expected $($base.sourceBuild); received $($pro[0].Version)." }
    if ($base.expectedLanguage -and @($pro[0].Languages) -notcontains [string]$base.expectedLanguage) { throw "Expected image language '$($base.expectedLanguage)' was not present." }
    $record = [pscustomobject]@{
        VerifiedAt=(Get-Date).ToString('o'); SourceIso=(Resolve-Path -LiteralPath $SourceIso).Path
        Sha256=$actualHash; ImagePath=$imagePath; ImageIndex=$pro[0].ImageIndex
        ImageName=$pro[0].ImageName; EditionId=$pro[0].EditionId; Architecture=$pro[0].Architecture
        Version=$pro[0].Version; Languages=@($pro[0].Languages); SetupSignature=$signature.Status; SetupSigner=$signature.SignerCertificate.Subject
    }
    $logRoot = Join-Path $root 'Logs'
    if (-not (Test-Path -LiteralPath $logRoot)) { New-Item -ItemType Directory -Path $logRoot -Force | Out-Null }
    $record | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $logRoot 'VerifiedSource.json') -Encoding UTF8
    $record
} finally {
    if ($diskImage) { Dismount-DiskImage -ImagePath (Resolve-Path -LiteralPath $SourceIso).Path -ErrorAction SilentlyContinue | Out-Null }
}
