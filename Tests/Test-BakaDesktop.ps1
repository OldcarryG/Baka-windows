[CmdletBinding()]
param([int]$TimeoutSeconds=180,[switch]$NoBuild)
# Builds BAKA Desktop from Shell\BakaDesktop and runs its self test: every surface opened in an isolated
# preview (no real settings, registry, taskbar or wallpaper are touched) and checked like a person would:
# menu bar, dock, Launchpad search, Control Center, Settings pages, BAKA Files, Arena, widgets, profiles,
# themes and the icon set.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$project=Join-Path $root 'Shell\BakaDesktop\BakaDesktop.csproj'
$bin=Join-Path $root 'Shell\BakaDesktop\bin\out'
if(-not $NoBuild){
    $dotnet=@((Join-Path $root 'Work\dotnet\dotnet.exe'),(Get-Command dotnet.exe -ErrorAction SilentlyContinue|ForEach-Object Source))|Where-Object {$_ -and (Test-Path -LiteralPath $_)}|Select-Object -First 1
    if(-not $dotnet){throw 'The .NET SDK (dotnet.exe) is needed to build BAKA Desktop.'}
    $build=& $dotnet build $project -c Release -o $bin --nologo 2>&1|Out-String
    if($LASTEXITCODE -ne 0){throw "BAKA Desktop did not build:`n$build"}
}
$exe=Join-Path $bin 'BakaDesktop.exe'
$result=Join-Path ([IO.Path]::GetTempPath()) ('BAKA-Desktop-SelfTest-'+[Guid]::NewGuid().ToString('N')+'.json')
$env:BAKA_SELFTEST_RESULT=$result
$p=Start-Process -FilePath $exe -ArgumentList '--selftest' -PassThru
if(-not $p.WaitForExit($TimeoutSeconds*1000)){Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue;throw "BAKA Desktop self test did not finish within $TimeoutSeconds seconds."}
if(-not(Test-Path -LiteralPath $result)){throw "BAKA Desktop self test wrote no result (exit $($p.ExitCode))."}
$doc=Get-Content -LiteralPath $result -Raw|ConvertFrom-Json
Remove-Item -LiteralPath $result -Force
foreach($pass in @($doc.passed)){Write-Output ('PASS: '+$pass)}
foreach($fail in @($doc.failed)){Write-Output ('FAIL: '+$fail)}
Write-Output ('RESULT: {0} passed, {1} failed; exit={2}; apps listed={3}' -f @($doc.passed).Count,@($doc.failed).Count,$p.ExitCode,$doc.apps)
if($doc.result -ne 'Passed' -or $p.ExitCode -ne 0){throw ('BAKA Desktop self test failed: '+(@($doc.failed) -join '; '))}
