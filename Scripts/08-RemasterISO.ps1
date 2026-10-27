[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceIso,
    [Parameter(Mandatory)][string]$SourceSha256,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$BuildRoot
)
# Refreshes an already serviced, structurally validated BAKA ISO with the current answer file and
# ProgramData\BAKA runtime payload. install.wim, boot.wim, and servicing are reused unchanged, so this
# runs on any Windows host with the ADK Deployment Tools (OSCDIMG). Approved app removals that are newer
# than the reused image are applied online at first logon by Apply-FirstLogonSystemSetup.ps1.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Modules\BAKA.Common.psm1') -Force
Assert-BakaAdministrator
$SourceIso=(Resolve-Path -LiteralPath $SourceIso).ProviderPath
if((Get-BakaSha256 -Path $SourceIso) -ne $SourceSha256.ToUpperInvariant()){throw "Source ISO hash does not match the pinned value: $SourceIso"}
if(-not $BuildRoot){$BuildRoot=Join-Path $root ('Work\Remaster-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))}
$BuildRoot=[IO.Path]::GetFullPath($BuildRoot)
if(-not (Test-BakaPathWithinRoot -Path $BuildRoot -Root (Join-Path $root 'Work'))){throw 'BuildRoot must be inside this project Work directory.'}
if(Test-Path -LiteralPath $BuildRoot){throw "Refusing to reuse an existing remaster workspace: $BuildRoot"}
$OutputPath=[IO.Path]::GetFullPath($OutputPath)
if(Test-Path -LiteralPath $OutputPath){throw "Refusing to overwrite existing ISO: $OutputPath"}
$media=Join-Path $BuildRoot 'Media'
New-Item -ItemType Directory -Path $media -Force|Out-Null
$diskImage=$null
try{
    $diskImage=Mount-DiskImage -ImagePath $SourceIso -PassThru -Access ReadOnly
    $letter=(Get-Volume -DiskImage $diskImage|Where-Object DriveLetter|Select-Object -First 1).DriveLetter
    if(-not $letter){throw 'Source ISO did not mount with a drive letter.'}
    Write-BakaLog -Message "Copying $SourceIso media to $media."
    & robocopy.exe "$($letter):\" $media /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP|Out-Null
    if($LASTEXITCODE -ge 8){throw "robocopy failed with exit code $LASTEXITCODE."}
}finally{if($diskImage){Dismount-DiskImage -ImagePath $SourceIso|Out-Null}}
Get-ChildItem -LiteralPath $media -Recurse -File|ForEach-Object {if($_.IsReadOnly){$_.IsReadOnly=$false}}
$oldPayload=Join-Path $media 'sources\$OEM$'
if(Test-Path -LiteralPath $oldPayload){Remove-Item -LiteralPath $oldPayload -Recurse -Force}
[pscustomobject]@{RemasteredFrom=$SourceIso;SourceSha256=$SourceSha256.ToUpperInvariant();RemasterStartedAt=(Get-Date).ToString('o');InstallWim='Reused unchanged from source ISO'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $BuildRoot 'build-context.json') -Encoding UTF8
& (Join-Path $PSScriptRoot '05-BuildSetup.ps1') -BuildRoot $BuildRoot
& (Join-Path $PSScriptRoot '06-BuildISO.ps1') -BuildRoot $BuildRoot -OutputPath $OutputPath
