[CmdletBinding()]
param()
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
    [System.Windows.Forms.MessageBox]::Show($Message,$Title,$Buttons,$Icon)
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Application manifest missing: $manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$selected = @($manifest.applications | Where-Object selected)
foreach ($app in $selected) {
    if ([string]::IsNullOrWhiteSpace([string]$app.sha256)) { throw "Selected application '$($app.displayName)' has no SHA-256 pin." }
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
        $process = Start-Process -FilePath $installer -PassThru -Wait
        if ($process.ExitCode -ne 0) { throw "Installer returned exit code $($process.ExitCode)." }
        Write-InstallLog "Installer completed for $($app.displayName); exit code 0."
        $setDefault = Show-Message "$($app.displayName) was installed. Windows controls browser defaults per user. Open Default apps so you can select Baka Browser for HTTP and HTTPS?" 'Set browser default' YesNo Question
        if ($setDefault -eq [System.Windows.Forms.DialogResult]::Yes) { Start-Process 'ms-settings:defaultapps' }
    } catch {
        Write-InstallLog "Installation failed for $($app.displayName): $($_.Exception.Message)"
        Show-Message "Installation failed. The details are saved in:`r`n$logPath`r`n`r`n$($_.Exception.Message)" 'BAKA App Installer' OK Error | Out-Null
    }
}
