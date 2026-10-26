[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$pipeline=Join-Path $root 'Scripts\Invoke-BuildPipeline.ps1'
$powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$fixtureId=[Guid]::NewGuid().ToString('N')
$existingBuildRoot=Join-Path $root ('Work\PipelineGuardFixture-'+$fixtureId)
$existingIso=Join-Path $root ('Output\PipelineGuardFixture-'+$fixtureId+'.iso')
$unusedOutput=Join-Path $root ('Output\PipelineGuardUnused-'+$fixtureId+'.iso')
$nonexistentBuildRoot=Join-Path $root ('Work\PipelineGuardMissing-'+$fixtureId)
$outputDirectory=Join-Path $root 'Output'
$logsDirectory=Join-Path $root 'Logs'
$createdOutputDirectory= -not (Test-Path -LiteralPath $outputDirectory -PathType Container)
if($createdOutputDirectory){New-Item -ItemType Directory -Path $outputDirectory -Force|Out-Null}
if(-not(Test-Path -LiteralPath $logsDirectory -PathType Container)){New-Item -ItemType Directory -Path $logsDirectory -Force|Out-Null}
New-Item -ItemType Directory -Path $existingBuildRoot -Force|Out-Null
Set-Content -LiteralPath $existingIso -Value 'Temporary release-pipeline guard fixture; not an ISO.' -Encoding ASCII
$checks=@(
    [pscustomobject]@{Name='existing build workspace';BuildRoot=$existingBuildRoot;OutputPath=$unusedOutput;Expected='Refusing to reuse an existing build workspace'},
    [pscustomobject]@{Name='existing ISO destination';BuildRoot=$nonexistentBuildRoot;OutputPath=$existingIso;Expected='Refusing to overwrite existing ISO'}
)
$passed=0
$results=[System.Collections.Generic.List[object]]::new()
try{
    foreach($check in $checks){
        $stdout=Join-Path $env:TEMP ('BAKA-PipelineGuard-'+[Guid]::NewGuid().ToString('N')+'.out')
        $stderr=Join-Path $env:TEMP ('BAKA-PipelineGuard-'+[Guid]::NewGuid().ToString('N')+'.err')
        $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $pipeline),'-BuildRoot',('"{0}"' -f $check.BuildRoot),'-OutputPath',('"{0}"' -f $check.OutputPath))
        $process=Start-Process -FilePath $powershell -ArgumentList $arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $combined=(Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)+' '+(Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue)
        Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue
        if($process.ExitCode -eq 0 -or $combined -notmatch [regex]::Escape($check.Expected)){throw "Pipeline did not reject $($check.Name) before starting a build. Exit=$($process.ExitCode); Output=$combined"}
        Write-Output "PASS: Pipeline rejected $($check.Name) without starting build stages."
        $results.Add([pscustomobject]@{Name=$check.Name;Passed=$true;ExpectedGuard=$check.Expected;ExitCode=$process.ExitCode})
        $passed++
    }
}finally{
    if(Test-Path -LiteralPath $existingIso -PathType Leaf){Remove-Item -LiteralPath $existingIso -Force}
    if((Test-Path -LiteralPath $existingBuildRoot -PathType Container) -and -not (Get-ChildItem -LiteralPath $existingBuildRoot -Force)){Remove-Item -LiteralPath $existingBuildRoot -Force}
    if($createdOutputDirectory -and (Test-Path -LiteralPath $outputDirectory -PathType Container) -and -not (Get-ChildItem -LiteralPath $outputDirectory -Force)){Remove-Item -LiteralPath $outputDirectory -Force}
}
Write-Output "RESULT: $passed/2 release-pipeline preservation guards passed."
$report=[pscustomobject]@{schemaVersion=1;test='Release pipeline preservation guards';result=if($passed -eq 2){'Passed'}else{'Failed'};completedAt=(Get-Date).ToString('o');passed=$passed;total=2;cases=@($results)}
$reportPath=Join-Path $root ('Logs\ReleasePipelineGuards-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json')
$report|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Output "REPORT: $reportPath"
