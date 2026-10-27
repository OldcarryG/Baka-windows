$ErrorActionPreference='Stop'
$register=Join-Path $env:ProgramData 'BAKA\Scripts\Register-FirstLogonTask.ps1'
& $register
# Make sure the post-OOBE automatic sign-in task exists (it changes nothing until OOBE has finished).
$autoSignIn=Join-Path $env:ProgramData 'BAKA\Scripts\Enable-AutoSignIn.ps1'
if(Test-Path -LiteralPath $autoSignIn -PathType Leaf){try{& $autoSignIn -RegisterTask}catch{}}
