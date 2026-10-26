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
$servicing = Import-BakaJson -Path (Join-Path $root 'Config\ServicingPackages.json')
$base = Import-BakaJson -Path (Join-Path $root 'Config\BaseImage.json')
$drivers = Import-BakaJson -Path (Join-Path $root 'Config\Drivers.json')
$requiredUpdate = $base.latestKnownServicing
$releaseUpdate = $servicing.releaseUpdate
if (-not $requiredUpdate -or -not $releaseUpdate -or
    [string]$releaseUpdate.targetKb -ne [string]$requiredUpdate.kb -or
    [string]$releaseUpdate.targetBuild -ne [string]$requiredUpdate.build) {
    throw 'The servicing manifest does not match the currently recorded release update. Refresh and review both manifests before building.'
}
if (-not $releaseUpdate.packageDirectory -or @($releaseUpdate.requiredFiles).Count -lt 2) {
    throw "Required release update $($requiredUpdate.kb) must include its checkpoint package(s) and target package."
}
$releaseUpdateDirectory = Join-Path $root ($releaseUpdate.packageDirectory -replace '/', '\\')
if (-not (Test-BakaPathWithinRoot -Path $releaseUpdateDirectory -Root (Join-Path $root 'Downloads\Servicing'))) { throw 'The release update package folder must stay under Downloads\Servicing.' }
$checkpointEntries = @($releaseUpdate.requiredFiles | Where-Object { $_.role -eq 'checkpoint' })
$targetEntries = @($releaseUpdate.requiredFiles | Where-Object { $_.kb -eq $requiredUpdate.kb -and $_.role -eq 'target' })
if ($checkpointEntries.Count -lt 1) { throw 'The servicing manifest must include at least one checkpoint package.' }
if ($targetEntries.Count -ne 1) { throw "Servicing manifest must contain exactly one target package entry for $($requiredUpdate.kb)." }
$packagePaths = [System.Collections.Generic.List[string]]::new()
foreach ($entry in $releaseUpdate.requiredFiles) {
    if (-not $entry.approved -or -not $entry.relativePath -or -not $entry.sha256) {
        throw "Required servicing file $($entry.kb) is not yet approved and SHA-256 pinned. Refusing to create a stale image."
    }
    $path = Join-Path $root ($entry.relativePath -replace '/', '\\')
    if (-not (Test-BakaPathWithinRoot -Path $path -Root $releaseUpdateDirectory)) { throw "Servicing file escapes its isolated package directory: $path" }
    if ([IO.Path]::GetExtension($path) -ne '.msu') { throw "Expected a catalog MSU package: $path" }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required servicing file not found: $path" }
    if ((Get-BakaSha256 -Path $path) -ne ([string]$entry.sha256).ToUpperInvariant()) { throw "Servicing package SHA-256 mismatch: $path" }
    $packagePaths.Add([IO.Path]::GetFullPath($path))
}
if (@($packagePaths | Split-Path -Parent | Select-Object -Unique).Count -ne 1) { throw 'Checkpoint and target updates must be staged together in one isolated folder.' }
if (-not (Test-Path -LiteralPath $releaseUpdateDirectory -PathType Container)) { throw "Servicing package folder not found: $releaseUpdateDirectory" }
$actualMsuFiles = @(Get-ChildItem -LiteralPath $releaseUpdateDirectory -Filter '*.msu' -File | ForEach-Object FullName | Sort-Object)
$expectedMsuFiles = @($packagePaths | Sort-Object)
if (Compare-Object -ReferenceObject $expectedMsuFiles -DifferenceObject $actualMsuFiles) { throw 'The isolated servicing folder must contain exactly the manifest-pinned checkpoint and target MSU files.' }
$mount = Join-Path $BuildRoot 'Mount'
if (-not (Test-Path -LiteralPath $mount)) { New-Item -ItemType Directory -Path $mount -Force | Out-Null }
Import-Module Dism -ErrorAction Stop
$adkDism = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\DISM\dism.exe'
if (-not (Test-Path -LiteralPath $adkDism -PathType Leaf)) { throw "Current ADK DISM was not found: $adkDism" }
$mounted = $false
try {
    Mount-WindowsImage -ImagePath $image -Index 1 -Path $mount -CheckIntegrity | Out-Null
    $mounted = $true
    $installedBefore = @(Get-WindowsPackage -Path $mount)
    $rollupVersions = @(
        foreach ($package in $installedBefore | Where-Object { $_.PackageName -like 'Package_for_RollupFix*' -and $_.PackageState -in @('Installed','Superseded') }) {
            if ($package.PackageName -match '~~(?<version>\d+\.\d+\.\d+\.\d+)$') { [version]$matches.version }
        }
    )
    if ($rollupVersions.Count -eq 0) { throw 'Could not determine the mounted image baseline rollup version; refusing to skip a required checkpoint.' }
    $baselineRollup = $rollupVersions | Sort-Object -Descending | Select-Object -First 1
    Write-BakaLog -Message "Mounted image baseline rollup version is $baselineRollup. Servicing with ADK DISM $((Get-Item $adkDism).VersionInfo.ProductVersion)."

    foreach ($entry in $checkpointEntries) {
        if (-not $entry.osBuild) { throw "Checkpoint $($entry.kb) has no pinned OS build; cannot determine whether it is already superseded." }
        $checkpointBuild = [version]([string]$entry.osBuild -replace '^10\.0\.', '')
        if ($baselineRollup -ge $checkpointBuild) {
            Write-BakaLog -Message "Checkpoint $($entry.kb) build $($entry.osBuild) is superseded by the image's installed rollup $baselineRollup; skipping the obsolete checkpoint package."
            continue
        }
        $checkpointPath = Join-Path $root ($entry.relativePath -replace '/', '\\')
        $log = Join-Path $root ("Logs\DISM-{0}-{1:yyyyMMdd-HHmmss}.log" -f $entry.kb,(Get-Date))
        Write-BakaLog -Message "Applying required checkpoint $($entry.kb) with current ADK DISM."
        $args = @("/Image:$mount",'/Add-Package',"/PackagePath:$checkpointPath","/LogPath:$log")
        & $adkDism @args
        if ($LASTEXITCODE -ne 0) { throw "ADK DISM failed to apply checkpoint $($entry.kb) (exit $LASTEXITCODE). See $log" }
    }

    $targetPath = Join-Path $root ($targetEntries[0].relativePath -replace '/', '\\')
    $targetLog = Join-Path $root ("Logs\DISM-{0}-{1:yyyyMMdd-HHmmss}.log" -f $requiredUpdate.kb,(Get-Date))
    Write-BakaLog -Message "Applying target update $($requiredUpdate.kb) from its verified MSU with current ADK DISM."
    $targetArgs = @("/Image:$mount",'/Add-Package',"/PackagePath:$targetPath","/LogPath:$targetLog")
    & $adkDism @targetArgs
    if ($LASTEXITCODE -ne 0) { throw "ADK DISM failed to apply target update $($requiredUpdate.kb) (exit $LASTEXITCODE). See $targetLog" }

    $targetPackageBuild = [string]$releaseUpdate.packageBuild -replace '^10\.0\.', ''
    if ([string]::IsNullOrWhiteSpace($targetPackageBuild)) { throw 'Servicing manifest has no pinned CBS package build for the target update.' }
    $targetPackagePrefix = "Package_for_RollupFix~31bf3856ad364e35~amd64~~$targetPackageBuild."
    $targetListLog = Join-Path $root ("Logs\DISM-{0}-List-{1:yyyyMMdd-HHmmss}.log" -f $requiredUpdate.kb,(Get-Date))
    # The package identity includes revision fields beyond packageBuild (for example .1.30).
    # Enumerate the offline image, then verify its exact installed identity with DISM.
    $packageInventory = (& $adkDism "/Image:$mount" '/Get-Packages' '/Format:Table' '/English' "/LogPath:$targetListLog" 2>&1 | Out-String)
    $packageInventoryExit = $LASTEXITCODE
    if ($packageInventoryExit -ne 0) { throw "DISM package inventory failed with exit $packageInventoryExit. See $targetListLog`n$packageInventory" }
    $installedIdentities = @(
        foreach ($line in ($packageInventory -split "`r?`n")) {
            if ($line -match '^\s*(?<identity>Package_for_RollupFix[^|]+?)\s*\|\s*(?<state>[^|]+)\|') {
                $identity = $matches.identity.Trim()
                $state = $matches.state.Trim()
                if ($identity.StartsWith($targetPackagePrefix,[StringComparison]::OrdinalIgnoreCase) -and $state -eq 'Installed') { $identity }
            }
        }
    )
    # Keep this as an array when only one installed identity is emitted; otherwise
    # indexing [0] on a scalar string returns its first character in PowerShell.
    $installedIdentities = @($installedIdentities | Sort-Object -Unique)
    if ($installedIdentities.Count -ne 1) { throw "Expected exactly one installed rollup package beginning '$targetPackagePrefix'; found $($installedIdentities.Count). See $targetListLog`n$packageInventory" }
    $targetPackageIdentity = $installedIdentities[0]
    $targetVerifyLog = Join-Path $root ("Logs\DISM-{0}-Verify-{1:yyyyMMdd-HHmmss}.log" -f $requiredUpdate.kb,(Get-Date))
    # Get-WindowsPackage can hang against an image immediately after DISM has serviced it.
    # Query the exact installed CBS identity through the same ADK DISM binary instead.
    $targetPackageInfo = (& $adkDism "/Image:$mount" '/Get-PackageInfo' "/PackageName:$targetPackageIdentity" '/English' "/LogPath:$targetVerifyLog" 2>&1 | Out-String)
    $targetPackageInfoExit = $LASTEXITCODE
    if ($targetPackageInfoExit -ne 0 -or $targetPackageInfo -notmatch '(?im)^\s*State\s*:\s*Installed\s*$') {
        throw "The offline image does not report the exact target package $targetPackageIdentity as installed (DISM exit $targetPackageInfoExit). See $targetVerifyLog`n$targetPackageInfo"
    }
    $installedTarget = @([pscustomobject]@{ PackageName=$targetPackageIdentity; PackageState='Installed' })
    foreach ($package in @($servicing.packages)) {
        if (-not $package.approved -or -not $package.relativePath -or -not $package.sha256) { throw 'Every servicing package must be approved and pinned by SHA-256.' }
        $path = Join-Path $root ($package.relativePath -replace '/', '\')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Servicing package not found: $path" }
        if ((Get-BakaSha256 -Path $path) -ne ([string]$package.sha256).ToUpperInvariant()) { throw "SHA-256 mismatch for $path" }
        Write-BakaLog -Message "Adding approved package $($package.displayName) from $path."
        Add-WindowsPackage -Path $mount -PackagePath $path -NoRestart -ErrorAction Stop | Out-Null
    }
    foreach ($driver in @($servicing.drivers) + @($drivers.integrateIntoBootImage)) {
        if (-not $driver.approved -or -not $driver.relativePath -or -not $driver.sha256) { throw 'Every integrated driver package must be approved and pinned by SHA-256.' }
        $path = Join-Path $root ($driver.relativePath -replace '/', '\')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Driver package not found: $path" }
        if ((Get-BakaSha256 -Path $path) -ne ([string]$driver.sha256).ToUpperInvariant()) { throw "SHA-256 mismatch for $path" }
        Add-WindowsDriver -Path $mount -Driver $path -Recurse -ErrorAction Stop | Out-Null
        Write-BakaLog -Message "Added approved driver package $($driver.displayName)."
    }
    $commitLog = Join-Path $root ("Logs\DISM-Commit-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
    $commitArgs = @('/Unmount-Image',"/MountDir:$mount",'/Commit','/CheckIntegrity',"/LogPath:$commitLog")
    & $adkDism @commitArgs
    if ($LASTEXITCODE -ne 0) { throw "ADK DISM failed to commit and integrity-check the serviced image (exit $LASTEXITCODE). See $commitLog" }
    $mounted = $false
    $contextPath = Join-Path $BuildRoot 'build-context.json'
    $context = Get-Content -LiteralPath $contextPath -Raw | ConvertFrom-Json
    $context | Add-Member -NotePropertyName ServicedUpdate -NotePropertyValue ([pscustomobject]@{
        TargetKb=$requiredUpdate.kb; TargetBuild=$requiredUpdate.build; PackageIdentities=@($installedTarget | ForEach-Object PackageName)
        Files=@($releaseUpdate.requiredFiles | ForEach-Object { [pscustomobject]@{Kb=$_.kb;Path=$_.relativePath;Sha256=$_.sha256} })
        AppliedAt=(Get-Date).ToString('o')
    }) -Force
    $context | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $contextPath -Encoding UTF8
    Write-BakaLog -Message 'Image servicing completed. No package or driver was added unless present in an approved manifest.'
} finally {
    if ($mounted) {
        $discardLog = Join-Path $root ("Logs\DISM-Discard-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
        & $adkDism '/Unmount-Image' "/MountDir:$mount" '/Discard' "/LogPath:$discardLog" | Out-Null
    }
}
