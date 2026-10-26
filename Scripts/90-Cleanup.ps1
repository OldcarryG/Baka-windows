[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param([switch]$RemoveCurrentBuild)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Modules\BAKA.Common.psm1') -Force
if (-not $RemoveCurrentBuild) { Write-Host 'No cleanup requested. Pass -RemoveCurrentBuild and confirm to remove only Work\CurrentBuild.'; return }
$target = [IO.Path]::GetFullPath((Join-Path $root 'Work\CurrentBuild'))
$work = [IO.Path]::GetFullPath((Join-Path $root 'Work'))
if (-not (Test-BakaPathWithinRoot -Path $target -Root $work) -or $target -eq $work) { throw 'Resolved cleanup target is outside the intended Work directory.' }
if (Test-Path -LiteralPath $target) {
    if ($PSCmdlet.ShouldProcess($target,'Remove generated current build workspace')) { Remove-Item -LiteralPath $target -Recurse -Force }
}
Write-BakaLog -Message 'Cleanup finished. Source media, Downloads, Logs, Tests, and Output were not selected for removal.'
