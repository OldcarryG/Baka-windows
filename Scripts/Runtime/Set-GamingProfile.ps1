[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Desktop','CompetitiveGaming','Benchmark')][string]$Profile)
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Modules\GamingProfiles.psm1'
Import-Module $modulePath -Force
$result = Set-BakaGamingProfile -Profile $Profile
$result | Format-List
