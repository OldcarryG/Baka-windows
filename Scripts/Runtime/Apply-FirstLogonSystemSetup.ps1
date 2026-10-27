$ErrorActionPreference='Stop'
# Runs once as SYSTEM at the first sign-in after OOBE. Every change here is recorded for the
# "Restore BAKA System Tuning" and "Restore Windows Update" shortcuts.
$root=Join-Path $env:ProgramData 'BAKA'
$log=Join-Path $root 'Logs\FirstLogonSystemSetup.log'
New-Item -ItemType Directory -Path (Split-Path -Parent $log) -Force|Out-Null
Start-Transcript -Path $log -Append|Out-Null
$completed=$false
try{
    Import-Module (Join-Path $root 'Modules\UpdateControl.psm1') -Force
    Import-Module (Join-Path $root 'Modules\SystemTuning.psm1') -Force
    Invoke-BakaWindowsUpdateControl -Mode Disable -Confirm:$false|Out-Null

    # Privacy policies, telemetry services/tasks, and the Baka Browser default-associations policy.
    $privacy=Get-Content -LiteralPath (Join-Path $root 'PrivacySettings.json') -Raw|ConvertFrom-Json
    $tuning=Get-Content -LiteralPath (Join-Path $root 'SystemTuning.json') -Raw|ConvertFrom-Json
    $registryValues=[System.Collections.Generic.List[object]]::new()
    foreach($setting in @($privacy.devicePolicies)){$registryValues.Add($setting)}
    $gamePerformancePath=Join-Path $root 'GamePerformance.json'
    if(Test-Path -LiteralPath $gamePerformancePath -PathType Leaf){foreach($setting in @((Get-Content -LiteralPath $gamePerformancePath -Raw|ConvertFrom-Json).devicePolicies)){$registryValues.Add($setting)}}
    $associations=Join-Path $root 'DefaultAssociations.xml'
    if(Test-Path -LiteralPath $associations -PathType Leaf){$registryValues.Add([pscustomobject]@{path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';name='DefaultAssociationsConfiguration';type='String';value=$associations})}
    $tuningResult=Invoke-BakaSystemTuning -Mode Apply -Configuration $tuning -RegistryValues $registryValues.ToArray() -StatePath (Join-Path $root 'SystemTuningBackup.json') -Confirm:$false
    Write-Output ('System tuning changed {0} item(s); skipped {1} item(s) absent from this build.' -f @($tuningResult.Changed).Count,@($tuningResult.Skipped).Count)

    # Remove the reviewed consumer apps for every user too (the image build removes them offline; this
    # also covers images built before a package was added to the reviewed list).
    $debloat=Get-Content -LiteralPath (Join-Path $root 'Debloat.json') -Raw|ConvertFrom-Json
    if($debloat.enabled){
        foreach($candidate in @($debloat.candidateRemovals|Where-Object approved)){
            foreach($name in @($candidate.packageNames)){
                if($name -match '[*?]'){throw "Wildcards are not allowed in approved package names: $name"}
                $blocked=@($debloat.blockedPackagePatterns|Where-Object {$name -like $_})
                if($blocked.Count){throw "Package '$name' matches a protected pattern."}
                foreach($package in @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue|Where-Object {$_.DisplayName -eq $name})){
                    try{Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction Stop|Out-Null;Write-Output "Removed provisioned package $($package.PackageName)."}catch{Write-Output "Could not remove provisioned package ${name}: $($_.Exception.Message)"}
                }
                foreach($package in @(Get-AppxPackage -AllUsers -Name $name -ErrorAction SilentlyContinue)){
                    try{Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop;Write-Output "Removed installed package $($package.PackageFullName)."}catch{Write-Output "Could not remove installed package ${name}: $($_.Exception.Message)"}
                }
            }
        }
    }

    # Boot straight to the desktop: keep auto sign-in for the passwordless BAKA account created by Setup.
    $accountPath=Join-Path $root 'AccountSetup.json'
    if(Test-Path -LiteralPath $accountPath -PathType Leaf){
        $account=Get-Content -LiteralPath $accountPath -Raw|ConvertFrom-Json
        $userName=[string]$account.localAccount.name
        $localUser=Get-LocalUser -Name $userName -ErrorAction SilentlyContinue
        if($account.autoLogon -and $localUser -and $localUser.Enabled){
            $winlogon='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
            New-ItemProperty -LiteralPath $winlogon -Name 'AutoAdminLogon' -Value '1' -PropertyType String -Force|Out-Null
            New-ItemProperty -LiteralPath $winlogon -Name 'DefaultUserName' -Value $userName -PropertyType String -Force|Out-Null
            New-ItemProperty -LiteralPath $winlogon -Name 'DefaultDomainName' -Value $env:COMPUTERNAME -PropertyType String -Force|Out-Null
            New-ItemProperty -LiteralPath $winlogon -Name 'DefaultPassword' -Value '' -PropertyType String -Force|Out-Null
            Remove-ItemProperty -LiteralPath $winlogon -Name 'AutoLogonCount' -ErrorAction SilentlyContinue
            Write-Output "Automatic sign-in kept for local account $userName."
        }else{Write-Output "Automatic sign-in not configured: local account '$userName' is not present or is disabled."}
        if($account.skipSignInAfterSleep){
            foreach($mode in @('/SETACVALUEINDEX','/SETDCVALUEINDEX')){& powercfg.exe $mode SCHEME_CURRENT SUB_NONE CONSOLELOCK 0|Out-Null}
            & powercfg.exe /SETACTIVE SCHEME_CURRENT|Out-Null
        }
    }

    $shell=New-Object -ComObject WScript.Shell
    $powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $shortcutSpecs=@(
        @{Folder=[Environment]::GetFolderPath('CommonDesktopDirectory');Name='BAKA Install Selected Apps.lnk';Script='Install-SelectedApps.ps1';Description='Install the approved BAKA application packages for this user.'},
        @{Folder=[Environment]::GetFolderPath('CommonDesktopDirectory');Name='BAKA Hardware Drivers.lnk';Script='Install-SelectedDrivers.ps1';Description='Detect hardware and install only approved matching vendor drivers.'},
        @{Folder=[Environment]::GetFolderPath('CommonDesktopDirectory');Name='Restore Windows Update.lnk';Script='Restore-WindowsUpdate.ps1';Description='Restore Windows Update policy settings as an administrator.'},
        @{Folder=[Environment]::GetFolderPath('CommonDesktopDirectory');Name='Restore BAKA System Tuning.lnk';Script='Restore-SystemTuning.ps1';Description='Undo BAKA service, scheduled-task, privacy, and default-browser policy changes.'},
        @{Folder=[Environment]::GetFolderPath('CommonStartup');Name='BAKA Liquid Desktop.lnk';Script='BakaCompanion.ps1';Description='BAKA Liquid dock, Quick Panel, optional bar, widgets, wallpaper, and reversible gaming profiles.';Sta=$true;Hidden=$true}
    )
    $legacyDock=Join-Path ([Environment]::GetFolderPath('CommonStartup')) 'BAKA Gaming Dock.lnk'
    if(Test-Path -LiteralPath $legacyDock -PathType Leaf){Remove-Item -LiteralPath $legacyDock -Force}
    foreach($spec in $shortcutSpecs){
        $link=$shell.CreateShortcut((Join-Path $spec.Folder $spec.Name))
        $link.TargetPath=$powershell
        $arguments='-NoProfile'
        if($spec.Sta){$arguments+=' -STA'}
        if($spec.Hidden){$arguments+=' -WindowStyle Hidden'}
        $link.Arguments=$arguments+' -ExecutionPolicy Bypass -File "'+(Join-Path $root ('Scripts\'+$spec.Script))+'"'
        $link.WorkingDirectory=Join-Path $root 'Scripts'
        $link.Description=$spec.Description
        $link.Save()
    }
    $activeSetup='HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{D7C6DA30-92B6-4B30-A4E0-26A2B2602A10}'
    if(-not(Test-Path -LiteralPath $activeSetup)){New-Item -Path $activeSetup -Force|Out-Null}
    $firstLogon=Join-Path $root 'Scripts\FirstLogon.ps1'
    $stub='"'+$powershell+'" -NoProfile -ExecutionPolicy Bypass -File "'+$firstLogon+'"'
    New-ItemProperty -LiteralPath $activeSetup -Name 'StubPath' -PropertyType String -Value $stub -Force|Out-Null
    New-ItemProperty -LiteralPath $activeSetup -Name 'Version' -PropertyType String -Value '1,0,0,0' -Force|Out-Null
    New-ItemProperty -LiteralPath $activeSetup -Name 'IsInstalled' -PropertyType DWord -Value 1 -Force|Out-Null
    Write-Output 'Applied BAKA policies after OOBE, installed the restoration workflow, and configured the BAKA Liquid desktop companion.'
    $completed=$true
}finally{
    if($completed){Unregister-ScheduledTask -TaskName 'BAKA-InitializeAfterOobe' -Confirm:$false -ErrorAction SilentlyContinue}
    Stop-Transcript|Out-Null
}
