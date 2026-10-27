$ErrorActionPreference = 'Stop'
# Runs once per user (Active Setup) at the first sign-in. User-level privacy values are backed up to
# %LOCALAPPDATA%\BAKA\UserTuningBackup.json so "Restore BAKA System Tuning" can put them back.
$root = Join-Path $env:ProgramData 'BAKA'
$userRoot = Join-Path $env:LOCALAPPDATA 'BAKA'
$logDirectory = Join-Path $userRoot 'Logs'
if (-not (Test-Path -LiteralPath $logDirectory)) { New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null }
$logPath = Join-Path $logDirectory 'FirstLogon.log'
function Write-FirstLogonLog([string]$Message) { Add-Content -LiteralPath $logPath -Value ('{0} {1}' -f (Get-Date -Format 'o'), $Message) -Encoding UTF8 }
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
# Install the selected apps (Baka Browser) silently in the background so sign-in is not delayed.
$installer = Join-Path $root 'Scripts\Install-SelectedApps.ps1'
if (Test-Path -LiteralPath $installer -PathType Leaf) {
    Start-Process -FilePath $powershell -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $installer),'-Silent') -WindowStyle Hidden
    Write-FirstLogonLog 'silent-app-install-started'
}
# Start the BAKA desktop now; the Startup shortcut takes over from the next sign-in (single instance).
$companion = Join-Path $root 'Scripts\BakaCompanion.ps1'
if (Test-Path -LiteralPath $companion -PathType Leaf) {
    Start-Process -FilePath $powershell -ArgumentList @('-NoProfile','-STA','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $companion)) -WindowStyle Hidden
    Write-FirstLogonLog 'companion-started'
}

$wallpaper = Join-Path $root 'Assets\BAKA-BlackGlass-4K.png'
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
