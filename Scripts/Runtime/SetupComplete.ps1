$ErrorActionPreference='Stop'
$register=Join-Path $env:ProgramData 'BAKA\Scripts\Register-FirstLogonTask.ps1'
& $register
# Re-apply after oobeSystem so Setup's own AutoLogon handling cannot leave a one-shot logon count behind.
$autoSignIn=Join-Path $env:ProgramData 'BAKA\Scripts\Enable-AutoSignIn.ps1'
if(Test-Path -LiteralPath $autoSignIn -PathType Leaf){try{& $autoSignIn}catch{}}
