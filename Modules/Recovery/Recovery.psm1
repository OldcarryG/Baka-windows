Set-StrictMode -Version Latest

function Get-BakaRecoveryStatus {
    [CmdletBinding()]
    param()
    $backup=Join-Path $env:ProgramData 'BAKA\WindowsUpdatePolicyBackup.json'
    $paths=@(
        (Join-Path $env:ProgramData 'BAKA\Scripts\Restore-WindowsUpdate.ps1'),
        (Join-Path $env:ProgramData 'BAKA\Scripts\Install-SelectedApps.ps1')
    )
    [pscustomobject]@{
        CapturedAt=(Get-Date).ToString('o')
        WindowsUpdateRestoreAvailable=(Test-Path -LiteralPath $backup)
        RecoveryScripts=@($paths | ForEach-Object { [pscustomobject]@{Path=$_;Present=(Test-Path -LiteralPath $_)} })
        WindowsRecoveryEnvironment=(Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Windows' -Name 'PEFirmwareType' -ErrorAction SilentlyContinue).PEFirmwareType
    }
}

Export-ModuleMember -Function Get-BakaRecoveryStatus
