[CmdletBinding()]
param([switch]$Silent)
# Installs the approved, hash-pinned BAKA applications for the current user.
# -Silent is used once at first logon: no prompts, Velopack --silent, and browser registration so the
# Windows default-associations policy can make Baka Browser the default for web links.
$ErrorActionPreference = 'Stop'
$dataRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $dataRoot 'Applications.json'
$logRoot = Join-Path $env:LOCALAPPDATA 'BAKA\Logs'
if (-not (Test-Path -LiteralPath $logRoot)) { New-Item -ItemType Directory -Path $logRoot -Force | Out-Null }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$logPath = Join-Path $logRoot 'Install-SelectedApps.log'
function Write-InstallLog([string]$Message) {
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}
function Show-Message([string]$Message,[string]$Title='BAKA Setup',[System.Windows.Forms.MessageBoxButtons]$Buttons=[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]$Icon=[System.Windows.Forms.MessageBoxIcon]::Information) {
    if ($Silent) { Write-InstallLog "Suppressed prompt in silent mode: $Title"; return [System.Windows.Forms.DialogResult]::Yes }
    [System.Windows.Forms.MessageBox]::Show($Message,$Title,$Buttons,$Icon)
}
function Get-BakaBrowserExecutable {
    $installRoot = Join-Path $env:LOCALAPPDATA 'BakaBrowser'
    foreach ($candidate in @((Join-Path $installRoot 'current\baka.exe'), (Join-Path $installRoot 'baka.exe'))) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}
function Register-BakaBrowserCapabilities([string]$Executable) {
    # Per-user browser registration (Default Programs capabilities). Velopack installs per user and the
    # browser does not register itself, so BAKA adds the standard keys Windows needs to list it.
    $progId = 'BakaBrowserHTML'
    $command = '"{0}" "%1"' -f $Executable
    $icon = '"{0}",0' -f $Executable
    $classes = 'HKCU:\Software\Classes'
    $client = 'HKCU:\Software\Clients\StartMenuInternet\BakaBrowser'
    foreach ($key in @("$classes\$progId", "$classes\$progId\DefaultIcon", "$classes\$progId\shell\open\command", $client, "$client\Capabilities", "$client\Capabilities\URLAssociations", "$client\Capabilities\FileAssociations", "$client\Capabilities\StartMenu", "$client\DefaultIcon", "$client\shell\open\command", 'HKCU:\Software\RegisteredApplications')) {
        if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
    }
    Set-Item -LiteralPath "$classes\$progId" -Value 'Baka Browser Document'
    New-ItemProperty -LiteralPath "$classes\$progId" -Name 'FriendlyTypeName' -Value 'Baka Browser Document' -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath "$classes\$progId" -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
    Set-Item -LiteralPath "$classes\$progId\DefaultIcon" -Value $icon
    Set-Item -LiteralPath "$classes\$progId\shell\open\command" -Value $command
    Set-Item -LiteralPath $client -Value 'Baka Browser'
    Set-Item -LiteralPath "$client\DefaultIcon" -Value $icon
    Set-Item -LiteralPath "$client\shell\open\command" -Value ('"{0}"' -f $Executable)
    New-ItemProperty -LiteralPath "$client\Capabilities" -Name 'ApplicationName' -Value 'Baka Browser' -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath "$client\Capabilities" -Name 'ApplicationDescription' -Value 'Lightweight private browser selected for BAKA Windows.' -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath "$client\Capabilities" -Name 'ApplicationIcon' -Value $icon -PropertyType String -Force | Out-Null
    foreach ($scheme in @('http','https')) { New-ItemProperty -LiteralPath "$client\Capabilities\URLAssociations" -Name $scheme -Value $progId -PropertyType String -Force | Out-Null }
    foreach ($extension in @('.htm','.html','.shtml','.xhtml','.svg','.webp','.pdf')) { New-ItemProperty -LiteralPath "$client\Capabilities\FileAssociations" -Name $extension -Value $progId -PropertyType String -Force | Out-Null }
    New-ItemProperty -LiteralPath "$client\Capabilities\StartMenu" -Name 'StartMenuInternet' -Value 'BakaBrowser' -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath 'HKCU:\Software\RegisteredApplications' -Name 'BakaBrowser' -Value 'Software\Clients\StartMenuInternet\BakaBrowser\Capabilities' -PropertyType String -Force | Out-Null
    Write-InstallLog "Registered Baka Browser capabilities for $Executable."
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Application manifest missing: $manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$selected = @($manifest.applications | Where-Object selected)
foreach ($app in $selected) {
    if ([string]::IsNullOrWhiteSpace([string]$app.sha256)) { throw "Selected application '$($app.displayName)' has no SHA-256 pin." }
    if ($app.id -eq 'baka-browser') {
        $existing = Get-BakaBrowserExecutable
        if ($existing) {
            Write-InstallLog "Baka Browser is already installed at $existing."
            Register-BakaBrowserCapabilities $existing
            if (-not $Silent) { Show-Message 'Baka Browser is already installed. Windows applies the BAKA default-browser setting at sign-in; you can change it any time in Settings > Apps > Default apps.' 'BAKA App Installer' | Out-Null }
            continue
        }
    }
    $installer = Join-Path (Join-Path $dataRoot 'Apps') (Split-Path -Leaf $app.relativePath)
    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
        $installer = Join-Path $env:LOCALAPPDATA ("BAKA\Downloads\{0}" -f (Split-Path -Leaf $app.relativePath))
        $downloadDirectory = Split-Path -Parent $installer
        if (-not (Test-Path -LiteralPath $downloadDirectory)) { New-Item -ItemType Directory -Path $downloadDirectory -Force | Out-Null }
        $downloaded = $false
        for ($attempt=1; $attempt -le [math]::Max(1,[int]$manifest.networkRetryCount); $attempt++) {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri $app.sourceUrl -OutFile $installer -UseBasicParsing -ErrorAction Stop
                $downloaded = $true
                break
            } catch {
                Write-InstallLog "Download attempt $attempt failed for $($app.displayName): $($_.Exception.Message)"
                if ($attempt -lt [math]::Max(1,[int]$manifest.networkRetryCount)) { Start-Sleep -Seconds 3 }
            }
        }
        if (-not $downloaded) { throw "Download failed after retries for $($app.displayName). Check network access and run this installer again." }
    }
    $actualHash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualHash -ne ([string]$app.sha256).ToUpperInvariant()) {
        Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
        throw "SHA-256 validation failed for $($app.displayName); the file was removed."
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $installer
    if ($signature.Status -eq 'NotSigned' -and $app.authenticode -notmatch 'NotSigned') { throw "Unsigned installer is not explicitly allowed for $($app.displayName)." }
    if ($signature.Status -notin @('Valid','NotSigned')) { throw "Installer signature status for $($app.displayName) is $($signature.Status)." }
    Write-InstallLog "Verified $($app.displayName) $($app.version); SHA-256 $actualHash; Authenticode $($signature.Status)."
    $choice = Show-Message "Install the approved $($app.displayName) $($app.version) for this Windows user?`r`n`r`nThe pinned release installer is unsigned. Windows may show an unknown-publisher warning. The installer may need an internet connection to install WebView2." 'BAKA App Installer' YesNo Warning
    if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) { Write-InstallLog "User skipped $($app.displayName)."; continue }
    try {
        $arguments = @()
        if ($Silent -and $app.silentArguments) { $arguments = @($app.silentArguments) }
        $process = if ($arguments.Count) { Start-Process -FilePath $installer -ArgumentList $arguments -PassThru -Wait } else { Start-Process -FilePath $installer -PassThru -Wait }
        if ($process.ExitCode -ne 0) { throw "Installer returned exit code $($process.ExitCode)." }
        Write-InstallLog "Installer completed for $($app.displayName); exit code 0; silent=$([bool]$Silent)."
        if ($app.id -eq 'baka-browser') {
            $executable = $null
            for ($wait = 0; $wait -lt 30 -and -not $executable; $wait++) { $executable = Get-BakaBrowserExecutable; if (-not $executable) { Start-Sleep -Seconds 1 } }
            if ($executable) { Register-BakaBrowserCapabilities $executable } else { Write-InstallLog 'Baka Browser executable was not found after installation; registration skipped.' }
        }
        if ($app.defaultBrowser -and -not $Silent) {
            $setDefault = Show-Message "$($app.displayName) was installed and registered. BAKA asks Windows to make it the default browser at your next sign-in. Open Default apps now to confirm or change it?" 'Set browser default' YesNo Question
            if ($setDefault -eq [System.Windows.Forms.DialogResult]::Yes) { Start-Process 'ms-settings:defaultapps' }
        }
    } catch {
        Write-InstallLog "Installation failed for $($app.displayName): $($_.Exception.Message)"
        Show-Message "Installation failed. The details are saved in:`r`n$logPath`r`n`r`n$($_.Exception.Message)" 'BAKA App Installer' OK Error | Out-Null
    }
}
