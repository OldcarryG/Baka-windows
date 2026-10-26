Set-StrictMode -Version Latest

$script:UpdatePolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$script:UpdateAutoPath = Join-Path $script:UpdatePolicyPath 'AU'
$script:UpdateStateDirectory = Join-Path $env:ProgramData 'BAKA'
$script:UpdateStatePath = Join-Path $script:UpdateStateDirectory 'WindowsUpdatePolicyBackup.json'

function Get-BakaPolicyValueState {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Name)
    $keyExists = Test-Path -LiteralPath $Path
    $item = if($keyExists){Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue}else{$null}
    $valueExists = $null -ne $item
    [pscustomobject]@{
        Path=$Path; Name=$Name; KeyExisted=$keyExists; ValueExisted=$valueExists
        Value=if($valueExists){$item.$Name}else{$null}
        Kind=if($valueExists){(Get-Item -LiteralPath $Path).GetValueKind($Name).ToString()}else{$null}
    }
}

function Set-BakaPolicyDword {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][int]$Value)
    if(-not (Test-Path -LiteralPath $Path)){New-Item -Path $Path -Force | Out-Null}
    New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
}

function Invoke-BakaWindowsUpdateControl {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param([Parameter(Mandatory)][ValidateSet('Disable','Restore','Status')][string]$Mode)
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=[Security.Principal.WindowsPrincipal]::new($identity)
    if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Run the update-control action from an elevated PowerShell session.'}
    if($Mode -eq 'Status'){
        $auto = Get-ItemProperty -LiteralPath $script:UpdateAutoPath -Name NoAutoUpdate -ErrorAction SilentlyContinue
        $ui = Get-ItemProperty -LiteralPath $script:UpdatePolicyPath -Name SetDisableUXWUAccess -ErrorAction SilentlyContinue
        return [pscustomobject]@{
            NoAutoUpdate=if($null -ne $auto){$auto.NoAutoUpdate}else{$null}
            SetDisableUXWUAccess=if($null -ne $ui){$ui.SetDisableUXWUAccess}else{$null}
            BackupPresent=(Test-Path -LiteralPath $script:UpdateStatePath)
        }
    }
    if($Mode -eq 'Disable'){
        if($PSCmdlet.ShouldProcess('Windows Update policy','Disable automatic update behavior and restrict the Settings workflow')){
            if(-not (Test-Path -LiteralPath $script:UpdateStatePath)){
                if(-not (Test-Path -LiteralPath $script:UpdateStateDirectory)){New-Item -ItemType Directory -Path $script:UpdateStateDirectory -Force | Out-Null}
                $state=[pscustomobject]@{
                    CreatedAt=(Get-Date).ToString('o')
                    Purpose='Restore the prior values of the two Windows Update policy settings managed by BAKA.'
                    Registry=@(
                        (Get-BakaPolicyValueState -Path $script:UpdateAutoPath -Name 'NoAutoUpdate'),
                        (Get-BakaPolicyValueState -Path $script:UpdatePolicyPath -Name 'SetDisableUXWUAccess')
                    )
                }
                $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:UpdateStatePath -Encoding UTF8
            }
            Set-BakaPolicyDword -Path $script:UpdateAutoPath -Name 'NoAutoUpdate' -Value 1
            Set-BakaPolicyDword -Path $script:UpdatePolicyPath -Name 'SetDisableUXWUAccess' -Value 1
        }
        return [pscustomobject]@{ Mode=$Mode; NoAutoUpdate=1; SetDisableUXWUAccess=1; Backup=$script:UpdateStatePath }
    }
    if(-not (Test-Path -LiteralPath $script:UpdateStatePath)){throw "No BAKA update-policy backup was found at '$script:UpdateStatePath'; refusing to guess what should be restored."}
    if($PSCmdlet.ShouldProcess('Windows Update policy','Restore saved policy values')){
        $state=Get-Content -LiteralPath $script:UpdateStatePath -Raw | ConvertFrom-Json
        foreach($entry in $state.Registry){
            if($entry.ValueExisted){
                if(-not (Test-Path -LiteralPath $entry.Path)){New-Item -Path $entry.Path -Force | Out-Null}
                $kind=[Enum]::Parse([Microsoft.Win32.RegistryValueKind],[string]$entry.Kind)
                New-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -PropertyType $kind -Value $entry.Value -Force | Out-Null
            }elseif(Test-Path -LiteralPath $entry.Path){
                Remove-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -ErrorAction SilentlyContinue
            }
        }
        Remove-Item -LiteralPath $script:UpdateStatePath -Force
        foreach($path in @($script:UpdateAutoPath,$script:UpdatePolicyPath)){
            if(Test-Path -LiteralPath $path){
                $key=Get-Item -LiteralPath $path
                if($key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0){Remove-Item -LiteralPath $path -Force}
            }
        }
    }
    return [pscustomobject]@{ Mode=$Mode; BackupConsumed=$script:UpdateStatePath }
}

Export-ModuleMember -Function Invoke-BakaWindowsUpdateControl
