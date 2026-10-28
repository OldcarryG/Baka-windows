$ErrorActionPreference = 'Stop'
# Runs once per user (Active Setup) at the first sign-in. User-level privacy values are backed up to
# %LOCALAPPDATA%\BAKA\UserTuningBackup.json so "Restore BAKA System Tuning" can put them back.
$root = Join-Path $env:ProgramData 'BAKA'
$userRoot = Join-Path $env:LOCALAPPDATA 'BAKA'
$logDirectory = Join-Path $userRoot 'Logs'
if (-not (Test-Path -LiteralPath $logDirectory)) { New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null }
$logPath = Join-Path $logDirectory 'FirstLogon.log'
function Write-FirstLogonLog([string]$Message) { Add-Content -LiteralPath $logPath -Value ('{0} {1}' -f (Get-Date -Format 'o'), $Message) -Encoding UTF8 }
# One failed step must not skip the rest (browser, desktop, wallpaper): log it and continue.
trap { Write-FirstLogonLog ('step-failed error="{0}"' -f $_.Exception.Message); continue }
$privacyPath = Join-Path $root 'PrivacySettings.json'
if (Test-Path -LiteralPath $privacyPath -PathType Leaf) {
    $privacy = Get-Content -LiteralPath $privacyPath -Raw | ConvertFrom-Json
    try {
        Import-Module (Join-Path $root 'Modules\SystemTuning.psm1') -Force
        $userValues = @($privacy.userPolicies)
        $gamePerformancePath = Join-Path $root 'GamePerformance.json'
        if (Test-Path -LiteralPath $gamePerformancePath -PathType Leaf) { $userValues += @((Get-Content -LiteralPath $gamePerformancePath -Raw | ConvertFrom-Json).userPolicies) }
        $result = Invoke-BakaSystemTuning -Mode Apply -Configuration ([pscustomobject]@{ services=@(); scheduledTasks=@(); protectedServices=@() }) -RegistryValues $userValues -StatePath (Join-Path $userRoot 'UserTuningBackup.json') -Confirm:$false
        Write-FirstLogonLog ('user-privacy-applied changed={0}' -f @($result.Changed).Count)
    } catch {
        Write-FirstLogonLog ('user-privacy-module-failed error="{0}"; applying without backup' -f $_.Exception.Message)
        foreach ($setting in $privacy.userPolicies) {
            if ($setting.type -ne 'DWord') { throw "Unsupported user privacy policy value type: $($setting.type)" }
            if (-not (Test-Path -LiteralPath $setting.path)) { New-Item -Path $setting.path -Force | Out-Null }
            New-ItemProperty -LiteralPath $setting.path -Name $setting.name -PropertyType DWord -Value ([int]$setting.value) -Force | Out-Null
        }
    }
}
$personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
if (-not (Test-Path -LiteralPath $personalize)) { New-Item -Path $personalize -Force | Out-Null }
New-ItemProperty -LiteralPath $personalize -Name 'AppsUseLightTheme' -PropertyType DWord -Value 0 -Force | Out-Null
New-ItemProperty -LiteralPath $personalize -Name 'SystemUsesLightTheme' -PropertyType DWord -Value 0 -Force | Out-Null
New-ItemProperty -LiteralPath $personalize -Name 'EnableTransparency' -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -LiteralPath $personalize -Name 'ColorPrevalence' -PropertyType DWord -Value 0 -Force | Out-Null

$powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
# Install the selected apps (Baka Browser) before the desktop appears, so the browser is already there
# and already the default the first time the user sees BAKA. The installer ships inside the image.
$installer = Join-Path $root 'Scripts\Install-SelectedApps.ps1'
if (Test-Path -LiteralPath $installer -PathType Leaf) {
    $install = Start-Process -FilePath $powershell -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $installer),'-Silent') -WindowStyle Hidden -PassThru
    Write-FirstLogonLog 'silent-app-install-started'
    if ($install.WaitForExit(240000)) { Write-FirstLogonLog ('silent-app-install-finished exitCode={0}' -f $install.ExitCode) }
    else { Write-FirstLogonLog 'silent-app-install-still-running; the BAKA desktop will finish it in the background' }
}
# Free 4K video codecs (AV1, VP9, HEVC from Device Manufacturer, HEIF) from Microsoft Store, in the background.
$codecInstaller = Join-Path $root 'Scripts\Install-MediaCodecs.ps1'
if (Test-Path -LiteralPath $codecInstaller -PathType Leaf) {
    Start-Process -FilePath $powershell -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $codecInstaller)) -WindowStyle Hidden
    Write-FirstLogonLog 'media-codec-install-started'
}
# Explorer stays this user's Windows shell and runs in the background (tray, notifications, file dialogs);
# BAKA Desktop replaces its taskbar, Start, desktop icons and folder windows. Earlier releases replaced the
# shell itself, which is undone here.
$winlogonUser = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon'
$oldShell = (Get-ItemProperty -LiteralPath $winlogonUser -Name 'Shell' -ErrorAction SilentlyContinue).Shell
if ($oldShell -and $oldShell -match 'Baka') { Remove-ItemProperty -LiteralPath $winlogonUser -Name 'Shell' -ErrorAction SilentlyContinue; Write-FirstLogonLog 'old-baka-shell-override-removed' }
# Startup apps run right away instead of after Explorer's 10-second delay, and the taskbar starts hidden
# so it does not flash before BAKA Desktop appears.
$serialize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize'
New-Item -Path $serialize -Force | Out-Null
New-ItemProperty -LiteralPath $serialize -Name 'StartupDelayInMSec' -PropertyType DWord -Value 0 -Force | Out-Null
New-ItemProperty -LiteralPath $serialize -Name 'WaitForIdleState' -PropertyType DWord -Value 0 -Force | Out-Null
$stuck = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
$settings = (Get-ItemProperty -LiteralPath $stuck -Name 'Settings' -ErrorAction SilentlyContinue).Settings
if ($settings -and $settings.Length -gt 8) { $settings[8] = $settings[8] -bor 1; New-ItemProperty -LiteralPath $stuck -Name 'Settings' -PropertyType Binary -Value $settings -Force | Out-Null }
$desktopExe = Join-Path $root 'Desktop\BakaDesktop.exe'
# No Edge shortcut on this user's desktop (Baka Browser is the browser).
$edgeLink = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Microsoft Edge.lnk'
if (Test-Path -LiteralPath $edgeLink -PathType Leaf) { Remove-Item -LiteralPath $edgeLink -Force -ErrorAction SilentlyContinue }
# Desktop background is a picture (not Windows Spotlight), so the BAKA wallpaper stays.
$wallpapersKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers'
if (-not (Test-Path -LiteralPath $wallpapersKey)) { New-Item -Path $wallpapersKey -Force | Out-Null }
New-ItemProperty -LiteralPath $wallpapersKey -Name 'BackgroundType' -PropertyType DWord -Value 0 -Force | Out-Null
# Start BAKA Desktop now; the HKLM Run entry starts it at every later sign-in (single instance).
if (Test-Path -LiteralPath $desktopExe -PathType Leaf) {
    Start-Process -FilePath $desktopExe -WorkingDirectory (Split-Path -Parent $desktopExe)
    Write-FirstLogonLog 'baka-desktop-started'
}

$wallpaper = Join-Path $root 'Assets\BAKA-Stealth-4K.png'
if (-not (Test-Path -LiteralPath $wallpaper -PathType Leaf)) { $wallpaper = Join-Path $root 'Assets\BAKA-Liquid-Ribbon.png' }
if (-not (Test-Path -LiteralPath $wallpaper -PathType Leaf)) { return }
$signature = @'
using System;
using System.Runtime.InteropServices;
public static class BakaDesktopNative {
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool SystemParametersInfo(uint action, uint param, string value, uint flags);
}
'@
Add-Type -TypeDefinition $signature -ErrorAction SilentlyContinue
$SPI_SETDESKWALLPAPER = 20
$SPIF_UPDATEINIFILE = 1
$SPIF_SENDCHANGE = 2
[void][BakaDesktopNative]::SystemParametersInfo($SPI_SETDESKWALLPAPER,0,$wallpaper,($SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE))
Write-FirstLogonLog 'wallpaper-set'
