[CmdletBinding()]
param(
    [string]$SourceIso,
    [string]$BuildRoot,
    [string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Modules\BAKA.Common.psm1') -Force
if (-not $BuildRoot) { $BuildRoot = Join-Path $root 'Work\ReleaseBuild-20261024' }
if (-not $OutputPath) { $OutputPath = Join-Path $root 'Output\BAKA-Windows-Gaming-Edition-26H2-x64-BakaLiquid-RC-20261024.iso' }
$BuildRoot=[IO.Path]::GetFullPath($BuildRoot)
$OutputPath=[IO.Path]::GetFullPath($OutputPath)
if (-not (Test-BakaPathWithinRoot -Path $BuildRoot -Root (Join-Path $root 'Work'))) { throw 'BuildRoot must be inside this project Work directory.' }
if (-not (Test-BakaPathWithinRoot -Path $OutputPath -Root (Join-Path $root 'Output'))) { throw 'OutputPath must be inside the project Output directory.' }
if (Test-Path -LiteralPath $BuildRoot) { throw "Refusing to reuse an existing build workspace: $BuildRoot" }
if (Test-Path -LiteralPath $OutputPath) { throw "Refusing to overwrite existing ISO: $OutputPath" }
$stages = @(
    @{ Name='Prepare source and work media'; Path=Join-Path $PSScriptRoot '02-PrepareWorkspace.ps1'; Arguments=@{SourceIso=$SourceIso;BuildRoot=$BuildRoot} },
    @{ Name='Service approved packages'; Path=Join-Path $PSScriptRoot '03-ServiceImage.ps1'; Arguments=@{BuildRoot=$BuildRoot} },
    @{ Name='Inventory and reviewed component configuration'; Path=Join-Path $PSScriptRoot '04-ConfigureWindows.ps1'; Arguments=@{BuildRoot=$BuildRoot} },
    @{ Name='Add Setup and post-install workflow'; Path=Join-Path $PSScriptRoot '05-BuildSetup.ps1'; Arguments=@{BuildRoot=$BuildRoot} },
    @{ Name='Create bootable ISO'; Path=Join-Path $PSScriptRoot '06-BuildISO.ps1'; Arguments=@{BuildRoot=$BuildRoot;OutputPath=$OutputPath} },
    @{ Name='Structural ISO validation'; Path=Join-Path $PSScriptRoot '07-ValidateISO.ps1'; Arguments=@{IsoPath=$OutputPath} }
)
Assert-BakaAdministrator
foreach($stage in $stages){
    Write-BakaLog -Message "Starting pipeline stage: $($stage.Name)."
    try { $arguments=$stage.Arguments; & $stage.Path @arguments }
    catch {
        $detail = [string]$_.Exception.Message
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = ($_ | Format-List * -Force | Out-String).Trim() }
        Write-BakaLog -Level ERROR -Message "Pipeline stopped at '$($stage.Name)': $detail"
        throw
    }
    Write-BakaLog -Message "Finished pipeline stage: $($stage.Name)."
}
Write-BakaLog -Message 'Structural build stages complete. VM, physical hardware, game, and performance acceptance remain separate.'
