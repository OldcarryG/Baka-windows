[CmdletBinding()]
param([switch]$KeepTestData)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Modules\GamingProfiles\GamingProfiles.psm1') -Force
Import-Module (Join-Path $root 'Modules\CompanionInstance.psm1') -Force
$testRoot=Join-Path $env:TEMP ('BAKA-ProfileTests-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force|Out-Null
$passed=[System.Collections.Generic.List[string]]::new()

function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function New-FakeRegistry {
    $state=[pscustomobject]@{ Keys=@{}; FailName=$null; FailOnce=$false }
    $state.Keys['HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize']=@{ EnableTransparency=[pscustomobject]@{Value=1;Kind='DWord'} }
    $state.Keys['HKCU:\Control Panel\Desktop']=@{ MinAnimate=[pscustomobject]@{Value='1';Kind='String'} }
    $adapter=[pscustomobject]@{
        ReadValue={param($Path,$Name)
            $keyExists=$state.Keys.ContainsKey($Path)
            if(-not $keyExists){return [pscustomobject]@{KeyExisted=$false;ValueExisted=$false;Value=$null;Kind=$null}}
            $key=$state.Keys[$Path]
            if(-not $key.ContainsKey($Name)){return [pscustomobject]@{KeyExisted=$true;ValueExisted=$false;Value=$null;Kind=$null}}
            $item=$key[$Name]
            [pscustomobject]@{KeyExisted=$true;ValueExisted=$true;Value=$item.Value;Kind=$item.Kind}
        }.GetNewClosure()
        EnsureKey={param($Path) if(-not $state.Keys.ContainsKey($Path)){$state.Keys[$Path]=@{}}}.GetNewClosure()
        WriteValue={param($Path,$Name,$Value,$Kind)
            if($state.FailOnce -and $state.FailName -eq $Name){$state.FailOnce=$false;throw "Injected failure writing $Name"}
            if(-not $state.Keys.ContainsKey($Path)){$state.Keys[$Path]=@{}}
            $state.Keys[$Path][$Name]=[pscustomobject]@{Value=$Value;Kind=$Kind}
        }.GetNewClosure()
        RemoveValue={param($Path,$Name) if($state.Keys.ContainsKey($Path)){$state.Keys[$Path].Remove($Name)|Out-Null}}.GetNewClosure()
        RemoveKeyIfEmpty={param($Path) if($state.Keys.ContainsKey($Path) -and $state.Keys[$Path].Count -eq 0){$state.Keys.Remove($Path)|Out-Null}}.GetNewClosure()
        State=$state
    }
    return $adapter
}

try {
    $dir=Join-Path $testRoot 'interrupted'
    $fake=New-FakeRegistry
    $result=Set-BakaGamingProfile -Profile CompetitiveGaming -StateDirectory $dir -RegistryAdapter $fake
    Assert-True ($result.Profile -eq 'CompetitiveGaming') 'Gaming transition did not report its profile.'
    Assert-True ((Test-Path (Join-Path $dir 'profile-baseline.json')) -and (Get-Content (Join-Path $dir 'active-profile.json') -Raw|ConvertFrom-Json).Profile -eq 'CompetitiveGaming') 'Gaming transition did not durably record recovery state.'
    Assert-True ($fake.State.Keys['HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'].EnableTransparency.Value -eq 0) 'Gaming transparency change was not applied.'
    $recovery=Initialize-BakaGamingProfiles -StateDirectory $dir -RegistryAdapter $fake
    Assert-True ($recovery.Recovered) 'Startup did not report recovery of the interrupted profile.'
    Assert-True ($fake.State.Keys['HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'].EnableTransparency.Value -eq 1) 'Startup recovery did not restore the original DWORD value.'
    Assert-True ($fake.State.Keys['HKCU:\Control Panel\Desktop'].MinAnimate.Value -eq '1') 'Startup recovery did not restore the original string value.'
    Assert-True (-not (Test-Path (Join-Path $dir 'profile-baseline.json'))) 'Recovery left an active baseline transaction behind.'
    $passed.Add('Interrupted Gaming profile is recovered before UI startup with original types and values.')

    $dir=Join-Path $testRoot 'idempotent'
    $fake=New-FakeRegistry
    [void](Set-BakaGamingProfile -Profile CompetitiveGaming -StateDirectory $dir -RegistryAdapter $fake)
    [void](Restore-BakaProfileBaseline -StateDirectory $dir -RegistryAdapter $fake)
    [void](Restore-BakaProfileBaseline -StateDirectory $dir -RegistryAdapter $fake)
    Assert-True ($fake.State.Keys['HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'].EnableTransparency.Value -eq 1) 'Repeated restore changed the original DWORD.'
    Assert-True ($fake.State.Keys['HKCU:\Control Panel\Desktop'].MinAnimate.Value -eq '1') 'Repeated restore changed the original string.'
    $passed.Add('Restoration is idempotent and preserves exact original values.')

    $dir=Join-Path $testRoot 'failed-transition'
    $fake=New-FakeRegistry
    $fake.State.FailName='MinAnimate';$fake.State.FailOnce=$true
    $failed=$false
    try { [void](Set-BakaGamingProfile -Profile CompetitiveGaming -StateDirectory $dir -RegistryAdapter $fake) } catch { $failed=$true }
    Assert-True $failed 'Injected profile-transition failure was not surfaced.'
    Assert-True ($fake.State.Keys['HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'].EnableTransparency.Value -eq 1) 'Failed transition did not roll back the first registry change.'
    Assert-True ($fake.State.Keys['HKCU:\Control Panel\Desktop'].MinAnimate.Value -eq '1') 'Failed transition did not preserve the second setting.'
    Assert-True (-not (Test-Path (Join-Path $dir 'profile-baseline.json'))) 'Successful rollback left a pending recovery record.'
    $passed.Add('Partial profile transition failure rolls back and retains the Desktop baseline.')

    $dir=Join-Path $testRoot 'missing-value'
    $fake=New-FakeRegistry
    $fake.State.Keys.Remove('HKCU:\Control Panel\Desktop')|Out-Null
    [void](Set-BakaGamingProfile -Profile CompetitiveGaming -StateDirectory $dir -RegistryAdapter $fake)
    [void](Set-BakaGamingProfile -Profile Desktop -StateDirectory $dir -RegistryAdapter $fake)
    Assert-True (-not $fake.State.Keys.ContainsKey('HKCU:\Control Panel\Desktop')) 'Restoration left a newly-created registry key behind.'
    $passed.Add('Missing original keys and values are removed rather than assigned hard-coded defaults.')

    $dir=Join-Path $testRoot 'benchmark'
    $fake=New-FakeRegistry
    [void](Set-BakaGamingProfile -Profile Benchmark -StateDirectory $dir -RegistryAdapter $fake)
    Assert-True ($fake.State.Keys['HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'].EnableTransparency.Value -eq 1) 'Benchmark changed Windows user settings.'
    Assert-True ((Get-Content (Join-Path $dir 'active-profile.json') -Raw|ConvertFrom-Json).Profile -eq 'Benchmark') 'Benchmark marker was not recorded.'
    $passed.Add('Benchmark profile records its state while leaving Windows settings unchanged.')

    $lockName='Local\BAKA.Companion.Test.'+[Guid]::NewGuid().ToString('N')
    $lock=Enter-BakaCompanionInstance -Name $lockName
    Assert-True $lock.Acquired 'First companion launch did not acquire the instance lock.'
    try {
        $runspace=[System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $runspace.Open()
        $powershell=[PowerShell]::Create();$powershell.Runspace=$runspace
        [void]$powershell.AddScript({param($modulePath,$name) Import-Module -Name $modulePath -Force; Test-BakaCompanionInstanceAvailable -Name $name}.GetNewClosure()).AddArgument((Join-Path $root 'Modules\CompanionInstance.psm1')).AddArgument($lockName)
        $available=$powershell.Invoke()
        $powershell.Dispose();$runspace.Dispose()
        Assert-True (-not [bool]$available[-1]) 'Second companion launch was not blocked by the named mutex.'
    } finally { Exit-BakaCompanionInstance -Lock $lock }
    $passed.Add('A second companion instance on another runspace is rejected.')

    $passed|ForEach-Object { Write-Output ('PASS: '+$_) }
    Write-Output ('RESULT: {0}/{0} profile and instance-lock regression checks passed.' -f $passed.Count)
} finally {
    $fullRoot=[IO.Path]::GetFullPath($testRoot)
    $tempRoot=[IO.Path]::GetFullPath($env:TEMP)
    if(-not $KeepTestData -and $fullRoot.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and $fullRoot -match 'BAKA-ProfileTests-[0-9a-f]{32}$') { Remove-Item -LiteralPath $fullRoot -Recurse -Force -ErrorAction SilentlyContinue }
    elseif($KeepTestData) { Write-Output ("Test data retained for diagnosis: {0}" -f $fullRoot) }
}
