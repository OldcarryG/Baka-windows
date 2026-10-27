$ErrorActionPreference='Stop'
# Runs as SYSTEM during Setup (specialize and SetupComplete), before the first sign-in. Windows 11 24H2+
# does not reliably honor the answer file's AutoLogon for a passwordless local account, so BAKA writes the
# Winlogon automatic sign-in values itself. No password is stored: the BAKA account has none.
$root=Join-Path $env:ProgramData 'BAKA'
$logDirectory=Join-Path $root 'Logs'
if(-not (Test-Path -LiteralPath $logDirectory)){New-Item -ItemType Directory -Path $logDirectory -Force|Out-Null}
$log=Join-Path $logDirectory 'Enable-AutoSignIn.log'
function Write-AutoSignInLog([string]$Message){Add-Content -LiteralPath $log -Value ('{0} {1}' -f (Get-Date -Format o),$Message) -Encoding UTF8}
try{
    $accountPath=Join-Path $root 'AccountSetup.json'
    if(-not (Test-Path -LiteralPath $accountPath -PathType Leaf)){Write-AutoSignInLog 'AccountSetup.json missing; skipped.';return}
    $account=Get-Content -LiteralPath $accountPath -Raw|ConvertFrom-Json
    if(-not $account.autoLogon){Write-AutoSignInLog 'autoLogon disabled in AccountSetup.json; skipped.';return}
    $userName=[string]$account.localAccount.name
    $winlogon='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    New-ItemProperty -LiteralPath $winlogon -Name 'AutoAdminLogon' -Value '1' -PropertyType String -Force|Out-Null
    New-ItemProperty -LiteralPath $winlogon -Name 'DefaultUserName' -Value $userName -PropertyType String -Force|Out-Null
    New-ItemProperty -LiteralPath $winlogon -Name 'DefaultDomainName' -Value '.' -PropertyType String -Force|Out-Null
    New-ItemProperty -LiteralPath $winlogon -Name 'DefaultPassword' -Value '' -PropertyType String -Force|Out-Null
    Remove-ItemProperty -LiteralPath $winlogon -Name 'AutoLogonCount' -ErrorAction SilentlyContinue
    # Windows Hello "passwordless" mode hides and can override automatic sign-in for local accounts.
    $passwordless='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device'
    if(-not (Test-Path -LiteralPath $passwordless)){New-Item -Path $passwordless -Force|Out-Null}
    New-ItemProperty -LiteralPath $passwordless -Name 'DevicePasswordLessBuildVersion' -Value 0 -PropertyType DWord -Force|Out-Null
    Write-AutoSignInLog ("Automatic sign-in configured for local account '{0}'." -f $userName)
}catch{Write-AutoSignInLog ('failed: {0}' -f $_.Exception.Message);throw}
