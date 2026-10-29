Set-StrictMode -Version Latest

# Reversible service, scheduled-task, and policy-value tuning applied once after OOBE.
# Apply records every prior value before changing it; Restore puts each value back exactly.
# Adapters let the tests run against an in-memory system instead of the real host.

function Get-BakaDefaultTuningAdapter {
    @{
        ServiceExists={param([string]$Name) Test-Path -LiteralPath ("HKLM:\SYSTEM\CurrentControlSet\Services\$Name")}
        GetServiceStart={param([string]$Name) $item=Get-ItemProperty -LiteralPath ("HKLM:\SYSTEM\CurrentControlSet\Services\$Name") -Name Start -ErrorAction SilentlyContinue; if($item){[int]$item.Start}else{$null}}
        SetServiceStart={param([string]$Name,[int]$Start)
            $mode=switch($Start){2{'Automatic'}3{'Manual'}4{'Disabled'}default{$null}}
            $applied=$false
            if($mode){try{Set-Service -Name $Name -StartupType $mode -ErrorAction Stop;$applied=$true}catch{}}
            if(-not $applied){Set-ItemProperty -LiteralPath ("HKLM:\SYSTEM\CurrentControlSet\Services\$Name") -Name Start -Value $Start -Type DWord}
            if($Start -eq 4){Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue}
        }
        GetTask={param([string]$Path,[string]$Name) $task=Get-ScheduledTask -TaskPath $Path -TaskName $Name -ErrorAction SilentlyContinue; if($task){[pscustomobject]@{Enabled=($task.State -ne 'Disabled')}}else{$null}}
        SetTaskEnabled={param([string]$Path,[string]$Name,[bool]$Enabled) if($Enabled){Enable-ScheduledTask -TaskPath $Path -TaskName $Name -ErrorAction Stop|Out-Null}else{Disable-ScheduledTask -TaskPath $Path -TaskName $Name -ErrorAction Stop|Out-Null}}
        ReadValue={param([string]$Path,[string]$Name)
            $keyExists=Test-Path -LiteralPath $Path
            $item=if($keyExists){Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue}else{$null}
            $valueExists=$null -ne $item
            [pscustomobject]@{KeyExisted=$keyExists;ValueExisted=$valueExists;Value=if($valueExists){$item.$Name}else{$null};Kind=if($valueExists){(Get-Item -LiteralPath $Path).GetValueKind($Name).ToString()}else{$null}}
        }
        WriteValue={param([string]$Path,[string]$Name,$Value,[string]$Kind) if(-not (Test-Path -LiteralPath $Path)){New-Item -Path $Path -Force|Out-Null}; New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType $Kind -Value $Value -Force|Out-Null}
        RemoveValue={param([string]$Path,[string]$Name) if(Test-Path -LiteralPath $Path){Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue}}
        RemoveKeyIfEmpty={param([string]$Path) if(Test-Path -LiteralPath $Path){$key=Get-Item -LiteralPath $Path; if($key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0){Remove-Item -LiteralPath $Path -Force}}}
    }
}

function ConvertTo-BakaServiceStart([string]$StartType){
    switch($StartType){'Automatic'{2}'Manual'{3}'Disabled'{4}default{throw "Unsupported service start type '$StartType'."}}
}

function Read-BakaTuningState([string]$StatePath){
    if(Test-Path -LiteralPath $StatePath -PathType Leaf){
        $state=Get-Content -LiteralPath $StatePath -Raw|ConvertFrom-Json
        return [pscustomobject]@{CreatedAt=$state.CreatedAt;Services=@($state.Services);Tasks=@($state.Tasks);Registry=@($state.Registry)}
    }
    [pscustomobject]@{CreatedAt=(Get-Date).ToString('o');Services=@();Tasks=@();Registry=@()}
}

function Save-BakaTuningState([string]$StatePath,$State){
    $directory=Split-Path -Parent $StatePath
    if(-not (Test-Path -LiteralPath $directory)){New-Item -ItemType Directory -Path $directory -Force|Out-Null}
    $temp=$StatePath+'.tmp'
    [IO.File]::WriteAllText($temp,($State|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $StatePath -Force
}

function Invoke-BakaSystemTuning {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][ValidateSet('Apply','Restore')][string]$Mode,
        [Parameter(Mandatory)][string]$StatePath,
        $Configuration,
        [object[]]$RegistryValues=@(),
        [hashtable]$Adapter=(Get-BakaDefaultTuningAdapter)
    )
    $changed=[System.Collections.Generic.List[string]]::new()
    $skipped=[System.Collections.Generic.List[string]]::new()
    if($Mode -eq 'Apply'){
        if(-not $Configuration){throw 'Apply requires the SystemTuning configuration.'}
        $protected=@($Configuration.protectedServices)
        $state=Read-BakaTuningState $StatePath
        $services=[System.Collections.Generic.List[object]]::new();foreach($entry in @($state.Services)){$services.Add($entry)}
        $tasks=[System.Collections.Generic.List[object]]::new();foreach($entry in @($state.Tasks)){$tasks.Add($entry)}
        $registry=[System.Collections.Generic.List[object]]::new();foreach($entry in @($state.Registry)){$registry.Add($entry)}
        foreach($service in @($Configuration.services)){
            $name=[string]$service.name
            if($name -in $protected){throw "Service '$name' is protected and cannot be tuned."}
            if(-not (& $Adapter.ServiceExists $name)){$skipped.Add("service:$name");continue}
            $target=ConvertTo-BakaServiceStart ([string]$service.startType)
            $current=& $Adapter.GetServiceStart $name
            if($null -eq $current -or $current -eq $target){continue}
            if(-not $PSCmdlet.ShouldProcess($name,"Set service start to $($service.startType)")){continue}
            try{& $Adapter.SetServiceStart $name $target}catch{$skipped.Add("service:$name failed: $($_.Exception.Message)");continue}
            if(-not @($services|Where-Object {$_.Name -eq $name}).Count){$services.Add([pscustomobject]@{Name=$name;PreviousStart=[int]$current})}
            $changed.Add("service:$name=$($service.startType)")
        }
        foreach($task in @($Configuration.scheduledTasks)){
            $id=[string]$task.path+[string]$task.name
            $current=& $Adapter.GetTask ([string]$task.path) ([string]$task.name)
            if(-not $current){$skipped.Add("task:$id");continue}
            if(-not $current.Enabled){continue}
            if(-not $PSCmdlet.ShouldProcess($id,'Disable scheduled task')){continue}
            try{& $Adapter.SetTaskEnabled ([string]$task.path) ([string]$task.name) $false}catch{$skipped.Add("task:$id failed: $($_.Exception.Message)");continue}
            if(-not @($tasks|Where-Object {$_.Path -eq [string]$task.path -and $_.Name -eq [string]$task.name}).Count){$tasks.Add([pscustomobject]@{Path=[string]$task.path;Name=[string]$task.name;WasEnabled=$true})}
            $changed.Add("task:$id")
        }
        foreach($value in @($RegistryValues)){
            $kind=[string]$value.type
            if($kind -notin @('DWord','String')){throw "Unsupported policy value type: $kind"}
            $path=[string]$value.path;$name=[string]$value.name
            $desired=if($kind -eq 'DWord'){[int]$value.value}else{[string]$value.value}
            $prior=& $Adapter.ReadValue $path $name
            if($prior.ValueExisted -and [string]$prior.Kind -eq $kind -and [string]$prior.Value -eq [string]$desired){continue}
            if(-not $PSCmdlet.ShouldProcess("$path\$name","Set $desired")){continue}
            if(-not @($registry|Where-Object {$_.Path -eq $path -and $_.Name -eq $name}).Count){$registry.Add([pscustomobject]@{Path=$path;Name=$name;KeyExisted=[bool]$prior.KeyExisted;ValueExisted=[bool]$prior.ValueExisted;Value=$prior.Value;Kind=$prior.Kind})}
            & $Adapter.WriteValue $path $name $desired $kind
            $changed.Add("registry:$path\$name")
        }
        Save-BakaTuningState $StatePath ([pscustomobject]@{CreatedAt=$state.CreatedAt;Services=@($services.ToArray());Tasks=@($tasks.ToArray());Registry=@($registry.ToArray())})
        return [pscustomobject]@{Mode=$Mode;Changed=@($changed.ToArray());Skipped=@($skipped.ToArray());StatePath=$StatePath}
    }
    if(-not (Test-Path -LiteralPath $StatePath -PathType Leaf)){throw "No BAKA system-tuning backup was found at '$StatePath'; refusing to guess what should be restored."}
    $state=Read-BakaTuningState $StatePath
    $failures=[System.Collections.Generic.List[string]]::new()
    foreach($service in @($state.Services)){
        if(-not $PSCmdlet.ShouldProcess([string]$service.Name,'Restore service start type')){continue}
        try{& $Adapter.SetServiceStart ([string]$service.Name) ([int]$service.PreviousStart);$changed.Add("service:$($service.Name)")}catch{$failures.Add("service:$($service.Name): $($_.Exception.Message)")}
    }
    foreach($task in @($state.Tasks)){
        if(-not $PSCmdlet.ShouldProcess(([string]$task.Path+[string]$task.Name),'Re-enable scheduled task')){continue}
        try{& $Adapter.SetTaskEnabled ([string]$task.Path) ([string]$task.Name) ([bool]$task.WasEnabled);$changed.Add("task:$($task.Path)$($task.Name)")}catch{$failures.Add("task:$($task.Name): $($_.Exception.Message)")}
    }
    foreach($entry in @($state.Registry)){
        if(-not $PSCmdlet.ShouldProcess(([string]$entry.Path+'\'+[string]$entry.Name),'Restore policy value')){continue}
        try{
            if($entry.ValueExisted){& $Adapter.WriteValue ([string]$entry.Path) ([string]$entry.Name) $entry.Value ([string]$entry.Kind)}
            else{& $Adapter.RemoveValue ([string]$entry.Path) ([string]$entry.Name);if(-not $entry.KeyExisted){& $Adapter.RemoveKeyIfEmpty ([string]$entry.Path)}}
            $changed.Add("registry:$($entry.Path)\$($entry.Name)")
        }catch{$failures.Add("registry:$($entry.Name): $($_.Exception.Message)")}
    }
    if($failures.Count){throw ('Some BAKA tuning values could not be restored; the backup was kept: '+($failures -join '; '))}
    Remove-Item -LiteralPath $StatePath -Force
    return [pscustomobject]@{Mode=$Mode;Changed=@($changed.ToArray());Skipped=@();StatePath=$StatePath}
}

Export-ModuleMember -Function Invoke-BakaSystemTuning,Get-BakaDefaultTuningAdapter
