Set-StrictMode -Version Latest

# BAKA Gaming power plan: a named copy of Windows "Ultimate Performance" (or High performance when the
# hidden Ultimate scheme is unavailable) with gaming-oriented settings. Everything uses powercfg, so the
# plan shows up in Control Panel > Power Options and can be removed with Remove-BakaPowerPlan.

$script:BakaPlanGuid='baca5e00-1d5c-4a6e-9b1f-6a6d6b616b61'
$script:BakaPlanName='BAKA Gaming'
$script:UltimateGuid='e9a42b02-d5df-448d-aa00-03f14749eb61'
$script:HighPerformanceGuid='8c5e7fda-e8bf-4a96-9a85-cf48a8f6b8b5'
$script:BalancedGuid='381b4222-f694-41f0-9685-ff5bb260df2e'
$script:PowerSaverGuid='a1841308-3541-4fab-bc81-f71556f20b4a'

function Get-BakaPowerPlanTweaks {
    # Subgroup GUID, setting GUID, AC value, DC value (DC keeps battery-friendly values on laptops), purpose.
    @(
        [pscustomobject]@{Sub='54533251-82be-4824-96c1-47b60b740d00';Setting='893dee8e-2bef-41e0-89c6-b55d0929964c';Ac=100;Dc=5;Purpose='Minimum processor state 100% on AC (no clock ramp-up delay)'}
        [pscustomobject]@{Sub='54533251-82be-4824-96c1-47b60b740d00';Setting='bc5038f7-23e0-4960-96da-33abaf5935ec';Ac=100;Dc=100;Purpose='Maximum processor state 100%'}
        [pscustomobject]@{Sub='54533251-82be-4824-96c1-47b60b740d00';Setting='0cc5b647-c1df-4637-891a-dec35c318583';Ac=100;Dc=10;Purpose='Core parking off on AC (all cores unparked)'}
        [pscustomobject]@{Sub='54533251-82be-4824-96c1-47b60b740d00';Setting='be337238-0d82-4146-a960-4f3749d470c7';Ac=2;Dc=1;Purpose='Processor boost mode Aggressive on AC'}
        [pscustomobject]@{Sub='501a4d13-42af-4429-9fd1-a8218c268e20';Setting='ee12f906-d277-404b-b6da-e5fa1a576df5';Ac=0;Dc=2;Purpose='PCI Express Link State Power Management off on AC'}
        [pscustomobject]@{Sub='2a737441-1930-4402-8d77-b2bebba308a3';Setting='48e6b7a6-50f5-4782-a5d4-53bb8f07e226';Ac=0;Dc=1;Purpose='USB selective suspend off on AC (no mouse/headset wake lag)'}
        [pscustomobject]@{Sub='0012ee47-9041-4b5d-9b77-535fba8b1442';Setting='6738e2c4-e8a5-4a42-b16a-e040e769756e';Ac=0;Dc=600;Purpose='Never turn off the hard disk on AC'}
        [pscustomobject]@{Sub='19cbb8fa-5279-450e-9fac-8a3d5fedd0c1';Setting='12bbebe6-58d6-4636-95bb-3217ef867c1a';Ac=0;Dc=2;Purpose='Wireless adapter maximum performance on AC'}
        [pscustomobject]@{Sub='238c9fa8-0aad-41ed-83f4-97be242c8f20';Setting='29f6c1db-86da-48c5-9fdb-f2b67b1f44da';Ac=0;Dc=900;Purpose='Never sleep on AC (games and downloads are not interrupted)'}
        [pscustomobject]@{Sub='238c9fa8-0aad-41ed-83f4-97be242c8f20';Setting='9d7815a6-7ee4-497e-8888-515a05f02364';Ac=0;Dc=0;Purpose='Never hibernate on idle'}
        [pscustomobject]@{Sub='7516b95f-f776-4464-8c53-06167f40cc99';Setting='3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e';Ac=900;Dc=300;Purpose='Turn the display off after 15 minutes on AC'}
    )
}

function Invoke-BakaPowerCfg {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $output=& powercfg.exe @Arguments 2>&1|Out-String
    [pscustomobject]@{ExitCode=$LASTEXITCODE;Output=$output.Trim()}
}

function Get-BakaPowerSchemes {
    # Returns installed schemes as GUID/Name/Active objects (powercfg /list).
    $result=Invoke-BakaPowerCfg -Arguments @('/list')
    foreach($line in ($result.Output -split "`r?`n")){
        if($line -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s+\((.+?)\)(\s*\*)?'){
            [pscustomobject]@{Guid=$Matches[1].ToLowerInvariant();Name=$Matches[2];Active=[bool]$Matches[3]}
        }
    }
}

function Get-BakaActivePowerScheme {
    @(Get-BakaPowerSchemes|Where-Object Active)|Select-Object -First 1
}

function Test-BakaBatteryPresent {
    try{return [bool](@(Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop).Count)}catch{return $false}
}

function Install-BakaPowerPlan {
    # Creates (or refreshes) the BAKA Gaming plan. -Activate makes it the active plan.
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([switch]$Activate)
    if(-not $PSCmdlet.ShouldProcess($script:BakaPlanName,'Create power plan')){return $null}
    $existing=@(Get-BakaPowerSchemes|Where-Object {$_.Guid -eq $script:BakaPlanGuid})
    $baseUsed=$null
    if(-not $existing.Count){
        foreach($base in @($script:UltimateGuid,$script:HighPerformanceGuid,$script:BalancedGuid)){
            $copy=Invoke-BakaPowerCfg -Arguments @('/duplicatescheme',$base,$script:BakaPlanGuid)
            if($copy.ExitCode -eq 0 -and @(Get-BakaPowerSchemes|Where-Object {$_.Guid -eq $script:BakaPlanGuid}).Count){$baseUsed=$base;break}
        }
        if(-not $baseUsed){throw 'Windows did not allow BAKA to create its power plan (powercfg /duplicatescheme failed).'}
    }
    [void](Invoke-BakaPowerCfg -Arguments @('/changename',$script:BakaPlanGuid,$script:BakaPlanName,'BAKA tuned plan: full CPU clocks, no core parking, no USB/PCIe power saving on AC power. Battery values stay economical.'))
    $applied=0
    foreach($tweak in Get-BakaPowerPlanTweaks){
        # Some settings do not exist on every machine (for example no Wi-Fi adapter); those are skipped.
        if((Invoke-BakaPowerCfg -Arguments @('/setacvalueindex',$script:BakaPlanGuid,$tweak.Sub,$tweak.Setting,[string]$tweak.Ac)).ExitCode -eq 0){$applied++}
        [void](Invoke-BakaPowerCfg -Arguments @('/setdcvalueindex',$script:BakaPlanGuid,$tweak.Sub,$tweak.Setting,[string]$tweak.Dc))
    }
    if($Activate){[void](Set-BakaActivePowerScheme -Guid $script:BakaPlanGuid)}
    [pscustomobject]@{Guid=$script:BakaPlanGuid;Name=$script:BakaPlanName;BasedOn=$baseUsed;SettingsApplied=$applied;Active=[bool]$Activate}
}

function Set-BakaActivePowerScheme {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory)][string]$Guid)
    if($Guid -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'){throw "Invalid power scheme GUID: $Guid"}
    if(-not $PSCmdlet.ShouldProcess($Guid,'Activate power scheme')){return $false}
    return ((Invoke-BakaPowerCfg -Arguments @('/setactive',$Guid)).ExitCode -eq 0)
}

function Get-BakaPowerPlanChoices {
    # The plans offered in the BAKA Quick Panel, in display order, limited to the ones installed.
    $installed=@(Get-BakaPowerSchemes)
    foreach($choice in @(
        [pscustomobject]@{Guid=$script:BakaPlanGuid;Label='BAKA Gaming'},
        [pscustomobject]@{Guid=$script:BalancedGuid;Label='Balanced'},
        [pscustomobject]@{Guid=$script:PowerSaverGuid;Label='Power saver'}
    )){
        $match=@($installed|Where-Object {$_.Guid -eq $choice.Guid})
        if($match.Count){[pscustomobject]@{Guid=$choice.Guid;Label=$choice.Label;Active=$match[0].Active}}
    }
}

function Remove-BakaPowerPlan {
    # Switches back to Balanced and deletes the BAKA plan.
    [CmdletBinding(SupportsShouldProcess=$true)]
    param()
    if(-not $PSCmdlet.ShouldProcess($script:BakaPlanName,'Remove power plan')){return $false}
    $active=Get-BakaActivePowerScheme
    if($active -and $active.Guid -eq $script:BakaPlanGuid){[void](Set-BakaActivePowerScheme -Guid $script:BalancedGuid)}
    if(@(Get-BakaPowerSchemes|Where-Object {$_.Guid -eq $script:BakaPlanGuid}).Count){return ((Invoke-BakaPowerCfg -Arguments @('/delete',$script:BakaPlanGuid)).ExitCode -eq 0)}
    return $true
}

function Get-BakaPowerPlanGuid { $script:BakaPlanGuid }
function Get-BakaBalancedPowerPlanGuid { $script:BalancedGuid }

Export-ModuleMember -Function Get-BakaPowerPlanTweaks,Get-BakaPowerSchemes,Get-BakaActivePowerScheme,Test-BakaBatteryPresent,Install-BakaPowerPlan,Set-BakaActivePowerScheme,Get-BakaPowerPlanChoices,Remove-BakaPowerPlan,Get-BakaPowerPlanGuid,Get-BakaBalancedPowerPlanGuid
