[CmdletBinding()]
param()
# 4K video for every app (browser, Films & TV, the BAKA video wallpaper): installs Microsoft's free codec
# extensions from Microsoft Store with winget. AV1 and VP9 carry YouTube's 4K streams; HEVC (the free
# "from Device Manufacturer" edition) covers 4K phone and camera video; HEIF opens iPhone photos.
# Runs in the background at first sign-in; already-installed codecs are skipped. Needs an internet connection.
$ErrorActionPreference='Continue'
$log=Join-Path $env:LOCALAPPDATA 'BAKA\Logs\MediaCodecs.log'
New-Item -ItemType Directory -Path (Split-Path -Parent $log) -Force|Out-Null
function Write-CodecLog([string]$m){Add-Content -LiteralPath $log -Value ('{0} {1}' -f (Get-Date -Format o),$m)}
$codecs=@(
    @{Name='AV1 Video Extension';Store='9MVZQVXJBQ9V';Package='Microsoft.AV1VideoExtension'},
    @{Name='VP9 Video Extensions';Store='9N4D0MSMP0PT';Package='Microsoft.VP9VideoExtensions'},
    @{Name='HEVC Video Extensions from Device Manufacturer';Store='9N4WGH0Z6VHQ';Package='Microsoft.HEVCVideoExtension'},
    @{Name='HEIF Image Extensions';Store='9PMMSR1CGPWG';Package='Microsoft.HEIFImageExtension'}
)
$winget=Get-Command winget.exe -ErrorAction SilentlyContinue
if(-not $winget){
    # App Installer registers winget for a new user a little after the first sign-in.
    for($i=0;$i -lt 20 -and -not $winget;$i++){Start-Sleep -Seconds 15;$winget=Get-Command winget.exe -ErrorAction SilentlyContinue}
}
if(-not $winget){Write-CodecLog 'winget-unavailable; codecs can be installed from Microsoft Store later';return}
foreach($codec in $codecs){
    if(Get-AppxPackage -Name $codec.Package -ErrorAction SilentlyContinue){Write-CodecLog ("already-installed {0}" -f $codec.Name);continue}
    $out=& $winget.Source install --id $codec.Store --source msstore --accept-package-agreements --accept-source-agreements --silent --disable-interactivity 2>&1|Out-String
    Write-CodecLog ("install {0} exit={1} {2}" -f $codec.Name,$LASTEXITCODE,($out -replace '\s+',' ').Trim())
}
