Set-StrictMode -Version Latest

function Get-BakaSystemMetrics {
    [CmdletBinding()]
    param()
    $cpu=$null;$memoryUsed=$null;$memoryTotal=$null;$diskFree=$null;$diskTotal=$null;$networkReceive=$null;$networkSend=$null
    $cpuError=$null;$memoryError=$null;$diskError=$null;$networkError=$null
    try {
        $processor=Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop|Select-Object -First 1
        if($processor -and $null -ne $processor.PercentProcessorTime){$cpu=[math]::Round([math]::Max(0,[math]::Min(100,[double]$processor.PercentProcessorTime)),0)}
        else{$cpuError='CPU utilization is unavailable from Windows performance data.'}
    }catch{$cpuError='CPU utilization is unavailable from Windows performance data.'}
    try {
        $os=Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $memoryTotal=[math]::Round(([double]$os.TotalVisibleMemorySize/1024),0)
        $memoryFree=[math]::Round(([double]$os.FreePhysicalMemory/1024),0)
        if($memoryTotal -gt 0){$memoryUsed=[math]::Max(0,$memoryTotal-$memoryFree)}
        else{$memoryError='Memory totals are unavailable from Windows.'}
    }catch{$memoryError='Memory totals are unavailable from Windows.'}
    try {
        $device=$env:SystemDrive.Replace('\','')
        $drive=Get-CimInstance -ClassName Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $device) -ErrorAction Stop|Select-Object -First 1
        if($drive){$diskFree=[math]::Round(([double]$drive.FreeSpace/1GB),1);$diskTotal=[math]::Round(([double]$drive.Size/1GB),1)}
        else{$diskError='System-drive free space is unavailable.'}
    }catch{$diskError='System-drive free space is unavailable.'}
    try {
        $interfaces=@(Get-CimInstance -Namespace root\cimv2 -ClassName Win32_PerfFormattedData_Tcpip_NetworkInterface -ErrorAction Stop|Where-Object {$_.Name -notmatch 'Loopback|isatap|Teredo'})
        if($interfaces.Count){
            $networkReceive=[math]::Round((($interfaces|Measure-Object -Property BytesReceivedPersec -Sum).Sum/1KB),1)
            $networkSend=[math]::Round((($interfaces|Measure-Object -Property BytesSentPersec -Sum).Sum/1KB),1)
        }else{$networkError='Network throughput is unavailable from Windows performance data.'}
    }catch{$networkError='Network throughput is unavailable from Windows performance data.'}
    $gpu=$null;$gpuError='GPU engine telemetry is unavailable on this system.'
    try {
        $engines=@(Get-CimInstance -Namespace root\cimv2 -ClassName Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop)
        $samples=@($engines|ForEach-Object { if($_.PSObject.Properties.Name -contains 'UtilizationPercentage' -and $null -ne $_.UtilizationPercentage){[double]$_.UtilizationPercentage} })
        if($samples.Count){$gpu=[math]::Round([math]::Min(100,(($samples|Measure-Object -Maximum).Maximum)),0);$gpuError=$null}
    }catch{ }
    [pscustomobject]@{
        CapturedAt=(Get-Date).ToString('o');CpuPercent=$cpu;CpuError=$cpuError
        MemoryUsedMiB=$memoryUsed;MemoryTotalMiB=$memoryTotal;MemoryError=$memoryError
        DiskFreeGiB=$diskFree;DiskTotalGiB=$diskTotal;DiskError=$diskError
        NetworkReceiveKiBs=$networkReceive;NetworkSendKiBs=$networkSend;NetworkError=$networkError
        GpuEnginePeakPercent=$gpu;GpuError=$gpuError;GpuTemperatureC=$null;GpuTemperatureError='GPU temperature is not exposed by a reliable built-in Windows sensor API.'
    }
}

Export-ModuleMember -Function Get-BakaSystemMetrics
