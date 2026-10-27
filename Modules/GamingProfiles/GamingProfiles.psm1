Set-StrictMode -Version Latest

$script:DefaultProfileValues = @(
    [pscustomobject]@{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name='EnableTransparency'; GamingValue=0 },
    [pscustomobject]@{ Path='HKCU:\Control Panel\Desktop'; Name='MinAnimate'; GamingValue='0' },
    [pscustomobject]@{ Path='HKCU:\Software\Microsoft\GameBar'; Name='AutoGameModeEnabled'; GamingValue=1 },
    [pscustomobject]@{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'; Name='GlobalUserDisabled'; GamingValue=1 },
    [pscustomobject]@{ Path='HKCU:\System\GameConfigStore'; Name='GameDVR_Enabled'; GamingValue=0 }
)

function Get-BakaProfilePaths {
    param([string]$StateDirectory)
    if ([string]::IsNullOrWhiteSpace($StateDirectory)) {
        if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA is unavailable; profile recovery storage cannot be selected safely.' }
        $StateDirectory = Join-Path $env:LOCALAPPDATA 'BAKA'
    }
    $full = [IO.Path]::GetFullPath($StateDirectory)
    [pscustomobject]@{
        Directory = $full
        State = Join-Path $full 'profile-baseline.json'
        StateBackup = Join-Path $full 'profile-baseline.json.bak'
        Marker = Join-Path $full 'active-profile.json'
        MarkerBackup = Join-Path $full 'active-profile.json.bak'
        Log = Join-Path (Join-Path $full 'Logs') 'Profiles.log'
    }
}

function Write-BakaProfileLog {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Message)
    try {
        $directory = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
        Add-Content -LiteralPath $Path -Value ('{0} {1}' -f (Get-Date -Format 'o'),$Message) -Encoding UTF8
    } catch { }
}

function Get-BakaProfileMutexName {
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    return ('Local\BAKA.Profile.{0}' -f ($sid -replace '[^A-Za-z0-9_.-]','_'))
}

function Enter-BakaProfileLock {
    param([int]$TimeoutSeconds = 15)
    $mutex = [System.Threading.Mutex]::new($false,(Get-BakaProfileMutexName))
    $owned = $false
    try {
        try { $owned = $mutex.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds)) }
        catch [System.Threading.AbandonedMutexException] { $owned = $true }
        if (-not $owned) { $mutex.Dispose(); throw "Timed out waiting for the BAKA profile transaction lock after $TimeoutSeconds seconds." }
        return [pscustomobject]@{ Mutex=$mutex; Owned=$true }
    } catch {
        if (-not $owned) { $mutex.Dispose() }
        throw
    }
}

function Exit-BakaProfileLock {
    param([Parameter(Mandatory)]$Lock)
    if ($Lock.Owned) {
        try { $Lock.Mutex.ReleaseMutex() } finally { $Lock.Mutex.Dispose(); $Lock.Owned=$false }
    }
}

function New-BakaRegistryAdapter {
    [pscustomobject]@{
        ReadValue = {
            param([string]$Path,[string]$Name)
            $keyExists = Test-Path -LiteralPath $Path
            if (-not $keyExists) { return [pscustomobject]@{ KeyExisted=$false; ValueExisted=$false; Value=$null; Kind=$null } }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            $names = @($key.GetValueNames())
            $valueExists = @($names | Where-Object { [string]::Equals($_,$Name,[StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
            if (-not $valueExists) { return [pscustomobject]@{ KeyExisted=$true; ValueExisted=$false; Value=$null; Kind=$null } }
            $kind = $key.GetValueKind($Name).ToString()
            $value = $key.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            [pscustomobject]@{ KeyExisted=$true; ValueExisted=$true; Value=$value; Kind=$kind }
        }.GetNewClosure()
        EnsureKey = {
            param([string]$Path)
            if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
        }.GetNewClosure()
        WriteValue = {
            param([string]$Path,[string]$Name,[object]$Value,[string]$Kind)
            $propertyType = [Enum]::Parse([Microsoft.Win32.RegistryValueKind],$Kind,$true)
            New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $propertyType -Force -ErrorAction Stop | Out-Null
        }.GetNewClosure()
        RemoveValue = {
            param([string]$Path,[string]$Name)
            if (Test-Path -LiteralPath $Path) { Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue }
        }.GetNewClosure()
        RemoveKeyIfEmpty = {
            param([string]$Path)
            if (-not (Test-Path -LiteralPath $Path)) { return }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($key.GetValueNames()).Count -eq 0 -and @($key.GetSubKeyNames()).Count -eq 0) { Remove-Item -LiteralPath $Path -Force -ErrorAction Stop }
        }.GetNewClosure()
    }
}

function Invoke-BakaAdapter {
    param([Parameter(Mandatory)]$Adapter,[Parameter(Mandatory)][string]$Method,[object[]]$Arguments=@())
    $call = $Adapter.$Method
    if ($null -eq $call) { throw "Registry adapter does not implement $Method." }
    & $call @Arguments
}

function Write-BakaAtomicJson {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value,[string]$BackupPath)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $temporary = Join-Path $directory ('.{0}.{1}.tmp' -f (Split-Path -Leaf $Path),[Guid]::NewGuid().ToString('N'))
    $json = ConvertTo-Json -InputObject $Value -Depth 12
    [IO.File]::WriteAllText($temporary,$json,(New-Object System.Text.UTF8Encoding($true)))
    $replaceBackup = Join-Path $directory ('.{0}.{1}.old' -f (Split-Path -Leaf $Path),[Guid]::NewGuid().ToString('N'))
    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            if ($BackupPath) { Copy-Item -LiteralPath $Path -Destination $BackupPath -Force }
            [IO.File]::Replace($temporary,$Path,$replaceBackup,$true)
        } else { [IO.File]::Move($temporary,$Path) }
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $replaceBackup) { Remove-Item -LiteralPath $replaceBackup -Force -ErrorAction SilentlyContinue }
    }
}

function Read-BakaJsonWithBackup {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$BackupPath,[Parameter(Mandatory)][string]$Label)
    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in @($Path,$BackupPath)) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        try { return (Get-Content -LiteralPath $candidate -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop) }
        catch { $errors.Add(('{0}: {1}' -f $candidate,$_.Exception.Message)) }
    }
    if ($errors.Count -gt 0) { throw ("Both the primary and backup {0} records are invalid. {1}" -f $Label,($errors -join ' | ')) }
    return $null
}

function Write-BakaProfileMarker {
    param([Parameter(Mandatory)]$Paths,[Parameter(Mandatory)][ValidateSet('Desktop','CompetitiveGaming','Benchmark')][string]$Profile,[string]$Reason='Profile transition')
    $marker = [pscustomobject]@{ SchemaVersion=1; Profile=$Profile; UpdatedAt=(Get-Date).ToString('o'); Reason=$Reason }
    Write-BakaAtomicJson -Path $Paths.Marker -BackupPath $Paths.MarkerBackup -Value $marker
}

function Get-BakaRegistrySnapshots {
    param([Parameter(Mandatory)]$Adapter)
    $snapshots = [System.Collections.Generic.List[object]]::new()
    foreach ($definition in $script:DefaultProfileValues) {
        $current = Invoke-BakaAdapter -Adapter $Adapter -Method 'ReadValue' -Arguments @([string]$definition.Path,[string]$definition.Name)
        $snapshots.Add([pscustomobject]@{
            Path=[string]$definition.Path; Name=[string]$definition.Name
            KeyExisted=[bool]$current.KeyExisted; ValueExisted=[bool]$current.ValueExisted
            Value=$current.Value; Kind=$current.Kind
        })
    }
    return $snapshots.ToArray()
}

function Get-BakaProfileState {
    param([Parameter(Mandatory)]$Paths)
    Read-BakaJsonWithBackup -Path $Paths.State -BackupPath $Paths.StateBackup -Label 'profile recovery'
}

function Restore-BakaProfileBaselineCore {
    param([Parameter(Mandatory)]$Paths,[Parameter(Mandatory)]$Adapter,[string]$Reason='Desktop selected')
    $state = Get-BakaProfileState -Paths $Paths
    if ($null -eq $state) {
        $marker = Read-BakaJsonWithBackup -Path $Paths.Marker -BackupPath $Paths.MarkerBackup -Label 'active profile'
        if ($marker -and $marker.Profile -eq 'CompetitiveGaming') {
            throw 'Gaming profile marker exists but its saved original registry values are missing. Refusing to guess restoration values.'
        }
        Write-BakaProfileMarker -Paths $Paths -Profile 'Desktop' -Reason $Reason
        return [pscustomobject]@{ Profile='Desktop'; Restored=$false; Recovered=$false; Changed=@() }
    }
    if ([int]$state.SchemaVersion -ne 2 -or -not $state.Registry -or @($state.Registry).Count -ne $script:DefaultProfileValues.Count) {
        throw 'Profile recovery record has an unsupported schema or incomplete registry snapshot. The UI will stay closed until it can be reviewed.'
    }
    $state | Add-Member -NotePropertyName Phase -NotePropertyValue 'Restoring' -Force
    Write-BakaAtomicJson -Path $Paths.State -BackupPath $Paths.StateBackup -Value $state
    $restoredNames = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $state.Registry) {
        if ($entry.ValueExisted) {
            Invoke-BakaAdapter -Adapter $Adapter -Method 'EnsureKey' -Arguments @([string]$entry.Path)
            Invoke-BakaAdapter -Adapter $Adapter -Method 'WriteValue' -Arguments @([string]$entry.Path,[string]$entry.Name,$entry.Value,[string]$entry.Kind)
        } else {
            Invoke-BakaAdapter -Adapter $Adapter -Method 'RemoveValue' -Arguments @([string]$entry.Path,[string]$entry.Name)
            if (-not $entry.KeyExisted) { Invoke-BakaAdapter -Adapter $Adapter -Method 'RemoveKeyIfEmpty' -Arguments @([string]$entry.Path) }
        }
        $restoredNames.Add([string]$entry.Name)
    }
    Write-BakaProfileMarker -Paths $Paths -Profile 'Desktop' -Reason $Reason
    foreach ($path in @($Paths.State,$Paths.StateBackup)) { if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force -ErrorAction Stop } }
    Write-BakaProfileLog -Path $Paths.Log -Message ('restore profile=Desktop reason="{0}" values={1}' -f $Reason,($restoredNames -join ','))
    [pscustomobject]@{ Profile='Desktop'; Restored=$true; Recovered=($Reason -eq 'Startup recovery'); Changed=@($restoredNames.ToArray()) }
}

function Restore-BakaProfileBaseline {
    [CmdletBinding()]
    param([string]$StateDirectory,[Parameter()][object]$RegistryAdapter,[string]$Reason='Desktop selected')
    $paths = Get-BakaProfilePaths -StateDirectory $StateDirectory
    $adapter = if ($RegistryAdapter) { $RegistryAdapter } else { New-BakaRegistryAdapter }
    $lock = Enter-BakaProfileLock
    try { Restore-BakaProfileBaselineCore -Paths $paths -Adapter $adapter -Reason $Reason }
    catch {
        Write-BakaProfileLog -Path $paths.Log -Message ('restore-failed reason="{0}" error="{1}"' -f $Reason,$_.Exception.Message)
        throw
    } finally { Exit-BakaProfileLock -Lock $lock }
}

function Initialize-BakaGamingProfiles {
    [CmdletBinding()]
    param([string]$StateDirectory,[Parameter()][object]$RegistryAdapter)
    $paths = Get-BakaProfilePaths -StateDirectory $StateDirectory
    $adapter = if ($RegistryAdapter) { $RegistryAdapter } else { New-BakaRegistryAdapter }
    $lock = Enter-BakaProfileLock
    try {
        $result = Restore-BakaProfileBaselineCore -Paths $paths -Adapter $adapter -Reason 'Startup recovery'
        if ($result.Recovered) { Write-BakaProfileLog -Path $paths.Log -Message 'startup-recovered interrupted profile transition before showing UI' }
        $result
    } catch {
        Write-BakaProfileLog -Path $paths.Log -Message ('startup-recovery-failed error="{0}"' -f $_.Exception.Message)
        throw
    } finally { Exit-BakaProfileLock -Lock $lock }
}

function Set-BakaGamingProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Desktop','CompetitiveGaming','Benchmark')][string]$Profile,
        [string]$StateDirectory,
        [Parameter()][object]$RegistryAdapter
    )
    $paths = Get-BakaProfilePaths -StateDirectory $StateDirectory
    $adapter = if ($RegistryAdapter) { $RegistryAdapter } else { New-BakaRegistryAdapter }
    $lock = Enter-BakaProfileLock
    try {
        if ($Profile -eq 'Desktop') { return (Restore-BakaProfileBaselineCore -Paths $paths -Adapter $adapter -Reason 'Desktop selected') }

        $currentMarker = Read-BakaJsonWithBackup -Path $paths.Marker -BackupPath $paths.MarkerBackup -Label 'active profile'
        $currentState = Get-BakaProfileState -Paths $paths
        if ($currentMarker -and $currentMarker.Profile -eq $Profile -and $Profile -eq 'CompetitiveGaming' -and $currentState -and $currentState.Phase -eq 'Applied') {
            return [pscustomobject]@{ Profile=$Profile; Restored=$false; Recovered=$false; Changed=@(); AlreadyActive=$true }
        }
        if ($currentState) { [void](Restore-BakaProfileBaselineCore -Paths $paths -Adapter $adapter -Reason 'Profile transition baseline') }
        elseif ($currentMarker -and $currentMarker.Profile -eq 'CompetitiveGaming') {
            throw 'Cannot start a new profile transition: the active Gaming marker has no recovery snapshot.'
        }
        if ($Profile -eq 'Benchmark') {
            Write-BakaProfileMarker -Paths $paths -Profile 'Benchmark' -Reason 'Benchmark selected; Windows settings unchanged'
            Write-BakaProfileLog -Path $paths.Log -Message 'profile=Benchmark windows-settings=unchanged power-plan=Balanced'
            return [pscustomobject]@{ Profile=$Profile; Restored=$false; Recovered=$false; Changed=@() }
        }

        $snapshots = @(Get-BakaRegistrySnapshots -Adapter $adapter)
        $state = [pscustomobject]@{
            SchemaVersion=2; TransactionId=[Guid]::NewGuid().ToString('N'); TargetProfile=$Profile
            Phase='Prepared'; CapturedAt=(Get-Date).ToString('o'); Registry=$snapshots
        }
        Write-BakaAtomicJson -Path $paths.State -BackupPath $paths.StateBackup -Value $state
        $changed = [System.Collections.Generic.List[string]]::new()
        try {
            foreach ($definition in $script:DefaultProfileValues) {
                Invoke-BakaAdapter -Adapter $adapter -Method 'EnsureKey' -Arguments @([string]$definition.Path)
                $valueKind = if ($definition.GamingValue -is [int]) { 'DWord' } else { 'String' }
                Invoke-BakaAdapter -Adapter $adapter -Method 'WriteValue' -Arguments @([string]$definition.Path,[string]$definition.Name,$definition.GamingValue,$valueKind)
                $changed.Add([string]$definition.Name)
            }
            $state.Phase='Applied'
            Write-BakaAtomicJson -Path $paths.State -BackupPath $paths.StateBackup -Value $state
            Write-BakaProfileMarker -Paths $paths -Profile 'CompetitiveGaming' -Reason 'Gaming profile applied'
             Write-BakaProfileLog -Path $paths.Log -Message ('profile=CompetitiveGaming transaction={0} changed={1} power-plan=Balanced game-mode=enabled background-apps=disabled game-dvr=disabled' -f $state.TransactionId,($changed -join ','))
            return [pscustomobject]@{ Profile=$Profile; Restored=$false; Recovered=$false; Changed=@($changed.ToArray()); AlreadyActive=$false }
        } catch {
            $transitionError = $_.Exception.Message
            try { [void](Restore-BakaProfileBaselineCore -Paths $paths -Adapter $adapter -Reason 'Failed transition rollback') }
            catch { throw "Profile transition failed ($transitionError); rollback also failed ($($_.Exception.Message)). The recovery record was retained for startup retry." }
            Write-BakaProfileLog -Path $paths.Log -Message ('transition-rolled-back profile=CompetitiveGaming error="{0}"' -f $transitionError)
            throw "Profile transition failed and was rolled back: $transitionError"
        }
    } catch {
        Write-BakaProfileLog -Path $paths.Log -Message ('profile-change-failed requested={0} error="{1}"' -f $Profile,$_.Exception.Message)
        throw
    } finally { Exit-BakaProfileLock -Lock $lock }
}

function Resolve-BakaDetectedGame {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][string[]]$RunningProcessNames = @(),
        [AllowEmptyCollection()][object[]]$Definitions = @()
    )
    $running = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $RunningProcessNames) { if (-not [string]::IsNullOrWhiteSpace($name)) { [void]$running.Add($name.Trim()) } }
    foreach ($definition in $Definitions) {
        $processName = [string]$definition.processName
        $displayName = [string]$definition.displayName
        if ([string]::IsNullOrWhiteSpace($processName) -or [string]::IsNullOrWhiteSpace($displayName)) { continue }
        if ($running.Contains($processName.Trim())) { return [pscustomobject]@{ ProcessName=$processName.Trim(); DisplayName=$displayName.Trim() } }
    }
    return $null
}

function Resolve-BakaAnyGame {
    # Detects any game, not only the named titles:
    #   1. a named definition (exact process name),
    #   2. an executable inside a known game library (Steam, Epic, GOG, EA, Ubisoft, Xbox, Riot, Battle.net, Amazon, itch),
    #   3. the foreground app covering its whole monitor (fullscreen or borderless) that is not a known non-game.
    # Launchers, crash handlers, installers, and anti-cheat helpers are ignored. Excluded processes are never matched.
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Processes = @(),
        [Parameter(Mandatory)]$Detection
    )
    $definitions = @($Detection.processes)
    $excluded = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @($Detection.excludedProcesses)) { if ($name) { [void]$excluded.Add([string]$name) } }
    $nonGames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @($Detection.nonGameProcesses)) { if ($name) { [void]$nonGames.Add([string]$name) } }
    $helperPattern = [string]$Detection.helperPattern
    $candidates = @($Processes | Where-Object { $_ -and $_.ProcessName -and -not $excluded.Contains([string]$_.ProcessName) })
    $named = Resolve-BakaDetectedGame -RunningProcessNames @($candidates | ForEach-Object { [string]$_.ProcessName }) -Definitions $definitions
    if ($named) { return [pscustomobject]@{ ProcessName=$named.ProcessName; DisplayName=$named.DisplayName; Reason='Named' } }
    if ($Detection.mode -ne 'AllGames') { return $null }
    foreach ($process in $candidates) {
        $name = [string]$process.ProcessName
        $path = [string]$process.Path
        if (-not $path -or $nonGames.Contains($name) -or ($helperPattern -and $name -match $helperPattern)) { continue }
        foreach ($pattern in @($Detection.libraryPathPatterns)) {
            if ($pattern -and $path.IndexOf([string]$pattern,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
                return [pscustomobject]@{ ProcessName=$name; DisplayName=$name; Reason='GameLibrary' }
            }
        }
    }
    if ($Detection.fullscreenDetection) {
        foreach ($process in @($candidates | Where-Object { $_.IsForegroundFullscreen })) {
            $name = [string]$process.ProcessName
            if ($nonGames.Contains($name) -or ($helperPattern -and $name -match $helperPattern)) { continue }
            return [pscustomobject]@{ ProcessName=$name; DisplayName=$name; Reason='Fullscreen' }
        }
    }
    return $null
}

Export-ModuleMember -Function Set-BakaGamingProfile,Restore-BakaProfileBaseline,Initialize-BakaGamingProfiles,Resolve-BakaDetectedGame,Resolve-BakaAnyGame
