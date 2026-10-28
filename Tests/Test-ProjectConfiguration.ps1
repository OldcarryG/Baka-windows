[CmdletBinding()]
param([switch]$SkipExternalArtifactChecks)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$checks=[System.Collections.Generic.List[object]]::new()
function Assert-Check([string]$Name,[bool]$Condition,[string]$Detail){
    $checks.Add([pscustomobject]@{Name=$Name;Passed=$Condition;Skipped=$false;Detail=$Detail})
    if(-not $Condition){throw "Check failed: $Name — $Detail"}
}
function Skip-Check([string]$Name,[string]$Reason){
    if(-not $SkipExternalArtifactChecks){throw "Cannot skip required local artifact check '$Name' without -SkipExternalArtifactChecks."}
    $checks.Add([pscustomobject]@{Name=$Name;Passed=$null;Skipped=$true;Detail=$Reason})
}
$jsonFiles=Get-ChildItem -LiteralPath (Join-Path $root 'Config') -Filter '*.json' -File
foreach($file in $jsonFiles){
    try{$null=Get-Content -LiteralPath $file.FullName -Raw|ConvertFrom-Json -ErrorAction Stop;Assert-Check "JSON $($file.Name)" $true 'Valid JSON.'}
    catch{Assert-Check "JSON $($file.Name)" $false $_.Exception.Message}
}
$powerShellFiles=@(
    Get-ChildItem -LiteralPath $root -File
    foreach($directoryName in @('Scripts','Modules','Tests')){
        $directoryPath=Join-Path $root $directoryName
        if(Test-Path -LiteralPath $directoryPath -PathType Container){Get-ChildItem -LiteralPath $directoryPath -Recurse -File}
    }
) | Where-Object { $_.Extension -in @('.ps1','.psm1') }
$encodingValid=$true
foreach($file in $powerShellFiles){
    $bytes=[System.IO.File]::ReadAllBytes($file.FullName)
    if($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF){$encodingValid=$false;break}
}
Assert-Check 'PowerShell sources use UTF-8 BOM for Windows PowerShell 5.1' $encodingValid 'Consistent UTF-8 encoding prevents non-ASCII literals from being misread by Windows PowerShell 5.1.'
foreach($file in $powerShellFiles){
    $tokens=$null;$parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    Assert-Check "PowerShell syntax $($file.Name)" ($parseErrors.Count -eq 0) (($parseErrors | ForEach-Object Message) -join '; ')
}
$base=Get-Content -LiteralPath (Join-Path $root 'Config\BaseImage.json') -Raw|ConvertFrom-Json
$apps=Get-Content -LiteralPath (Join-Path $root 'Config\Applications.json') -Raw|ConvertFrom-Json
$debloat=Get-Content -LiteralPath (Join-Path $root 'Config\Debloat.json') -Raw|ConvertFrom-Json
$profiles=Get-Content -LiteralPath (Join-Path $root 'Config\PerformanceProfiles.json') -Raw|ConvertFrom-Json
$servicing=Get-Content -LiteralPath (Join-Path $root 'Config\ServicingPackages.json') -Raw|ConvertFrom-Json
$serviceScript=Get-Content -LiteralPath (Join-Path $root 'Scripts\03-ServiceImage.ps1') -Raw
$browser=@($apps.applications|Where-Object id -eq 'baka-browser')
Assert-Check 'Windows base candidate' ($base.product -eq 'Windows 11 Pro' -and $base.architecture -eq 'x64' -and $base.releaseCandidate -eq '26H2') 'Pro x64 26H2 is recorded as a candidate.'
Assert-Check 'Source hash pinned' ([bool]$base.requireSourceSha256 -and $base.sourceSha256 -match '^[A-Fa-f0-9]{64}$' -and $base.sourceBuild -eq '10.0.26300.9457') 'The Microsoft-hosted source has a recorded SHA-256 and exact image build.'
$sourcePath=Join-Path $root ($base.sourceIsoRelativePath -replace '/','\')
if($SkipExternalArtifactChecks){
    Skip-Check 'Pinned Windows source presence and SHA-256' 'External installation media is intentionally excluded from the source repository.'
}else{
    $sourcePresent=Test-Path -LiteralPath $sourcePath -PathType Leaf
    Assert-Check 'Pinned Windows source present' $sourcePresent $sourcePath
    if($sourcePresent){
        $sourceHash=(Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToUpperInvariant()
        Assert-Check 'Pinned Windows source SHA-256' ($sourceHash -eq $base.sourceSha256.ToUpperInvariant()) $sourceHash
    }
}
$updateFiles=@($servicing.releaseUpdate.requiredFiles)
$checkpoint=@($updateFiles|Where-Object { $_.kb -eq 'KB5043080' -and $_.role -eq 'checkpoint' })
$target=@($updateFiles|Where-Object { $_.kb -eq $base.latestKnownServicing.kb -and $_.role -eq 'target' })
$servicingFilesValid=$true
$servicingSignaturesValid=$true
if(-not $SkipExternalArtifactChecks){
    foreach($entry in $updateFiles){
        if(-not $entry.approved -or $entry.relativePath -notmatch '(?i)x64\.msu$' -or $entry.sha256 -notmatch '^[A-Fa-f0-9]{64}$'){$servicingFilesValid=$false;continue}
        $packagePath=Join-Path $root ($entry.relativePath -replace '/','\')
        if(-not (Test-Path -LiteralPath $packagePath -PathType Leaf)){$servicingFilesValid=$false;continue}
        $package=Get-Item -LiteralPath $packagePath
        if(($entry.sizeBytes -and $package.Length -ne [long]$entry.sizeBytes) -or (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash -ne $entry.sha256.ToUpperInvariant()){$servicingFilesValid=$false}
        $packageSignature=Get-AuthenticodeSignature -LiteralPath $packagePath
        if($packageSignature.Status -ne 'Valid' -or $packageSignature.SignerCertificate.Subject -notmatch 'Microsoft Corporation'){$servicingSignaturesValid=$false}
    }
}
$servicingManifestValid=($servicing.releaseUpdate.targetKb -eq $base.latestKnownServicing.kb -and $servicing.releaseUpdate.targetBuild -eq $base.latestKnownServicing.build -and $checkpoint.Count -eq 1 -and $target.Count -eq 1 -and $updateFiles.Count -eq 2 -and @($updateFiles|Where-Object { -not $_.approved -or $_.relativePath -notmatch '(?i)x64\.msu$' -or $_.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [long]$_.sizeBytes -le 0 }).Count -eq 0)
Assert-Check 'Required servicing manifest is pinned and fail-closed' $servicingManifestValid 'The manifest must name exactly one approved x64 checkpoint and one approved target update with pinned hashes.'
if($SkipExternalArtifactChecks){
    Skip-Check 'Staged servicing package hashes and signatures' 'Microsoft-signed MSU packages are excluded from the source repository; local build preflight verifies their bytes and signatures.'
}else{
    Assert-Check 'Required current update and checkpoint are staged and signed' ($servicingFilesValid -and $servicingSignaturesValid) 'Both exact x64 packages must be present, match their size and SHA-256, and have valid Microsoft Authenticode signatures before image servicing.'
}
Assert-Check 'Target update verification resolves the full CBS package identity' ($serviceScript -match '/Get-Packages' -and $serviceScript -match 'targetPackagePrefix' -and $serviceScript -match '\$installedIdentities = @\(\$installedIdentities \| Sort-Object -Unique\)' -and $serviceScript -match 'targetPackageIdentity = \$installedIdentities\[0\]') 'DISM package revision suffixes are discovered from the serviced image and kept as an array before exact installed-state verification.'
$singlePackageIdentity='Package_for_RollupFix~31bf3856ad364e35~amd64~~26100.9711.1.30'
$singlePackageIdentities=@($singlePackageIdentity|Sort-Object -Unique)
Assert-Check 'Single target package identity survives array indexing' ($singlePackageIdentities.Count -eq 1 -and $singlePackageIdentities[0] -ceq $singlePackageIdentity) 'PowerShell scalar unrolling must not truncate a one-item package identity to its first character.'
Assert-Check 'Image commit and discard use the pinned ADK DISM binary' ($serviceScript -match "commitArgs = @\('/Unmount-Image'" -and $serviceScript -match '& \$adkDism @commitArgs' -and $serviceScript -match "'/Commit','/CheckIntegrity'" -and $serviceScript -match "'/Discard'" -and $serviceScript -notmatch 'Dismount-WindowsImage -Path \$mount -Save') 'Keep mount commit, integrity verification, and failure cleanup on the same ADK DISM toolchain used for package verification.'
$approvedRemovals=@($debloat.candidateRemovals|Where-Object approved)
$removalNames=@($approvedRemovals|ForEach-Object packageNames)
$expectedRemovals=@('Microsoft.GamingApp','Microsoft.XboxGamingOverlay','Microsoft.BingNews','Microsoft.BingWeather','Microsoft.MicrosoftOfficeHub','Microsoft.MicrosoftSolitaireCollection','MSTeams','Clipchamp.Clipchamp','Microsoft.BingSearch','Microsoft.OutlookForWindows','Microsoft.Todos','Microsoft.PowerAutomateDesktop','Microsoft.GetHelp','Microsoft.WindowsFeedbackHub','Microsoft.Windows.DevHome','Microsoft.YourPhone','MicrosoftWindows.CrossDevice','MicrosoftCorporationII.QuickAssist','Microsoft.XboxSpeechToTextOverlay')
$protectedKeepers=@('Microsoft.WindowsStore','Microsoft.SecHealthUI','Microsoft.DesktopAppInstaller','Microsoft.XboxIdentityProvider','Microsoft.Xbox.TCUI','Microsoft.HEVCVideoExtension','Microsoft.WebMediaExtensions','Microsoft.StorePurchaseApp')
Assert-Check 'Game sign-in, security, Store, and codec packages stay protected' (@($protectedKeepers|Where-Object {$name=$_;-not @($debloat.blockedPackagePatterns|Where-Object {$name -like $_}).Count}).Count -eq 0 -and @($removalNames|Where-Object {$name=$_;@($debloat.blockedPackagePatterns|Where-Object {$name -like $_}).Count}).Count -eq 0) 'Every protected package matches a blocked pattern and no approved removal does.'
$removalSetMatches=(@(Compare-Object -ReferenceObject ($expectedRemovals|Sort-Object) -DifferenceObject ($removalNames|Sort-Object)).Count -eq 0)
Assert-Check 'Reviewed optional app removals are exact' ($debloat.enabled -and $debloat.requireImageInventoryReview -and $removalSetMatches -and @($removalNames|Where-Object { $_ -match '[*?]' }).Count -eq 0) 'Only inventory-reviewed consumer packages are removed by exact identity; protected components remain blocked.'
Assert-Check 'BAKA Gaming power plan is the profile plan and is created at first logon' ($profiles.defaultProfile -eq 'Desktop' -and $profiles.profiles.Desktop.powerPlan -eq 'BAKA Gaming' -and (Test-Path -LiteralPath (Join-Path $root 'Modules\PowerPlan.psm1')) -and (Get-Content -LiteralPath (Join-Path $root 'Scripts\Runtime\Apply-FirstLogonSystemSetup.ps1') -Raw) -match 'Install-BakaPowerPlan') 'A named BAKA Gaming plan (Ultimate Performance base + gaming tweaks) is installed; Restore BAKA System Tuning removes it.'
Assert-Check 'No experimental global performance changes enabled' (@($profiles.profiles.CompetitiveGaming.experimentalTweaks).Count -eq 0 -and @($profiles.profiles.Benchmark.experimentalTweaks).Count -eq 0) 'Experimental tweak lists are empty.'
$gameDetection=@($profiles.gameDetection.processes)
$gameProcessNames=@($gameDetection|ForEach-Object { [string]$_.processName })
Assert-Check 'Automatic detection targets approved free games' ((($gameProcessNames|Sort-Object) -join ',') -eq 'cs2,tf_win64') 'Only CS2 and Team Fortress 2 process names are configured.'
Assert-Check 'VALORANT is excluded from automatic detection' (@($gameProcessNames|Where-Object { $_ -match '(?i)valorant|shipping' }).Count -eq 0) 'The user-selected test scope excludes VALORANT.'
$buildSetupText=Get-Content -LiteralPath (Join-Path $root 'Scripts\05-BuildSetup.ps1') -Raw
Assert-Check 'Runtime profile config is staged beside the companion' ($buildSetupText -match 'Config\\PerformanceProfiles\.json' -and $buildSetupText -match 'PerformanceProfiles\.json' -and $buildSetupText -match 'targetRoot') 'The companion reads its profile config from ProgramData\BAKA and Setup stages it there.'
$requiredLiquidFiles=@('BakaCompanion.ps1','DesktopConfiguration.psm1','CompanionInstance.psm1','SystemMonitoring.psm1','DesktopSettings.default.json','DesktopThemes.json')
$liquidStagesAll=@($requiredLiquidFiles|ForEach-Object {$buildSetupText -match [regex]::Escape($_)}|Where-Object {$_ -eq $false}).Count -eq 0
Assert-Check 'BAKA Liquid runtime payload is staged together' $liquidStagesAll 'The WPF companion, settings, themes, and monitoring modules are staged together under ProgramData\BAKA.'
$ribbonWallpaper=Join-Path $root 'Assets\Wallpapers\BAKA-Liquid-Ribbon.png'
$firstLogonText=Get-Content -LiteralPath (Join-Path $root 'Scripts\Runtime\FirstLogon.ps1') -Raw
$validatorText=Get-Content -LiteralPath (Join-Path $root 'Scripts\07-ValidateISO.ps1') -Raw
Assert-Check 'Original liquid-glass wallpaper is staged and selected by default' ((Test-Path -LiteralPath $ribbonWallpaper -PathType Leaf) -and $buildSetupText -match 'BAKA-Liquid-Ribbon\.png' -and $firstLogonText -match 'BAKA-Liquid-Ribbon\.png' -and $validatorText -match 'Assets\\BAKA-Liquid-Ribbon\.png') 'The original silver glass wallpaper ships with the image and becomes the first-logon desktop background.'
$companionText=Get-Content -LiteralPath (Join-Path $root 'Scripts\Runtime\BakaCompanion.ps1') -Raw
Assert-Check 'Dock and editor preserve translucent glass surfaces' ($companionText -match 'Dock\.Tag\.Background=\$script:glassBrush' -and $companionText -match '\$layout\.Background=\[System\.Windows\.Media\.Brushes\]::Transparent' -and $companionText -match 'DwmSetWindowAttribute') 'The dock uses the shared glass brush, settings content does not cover the Acrylic backdrop, and Windows DWM provides supported window backdrop material.'
Assert-Check 'BAKA Liquid has a moving specular sweep and dock wave' ($companionText -match 'ui-animation=liquid-glint' -and $companionText -match 'centerScale=1\.26 neighborScale=1\.13' -and $companionText -match '1120') 'Full motion includes an event-driven silver light sweep and pointer-focused icon magnification.'
$themeManifest=Get-Content -LiteralPath (Join-Path $root 'Config\DesktopThemes.json') -Raw|ConvertFrom-Json
$requiredThemes=@('BAKA Obsidian','BAKA Liquid','BAKA Minimal','BAKA Gaming')
$themeNames=@($themeManifest.themes|ForEach-Object name)
Assert-Check 'BAKA required preset names match the design' (@($requiredThemes|Where-Object {$_ -notin $themeNames}).Count -eq 0) 'Obsidian, Liquid, Minimal, and Gaming are present; additional presets remain supported.'
$configureScript=Get-Content -LiteralPath (Join-Path $root 'Scripts\04-ConfigureWindows.ps1') -Raw
Assert-Check 'Component image commit uses the pinned ADK DISM binary' ($configureScript -match 'Complete-BakaImageMount' -and $configureScript -match '& \$adkDism @arguments' -and $configureScript -notmatch 'Dismount-WindowsImage -Path \$mount -Save') 'Use the current ADK toolchain for component-image commit and discard.'
Assert-Check 'Optional packages absent from this Windows edition are skipped' ($configureScript -match '\$match\.Count -eq 0' -and $configureScript -match '\$changesApplied' -and $configureScript -match 'No approved optional packages were present') 'Do not fail the build when a reviewed optional app is absent, and discard an unchanged image.'
$firstLogon=Get-Content -LiteralPath (Join-Path $root 'Scripts\Runtime\FirstLogon.ps1') -Raw
$systemSetup=Get-Content -LiteralPath (Join-Path $root 'Scripts\Runtime\Apply-FirstLogonSystemSetup.ps1') -Raw
Assert-Check 'The BAKA Liquid companion launches once in the interactive user session' ($systemSetup -match 'CommonStartup' -and $systemSetup -match 'BAKA Liquid Desktop\.lnk' -and $systemSetup -match 'BakaCompanion\.ps1' -and $systemSetup -match '\-STA' -and $firstLogon -notmatch 'BakaDock\.ps1') 'Launch the STA WPF companion from the shared Startup shortcut, not the legacy dock or both Active Setup and Startup.'
$moduleText=Get-Content -LiteralPath (Join-Path $root 'Modules\GamingProfiles\GamingProfiles.psm1') -Raw
Assert-Check 'Game resolver is exported for runtime use' ($moduleText -match 'function Resolve-BakaDetectedGame' -and $moduleText -match 'Export-ModuleMember.*Resolve-BakaDetectedGame') 'The companion calls the shared, testable process-name resolver.'
$validatorText=Get-Content -LiteralPath (Join-Path $root 'Scripts\07-ValidateISO.ps1') -Raw
Assert-Check 'ISO validation records requested game scope' ($validatorText -match "CS2='Not run'" -and $validatorText -match "TeamFortress2='Not run'" -and $validatorText -match 'VALORANT=.Excluded by user instruction') 'Future ISO validation records CS2 and Team Fortress 2 as unrun and VALORANT as excluded.'
Assert-Check 'ISO validation checks the installed BAKA Liquid runtime' ($validatorText -match 'BakaCompanion\.ps1' -and $validatorText -match 'DesktopConfiguration\.psm1' -and $validatorText -match 'DesktopThemes\.json' -and $validatorText -notmatch 'ProgramData\\BAKA\\Scripts\\BakaDock\.ps1') 'Require the companion, required modules and themes, and stop expecting the removed legacy dock.'
$pipelineText=Get-Content -LiteralPath (Join-Path $root 'Scripts\Invoke-BuildPipeline.ps1') -Raw
Assert-Check 'Build pipeline supports isolated output and build paths' ($pipelineText -match '\[string\]\$BuildRoot' -and $pipelineText -match '\[string\]\$OutputPath' -and $pipelineText -match 'BakaLiquid-RC-20261024' -and $pipelineText -match 'Refusing to overwrite existing ISO') 'Pass an isolated Work directory and distinct, non-overwriting ISO destination through all build stages.'
Assert-Check 'Workspace preparation receives the isolated BuildRoot' ((Get-Content -LiteralPath (Join-Path $root 'Scripts\02-PrepareWorkspace.ps1') -Raw) -match 'param\([^\r\n]*\$SourceIso[^\r\n]*\$BuildRoot' -and (Get-Content -LiteralPath (Join-Path $root 'Scripts\Invoke-BuildPipeline.ps1') -Raw) -match 'Name=''Prepare source and work media''.*BuildRoot=\$BuildRoot') 'The first build stage must create media inside the pipeline-selected, guarded workspace.'
$isoBuilderText=Get-Content -LiteralPath (Join-Path $root 'Scripts\06-BuildISO.ps1') -Raw
Assert-Check 'OSCDIMG output is isolated from remoting and its exit code is checked' ($isoBuilderText -match 'Start-Process -FilePath \$oscdimg' -and $isoBuilderText -match 'RedirectStandardOutput \$stdoutLog' -and $isoBuilderText -match 'RedirectStandardError \$stderrLog' -and $isoBuilderText -match '\$process\.ExitCode -ne 0' -and $isoBuilderText -notmatch '& \$oscdimg @arguments') 'Capture native output in separate logs so PowerShell remoting does not treat OSCDIMG stderr as a terminating error; record the real exit code.'
Assert-Check 'Baka Browser explicitly selected' ($browser.Count -eq 1 -and $browser[0].selected -and $browser[0].defaultBrowser) 'User selected Baka Browser.'
Assert-Check 'Baka Browser installer hash and unsigned status are pinned' ($browser.Count -eq 1 -and $browser[0].sha256 -match '^[A-Fa-f0-9]{64}$' -and $browser[0].authenticode -match 'NotSigned') 'The installer hash and unsigned status remain explicit in the manifest even when external installer checks are skipped.'
Assert-Check 'Baka Browser installs silently at first logon and registers as a browser' ($browser.Count -eq 1 -and @($browser[0].silentArguments) -contains '--silent' -and $browser[0].progId -eq 'BakaBrowserHTML' -and (Get-Content -LiteralPath (Join-Path $root 'Scripts\Runtime\Install-SelectedApps.ps1') -Raw) -match 'StartMenuInternet\\BakaBrowser' -and $firstLogon -match 'Install-SelectedApps\.ps1' -and $firstLogon -match "'-Silent'") 'Velopack --silent per-user install, Default Programs capabilities, and a first-logon background launch.'
[xml]$associationsXml=Get-Content -LiteralPath (Join-Path $root 'Config\DefaultAssociations.xml') -Raw
$associationIds=@($associationsXml.DefaultAssociations.Association|Where-Object {$_.ProgId -eq 'BakaBrowserHTML'}|ForEach-Object Identifier)
Assert-Check 'Default associations make Baka Browser the web handler' ((@('http','https','.htm','.html')|Where-Object {$_ -notin $associationIds}).Count -eq 0 -and $systemSetup -match 'DefaultAssociationsConfiguration') 'http, https, .htm, and .html map to the registered Baka Browser ProgId through the reversible Windows policy.'
$tuningConfig=Get-Content -LiteralPath (Join-Path $root 'Config\SystemTuning.json') -Raw|ConvertFrom-Json
$tunedServices=@($tuningConfig.services|ForEach-Object name)
Assert-Check 'Service tuning never touches protected services' (@($tunedServices|Where-Object {$_ -in @($tuningConfig.protectedServices)}).Count -eq 0 -and $tunedServices -contains 'DiagTrack' -and @($tuningConfig.services|Where-Object {$_.startType -notin @('Disabled','Manual')}).Count -eq 0) 'Telemetry services are disabled; Defender, Firewall, Update, Xbox sign-in, audio, and network services are protected.'
$privacyConfig=Get-Content -LiteralPath (Join-Path $root 'Config\PrivacySettings.json') -Raw|ConvertFrom-Json
$privacyNames=@($privacyConfig.devicePolicies|ForEach-Object name)+@($privacyConfig.userPolicies|ForEach-Object name)
Assert-Check 'Ads, Copilot, Recall, web search, and suggestions are turned off' ((@('TurnOffWindowsCopilot','DisableAIDataAnalysis','DisableWebSearch','EnableActivityFeed','SilentInstalledAppsEnabled','SubscribedContent-338388Enabled','Start_IrisRecommendations','DisabledByGroupPolicy')|Where-Object {$_ -notin $privacyNames}).Count -eq 0 -and @(@($privacyConfig.devicePolicies)+@($privacyConfig.userPolicies)|Where-Object {$_.type -ne 'DWord'}).Count -eq 0) 'Privacy policy coverage is explicit and uses DWord values only.'
Assert-Check 'System tuning is backed up and restorable' ($systemSetup -match 'Invoke-BakaSystemTuning -Mode Apply' -and $systemSetup -match 'SystemTuningBackup\.json' -and (Get-Content -LiteralPath (Join-Path $root 'Scripts\Runtime\Restore-SystemTuning.ps1') -Raw) -match 'Invoke-BakaSystemTuning -Mode Restore' -and $systemSetup -match 'Restore BAKA System Tuning\.lnk') 'Apply records prior values; the desktop restore shortcut replays them.'
$gamePerformance=Get-Content -LiteralPath (Join-Path $root 'Config\GamePerformance.json') -Raw|ConvertFrom-Json
$gamePerformanceNames=@($gamePerformance.devicePolicies|ForEach-Object name)+@($gamePerformance.userPolicies|ForEach-Object name)
Assert-Check 'Game performance settings apply to every game and are restorable' ((@('HwSchMode','AllowGameDVR','SystemResponsiveness','AutoGameModeEnabled','DirectXUserGlobalSettings','MouseSpeed')|Where-Object {$_ -notin $gamePerformanceNames}).Count -eq 0 -and @(@($gamePerformance.devicePolicies)+@($gamePerformance.userPolicies)|Where-Object {$_.type -notin @('DWord','String')}).Count -eq 0 -and $systemSetup -match 'GamePerformance\.json' -and $firstLogon -match 'GamePerformance\.json') 'Device values go through the SYSTEM backup and user values through the per-user backup.'
Assert-Check 'Automatic profile switching covers all games' ($profiles.gameDetection.mode -eq 'AllGames' -and @($profiles.gameDetection.libraryPathPatterns) -contains '\steamapps\common\' -and $profiles.gameDetection.fullscreenDetection -and $companionText -match 'Resolve-BakaAnyGame') 'Named titles, game-library executables, and fullscreen foreground apps all trigger Competitive Gaming.'
$newRuntimeStaged=@('DesktopShell.psm1','SystemTuning.psm1','Restore-SystemTuning.ps1','SystemTuning.json','GamePerformance.json','Debloat.json','AccountSetup.json','DefaultAssociations.xml','Set-BakaAdBlockDns.ps1','Install-MediaCodecs.ps1','AdBlockDns.psm1')
Assert-Check 'R4 runtime payload is staged and validated in the ISO' (@($newRuntimeStaged|Where-Object {$buildSetupText -notmatch [regex]::Escape($_) -or $validatorText -notmatch [regex]::Escape($_)}).Count -eq 0) 'Setup staging and ISO validation both cover the shell, tuning, account, and association files.'
$account=Get-Content -LiteralPath (Join-Path $root 'Config\AccountSetup.json') -Raw|ConvertFrom-Json
$answerPath=Join-Path $root 'Config\Autounattend.template.xml'
try{
    [xml]$answerForLogon=Get-Content -LiteralPath $answerPath -Raw
    $oobe=$answerForLogon.unattend.settings|Where-Object pass -eq 'oobeSystem'
    $shellSetup=@($oobe.component|Where-Object name -eq 'Microsoft-Windows-Shell-Setup')[0]
    $windowsPe=@($answerForLogon.unattend.settings|Where-Object pass -eq 'windowsPE')
    $answerText=Get-Content -LiteralPath $answerPath -Raw
    $autoSignInText=Get-Content -LiteralPath (Join-Path $root 'Scripts\Runtime\Enable-AutoSignIn.ps1') -Raw
    # The answer file must not set an account password at all; BAKA creates the account with New-LocalUser -NoPassword.
    Assert-Check 'Setup boots straight to the desktop without a sign-in or Microsoft account screen' ($account.autoLogon -and $answerText -match 'Enable-AutoSignIn\.ps1" -CreateAccount' -and $answerText -match 'Enable-AutoSignIn\.ps1" -RegisterTask' -and $answerText -notmatch '<Password>' -and $autoSignInText -match 'New-LocalUser -Name \$userName .*-NoPassword' -and $autoSignInText -match "S-1-5-32-544" -and $shellSetup.OOBE.HideOnlineAccountScreens -eq 'true' -and $windowsPe.Count -eq 0 -and $systemSetup -match 'AutoAdminLogon' -and (Get-Content -LiteralPath $answerPath -Raw) -match 'Enable-AutoSignIn\.ps1' -and (Get-Content -LiteralPath (Join-Path $root 'Scripts\Runtime\Enable-AutoSignIn.ps1') -Raw) -match 'DevicePasswordLessBuildVersion' -and $buildSetupText -match 'Enable-AutoSignIn\.ps1') 'The passwordless local account signs in automatically; disk selection remains interactive (no windowsPE pass).'
}catch{Assert-Check 'Setup boots straight to the desktop without a sign-in or Microsoft account screen' $false $_.Exception.Message}
try{
    [xml]$answer=Get-Content -LiteralPath $answerPath -Raw
    $specialize=$answer.unattend.settings | Where-Object pass -eq 'specialize'
    $runCommand=$specialize.component.RunSynchronous.RunSynchronousCommand
    Assert-Check 'Answer file XML structure' ($answer.unattend.LocalName -eq 'unattend' -and $specialize -and $runCommand.Path -match 'Register-FirstLogonTask.ps1') 'Well-formed XML with only the intended specialize registration hook; validate with Windows SIM on the build host.'
}catch{Assert-Check 'Answer file XML structure' $false $_.Exception.Message}
if($browser.Count -eq 1){
    $installer=Join-Path $root ($browser[0].relativePath -replace '/','\')
    if($SkipExternalArtifactChecks){
        Skip-Check 'Pinned Baka Browser installer hash and signature' 'The unsigned installer is excluded from the source repository; local preflight verifies its pinned hash and signature state.'
    }else{
        $present=Test-Path -LiteralPath $installer -PathType Leaf
        Assert-Check 'Pinned Baka Browser installer present' $present $installer
        if($present){
            $actual=(Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToUpperInvariant()
            Assert-Check 'Pinned Baka Browser SHA-256' ($actual -eq $browser[0].sha256.ToUpperInvariant()) $actual
            $signature=Get-AuthenticodeSignature -LiteralPath $installer
            Assert-Check 'Baka Browser unsigned status is documented' ($signature.Status -eq 'NotSigned' -and $browser[0].authenticode -match 'NotSigned') "$($signature.Status); release installer SHA-256 is pinned."
        }
    }
}
$report=[pscustomobject]@{RanAt=(Get-Date).ToString('o');Passed=(@($checks|Where-Object {$_.Passed -eq $false}).Count -eq 0);SkippedCount=@($checks|Where-Object {$_.Skipped}).Count;Checks=@($checks)}
$logsDirectory=Join-Path $root 'Logs'
if(-not(Test-Path -LiteralPath $logsDirectory -PathType Container)){New-Item -ItemType Directory -Path $logsDirectory -Force|Out-Null}
$reportPath=Join-Path $root ("Logs\ProjectPreflight-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$checks | Format-Table Name,Passed,Skipped,Detail -AutoSize
Write-Host ('RESULT: {0} passed; {1} explicitly skipped.' -f @($checks|Where-Object {$_.Passed -eq $true}).Count,$report.SkippedCount)
Write-Host "Report: $reportPath"
