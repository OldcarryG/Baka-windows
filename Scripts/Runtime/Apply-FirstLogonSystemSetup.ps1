$ErrorActionPreference='Stop'
$root=Join-Path $env:ProgramData 'BAKA'
$log=Join-Path $root 'Logs\FirstLogonSystemSetup.log'
New-Item -ItemType Directory -Path (Split-Path -Parent $log) -Force|Out-Null
Start-Transcript -Path $log -Append|Out-Null
$completed=$false
try{
    Import-Module (Join-Path $root 'Modules\UpdateControl.psm1') -Force
    Invoke-BakaWindowsUpdateControl -Mode Disable -Confirm:$false|Out-Null
    $privacy=Get-Content -LiteralPath (Join-Path $root 'PrivacySettings.json') -Raw|ConvertFrom-Json
    foreach($setting in $privacy.devicePolicies){
        if($setting.type -ne 'DWord'){throw "Unsupported privacy policy value type: $($setting.type)"}
        if(-not(Test-Path -LiteralPath $setting.path)){New-Item -Path $setting.path -Force|Out-Null}
        New-ItemProperty -LiteralPath $setting.path -Name $setting.name -PropertyType DWord -Value ([int]$setting.value) -Force|Out-Null
    }
    $shell=New-Object -ComObject WScript.Shell
    $powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $shortcutSpecs=@(
        @{Folder=[Environment]::GetFolderPath('CommonDesktopDirectory');Name='BAKA Install Selected Apps.lnk';Script='Install-SelectedApps.ps1';Description='Install the approved BAKA application packages for this user.'},
        @{Folder=[Environment]::GetFolderPath('CommonDesktopDirectory');Name='BAKA Hardware Drivers.lnk';Script='Install-SelectedDrivers.ps1';Description='Detect hardware and install only approved matching vendor drivers.'},
        @{Folder=[Environment]::GetFolderPath('CommonDesktopDirectory');Name='Restore Windows Update.lnk';Script='Restore-WindowsUpdate.ps1';Description='Restore Windows Update policy settings as an administrator.'},
        @{Folder=[Environment]::GetFolderPath('CommonStartup');Name='BAKA Liquid Desktop.lnk';Script='BakaCompanion.ps1';Description='BAKA Liquid dock, Quick Panel, optional bar, widgets, and reversible gaming profiles.';Sta=$true;Hidden=$true}
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
