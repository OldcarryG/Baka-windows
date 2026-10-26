[CmdletBinding()]
param([string]$SourceIso,[string]$BuildRoot)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Modules\BAKA.Common.psm1') -Force
Assert-BakaAdministrator
& (Join-Path $PSScriptRoot '00-CheckBuildHost.ps1')
$verified = & (Join-Path $PSScriptRoot '01-VerifySource.ps1') -SourceIso $SourceIso
$sourcePath = $verified.SourceIso
$buildRoot = if($BuildRoot){[IO.Path]::GetFullPath($BuildRoot)}else{Join-Path $root 'Work\CurrentBuild'}
if (-not (Test-BakaPathWithinRoot -Path $buildRoot -Root (Join-Path $root 'Work'))) { throw 'BuildRoot must be inside this project Work directory.' }
if (Test-Path -LiteralPath $buildRoot) { throw "Build workspace already exists: $buildRoot. Review it or use 90-Cleanup.ps1 with its explicit confirmation before starting again." }
$mediaRoot = Join-Path $buildRoot 'Media'
New-Item -ItemType Directory -Path $mediaRoot -Force | Out-Null
$diskImage = $null
try {
    $diskImage = Mount-DiskImage -ImagePath $sourcePath -PassThru -Access ReadOnly
    $volume = Get-Volume -DiskImage $diskImage | Where-Object DriveLetter | Select-Object -First 1
    if (-not $volume) { throw 'Mounted ISO has no readable drive volume.' }
    $from = "$($volume.DriveLetter):\"
    & robocopy.exe $from $mediaRoot /E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /NFL /NDL /NP
    if ($LASTEXITCODE -ge 8) { throw "Robocopy failed with exit code $LASTEXITCODE." }
    $copiedImages = @('install.wim','install.esd') | ForEach-Object { Join-Path $mediaRoot "sources\$_" } | Where-Object { Test-Path -LiteralPath $_ }
    if ($copiedImages.Count -ne 1) { throw 'Expected one copied install.wim or install.esd.' }
    Import-Module Dism -ErrorAction Stop
    # 01-VerifySource.ps1 mounts and then dismounts its ISO, so its recorded
    # ImagePath may refer to a drive letter that is no longer mounted here.
    # Resolve install.wim from this stage's active read-only ISO mount instead.
    $sourceImagePath = Join-Path $from 'sources\install.wim'
    if (-not (Test-Path -LiteralPath $sourceImagePath -PathType Leaf)) { throw "Source install.wim not found in the active ISO mount: $sourceImagePath" }
    $exportPath = Join-Path $mediaRoot 'sources\install-pro.wim'
    Export-WindowsImage -SourceImagePath $sourceImagePath -SourceIndex $verified.ImageIndex -DestinationImagePath $exportPath -CompressionType Max -CheckIntegrity | Out-Null
    $exported = @(Get-WindowsImage -ImagePath $exportPath -Index 1)
    if ($exported.Count -ne 1 -or $exported[0].EditionId -ne 'Professional') { throw 'Exported Pro image failed its edition check.' }
    foreach ($copied in $copiedImages) { Remove-Item -LiteralPath $copied -Force }
    Move-Item -LiteralPath $exportPath -Destination (Join-Path $mediaRoot 'sources\install.wim')
    $context = [pscustomobject]@{ CreatedAt=(Get-Date).ToString('o'); SourceIso=$sourcePath; SourceSha256=$verified.Sha256; ImageName=$exported[0].ImageName; EditionId=$exported[0].EditionId; Architecture=$exported[0].Architecture; ImageVersion=$exported[0].Version }
    $context | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $buildRoot 'build-context.json') -Encoding UTF8
    Write-BakaLog -Message "Prepared one-image Pro media in $mediaRoot; source hash $($verified.Sha256)."
    $context
} catch {
    Write-BakaLog -Level ERROR -Message $_.Exception.Message
    throw
} finally {
    if ($diskImage) { Dismount-DiskImage -ImagePath $sourcePath -ErrorAction SilentlyContinue | Out-Null }
}
