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

    # Old Windows tools that newer built-in apps replace (Internet Explorer, the legacy Windows Media
    # Player, WordPad, Steps Recorder, Math Input Panel, Fax and Scan, PowerShell ISE).
    if($debloat.enabled -and $debloat.legacyCapabilities -and $debloat.legacyCapabilities.approved){
        $installed=@(Get-WindowsCapability -Online -ErrorAction SilentlyContinue|Where-Object State -eq 'Installed')
        foreach($entry in @($debloat.legacyCapabilities.names)){
            foreach($cap in @($installed|Where-Object {$_.Name -like ([string]$entry.name+'~*')})){
                try{Remove-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop|Out-Null;Write-Output "Removed legacy capability $($cap.Name) (replaced by $($entry.replacedBy))."}catch{Write-Output "Could not remove $($cap.Name): $($_.Exception.Message)"}
            }
        }
    }
    # Microsoft Edge (the browser). WebView2 is a separate install and is not touched.
    if($debloat.enabled -and $debloat.removeEdge -and $debloat.removeEdge.approved){
        try{
            $edgeRoot=Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application'
            $setup=@(Get-ChildItem -LiteralPath $edgeRoot -Filter setup.exe -Recurse -ErrorAction SilentlyContinue|Where-Object {$_.DirectoryName -like '*\Installer'}|Sort-Object LastWriteTime -Descending|Select-Object -First 1)
            if($setup){
                # Edge's uninstaller refuses unless it believes legacy Edge exists; this empty marker satisfies it.
                $marker=Join-Path $env:WINDIR 'SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe\MicrosoftEdge.exe'
                New-Item -ItemType Directory -Path (Split-Path -Parent $marker) -Force|Out-Null
                if(-not(Test-Path -LiteralPath $marker)){New-Item -ItemType File -Path $marker -Force|Out-Null}
                $uninstallKey='HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge'
                if(Test-Path -LiteralPath $uninstallKey){Set-ItemProperty -LiteralPath $uninstallKey -Name NoRemove -Value 0 -Type DWord -ErrorAction SilentlyContinue}
                $p=Start-Process -FilePath $setup[0].FullName -ArgumentList '--uninstall','--system-level','--force-uninstall','--delete-profile' -Wait -PassThru -WindowStyle Hidden
                Write-Output ('Edge uninstall exit code {0}.' -f $p.ExitCode)
            }else{Write-Output 'Edge is not installed.'}
            # Edge Update: never put the Edge browser back, keep updating WebView2.
            $policy='HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'
            New-Item -Path $policy -Force|Out-Null
            Set-ItemProperty -LiteralPath $policy -Name 'Install{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}' -Value 0 -Type DWord
            Set-ItemProperty -LiteralPath $policy -Name 'Install{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' -Value 1 -Type DWord
            Set-ItemProperty -LiteralPath $policy -Name 'Update{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' -Value 1 -Type DWord
            New-Item -Path 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate' -Force|Out-Null
            Set-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate' -Name 'DoNotUpdateToEdgeWithChromium' -Value 1 -Type DWord
            foreach($lnk in @((Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'Microsoft Edge.lnk'),(Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'Microsoft Edge.lnk'))){if(Test-Path -LiteralPath $lnk){Remove-Item -LiteralPath $lnk -Force}}
            $webView=Test-Path -LiteralPath (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\EdgeWebView\Application')
            Write-Output "WebView2 runtime present after Edge removal: $webView"
        }catch{Write-Output "Edge was not removed: $($_.Exception.Message)"}
    }

    # BAKA Gaming power plan (Ultimate Performance base + gaming tweaks). Desktops switch to it right away;
    # laptops keep Balanced on battery and get the plan from the Gaming profile or the Quick Panel.
    try{
        Import-Module (Join-Path $root 'Modules\PowerPlan.psm1') -Force
        $laptop=Test-BakaBatteryPresent
        $plan=Install-BakaPowerPlan -Activate:(-not $laptop) -Confirm:$false
        Write-Output ('Power plan "{0}" ready (based on {1}, {2} settings, active={3}, laptop={4}).' -f $plan.Name,$plan.BasedOn,$plan.SettingsApplied,$plan.Active,$laptop)
    }catch{Write-Output "BAKA power plan was not created: $($_.Exception.Message)"}

    # System-wide ad and tracker blocking: encrypted AdGuard DNS on every connected adapter (restorable).
    try{
        $privacyDns=$privacy.PSObject.Properties['adBlockDns']
        if(-not $privacyDns -or $privacyDns.Value.enabled){
            $dnsExe=Join-Path $root 'Desktop\BakaDesktop.exe'
            $p=Start-Process -FilePath $dnsExe -ArgumentList '--adblock','on' -Wait -PassThru -WindowStyle Hidden
            Write-Output ('Ad-blocking DNS (AdGuard, encrypted) exit code {0}; backup present: {1}' -f $p.ExitCode,(Test-Path -LiteralPath (Join-Path $root 'AdBlockDnsBackup.json')))
        }
    }catch{Write-Output "Ad-blocking DNS was not turned on: $($_.Exception.Message)"}

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

    # BAKA tools live in BAKA Settings > System and in a Start menu folder with real icons. They run
    # without a console window; nothing is left on the desktop that looks like a PowerShell command.
    $shell=New-Object -ComObject WScript.Shell
    $powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $imageres=Join-Path $env:WINDIR 'System32\imageres.dll'
    $commonDesktop=[Environment]::GetFolderPath('CommonDesktopDirectory')
    foreach($old in @('BAKA Install Selected Apps.lnk','BAKA Hardware Drivers.lnk','Restore Windows Update.lnk','Restore BAKA System Tuning.lnk','Microsoft Edge.lnk')){
        $oldPath=Join-Path $commonDesktop $old
        if(Test-Path -LiteralPath $oldPath -PathType Leaf){Remove-Item -LiteralPath $oldPath -Force}
    }
    $menuFolder=Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'BAKA'
    New-Item -ItemType Directory -Path $menuFolder -Force|Out-Null
    # BAKA Desktop (a compiled app, no PowerShell) starts at every sign-in for every user. Explorer stays
    # the Windows shell and runs in the background; BAKA hides its taskbar, Start and desktop icons.
    $desktopExe=Join-Path $root 'Desktop\BakaDesktop.exe'
    foreach($old in @('BAKA Liquid Desktop.lnk','BAKA Gaming Dock.lnk')){$oldPath=Join-Path ([Environment]::GetFolderPath('CommonStartup')) $old;if(Test-Path -LiteralPath $oldPath -PathType Leaf){Remove-Item -LiteralPath $oldPath -Force}}
    if(Test-Path -LiteralPath $desktopExe -PathType Leaf){
        New-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'BAKA Desktop' -PropertyType String -Value ('"{0}"' -f $desktopExe) -Force|Out-Null
        foreach($spec in @(@{Name='BAKA Desktop.lnk';Args='';Desc='Start the BAKA desktop (menu bar, dock, Launchpad, widgets).'},@{Name='BAKA Settings.lnk';Args='--settings';Desc='Theme, wallpaper, dock, menu bar, widgets, privacy and power.'},@{Name='BAKA Files.lnk';Args='--open "%USERPROFILE%"';Desc='Your files and drives.'})){
            $link=$shell.CreateShortcut((Join-Path $menuFolder $spec.Name));$link.TargetPath=$desktopExe;$link.Arguments=$spec.Args;$link.WorkingDirectory=Split-Path -Parent $desktopExe;$link.Description=$spec.Desc;$link.IconLocation="$desktopExe,0";$link.Save()
        }
    }
    $shortcutSpecs=@(
        @{Folder=$menuFolder;Name='Reinstall Baka Browser.lnk';Script='Install-SelectedApps.ps1';Description='Install or repair Baka Browser for this user.';Icon="$imageres,1023"},
        @{Folder=$menuFolder;Name='Install Hardware Drivers.lnk';Script='Install-SelectedDrivers.ps1';Description='Detect hardware and install only approved matching vendor drivers.';Icon="$imageres,27"},
        @{Folder=$menuFolder;Name='Restore Windows Update.lnk';Script='Restore-WindowsUpdate.ps1';Description='Turn Windows Update back on (asks for administrator approval).';Icon="$imageres,1401"},
        @{Folder=$menuFolder;Name='Restore BAKA System Tuning.lnk';Script='Restore-SystemTuning.ps1';Description='Undo BAKA service, scheduled-task, privacy, power plan, and default-browser policy changes.';Icon="$imageres,5364"}
    )
    foreach($spec in $shortcutSpecs){
        $link=$shell.CreateShortcut((Join-Path $spec.Folder $spec.Name))
        $link.TargetPath=$powershell
        $arguments='-NoProfile'
        if($spec.Sta){$arguments+=' -STA'}
        $arguments+=' -WindowStyle Hidden'
        $link.Arguments=$arguments+' -ExecutionPolicy Bypass -File "'+(Join-Path $root ('Scripts\'+$spec.Script))+'"'+$(if($spec.Arguments){' '+$spec.Arguments}else{''})
        $link.WorkingDirectory=Join-Path $root 'Scripts'
        $link.Description=$spec.Description
        $link.WindowStyle=7
        if($spec.Icon){$link.IconLocation=$spec.Icon}
        $link.Save()
    }
    $activeSetup='HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{D7C6DA30-92B6-4B30-A4E0-26A2B2602A10}'
    if(-not(Test-Path -LiteralPath $activeSetup)){New-Item -Path $activeSetup -Force|Out-Null}
    $firstLogon=Join-Path $root 'Scripts\FirstLogon.ps1'
    $stub='"'+$powershell+'" -NoProfile -ExecutionPolicy Bypass -File "'+$firstLogon+'"'
    New-ItemProperty -LiteralPath $activeSetup -Name 'StubPath' -PropertyType String -Value $stub -Force|Out-Null
    New-ItemProperty -LiteralPath $activeSetup -Name 'Version' -PropertyType String -Value '1,0,0,0' -Force|Out-Null
    New-ItemProperty -LiteralPath $activeSetup -Name 'IsInstalled' -PropertyType DWord -Value 1 -Force|Out-Null
    Write-Output 'Applied BAKA policies after OOBE, installed the restoration workflow, and registered BAKA Desktop.'
    $completed=$true
}finally{
    if($completed){Unregister-ScheduledTask -TaskName 'BAKA-InitializeAfterOobe' -Confirm:$false -ErrorAction SilentlyContinue}
    Stop-Transcript|Out-Null
}
