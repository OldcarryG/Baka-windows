[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Modules\SystemMonitoring.psm1') -Force
$metrics=Get-BakaSystemMetrics
if(-not $metrics.CapturedAt){throw 'System metrics did not include a capture time.'}
if($null -ne $metrics.CpuPercent -and ($metrics.CpuPercent -lt 0 -or $metrics.CpuPercent -gt 100)){throw 'CPU utilization was outside the valid range.'}
if($null -ne $metrics.GpuEnginePeakPercent -and ($metrics.GpuEnginePeakPercent -lt 0 -or $metrics.GpuEnginePeakPercent -gt 100)){throw 'GPU engine telemetry was outside the valid range.'}
if($null -ne $metrics.MemoryUsedMiB -and $metrics.MemoryUsedMiB -gt $metrics.MemoryTotalMiB){throw 'Reported memory use exceeded visible physical memory.'}
Write-Output ('PASS: System metrics returned truthful values or explicit unavailable states. CPU={0}; GPU={1}; memory={2}; disk={3}; network={4}' -f $(if($null -eq $metrics.CpuPercent){$metrics.CpuError}else{$metrics.CpuPercent}),$(if($null -eq $metrics.GpuEnginePeakPercent){$metrics.GpuError}else{$metrics.GpuEnginePeakPercent}),$(if($null -eq $metrics.MemoryUsedMiB){$metrics.MemoryError}else{$metrics.MemoryUsedMiB}),$(if($null -eq $metrics.DiskFreeGiB){$metrics.DiskError}else{$metrics.DiskFreeGiB}),$(if($null -eq $metrics.NetworkReceiveKiBs){$metrics.NetworkError}else{$metrics.NetworkReceiveKiBs}))
