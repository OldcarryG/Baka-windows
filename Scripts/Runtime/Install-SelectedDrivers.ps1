[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$dataRoot=Split-Path -Parent $PSScriptRoot
$modulePath=Join-Path $dataRoot 'Modules\HardwareDetection.psm1'
$manifestPath=Join-Path $dataRoot 'Drivers.json'
$logDirectory=Join-Path $env:ProgramData 'BAKA\Logs'
if(-not(Test-Path -LiteralPath $logDirectory)){New-Item -ItemType Directory -Path $logDirectory -Force|Out-Null}
$logPath=Join-Path $logDirectory 'Drivers.log'
function Write-DriverLog([string]$Message){Add-Content -LiteralPath $logPath -Value ('{0} {1}' -f (Get-Date -Format 'o'),$Message) -Encoding UTF8}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
    $powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Start-Process -FilePath $powershell -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath) -Wait
    return
}
Import-Module $modulePath -Force
$inventory=Get-BakaHardwareInventory
$families=@(Get-BakaHardwareFamilies -Inventory $inventory)
$inventory | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $logDirectory 'HardwareInventory.json') -Encoding UTF8
$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
$enabled=@($manifest.postInstallCatalog|Where-Object enabled)
if($enabled.Count -eq 0){Write-DriverLog 'No driver packages are approved/enabled; no driver was downloaded or installed.';Write-Host 'Hardware inventory saved. No driver packages are enabled in the reviewed catalog.';return}
$results=[System.Collections.Generic.List[object]]::new()
foreach($driver in $enabled){
    $matched=$false
    if($driver.hardwareMatch -in $families){$matched=$true}
    if($driver.hardwareMatch -eq 'network' -and $inventory.ActiveNetworkAdapters.Count -gt 0){$matched=$true}
    if($driver.hardwareMatch -eq 'audio' -and @(Get-CimInstance Win32_SoundDevice).Count -gt 0){$matched=$true}
    if($driver.hardwareMatch -eq 'storage' -and $inventory.Disks.Count -gt 0){$matched=$true}
    if(-not $matched){$results.Add([pscustomobject]@{Family=$driver.family;Status='Skipped';Reason='No hardware match'});continue}
    if(-not $driver.sourceUrl -or -not $driver.sha256 -or -not $driver.signerPattern){throw "Matched driver '$($driver.family)' is missing a pinned official source, SHA-256, or signer pattern."}
    $packagePath=$null
    if($driver.package){$packagePath=Join-Path $dataRoot ($driver.package -replace '/','\')}
    if(-not $packagePath -or -not(Test-Path -LiteralPath $packagePath -PathType Leaf)){
        $download=Join-Path (Join-Path $env:ProgramData 'BAKA\Downloads') (([uri]$driver.sourceUrl).Segments[-1])
        $downloadDirectory=Split-Path -Parent $download
        if(-not(Test-Path -LiteralPath $downloadDirectory)){New-Item -ItemType Directory -Path $downloadDirectory -Force|Out-Null}
        $downloaded=$false
        for($attempt=1;$attempt -le 3;$attempt++){
            try{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;Invoke-WebRequest -Uri $driver.sourceUrl -OutFile $download -UseBasicParsing -ErrorAction Stop;$downloaded=$true;break}
            catch{Write-DriverLog "Download attempt $attempt failed for $($driver.family): $($_.Exception.Message)";if($attempt -lt 3){Start-Sleep -Seconds 3}}
        }
        if(-not $downloaded){$results.Add([pscustomobject]@{Family=$driver.family;Status='Failed';Reason='Download failed after retries'});continue}
        $packagePath=$download
    }
    $actual=(Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToUpperInvariant()
    if($actual -ne ([string]$driver.sha256).ToUpperInvariant()){Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue;throw "Driver hash mismatch for '$($driver.family)'; rejected package."}
    $signature=Get-AuthenticodeSignature -LiteralPath $packagePath
    if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch $driver.signerPattern){throw "Driver package for '$($driver.family)' is not signed by the expected vendor (status $($signature.Status); signer $($signature.SignerCertificate.Subject))."}
    Write-DriverLog "Verified $($driver.family); SHA-256 $actual; signer $($signature.SignerCertificate.Subject)."
    $arguments=@()
    if($driver.arguments){$arguments=[string[]]$driver.arguments}
    if($arguments.Count -gt 0){$process=Start-Process -FilePath $packagePath -ArgumentList $arguments -PassThru -Wait}else{$process=Start-Process -FilePath $packagePath -PassThru -Wait}
    $results.Add([pscustomobject]@{Family=$driver.family;Status=if($process.ExitCode -eq 0){'Completed'}else{'Failed'};ExitCode=$process.ExitCode;Sha256=$actual})
    if($process.ExitCode -ne 0){Write-DriverLog "Installer failed for $($driver.family), exit code $($process.ExitCode)."}else{Write-DriverLog "Installer completed for $($driver.family)."}
}
$results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $logDirectory 'DriverInstallResults.json') -Encoding UTF8
$results | Format-Table -AutoSize
