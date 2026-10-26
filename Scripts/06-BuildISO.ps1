[CmdletBinding()]
param([string]$BuildRoot,[string]$OutputPath)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Modules\BAKA.Common.psm1') -Force
Assert-BakaAdministrator
if (-not $BuildRoot) { $BuildRoot = Join-Path $root 'Work\CurrentBuild' }
$BuildRoot = [IO.Path]::GetFullPath($BuildRoot)
if (-not (Test-BakaPathWithinRoot -Path $BuildRoot -Root (Join-Path $root 'Work'))) { throw 'BuildRoot must be inside this project Work directory.' }
$media = Join-Path $BuildRoot 'Media'
$required = @('boot\etfsboot.com','efi\microsoft\boot\efisys.bin','sources\boot.wim','sources\install.wim','setup.exe')
foreach ($relative in $required) { if (-not (Test-Path -LiteralPath (Join-Path $media $relative) -PathType Leaf)) { throw "Required setup/boot file missing: $relative" } }
$toolRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg'
$oscdimg = Join-Path $toolRoot 'oscdimg.exe'
if (-not (Test-Path -LiteralPath $oscdimg -PathType Leaf)) { throw "OSCDIMG not found: $oscdimg" }
if (-not $OutputPath) { $OutputPath = Join-Path $root 'Output\BAKA-Windows-Gaming-Edition-26H2-x64.iso' }
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if (-not (Test-BakaPathWithinRoot -Path $OutputPath -Root (Join-Path $root 'Output'))) { throw 'OutputPath must be inside the project Output directory.' }
$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) { New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null }
if (Test-Path -LiteralPath $OutputPath) { throw "Refusing to overwrite existing ISO: $OutputPath" }
$bootData = "2#p0,e,b$(Join-Path $media 'boot\etfsboot.com')#pEF,e,b$(Join-Path $media 'efi\microsoft\boot\efisys.bin')"
$arguments = @('-m','-o','-u2','-udfver102',"-bootdata:$bootData",'-lBAKAWIN11',$media,$OutputPath)
Write-BakaLog -Message "Creating UEFI + BIOS bootable ISO at $OutputPath."
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdoutLog = Join-Path $root "Logs\OSCDIMG-$stamp-stdout.log"
$stderrLog = Join-Path $root "Logs\OSCDIMG-$stamp-stderr.log"
# Keep native output out of PowerShell remoting's error stream. OSCDIMG emits
# progress/diagnostic text on stderr on some builds; remoting can wrap it as a
# terminating RemoteException even when the ISO operation itself succeeds.
$quotedArguments = @($arguments | ForEach-Object { '"' + ([string]$_).Replace('"','\"') + '"' })
$argumentLine = $quotedArguments -join ' '
$process = Start-Process -FilePath $oscdimg -ArgumentList $argumentLine -WorkingDirectory $root -PassThru -Wait -NoNewWindow -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
if ($process.ExitCode -ne 0) { throw "OSCDIMG failed with exit code $($process.ExitCode). See $stderrLog and $stdoutLog." }
$isoHash = Get-BakaSha256 -Path $OutputPath
$record = [pscustomobject]@{ BuiltAt=(Get-Date).ToString('o'); IsoPath=$OutputPath; Sha256=$isoHash; SizeBytes=(Get-Item -LiteralPath $OutputPath).Length; BootMode='BIOS + UEFI'; OsCdImgExitCode=$process.ExitCode; OsCdImgStdoutLog=$stdoutLog; OsCdImgStderrLog=$stderrLog; VmBootTest='Not run' }
$record | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $root 'Logs\ISO-Build.json') -Encoding UTF8
$record
