$ErrorActionPreference = 'Stop'
$root = Join-Path $env:ProgramData 'BAKA'
$privacyPath = Join-Path $root 'PrivacySettings.json'
if (Test-Path -LiteralPath $privacyPath -PathType Leaf) {
    $privacy = Get-Content -LiteralPath $privacyPath -Raw | ConvertFrom-Json
    foreach ($setting in $privacy.userPolicies) {
        if ($setting.type -ne 'DWord') { throw "Unsupported user privacy policy value type: $($setting.type)" }
        if (-not (Test-Path -LiteralPath $setting.path)) { New-Item -Path $setting.path -Force | Out-Null }
        New-ItemProperty -LiteralPath $setting.path -Name $setting.name -PropertyType DWord -Value ([int]$setting.value) -Force | Out-Null
    }
}
$personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
if (-not (Test-Path -LiteralPath $personalize)) { New-Item -Path $personalize -Force | Out-Null }
New-ItemProperty -LiteralPath $personalize -Name 'AppsUseLightTheme' -PropertyType DWord -Value 0 -Force | Out-Null
New-ItemProperty -LiteralPath $personalize -Name 'SystemUsesLightTheme' -PropertyType DWord -Value 0 -Force | Out-Null
New-ItemProperty -LiteralPath $personalize -Name 'EnableTransparency' -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -LiteralPath $personalize -Name 'ColorPrevalence' -PropertyType DWord -Value 0 -Force | Out-Null
$wallpaper = Join-Path $root 'Assets\BAKA-Liquid-Ribbon.png'
if (-not (Test-Path -LiteralPath $wallpaper -PathType Leaf)) { $wallpaper = Join-Path $root 'Assets\BAKA-BlackGlass-4K.png' }
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
