Set-StrictMode -Version Latest

function Get-BakaCompanionMutexName {
    $sid=[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    'Local\BAKA.DesktopCompanion.{0}' -f ($sid -replace '[^A-Za-z0-9_.-]','_')
}

function Enter-BakaCompanionInstance {
    [CmdletBinding()]
    param([string]$Name=(Get-BakaCompanionMutexName))
    $mutex=[System.Threading.Mutex]::new($false,$Name)
    $acquired=$false
    try {
        try { $acquired=$mutex.WaitOne(0) }
        catch [System.Threading.AbandonedMutexException] { $acquired=$true }
        if (-not $acquired) { $mutex.Dispose(); return [pscustomobject]@{ Acquired=$false; Mutex=$null; Name=$Name } }
        [pscustomobject]@{ Acquired=$true; Mutex=$mutex; Name=$Name }
    } catch {
        if (-not $acquired) { $mutex.Dispose() }
        throw
    }
}

function Exit-BakaCompanionInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Lock)
    if ($Lock.Acquired -and $Lock.Mutex) {
        try { $Lock.Mutex.ReleaseMutex() }
        finally { $Lock.Mutex.Dispose(); $Lock.Acquired=$false }
    }
}

function Test-BakaCompanionInstanceAvailable {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    $lock=Enter-BakaCompanionInstance -Name $Name
    if (-not $lock.Acquired) { return $false }
    Exit-BakaCompanionInstance -Lock $lock
    return $true
}

Export-ModuleMember -Function Get-BakaCompanionMutexName,Enter-BakaCompanionInstance,Exit-BakaCompanionInstance,Test-BakaCompanionInstanceAvailable
