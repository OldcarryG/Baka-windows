[CmdletBinding()]
param()
# Exercises apply/restore of services, scheduled tasks, and policy values against an in-memory system.
# No host service, task, or registry value is read or changed.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Modules\SystemTuning.psm1') -Force
$testRoot=Join-Path $env:TEMP ('BAKA-TuningTests-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force|Out-Null
$passed=[System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
try{
    $services=@{DiagTrack=2;MapsBroker=2;Fax=3;WerSvc=3}
    $tasks=@{'\T\Appraiser'=$true;'\T\Consolidator'=$false}
    $registry=@{'HKLM:\P|AllowTelemetry'=[pscustomobject]@{KeyExisted=$true;ValueExisted=$true;Value=3;Kind='DWord'}}
    $adapter=@{
        ServiceExists={param($Name)$services.ContainsKey($Name)}.GetNewClosure()
        GetServiceStart={param($Name)$services[$Name]}.GetNewClosure()
        SetServiceStart={param($Name,$Start)$services[$Name]=[int]$Start}.GetNewClosure()
        GetTask={param($Path,$Name)$key=$Path+$Name;if($tasks.ContainsKey($key)){[pscustomobject]@{Enabled=$tasks[$key]}}else{$null}}.GetNewClosure()
        SetTaskEnabled={param($Path,$Name,$Enabled)$tasks[$Path+$Name]=[bool]$Enabled}.GetNewClosure()
        ReadValue={param($Path,$Name)$key=$Path+'|'+$Name;if($registry.ContainsKey($key)){$registry[$key]}else{[pscustomobject]@{KeyExisted=$false;ValueExisted=$false;Value=$null;Kind=$null}}}.GetNewClosure()
        WriteValue={param($Path,$Name,$Value,$Kind)$registry[$Path+'|'+$Name]=[pscustomobject]@{KeyExisted=$true;ValueExisted=$true;Value=$Value;Kind=$Kind}}.GetNewClosure()
        RemoveValue={param($Path,$Name)$registry.Remove($Path+'|'+$Name)}.GetNewClosure()
        RemoveKeyIfEmpty={param($Path)}.GetNewClosure()
    }
    $config=[pscustomobject]@{
        services=@([pscustomobject]@{name='DiagTrack';startType='Disabled'},[pscustomobject]@{name='MapsBroker';startType='Disabled'},[pscustomobject]@{name='Fax';startType='Disabled'},[pscustomobject]@{name='Missing';startType='Disabled'})
        scheduledTasks=@([pscustomobject]@{path='\T\';name='Appraiser'},[pscustomobject]@{path='\T\';name='Consolidator'},[pscustomobject]@{path='\T\';name='Absent'})
        protectedServices=@('WinDefend','wuauserv')
    }
    $values=@([pscustomobject]@{path='HKLM:\P';name='AllowTelemetry';type='DWord';value=1},[pscustomobject]@{path='HKLM:\Q';name='TurnOffWindowsCopilot';type='DWord';value=1},[pscustomobject]@{path='HKLM:\S';name='DefaultAssociationsConfiguration';type='String';value='C:\ProgramData\BAKA\DefaultAssociations.xml'})
    $state=Join-Path $testRoot 'SystemTuningBackup.json'
    $result=Invoke-BakaSystemTuning -Mode Apply -Configuration $config -RegistryValues $values -StatePath $state -Adapter $adapter -Confirm:$false
    Assert-True ($services.DiagTrack -eq 4 -and $services.MapsBroker -eq 4 -and $services.Fax -eq 4 -and $services.WerSvc -eq 3) 'Configured services were not disabled, or an unlisted service changed.'
    Assert-True (-not $tasks['\T\Appraiser'] -and -not $tasks['\T\Consolidator']) 'Enabled telemetry task was not disabled.'
    Assert-True ($registry['HKLM:\P|AllowTelemetry'].Value -eq 1 -and $registry['HKLM:\Q|TurnOffWindowsCopilot'].Value -eq 1 -and $registry['HKLM:\S|DefaultAssociationsConfiguration'].Kind -eq 'String') 'Policy values were not written with their declared types.'
    Assert-True (@($result.Skipped) -contains 'service:Missing' -and @($result.Skipped) -contains 'task:\T\Absent') 'Absent services and tasks were not reported as skipped.'
    $passed.Add('Apply disables listed services and tasks, writes typed policies, and skips absent items.')

    $second=Invoke-BakaSystemTuning -Mode Apply -Configuration $config -RegistryValues $values -StatePath $state -Adapter $adapter -Confirm:$false
    Assert-True (@($second.Changed).Count -eq 0) 'A repeated apply changed values again.'
    $backup=Get-Content -LiteralPath $state -Raw|ConvertFrom-Json
    Assert-True (@($backup.Services).Count -eq 3 -and @($backup.Tasks).Count -eq 1 -and @($backup.Registry).Count -eq 3) 'A repeated apply duplicated or lost backup entries.'
    $passed.Add('A repeated apply is idempotent and keeps the original backup.')

    Invoke-BakaSystemTuning -Mode Restore -StatePath $state -Adapter $adapter -Confirm:$false|Out-Null
    Assert-True ($services.DiagTrack -eq 2 -and $services.MapsBroker -eq 2 -and $services.Fax -eq 3) 'Service start types were not restored exactly.'
    Assert-True ($tasks['\T\Appraiser'] -and -not $tasks['\T\Consolidator']) 'Task state was not restored exactly; a task that was already disabled must stay disabled.'
    Assert-True ($registry['HKLM:\P|AllowTelemetry'].Value -eq 3 -and -not $registry.ContainsKey('HKLM:\Q|TurnOffWindowsCopilot') -and -not $registry.ContainsKey('HKLM:\S|DefaultAssociationsConfiguration')) 'Policy values were not restored or removed.'
    Assert-True (-not (Test-Path -LiteralPath $state)) 'The backup was not consumed after a successful restore.'
    $passed.Add('Restore returns every service, task, and policy value to its prior state and consumes the backup.')

    $protectedConfig=[pscustomobject]@{services=@([pscustomobject]@{name='WinDefend';startType='Disabled'});scheduledTasks=@();protectedServices=@('WinDefend')}
    $services.WinDefend=2;$threw=$false
    try{Invoke-BakaSystemTuning -Mode Apply -Configuration $protectedConfig -StatePath (Join-Path $testRoot 'p.json') -Adapter $adapter -Confirm:$false|Out-Null}catch{$threw=$true}
    Assert-True ($threw -and $services.WinDefend -eq 2) 'A protected service was changed.'
    $threw=$false
    try{Invoke-BakaSystemTuning -Mode Restore -StatePath (Join-Path $testRoot 'none.json') -Adapter $adapter -Confirm:$false|Out-Null}catch{$threw=$true}
    Assert-True $threw 'Restore without a backup did not refuse to guess.'
    $passed.Add('Protected services are refused and restore without a backup is refused.')
}finally{Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue}
$passed|ForEach-Object {Write-Output "PASS: $_"}
Write-Output ("RESULT: {0}/4 system-tuning checks passed." -f $passed.Count)
