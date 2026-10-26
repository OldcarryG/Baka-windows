[CmdletBinding()]
param([string]$BuildRoot)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Modules\BAKA.Common.psm1') -Force
Assert-BakaAdministrator
if (-not $BuildRoot) { $BuildRoot = Join-Path $root 'Work\CurrentBuild' }
$BuildRoot = [IO.Path]::GetFullPath($BuildRoot)
if (-not (Test-BakaPathWithinRoot -Path $BuildRoot -Root (Join-Path $root 'Work'))) { throw 'BuildRoot must be inside this project Work directory.' }
$image = Join-Path $BuildRoot 'Media\sources\install.wim'
if (-not (Test-Path -LiteralPath $image -PathType Leaf)) { throw "Prepared install.wim not found: $image" }
$debloat = Import-BakaJson -Path (Join-Path $root 'Config\Debloat.json')
Import-Module Dism -ErrorAction Stop
$adkDism = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\DISM\dism.exe'
if (-not (Test-Path -LiteralPath $adkDism -PathType Leaf)) { throw "Current ADK DISM was not found: $adkDism" }
$inventoryPath = Join-Path $BuildRoot 'provisioned-packages.json'
$mount = Join-Path $BuildRoot 'Mount'
if (-not (Test-Path -LiteralPath $mount)) { New-Item -ItemType Directory -Path $mount -Force | Out-Null }
$mounted = $false
$changesApplied = $false
function Complete-BakaImageMount {
    param([ValidateSet('Commit','Discard')][string]$Mode)
    $dismLog = Join-Path $root ("Logs\DISM-Appx-{0}-{1:yyyyMMdd-HHmmss}.log" -f $Mode,(Get-Date))
    $arguments = @('/Unmount-Image',"/MountDir:$mount")
    if ($Mode -eq 'Commit') { $arguments += @('/Commit','/CheckIntegrity') } else { $arguments += '/Discard' }
    $arguments += "/LogPath:$dismLog"
    & $adkDism @arguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "ADK DISM failed to $($Mode.ToLowerInvariant()) the package image (exit $LASTEXITCODE). See $dismLog" }
}
try {
    Mount-WindowsImage -ImagePath $image -Index 1 -Path $mount -CheckIntegrity | Out-Null
    $mounted = $true
    $packages = @(Get-AppxProvisionedPackage -Path $mount | Select-Object DisplayName,PackageName,Version,Architecture)
    $packages | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $inventoryPath -Encoding UTF8
    Write-BakaLog -Message "Saved provisioned package inventory to $inventoryPath."
    if ($debloat.enabled) {
        if (-not $debloat.requireImageInventoryReview) { throw 'Debloat must require an image inventory review.' }
        foreach ($candidate in @($debloat.candidateRemovals)) {
            if (-not $candidate.approved) { continue }
            if (@($candidate.packageNames).Count -eq 0) { throw "Approved category '$($candidate.category)' has no exact package names." }
            foreach ($name in @($candidate.packageNames)) {
                if ($name -match '[*?]') { throw "Wildcards are not allowed in approved package names: $name" }
                $match = @($packages | Where-Object { $_.PackageName -eq $name -or $_.DisplayName -eq $name })
                if ($match.Count -eq 0) { Write-BakaLog -Message "Approved optional package '$name' is not provisioned in this image; skipping."; continue }
                if ($match.Count -ne 1) { throw "Expected one exact provisioned package match for '$name'; found $($match.Count)." }
                foreach ($blocked in @($debloat.blockedPackagePatterns)) { if ($match[0].PackageName -like $blocked) { throw "Package '$name' matches protected pattern '$blocked'." } }
                Remove-AppxProvisionedPackage -Path $mount -PackageName $match[0].PackageName -ErrorAction Stop | Out-Null
                $changesApplied = $true
                Write-BakaLog -Message "Removed reviewed provisioned package $($match[0].PackageName)."
            }
        }
        if ($changesApplied) {
            Complete-BakaImageMount -Mode Commit
        } else {
            Complete-BakaImageMount -Mode Discard
            Write-BakaLog -Message 'No approved optional packages were present; the image was left unchanged.'
        }
        $mounted = $false
    } else {
        Complete-BakaImageMount -Mode Discard
        $mounted = $false
        Write-BakaLog -Message 'Component removal is disabled; the package inventory was collected without image changes.'
    }
} finally {
    if ($mounted) {
        try { Complete-BakaImageMount -Mode Discard }
        catch { Write-BakaLog -Level 'WARN' -Message "Could not discard the failed package-image mount: $($_.Exception.Message)" }
    }
}
