Set-StrictMode -Version Latest

function Get-BakaHardwareInventory {
    [CmdletBinding()]
    param()
    $os = Get-CimInstance Win32_OperatingSystem
    $system = Get-CimInstance Win32_ComputerSystem
    $processors = @(Get-CimInstance Win32_Processor | ForEach-Object {
        [pscustomobject]@{ Name=$_.Name.Trim(); Vendor=$_.Manufacturer; Cores=$_.NumberOfCores; LogicalProcessors=$_.NumberOfLogicalProcessors }
    })
    $memory = [math]::Round(((Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1GB), 1)
    $graphics = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name } | ForEach-Object {
        [pscustomobject]@{ Name=$_.Name.Trim(); DriverVersion=$_.DriverVersion }
    })
    $disks = @(Get-CimInstance Win32_DiskDrive | ForEach-Object {
        [pscustomobject]@{ Model=$_.Model; InterfaceType=$_.InterfaceType; SizeGiB=[math]::Round($_.Size / 1GB, 1) }
    })
    $network = @(Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.PhysicalAdapter -and $_.NetEnabled } | ForEach-Object {
        [pscustomobject]@{ Name=$_.Name; Manufacturer=$_.Manufacturer; AdapterType=$_.AdapterType }
    })
    $tpm = $null
    if (Get-Command Get-Tpm -ErrorAction SilentlyContinue) {
        try { $t = Get-Tpm; $tpm = [pscustomobject]@{ Present=$t.TpmPresent; Ready=$t.TpmReady; Manufacturer=$t.ManufacturerIdTxt } } catch { $tpm = [pscustomobject]@{ Present=$null; Ready=$null; Manufacturer=$null } }
    }
    $secureBoot = $null
    if (Get-Command Confirm-SecureBootUEFI -ErrorAction SilentlyContinue) {
        try { $secureBoot = [bool](Confirm-SecureBootUEFI -ErrorAction Stop) } catch { $secureBoot = $null }
    }
    [pscustomobject]@{
        CapturedAt = (Get-Date).ToString('o')
        OperatingSystem = [pscustomobject]@{ Caption=$os.Caption; Version=$os.Version; Build=$os.BuildNumber; Architecture=$os.OSArchitecture }
        Platform = [pscustomobject]@{ Manufacturer=$system.Manufacturer; Model=$system.Model }
        Processors = $processors
        MemoryGiB = $memory
        Graphics = $graphics
        Disks = $disks
        ActiveNetworkAdapters = $network
        Tpm = $tpm
        SecureBoot = $secureBoot
    }
}

function Get-BakaHardwareFamilies {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Inventory)
    $families = [System.Collections.Generic.List[string]]::new()
    foreach ($cpu in $Inventory.Processors) {
        if ($cpu.Vendor -match 'Intel' -or $cpu.Name -match 'Intel') { $families.Add('Intel') }
        if ($cpu.Vendor -match 'AMD' -or $cpu.Name -match 'AMD') { $families.Add('AMD CPU') }
    }
    foreach ($gpu in $Inventory.Graphics) {
        if ($gpu.Name -match 'NVIDIA') { $families.Add('NVIDIA GPU') }
        if ($gpu.Name -match 'AMD|Radeon') { $families.Add('AMD Radeon GPU') }
        if ($gpu.Name -match 'Intel') { $families.Add('Intel GPU') }
    }
    $pnp = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue)
    if ($pnp.Name -match 'Bluetooth') { $families.Add('Bluetooth') }
    return @($families | Select-Object -Unique)
}

Export-ModuleMember -Function Get-BakaHardwareInventory,Get-BakaHardwareFamilies
