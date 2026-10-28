[CmdletBinding()]
param([switch]$RegisterTask,[switch]$WaitForOobe)
$ErrorActionPreference='Stop'
# Boot straight to the desktop for the passwordless BAKA account.
# Windows 11 26H2 left the answer-file AutoLogon at the lock screen in VMware testing, and writing the
# Winlogon values during specialize stalled OOBE (OOBE uses its own temporary sign-in). So BAKA:
#   1. -RegisterTask (specialize): registers a SYSTEM startup task and changes nothing else.
#   2. -WaitForOobe (startup task): waits until OOBE has finished and the BAKA account exists, writes the
#      Winlogon automatic sign-in values, removes itself, and restarts once so the first sign-in is automatic.
# No password is stored: the BAKA account has none.
$root=Join-Path $env:ProgramData 'BAKA'
$taskName='BAKA-EnableAutoSignIn'
$logDirectory=Join-Path $root 'Logs'
if(-not (Test-Path -LiteralPath $logDirectory)){New-Item -ItemType Directory -Path $logDirectory -Force|Out-Null}
$log=Join-Path $logDirectory 'Enable-AutoSignIn.log'
function Write-AutoSignInLog([string]$Message){Add-Content -LiteralPath $log -Value ('{0} {1}' -f (Get-Date -Format o),$Message) -Encoding UTF8}
$accountPath=Join-Path $root 'AccountSetup.json'
if(-not (Test-Path -LiteralPath $accountPath -PathType Leaf)){Write-AutoSignInLog 'AccountSetup.json missing; skipped.';return}
$account=Get-Content -LiteralPath $accountPath -Raw|ConvertFrom-Json
if(-not $account.autoLogon){Write-AutoSignInLog 'autoLogon disabled in AccountSetup.json; skipped.';return}
$userName=[string]$account.localAccount.name
# The answer file's oobeSystem UserAccounts creates the account (that is what makes OOBE skip its account page).
# After OOBE this makes sure it really has an empty password that never expires and is an enabled administrator,
# because VMware testing once showed an answer-file account whose empty password was rejected.
function Set-BakaAccountPasswordless{
    try{
        Set-LocalUser -Name $userName -Password ([securestring]::new()) -PasswordNeverExpires $true -ErrorAction Stop
        Enable-LocalUser -Name $userName -ErrorAction Stop
        # S-1-5-32-544 is the built-in Administrators group in every language.
        if(-not (Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction SilentlyContinue|Where-Object {$_.Name -match ('\\'+[regex]::Escape($userName)+'$')})){Add-LocalGroupMember -SID 'S-1-5-32-544' -Member $userName -ErrorAction Stop}
        Write-AutoSignInLog "Account '$userName': empty password, never expires, enabled administrator."
    }catch{Write-AutoSignInLog "Account '$userName' could not be normalized: $($_.Exception.Message)"}
}
if($RegisterTask){
    $powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $action=New-ScheduledTaskAction -Execute $powershell -Argument ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -WaitForOobe' -f $PSCommandPath)
    $trigger=New-ScheduledTaskTrigger -AtStartup
    $principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2) -StartWhenAvailable
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force|Out-Null
    Write-AutoSignInLog 'Startup task registered; waiting for OOBE to finish on the next boots.'
    return
}
if($WaitForOobe){
    $deadline=(Get-Date).AddMinutes(110)
    while((Get-Date) -lt $deadline){
        $setup=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\Setup' -ErrorAction SilentlyContinue
        $oobeDone=($setup -and [int]$setup.SystemSetupInProgress -eq 0 -and [int]$setup.OOBEInProgress -eq 0 -and [int]$setup.SetupType -eq 0)
        $userReady=[bool](Get-LocalUser -Name $userName -ErrorAction SilentlyContinue)
        if($oobeDone -and $userReady){break}
        Start-Sleep -Seconds 10
    }
    if(-not $userReady){Write-AutoSignInLog "Account '$userName' never appeared; automatic sign-in not configured.";return}
    Set-BakaAccountPasswordless
}
$winlogon='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$alreadyOn=((Get-ItemProperty -LiteralPath $winlogon -Name AutoAdminLogon -ErrorAction SilentlyContinue).AutoAdminLogon -eq '1' -and (Get-ItemProperty -LiteralPath $winlogon -Name DefaultUserName -ErrorAction SilentlyContinue).DefaultUserName -eq $userName -and $null -eq (Get-ItemProperty -LiteralPath $winlogon -Name AutoLogonCount -ErrorAction SilentlyContinue))
New-ItemProperty -LiteralPath $winlogon -Name 'AutoAdminLogon' -Value '1' -PropertyType String -Force|Out-Null
New-ItemProperty -LiteralPath $winlogon -Name 'DefaultUserName' -Value $userName -PropertyType String -Force|Out-Null
New-ItemProperty -LiteralPath $winlogon -Name 'DefaultDomainName' -Value $env:COMPUTERNAME -PropertyType String -Force|Out-Null
New-ItemProperty -LiteralPath $winlogon -Name 'DefaultPassword' -Value '' -PropertyType String -Force|Out-Null
Remove-ItemProperty -LiteralPath $winlogon -Name 'AutoLogonCount' -ErrorAction SilentlyContinue
$passwordless='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device'
if(-not (Test-Path -LiteralPath $passwordless)){New-Item -Path $passwordless -Force|Out-Null}
New-ItemProperty -LiteralPath $passwordless -Name 'DevicePasswordLessBuildVersion' -Value 0 -PropertyType DWord -Force|Out-Null
Write-AutoSignInLog ("Automatic sign-in configured for local account '{0}'." -f $userName)
if($WaitForOobe){
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    $signedIn=[bool](Get-Process explorer -IncludeUserName -ErrorAction SilentlyContinue|Where-Object {$_.UserName -match [regex]::Escape($userName)})
    if(-not $signedIn -and -not $alreadyOn){Write-AutoSignInLog 'Restarting once so Windows signs in automatically.';Restart-Computer -Force}
}
