[CmdletBinding()]
param([switch]$Preview,[switch]$SmokeTest,[switch]$FileSmoke,[switch]$ArenaSmoke,[string]$CapturePath)
$ErrorActionPreference='Stop'
if($SmokeTest -and -not $Preview){throw 'The UI smoke test requires -Preview so profile and settings changes remain isolated.'}

# BAKA Liquid uses Explorer as the shell and hosts all optional desktop surfaces in one WPF process.
$runtimeRoot=$PSScriptRoot
$scriptsRoot=Split-Path -Parent $runtimeRoot
if((Split-Path -Leaf $runtimeRoot) -ieq 'Runtime' -and (Split-Path -Leaf $scriptsRoot) -ieq 'Scripts'){$dataRoot=Split-Path -Parent $scriptsRoot}else{$dataRoot=$scriptsRoot}
$moduleRoot=Join-Path $dataRoot 'Modules'
$script:previewMode=[bool]$Preview
$script:smokeTestMode=[bool]$SmokeTest
$script:uiRelease='R4 Liquid Shell'
$script:smokeFailed=$false
$localRoot=if($script:previewMode){Join-Path $env:TEMP ('BAKA-Liquid-Preview-'+[Guid]::NewGuid().ToString('N'))}else{Join-Path $env:LOCALAPPDATA 'BAKA'}
$settingsDirectory=Join-Path $localRoot 'Settings'
$settingsPath=Join-Path $settingsDirectory 'desktop-settings.json'
$defaultSettingsPath=Join-Path $dataRoot 'DesktopSettings.default.json'
$themesPath=Join-Path $dataRoot 'DesktopThemes.json'
$profileConfigPath=Join-Path $dataRoot 'PerformanceProfiles.json'
$developmentConfig=Join-Path $dataRoot 'Config'
if(-not(Test-Path -LiteralPath $defaultSettingsPath) -and (Test-Path -LiteralPath (Join-Path $developmentConfig 'DesktopSettings.default.json'))){$defaultSettingsPath=Join-Path $developmentConfig 'DesktopSettings.default.json'}
if(-not(Test-Path -LiteralPath $themesPath) -and (Test-Path -LiteralPath (Join-Path $developmentConfig 'DesktopThemes.json'))){$themesPath=Join-Path $developmentConfig 'DesktopThemes.json'}
if(-not(Test-Path -LiteralPath $profileConfigPath) -and (Test-Path -LiteralPath (Join-Path $developmentConfig 'PerformanceProfiles.json'))){$profileConfigPath=Join-Path $developmentConfig 'PerformanceProfiles.json'}
$logDirectory=Join-Path $localRoot 'Logs'
$logPath=Join-Path $logDirectory 'Companion.log'
foreach($directory in @($settingsDirectory,$logDirectory)){if(-not(Test-Path -LiteralPath $directory -PathType Container)){New-Item -ItemType Directory -Path $directory -Force|Out-Null}}
Add-Type -AssemblyName System.Windows.Forms
try {
    if(-not ('BakaLiquidNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BakaLiquidNative {
  [DllImport("dwmapi.dll", PreserveSig=true)] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
  [DllImport("user32.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
  [DllImport("user32.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint key);
  [DllImport("user32.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool UnregisterHotKey(IntPtr hwnd, int id);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int command);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);
  [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)] public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }
}
'@ -ErrorAction Stop
    }
    [void][BakaLiquidNative]::SetProcessDpiAwarenessContext([IntPtr]::new(-4))
} catch { }

function Write-BakaUiLog([string]$Message){try{Add-Content -LiteralPath $script:logPath -Value ('{0} {1}' -f (Get-Date -Format 'o'),$Message) -Encoding UTF8}catch{}}

Import-Module (Join-Path $moduleRoot 'CompanionInstance.psm1') -Force
 $gamingModulePath=Join-Path $moduleRoot 'GamingProfiles.psm1'
if(-not(Test-Path -LiteralPath $gamingModulePath)){$gamingModulePath=Join-Path $moduleRoot 'GamingProfiles\GamingProfiles.psm1'}
Import-Module $gamingModulePath -Force
Import-Module (Join-Path $moduleRoot 'DesktopConfiguration.psm1') -Force
Import-Module (Join-Path $moduleRoot 'DesktopShell.psm1') -Force
$script:monitoringModulePath=Join-Path $moduleRoot 'SystemMonitoring.psm1'
Import-Module $script:monitoringModulePath -Force
$script:instanceLock=Enter-BakaCompanionInstance
if(-not $script:instanceLock.Acquired){Write-BakaUiLog 'second-launch-rejected';exit 0}

try {
    # Restore any interrupted visual profile before creating or showing a window.
    if($script:previewMode){
        $mockValues=@{
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize|EnableTransparency'=[pscustomobject]@{KeyExisted=$true;ValueExisted=$true;Value=[int]1;Kind='DWord'}
            'HKCU:\Control Panel\Desktop|MinAnimate'=[pscustomobject]@{KeyExisted=$true;ValueExisted=$true;Value='1';Kind='String'}
        }
        $script:profileRegistryAdapter=@{
            ReadValue={param([string]$Path,[string]$Name);$key=$Path+'|'+$Name;if($mockValues.ContainsKey($key)){return $mockValues[$key]};[pscustomobject]@{KeyExisted=$false;ValueExisted=$false;Value=$null;Kind=$null}}.GetNewClosure()
            EnsureKey={param([string]$Path)}.GetNewClosure()
            WriteValue={param([string]$Path,[string]$Name,[object]$Value,[string]$Kind);$mockValues[$Path+'|'+$Name]=[pscustomobject]@{KeyExisted=$true;ValueExisted=$true;Value=$Value;Kind=$Kind}}.GetNewClosure()
            RemoveValue={param([string]$Path,[string]$Name);$mockValues.Remove($Path+'|'+$Name)|Out-Null}.GetNewClosure()
            RemoveKeyIfEmpty={param([string]$Path)}.GetNewClosure()
        }
        $script:profileStateDirectory=Join-Path $localRoot 'ProfileState'
    }else{$script:profileRegistryAdapter=$null;$script:profileStateDirectory=$null}
    $profileArgs=@{}
    if($script:previewMode){$profileArgs.StateDirectory=$script:profileStateDirectory;$profileArgs.RegistryAdapter=$script:profileRegistryAdapter}
    $recovery=Initialize-BakaGamingProfiles @profileArgs
    $script:config=Read-BakaDesktopConfiguration -Path $script:settingsPath -DefaultPath $script:defaultSettingsPath
    $script:config=Complete-BakaDesktopConfiguration -Configuration $script:config
    if($script:smokeTestMode){$script:config.topBar.enabled=$true;Save-BakaDesktopConfiguration -Path $script:settingsPath -Configuration $script:config|Out-Null}
    $script:profileSettings=Get-Content -LiteralPath $script:profileConfigPath -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
    $themeDocument=Get-Content -LiteralPath $script:themesPath -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
    $requiredThemeNames=@('BAKA Obsidian','BAKA Liquid','BAKA Minimal','BAKA Gaming')
    $availableThemeNames=@($themeDocument.themes|ForEach-Object {[string]$_.name})
    if([int]$themeDocument.schemaVersion -ne 1 -or @($requiredThemeNames|Where-Object {$_ -notin $availableThemeNames}).Count -gt 0){throw 'BAKA theme manifest is invalid.'}
} catch {
    Write-BakaUiLog ('startup-blocked error="{0}"' -f $_.Exception.Message)
    [System.Windows.Forms.MessageBox]::Show(('BAKA could not safely start. Explorer is still available.`r`r{0}' -f $_.Exception.Message),'BAKA startup recovery failed',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)|Out-Null
    Exit-BakaCompanionInstance -Lock $script:instanceLock
    exit 1
}

function Set-BakaCompanionProfile([string]$Profile){
    $arguments=@{Profile=$Profile}
    if($script:previewMode){$arguments.StateDirectory=$script:profileStateDirectory;$arguments.RegistryAdapter=$script:profileRegistryAdapter}
    Set-BakaGamingProfile @arguments
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Drawing

$script:gameDefinitions=@($script:profileSettings.gameDetection.processes)
$script:activeProfile='Desktop'
$script:manualOverride=$null
$script:autoGame=$false
$script:detectedGame=$null
$script:themeManifest=@($themeDocument.themes)
$script:theme=$null
$script:windows=@{}
$script:fileExplorerCurrent=[Environment]::GetFolderPath('UserProfile')
$script:fileExplorerHistory=[System.Collections.Generic.Stack[string]]::new()
$script:fileExplorerList=$null
$script:fileExplorerAddress=$null
$script:fileExplorerSearch=$null
$script:fileExplorerStatus=$null
$script:dockButtons=@{}
$script:iconCache=@{}
$script:templateCache=@{}
$script:popStyle=$false
$script:runningAppSignature=''
$script:stickyGame=$null
$script:videoWallpaper=$null
$script:dashboardVisibleBeforeProfile=$false
$script:wallpaperDirty=$false
$script:taskbarStatePath=Join-Path $settingsDirectory 'taskbar-state.json'
$script:widgetWindows=@{}
$script:backdropHookedWindows=[System.Collections.Generic.HashSet[System.Windows.Window]]::new()
$script:dwmBackdropUnsupported=$false
$script:widgetSaveTimers=@{}
$script:widgetSaveTimer=[System.Windows.Threading.DispatcherTimer]::new()
$script:widgetSaveTimer.Interval=[TimeSpan]::FromMilliseconds(700)
$script:pendingWidgetSaveId=$null
$script:widgetSaveTimer.Add_Tick({param($sender,$eventArgs)$sender.Stop();$pending=[string]$script:pendingWidgetSaveId;$script:pendingWidgetSaveId=$null;if($pending){Save-BakaWidgetPosition $pending}})
$script:widgetUserVisible=[bool]$script:config.widgets.enabled
$script:widgetsVisibleBeforeProfile=$false
$script:allowShutdown=$false
$script:metricsPowerShell=$null
$script:metricsRunspace=$null
$script:metricsAsyncResult=$null
$script:systemMetricsLast=$null
$script:systemMetricsError=''
$script:smokeTimer=$null
$script:app=[System.Windows.Application]::new()
$script:app.ShutdownMode=[System.Windows.ShutdownMode]::OnExplicitShutdown
$script:app.add_DispatcherUnhandledException({param($sender,$eventArgs) $scriptTrace=try{$eventArgs.Exception.ScriptStackTrace}catch{''};$position=try{$eventArgs.Exception.InvocationInfo.PositionMessage}catch{''};Write-BakaUiLog ('ui-exception error="{0}" position="{1}" scriptStack="{2}" stack="{3}"' -f $eventArgs.Exception.Message,$position,$scriptTrace,$eventArgs.Exception.StackTrace);if($script:smokeTestMode){$script:smokeFailed=$true};$eventArgs.Handled=$true})

function Get-BakaTheme([string]$Name){
    $item=@($script:themeManifest|Where-Object { $_.name -eq $Name })|Select-Object -First 1
    if(-not $item){$item=@($script:themeManifest|Where-Object { $_.name -eq 'BAKA Obsidian' })|Select-Object -First 1}
    return $item
}
function ConvertTo-BakaColor([string]$Hex){return [System.Windows.Media.ColorConverter]::ConvertFromString($Hex)}
function New-BakaBrush([string]$Hex,[byte]$Alpha=255){$c=ConvertTo-BakaColor $Hex;[System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb($Alpha,$c.R,$c.G,$c.B))}
function New-BakaGlassBrush([string]$Hex,[byte]$Opacity){
    $base=ConvertTo-BakaColor $Hex
    $brush=[System.Windows.Media.LinearGradientBrush]::new()
    $brush.StartPoint=[System.Windows.Point]::new(0,0);$brush.EndPoint=[System.Windows.Point]::new(1,1)
    $liquid=([string]$script:theme.style -eq 'PopGlass')
    # Liquid glass: a bright specular band at the top edge, a clear body, and a slightly denser base.
    $top=[System.Windows.Media.Color]::FromArgb([byte]$(if($liquid){72}else{34}),255,255,255)
    $glint=[System.Windows.Media.Color]::FromArgb([byte]$(if($liquid){30}else{24}),255,255,255)
    if($liquid){$Opacity=[byte][Math]::Max(120,[int]$Opacity-34)}
    $mid=[System.Windows.Media.Color]::FromArgb($Opacity,$base.R,$base.G,$base.B)
    $low=[System.Windows.Media.Color]::FromArgb([byte][Math]::Max(110,[int]$Opacity-18),$base.R,$base.G,$base.B)
    $brush.GradientStops.Add([System.Windows.Media.GradientStop]::new($top,0.0))
    $brush.GradientStops.Add([System.Windows.Media.GradientStop]::new($glint,$(if($liquid){0.10}else{0.16})))
    $brush.GradientStops.Add([System.Windows.Media.GradientStop]::new($mid,0.38))
    $brush.GradientStops.Add([System.Windows.Media.GradientStop]::new($low,0.78))
    $brush.GradientStops.Add([System.Windows.Media.GradientStop]::new($mid,1.0))
    return $brush
}
function New-BakaGlassRimBrush([string]$AccentHex){
    if($script:opaqueMode){return $script:borderBrush}
    $accent=ConvertTo-BakaColor $AccentHex
    $brush=[System.Windows.Media.LinearGradientBrush]::new()
    $brush.StartPoint=[System.Windows.Point]::new(0,0);$brush.EndPoint=[System.Windows.Point]::new(1,1)
    $brush.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromArgb([byte]112,255,255,255),0.0))
    $brush.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromArgb([byte]54,$accent.R,$accent.G,$accent.B),0.28))
    $brush.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromArgb([byte]22,255,255,255),0.62))
    $brush.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromArgb([byte]86,255,255,255),1.0))
    return $brush
}
function Update-BakaVisualTreeTheme($Element,$OldBrushes){
    if(-not $Element){return}
    foreach($propertyName in @('Foreground','Background','BorderBrush')){
        $property=$Element.GetType().GetProperty($propertyName)
        if(-not $property -or -not $property.CanWrite){continue}
        $current=$property.GetValue($Element,$null)
        if([object]::ReferenceEquals($current,$OldBrushes.Text)){$property.SetValue($Element,$script:textBrush,$null)}
        elseif([object]::ReferenceEquals($current,$OldBrushes.Muted)){$property.SetValue($Element,$script:mutedBrush,$null)}
        elseif([object]::ReferenceEquals($current,$OldBrushes.Accent)){$property.SetValue($Element,$script:accentBrush,$null)}
        elseif([object]::ReferenceEquals($current,$OldBrushes.Surface)){$property.SetValue($Element,$script:surfaceBrush,$null)}
        elseif($OldBrushes.Glass -and [object]::ReferenceEquals($current,$OldBrushes.Glass)){$property.SetValue($Element,$script:glassBrush,$null)}
        elseif([object]::ReferenceEquals($current,$OldBrushes.SurfaceAlt)){$property.SetValue($Element,$script:surfaceAltBrush,$null)}
        elseif([object]::ReferenceEquals($current,$OldBrushes.Border)){$property.SetValue($Element,$script:borderBrush,$null)}
        elseif($OldBrushes.Rim -and [object]::ReferenceEquals($current,$OldBrushes.Rim)){$property.SetValue($Element,$script:rimBrush,$null)}
        elseif($OldBrushes.Ring -and [object]::ReferenceEquals($current,$OldBrushes.Ring)){$property.SetValue($Element,$script:ringBrush,$null)}
    }
    try{$count=[System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Element);for($i=0;$i -lt $count;$i++){Update-BakaVisualTreeTheme ([System.Windows.Media.VisualTreeHelper]::GetChild($Element,$i)) $OldBrushes}}catch{}
}
function Set-BakaTheme([string]$Name){
    $oldBrushes=@{Text=$script:textBrush;Muted=$script:mutedBrush;Accent=$script:accentBrush;Surface=$script:surfaceBrush;Glass=$script:glassBrush;SurfaceAlt=$script:surfaceAltBrush;Border=$script:borderBrush;Rim=$script:rimBrush}
    $script:theme=Get-BakaTheme $Name
    if(-not $script:theme){throw "Theme '$Name' is unavailable."}
    $highContrast=[System.Windows.SystemParameters]::HighContrast
    $remote=$false
    try{$remote=([System.Windows.Forms.SystemInformation]::TerminalServerSession)}catch{}
    $script:opaqueMode=($highContrast -or $remote -or $script:dwmBackdropUnsupported -or $script:theme.backdrop -eq 'Opaque' -or $script:activeProfile -ne 'Desktop')
    $script:motionEnabled=(-not $highContrast -and -not $remote -and -not [bool]$script:config.appearance.reducedMotion -and $script:config.appearance.animationIntensity -ne 'Off' -and $script:theme.animations -ne 'Off' -and $script:activeProfile -eq 'Desktop')
    $requested=[int]$script:config.appearance.glassIntensity
    $script:surfaceAlpha=if($script:opaqueMode){[byte]255}else{[byte][math]::Max(158,(255-[math]::Min(88,($requested*2.1))))}
    $script:canvasBrush=New-BakaBrush $script:theme.canvas 255
    $script:surfaceBrush=New-BakaBrush $script:theme.surface $script:surfaceAlpha
    $script:glassBrush=if($script:opaqueMode){$script:surfaceBrush}else{New-BakaGlassBrush $script:theme.surface $script:surfaceAlpha}
    $script:surfaceAltBrush=New-BakaBrush $script:theme.surfaceAlt ([byte][math]::Min(255,([int]$script:surfaceAlpha+7)))
    $script:textBrush=New-BakaBrush $script:theme.text 255
    $script:mutedBrush=New-BakaBrush $script:theme.muted 255
    $script:borderBrush=New-BakaBrush $script:theme.border 255
    $accent=if(Test-BakaHexColor $script:config.appearance.accentColor){$script:config.appearance.accentColor}else{$script:theme.accent}
    $script:accentBrush=New-BakaBrush $accent 255
    $script:rimBrush=New-BakaGlassRimBrush $accent
    # Pop Glass: SekaiPop-style keycap blocks (cream ring + hard drop shadow) on Apple-style liquid glass.
    $script:popStyle=([string]$script:theme.style -eq 'PopGlass')
    $script:ringBrush=if($script:popStyle -and $script:theme.ring){New-BakaBrush ([string]$script:theme.ring) 235}else{$script:borderBrush}
    $script:keycapShadowColor=if($script:theme.shadow){ConvertTo-BakaColor ([string]$script:theme.shadow)}else{[System.Windows.Media.Colors]::Black}
    $script:accent2Brush=if($script:theme.accent2){New-BakaBrush ([string]$script:theme.accent2) 255}else{$script:accentBrush}
    $oldBrushes.Ring=$script:previousRingBrush;$script:previousRingBrush=$script:ringBrush
    foreach($key in @('Dashboard','Files','Dock','Quick','TopBar','Settings')){if($script:windows[$key]){Set-BakaWindowSurface $script:windows[$key];Update-BakaVisualTreeTheme $script:windows[$key] $oldBrushes}}
    foreach($widget in @($script:widgetWindows.Values|Where-Object {$_ -is [System.Windows.Window]})){Set-BakaWindowSurface $widget;Update-BakaVisualTreeTheme $widget $oldBrushes}
}
function Set-BakaOpaqueFallback($Window){
    $oldBrushes=@{Text=$script:textBrush;Muted=$script:mutedBrush;Accent=$script:accentBrush;Surface=$script:surfaceBrush;Glass=$script:glassBrush;SurfaceAlt=$script:surfaceAltBrush;Border=$script:borderBrush;Rim=$script:rimBrush}
    $script:opaqueMode=$true;$script:dwmBackdropUnsupported=$true;$script:surfaceAlpha=255
    $script:surfaceBrush=New-BakaBrush $script:theme.surface 255;$script:glassBrush=$script:surfaceBrush
    $script:surfaceAltBrush=New-BakaBrush $script:theme.surfaceAlt 255;$script:borderBrush=New-BakaBrush $script:theme.border 255
    $script:rimBrush=$script:borderBrush
    $accent=if(Test-BakaHexColor $script:config.appearance.accentColor){$script:config.appearance.accentColor}else{$script:theme.accent}
    $script:accentBrush=New-BakaBrush $accent 255
    foreach($key in @('Dashboard','Files','Dock','Quick','TopBar','Settings')){
        $surfaceWindow=$script:windows[$key]
        if($surfaceWindow -and $surfaceWindow.Tag -and $surfaceWindow.Tag -is [System.Windows.Controls.Border]){$surfaceWindow.Tag.Background=$script:surfaceBrush;$surfaceWindow.Tag.BorderBrush=$script:borderBrush;$surfaceWindow.Tag.Effect=$null;Update-BakaVisualTreeTheme $surfaceWindow $oldBrushes}
    }
    foreach($widgetWindow in @($script:widgetWindows.Values|Where-Object {$_ -is [System.Windows.Window]})){
        if($widgetWindow.Tag -and $widgetWindow.Tag -is [System.Windows.Controls.Border]){$widgetWindow.Tag.Background=$script:surfaceBrush;$widgetWindow.Tag.BorderBrush=$script:borderBrush;$widgetWindow.Tag.Effect=$null;Update-BakaVisualTreeTheme $widgetWindow $oldBrushes}
    }
    if($Window -and $Window.Tag -and $Window.Tag -is [System.Windows.Controls.Border]){$Window.Tag.Background=$script:surfaceBrush;$Window.Tag.BorderBrush=$script:borderBrush;$Window.Tag.Effect=$null;Update-BakaVisualTreeTheme $Window $oldBrushes}
}
function Apply-BakaWindowBackdrop($Window){
    if($script:opaqueMode){return}
    try{
        $source=[System.Windows.Interop.HwndSource]::FromVisual($Window)
        if(-not $source){return}
        $backdrop=if($script:theme.backdrop -eq 'Acrylic'){3}else{2}
        $hr=[BakaLiquidNative]::DwmSetWindowAttribute($source.Handle,38,[ref]$backdrop,4)
        if($hr -ne 0){Set-BakaOpaqueFallback $Window;Write-BakaUiLog ('backdrop-fallback title="{0}" hresult=0x{1:X8}' -f $Window.Title,$hr);return}
        $corners=2;[void][BakaLiquidNative]::DwmSetWindowAttribute($source.Handle,33,[ref]$corners,4)
    }catch{Set-BakaOpaqueFallback $Window;Write-BakaUiLog ('backdrop-fallback title="{0}" error="{1}"' -f $Window.Title,$_.Exception.ToString())}
}
function Set-BakaWindowSurface($Window){
    if($Window.Tag -and $Window.Tag -is [System.Windows.Controls.Border]){
        $Window.Tag.Background=$script:glassBrush;$Window.Tag.BorderBrush=$script:rimBrush
        if($script:motionEnabled){$effect=[System.Windows.Media.Effects.DropShadowEffect]::new();$effect.Color=[System.Windows.Media.Colors]::Black;$effect.BlurRadius=26;$effect.ShadowDepth=5;$effect.Opacity=0.34;$Window.Tag.Effect=$effect}else{$Window.Tag.Effect=$null}
    }
    $Window.Background=[System.Windows.Media.Brushes]::Transparent
    if($script:backdropHookedWindows.Add($Window)){$Window.add_SourceInitialized({param($sender,$eventArgs) Apply-BakaWindowBackdrop $sender})}
    else{Apply-BakaWindowBackdrop $Window}
}
Set-BakaTheme $script:config.appearance.theme
function New-BakaWindow([double]$Width,[double]$Height,[string]$Name,[bool]$Topmost=$false){
    $window=[System.Windows.Window]::new();$window.Title=$Name;$window.Width=$Width;$window.Height=$Height
    $window.WindowStyle=[System.Windows.WindowStyle]::None;$window.ResizeMode=[System.Windows.ResizeMode]::NoResize
    $window.ShowInTaskbar=$false;$window.Topmost=$Topmost;$window.ShowActivated=$false
    $window.Background=[System.Windows.Media.Brushes]::Transparent
    $surface=[System.Windows.Controls.Border]::new();$surface.CornerRadius=[System.Windows.CornerRadius]::new(20)
    $surface.BorderThickness=[System.Windows.Thickness]::new(1);$surface.Padding=[System.Windows.Thickness]::new(16)
    $surface.Background=$script:glassBrush;$surface.BorderBrush=$script:rimBrush
    $surface.ClipToBounds=$true
    $root=[System.Windows.Controls.Grid]::new()
    $contentHost=[System.Windows.Controls.Grid]::new();$contentHost.Background=[System.Windows.Media.Brushes]::Transparent;$contentHost.Tag='BAKAContentHost';$root.Children.Add($contentHost)|Out-Null
    $sheen=[System.Windows.Controls.Border]::new();$sheen.Width=138;$sheen.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Left;$sheen.VerticalAlignment=[System.Windows.VerticalAlignment]::Stretch;$sheen.Opacity=0;$sheen.IsHitTestVisible=$false
    $sheen.CornerRadius=[System.Windows.CornerRadius]::new(26)
    $sheenBrush=[System.Windows.Media.LinearGradientBrush]::new();$sheenBrush.StartPoint=[System.Windows.Point]::new(0,0);$sheenBrush.EndPoint=[System.Windows.Point]::new(1,0)
    $sheenBrush.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromArgb([byte]0,255,255,255),0.0))
    $sheenBrush.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromArgb([byte]12,255,255,255),0.3))
    $sheenBrush.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromArgb([byte]78,255,255,255),0.5))
    $sheenBrush.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromArgb([byte]30,255,255,255),0.57))
    $sheenBrush.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromArgb([byte]0,255,255,255),0.8))
    $sheenBrush.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromArgb([byte]0,255,255,255),1.0))
    $sheen.Background=$sheenBrush;$sheen.RenderTransform=[System.Windows.Media.TranslateTransform]::new(-180,0);$sheen.RenderTransformOrigin=[System.Windows.Point]::new(0.5,0.5)
    $sheen.Effect=[System.Windows.Media.Effects.DropShadowEffect]::new();$sheen.Effect.Color=[System.Windows.Media.Colors]::White;$sheen.Effect.BlurRadius=16;$sheen.Effect.ShadowDepth=0;$sheen.Effect.Opacity=0.24
    $root.Children.Add($sheen)|Out-Null
    # Liquid light: a soft specular highlight that follows the pointer across the glass (event-driven, no idle animation).
    $light=[System.Windows.Shapes.Ellipse]::new();$light.Width=260;$light.Height=260;$light.IsHitTestVisible=$false;$light.Opacity=0
    $light.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Left;$light.VerticalAlignment=[System.Windows.VerticalAlignment]::Top
    $lightBrush=[System.Windows.Media.RadialGradientBrush]::new()
    $lightBrush.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromArgb([byte]54,255,255,255),0.0))
    $lightBrush.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromArgb([byte]18,255,255,255),0.45))
    $lightBrush.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromArgb([byte]0,255,255,255),1.0))
    $light.Fill=$lightBrush;$lightTransform=[System.Windows.Media.TranslateTransform]::new(-300,-300);$light.RenderTransform=$lightTransform
    $root.Children.Add($light)|Out-Null
    # Specular rim: a thin inner highlight on the top edge, the way Apple's liquid glass catches light.
    $rim=[System.Windows.Controls.Border]::new();$rim.IsHitTestVisible=$false;$rim.Margin=[System.Windows.Thickness]::new(-15);$rim.CornerRadius=[System.Windows.CornerRadius]::new(25);$rim.BorderThickness=[System.Windows.Thickness]::new(1.2,1.2,0.6,0.4)
    $rimLight=[System.Windows.Media.LinearGradientBrush]::new();$rimLight.StartPoint=[System.Windows.Point]::new(0,0);$rimLight.EndPoint=[System.Windows.Point]::new(0,1)
    $rimLight.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromArgb([byte]150,255,255,255),0.0))
    $rimLight.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromArgb([byte]20,255,255,255),0.35))
    $rimLight.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.Color]::FromArgb([byte]0,255,255,255),1.0))
    $rim.BorderBrush=$rimLight;$root.Children.Add($rim)|Out-Null
    $window.add_MouseMove({param($sender,$eventArgs)
        if(-not $script:motionEnabled -or -not $sender.Tag -or -not $sender.Tag.Tag.Light){return}
        $info=$sender.Tag.Tag;$point=$eventArgs.GetPosition($info.Root)
        $info.LightTransform.X=$point.X-130;$info.LightTransform.Y=$point.Y-130
        if($info.Light.Opacity -lt 0.9){$info.Light.BeginAnimation([System.Windows.UIElement]::OpacityProperty,[System.Windows.Media.Animation.DoubleAnimation]::new(1.0,[TimeSpan]::FromMilliseconds(160)))}
    })
    $window.add_MouseLeave({param($sender,$eventArgs)if($sender.Tag -and $sender.Tag.Tag.Light){$sender.Tag.Tag.Light.BeginAnimation([System.Windows.UIElement]::OpacityProperty,[System.Windows.Media.Animation.DoubleAnimation]::new(0.0,[TimeSpan]::FromMilliseconds(260)))}})
    $surface.CornerRadius=[System.Windows.CornerRadius]::new(26)
    $surface.Child=$root;$surface.Tag=[pscustomobject]@{ContentHost=$contentHost;Sheen=$sheen;SheenBrush=$sheenBrush;SheenTransform=$sheen.RenderTransform;Light=$light;LightTransform=$lightTransform;Root=$root;Rim=$rim;HidePending=$false}
    $window.Content=$surface;$window.Tag=$surface
    Set-BakaWindowSurface $window
    return $window
}
function Get-BakaWindowContentHost($Window){
    if($Window -and $Window.Tag -and $Window.Tag.Tag -and $Window.Tag.Tag.ContentHost){return $Window.Tag.Tag.ContentHost}
    if($Window -and $Window.Tag){return $Window.Tag.Child}
    return $null
}
function Set-BakaWindowContent($Window,$Content){
    $contentHost=Get-BakaWindowContentHost $Window
    if($contentHost -is [System.Windows.Controls.Grid] -and $contentHost.Tag -eq 'BAKAContentHost'){$contentHost.Children.Clear();$contentHost.Children.Add($Content)|Out-Null}
    elseif($Window -and $Window.Tag){$Window.Tag.Child=$Content}
}
function Start-BakaGlassSweep($Window){
    if(-not $script:motionEnabled -or ($script:theme.name -ne 'BAKA Liquid' -and -not $script:popStyle) -or -not $Window.Tag.Tag.SheenTransform){return}
    $duration=[TimeSpan]::FromMilliseconds(1120);$sheen=$Window.Tag.Tag.Sheen;$transform=$Window.Tag.Tag.SheenTransform
    $slide=[System.Windows.Media.Animation.DoubleAnimation]::new(-180,($Window.ActualWidth+180),$duration)
    $slideEase=[System.Windows.Media.Animation.CubicEase]::new();$slideEase.EasingMode=[System.Windows.Media.Animation.EasingMode]::EaseInOut;$slide.EasingFunction=$slideEase
    $fade=[System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames]::new();$fade.Duration=$duration;$fade.FillBehavior=[System.Windows.Media.Animation.FillBehavior]::Stop
    [void]$fade.KeyFrames.Add([System.Windows.Media.Animation.LinearDoubleKeyFrame]::new(0.0,[System.Windows.Media.Animation.KeyTime]::FromPercent(0.0)))
    [void]$fade.KeyFrames.Add([System.Windows.Media.Animation.SplineDoubleKeyFrame]::new(0.76,[System.Windows.Media.Animation.KeyTime]::FromPercent(0.15)))
    [void]$fade.KeyFrames.Add([System.Windows.Media.Animation.LinearDoubleKeyFrame]::new(0.76,[System.Windows.Media.Animation.KeyTime]::FromPercent(0.58)))
    [void]$fade.KeyFrames.Add([System.Windows.Media.Animation.SplineDoubleKeyFrame]::new(0.0,[System.Windows.Media.Animation.KeyTime]::FromPercent(1.0)))
    $fade.KeyFrames[1].KeySpline=[System.Windows.Media.Animation.KeySpline]::new(0.16,0.0,0.2,1.0)
    $fade.KeyFrames[3].KeySpline=[System.Windows.Media.Animation.KeySpline]::new(0.4,0.0,0.8,1.0)
    $sheen.BeginAnimation([System.Windows.UIElement]::OpacityProperty,$fade)
    $transform.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty,$slide)
    Write-BakaUiLog ('ui-animation=liquid-glint title="{0}" durationMs=1120 peakOpacity=0.76' -f $Window.Title)
}
function Start-BakaWindowEntrance($Window){
    if(-not $Window -or -not $Window.Tag){return}
    $surface=$Window.Tag
    if(-not $script:motionEnabled){$surface.Opacity=1;return}
    $group=[System.Windows.Media.TransformGroup]::new();$scale=[System.Windows.Media.ScaleTransform]::new(0.92,0.92);$translate=[System.Windows.Media.TranslateTransform]::new(0,24);$tilt=[System.Windows.Media.RotateTransform]::new(-0.8)
    $group.Children.Add($scale);$group.Children.Add($translate);$group.Children.Add($tilt);$surface.RenderTransformOrigin=[System.Windows.Point]::new(0.5,0.5);$surface.RenderTransform=$group;$surface.Opacity=0
    $full=($script:config.appearance.animationIntensity -eq 'Full' -and $script:theme.animations -eq 'Full')
    $scaleDuration=[TimeSpan]::FromMilliseconds($(if($full){520}else{280}));$moveDuration=[TimeSpan]::FromMilliseconds($(if($full){440}else{240}))
    $fade=[System.Windows.Media.Animation.DoubleAnimation]::new(1.0,[TimeSpan]::FromMilliseconds($(if($full){340}else{250})));$fadeEase=[System.Windows.Media.Animation.CubicEase]::new();$fadeEase.EasingMode=[System.Windows.Media.Animation.EasingMode]::EaseOut;$fade.EasingFunction=$fadeEase
    $scaleAnimation=[System.Windows.Media.Animation.DoubleAnimation]::new(1.0,$scaleDuration);$spring=[System.Windows.Media.Animation.BackEase]::new();$spring.EasingMode=[System.Windows.Media.Animation.EasingMode]::EaseOut;$spring.Amplitude=0.18;$scaleAnimation.EasingFunction=$spring
    $move=[System.Windows.Media.Animation.DoubleAnimation]::new(0.0,$moveDuration);$moveEase=[System.Windows.Media.Animation.CubicEase]::new();$moveEase.EasingMode=[System.Windows.Media.Animation.EasingMode]::EaseOut;$move.EasingFunction=$moveEase
    $tiltAnimation=[System.Windows.Media.Animation.DoubleAnimation]::new(0.0,[TimeSpan]::FromMilliseconds($(if($full){460}else{250})));$tiltEase=[System.Windows.Media.Animation.CubicEase]::new();$tiltEase.EasingMode=[System.Windows.Media.Animation.EasingMode]::EaseOut;$tiltAnimation.EasingFunction=$tiltEase
    $variant='glide'
    if($script:popStyle -and $full){
        # SekaiPop motion: things pop in on a spring instead of fading. The Quick Panel is a phone that
        # bounces up from the bottom edge; Settings is the same phone turning into landscape.
        $pop=[System.Windows.Media.Animation.ElasticEase]::new();$pop.Oscillations=1;$pop.Springiness=5;$pop.EasingMode=[System.Windows.Media.Animation.EasingMode]::EaseOut
        $rise=[System.Windows.Media.Animation.BackEase]::new();$rise.Amplitude=0.42;$rise.EasingMode=[System.Windows.Media.Animation.EasingMode]::EaseOut
        $fade=[System.Windows.Media.Animation.DoubleAnimation]::new(1.0,[TimeSpan]::FromMilliseconds(170))
        if($Window.Title -eq 'BAKA Quick Panel'){
            $variant='phone-rise';$scale.ScaleX=0.94;$scale.ScaleY=0.94;$translate.Y=[math]::Max(260,$Window.Height*0.8);$tilt.Angle=0
            $scaleAnimation=[System.Windows.Media.Animation.DoubleAnimation]::new(1.0,[TimeSpan]::FromMilliseconds(560));$scaleAnimation.EasingFunction=$rise
            $move=[System.Windows.Media.Animation.DoubleAnimation]::new(0.0,[TimeSpan]::FromMilliseconds(620));$move.EasingFunction=$rise
            $tiltAnimation=[System.Windows.Media.Animation.DoubleAnimation]::new(0.0,[TimeSpan]::FromMilliseconds(10))
        }elseif($Window.Title -eq 'BAKA Liquid Settings'){
            $variant='phone-rotate';$scale.ScaleX=0.55;$scale.ScaleY=0.55;$translate.Y=40;$tilt.Angle=-90
            $scaleAnimation=[System.Windows.Media.Animation.DoubleAnimation]::new(1.0,[TimeSpan]::FromMilliseconds(640));$scaleAnimation.EasingFunction=$rise
            $move=[System.Windows.Media.Animation.DoubleAnimation]::new(0.0,[TimeSpan]::FromMilliseconds(520));$move.EasingFunction=$rise
            $tiltAnimation=[System.Windows.Media.Animation.DoubleAnimation]::new(0.0,[TimeSpan]::FromMilliseconds(600));$tiltAnimation.EasingFunction=$rise
        }else{
            $variant='pop';$scale.ScaleX=0.62;$scale.ScaleY=0.62;$translate.Y=10;$tilt.Angle=0
            $scaleAnimation=[System.Windows.Media.Animation.DoubleAnimation]::new(1.0,[TimeSpan]::FromMilliseconds(620));$scaleAnimation.EasingFunction=$pop
        }
    }
    $surface.BeginAnimation([System.Windows.UIElement]::OpacityProperty,$fade)
    $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty,$scaleAnimation);$scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty,$scaleAnimation)
    $translate.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty,$move)
    $tilt.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty,$tiltAnimation)
    Write-BakaUiLog ('ui-animation=surface-entrance title="{0}" profile={1} intensity={2} variant={3}' -f $Window.Title,$script:activeProfile,$script:config.appearance.animationIntensity,$variant)
    Start-BakaGlassSweep $Window
}
function Hide-BakaWindow($Window){
    # SekaiPop "swallow": the surface shrinks and drops away instead of blinking out.
    if(-not $Window -or -not $Window.IsVisible){return}
    if(-not $script:motionEnabled -or -not $script:popStyle -or -not $Window.Tag -or -not $Window.Tag.Tag){$Window.Hide();return}
    $surface=$Window.Tag;$surface.Tag.HidePending=$true
    $scale=[System.Windows.Media.ScaleTransform]::new(1,1);$surface.RenderTransformOrigin=[System.Windows.Point]::new(0.5,0.6);$surface.RenderTransform=$scale
    $ease=[System.Windows.Media.Animation.BackEase]::new();$ease.Amplitude=0.3;$ease.EasingMode=[System.Windows.Media.Animation.EasingMode]::EaseIn
    $shrink=[System.Windows.Media.Animation.DoubleAnimation]::new(0.78,[TimeSpan]::FromMilliseconds(170));$shrink.EasingFunction=$ease
    $fade=[System.Windows.Media.Animation.DoubleAnimation]::new(0.0,[TimeSpan]::FromMilliseconds(170))
    $fade.Add_Completed({if($surface.Tag.HidePending){$surface.Tag.HidePending=$false;$Window.Hide();$surface.BeginAnimation([System.Windows.UIElement]::OpacityProperty,$null);$surface.Opacity=1;$surface.RenderTransform=$null}}.GetNewClosure())
    $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty,$shrink);$scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty,$shrink)
    $surface.BeginAnimation([System.Windows.UIElement]::OpacityProperty,$fade)
    Write-BakaUiLog ('ui-animation=surface-swallow title="{0}"' -f $Window.Title)
}
function Show-BakaWindow($Window,[switch]$Activate){
    if(-not $Window){return}
    if($Window.Tag -and $Window.Tag.Tag -and $Window.Tag.Tag.PSObject.Properties['HidePending'] -and $Window.Tag.Tag.HidePending){
        $Window.Tag.Tag.HidePending=$false;$Window.Tag.BeginAnimation([System.Windows.UIElement]::OpacityProperty,$null);$Window.Tag.Opacity=1;$Window.Tag.RenderTransform=$null
    }
    $animate=(-not $Window.IsVisible -and $script:motionEnabled)
    if($animate){$Window.Tag.Opacity=0}
    $Window.Show()
    if($animate){Start-BakaWindowEntrance $Window}
    if($Activate){$Window.Activate()}
}
function New-BakaText([string]$Text,[double]$Size=13,[string]$Weight='Normal',[System.Windows.Media.Brush]$Color=$script:textBrush){
    $control=[System.Windows.Controls.TextBlock]::new();$control.Text=$Text;$control.FontFamily=[System.Windows.Media.FontFamily]::new('Segoe UI Variable')
    $control.FontSize=$Size;$control.FontWeight=if($Weight -eq 'Bold'){[System.Windows.FontWeights]::SemiBold}else{[System.Windows.FontWeights]::Normal}
    $control.Foreground=$Color;$control.TextWrapping=[System.Windows.TextWrapping]::Wrap
    return $control
}
function Get-BakaPillTemplate([double]$Radius=14){
    # Rounded button chrome so every BAKA control is a soft pill/keycap instead of the square Win32 button.
    $key='pill-'+$Radius
    if($script:templateCache.ContainsKey($key)){return $script:templateCache[$key]}
    $xaml='<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button"><Border CornerRadius="{0}" Background="{{TemplateBinding Background}}" BorderBrush="{{TemplateBinding BorderBrush}}" BorderThickness="{{TemplateBinding BorderThickness}}" Padding="{{TemplateBinding Padding}}" SnapsToDevicePixels="True"><ContentPresenter HorizontalAlignment="{{TemplateBinding HorizontalContentAlignment}}" VerticalAlignment="{{TemplateBinding VerticalContentAlignment}}" RecognizesAccessKey="True"/></Border></ControlTemplate>' -f $Radius
    $template=[System.Windows.Markup.XamlReader]::Parse($xaml)
    $script:templateCache[$key]=$template
    return $template
}
function New-BakaKeycapShadow([double]$Depth=4){
    # SekaiPop block language: a hard shadow straight down (no blur), like a keycap.
    $shadow=[System.Windows.Media.Effects.DropShadowEffect]::new();$shadow.BlurRadius=0;$shadow.Direction=270;$shadow.ShadowDepth=$Depth;$shadow.Opacity=0.92;$shadow.Color=$script:keycapShadowColor
    return $shadow
}
function Set-BakaKeycap($Element,[double]$Depth=4){
    if(-not $Element -or -not $script:popStyle -or $script:activeProfile -ne 'Desktop'){return}
    $Element.BorderBrush=$script:ringBrush
    $Element.BorderThickness=[System.Windows.Thickness]::new(1.5)
    $Element.Effect=New-BakaKeycapShadow $Depth
    if(-not $Element.Resources.Contains('BAKA.Keycap')){
        $Element.Resources.Add('BAKA.Keycap',$Depth)
        $Element.Resources.Add('BAKA.KeycapMargin',$Element.Margin)
        # Press: the key sinks into its shadow. Release: it springs back up.
        $Element.Add_PreviewMouseLeftButtonDown({param($sender,$eventArgs)Set-BakaKeycapPressed $sender $true})
        $Element.Add_PreviewMouseLeftButtonUp({param($sender,$eventArgs)Set-BakaKeycapPressed $sender $false})
        $Element.Add_MouseLeave({param($sender,$eventArgs)if($sender.Resources.Contains('BAKA.KeycapDown')){Set-BakaKeycapPressed $sender $false}})
    }
}
function Set-BakaKeycapPressed($Element,[bool]$Pressed){
    if(-not $Element -or -not ($Element.Effect -is [System.Windows.Media.Effects.DropShadowEffect])){return}
    $depth=[double]$Element.Resources['BAKA.Keycap']
    if($Pressed){if(-not $Element.Resources.Contains('BAKA.KeycapDown')){$Element.Resources.Add('BAKA.KeycapDown',$true)}}elseif($Element.Resources.Contains('BAKA.KeycapDown')){$Element.Resources.Remove('BAKA.KeycapDown')}
    $target=if($Pressed){1.0}else{$depth}
    $animation=[System.Windows.Media.Animation.DoubleAnimation]::new($target,[TimeSpan]::FromMilliseconds($(if($Pressed){70}else{260})))
    if(-not $Pressed){$ease=[System.Windows.Media.Animation.ElasticEase]::new();$ease.Oscillations=1;$ease.Springiness=4;$ease.EasingMode=[System.Windows.Media.Animation.EasingMode]::EaseOut;$animation.EasingFunction=$ease}
    $Element.Effect.BeginAnimation([System.Windows.Media.Effects.DropShadowEffect]::ShadowDepthProperty,$animation)
    if($Pressed -and -not $Element.Resources.Contains('BAKA.KeycapSunk')){$Element.Resources['BAKA.KeycapMargin']=$Element.Margin;$Element.Resources['BAKA.KeycapSunk']=$true}
    elseif(-not $Pressed){if(-not $Element.Resources.Contains('BAKA.KeycapSunk')){return};$Element.Resources.Remove('BAKA.KeycapSunk')}
    else{return}
    $base=$Element.Resources['BAKA.KeycapMargin']
    $sink=$depth-1
    $Element.Margin=if($Pressed){[System.Windows.Thickness]::new($base.Left,$base.Top+$sink,$base.Right,[math]::Max(0,$base.Bottom-$sink))}else{$base}
}
function Start-BakaDockBounce($Button){
    # macOS-style launch bounce: the icon hops twice while the app starts.
    if(-not $script:motionEnabled -or -not $Button -or -not ($Button.Content -is [System.Windows.UIElement])){return}
    $content=$Button.Content
    if(-not ($content.RenderTransform -is [System.Windows.Media.TranslateTransform])){$content.RenderTransform=[System.Windows.Media.TranslateTransform]::new(0,0)}
    $hop=[System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames]::new();$hop.Duration=[TimeSpan]::FromMilliseconds(820)
    foreach($frame in @(@(0,0.0),@(-16,0.18),@(0,0.40),@(-8,0.58),@(0,0.76),@(0,1.0))){[void]$hop.KeyFrames.Add([System.Windows.Media.Animation.EasingDoubleKeyFrame]::new([double]$frame[0],[System.Windows.Media.Animation.KeyTime]::FromPercent([double]$frame[1]),([System.Windows.Media.Animation.QuadraticEase]::new())))}
    $content.RenderTransform.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty,$hop)
    Write-BakaUiLog 'ui-animation=dock-launch-bounce'
}
function Get-BakaImageSource([string]$Path,[int]$DecodeWidth=64){
    # Loads a user-chosen icon or image without locking the file.
    $expanded=[Environment]::ExpandEnvironmentVariables($Path)
    if([string]::IsNullOrWhiteSpace($expanded) -or -not (Test-Path -LiteralPath $expanded -PathType Leaf)){return $null}
    $cacheKey='img|'+$expanded+'|'+$DecodeWidth
    if($script:iconCache.ContainsKey($cacheKey)){return $script:iconCache[$cacheKey]}
    try{
        $image=[System.Windows.Media.Imaging.BitmapImage]::new()
        $image.BeginInit();$image.CacheOption=[System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad;$image.DecodePixelWidth=$DecodeWidth;$image.UriSource=[Uri]::new($expanded);$image.EndInit();$image.Freeze()
        $script:iconCache[$cacheKey]=$image;return $image
    }catch{Write-BakaUiLog ('icon-image-load-failed path="{0}" error="{1}"' -f $expanded,$_.Exception.Message);return $null}
}
function Get-BakaExecutableIconSource([string]$Path){
    $expanded=[Environment]::ExpandEnvironmentVariables($Path)
    if([string]::IsNullOrWhiteSpace($expanded) -or -not (Test-Path -LiteralPath $expanded -PathType Leaf)){return $null}
    $cacheKey='exe|'+$expanded
    if($script:iconCache.ContainsKey($cacheKey)){return $script:iconCache[$cacheKey]}
    try{
        $icon=[System.Drawing.Icon]::ExtractAssociatedIcon($expanded)
        if(-not $icon){return $null}
        $source=[System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($icon.Handle,[System.Windows.Int32Rect]::Empty,[System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
        $source.Freeze();$icon.Dispose()
        $script:iconCache[$cacheKey]=$source;return $source
    }catch{$script:iconCache[$cacheKey]=$null;return $null}
}
function Get-BakaAppIconSource($App){
    # Custom icon first, then the app's designed glyph, then the executable's own icon.
    $custom=[string]$App.iconPath
    if($custom){$source=Get-BakaImageSource $custom 96;if($source){return $source}}
    if(-not [string]::IsNullOrWhiteSpace([string]$App.glyph)){return $null}
    if([string]$App.kind -eq 'Executable'){return Get-BakaExecutableIconSource ([string]$App.target)}
    return $null
}
function New-BakaButton([string]$Label,[scriptblock]$Action,[string]$Glyph='',[string]$AccessibleLabel=$Label,[switch]$ShowIndicator,[System.Windows.Media.ImageSource]$IconSource=$null){
    $button=[System.Windows.Controls.Button]::new();$button.Padding=[System.Windows.Thickness]::new(10,8,10,8);$button.Margin=[System.Windows.Thickness]::new(3)
    $button.Background=[System.Windows.Media.Brushes]::Transparent;$button.BorderThickness=[System.Windows.Thickness]::new(0);$button.Foreground=$script:textBrush
    $button.Cursor=[System.Windows.Input.Cursors]::Hand;$button.ToolTip=$AccessibleLabel
    [System.Windows.Automation.AutomationProperties]::SetName($button,$AccessibleLabel)
    $content=[System.Windows.Controls.StackPanel]::new();$content.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center
    $tileSize=[math]::Max(26,[math]::Min(58,([double]$script:config.dock.iconSize-14)))
    $tile=[System.Windows.Controls.Border]::new();$tile.Width=$tileSize;$tile.Height=$tileSize;$tile.Margin=[System.Windows.Thickness]::new(0,0,0,4);$tile.CornerRadius=[System.Windows.CornerRadius]::new([math]::Min(16,$tileSize*0.32));$tile.Background=$script:surfaceAltBrush;$tile.BorderBrush=$script:borderBrush;$tile.BorderThickness=[System.Windows.Thickness]::new(1)
    Set-BakaKeycap $tile 4
    $iconText=if([string]::IsNullOrWhiteSpace($Glyph)){$Label.Substring(0,1).ToUpperInvariant()}else{$Glyph}
    $monogram=New-BakaText $iconText ([math]::Max(16,[math]::Min(29,$tileSize*0.52))) 'Bold' $script:accentBrush
    if($Glyph){$monogram.FontFamily=[System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')}
    $monogram.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center;$monogram.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$tile.Child=$monogram
    if($IconSource){
        $iconImage=[System.Windows.Controls.Image]::new();$iconImage.Source=$IconSource;$iconImage.Stretch=[System.Windows.Media.Stretch]::Uniform
        $iconImage.Width=$tileSize*0.68;$iconImage.Height=$tileSize*0.68;$iconImage.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center;$iconImage.VerticalAlignment=[System.Windows.VerticalAlignment]::Center
        [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($iconImage,[System.Windows.Media.BitmapScalingMode]::HighQuality);$tile.Child=$iconImage
    }
    $content.Children.Add($tile)|Out-Null
    $labelText=New-BakaText $Label 10 'Normal' $script:mutedBrush;$labelText.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center;$content.Children.Add($labelText)|Out-Null
    if($ShowIndicator){
        $indicator=[System.Windows.Shapes.Ellipse]::new();$indicator.Width=5;$indicator.Height=5;$indicator.Margin=[System.Windows.Thickness]::new(0,2,0,0);$indicator.Fill=$script:accentBrush;$indicator.Opacity=0;$indicator.IsHitTestVisible=$false
        $content.Children.Add($indicator)|Out-Null;$button.Resources.Add('BAKA.RunningIndicator',$indicator)
    }
    $button.Content=$content
    $button.Template=Get-BakaPillTemplate 18
    $button.Add_MouseEnter({param($sender,$eventArgs)$sender.Background=$script:surfaceAltBrush;$sender.Opacity=1;Set-BakaDockHover $sender;Set-BakaButtonHover $sender $true})
    $button.Add_MouseLeave({param($sender,$eventArgs)$sender.Background=[System.Windows.Media.Brushes]::Transparent;$sender.Opacity=0.92;Set-BakaDockHover $null;Set-BakaButtonHover $sender $false})
    $button.Add_Click($Action)
    return $button
}
function Set-BakaButtonMagnification($Button,[double]$Scale){
    if(-not $Button.RenderTransform -or $Button.RenderTransform -isnot [System.Windows.Media.ScaleTransform]){$Button.RenderTransform=[System.Windows.Media.ScaleTransform]::new(1,1);$Button.RenderTransformOrigin=[System.Windows.Point]::new(0.5,0.5)}
    $transform=$Button.RenderTransform
    $duration=if($script:theme.animations -eq 'Full'){220}else{140}
    $animation=[System.Windows.Media.Animation.DoubleAnimation]::new($Scale,[TimeSpan]::FromMilliseconds($duration))
    if($Scale -gt 1.0 -and $script:theme.animations -eq 'Full'){$ease=[System.Windows.Media.Animation.BackEase]::new();$ease.EasingMode=[System.Windows.Media.Animation.EasingMode]::EaseOut;$ease.Amplitude=0.16}
    else{$ease=[System.Windows.Media.Animation.CubicEase]::new();$ease.EasingMode=[System.Windows.Media.Animation.EasingMode]::EaseOut}
    $animation.EasingFunction=$ease
    $transform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty,$animation)
    $transform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty,$animation)
}
function Set-BakaDockHover($Button){
    if(-not $script:config.dock.magnification -or -not $script:motionEnabled -or -not $script:windows.DockAppPanel){return}
    $dockButtons=@($script:windows.DockAppPanel.Children|Where-Object {$_ -is [System.Windows.Controls.Button]})
    $hoverIndex=-1
    if($Button){for($i=0;$i -lt $dockButtons.Count;$i++){if([object]::ReferenceEquals($dockButtons[$i],$Button)){$hoverIndex=$i;break}}}
    for($i=0;$i -lt $dockButtons.Count;$i++){
        $distance=if($hoverIndex -lt 0){99}else{[Math]::Abs($i-$hoverIndex)}
        $scale=if($distance -eq 0){1.26}elseif($distance -eq 1){1.13}elseif($distance -eq 2){1.05}else{1.0}
        Set-BakaButtonMagnification $dockButtons[$i] $scale
    }
}
function Set-BakaButtonHover($Button,[bool]$IsHover){
    if(-not $Button){return}
    $tile=$null
    if($Button.Content -is [System.Windows.Controls.StackPanel] -and $Button.Content.Children.Count -gt 0){$tile=$Button.Content.Children[0]}
    if($tile -is [System.Windows.Controls.Border]){
        if($IsHover){$tile.BorderBrush=$script:accentBrush;$tile.Background=New-BakaBrush $script:theme.accent 82}
        else{$tile.BorderBrush=if($script:popStyle){$script:ringBrush}else{$script:borderBrush};$tile.Background=$script:surfaceAltBrush}
        if($script:motionEnabled){Set-BakaButtonMagnification $tile $(if($IsHover){1.10}else{1.0})}
    }
    elseif($script:motionEnabled){Set-BakaButtonMagnification $Button $(if($IsHover){1.035}else{1.0})}
}
function New-BakaActionButton([string]$Label,[scriptblock]$Action,[string]$Glyph=''){
    $button=[System.Windows.Controls.Button]::new();$button.Padding=[System.Windows.Thickness]::new(14,9,14,9);$button.Margin=[System.Windows.Thickness]::new(4)
    $button.Background=$script:surfaceAltBrush;$button.Foreground=$script:textBrush;$button.BorderBrush=$script:borderBrush;$button.BorderThickness=[System.Windows.Thickness]::new(1)
    $button.Cursor=[System.Windows.Input.Cursors]::Hand;$button.ToolTip=$Label;[System.Windows.Automation.AutomationProperties]::SetName($button,$Label)
    $content=[System.Windows.Controls.StackPanel]::new();$content.Orientation=[System.Windows.Controls.Orientation]::Horizontal;$content.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center
    if(-not [string]::IsNullOrWhiteSpace($Glyph)){
        $icon=New-BakaText $Glyph 15 'Normal' $script:accentBrush;$icon.FontFamily=[System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets');$icon.Width=22;$icon.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center;$icon.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$content.Children.Add($icon)|Out-Null
    }
    $text=New-BakaText $Label 12 'Normal' $script:textBrush;$text.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$content.Children.Add($text)|Out-Null
    $button.Content=$content
    $button.Template=Get-BakaPillTemplate 14
    Set-BakaKeycap $button 3
    $button.Add_MouseEnter({param($sender,$eventArgs)$sender.Background=New-BakaBrush $script:theme.accent 80;Set-BakaButtonHover $sender $true})
    $button.Add_MouseLeave({param($sender,$eventArgs)$sender.Background=$script:surfaceAltBrush;Set-BakaButtonHover $sender $false})
    $button.Add_Click($Action)
    return $button
}
function New-BakaHeading([string]$Title,[string]$Caption=''){
    $panel=[System.Windows.Controls.StackPanel]::new();$panel.Margin=[System.Windows.Thickness]::new(0,0,0,14)
    $panel.Children.Add((New-BakaText $Title 18 'Bold'))|Out-Null
    if($Caption){$panel.Children.Add((New-BakaText $Caption 11 'Normal' $script:mutedBrush))|Out-Null}
    return $panel
}
function New-BakaRow([string]$Title,[string]$Description,$Control){
    $grid=[System.Windows.Controls.Grid]::new();$grid.Margin=[System.Windows.Thickness]::new(0,8,0,8)
    $grid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
    $right=[System.Windows.Controls.ColumnDefinition]::new();$right.Width=[System.Windows.GridLength]::new(300);$grid.ColumnDefinitions.Add($right)
    $copy=[System.Windows.Controls.StackPanel]::new();$copy.Children.Add((New-BakaText $Title 12 'Bold'))|Out-Null
    if($Description){$copy.Children.Add((New-BakaText $Description 10 'Normal' $script:mutedBrush))|Out-Null}
    $grid.Children.Add($copy)|Out-Null;[System.Windows.Controls.Grid]::SetColumn($Control,1);$Control.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$grid.Children.Add($Control)|Out-Null
    return $grid
}
function Set-BakaSettingsControlTheme($Root){
    $pending=[System.Collections.Generic.Stack[System.Windows.DependencyObject]]::new();$pending.Push($Root)
    while($pending.Count){
        $control=$pending.Pop()
        if($control -is [System.Windows.Controls.ScrollViewer]){$control.Background=[System.Windows.Media.Brushes]::Transparent;$control.BorderBrush=$script:borderBrush}
        elseif($control -is [System.Windows.Controls.TabControl]){$control.Background=[System.Windows.Media.Brushes]::Transparent;$control.Foreground=$script:textBrush;$control.BorderBrush=$script:borderBrush}
        elseif($control -is [System.Windows.Controls.TabItem]){
            $control.Padding=[System.Windows.Thickness]::new(12,7,12,7)
            $tabStyle=[System.Windows.Style]::new([System.Windows.Controls.TabItem]);$tabStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.Control]::BackgroundProperty,$script:surfaceAltBrush));$tabStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.Control]::ForegroundProperty,$script:textBrush));$tabStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.Control]::BorderBrushProperty,$script:borderBrush));$tabStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.Control]::PaddingProperty,[System.Windows.Thickness]::new(12,7,12,7)))
            $selected=[System.Windows.Trigger]::new();$selected.Property=[System.Windows.Controls.TabItem]::IsSelectedProperty;$selected.Value=$true;$selected.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.Control]::BackgroundProperty,$script:surfaceBrush));$selected.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.Control]::ForegroundProperty,$script:accentBrush));$tabStyle.Triggers.Add($selected);$control.Style=$tabStyle
        }
        elseif($control -is [System.Windows.Controls.ComboBox]){
            $control.Background=$script:surfaceAltBrush;$control.Foreground=(New-BakaBrush '#17191E' 255);$control.BorderBrush=$script:borderBrush;$control.Padding=[System.Windows.Thickness]::new(7,5,7,5)
            $itemsStyle=[System.Windows.Style]::new([System.Windows.Controls.ComboBoxItem]);$itemsStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.Control]::BackgroundProperty,(New-BakaBrush '#F2F3F5' 255)));$itemsStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.Control]::ForegroundProperty,(New-BakaBrush '#17191E' 255)));$itemsStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.Control]::PaddingProperty,[System.Windows.Thickness]::new(8,5,8,5)));$control.ItemContainerStyle=$itemsStyle
        }
        elseif($control -is [System.Windows.Controls.TextBox]){$control.Background=$script:surfaceAltBrush;$control.Foreground=$script:textBrush;$control.BorderBrush=$script:borderBrush;$control.CaretBrush=$script:accentBrush;$control.Padding=[System.Windows.Thickness]::new(7,5,7,5);$control.FontFamily=[System.Windows.Media.FontFamily]::new('Segoe UI Variable')}
        elseif($control -is [System.Windows.Controls.ListBox]){$control.Background=$script:surfaceAltBrush;$control.Foreground=$script:textBrush;$control.BorderBrush=$script:borderBrush}
        elseif($control -is [System.Windows.Controls.CheckBox]){$control.Background=[System.Windows.Media.Brushes]::Transparent;$control.Foreground=$script:textBrush}
        elseif($control -is [System.Windows.Controls.Slider]){$control.Foreground=$script:accentBrush}
        elseif($control -is [System.Windows.Controls.Grid]){$control.Background=[System.Windows.Media.Brushes]::Transparent}
        try{foreach($child in [System.Windows.LogicalTreeHelper]::GetChildren($control)){if($child -is [System.Windows.DependencyObject]){$pending.Push($child)}}}catch{}
    }
}
function Get-BakaActiveScreen {
    $screens=[System.Windows.Forms.Screen]::AllScreens
    $preferred=[string]$script:config.dock.monitor
    $screen=if($preferred -eq 'Primary'){[System.Windows.Forms.Screen]::PrimaryScreen}else{@($screens|Where-Object {$_.DeviceName -eq $preferred})|Select-Object -First 1}
    if(-not $screen){$screen=[System.Windows.Forms.Screen]::PrimaryScreen}
    return $screen
}
function Get-BakaScreenByName([string]$MonitorName){
    $screens=[System.Windows.Forms.Screen]::AllScreens
    if([string]::IsNullOrWhiteSpace($MonitorName) -or $MonitorName -eq 'Primary'){return [System.Windows.Forms.Screen]::PrimaryScreen}
    $screen=@($screens|Where-Object {$_.DeviceName -eq $MonitorName}|Select-Object -First 1)
    if($screen){return $screen[0]}
    return [System.Windows.Forms.Screen]::PrimaryScreen
}
function Set-BakaTopBarPosition {
    if(-not $script:windows.TopBar){return}
    try{
        $screen=Get-BakaScreenByName ([string]$script:config.topBar.monitor)
        if(-not $screen){throw 'No display is available for the BAKA top bar.'}
        $area=$screen.WorkingArea
        $width=[double]$script:windows.TopBar.ActualWidth
        if($width -le 0){$width=[double]$script:windows.TopBar.Width}
        $script:windows.TopBar.Left=$area.Left+[Math]::Max(0,($area.Width-$width)/2)
        $script:windows.TopBar.Top=$area.Top+8
    }catch{Write-BakaUiLog ('topbar-position-failed error="{0}" stack="{1}"' -f $_.Exception.ToString(),$_.ScriptStackTrace)}
}
function Set-BakaDockPosition {
    if(-not $script:windows.Dock -or -not $script:windows.Dock.IsVisible){return}
    try{
        $screen=Get-BakaActiveScreen
        if(-not $screen){throw 'No active display is available for the BAKA dock.'}
        $area=$screen.WorkingArea
        $script:windows.Dock.Left=if($script:config.dock.alignment -eq 'Left'){$area.Left+18}elseif($script:config.dock.alignment -eq 'Right'){$area.Right-$script:windows.Dock.ActualWidth-18}else{$area.Left+($area.Width-$script:windows.Dock.ActualWidth)/2}
        $script:windows.Dock.Top=$area.Bottom-$script:windows.Dock.ActualHeight-16
    }catch{Write-BakaUiLog ('dock-position-failed error="{0}" stack="{1}"' -f $_.Exception.ToString(),$_.ScriptStackTrace);throw}
}
function Get-BakaDetectedGame {
    if($script:previewMode){return $null}
    $detection=$script:profileSettings.gameDetection
    $foreground=[BakaLiquidNative]::GetForegroundWindow()
    $fullscreenPid=0
    if($foreground -ne [IntPtr]::Zero -and $detection.fullscreenDetection){
        try{
            $rect=New-Object BakaLiquidNative+RECT
            if([BakaLiquidNative]::GetWindowRect($foreground,[ref]$rect)){
                $info=New-Object BakaLiquidNative+MONITORINFO;$info.cbSize=[Runtime.InteropServices.Marshal]::SizeOf($info)
                $monitor=[BakaLiquidNative]::MonitorFromWindow($foreground,2)
                if([BakaLiquidNative]::GetMonitorInfo($monitor,[ref]$info) -and $rect.Left -le $info.rcMonitor.Left -and $rect.Top -le $info.rcMonitor.Top -and $rect.Right -ge $info.rcMonitor.Right -and $rect.Bottom -ge $info.rcMonitor.Bottom){
                    $fullscreenPid=[int](Get-Process|Where-Object {$_.MainWindowHandle -eq $foreground}|Select-Object -First 1 -ExpandProperty Id)
                }
            }
        }catch{}
    }
    $processes=foreach($process in @(Get-Process -ErrorAction SilentlyContinue|Where-Object {$_.Id -ne $PID -and ($_.MainWindowHandle -ne [IntPtr]::Zero -or @($script:gameDefinitions|Where-Object processName -eq $_.ProcessName).Count)})){
        $path=$null;try{$path=$process.Path}catch{}
        [pscustomobject]@{ProcessName=$process.ProcessName;Path=$path;IsForegroundFullscreen=($fullscreenPid -ne 0 -and $process.Id -eq $fullscreenPid)}
    }
    $game=Resolve-BakaAnyGame -Processes @($processes) -Detection $detection
    # A game found only because it was fullscreen stays "running" while its process lives, so Alt+Tab
    # to the desktop does not flip the profile back and forth.
    if($game -and $game.Reason -eq 'Fullscreen'){$script:stickyGame=$game}
    elseif(-not $game -and $script:stickyGame){
        if(@($processes|Where-Object {$_.ProcessName -eq $script:stickyGame.ProcessName}).Count){$game=$script:stickyGame}else{$script:stickyGame=$null}
    }
    return $game
}
function Get-BakaProcessForApp($App){
    if([string]::IsNullOrWhiteSpace([string]$App.processName)){return $null}
    Get-Process -Name ([string]$App.processName) -ErrorAction SilentlyContinue|Where-Object {$_.MainWindowHandle -ne [IntPtr]::Zero}|Select-Object -First 1
}
function Open-BakaSystemSettings([string]$Uri){
    if($Uri -notmatch '^ms-settings:[a-z0-9.-]*$'){throw 'Only built-in Windows Settings pages can be opened from this panel.'}
    try{Start-Process -FilePath $Uri|Out-Null;Write-BakaUiLog ('windows-settings-opened uri={0}' -f $Uri)}catch{Write-BakaUiLog ('windows-settings-open-failed uri={0} error="{1}"' -f $Uri,$_.Exception.Message);[System.Windows.Forms.MessageBox]::Show(('Windows could not open this Settings page: {0}' -f $Uri),'BAKA Quick Panel',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)|Out-Null}
}
function Start-BakaPinnedApp($App){
    try {
        if([string]$App.id -eq 'explorer') { Show-BakaFiles;return }
        $process=Get-BakaProcessForApp $App
        if($process){
            $handle=$process.MainWindowHandle
            if([BakaLiquidNative]::GetForegroundWindow() -eq $handle){[void][BakaLiquidNative]::ShowWindow($handle,6)}
            else{[void][BakaLiquidNative]::ShowWindow($handle,9);[void][BakaLiquidNative]::SetForegroundWindow($handle)}
            return
        }
        if($script:dockButtons.ContainsKey([string]$App.id)){Start-BakaDockBounce $script:dockButtons[[string]$App.id]}
        if([string]$App.kind -eq 'Uri'){Start-Process -FilePath ([string]$App.target);return}
        $target=[Environment]::ExpandEnvironmentVariables([string]$App.target)
        if(-not (Test-Path -LiteralPath $target -PathType Leaf)){[System.Windows.MessageBox]::Show(('Application target not found:`n{0}' -f $target),[string]$App.name,[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Information)|Out-Null;return}
        if([string]::IsNullOrWhiteSpace([string]$App.arguments)){Start-Process -FilePath $target|Out-Null}else{Start-Process -FilePath $target -ArgumentList ([string]$App.arguments)|Out-Null}
        Write-BakaUiLog ('app-launched id={0}' -f $App.id)
    } catch {Write-BakaUiLog ('app-launch-failed id={0} error="{1}"' -f $App.id,$_.Exception.Message);[System.Windows.MessageBox]::Show($_.Exception.Message,'BAKA launch error',[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error)|Out-Null}
}
function Switch-BakaWindowFocus([IntPtr]$Handle){
    if($Handle -eq [IntPtr]::Zero){return}
    if([BakaLiquidNative]::GetForegroundWindow() -eq $Handle){[void][BakaLiquidNative]::ShowWindow($Handle,6)}
    else{[void][BakaLiquidNative]::ShowWindow($Handle,9);[void][BakaLiquidNative]::SetForegroundWindow($Handle)}
}

# ---- Running applications: the dock doubles as the taskbar while the native one is auto-hidden ----
$script:runningAppExclusions=@('explorer','TextInputHost','ShellExperienceHost','StartMenuExperienceHost','SearchHost','SearchApp','LockApp','SystemSettingsAdminFlows','Widgets','WidgetBoard','PhoneExperienceHost')
function Get-BakaRunningApps {
    $pinned=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach($app in @($script:config.pinnedApps)){if($app.processName){[void]$pinned.Add([string]$app.processName)}}
    $seen=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $result=[System.Collections.Generic.List[object]]::new()
    foreach($process in @(Get-Process -ErrorAction SilentlyContinue|Where-Object {$_.MainWindowHandle -ne [IntPtr]::Zero -and $_.Id -ne $PID -and -not [string]::IsNullOrWhiteSpace($_.MainWindowTitle)}|Sort-Object ProcessName)){
        $name=[string]$process.ProcessName
        if($name -in $script:runningAppExclusions -or $pinned.Contains($name) -or -not $seen.Add($name)){continue}
        $path=$null;try{$path=$process.Path}catch{}
        $result.Add([pscustomobject]@{ProcessName=$name;ProcessId=$process.Id;Title=[string]$process.MainWindowTitle;Path=$path})
        if($result.Count -ge 8){break}
    }
    return @($result.ToArray())
}
function Update-BakaDockRunningApps {
    $panel=$script:windows.DockRunningPanel
    if(-not $panel){return}
    $apps=if([bool]$script:config.taskbar.showRunningApps){@(Get-BakaRunningApps)}else{@()}
    $signature=(@($apps|ForEach-Object {$_.ProcessName+':'+$_.ProcessId}) -join '|')+'|'+$script:config.dock.iconSize
    if($signature -eq $script:runningAppSignature){return}
    $script:runningAppSignature=$signature
    $panel.Children.Clear()
    foreach($app in $apps){
        $label=$app.ProcessName;if($label.Length -gt 11){$label=$label.Substring(0,10)+'…'}
        $icon=if($app.Path){Get-BakaExecutableIconSource $app.Path}else{$null}
        $button=New-BakaButton $label {param($sender,$eventArgs)$info=$sender.Tag;$process=Get-Process -Id $info.ProcessId -ErrorAction SilentlyContinue;if(-not $process -or $process.MainWindowHandle -eq [IntPtr]::Zero){$process=Get-Process -Name $info.ProcessName -ErrorAction SilentlyContinue|Where-Object {$_.MainWindowHandle -ne [IntPtr]::Zero}|Select-Object -First 1};if($process){Switch-BakaWindowFocus $process.MainWindowHandle}} '' ('Switch to {0}' -f $app.Title) -ShowIndicator -IconSource $icon
        $button.Tag=$app;$button.ToolTip=$app.Title
        $button.Width=[double]$script:config.dock.iconSize+15;$button.Height=[double]$script:config.dock.iconSize+8;$button.Margin=[System.Windows.Thickness]::new([double]$script:config.dock.spacing/2,0,[double]$script:config.dock.spacing/2,0)
        if($button.Resources.Contains('BAKA.RunningIndicator')){$button.Resources['BAKA.RunningIndicator'].Opacity=1}
        $panel.Children.Add($button)|Out-Null
    }
    if($script:windows.DockRunningSeparator){$script:windows.DockRunningSeparator.Visibility=if($apps.Count){[System.Windows.Visibility]::Visible}else{[System.Windows.Visibility]::Collapsed}}
}

# ---- Native taskbar: auto-hidden while BAKA runs, restored on exit or when the option is turned off ----
function Invoke-BakaTaskbarMode {
    $want=[bool]$script:config.taskbar.autoHideWindowsTaskbar
    if($script:previewMode){Write-BakaUiLog ('taskbar-preview autoHide={0}' -f $want);return}
    try{
        $current=Get-BakaTaskbarAutoHide
        if($null -eq $current){Write-BakaUiLog 'taskbar-unavailable';return}
        if($want){
            if(-not (Test-Path -LiteralPath $script:taskbarStatePath -PathType Leaf)){[IO.File]::WriteAllText($script:taskbarStatePath,(@{PreviousAutoHide=[bool]$current;SavedAt=(Get-Date).ToString('o')}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))}
            if(-not $current){[void](Set-BakaTaskbarAutoHide -Enabled $true -Confirm:$false)}
            Write-BakaUiLog 'taskbar-autohide-enabled'
        }else{Restore-BakaTaskbarMode}
    }catch{Write-BakaUiLog ('taskbar-mode-failed error="{0}"' -f $_.Exception.Message)}
}
function Restore-BakaTaskbarMode {
    if($script:previewMode){return}
    try{
        if(-not (Test-Path -LiteralPath $script:taskbarStatePath -PathType Leaf)){return}
        $state=Get-Content -LiteralPath $script:taskbarStatePath -Raw|ConvertFrom-Json
        [void](Set-BakaTaskbarAutoHide -Enabled ([bool]$state.PreviousAutoHide) -Confirm:$false)
        Remove-Item -LiteralPath $script:taskbarStatePath -Force
        Write-BakaUiLog ('taskbar-restored autoHide={0}' -f [bool]$state.PreviousAutoHide)
    }catch{Write-BakaUiLog ('taskbar-restore-failed error="{0}"' -f $_.Exception.Message)}
}

# ---- Wallpaper: Windows default, any image, a solid color, or a looping video behind the desktop icons ----
function Get-BakaShippedWallpaperPath {
    foreach($candidate in @((Join-Path $dataRoot 'Assets\BAKA-BlackGlass-4K.png'),(Join-Path $dataRoot 'Assets\Wallpapers\BAKA-BlackGlass-4K.png'),(Join-Path $dataRoot 'Assets\BAKA-Liquid-Ribbon.png'),(Join-Path $dataRoot 'Assets\Wallpapers\BAKA-Liquid-Ribbon.png'))){if(Test-Path -LiteralPath $candidate -PathType Leaf){return $candidate}}
    return $null
}
function Stop-BakaVideoWallpaper {
    if(-not $script:videoWallpaper){return}
    try{$script:videoWallpaper.Media.Stop();$script:videoWallpaper.Media.Close()}catch{}
    try{$script:videoWallpaper.Window.Tag='closing';$script:videoWallpaper.Window.Close()}catch{}
    $script:videoWallpaper=$null
    Write-BakaUiLog 'video-wallpaper-stopped'
}
function Update-BakaVideoWallpaperPlayback {
    if(-not $script:videoWallpaper){return}
    $pause=($script:activeProfile -ne 'Desktop' -or $script:autoGame) -and [bool]$script:config.wallpaper.pauseInGames
    try{if($pause){$script:videoWallpaper.Media.Pause();Write-BakaUiLog 'video-wallpaper-paused'}else{$script:videoWallpaper.Media.Play()}}catch{}
}
function Start-BakaVideoWallpaper([string]$Path){
    Stop-BakaVideoWallpaper
    $bounds=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $virtual=[System.Windows.Forms.SystemInformation]::VirtualScreen
    $window=[System.Windows.Window]::new();$window.Title='BAKA Video Wallpaper';$window.WindowStyle=[System.Windows.WindowStyle]::None;$window.ResizeMode=[System.Windows.ResizeMode]::NoResize
    $window.ShowInTaskbar=$false;$window.ShowActivated=$false;$window.Focusable=$false;$window.Background=[System.Windows.Media.Brushes]::Black
    $window.Left=-32000;$window.Top=-32000;$window.Width=320;$window.Height=200
    $media=[System.Windows.Controls.MediaElement]::new()
    $media.LoadedBehavior=[System.Windows.Controls.MediaState]::Manual;$media.UnloadedBehavior=[System.Windows.Controls.MediaState]::Manual
    $media.IsMuted=[bool]$script:config.wallpaper.muted;$media.Volume=if($media.IsMuted){0}else{0.5}
    $media.Stretch=switch([string]$script:config.wallpaper.fit){'Fit'{[System.Windows.Media.Stretch]::Uniform}'Stretch'{[System.Windows.Media.Stretch]::Fill}'Center'{[System.Windows.Media.Stretch]::None}default{[System.Windows.Media.Stretch]::UniformToFill}}
    $media.Add_MediaEnded({param($sender,$eventArgs)$sender.Position=[TimeSpan]::Zero;$sender.Play()})
    $media.Add_MediaFailed({param($sender,$eventArgs)Write-BakaUiLog ('video-wallpaper-failed error="{0}"' -f $eventArgs.ErrorException.Message);Stop-BakaVideoWallpaper;$fallback=Get-BakaShippedWallpaperPath;if($fallback){try{[void](Set-BakaStaticWallpaper -Path $fallback -Fit Fill -Confirm:$false)}catch{}}})
    $media.Source=[Uri]::new($Path)
    $window.Content=$media
    $window.add_Closing({param($sender,$eventArgs)if($sender.Tag -ne 'closing' -and -not $script:allowShutdown){$eventArgs.Cancel=$true}})
    $window.Show()
    $handle=[System.Windows.Interop.WindowInteropHelper]::new($window).Handle
    $attached=Set-BakaWindowAsWallpaper -Handle $handle -Left ($bounds.X-$virtual.X) -Top ($bounds.Y-$virtual.Y) -Width $bounds.Width -Height $bounds.Height
    if(-not $attached){
        $window.Tag='closing';$window.Close()
        throw 'Windows did not expose a desktop wallpaper host for video playback.'
    }
    $script:videoWallpaper=@{Window=$window;Media=$media;Path=$Path}
    $media.Play()
    Update-BakaVideoWallpaperPlayback
    Write-BakaUiLog ('video-wallpaper-started path="{0}" muted={1}' -f $Path,$media.IsMuted)
}
function Invoke-BakaWallpaper([switch]$Force){
    $settings=$script:config.wallpaper
    $mode=[string]$settings.mode
    $path=[Environment]::ExpandEnvironmentVariables([string]$settings.path)
    if($script:previewMode){Write-BakaUiLog ('wallpaper-preview mode={0} kind={1} fit={2}' -f $mode,(Get-BakaWallpaperKind $path),$settings.fit);$script:wallpaperDirty=$false;return}
    try{
        switch($mode){
            'Video' {
                if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw "Video wallpaper not found: $path"}
                if(-not $script:videoWallpaper -or $script:videoWallpaper.Path -ne $path -or $Force){Start-BakaVideoWallpaper $path}else{Update-BakaVideoWallpaperPlayback}
            }
            'Image' {Stop-BakaVideoWallpaper;[void](Set-BakaStaticWallpaper -Path $path -Fit ([string]$settings.fit) -Confirm:$false);Write-BakaUiLog ('wallpaper-image path="{0}"' -f $path)}
            'Color' {Stop-BakaVideoWallpaper;[void](Set-BakaSolidColorWallpaper -Color ([string]$settings.color) -Confirm:$false);Write-BakaUiLog ('wallpaper-color color={0}' -f $settings.color)}
            default {Stop-BakaVideoWallpaper;if($Force){$shipped=Get-BakaShippedWallpaperPath;if($shipped){[void](Set-BakaStaticWallpaper -Path $shipped -Fit Fill -Confirm:$false)}}}
        }
    }catch{
        Write-BakaUiLog ('wallpaper-apply-failed mode={0} error="{1}"' -f $mode,$_.Exception.Message)
        if($Force){[System.Windows.Forms.MessageBox]::Show(('BAKA could not apply this wallpaper. Your previous desktop background was kept.`r`n`r`n{0}' -f $_.Exception.Message),'BAKA wallpaper',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning)|Out-Null}
    }
    $script:wallpaperDirty=$false
}

function Update-BakaProfileStatus {
    $mode=if($script:manualOverride){'MANUAL'}elseif($script:autoGame -and $script:detectedGame){'AUTO · '+$script:detectedGame.ToUpperInvariant()}else{'AUTO'}
    $label='{0}  ·  {1}  ·  BALANCED' -f $mode,$script:activeProfile.ToUpperInvariant()
    foreach($key in @('DockStatus','QuickStatus','BarStatus')){if($script:windows[$key]){$script:windows[$key].Text=$label}}
    if($script:windows.BarProfile -and $script:config.topBar.showProfile){$script:windows.BarProfile.Text=$script:activeProfile.ToUpperInvariant()}
    if($script:windows.DashNavStatus){$script:windows.DashNavStatus.Text=('{0}  /  {1}' -f $mode,$script:activeProfile.ToUpperInvariant())}
    if($script:windows.DashActiveProfile){$script:windows.DashActiveProfile.Text=$script:activeProfile.ToUpperInvariant()}
}
function Set-BakaUiProfile([string]$Profile,[string]$Reason='Manual'){
    $previous=$script:activeProfile
    $previousOverride=$script:manualOverride
    try {
        $result=Set-BakaCompanionProfile -Profile $Profile
        $script:activeProfile=$Profile
        if($Reason -eq 'Manual'){$script:manualOverride=$Profile}elseif($Reason -eq 'Auto'){$script:manualOverride=$null}
        if($Profile -ne 'Desktop'){
            if(-not $script:widgetsVisibleBeforeProfile){$script:widgetsVisibleBeforeProfile=@($script:widgetWindows.Values|Where-Object {$_ -is [System.Windows.Window] -and $_.IsVisible}).Count -gt 0}
            Hide-BakaWidgets
            if($script:windows.Dashboard){if($script:windows.Dashboard.IsVisible){$script:dashboardVisibleBeforeProfile=$true};$script:windows.Dashboard.Hide()}
        }elseif($previous -ne 'Desktop' -and $script:widgetsVisibleBeforeProfile -and $script:config.widgets.enabled){Show-BakaWidgets;$script:widgetsVisibleBeforeProfile=$false}
        # Arena only comes back if it was open before the game; it never pops over other apps on its own.
        if($Profile -eq 'Desktop' -and $script:windows.Dashboard -and -not $script:autoGame -and $script:dashboardVisibleBeforeProfile){$script:dashboardVisibleBeforeProfile=$false;Show-BakaDashboard}
        if($script:windows.Dock){Set-BakaDockAppearance;Set-BakaDockPosition}
        Set-BakaTheme $script:config.appearance.theme
        Update-BakaProfileStatus
        Update-BakaDockIndicators
        Update-BakaVideoWallpaperPlayback
        if($script:profileTimer){if($script:manualOverride){$script:profileTimer.Stop()}elseif(-not $script:profileTimer.IsEnabled){$script:profileTimer.Start()}}
        Write-BakaUiLog ('profile-change from={0} to={1} reason={2} reported-changes={3}' -f $previous,$Profile,$Reason,(@($result.Changed)-join ','))
        return $result
    } catch {
        $failure=$_.Exception.Message
        try {
            if($Profile -ne $previous){[void](Set-BakaCompanionProfile -Profile $previous)}
            $script:activeProfile=$previous;$script:manualOverride=$previousOverride
            Set-BakaTheme $script:config.appearance.theme
            Update-BakaProfileStatus
            if($script:profileTimer){if($script:manualOverride){$script:profileTimer.Stop()}elseif(-not $script:profileTimer.IsEnabled){$script:profileTimer.Start()}}
        } catch { Write-BakaUiLog ('profile-ui-rollback-failed error="{0}" original="{1}"' -f $_.Exception.Message,$failure) }
        Write-BakaUiLog ('profile-ui-change-failed from={0} requested={1} error="{2}"' -f $previous,$Profile,$failure)
        throw "BAKA could not apply profile '$Profile'; the previous profile '$previous' was restored where possible. $failure"
    }
}

function New-BakaArenaCard([double]$Width=0,[double]$Height=0,[int]$Alpha=210){
    $card=[System.Windows.Controls.Border]::new();if($Width -gt 0){$card.Width=$Width};if($Height -gt 0){$card.Height=$Height}
    $card.Margin=[System.Windows.Thickness]::new(6);$card.Padding=[System.Windows.Thickness]::new(16);$card.CornerRadius=[System.Windows.CornerRadius]::new(18)
    $card.Background=New-BakaBrush $script:theme.surfaceAlt ([byte]$Alpha);$card.BorderBrush=$script:borderBrush;$card.BorderThickness=[System.Windows.Thickness]::new(1)
    $shadow=[System.Windows.Media.Effects.DropShadowEffect]::new();$shadow.Color=[System.Windows.Media.Colors]::Black;$shadow.BlurRadius=22;$shadow.ShadowDepth=4;$shadow.Opacity=0.25;$card.Effect=$shadow
    return $card
}
function New-BakaArenaButton([string]$Label,[scriptblock]$Action,[string]$Glyph='',[switch]$Primary){
    $button=[System.Windows.Controls.Button]::new();$button.Padding=[System.Windows.Thickness]::new(15,10,15,10);$button.Margin=[System.Windows.Thickness]::new(4);$button.Cursor=[System.Windows.Input.Cursors]::Hand
    $button.Foreground=$script:textBrush;$button.BorderThickness=[System.Windows.Thickness]::new(1);$button.BorderBrush=if($Primary){$script:accentBrush}else{$script:borderBrush};$button.Background=if($Primary){New-BakaBrush $script:theme.accent 56}else{New-BakaBrush $script:theme.surfaceAlt 190}
    [System.Windows.Automation.AutomationProperties]::SetName($button,$Label)
    $row=[System.Windows.Controls.StackPanel]::new();$row.Orientation=[System.Windows.Controls.Orientation]::Horizontal;$row.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center
    if($Glyph){$icon=New-BakaText $Glyph 15 'Normal' $script:accentBrush;$icon.FontFamily=[System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets');$icon.Margin=[System.Windows.Thickness]::new(0,0,8,0);$row.Children.Add($icon)|Out-Null}
    $row.Children.Add((New-BakaText $Label 12 'Bold'))|Out-Null;$button.Content=$row
    $button.Add_MouseEnter({param($sender,$eventArgs)$sender.Background=New-BakaBrush $script:theme.accent $(if($sender.Tag -eq 'Primary'){108}else{72});if($script:motionEnabled){Set-BakaButtonMagnification $sender 1.035}})
    $button.Add_MouseLeave({param($sender,$eventArgs)$sender.Background=if($sender.Tag -eq 'Primary'){New-BakaBrush $script:theme.accent 56}else{New-BakaBrush $script:theme.surfaceAlt 190};if($script:motionEnabled){Set-BakaButtonMagnification $sender 1.0}})
    $button.Template=Get-BakaPillTemplate 16
    Set-BakaKeycap $button 4
    if($Primary){$button.Tag='Primary';$button.BorderBrush=$script:accentBrush};[void]$button.Add_Click($Action);return $button
}
function Update-BakaDashboardMetrics($Metrics){
    if(-not $script:windows.Dashboard -or -not $Metrics){return}
    $values=@{
        DashCpu=if($null -ne $Metrics.CpuPercent){'{0}%' -f $Metrics.CpuPercent}else{'--'}
        DashMemory=if($null -ne $Metrics.MemoryUsedMiB){'{0:N0} MB' -f $Metrics.MemoryUsedMiB}else{'--'}
        DashGpu=if($null -ne $Metrics.GpuEnginePeakPercent){'{0}%' -f $Metrics.GpuEnginePeakPercent}else{'N/A'}
        DashDisk=if($null -ne $Metrics.DiskFreeGiB){'{0:N0} GB' -f $Metrics.DiskFreeGiB}else{'--'}
    }
    foreach($name in $values.Keys){if($script:windows[$name]){$script:windows[$name].Text=$values[$name]}}
    if($script:windows.DashTelemetry){$script:windows.DashTelemetry.Text=('LIVE WINDOWS TELEMETRY  ·  UPDATED {0}' -f (Get-Date -Format 'HH:mm:ss'))}
}
function Show-BakaDashboard {
    if(-not $script:windows.Dashboard){return}
    $area=(Get-BakaActiveScreen).WorkingArea;$window=$script:windows.Dashboard
    $window.Left=$area.Left+([math]::Max(20,($area.Width-$window.Width)/2));$window.Top=$area.Top+([math]::Max(24,($area.Height-$window.Height)/2-22))
    Show-BakaWindow $window -Activate;Update-BakaWidgetPolling;Start-BakaMetricRead
}
function New-BakaDashboard {
    $window=New-BakaWindow 1120 760 'BAKA Arena' $false;$window.ShowInTaskbar=$false;$window.Topmost=[bool]$ArenaSmoke
    $layout=[System.Windows.Controls.Grid]::new();$layout.Margin=[System.Windows.Thickness]::new(4)
    foreach($height in @([System.Windows.GridLength]::new(58,[System.Windows.GridUnitType]::Pixel),[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star))){$row=[System.Windows.Controls.RowDefinition]::new();$row.Height=$height;$layout.RowDefinitions.Add($row)}
    $nav=[System.Windows.Controls.Grid]::new();$nav.Margin=[System.Windows.Thickness]::new(4,0,4,8);$nav.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new());$nav.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new());$nav.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new());
    $brandStack=[System.Windows.Controls.StackPanel]::new();$brandStack.Orientation=[System.Windows.Controls.Orientation]::Horizontal
    $brand=New-BakaText 'BAKA' 23 'Bold' $script:textBrush;$brandStack.Children.Add($brand)|Out-Null;$slash=New-BakaText '  /  ARENA' 13 'Bold' $script:accentBrush;$slash.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$brandStack.Children.Add($slash)|Out-Null
    $subtitle=New-BakaText 'LIQUID GLASS GAMING DESKTOP' 9 'Normal' $script:mutedBrush;$subtitle.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$subtitle.Margin=[System.Windows.Thickness]::new(16,0,0,0);$brandStack.Children.Add($subtitle)|Out-Null;$nav.Children.Add($brandStack)|Out-Null
    $navStatus=New-BakaText 'READY  /  BALANCED' 10 'Bold' $script:accentBrush;$navStatus.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center;$navStatus.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$navStatus.Name='DashNavStatus';$script:windows.DashNavStatus=$navStatus;[System.Windows.Controls.Grid]::SetColumn($navStatus,1);$nav.Children.Add($navStatus)|Out-Null
    $right=[System.Windows.Controls.StackPanel]::new();$right.Orientation=[System.Windows.Controls.Orientation]::Horizontal;$right.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Right
    $clock=New-BakaText (Get-Date -Format 'HH:mm') 12 'Bold' $script:textBrush;$clock.Name='DashClock';$script:windows.DashClock=$clock;$clock.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$right.Children.Add($clock)|Out-Null
    $hide=New-BakaArenaButton 'Hide' {Hide-BakaWindow $script:windows.Dashboard} ([string][char]0xE711);$hide.Padding=[System.Windows.Thickness]::new(11,7,11,7);$right.Children.Add($hide)|Out-Null;[System.Windows.Controls.Grid]::SetColumn($right,2);$nav.Children.Add($right)|Out-Null
    $layout.Children.Add($nav)|Out-Null
    $body=[System.Windows.Controls.Grid]::new();$body.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new());$body.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new());$body.ColumnDefinitions[0].Width=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star);$body.ColumnDefinitions[1].Width=[System.Windows.GridLength]::new(350,[System.Windows.GridUnitType]::Pixel);[System.Windows.Controls.Grid]::SetRow($body,1);$layout.Children.Add($body)|Out-Null
    $left=[System.Windows.Controls.Grid]::new();$left.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new());$left.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new());$left.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new());$left.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new());foreach($leftRow in $left.RowDefinitions){$leftRow.Height=[System.Windows.GridLength]::Auto};[System.Windows.Controls.Grid]::SetColumn($left,0);$body.Children.Add($left)|Out-Null
    $hero=New-BakaArenaCard 0 0 224;$hero.MinHeight=210;$hero.Margin=[System.Windows.Thickness]::new(6);$heroGrid=[System.Windows.Controls.Grid]::new();$heroGrid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new());$heroColumn=[System.Windows.Controls.ColumnDefinition]::new();$heroColumn.Width=[System.Windows.GridLength]::new(230,[System.Windows.GridUnitType]::Pixel);$heroGrid.ColumnDefinitions.Add($heroColumn);
    $heroCopy=[System.Windows.Controls.StackPanel]::new();$eyebrow=New-BakaText 'YOUR WINDOWS. TUNED WITH INTENT.' 10 'Bold' $script:accentBrush;$heroCopy.Children.Add($eyebrow)|Out-Null;$heroTitle=New-BakaText 'Game with intent.' 34 'Bold';$heroTitle.Margin=[System.Windows.Thickness]::new(0,8,0,3);$heroCopy.Children.Add($heroTitle)|Out-Null;$heroCopy.Children.Add((New-BakaText 'A focused desktop for play, creation, and control. Safe defaults stay native; every BAKA change is visible and reversible.' 12 'Normal' $script:mutedBrush))|Out-Null
    $heroActions=[System.Windows.Controls.WrapPanel]::new();$launch=New-BakaArenaButton 'Launch Gaming Mode' {try{[void](Set-BakaUiProfile 'CompetitiveGaming' 'Manual')}catch{[System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'BAKA profile',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)|Out-Null}} ([string][char]0xE7FC) -Primary;$heroActions.Children.Add($launch)|Out-Null;$control=New-BakaArenaButton 'Control center' {Show-BakaQuickPanel} ([string][char]0xE713);$heroActions.Children.Add($control)|Out-Null;[System.Windows.Controls.Grid]::SetColumn($heroCopy,0);$heroGrid.Children.Add($heroCopy)|Out-Null
    $heroBadge=New-BakaArenaCard 204 0 125;$heroBadge.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$heroBadge.Margin=[System.Windows.Thickness]::new(12,6,0,6);$badgeStack=[System.Windows.Controls.StackPanel]::new();$badge=New-BakaText 'ACTIVE PROFILE' 10 'Bold' $script:mutedBrush;$badgeStack.Children.Add($badge)|Out-Null;$active=New-BakaText 'DESKTOP' 28 'Bold' $script:accentBrush;$active.Name='DashActiveProfile';$script:windows.DashActiveProfile=$active;$badgeStack.Children.Add($active)|Out-Null;$badgeLine=New-BakaText 'Balanced power  ·  Native scheduler' 10 'Normal' $script:mutedBrush;$badgeLine.TextWrapping=[System.Windows.TextWrapping]::Wrap;$badgeStack.Children.Add($badgeLine)|Out-Null;$heroBadge.Child=$badgeStack;[System.Windows.Controls.Grid]::SetColumn($heroBadge,1);$heroGrid.Children.Add($heroBadge)|Out-Null;$hero.Child=$heroGrid;$left.Children.Add($hero)|Out-Null
    $profiles=[System.Windows.Controls.WrapPanel]::new();$profiles.Margin=[System.Windows.Thickness]::new(0,5,0,5);$profileData=@([pscustomobject]@{Name='Desktop';Label='DESKTOP';Glyph=[string][char]0xE80F;Copy='Glass + widgets + motion';Color='#7CE7FF'},[pscustomobject]@{Name='CompetitiveGaming';Label='COMPETITIVE';Glyph=[string][char]0xE7FC;Copy='Game Mode + low overhead';Color='#66F2C5'},[pscustomobject]@{Name='Benchmark';Label='BENCHMARK';Glyph=[string][char]0xE9D2;Copy='Clean, repeatable capture';Color='#C59BFF'})
    foreach($data in $profileData){$card=New-BakaArenaCard 205 0 200;$card.MinHeight=118;$card.Tag=$data.Name;$stack=[System.Windows.Controls.StackPanel]::new();$tag=New-BakaText $data.Label 11 'Bold' (New-BakaBrush $data.Color 255);$stack.Children.Add($tag)|Out-Null;$stack.Children.Add((New-BakaText $data.Copy 11 'Normal' $script:mutedBrush))|Out-Null;$button=New-BakaArenaButton 'Activate' {param($sender,$eventArgs)try{[void](Set-BakaUiProfile ([string]$sender.Tag) 'Manual')}catch{[System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'BAKA profile',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)|Out-Null}} $data.Glyph;$button.Tag=$data.Name;$button.Margin=[System.Windows.Thickness]::new(-4,8,0,0);$stack.Children.Add($button)|Out-Null;$card.Child=$stack;$profiles.Children.Add($card)|Out-Null}
    [System.Windows.Controls.Grid]::SetRow($profiles,1);$left.Children.Add($profiles)|Out-Null
    $metrics=[System.Windows.Controls.Primitives.UniformGrid]::new();$metrics.Columns=4;$metrics.Margin=[System.Windows.Thickness]::new(0,0,0,2);$metricData=@([pscustomobject]@{Name='DashCpu';Label='CPU LOAD';Value='--';Color='#7CE7FF'},[pscustomobject]@{Name='DashMemory';Label='MEMORY';Value='--';Color='#66F2C5'},[pscustomobject]@{Name='DashGpu';Label='GPU ENGINE';Value='N/A';Color='#C59BFF'},[pscustomobject]@{Name='DashDisk';Label='SYSTEM FREE';Value='--';Color='#FFCF70'})
    foreach($item in $metricData){$card=New-BakaArenaCard 0 0 190;$card.MinHeight=82;$card.Margin=[System.Windows.Thickness]::new(6);$stack=[System.Windows.Controls.StackPanel]::new();$stack.Children.Add((New-BakaText $item.Label 9 'Bold' $script:mutedBrush))|Out-Null;$value=New-BakaText $item.Value 24 'Bold' (New-BakaBrush $item.Color 255);$value.Name=$item.Name;$script:windows[$item.Name]=$value;$stack.Children.Add($value)|Out-Null;$card.Child=$stack;$metrics.Children.Add($card)|Out-Null};[System.Windows.Controls.Grid]::SetRow($metrics,2);$left.Children.Add($metrics)|Out-Null
    $session=New-BakaArenaCard 0 112 190;$sessionStack=[System.Windows.Controls.StackPanel]::new();$sessionStack.Children.Add((New-BakaText 'BAKA FOUNDATION' 10 'Bold' $script:accentBrush))|Out-Null;$sessionStack.Children.Add((New-BakaText 'A native Windows base with a BAKA control layer on top.' 12 'Bold'))|Out-Null;$sessionStack.Children.Add((New-BakaText 'Explorer recovery shell  ·  Balanced power  ·  Security preserved  ·  Every game detected automatically' 10 'Normal' $script:mutedBrush))|Out-Null;$sessionButton=New-BakaArenaButton 'Open BAKA Files workspace' {Show-BakaFiles} ([string][char]0xE8B7);$sessionButton.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Left;$sessionStack.Children.Add($sessionButton)|Out-Null;$session.Child=$sessionStack;[System.Windows.Controls.Grid]::SetRow($session,3);$left.Children.Add($session)|Out-Null
    $rightPanel=[System.Windows.Controls.StackPanel]::new();$rightPanel.Margin=[System.Windows.Thickness]::new(5,6,5,6);[System.Windows.Controls.Grid]::SetColumn($rightPanel,1);$body.Children.Add($rightPanel)|Out-Null
    $timeCard=New-BakaArenaCard 0 0 212;$timeStack=[System.Windows.Controls.StackPanel]::new();$timeStack.Children.Add((New-BakaText 'CLOCK  /  QUICK PANEL' 11 'Bold' $script:accentBrush))|Out-Null;$dashClockLarge=New-BakaText (Get-Date -Format 'HH:mm') 34 'Bold' $script:textBrush;$dashClockLarge.Name='DashClockLarge';$script:windows.DashClockLarge=$dashClockLarge;$timeStack.Children.Add($dashClockLarge)|Out-Null;$timeStack.Children.Add((New-BakaText (Get-Date -Format 'dddd, d MMMM yyyy') 10 'Normal' $script:mutedBrush))|Out-Null;$timeActions=[System.Windows.Controls.WrapPanel]::new();$timeActions.Children.Add((New-BakaArenaButton 'Quick Panel' {Show-BakaQuickPanel} ([string][char]0xE713)))|Out-Null;$timeActions.Children.Add((New-BakaArenaButton 'Calendar' {Show-BakaSettings 'Widgets'} ([string][char]0xE787)))|Out-Null;$timeStack.Children.Add($timeActions)|Out-Null;$timeCard.Child=$timeStack;$rightPanel.Children.Add($timeCard)|Out-Null
    $controlCard=New-BakaArenaCard 0 0 212;$controlStack=[System.Windows.Controls.StackPanel]::new();$controlStack.Children.Add((New-BakaText 'CONTROL CENTER' 11 'Bold' $script:accentBrush))|Out-Null;$controlStack.Children.Add((New-BakaText 'Your important controls, without pretending to replace Windows.' 11 'Normal' $script:mutedBrush))|Out-Null;$quickButtons=[System.Windows.Controls.WrapPanel]::new();$quickButtons.Children.Add((New-BakaArenaButton 'Quick Panel' {Show-BakaQuickPanel} ([string][char]0xE713)))|Out-Null;$quickButtons.Children.Add((New-BakaArenaButton 'Files' {Show-BakaFiles} ([string][char]0xE8B7)))|Out-Null;$quickButtons.Children.Add((New-BakaArenaButton 'Customize' {Show-BakaSettings} ([string][char]0xE70F)))|Out-Null;$controlStack.Children.Add($quickButtons)|Out-Null;$auto=New-BakaArenaButton 'Auto-detect every game' {$script:manualOverride=$null;if($script:profileTimer -and -not $script:profileTimer.IsEnabled){$script:profileTimer.Start()};Update-BakaProfileStatus} ([string][char]0xE768);$controlStack.Children.Add($auto)|Out-Null;$controlCard.Child=$controlStack;$rightPanel.Children.Add($controlCard)|Out-Null
    $ledger=New-BakaArenaCard 0 0 212;$ledgerStack=[System.Windows.Controls.StackPanel]::new();$ledgerStack.Children.Add((New-BakaText 'SAFE TWEAK LEDGER' 11 'Bold' $script:accentBrush))|Out-Null;$ledgerStack.Children.Add((New-BakaText 'Competitive Gaming applies only reversible user-level changes:' 10 'Normal' $script:mutedBrush))|Out-Null;foreach($line in @('✓ Windows Game Mode enabled','✓ Background apps paused','✓ Game DVR capture overhead off','✓ Balanced power preserved','✓ Security + recovery preserved')){$t=New-BakaText $line 10 'Normal' $script:textBrush;$t.Margin=[System.Windows.Thickness]::new(0,5,0,0);$ledgerStack.Children.Add($t)|Out-Null};$ledger.Child=$ledgerStack;$rightPanel.Children.Add($ledger)|Out-Null
    $telemetry=New-BakaText 'LIVE WINDOWS TELEMETRY  ·  WAITING' 9 'Bold' $script:mutedBrush;$telemetry.Name='DashTelemetry';$script:windows.DashTelemetry=$telemetry;$telemetry.Margin=[System.Windows.Thickness]::new(12,9,0,0);$rightPanel.Children.Add($telemetry)|Out-Null
    Set-BakaWindowContent $window $layout;$script:windows.Dashboard=$window;$window.add_Closing({param($sender,$eventArgs)if(-not $script:allowShutdown){$eventArgs.Cancel=$true;$sender.Hide()}});return $window
}

function Format-BakaFileSize([long]$Bytes){
    if($Bytes -lt 1KB){return ('{0} B' -f $Bytes)}
    if($Bytes -lt 1MB){return ('{0:N1} KB' -f ($Bytes/1KB))}
    if($Bytes -lt 1GB){return ('{0:N1} MB' -f ($Bytes/1MB))}
    return ('{0:N1} GB' -f ($Bytes/1GB))
}
function Get-BakaKnownFolderPath([string]$Name){
    switch($Name){
        'Home'{return [Environment]::GetFolderPath('UserProfile')}
        'Desktop'{return [Environment]::GetFolderPath('Desktop')}
        'Downloads'{return (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads')}
        'Documents'{return [Environment]::GetFolderPath('MyDocuments')}
        'Pictures'{return [Environment]::GetFolderPath('MyPictures')}
        'This PC'{return $null}
    }
    return $null
}
function Load-BakaFilesDirectory([string]$Path,[string]$Search=''){
    if(-not $script:fileExplorerList){return}
    if(-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)){
        if($script:fileExplorerStatus){$script:fileExplorerStatus.Text='Location unavailable'};return
    }
    try{
        $script:fileExplorerCurrent=[IO.Path]::GetFullPath($Path)
        if($script:fileExplorerAddress){$script:fileExplorerAddress.Text=$script:fileExplorerCurrent}
        $script:fileExplorerList.Items.Clear()
        $query=if([string]::IsNullOrWhiteSpace($Search)){$null}else{$Search.Trim()}
        $items=@(Get-ChildItem -LiteralPath $script:fileExplorerCurrent -Force -ErrorAction Stop|Where-Object {-not $query -or $_.Name -like ('*'+$query+'*')}|Sort-Object @{Expression={$_.PSIsContainer};Descending=$true},Name)
        foreach($item in $items){
            $kind=if($item.PSIsContainer){'Folder'}else{if($item.Extension){$item.Extension.TrimStart('.').ToUpperInvariant()+' file'}else{'File'}}
            $size=if($item.PSIsContainer){'—'}else{Format-BakaFileSize ([long]$item.Length)}
            [void]$script:fileExplorerList.Items.Add([pscustomobject]@{Name=[string]$item.Name;Type=$kind;Modified=$item.LastWriteTime.ToString('dd MMM yyyy  HH:mm');Size=$size;FullName=[string]$item.FullName;IsDirectory=[bool]$item.PSIsContainer})
        }
        if($script:fileExplorerStatus){$script:fileExplorerStatus.Text=('{0} items  ·  {1}' -f $items.Count,$script:fileExplorerCurrent)}
    }catch{if($script:fileExplorerStatus){$script:fileExplorerStatus.Text=('Cannot read this location  ·  '+$_.Exception.Message)}}
}
function Navigate-BakaFiles([string]$Path,[switch]$Remember){
    if(-not $Path){return}
    if($Remember -and $script:fileExplorerCurrent -and $script:fileExplorerCurrent -ne $Path){$script:fileExplorerHistory.Push($script:fileExplorerCurrent)}
    $query=if($script:fileExplorerSearch -and $script:fileExplorerSearch.Tag -ne 'Placeholder'){[string]$script:fileExplorerSearch.Text}else{''};Load-BakaFilesDirectory $Path $query
}
function Open-BakaFileSelection($Item){
    if(-not $Item){return}
    if($Item.IsDirectory){Navigate-BakaFiles ([string]$Item.FullName) -Remember;return}
    try{Start-Process -FilePath ([string]$Item.FullName)|Out-Null}catch{if($script:fileExplorerStatus){$script:fileExplorerStatus.Text=('Open failed  ·  '+$_.Exception.Message)}}
}
function Show-BakaFiles {
    if(-not $script:windows.Files){$script:windows.Files=New-BakaFileExplorer}
    $area=(Get-BakaActiveScreen).WorkingArea;$window=$script:windows.Files
    $window.Left=$area.Left+([math]::Max(16,($area.Width-$window.Width)/2));$window.Top=$area.Top+([math]::Max(16,($area.Height-$window.Height)/2-18))
    Show-BakaWindow $window -Activate;Load-BakaFilesDirectory $script:fileExplorerCurrent $(if($script:fileExplorerSearch.Tag -eq 'Placeholder'){''}else{[string]$script:fileExplorerSearch.Text})
}
function New-BakaFileExplorer {
    $window=New-BakaWindow 1280 760 'BAKA Files' $false;$window.ShowInTaskbar=$true;$window.Topmost=[bool]$FileSmoke
    $layout=[System.Windows.Controls.Grid]::new();$layout.Margin=[System.Windows.Thickness]::new(4)
    $toolbarRow=[System.Windows.Controls.RowDefinition]::new();$toolbarRow.Height=[System.Windows.GridLength]::new(68,[System.Windows.GridUnitType]::Pixel);$layout.RowDefinitions.Add($toolbarRow)
    $bodyRow=[System.Windows.Controls.RowDefinition]::new();$bodyRow.Height=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star);$layout.RowDefinitions.Add($bodyRow)
    $statusRow=[System.Windows.Controls.RowDefinition]::new();$statusRow.Height=[System.Windows.GridLength]::new(30,[System.Windows.GridUnitType]::Pixel);$layout.RowDefinitions.Add($statusRow)
    $toolbar=[System.Windows.Controls.Grid]::new();$toolbar.Margin=[System.Windows.Thickness]::new(4,0,4,10)
    foreach($width in @([System.Windows.GridLength]::new(48,[System.Windows.GridUnitType]::Pixel),[System.Windows.GridLength]::new(48,[System.Windows.GridUnitType]::Pixel),[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star),[System.Windows.GridLength]::new(58,[System.Windows.GridUnitType]::Pixel),[System.Windows.GridLength]::new(230,[System.Windows.GridUnitType]::Pixel),[System.Windows.GridLength]::new(84,[System.Windows.GridUnitType]::Pixel))){$column=[System.Windows.Controls.ColumnDefinition]::new();$column.Width=$width;$toolbar.ColumnDefinitions.Add($column)}
    $back=New-BakaArenaButton '' {if($script:fileExplorerHistory.Count -gt 0){Navigate-BakaFiles $script:fileExplorerHistory.Pop()}} ([string][char]0xE72B);$back.ToolTip='Back';$back.Margin=[System.Windows.Thickness]::new(2);[System.Windows.Controls.Grid]::SetColumn($back,0);$toolbar.Children.Add($back)|Out-Null
    $up=New-BakaArenaButton '' {try{ $parent=[IO.Directory]::GetParent($script:fileExplorerCurrent);if($parent){Navigate-BakaFiles $parent.FullName -Remember}}catch{}} ([string][char]0xE74A);$up.ToolTip='Up';$up.Margin=[System.Windows.Thickness]::new(2);[System.Windows.Controls.Grid]::SetColumn($up,1);$toolbar.Children.Add($up)|Out-Null
    $address=[System.Windows.Controls.TextBox]::new();$address.Text=$script:fileExplorerCurrent;$address.Padding=[System.Windows.Thickness]::new(12,8,12,8);$address.FontSize=12;$address.Background=New-BakaBrush $script:theme.surfaceAlt 210;$address.Foreground=$script:textBrush;$address.BorderBrush=$script:borderBrush;$address.VerticalContentAlignment=[System.Windows.VerticalAlignment]::Center;$script:fileExplorerAddress=$address;[System.Windows.Controls.Grid]::SetColumn($address,2);$toolbar.Children.Add($address)|Out-Null
    $go=New-BakaArenaButton 'Go' {Navigate-BakaFiles ([string]$script:fileExplorerAddress.Text)} ([string][char]0xE72A);$go.Margin=[System.Windows.Thickness]::new(4,2,4,2);[System.Windows.Controls.Grid]::SetColumn($go,3);$toolbar.Children.Add($go)|Out-Null
    $search=[System.Windows.Controls.TextBox]::new();$search.Text='Search this folder';$search.Padding=[System.Windows.Thickness]::new(12,8,12,8);$search.FontSize=11;$search.Background=New-BakaBrush $script:theme.surfaceAlt 210;$search.Foreground=$script:mutedBrush;$search.BorderBrush=$script:borderBrush;$search.VerticalContentAlignment=[System.Windows.VerticalAlignment]::Center;$search.Tag='Placeholder';$script:fileExplorerSearch=$search;$search.Add_GotFocus({param($sender,$eventArgs)if($sender.Tag -eq 'Placeholder'){$sender.Text='';$sender.Tag=''}});$search.Add_LostFocus({param($sender,$eventArgs)if([string]::IsNullOrWhiteSpace($sender.Text)){$sender.Text='Search this folder';$sender.Tag='Placeholder'}});$search.Add_KeyDown({param($sender,$eventArgs)if($eventArgs.Key -eq [System.Windows.Input.Key]::Enter){$query=if($sender.Tag -eq 'Placeholder'){''}else{[string]$sender.Text};Load-BakaFilesDirectory $script:fileExplorerCurrent $query}});[System.Windows.Controls.Grid]::SetColumn($search,4);$toolbar.Children.Add($search)|Out-Null
    $close=New-BakaArenaButton 'Close' {Hide-BakaWindow $script:windows.Files} ([string][char]0xE711);$close.Margin=[System.Windows.Thickness]::new(4,2,0,2);[System.Windows.Controls.Grid]::SetColumn($close,5);$toolbar.Children.Add($close)|Out-Null;$layout.Children.Add($toolbar)|Out-Null
    $body=[System.Windows.Controls.Grid]::new();$body.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new());$mainColumn=[System.Windows.Controls.ColumnDefinition]::new();$mainColumn.Width=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star);$body.ColumnDefinitions.Add($mainColumn);[System.Windows.Controls.Grid]::SetRow($body,1);$layout.Children.Add($body)|Out-Null
    $sidebar=[System.Windows.Controls.Border]::new();$sidebar.Width=210;$sidebar.Margin=[System.Windows.Thickness]::new(4,0,8,0);$sidebar.Padding=[System.Windows.Thickness]::new(8);$sidebar.Background=New-BakaBrush $script:theme.surface 178;$sidebar.BorderBrush=$script:borderBrush;$sidebar.BorderThickness=[System.Windows.Thickness]::new(1);$sideStack=[System.Windows.Controls.StackPanel]::new();$sideStack.Children.Add((New-BakaText 'BAKA FILES' 17 'Bold' $script:accentBrush))|Out-Null;$sideStack.Children.Add((New-BakaText 'Your Windows workspace' 10 'Normal' $script:mutedBrush))|Out-Null
    foreach($entry in @([pscustomobject]@{Name='Home';Glyph=[string][char]0xE80F},[pscustomobject]@{Name='Desktop';Glyph=[string][char]0xE7F4},[pscustomobject]@{Name='Downloads';Glyph=[string][char]0xE896},[pscustomobject]@{Name='Documents';Glyph=[string][char]0xE8A5},[pscustomobject]@{Name='Pictures';Glyph=[string][char]0xEB9F})){$button=New-BakaArenaButton $entry.Name {param($sender,$eventArgs)$path=Get-BakaKnownFolderPath ([string]$sender.Tag);if($path){Navigate-BakaFiles $path -Remember}} $entry.Glyph;$button.Tag=$entry.Name;$button.HorizontalContentAlignment=[System.Windows.HorizontalAlignment]::Left;$button.Margin=[System.Windows.Thickness]::new(0,5,0,0);$sideStack.Children.Add($button)|Out-Null}
    $sideStack.Children.Add((New-BakaText 'DRIVES' 10 'Bold' $script:mutedBrush))|Out-Null
    foreach($drive in @(Get-PSDrive -PSProvider FileSystem|Where-Object {$_.Root}|Sort-Object Name)){$button=New-BakaArenaButton ('{0}  {1}' -f $drive.Name,$drive.Root) {param($sender,$eventArgs)Navigate-BakaFiles ([string]$sender.Tag) -Remember} ([string][char]0xE7F4);$button.Tag=$drive.Root;$button.HorizontalContentAlignment=[System.Windows.HorizontalAlignment]::Left;$button.Margin=[System.Windows.Thickness]::new(0,5,0,0);$sideStack.Children.Add($button)|Out-Null}
    $sidebar.Child=$sideStack;[System.Windows.Controls.Grid]::SetColumn($sidebar,0);$body.Children.Add($sidebar)|Out-Null
    $main=[System.Windows.Controls.Grid]::new();$main.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new());$main.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new());$main.RowDefinitions[0].Height=[System.Windows.GridLength]::new(52,[System.Windows.GridUnitType]::Pixel);$main.RowDefinitions[1].Height=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star);[System.Windows.Controls.Grid]::SetColumn($main,1);$body.Children.Add($main)|Out-Null
    $heading=[System.Windows.Controls.StackPanel]::new();$heading.Orientation=[System.Windows.Controls.Orientation]::Horizontal;$heading.Children.Add((New-BakaText 'WORKSPACE' 13 'Bold'))|Out-Null;$heading.Children.Add((New-BakaText '  /  FILES' 13 'Bold' $script:accentBrush))|Out-Null;$heading.Children.Add((New-BakaText '  Native folders, BAKA command surface' 10 'Normal' $script:mutedBrush))|Out-Null;[System.Windows.Controls.Grid]::SetRow($heading,0);$main.Children.Add($heading)|Out-Null
    $list=[System.Windows.Controls.ListView]::new();$list.Background=New-BakaBrush $script:theme.surface 138;$list.Foreground=$script:textBrush;$list.BorderBrush=$script:borderBrush;$list.BorderThickness=[System.Windows.Thickness]::new(1);$list.Padding=[System.Windows.Thickness]::new(8);$view=[System.Windows.Controls.GridView]::new();foreach($column in @([pscustomobject]@{Header='NAME';Path='Name';Width=390},[pscustomobject]@{Header='TYPE';Path='Type';Width=120},[pscustomobject]@{Header='MODIFIED';Path='Modified';Width=180},[pscustomobject]@{Header='SIZE';Path='Size';Width=110})){$gridColumn=[System.Windows.Controls.GridViewColumn]::new();$gridColumn.Header=$column.Header;$gridColumn.Width=$column.Width;$gridColumn.DisplayMemberBinding=[System.Windows.Data.Binding]::new($column.Path);$view.Columns.Add($gridColumn)|Out-Null};$list.View=$view;$script:fileExplorerList=$list;$list.Add_MouseDoubleClick({param($sender,$eventArgs)Open-BakaFileSelection $sender.SelectedItem});[System.Windows.Controls.Grid]::SetRow($list,1);$main.Children.Add($list)|Out-Null
    $status=New-BakaText 'Loading BAKA Files…' 10 'Normal' $script:mutedBrush;$status.Margin=[System.Windows.Thickness]::new(14,4,0,0);$script:fileExplorerStatus=$status;[System.Windows.Controls.Grid]::SetRow($status,2);$layout.RowDefinitions[2].Height=[System.Windows.GridLength]::new(30,[System.Windows.GridUnitType]::Pixel);$layout.Children.Add($status)|Out-Null
    Set-BakaSettingsControlTheme $layout;Set-BakaWindowContent $window $layout;$script:windows.Files=$window;$window.add_Closing({param($sender,$eventArgs)if(-not $script:allowShutdown){$eventArgs.Cancel=$true;$sender.Hide()}});return $window
}

function New-BakaDock {
    $window=New-BakaWindow 820 108 'BAKA Arena Dock' $true
    $window.MinWidth=380;$window.MaxWidth=[math]::Max(760,[System.Windows.SystemParameters]::WorkArea.Width-36);$window.add_KeyDown({param($sender,$eventArgs) if($eventArgs.Key -eq [System.Windows.Input.Key]::Escape){$sender.Hide()}})
    $row=[System.Windows.Controls.StackPanel]::new();$row.Orientation=[System.Windows.Controls.Orientation]::Horizontal;$row.VerticalAlignment=[System.Windows.VerticalAlignment]::Center
    $brand=[System.Windows.Controls.StackPanel]::new();$brand.Width=154;$brand.Margin=[System.Windows.Thickness]::new(8,0,9,0)
    $brand.Children.Add((New-BakaText 'BAKA  /  ARENA' 17 'Bold'))|Out-Null
    $status=New-BakaText 'DESKTOP  ·  BALANCED' 9 'Normal' $script:accentBrush;$status.Name='DockStatus';$script:windows.DockStatus=$status;$brand.Children.Add($status)|Out-Null
    $start=New-BakaButton 'Start' {try{Invoke-BakaStartMenu}catch{Write-BakaUiLog ('start-menu-failed error="{0}"' -f $_.Exception.Message)}} ([string][char]0xE721) 'Open the Windows Start menu and search'
    $start.Width=70;$start.Height=[double]$script:config.dock.iconSize+8
    $start.Visibility=if([bool]$script:config.taskbar.showStartButton){[System.Windows.Visibility]::Visible}else{[System.Windows.Visibility]::Collapsed}
    $script:windows.DockStartButton=$start;$row.Children.Add($start)|Out-Null
    $row.Children.Add($brand)|Out-Null
    $separator=[System.Windows.Controls.Border]::new();$separator.Width=1;$separator.Height=48;$separator.Background=$script:borderBrush;$separator.Margin=[System.Windows.Thickness]::new(4,0,8,0);$row.Children.Add($separator)|Out-Null
    # Pop Glass keeps the dock clean like macOS: icons only, no wordmark.
    if($script:popStyle){$brand.Visibility=[System.Windows.Visibility]::Collapsed}
    $appPanel=[System.Windows.Controls.StackPanel]::new();$appPanel.Orientation=[System.Windows.Controls.Orientation]::Horizontal
    foreach($app in @($script:config.pinnedApps)){
        $button=New-BakaButton ([string]$app.name) ({param($sender,$eventArgs)Start-BakaPinnedApp $sender.Tag}) ([string]$app.glyph) ("Launch or focus {0}" -f $app.name) -ShowIndicator -IconSource (Get-BakaAppIconSource $app)
        $button.Tag=$app
        $button.Width=[double]$script:config.dock.iconSize+15;$button.Height=[double]$script:config.dock.iconSize+8;$button.Margin=[System.Windows.Thickness]::new([double]$script:config.dock.spacing/2,0,[double]$script:config.dock.spacing/2,0)
        $script:dockButtons[[string]$app.id]=$button;$appPanel.Children.Add($button)|Out-Null
    }
    $row.Children.Add($appPanel)|Out-Null
    $runningSeparator=[System.Windows.Controls.Border]::new();$runningSeparator.Width=1;$runningSeparator.Height=36;$runningSeparator.Background=$script:borderBrush;$runningSeparator.Margin=[System.Windows.Thickness]::new(6,0,6,0);$runningSeparator.Visibility=[System.Windows.Visibility]::Collapsed;$row.Children.Add($runningSeparator)|Out-Null
    $runningPanel=[System.Windows.Controls.StackPanel]::new();$runningPanel.Orientation=[System.Windows.Controls.Orientation]::Horizontal;$row.Children.Add($runningPanel)|Out-Null
    $script:windows.DockRunningPanel=$runningPanel;$script:windows.DockRunningSeparator=$runningSeparator
    $separator2=[System.Windows.Controls.Border]::new();$separator2.Width=1;$separator2.Height=48;$separator2.Background=$script:borderBrush;$separator2.Margin=[System.Windows.Thickness]::new(6,0,7,0);$row.Children.Add($separator2)|Out-Null
    $arena=New-BakaButton 'Arena' {Show-BakaDashboard} ([string][char]0xE80F) 'Open BAKA Arena dashboard';$arena.Width=70;$arena.Height=[double]$script:config.dock.iconSize+8;$row.Children.Add($arena)|Out-Null
    $files=New-BakaButton 'Files' {Show-BakaFiles} ([string][char]0xE8B7) 'Open BAKA Files';$files.Width=70;$files.Height=[double]$script:config.dock.iconSize+8;$row.Children.Add($files)|Out-Null
    $quick=New-BakaButton 'Control' {Show-BakaQuickPanel} ([string][char]0xE713) 'Open BAKA Quick Panel';$quick.Width=70;$quick.Height=[double]$script:config.dock.iconSize+8;$row.Children.Add($quick)|Out-Null
    $edit=New-BakaButton 'Customize' {Show-BakaSettings} ([string][char]0xE70F) 'Open desktop settings and editor';$edit.Width=82;$edit.Height=[double]$script:config.dock.iconSize+8;$row.Children.Add($edit)|Out-Null
    Set-BakaWindowContent $window $row
    $window.SizeToContent=[System.Windows.SizeToContent]::Width
    $script:windows.DockAppPanel=$appPanel
    $script:windows.DockUtilityButtons=@($start,$arena,$files,$quick,$edit)
    $window.add_SourceInitialized({try{Set-BakaDockPosition}catch{Write-BakaUiLog ('dock-sourceinit-failed error="{0}" stack="{1}"' -f $_.Exception.ToString(),$_.ScriptStackTrace)}})
    $window.add_SizeChanged({try{Set-BakaDockPosition}catch{Write-BakaUiLog ('dock-sizechanged-failed error="{0}" stack="{1}"' -f $_.Exception.ToString(),$_.ScriptStackTrace)}})
    $window.add_MouseEnter({param($sender,$eventArgs)
        if($script:dockHideTimer){$script:dockHideTimer.Stop()}
        if($script:motionEnabled){$sender.Tag.Opacity=1}
    })
    $window.add_MouseLeave({param($sender,$eventArgs)
        Set-BakaDockHover $null
        if($script:config.dock.autoHide -and -not $script:autoGame -and $script:dockHideTimer){$script:dockHideTimer.Stop();$script:dockHideTimer.Start()}
    })
    $window.add_Closing({param($sender,$eventArgs) if(-not $script:allowShutdown){$eventArgs.Cancel=$true;$sender.Hide()}})
    $script:windows.Dock=$window
    return $window
}

function New-BakaQuickTile([string]$Label,[string]$Glyph,[scriptblock]$Action){
    # A phone "app" tile: big glyph on a rounded keycap with the label underneath.
    $button=[System.Windows.Controls.Button]::new();$button.Width=88;$button.Height=82;$button.Margin=[System.Windows.Thickness]::new(5);$button.Padding=[System.Windows.Thickness]::new(4)
    $button.Background=$script:surfaceAltBrush;$button.Foreground=$script:textBrush;$button.BorderBrush=$script:borderBrush;$button.BorderThickness=[System.Windows.Thickness]::new(1)
    $button.Cursor=[System.Windows.Input.Cursors]::Hand;$button.ToolTip=$Label;[System.Windows.Automation.AutomationProperties]::SetName($button,$Label)
    $stackTile=[System.Windows.Controls.StackPanel]::new();$stackTile.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center;$stackTile.VerticalAlignment=[System.Windows.VerticalAlignment]::Center
    $icon=New-BakaText $Glyph 22 'Normal' $script:accentBrush;$icon.FontFamily=[System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets');$icon.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center;$stackTile.Children.Add($icon)|Out-Null
    $text=New-BakaText $Label 10 'Bold' $script:textBrush;$text.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center;$text.Margin=[System.Windows.Thickness]::new(0,6,0,0);$stackTile.Children.Add($text)|Out-Null
    $button.Content=$stackTile;$button.Template=Get-BakaPillTemplate 22
    $button.Add_MouseEnter({param($sender,$eventArgs)$sender.Background=New-BakaBrush $script:theme.accent 80;if($script:motionEnabled){Set-BakaButtonMagnification $sender 1.06}})
    $button.Add_MouseLeave({param($sender,$eventArgs)$sender.Background=$script:surfaceAltBrush;if($script:motionEnabled){Set-BakaButtonMagnification $sender 1.0}})
    Set-BakaKeycap $button 5
    $button.Add_Click($Action)
    return $button
}
function New-BakaQuickPanel {
    $window=New-BakaWindow 430 660 'BAKA Quick Panel' $true
    $stack=[System.Windows.Controls.StackPanel]::new();$stack.Margin=[System.Windows.Thickness]::new(4)
    # The Quick Panel is a phone (SekaiPop): rounded device body, a notch, and app-style keycap tiles.
    $window.Tag.CornerRadius=[System.Windows.CornerRadius]::new(40)
    if($window.Tag.Tag.Rim){$window.Tag.Tag.Rim.CornerRadius=[System.Windows.CornerRadius]::new(39)}
    $notch=[System.Windows.Controls.Border]::new();$notch.Width=96;$notch.Height=22;$notch.CornerRadius=[System.Windows.CornerRadius]::new(11);$notch.Background=New-BakaBrush '#05040A' 235;$notch.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center;$notch.Margin=[System.Windows.Thickness]::new(0,-4,0,10)
    $notchDot=[System.Windows.Shapes.Ellipse]::new();$notchDot.Width=7;$notchDot.Height=7;$notchDot.Fill=$script:accent2Brush;$notchDot.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Right;$notchDot.Margin=[System.Windows.Thickness]::new(0,0,14,0);$notch.Child=$notchDot
    $stack.Children.Add($notch)|Out-Null
    $stack.Children.Add((New-BakaHeading 'Quick Panel' 'Your BAKA phone  ·  Windows stays in charge of security and updates.'))|Out-Null
    $status=New-BakaText 'DESKTOP  ·  BALANCED' 11 'Bold' $script:accentBrush;$status.Name='QuickStatus';$script:windows.QuickStatus=$status;$stack.Children.Add($status)|Out-Null
    $network=New-BakaText 'Network status is provided by Windows.' 10 'Normal' $script:mutedBrush;$network.Name='QuickNetwork';$script:windows.QuickNetwork=$network;$network.Margin=[System.Windows.Thickness]::new(0,3,0,5);$stack.Children.Add($network)|Out-Null
    $profiles=[System.Windows.Controls.WrapPanel]::new();$profiles.Margin=[System.Windows.Thickness]::new(-3,8,0,8)
    foreach($profile in @([pscustomobject]@{Name='Desktop';Glyph=[string][char]0xE80F},[pscustomobject]@{Name='CompetitiveGaming';Glyph=[string][char]0xE7FC},[pscustomobject]@{Name='Benchmark';Glyph=[string][char]0xE9D2})){
        $label=if($profile.Name -eq 'CompetitiveGaming'){'Gaming'}else{$profile.Name}
        $profileName=[string]$profile.Name
        $button=New-BakaActionButton $label {param($sender,$eventArgs)try{[void](Set-BakaUiProfile ([string]$sender.Tag) 'Manual')}catch{[System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Profile change failed',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)|Out-Null}} $profile.Glyph
        $button.Tag=$profileName;$profiles.Children.Add($button)|Out-Null
    }
    $stack.Children.Add($profiles)|Out-Null
    $autoDetect=New-BakaActionButton 'Resume automatic game detection' {
        $script:manualOverride=$null
        $game=Get-BakaDetectedGame
        if($game){$script:autoGame=$true;$script:detectedGame=$game.DisplayName;[void](Set-BakaUiProfile 'CompetitiveGaming' 'Auto')}
        else{$script:autoGame=$false;$script:detectedGame=$null;[void](Set-BakaUiProfile 'Desktop' 'Auto')}
    } ([string][char]0xE768)
    $stack.Children.Add($autoDetect)|Out-Null
    $themeCombo=[System.Windows.Controls.ComboBox]::new();$themeCombo.MinWidth=160;$themeCombo.Margin=[System.Windows.Thickness]::new(0,5,0,5)
    foreach($theme in @($script:themeManifest)){$themeCombo.Items.Add([string]$theme.name)|Out-Null};$themeCombo.SelectedItem=[string]$script:config.appearance.theme
    $themeCombo.Add_SelectionChanged({param($sender,$eventArgs)if($sender.SelectedItem){$script:config.appearance.theme=[string]$sender.SelectedItem;Set-BakaTheme $script:config.appearance.theme;Save-BakaDesktopConfiguration -Path $script:settingsPath -Configuration $script:config|Out-Null;Write-BakaUiLog ('theme-selected name="{0}"' -f $script:config.appearance.theme)}})
    $stack.Children.Add((New-BakaRow 'Theme' 'Apply a BAKA appearance preset.' $themeCombo))|Out-Null
    $widgetsToggle=[System.Windows.Controls.CheckBox]::new();$widgetsToggle.Content='Show desktop widgets';$widgetsToggle.IsChecked=[bool]$script:config.widgets.enabled;$widgetsToggle.Foreground=$script:textBrush;$widgetsToggle.Margin=[System.Windows.Thickness]::new(0,10,0,10)
    $widgetsToggle.Add_Click({param($sender,$eventArgs)$script:config.widgets.enabled=[bool]$sender.IsChecked;Save-BakaDesktopConfiguration -Path $script:settingsPath -Configuration $script:config|Out-Null;if($script:config.widgets.enabled){Show-BakaWidgets}else{Hide-BakaWidgets};Write-BakaUiLog ('widgets-enabled={0}' -f $script:config.widgets.enabled)})
    $stack.Children.Add($widgetsToggle)|Out-Null
    $stack.Children.Add((New-BakaText 'Windows quick actions' 12 'Bold'))|Out-Null
    $links=[System.Windows.Controls.WrapPanel]::new();$links.Margin=[System.Windows.Thickness]::new(-3,3,0,3)
    foreach($entry in @(
        [pscustomobject]@{Name='Network';Uri='ms-settings:network-status';Glyph=[string][char]0xE774},
        [pscustomobject]@{Name='Bluetooth';Uri='ms-settings:bluetooth';Glyph=[string][char]0xE702},
        [pscustomobject]@{Name='Sound';Uri='ms-settings:sound';Glyph=[string][char]0xE767},
        [pscustomobject]@{Name='Display';Uri='ms-settings:display';Glyph=[string][char]0xE7F4},
        [pscustomobject]@{Name='Microphone';Uri='ms-settings:privacy-microphone';Glyph=[string][char]0xE720},
        [pscustomobject]@{Name='Notifications';Uri='ms-settings:notifications';Glyph=[string][char]0xE7F4},
        [pscustomobject]@{Name='Power';Uri='ms-settings:powersleep';Glyph=[string][char]0xE7E8}
    )){
        $uri=[string]$entry.Uri
        $link=New-BakaQuickTile ([string]$entry.Name) ([string]$entry.Glyph) {param($sender,$eventArgs)Open-BakaSystemSettings ([string]$sender.Tag)}
        $link.Tag=$uri
        $links.Children.Add($link)|Out-Null
    }
    $stack.Children.Add($links)|Out-Null
    $note=New-BakaText 'Hardware controls open the matching Windows Settings page. BAKA does not simulate or force unsupported Wi-Fi, Bluetooth, audio, microphone, or brightness toggles.' 9 'Normal' $script:mutedBrush;$note.Margin=[System.Windows.Thickness]::new(0,0,0,5);$stack.Children.Add($note)|Out-Null
    $buttons=[System.Windows.Controls.WrapPanel]::new()
    $buttons.Children.Add((New-BakaActionButton 'Settings' {Show-BakaSettings} ([string][char]0xE713)))|Out-Null
    $buttons.Children.Add((New-BakaActionButton 'Widget editor' {Show-BakaSettings 'Widgets'} ([string][char]0xE80F)))|Out-Null
    $buttons.Children.Add((New-BakaActionButton 'Open Windows Settings' {Start-Process 'ms-settings:'|Out-Null} ([string][char]0xE713)))|Out-Null
    $stack.Children.Add($buttons)|Out-Null
    $footer=New-BakaText 'Balanced power  ·  Native Windows scheduling  ·  Security protections unchanged' 10 'Normal' $script:mutedBrush;$footer.Margin=[System.Windows.Thickness]::new(0,12,0,0);$stack.Children.Add($footer)|Out-Null
    $quickScroll=[System.Windows.Controls.ScrollViewer]::new();$quickScroll.VerticalScrollBarVisibility=[System.Windows.Controls.ScrollBarVisibility]::Auto;$quickScroll.Background=[System.Windows.Media.Brushes]::Transparent;$quickScroll.Content=$stack
    Set-BakaWindowContent $window $quickScroll;$script:windows.Quick=$window
    $window.add_Closing({param($sender,$eventArgs) if(-not $script:allowShutdown){$eventArgs.Cancel=$true;$sender.Hide()}})
    return $window
}

function New-BakaTopBar {
    $window=New-BakaWindow 980 52 'BAKA Liquid System Bar' $false
    $grid=[System.Windows.Controls.Grid]::new();$grid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
    $center=[System.Windows.Controls.ColumnDefinition]::new();$center.Width=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star);$grid.ColumnDefinitions.Add($center)
    $right=[System.Windows.Controls.ColumnDefinition]::new();$right.Width=[System.Windows.GridLength]::new(380);$grid.ColumnDefinitions.Add($right)
    $brand=New-BakaText 'BAKA  /  LIQUID' 13 'Bold';$brand.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$grid.Children.Add($brand)|Out-Null
    $status=New-BakaText 'DESKTOP  ·  BALANCED' 10 'Normal' $script:accentBrush;$status.Name='BarStatus';$script:windows.BarStatus=$status;$status.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center;$status.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;[System.Windows.Controls.Grid]::SetColumn($status,1);$grid.Children.Add($status)|Out-Null
    $rightStack=[System.Windows.Controls.StackPanel]::new();$rightStack.Orientation=[System.Windows.Controls.Orientation]::Horizontal;$rightStack.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Right
    $network=New-BakaText 'OFFLINE' 10 'Normal' $script:mutedBrush;$network.Name='BarNetwork';$script:windows.BarNetwork=$network;$network.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$network.Margin=[System.Windows.Thickness]::new(6,0,8,0);$network.ToolTip='Windows network availability';$rightStack.Children.Add($network)|Out-Null
    $battery=New-BakaText '' 10 'Normal' $script:mutedBrush;$battery.Name='BarBattery';$script:windows.BarBattery=$battery;$battery.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$battery.Margin=[System.Windows.Thickness]::new(6,0,8,0);$rightStack.Children.Add($battery)|Out-Null
    $clock=New-BakaText (Get-Date -Format 'ddd, d MMM  ·  HH:mm') 11 'Normal' $script:textBrush;$clock.Name='BarClock';$script:windows.BarClock=$clock;$clock.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$rightStack.Children.Add($clock)|Out-Null
    $quick=New-BakaActionButton 'Panel' {Show-BakaQuickPanel} ([string][char]0xE713);$rightStack.Children.Add($quick)|Out-Null
    [System.Windows.Controls.Grid]::SetColumn($rightStack,2);$grid.Children.Add($rightStack)|Out-Null
    Set-BakaWindowContent $window $grid;$script:windows.TopBar=$window
    $window.add_SourceInitialized({param($sender,$eventArgs) Set-BakaTopBarPosition})
    $window.add_Closing({param($sender,$eventArgs) if(-not $script:allowShutdown){$eventArgs.Cancel=$true;$sender.Hide()}})
    return $window
}

function Save-BakaWidgetPosition([string]$WidgetId){
    if(-not $script:widgetWindows.ContainsKey($WidgetId)){return}
    $window=$script:widgetWindows[$WidgetId]
    $item=@($script:config.widgets.items|Where-Object {$_.id -eq $WidgetId}|Select-Object -First 1)
    if(-not $item){return}
    $area=(Get-BakaActiveScreen).WorkingArea
    $item[0].left=[math]::Max(0,[int]($window.Left-$area.Left));$item[0].top=[math]::Max(0,[int]($window.Top-$area.Top))
    $item[0].width=[math]::Max(180,[math]::Min(720,[int]$window.Width));$item[0].height=[math]::Max(100,[math]::Min(720,[int]$window.Height))
    try {Save-BakaDesktopConfiguration -Path $script:settingsPath -Configuration $script:config|Out-Null;Write-BakaUiLog ('widget-layout-saved id={0}' -f $WidgetId)}catch{Write-BakaUiLog ('widget-layout-save-failed id={0} error="{1}"' -f $WidgetId,$_.Exception.Message)}
}
function Get-BakaWidgetTitle([string]$WidgetId){switch($WidgetId){'clock'{'Clock'}'calendar'{'Calendar'}'system'{'System monitor'}'notes'{'Notes'}default{'Widget'}}}
function New-BakaWidgetWindow($Item){
    $widgetId=[string]$Item.id;$title=Get-BakaWidgetTitle $widgetId
    $window=New-BakaWindow ([double]$Item.width) ([double]$Item.height) ('BAKA '+$title) $false
    $window.ResizeMode=[System.Windows.ResizeMode]::CanResizeWithGrip;$window.MinWidth=180;$window.MinHeight=100;$window.MaxWidth=720;$window.MaxHeight=720
    $window.ShowActivated=$false;$window.Topmost=$false
    $area=(Get-BakaActiveScreen).WorkingArea;$window.Left=$area.Left+[double]$Item.left;$window.Top=$area.Top+[double]$Item.top
    $grid=[System.Windows.Controls.Grid]::new()
    $headerRow=[System.Windows.Controls.RowDefinition]::new();$headerRow.Height=[System.Windows.GridLength]::Auto;$grid.RowDefinitions.Add($headerRow)
    $bodyRow=[System.Windows.Controls.RowDefinition]::new();$bodyRow.Height=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star);$grid.RowDefinitions.Add($bodyRow)
    $header=[System.Windows.Controls.Border]::new();$header.Background=$script:surfaceAltBrush;$header.CornerRadius=[System.Windows.CornerRadius]::new(12);$header.Padding=[System.Windows.Thickness]::new(10,5,8,5);$header.Margin=[System.Windows.Thickness]::new(0,0,0,8);$header.Cursor=[System.Windows.Input.Cursors]::SizeAll
    $headerGrid=[System.Windows.Controls.Grid]::new();$headerGrid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new());$buttonColumn=[System.Windows.Controls.ColumnDefinition]::new();$buttonColumn.Width=[System.Windows.GridLength]::Auto;$headerGrid.ColumnDefinitions.Add($buttonColumn)
    $heading=New-BakaText $title 11 'Bold' $script:textBrush;$headerGrid.Children.Add($heading)|Out-Null
    $remove=New-BakaActionButton '×' {param($sender,$eventArgs)
        $id=[string]$sender.Tag
        $entry=@($script:config.widgets.items|Where-Object {$_.id -eq $id}|Select-Object -First 1)
        if($entry){$entry[0].enabled=$false;Save-BakaDesktopConfiguration -Path $script:settingsPath -Configuration $script:config|Out-Null}
        $script:widgetWindows[$id].Hide();Update-BakaWidgetPolling
    }
    $remove.Tag=$widgetId
    $remove.Padding=[System.Windows.Thickness]::new(5,2,5,2);$remove.Margin=[System.Windows.Thickness]::new(0);[System.Windows.Controls.Grid]::SetColumn($remove,1);$headerGrid.Children.Add($remove)|Out-Null
    $header.Child=$headerGrid
    $header.Tag=$widgetId
    $header.Add_MouseLeftButtonDown({param($sender,$eventArgs) if($eventArgs.ButtonState -eq [System.Windows.Input.MouseButtonState]::Pressed){$id=[string]$sender.Tag;$script:widgetWindows[$id].DragMove();Save-BakaWidgetPosition $id}})
    $grid.Children.Add($header)|Out-Null
    $body=[System.Windows.Controls.StackPanel]::new();$body.Margin=[System.Windows.Thickness]::new(5,0,5,4);[System.Windows.Controls.Grid]::SetRow($body,1);$grid.Children.Add($body)|Out-Null
    switch($widgetId){
        'clock' {
            $time=New-BakaText (Get-Date -Format 'HH:mm') 38 'Bold' $script:textBrush;$time.Name='ClockTime';$time.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Left
            $date=New-BakaText (Get-Date -Format 'dddd, d MMMM yyyy') 12 'Normal' $script:mutedBrush;$date.Name='ClockDate'
            $body.Children.Add($time)|Out-Null;$body.Children.Add($date)|Out-Null
            $script:widgetWindows['clockTime']=$time;$script:widgetWindows['clockDate']=$date
        }
        'calendar' {
            $calendar=[System.Windows.Controls.Calendar]::new();$calendar.DisplayDate=Get-Date;$calendar.IsTodayHighlighted=$true
            $calendar.Background=[System.Windows.Media.Brushes]::Transparent;$calendar.Foreground=$script:textBrush;$calendar.BorderBrush=$script:borderBrush;$body.Children.Add($calendar)|Out-Null
        }
        'system' {
            $hint=New-BakaText 'Windows performance data · updates while visible' 9 'Normal' $script:mutedBrush;$body.Children.Add($hint)|Out-Null
            $text=New-BakaText 'Reading system counters…' 11 'Normal' $script:textBrush;$text.Name='SystemReadout';$text.Margin=[System.Windows.Thickness]::new(0,8,0,0);$body.Children.Add($text)|Out-Null
            $script:systemWidgetText=$text
        }
        'notes' {
            $notesPath=Join-Path $script:settingsDirectory 'notes.txt';$notes=''
            if(Test-Path -LiteralPath $notesPath){$notes=Get-Content -LiteralPath $notesPath -Raw -ErrorAction SilentlyContinue}
            $box=[System.Windows.Controls.TextBox]::new();$box.Text=$notes;$box.AcceptsReturn=$true;$box.TextWrapping=[System.Windows.TextWrapping]::Wrap;$box.VerticalScrollBarVisibility=[System.Windows.Controls.ScrollBarVisibility]::Auto;$box.Background=$script:surfaceAltBrush;$box.Foreground=$script:textBrush;$box.BorderBrush=$script:borderBrush;$box.FontFamily=[System.Windows.Media.FontFamily]::new('Segoe UI Variable');$box.FontSize=12
            $body.Children.Add($box)|Out-Null
            $save=New-BakaActionButton 'Save notes locally' {param($sender,$eventArgs)$state=$sender.Tag;[IO.File]::WriteAllText($state.Path,$state.Box.Text,[System.Text.UTF8Encoding]::new($true));Write-BakaUiLog 'notes-saved-locally'}
            $save.Tag=[pscustomobject]@{Path=$notesPath;Box=$box};$body.Children.Add($save)|Out-Null
        }
    }
    Set-BakaWindowContent $window $grid
    $window.Name='BakaWidget_'+$widgetId
    $window.add_SizeChanged({param($sender,$eventArgs)try{$script:pendingWidgetSaveId=([string]$sender.Name -replace '^BakaWidget_','');$script:widgetSaveTimer.Stop();$script:widgetSaveTimer.Start()}catch{Write-BakaUiLog ('widget-sizechanged-failed id={0} error="{1}" stack="{2}"' -f $sender.Name,$_.Exception.ToString(),$_.ScriptStackTrace)}})
    $script:widgetWindows[$widgetId]=$window
    return $window
}
function Show-BakaWidgets {
    if(-not $script:config.widgets.enabled -or $script:activeProfile -ne 'Desktop'){return}
    $enabled=@($script:config.widgets.items|Where-Object {$_.enabled}|ForEach-Object {[string]$_.id})
    foreach($pair in @($script:widgetWindows.GetEnumerator())){if($pair.Value -is [System.Windows.Window] -and $pair.Key -notin $enabled){$pair.Value.Hide()}}
    foreach($item in @($script:config.widgets.items|Where-Object {$_.enabled})){
        $id=[string]$item.id
        if(-not $script:widgetWindows.ContainsKey($id)){[void](New-BakaWidgetWindow $item)}
        $window=$script:widgetWindows[$id];if(-not $window.IsVisible){Show-BakaWindow $window}
    }
    $script:widgetUserVisible=$true;Update-BakaWidgetPolling
}
function Hide-BakaWidgets {
    foreach($pair in @($script:widgetWindows.GetEnumerator())){if($pair.Value -is [System.Windows.Window]){$pair.Value.Hide()}}
    Update-BakaWidgetPolling
}
function Update-BakaWidgetPolling {
    $systemVisible=$script:activeProfile -eq 'Desktop' -and (($script:widgetWindows.ContainsKey('system') -and $script:widgetWindows['system'].IsVisible) -or ($script:windows.Dashboard -and $script:windows.Dashboard.IsVisible))
    if($script:systemMetricsTimer){
        $interval=[TimeSpan]::FromSeconds([int]$script:config.widgets.refreshSeconds)
        if($script:systemMetricsTimer.Interval -ne $interval){$script:systemMetricsTimer.Stop();$script:systemMetricsTimer.Interval=$interval}
        if($systemVisible){if(-not $script:systemMetricsTimer.IsEnabled){$script:systemMetricsTimer.Start()}}else{$script:systemMetricsTimer.Stop()}
    }
}
function Format-BakaMetrics($Metrics){
    $cpu=if($null -ne $Metrics.CpuPercent){('{0}% CPU' -f $Metrics.CpuPercent)}else{'CPU unavailable'}
    $memory=if($null -ne $Metrics.MemoryUsedMiB){('{0:N0} / {1:N0} MiB memory' -f $Metrics.MemoryUsedMiB,$Metrics.MemoryTotalMiB)}else{'Memory unavailable'}
    $gpu=if($null -ne $Metrics.GpuEnginePeakPercent){('{0}% peak GPU engine' -f $Metrics.GpuEnginePeakPercent)}else{'GPU engine telemetry unavailable'}
    $temperature=if($null -ne $Metrics.GpuTemperatureC){('{0:N0}°C GPU temperature' -f $Metrics.GpuTemperatureC)}else{'GPU temperature unavailable'}
    $disk=if($null -ne $Metrics.DiskFreeGiB){('{0:N1} / {1:N1} GiB free on system drive' -f $Metrics.DiskFreeGiB,$Metrics.DiskTotalGiB)}else{'Disk data unavailable'}
    $network=if($null -ne $Metrics.NetworkReceiveKiBs){('{0:N1} KiB/s down  ·  {1:N1} KiB/s up' -f $Metrics.NetworkReceiveKiBs,$Metrics.NetworkSendKiBs)}else{'Network throughput unavailable'}
    @($cpu,$memory,$gpu,$temperature,$disk,$network) -join "`n"
}
function Start-BakaMetricRead {
    if($script:metricsPowerShell){
        if(-not $script:metricsAsyncResult.IsCompleted){return}
        try{
            $result=@($script:metricsPowerShell.EndInvoke($script:metricsAsyncResult))|Select-Object -First 1
            $streamErrors=@($script:metricsPowerShell.Streams.Error)
            if($streamErrors.Count){throw (($streamErrors|ForEach-Object {$_.ToString()}) -join '; ')}
            if($result){
                $script:systemMetricsLast=$result;$script:systemMetricsError='';Update-BakaDashboardMetrics $result
                if($script:systemWidgetText -and $script:widgetWindows.ContainsKey('system') -and $script:widgetWindows['system'].IsVisible){$script:systemWidgetText.Text=Format-BakaMetrics $result}
                Write-BakaUiLog ('metrics-query-complete cpu={0} gpuEnginePeak={1} memoryMiB={2} diskFreeGiB={3}' -f $result.CpuPercent,$result.GpuEnginePeakPercent,$result.MemoryUsedMiB,$result.DiskFreeGiB)
            }else{Write-BakaUiLog 'metrics-query-empty-result'}
        }catch{$script:systemMetricsError=$_.Exception.ToString();Write-BakaUiLog ('metrics-read-failed error="{0}"' -f $script:systemMetricsError)}
        finally{
            try{$script:metricsPowerShell.Dispose()}catch{}
            try{$script:metricsRunspace.Close();$script:metricsRunspace.Dispose()}catch{}
            $script:metricsPowerShell=$null;$script:metricsRunspace=$null;$script:metricsAsyncResult=$null
        }
    }
    if($script:metricsPowerShell){return}
    try{
        $initialState=[System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $initialState.ExecutionPolicy=[Microsoft.PowerShell.ExecutionPolicy]::Bypass
        $runspace=[System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($initialState)
        $runspace.Open()
        $worker=[System.Management.Automation.PowerShell]::Create();$worker.Runspace=$runspace
        [void]$worker.AddCommand('Import-Module').AddParameter('Name',$script:monitoringModulePath).AddParameter('Force')
        [void]$worker.AddStatement()
        [void]$worker.AddCommand('Get-BakaSystemMetrics')
        $script:metricsRunspace=$runspace;$script:metricsPowerShell=$worker;$script:metricsAsyncResult=$worker.BeginInvoke()
        Write-BakaUiLog 'metrics-query-started'
    }catch{
        Write-BakaUiLog ('metrics-worker-start-failed error="{0}"' -f $_.Exception.ToString())
        if($worker){try{$worker.Dispose()}catch{}}
        if($runspace){try{$runspace.Close();$runspace.Dispose()}catch{}}
        $script:metricsPowerShell=$null;$script:metricsRunspace=$null;$script:metricsAsyncResult=$null
    }
}
function Stop-BakaMetricWorker {
    $worker=$script:metricsPowerShell;$async=$script:metricsAsyncResult;$runspace=$script:metricsRunspace
    if(-not $worker){return}
    try {
        if($async -and -not $async.IsCompleted){try{$worker.Stop()}catch{}}
        if($async -and -not $async.IsCompleted){try{[void]$async.AsyncWaitHandle.WaitOne(5000)}catch{}}
        if($async -and $async.IsCompleted){try{[void]$worker.EndInvoke($async)}catch{}}
        elseif($async){Write-BakaUiLog 'metrics-worker-stop-timeout; leaving worker resources for process teardown';return}
    } finally {
        if(-not $async -or $async.IsCompleted){
            try{$worker.Dispose()}catch{}
            if($runspace){try{$runspace.Close();$runspace.Dispose()}catch{}}
            $script:metricsPowerShell=$null;$script:metricsRunspace=$null;$script:metricsAsyncResult=$null
        }
    }
}

function Get-BakaWidgetItem([string]$WidgetId){@($script:config.widgets.items|Where-Object {$_.id -eq $WidgetId}|Select-Object -First 1)}

function Copy-BakaSettings($Configuration){$Configuration|ConvertTo-Json -Depth 12|ConvertFrom-Json}
function Update-BakaSettingsControls {
    if(-not $script:settingsControls){return}
    $wasLoading=$script:settingsLoading;$script:settingsLoading=$true
    try{
        $controls=$script:settingsControls
        if($controls.Theme){$controls.Theme.SelectedItem=[string]$script:config.appearance.theme}
        if($controls.Accent){$controls.Accent.Text=[string]$script:config.appearance.accentColor}
        if($controls.Glass){$controls.Glass.Value=[double]$script:config.appearance.glassIntensity}
        if($controls.Motion){$controls.Motion.SelectedItem=[string]$script:config.appearance.animationIntensity}
        if($controls.ReducedMotion){$controls.ReducedMotion.IsChecked=[bool]$script:config.appearance.reducedMotion}
        if($controls.DockSize){$controls.DockSize.Value=[double]$script:config.dock.iconSize}
        if($controls.DockSpacing){$controls.DockSpacing.Value=[double]$script:config.dock.spacing}
        if($controls.DockAlignment){$controls.DockAlignment.SelectedItem=[string]$script:config.dock.alignment}
        if($controls.DockMonitor){$controls.DockMonitor.SelectedItem=[string]$script:config.dock.monitor}
        if($controls.DockAutoHide){$controls.DockAutoHide.IsChecked=[bool]$script:config.dock.autoHide}
        if($controls.DockMagnify){$controls.DockMagnify.IsChecked=[bool]$script:config.dock.magnification}
        if($controls.PinnedApps){$controls.PinnedApps.ItemsSource=@($script:config.pinnedApps)}
        if($controls.WallpaperMode){$controls.WallpaperMode.SelectedItem=[string]$script:config.wallpaper.mode}
        if($controls.WallpaperPath){$controls.WallpaperPath.Text=[string]$script:config.wallpaper.path}
        if($controls.WallpaperFit){$controls.WallpaperFit.SelectedItem=[string]$script:config.wallpaper.fit}
        if($controls.WallpaperColor){$controls.WallpaperColor.Text=[string]$script:config.wallpaper.color}
        if($controls.WallpaperMuted){$controls.WallpaperMuted.IsChecked=[bool]$script:config.wallpaper.muted}
        if($controls.WallpaperPause){$controls.WallpaperPause.IsChecked=[bool]$script:config.wallpaper.pauseInGames}
        if($controls.TaskbarHide){$controls.TaskbarHide.IsChecked=[bool]$script:config.taskbar.autoHideWindowsTaskbar}
        if($controls.TaskbarRunning){$controls.TaskbarRunning.IsChecked=[bool]$script:config.taskbar.showRunningApps}
        if($controls.TaskbarStart){$controls.TaskbarStart.IsChecked=[bool]$script:config.taskbar.showStartButton}
        if($controls.BarEnabled){$controls.BarEnabled.IsChecked=[bool]$script:config.topBar.enabled}
        if($controls.BarProfile){$controls.BarProfile.IsChecked=[bool]$script:config.topBar.showProfile}
        if($controls.BarDate){$controls.BarDate.IsChecked=[bool]$script:config.topBar.showDate}
        if($controls.BarMonitor){$controls.BarMonitor.SelectedItem=[string]$script:config.topBar.monitor}
        if($controls.WidgetsEnabled){$controls.WidgetsEnabled.IsChecked=[bool]$script:config.widgets.enabled}
        foreach($id in $controls.WidgetChecks.Keys){$item=Get-BakaWidgetItem $id;if($item){$controls.WidgetChecks[$id].IsChecked=[bool]$item[0].enabled}}
        if($controls.WidgetRefresh){$controls.WidgetRefresh.Value=[double]$script:config.widgets.refreshSeconds}
    }finally{$script:settingsLoading=$wasLoading}
}
function Invoke-BakaSettingsRefresh {
    Set-BakaTheme $script:config.appearance.theme
    if($script:windows.Dock){Set-BakaDockAppearance}
    if($script:windows.TopBar){Set-BakaTopBarPosition;if($script:config.topBar.enabled -and $script:activeProfile -eq 'Desktop' -and -not $script:autoGame){if(-not $script:windows.TopBar.IsVisible){Show-BakaWindow $script:windows.TopBar}}else{$script:windows.TopBar.Hide()}}
    if($script:config.widgets.enabled -and $script:widgetUserVisible -and $script:activeProfile -eq 'Desktop'){Show-BakaWidgets}else{Hide-BakaWidgets}
    Update-BakaSettingsControls
}
function Save-BakaSettingsDraft {
    Save-BakaDesktopConfiguration -Path $script:settingsPath -Configuration $script:config|Out-Null
    $script:settingsOriginal=Copy-BakaSettings $script:config;$script:settingsDirty=$false
    Invoke-BakaSettingsRefresh;Set-BakaDockAppearance
    Invoke-BakaTaskbarMode
    if($script:wallpaperDirty){Invoke-BakaWallpaper -Force}
    Write-BakaUiLog 'desktop-settings-saved'
}
function Close-BakaSettings {
    if($script:settingsDirty){
        $choice=[System.Windows.Forms.MessageBox]::Show('Save the current BAKA desktop changes before closing?','Unsaved BAKA settings',[System.Windows.Forms.MessageBoxButtons]::YesNoCancel,[System.Windows.Forms.MessageBoxIcon]::Question)
        if($choice -eq [System.Windows.Forms.DialogResult]::Cancel){return}
        if($choice -eq [System.Windows.Forms.DialogResult]::Yes){try{Save-BakaSettingsDraft}catch{[System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Settings not saved',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)|Out-Null;return}}
        else{$script:config=Copy-BakaSettings $script:settingsOriginal;$script:settingsDirty=$false;$script:wallpaperDirty=$false;$script:widgetUserVisible=[bool]$script:config.widgets.enabled;Invoke-BakaSettingsRefresh;Update-BakaSettingsControls;Write-BakaUiLog 'desktop-settings-draft-discarded'}
    }
    if($script:windows.Settings){Hide-BakaWindow $script:windows.Settings}
}
function Set-BakaDockAppearance {
    if(-not $script:windows.Dock){return}
    $script:windows.Dock.Height=[double]$script:config.dock.iconSize+$(if($script:activeProfile -eq 'Desktop'){54}else{42})
    $script:windows.Dock.Tag.Background=$script:glassBrush;$script:windows.Dock.Tag.BorderBrush=$script:rimBrush
    foreach($button in @($script:windows.DockUtilityButtons)){$button.Height=[double]$script:config.dock.iconSize+8}
    if($script:windows.DockAppPanel){
        $script:windows.DockAppPanel.Children.Clear()
        $script:dockButtons.Clear()
        foreach($app in @($script:config.pinnedApps)){
            $button=New-BakaButton ([string]$app.name) ({param($sender,$eventArgs)Start-BakaPinnedApp $sender.Tag}) ([string]$app.glyph) ("Launch or focus {0}" -f $app.name) -ShowIndicator -IconSource (Get-BakaAppIconSource $app)
            $button.Tag=$app
            $button.Width=[double]$script:config.dock.iconSize+15;$button.Height=[double]$script:config.dock.iconSize+8;$button.Margin=[System.Windows.Thickness]::new([double]$script:config.dock.spacing/2,0,[double]$script:config.dock.spacing/2,0)
            if(Get-BakaProcessForApp $app){$button.BorderBrush=$script:accentBrush;$button.BorderThickness=[System.Windows.Thickness]::new(0,0,0,2)}
            $script:dockButtons[[string]$app.id]=$button;$script:windows.DockAppPanel.Children.Add($button)|Out-Null
        }
    }
    if($script:windows.DockStartButton){$script:windows.DockStartButton.Visibility=if([bool]$script:config.taskbar.showStartButton){[System.Windows.Visibility]::Visible}else{[System.Windows.Visibility]::Collapsed}}
    $script:runningAppSignature='';Update-BakaDockRunningApps
    Set-BakaDockPosition
}

function New-BakaSettings {
    $window=New-BakaWindow 900 620 'BAKA Liquid Settings' $true
    $layout=[System.Windows.Controls.Grid]::new();$layout.Background=[System.Windows.Media.Brushes]::Transparent
    $headerRow=[System.Windows.Controls.RowDefinition]::new();$headerRow.Height=[System.Windows.GridLength]::Auto;$layout.RowDefinitions.Add($headerRow)
    $bodyRow=[System.Windows.Controls.RowDefinition]::new();$bodyRow.Height=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star);$layout.RowDefinitions.Add($bodyRow)
    $footerRow=[System.Windows.Controls.RowDefinition]::new();$footerRow.Height=[System.Windows.GridLength]::Auto;$layout.RowDefinitions.Add($footerRow)
    $header=[System.Windows.Controls.DockPanel]::new();$header.LastChildFill=$true;$header.Height=56
    $close=New-BakaActionButton 'Close' {Close-BakaSettings} ([string][char]0xE711);$close.Width=76;$close.Height=42;$close.VerticalAlignment=[System.Windows.VerticalAlignment]::Top;[System.Windows.Controls.DockPanel]::SetDock($close,[System.Windows.Controls.Dock]::Right);$header.Children.Add($close)|Out-Null
    $header.Children.Add((New-BakaHeading 'BAKA Liquid' 'One design system for the dock, Quick Panel, optional bar, and desktop widgets.'))|Out-Null
    $layout.Children.Add($header)|Out-Null
    $tabs=[System.Windows.Controls.TabControl]::new();$tabs.Margin=[System.Windows.Thickness]::new(0,4,0,8);[System.Windows.Controls.Grid]::SetRow($tabs,1);$layout.Children.Add($tabs)|Out-Null

    $appearanceTab=[System.Windows.Controls.TabItem]::new();$appearanceTab.Header='Appearance';$appearanceScroll=[System.Windows.Controls.ScrollViewer]::new();$appearanceScroll.VerticalScrollBarVisibility=[System.Windows.Controls.ScrollBarVisibility]::Auto
    $appearance=[System.Windows.Controls.StackPanel]::new();$appearance.Margin=[System.Windows.Thickness]::new(14)
    $appearance.Children.Add((New-BakaHeading 'Theme and surface' 'Preset colors are shared by every BAKA surface; high contrast and remote sessions use opaque fallbacks.'))|Out-Null
    $themeCombo=[System.Windows.Controls.ComboBox]::new();$themeCombo.MinWidth=190;$themeCombo.Margin=[System.Windows.Thickness]::new(0,4,0,8)
    foreach($theme in @($script:themeManifest)){$themeCombo.Items.Add([string]$theme.name)|Out-Null};$themeCombo.SelectedItem=[string]$script:config.appearance.theme
    $themeCombo.Add_SelectionChanged({param($sender,$eventArgs)if($sender.SelectedItem -and -not $script:settingsLoading){$script:config.appearance.theme=[string]$sender.SelectedItem;Set-BakaTheme $script:config.appearance.theme;$script:settingsDirty=$true}})
    $appearance.Children.Add((New-BakaRow 'Preset' 'Obsidian, Liquid, Minimal, Gaming, and optional Violet.' $themeCombo))|Out-Null
    $accentRow=[System.Windows.Controls.StackPanel]::new();$accentRow.Orientation=[System.Windows.Controls.Orientation]::Horizontal
    $accentInput=[System.Windows.Controls.TextBox]::new();$accentInput.Text=[string]$script:config.appearance.accentColor;$accentInput.Width=140;$accentInput.Margin=[System.Windows.Thickness]::new(0,4,8,4);$accentInput.VerticalContentAlignment=[System.Windows.VerticalAlignment]::Center
    $accentApply=New-BakaActionButton 'Preview accent' {param($sender,$eventArgs)$inputBox=$sender.Tag;if(Test-BakaHexColor $inputBox.Text){$script:config.appearance.accentColor=$inputBox.Text.ToUpperInvariant();Set-BakaTheme $script:config.appearance.theme;$script:settingsDirty=$true}else{[System.Windows.Forms.MessageBox]::Show('Enter a color in #RRGGBB format.','Accent color',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)|Out-Null}}
    $accentApply.Tag=$accentInput
    $accentRow.Children.Add($accentInput)|Out-Null;$accentRow.Children.Add($accentApply)|Out-Null
    $appearance.Children.Add((New-BakaRow 'Accent color' 'Use a readable monochrome or restrained purple accent.' $accentRow))|Out-Null
    $glass=[System.Windows.Controls.Slider]::new();$glass.Minimum=0;$glass.Maximum=45;$glass.TickFrequency=5;$glass.IsSnapToTickEnabled=$true;$glass.Value=[double]$script:config.appearance.glassIntensity
    $glass.Add_ValueChanged({param($sender,$eventArgs)if(-not $script:settingsLoading){$script:config.appearance.glassIntensity=[int]$sender.Value;Set-BakaTheme $script:config.appearance.theme;$script:settingsDirty=$true}})
    $appearance.Children.Add((New-BakaRow 'Glass intensity' 'Reduced automatically for gaming, high contrast, and remote sessions.' $glass))|Out-Null
    $motion=[System.Windows.Controls.ComboBox]::new();foreach($value in @('Off','Subtle','Full')){$motion.Items.Add($value)|Out-Null};$motion.SelectedItem=[string]$script:config.appearance.animationIntensity
    $motion.Add_SelectionChanged({param($sender,$eventArgs)if($sender.SelectedItem -and -not $script:settingsLoading){$script:config.appearance.animationIntensity=[string]$sender.SelectedItem;$script:settingsDirty=$true;Invoke-BakaSettingsRefresh}})
    $appearance.Children.Add((New-BakaRow 'Motion' 'Full adds a spring reveal, moving silver light sweep, and dock wave. Gaming and Benchmark suppress motion automatically.' $motion))|Out-Null
    $reducedMotion=[System.Windows.Controls.CheckBox]::new();$reducedMotion.Content='Reduce motion';$reducedMotion.IsChecked=[bool]$script:config.appearance.reducedMotion;$reducedMotion.Foreground=$script:textBrush
    $reducedMotion.Add_Click({param($sender,$eventArgs)if(-not $script:settingsLoading){$script:config.appearance.reducedMotion=[bool]$sender.IsChecked;$script:settingsDirty=$true;Invoke-BakaSettingsRefresh}});$appearance.Children.Add($reducedMotion)|Out-Null
    $appearance.Children.Add((New-BakaText 'Windows glass effects apply only to BAKA-owned windows. Native application title bars remain under Windows and the application.' 10 'Normal' $script:mutedBrush))|Out-Null
    $appearanceScroll.Content=$appearance;$appearanceTab.Content=$appearanceScroll;$tabs.Items.Add($appearanceTab)|Out-Null

    $wallpaperTab=[System.Windows.Controls.TabItem]::new();$wallpaperTab.Header='Wallpaper';$wallpaperScroll=[System.Windows.Controls.ScrollViewer]::new();$wallpaperScroll.VerticalScrollBarVisibility=[System.Windows.Controls.ScrollBarVisibility]::Auto
    $wallpaperContent=[System.Windows.Controls.StackPanel]::new();$wallpaperContent.Margin=[System.Windows.Thickness]::new(14)
    $wallpaperContent.Children.Add((New-BakaHeading 'Your desktop, your media' 'Use any picture, a looping video, or a solid color. Videos play muted behind your desktop icons and pause during games.'))|Out-Null
    $wallpaperMode=[System.Windows.Controls.ComboBox]::new();foreach($value in @('Default','Image','Video','Color')){$wallpaperMode.Items.Add($value)|Out-Null};$wallpaperMode.SelectedItem=[string]$script:config.wallpaper.mode
    $wallpaperMode.Add_SelectionChanged({param($sender,$eventArgs)if($sender.SelectedItem -and -not $script:settingsLoading){$script:config.wallpaper.mode=[string]$sender.SelectedItem;$script:settingsDirty=$true;$script:wallpaperDirty=$true}})
    $wallpaperContent.Children.Add((New-BakaRow 'Background type' 'Default keeps whatever Windows Settings uses. Image, Video, and Color are managed by BAKA.' $wallpaperMode))|Out-Null
    $wallpaperPathRow=[System.Windows.Controls.StackPanel]::new();$wallpaperPathRow.Orientation=[System.Windows.Controls.Orientation]::Horizontal
    $wallpaperPath=[System.Windows.Controls.TextBox]::new();$wallpaperPath.Width=190;$wallpaperPath.Margin=[System.Windows.Thickness]::new(0,4,8,4);$wallpaperPath.Text=[string]$script:config.wallpaper.path;$wallpaperPath.IsReadOnly=$true
    $wallpaperBrowse=New-BakaActionButton 'Browse' {param($sender,$eventArgs)$dialog=[System.Windows.Forms.OpenFileDialog]::new();$dialog.Title='Choose a wallpaper image or video';$dialog.Filter='Images and videos|*.jpg;*.jpeg;*.jfif;*.png;*.bmp;*.gif;*.webp;*.mp4;*.m4v;*.mov;*.wmv;*.avi;*.mkv;*.webm|Images|*.jpg;*.jpeg;*.jfif;*.png;*.bmp;*.gif;*.webp|Videos|*.mp4;*.m4v;*.mov;*.wmv;*.avi;*.mkv;*.webm';if($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){$kind=Get-BakaWallpaperKind $dialog.FileName;if($kind -notin @('Image','Video')){[System.Windows.Forms.MessageBox]::Show('Choose a supported image or video file.','BAKA wallpaper',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)|Out-Null;return};$script:config.wallpaper.path=$dialog.FileName;$script:config.wallpaper.mode=$kind;$script:settingsDirty=$true;$script:wallpaperDirty=$true;Update-BakaSettingsControls}} ([string][char]0xE8E5)
    $wallpaperPathRow.Children.Add($wallpaperPath)|Out-Null;$wallpaperPathRow.Children.Add($wallpaperBrowse)|Out-Null
    $wallpaperContent.Children.Add((New-BakaRow 'Media file' 'Pictures: JPG, PNG, BMP, GIF, WebP. Videos: MP4, MOV, WMV, AVI, MKV, WebM (codec support comes from Windows).' $wallpaperPathRow))|Out-Null
    $wallpaperFit=[System.Windows.Controls.ComboBox]::new();foreach($value in @('Fill','Fit','Stretch','Center','Span')){$wallpaperFit.Items.Add($value)|Out-Null};$wallpaperFit.SelectedItem=[string]$script:config.wallpaper.fit
    $wallpaperFit.Add_SelectionChanged({param($sender,$eventArgs)if($sender.SelectedItem -and -not $script:settingsLoading){$script:config.wallpaper.fit=[string]$sender.SelectedItem;$script:settingsDirty=$true;$script:wallpaperDirty=$true}})
    $wallpaperContent.Children.Add((New-BakaRow 'Fit' 'How the picture or video fills the screen.' $wallpaperFit))|Out-Null
    $wallpaperColorRow=[System.Windows.Controls.StackPanel]::new();$wallpaperColorRow.Orientation=[System.Windows.Controls.Orientation]::Horizontal
    $wallpaperColor=[System.Windows.Controls.TextBox]::new();$wallpaperColor.Width=120;$wallpaperColor.Margin=[System.Windows.Thickness]::new(0,4,8,4);$wallpaperColor.Text=[string]$script:config.wallpaper.color
    $wallpaperColorApply=New-BakaActionButton 'Use color' {param($sender,$eventArgs)$inputBox=$sender.Tag;if(Test-BakaHexColor $inputBox.Text){$script:config.wallpaper.color=$inputBox.Text.ToUpperInvariant();$script:config.wallpaper.mode='Color';$script:settingsDirty=$true;$script:wallpaperDirty=$true;Update-BakaSettingsControls}else{[System.Windows.Forms.MessageBox]::Show('Enter a color in #RRGGBB format.','Wallpaper color',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)|Out-Null}} ([string][char]0xE790)
    $wallpaperColorApply.Tag=$wallpaperColor
    $wallpaperColorRow.Children.Add($wallpaperColor)|Out-Null;$wallpaperColorRow.Children.Add($wallpaperColorApply)|Out-Null
    $wallpaperContent.Children.Add((New-BakaRow 'Solid color' 'A flat #RRGGBB background with no image decoding cost.' $wallpaperColorRow))|Out-Null
    $wallpaperMuted=[System.Windows.Controls.CheckBox]::new();$wallpaperMuted.Content='Mute video wallpaper';$wallpaperMuted.IsChecked=[bool]$script:config.wallpaper.muted;$wallpaperMuted.Foreground=$script:textBrush
    $wallpaperMuted.Add_Click({param($sender,$eventArgs)if(-not $script:settingsLoading){$script:config.wallpaper.muted=[bool]$sender.IsChecked;$script:settingsDirty=$true;$script:wallpaperDirty=$true}});$wallpaperContent.Children.Add($wallpaperMuted)|Out-Null
    $wallpaperPause=[System.Windows.Controls.CheckBox]::new();$wallpaperPause.Content='Pause video during Gaming and Benchmark profiles';$wallpaperPause.IsChecked=[bool]$script:config.wallpaper.pauseInGames;$wallpaperPause.Foreground=$script:textBrush
    $wallpaperPause.Add_Click({param($sender,$eventArgs)if(-not $script:settingsLoading){$script:config.wallpaper.pauseInGames=[bool]$sender.IsChecked;$script:settingsDirty=$true}});$wallpaperContent.Children.Add($wallpaperPause)|Out-Null
    $wallpaperActions=[System.Windows.Controls.WrapPanel]::new();$wallpaperActions.Margin=[System.Windows.Thickness]::new(0,10,0,0)
    $wallpaperShipped=New-BakaActionButton 'Use BAKA wallpaper' {$shipped=Get-BakaShippedWallpaperPath;if($shipped){$script:config.wallpaper.path=$shipped;$script:config.wallpaper.mode='Image';$script:config.wallpaper.fit='Fill';$script:settingsDirty=$true;$script:wallpaperDirty=$true;Update-BakaSettingsControls}} ([string][char]0xE91B)
    $wallpaperApplyNow=New-BakaActionButton 'Apply now' {Invoke-BakaWallpaper -Force} ([string][char]0xE73E)
    $wallpaperActions.Children.Add($wallpaperShipped)|Out-Null;$wallpaperActions.Children.Add($wallpaperApplyNow)|Out-Null;$wallpaperContent.Children.Add($wallpaperActions)|Out-Null
    $wallpaperContent.Children.Add((New-BakaText 'Video wallpaper runs on the primary display. If Windows cannot host it behind the icons or the codec is missing, BAKA keeps a static background and records the reason in its log.' 10 'Normal' $script:mutedBrush))|Out-Null
    $wallpaperScroll.Content=$wallpaperContent;$wallpaperTab.Content=$wallpaperScroll;$tabs.Items.Add($wallpaperTab)|Out-Null

    $dockTab=[System.Windows.Controls.TabItem]::new();$dockTab.Header='Dock';$dockScroll=[System.Windows.Controls.ScrollViewer]::new();$dockScroll.VerticalScrollBarVisibility=[System.Windows.Controls.ScrollBarVisibility]::Auto
    $dockContent=[System.Windows.Controls.StackPanel]::new();$dockContent.Margin=[System.Windows.Thickness]::new(14);$dockContent.Children.Add((New-BakaHeading 'App dock' 'Pinned programs launch, focus, restore, or minimize when supported. A running app gets a subtle accent indicator.'))|Out-Null
    $size=[System.Windows.Controls.Slider]::new();$size.Minimum=40;$size.Maximum=72;$size.Value=[double]$script:config.dock.iconSize;$size.TickFrequency=4;$size.IsSnapToTickEnabled=$true
    $size.Add_ValueChanged({param($sender,$eventArgs)if(-not $script:settingsLoading){$script:config.dock.iconSize=[int]$sender.Value;$script:settingsDirty=$true}})
    $dockContent.Children.Add((New-BakaRow 'Icon size' 'Choose a comfortable dock scale.' $size))|Out-Null
    $spacing=[System.Windows.Controls.Slider]::new();$spacing.Minimum=4;$spacing.Maximum=18;$spacing.Value=[double]$script:config.dock.spacing;$spacing.TickFrequency=1;$spacing.IsSnapToTickEnabled=$true
    $spacing.Add_ValueChanged({param($sender,$eventArgs)if(-not $script:settingsLoading){$script:config.dock.spacing=[int]$sender.Value;$script:settingsDirty=$true}})
    $dockContent.Children.Add((New-BakaRow 'Icon spacing' 'Set the gap between app launchers.' $spacing))|Out-Null
    $align=[System.Windows.Controls.ComboBox]::new();foreach($v in @('Left','Center','Right')){$align.Items.Add($v)|Out-Null};$align.SelectedItem=[string]$script:config.dock.alignment
    $align.Add_SelectionChanged({param($sender,$eventArgs)if($sender.SelectedItem -and -not $script:settingsLoading){$script:config.dock.alignment=[string]$sender.SelectedItem;$script:settingsDirty=$true}})
    $dockContent.Children.Add((New-BakaRow 'Alignment' 'Place the dock along the bottom work area.' $align))|Out-Null
    $screens=[System.Windows.Forms.Screen]::AllScreens;$monitorCombo=[System.Windows.Controls.ComboBox]::new();[void]$monitorCombo.Items.Add('Primary');foreach($s in $screens){[void]$monitorCombo.Items.Add($s.DeviceName)};$monitorCombo.SelectedItem=[string]$script:config.dock.monitor
    $monitorCombo.Add_SelectionChanged({param($sender,$eventArgs)if($sender.SelectedItem -and -not $script:settingsLoading){$script:config.dock.monitor=[string]$sender.SelectedItem;$script:settingsDirty=$true}})
    $dockContent.Children.Add((New-BakaRow 'Display' 'Choose which monitor owns the dock and widgets.' $monitorCombo))|Out-Null
    $autoHide=[System.Windows.Controls.CheckBox]::new();$autoHide.Content='Hide after leaving the dock';$autoHide.IsChecked=[bool]$script:config.dock.autoHide;$autoHide.Foreground=$script:textBrush
    $autoHide.Add_Click({param($sender,$eventArgs)if(-not $script:settingsLoading){$script:config.dock.autoHide=[bool]$sender.IsChecked;$script:settingsDirty=$true}});$dockContent.Children.Add($autoHide)|Out-Null
    $magnify=[System.Windows.Controls.CheckBox]::new();$magnify.Content='Enable liquid dock wave magnification';$magnify.IsChecked=[bool]$script:config.dock.magnification;$magnify.Foreground=$script:textBrush
    $magnify.Add_Click({param($sender,$eventArgs)if(-not $script:settingsLoading){$script:config.dock.magnification=[bool]$sender.IsChecked;$script:settingsDirty=$true}});$dockContent.Children.Add($magnify)|Out-Null
    $dockContent.Children.Add((New-BakaText 'Taskbar replacement' 12 'Bold'))|Out-Null
    $taskbarHide=[System.Windows.Controls.CheckBox]::new();$taskbarHide.Content='Auto-hide the Windows taskbar while BAKA runs (restored when BAKA exits)';$taskbarHide.IsChecked=[bool]$script:config.taskbar.autoHideWindowsTaskbar;$taskbarHide.Foreground=$script:textBrush
    $taskbarHide.Add_Click({param($sender,$eventArgs)if(-not $script:settingsLoading){$script:config.taskbar.autoHideWindowsTaskbar=[bool]$sender.IsChecked;$script:settingsDirty=$true}});$dockContent.Children.Add($taskbarHide)|Out-Null
    $taskbarRunning=[System.Windows.Controls.CheckBox]::new();$taskbarRunning.Content='Show open windows in the dock';$taskbarRunning.IsChecked=[bool]$script:config.taskbar.showRunningApps;$taskbarRunning.Foreground=$script:textBrush
    $taskbarRunning.Add_Click({param($sender,$eventArgs)if(-not $script:settingsLoading){$script:config.taskbar.showRunningApps=[bool]$sender.IsChecked;$script:settingsDirty=$true}});$dockContent.Children.Add($taskbarRunning)|Out-Null
    $taskbarStart=[System.Windows.Controls.CheckBox]::new();$taskbarStart.Content='Show a Start button in the dock';$taskbarStart.IsChecked=[bool]$script:config.taskbar.showStartButton;$taskbarStart.Foreground=$script:textBrush
    $taskbarStart.Add_Click({param($sender,$eventArgs)if(-not $script:settingsLoading){$script:config.taskbar.showStartButton=[bool]$sender.IsChecked;$script:settingsDirty=$true}});$dockContent.Children.Add($taskbarStart)|Out-Null
    $appsList=[System.Windows.Controls.ListBox]::new();$appsList.Height=132;$appsList.Margin=[System.Windows.Thickness]::new(0,8,0,4);$appsList.DisplayMemberPath='name';$appsList.ItemsSource=@($script:config.pinnedApps);$appsList.Background=$script:surfaceAltBrush;$appsList.Foreground=$script:textBrush
    $dockContent.Children.Add((New-BakaText 'Pinned apps' 12 'Bold'))|Out-Null;$dockContent.Children.Add($appsList)|Out-Null
    $appActions=[System.Windows.Controls.WrapPanel]::new()
    $addApp=New-BakaActionButton 'Add application' {param($sender,$eventArgs)$appsList=$sender.Tag;$dialog=[System.Windows.Forms.OpenFileDialog]::new();$dialog.Filter='Applications (*.exe)|*.exe';$dialog.Title='Choose an application to pin';if($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){$base=[IO.Path]::GetFileNameWithoutExtension($dialog.FileName);$id=$base.ToLowerInvariant()+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6);$script:config.pinnedApps=@($script:config.pinnedApps)+@([pscustomobject]@{id=$id;name=$base;kind='Executable';target=$dialog.FileName;arguments='';processName=$base;glyph='';iconPath=''});$appsList.ItemsSource=@($script:config.pinnedApps);$script:settingsDirty=$true}} ([string][char]0xE8A5)
    $addApp.Tag=$appsList
    $removeApp=New-BakaActionButton 'Remove selected' {param($sender,$eventArgs)$appsList=$sender.Tag;$selected=$appsList.SelectedItem;if($selected){$script:config.pinnedApps=@($script:config.pinnedApps|Where-Object {$_.id -ne $selected.id});$appsList.ItemsSource=@($script:config.pinnedApps);$script:settingsDirty=$true}} ([string][char]0xE74D)
    $removeApp.Tag=$appsList
    $iconApp=New-BakaActionButton 'Custom icon' {param($sender,$eventArgs)$appsList=$sender.Tag;$selected=$appsList.SelectedItem;if(-not $selected){[System.Windows.Forms.MessageBox]::Show('Select a pinned app first.','Custom icon',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)|Out-Null;return};$dialog=[System.Windows.Forms.OpenFileDialog]::new();$dialog.Filter='Icons and pictures|*.png;*.jpg;*.jpeg;*.bmp;*.ico;*.gif';$dialog.Title=('Choose an icon for {0}' -f $selected.name);if($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){$selected|Add-Member -NotePropertyName iconPath -NotePropertyValue $dialog.FileName -Force;$appsList.ItemsSource=@($script:config.pinnedApps);$script:settingsDirty=$true;Set-BakaDockAppearance}} ([string][char]0xE8B9)
    $iconApp.Tag=$appsList
    $iconReset=New-BakaActionButton 'Default icon' {param($sender,$eventArgs)$appsList=$sender.Tag;$selected=$appsList.SelectedItem;if($selected){$selected|Add-Member -NotePropertyName iconPath -NotePropertyValue '' -Force;$appsList.ItemsSource=@($script:config.pinnedApps);$script:settingsDirty=$true;Set-BakaDockAppearance}} ([string][char]0xE777)
    $iconReset.Tag=$appsList
    $appActions.Children.Add($addApp)|Out-Null;$appActions.Children.Add($removeApp)|Out-Null;$appActions.Children.Add($iconApp)|Out-Null;$appActions.Children.Add($iconReset)|Out-Null;$dockContent.Children.Add($appActions)|Out-Null
    $dockScroll.Content=$dockContent;$dockTab.Content=$dockScroll;$tabs.Items.Add($dockTab)|Out-Null

    $barTab=[System.Windows.Controls.TabItem]::new();$barTab.Header='Top bar';$barContent=[System.Windows.Controls.StackPanel]::new();$barContent.Margin=[System.Windows.Thickness]::new(14)
    $barContent.Children.Add((New-BakaHeading 'Optional system bar' 'A compact BAKA status strip. It closes while an approved game process is running.'))|Out-Null
    $barEnabled=[System.Windows.Controls.CheckBox]::new();$barEnabled.Content='Show the BAKA top bar';$barEnabled.IsChecked=[bool]$script:config.topBar.enabled;$barEnabled.Foreground=$script:textBrush
    $barEnabled.Add_Click({param($sender,$eventArgs)if(-not $script:settingsLoading){$script:config.topBar.enabled=[bool]$sender.IsChecked;$script:settingsDirty=$true}});$barContent.Children.Add($barEnabled)|Out-Null
    $barStatus=[System.Windows.Controls.CheckBox]::new();$barStatus.Content='Show active profile';$barStatus.IsChecked=[bool]$script:config.topBar.showProfile;$barStatus.Foreground=$script:textBrush
    $barStatus.Add_Click({param($sender,$eventArgs)if(-not $script:settingsLoading){$script:config.topBar.showProfile=[bool]$sender.IsChecked;$script:settingsDirty=$true}});$barContent.Children.Add($barStatus)|Out-Null
    $barDate=[System.Windows.Controls.CheckBox]::new();$barDate.Content='Show date and time';$barDate.IsChecked=[bool]$script:config.topBar.showDate;$barDate.Foreground=$script:textBrush
    $barDate.Add_Click({param($sender,$eventArgs)if(-not $script:settingsLoading){$script:config.topBar.showDate=[bool]$sender.IsChecked;$script:settingsDirty=$true}});$barContent.Children.Add($barDate)|Out-Null
    $barMonitor=[System.Windows.Controls.ComboBox]::new();[void]$barMonitor.Items.Add('Primary');foreach($screen in [System.Windows.Forms.Screen]::AllScreens){[void]$barMonitor.Items.Add($screen.DeviceName)};$barMonitor.SelectedItem=[string]$script:config.topBar.monitor
    $barMonitor.Add_SelectionChanged({param($sender,$eventArgs)if($sender.SelectedItem -and -not $script:settingsLoading){$script:config.topBar.monitor=[string]$sender.SelectedItem;$script:settingsDirty=$true}})
    $barContent.Children.Add((New-BakaRow 'Display' 'Choose where the optional bar appears.' $barMonitor))|Out-Null
    $barContent.Children.Add((New-BakaText 'The native Windows taskbar and its tray remain available. The BAKA bar does not replace Windows notifications or system controls.' 11 'Normal' $script:mutedBrush))|Out-Null
    $barTab.Content=$barContent;$tabs.Items.Add($barTab)|Out-Null

    $widgetsTab=[System.Windows.Controls.TabItem]::new();$widgetsTab.Header='Widgets';$widgetsScroll=[System.Windows.Controls.ScrollViewer]::new();$widgetsScroll.VerticalScrollBarVisibility=[System.Windows.Controls.ScrollBarVisibility]::Auto
    $widgetsContent=[System.Windows.Controls.StackPanel]::new();$widgetsContent.Margin=[System.Windows.Thickness]::new(14);$widgetsContent.Children.Add((New-BakaHeading 'Desktop widgets' 'Move a card by dragging its title. Resize with the window edge. Hidden widgets stop refreshing.'))|Out-Null
    $widgetMaster=[System.Windows.Controls.CheckBox]::new();$widgetMaster.Content='Enable desktop widgets';$widgetMaster.IsChecked=[bool]$script:config.widgets.enabled;$widgetMaster.Foreground=$script:textBrush;$widgetsContent.Children.Add($widgetMaster)|Out-Null
    $widgetMaster.Add_Click({param($sender,$eventArgs)if(-not $script:settingsLoading){$script:config.widgets.enabled=[bool]$sender.IsChecked;$script:widgetUserVisible=[bool]$sender.IsChecked;$script:settingsDirty=$true}})
    $widgetChecks=@{}
    foreach($entry in @($script:config.widgets.items)){
        $check=[System.Windows.Controls.CheckBox]::new();$check.Content=(Get-BakaWidgetTitle ([string]$entry.id));$check.IsChecked=[bool]$entry.enabled;$check.Foreground=$script:textBrush;$check.Margin=[System.Windows.Thickness]::new(0,5,0,5)
        $id=[string]$entry.id
        $check.Tag=$id
        $check.Add_Click({param($sender,$eventArgs)if(-not $script:settingsLoading){$items=Get-BakaWidgetItem ([string]$sender.Tag);if($items){$items[0].enabled=[bool]$sender.IsChecked};$script:settingsDirty=$true}})
        $widgetChecks[$id]=$check;$widgetsContent.Children.Add($check)|Out-Null
    }
    $refresh=[System.Windows.Controls.Slider]::new();$refresh.Minimum=2;$refresh.Maximum=30;$refresh.Value=[double]$script:config.widgets.refreshSeconds;$refresh.TickFrequency=1;$refresh.IsSnapToTickEnabled=$true
    $refresh.Add_ValueChanged({param($sender,$eventArgs)if(-not $script:settingsLoading){$script:config.widgets.refreshSeconds=[int]$sender.Value;$script:settingsDirty=$true}})
    $widgetsContent.Children.Add((New-BakaRow 'System monitor refresh' 'Seconds between Windows performance-counter reads while the system widget is visible.' $refresh))|Out-Null
    $widgetEdit=New-BakaActionButton 'Open widget layout' {if(-not $script:config.widgets.enabled){$script:config.widgets.enabled=$true;$script:widgetUserVisible=$true};Save-BakaDesktopConfiguration -Path $script:settingsPath -Configuration $script:config|Out-Null;Show-BakaWidgets} ([string][char]0xE80F)
    $widgetsContent.Children.Add($widgetEdit)|Out-Null
    $widgetsContent.Children.Add((New-BakaText 'GPU temperature is shown as unavailable unless Windows exposes a reliable sensor. No vendor suite, external service, or clipboard access is used.' 10 'Normal' $script:mutedBrush))|Out-Null
    $widgetsScroll.Content=$widgetsContent;$widgetsTab.Content=$widgetsScroll;$tabs.Items.Add($widgetsTab)|Out-Null

    $footer=[System.Windows.Controls.WrapPanel]::new();$footer.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Right
    $save=New-BakaActionButton 'Save changes' {try{Save-BakaSettingsDraft}catch{[System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Settings not saved',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)|Out-Null}} ([string][char]0xE74E)
    $reset=New-BakaActionButton 'Reset defaults' {if([System.Windows.Forms.MessageBox]::Show('Reset BAKA appearance, dock, bar, and widget settings to the reviewed defaults?','Reset BAKA settings',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Question) -eq [System.Windows.Forms.DialogResult]::Yes){$script:config=Get-BakaDefaultDesktopConfiguration;$script:wallpaperDirty=$true;$script:widgetUserVisible=[bool]$script:config.widgets.enabled;$script:settingsDirty=$true;Invoke-BakaSettingsRefresh;[System.Windows.Forms.MessageBox]::Show('Defaults are previewed. Choose Save changes to persist them.','BAKA settings',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)|Out-Null}} ([string][char]0xE777)
    $restore=New-BakaActionButton 'Restore previous' {try{$previous=Get-Content -LiteralPath ($script:settingsPath+'.bak') -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop;$valid=Test-BakaDesktopConfiguration $previous;if(-not $valid.Valid){throw ($valid.Errors -join ' ')};$script:config=Complete-BakaDesktopConfiguration -Configuration $previous;$script:wallpaperDirty=$true;$script:widgetUserVisible=[bool]$script:config.widgets.enabled;$script:settingsDirty=$true;Invoke-BakaSettingsRefresh;[System.Windows.Forms.MessageBox]::Show('Previous settings are previewed. Choose Save changes to keep them.','BAKA settings',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)|Out-Null}catch{[System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Previous settings unavailable',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning)|Out-Null}} ([string][char]0xE777)
    $export=New-BakaActionButton 'Export' { $dialog=[System.Windows.Forms.SaveFileDialog]::new();$dialog.Filter='BAKA settings (*.json)|*.json';$dialog.FileName='baka-desktop-settings.json';if($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){Export-BakaDesktopConfiguration -Path $dialog.FileName -Configuration $script:config|Out-Null}} ([string][char]0xE74E)
    $import=New-BakaActionButton 'Import' { try{$dialog=[System.Windows.Forms.OpenFileDialog]::new();$dialog.Filter='BAKA settings (*.json)|*.json';if($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){$candidate=Get-Content -LiteralPath $dialog.FileName -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop;$valid=Test-BakaDesktopConfiguration $candidate;if(-not $valid.Valid){throw ($valid.Errors -join ' ')};$script:config=Complete-BakaDesktopConfiguration -Configuration $candidate;$script:wallpaperDirty=$true;$script:widgetUserVisible=[bool]$script:config.widgets.enabled;$script:settingsDirty=$true;Invoke-BakaSettingsRefresh}}catch{[System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Settings import failed',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning)|Out-Null} } ([string][char]0xE8B5)
    foreach($button in @($import,$export,$restore,$reset,$save)){$footer.Children.Add($button)|Out-Null}
    [System.Windows.Controls.Grid]::SetRow($footer,2);$layout.Children.Add($footer)|Out-Null
    Set-BakaSettingsControlTheme $layout
    Set-BakaWindowContent $window $layout;$script:windows.Settings=$window
    $window.add_Closing({param($sender,$eventArgs) if(-not $script:allowShutdown -and -not $script:allowSettingsClose){$eventArgs.Cancel=$true;Close-BakaSettings}})
    $window.add_KeyDown({param($sender,$eventArgs) if($eventArgs.Key -eq [System.Windows.Input.Key]::Escape){Close-BakaSettings}})
    $script:settingsTabs=$tabs
    $tabs.Add_SelectionChanged({param($sender,$eventArgs)if($sender -is [System.Windows.Controls.TabControl]){foreach($tabItem in $sender.Items){if($tabItem.IsSelected){$tabItem.Foreground=(New-BakaBrush '#17191E' 255)}else{$tabItem.Foreground=$script:textBrush}}}})
    foreach($tabItem in $tabs.Items){if($tabItem.IsSelected){$tabItem.Foreground=(New-BakaBrush '#17191E' 255)}else{$tabItem.Foreground=$script:textBrush}}
    $script:settingsControls=@{Theme=$themeCombo;Accent=$accentInput;Glass=$glass;Motion=$motion;ReducedMotion=$reducedMotion;DockSize=$size;DockSpacing=$spacing;DockAlignment=$align;DockMonitor=$monitorCombo;DockAutoHide=$autoHide;DockMagnify=$magnify;PinnedApps=$appsList;BarEnabled=$barEnabled;BarProfile=$barStatus;BarDate=$barDate;BarMonitor=$barMonitor;WidgetsEnabled=$widgetMaster;WidgetChecks=$widgetChecks;WidgetRefresh=$refresh;WallpaperMode=$wallpaperMode;WallpaperPath=$wallpaperPath;WallpaperFit=$wallpaperFit;WallpaperColor=$wallpaperColor;WallpaperMuted=$wallpaperMuted;WallpaperPause=$wallpaperPause;TaskbarHide=$taskbarHide;TaskbarRunning=$taskbarRunning;TaskbarStart=$taskbarStart}
    $script:settingsLoading=$false
    return $window
}
function Show-BakaSettings([string]$Tab=''){
    if(-not $script:windows.Settings){$script:settingsLoading=$true;$script:settingsOriginal=Copy-BakaSettings $script:config;$script:windows.Settings=New-BakaSettings}
    if($Tab){$match=@($script:settingsTabs.Items|Where-Object {$_.Header -eq $Tab}|Select-Object -First 1);if($match){$script:settingsTabs.SelectedItem=$match[0]}}
    $script:settingsOriginal=Copy-BakaSettings $script:config
    $script:settingsDirty=$false
    Update-BakaSettingsControls
    Show-BakaWindow $script:windows.Settings -Activate
}

function Show-BakaQuickPanel {
    if(-not $script:windows.Quick){$panel=New-BakaQuickPanel;if(-not $panel){throw 'Quick Panel window construction returned no window.'};$script:windows.Quick=$panel}
    $window=$script:windows.Quick
    if(-not $window){throw 'Quick Panel window is unavailable.'}
    $area=(Get-BakaActiveScreen).WorkingArea
    $window.Height=[math]::Min(660,$area.Height-40)
    $window.Left=$area.Right-$window.Width-22;$window.Top=[math]::Max($area.Top+12,$area.Bottom-$window.Height-124)
    try{Show-BakaWindow $window -Activate}catch{Write-BakaUiLog ('quick-panel-show-failed windowType="{0}" error="{1}" stack="{2}"' -f $window.GetType().FullName,$_.Exception.ToString(),$_.ScriptStackTrace);throw}
}

function Update-BakaDockIndicators {
    foreach($app in @($script:config.pinnedApps)){
        $button=$script:dockButtons[[string]$app.id]
        if(-not $button){continue}
        $running=[bool](Get-BakaProcessForApp $app)
        if($running){$button.BorderBrush=$script:accentBrush;$button.BorderThickness=[System.Windows.Thickness]::new(0,0,0,2)}
        else{$button.BorderThickness=[System.Windows.Thickness]::new(0)}
        if($button.Resources.Contains('BAKA.RunningIndicator')){
            $indicator=$button.Resources['BAKA.RunningIndicator'];$target=if($running){1.0}else{0.0}
            if([math]::Abs([double]$indicator.Opacity-$target) -gt 0.04){
                $duration=if($script:motionEnabled){220}else{90}
                $fade=[System.Windows.Media.Animation.DoubleAnimation]::new($target,[TimeSpan]::FromMilliseconds($duration))
                $fadeEase=[System.Windows.Media.Animation.CubicEase]::new();$fadeEase.EasingMode=[System.Windows.Media.Animation.EasingMode]::EaseOut;$fade.EasingFunction=$fadeEase
                $indicator.BeginAnimation([System.Windows.UIElement]::OpacityProperty,$fade)
            }
        }
    }
}
function Update-BakaClock {
    if($script:windows.BarClock -and $script:windows.BarClock.IsVisible){
        if($script:config.topBar.showDate){$script:windows.BarClock.Text=Get-Date -Format 'ddd, d MMM  ·  HH:mm'}else{$script:windows.BarClock.Text=Get-Date -Format 'HH:mm'}
    }
    if($script:widgetWindows.ContainsKey('clockTime') -and $script:widgetWindows['clockTime'].IsVisible){$script:widgetWindows['clockTime'].Text=Get-Date -Format 'HH:mm';$script:widgetWindows['clockDate'].Text=Get-Date -Format 'dddd, d MMMM yyyy'}
    if($script:windows.BarNetwork){
        $online=[System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()
        $script:windows.BarNetwork.Text=if($online){'ONLINE'}else{'OFFLINE'}
        if($script:windows.QuickNetwork){$script:windows.QuickNetwork.Text=if($online){'Network available · Windows controls Wi-Fi and Ethernet'}else{'No active network · Windows controls Wi-Fi and Ethernet'}}
    }
    if($script:windows.BarBattery){
        $power=[System.Windows.Forms.SystemInformation]::PowerStatus
        if(($power.BatteryChargeStatus -band [System.Windows.Forms.BatteryChargeStatus]::NoSystemBattery) -ne [System.Windows.Forms.BatteryChargeStatus]::NoSystemBattery){$script:windows.BarBattery.Text=('BATTERY {0}%' -f [math]::Round($power.BatteryLifePercent*100));$script:windows.BarBattery.Visibility=[System.Windows.Visibility]::Visible}
        else{$script:windows.BarBattery.Visibility=[System.Windows.Visibility]::Collapsed}
    }
    if($script:windows.DashClock -and $script:windows.DashClock.IsVisible){$script:windows.DashClock.Text=Get-Date -Format 'HH:mm'}
    if($script:windows.DashClockLarge -and $script:windows.Dashboard -and $script:windows.Dashboard.IsVisible){$script:windows.DashClockLarge.Text=Get-Date -Format 'HH:mm'}
}
function Set-BakaBarVisibility([bool]$GameDetected){
    if(-not $script:windows.TopBar){return}
    if($script:config.topBar.enabled -and -not $GameDetected){if(-not $script:windows.TopBar.IsVisible){Show-BakaWindow $script:windows.TopBar}}
    else{$script:windows.TopBar.Hide()}
    if($script:windows.BarProfile){$script:windows.BarProfile.Visibility=if($script:config.topBar.showProfile){[System.Windows.Visibility]::Visible}else{[System.Windows.Visibility]::Collapsed}}
    if($script:windows.BarClock){$script:windows.BarClock.Visibility=if($script:config.topBar.showDate){[System.Windows.Visibility]::Visible}else{[System.Windows.Visibility]::Collapsed}}
}
function Exit-BakaCompanion {
    try {
        [void](Set-BakaCompanionProfile 'Desktop')
        $script:activeProfile='Desktop';$script:allowShutdown=$true
        $script:smokeTestMode=$false
        $script:app.Shutdown(0)
    } catch {
        Write-BakaUiLog ('exit-blocked profile-restore-failed error="{0}"' -f $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show(('BAKA kept running because it could not restore your prior desktop settings.`r`n`r`n{0}' -f $_.Exception.Message),'BAKA safe exit',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)|Out-Null
    }
}
function New-BakaTrayIcon {
    $icon=[System.Windows.Forms.NotifyIcon]::new();$icon.Text='BAKA Liquid Desktop';$icon.Icon=[System.Drawing.SystemIcons]::Application;$icon.Visible=$true
    $menu=[System.Windows.Forms.ContextMenuStrip]::new()
    $show=$menu.Items.Add('Show BAKA dock');$show.Add_Click({param($sender,$eventArgs)Show-BakaWindow $script:windows.Dock -Activate})
    $arena=$menu.Items.Add('Open BAKA Arena');$arena.Add_Click({param($sender,$eventArgs)Show-BakaDashboard})
    $files=$menu.Items.Add('Open BAKA Files');$files.Add_Click({param($sender,$eventArgs)Show-BakaFiles})
    $quick=$menu.Items.Add('Open Quick Panel');$quick.Add_Click({param($sender,$eventArgs)Show-BakaQuickPanel})
    $desktop=$menu.Items.Add('Switch to Desktop profile');$desktop.Add_Click({param($sender,$eventArgs)[void](Set-BakaUiProfile 'Desktop' 'Manual')})
    [void]$menu.Items.Add('-')
    $exit=$menu.Items.Add('Exit BAKA');$exit.Add_Click({param($sender,$eventArgs)Exit-BakaCompanion})
    $icon.ContextMenuStrip=$menu
    $icon.add_DoubleClick({param($sender,$eventArgs)Show-BakaQuickPanel})
    $script:trayIcon=$icon
}

$script:dockHideTimer=[System.Windows.Threading.DispatcherTimer]::new()
$script:dockHideTimer.Interval=[TimeSpan]::FromMilliseconds(1400)
$script:dockHideTimer.Add_Tick({param($sender,$eventArgs)$sender.Stop();if($script:config.dock.autoHide -and $script:windows.Dock -and -not $script:windows.Dock.IsMouseOver -and -not $script:autoGame){$script:windows.Dock.Hide();Write-BakaUiLog 'dock-auto-hidden'}})
$script:clockTimer=[System.Windows.Threading.DispatcherTimer]::new()
$script:clockTimer.Interval=[TimeSpan]::FromSeconds(1)
$script:clockTimer.Add_Tick({param($sender,$eventArgs)Update-BakaClock})
$script:systemMetricsTimer=[System.Windows.Threading.DispatcherTimer]::new()
$script:systemMetricsTimer.Interval=[TimeSpan]::FromSeconds([int]$script:config.widgets.refreshSeconds)
    $script:systemMetricsTimer.Add_Tick({param($sender,$eventArgs)if($script:activeProfile -eq 'Desktop' -and (($script:widgetWindows.ContainsKey('system') -and $script:widgetWindows['system'].IsVisible) -or ($script:windows.Dashboard -and $script:windows.Dashboard.IsVisible))){Start-BakaMetricRead}else{$sender.Stop()}})
$script:runningAppsTimer=[System.Windows.Threading.DispatcherTimer]::new()
$script:runningAppsTimer.Interval=[TimeSpan]::FromSeconds(3)
$script:runningAppsTimer.Add_Tick({param($sender,$eventArgs)try{if($script:windows.Dock -and $script:windows.Dock.IsVisible){Update-BakaDockRunningApps;Update-BakaDockIndicators}}catch{Write-BakaUiLog ('running-apps-refresh-failed error="{0}"' -f $_.Exception.Message)}})
$script:profileTimer=[System.Windows.Threading.DispatcherTimer]::new()
$script:profileTimer.Interval=[TimeSpan]::FromSeconds(4)
$script:profileTimer.Add_Tick({
    try {
        if($script:manualOverride){Update-BakaProfileStatus;return}
        $game=Get-BakaDetectedGame
        $gameDetected=[bool]$game
        if($gameDetected){$script:detectedGame=$game.DisplayName}else{$script:detectedGame=$null}
        if(-not $script:manualOverride){
            if($gameDetected -and -not $script:autoGame){$script:autoGame=$true;[void](Set-BakaUiProfile 'CompetitiveGaming' 'Auto')}
            elseif(-not $gameDetected -and $script:autoGame){$script:autoGame=$false;[void](Set-BakaUiProfile 'Desktop' 'Auto')}
        }
        if($gameDetected){
            if($script:windows.Dock.IsVisible){$script:windows.Dock.Hide()}
            if($script:windows.Dashboard -and $script:windows.Dashboard.IsVisible){$script:windows.Dashboard.Hide()}
            if($script:windows.Quick -and $script:windows.Quick.IsVisible){$script:windows.Quick.Hide()}
            Set-BakaBarVisibility $true
            Hide-BakaWidgets
        }else{
            if(-not $script:windows.Dock.IsVisible -and -not $script:config.dock.autoHide){Show-BakaWindow $script:windows.Dock}
            Set-BakaBarVisibility $false
            if($script:activeProfile -eq 'Desktop' -and $script:widgetUserVisible -and $script:config.widgets.enabled -and @($script:widgetWindows.Values|Where-Object {$_ -is [System.Windows.Window] -and $_.IsVisible}).Count -eq 0){Show-BakaWidgets}
        }
        Update-BakaProfileStatus;Update-BakaDockIndicators
    } catch {Write-BakaUiLog ('profile-poll-failed error="{0}"' -f $_.Exception.Message)}
})

$script:windows.Dashboard=New-BakaDashboard
$script:windows.Dock=New-BakaDock
$script:windows.Quick=$null
$script:windows.TopBar=New-BakaTopBar
$script:windows.Settings=$null
$script:windows.BarProfile=New-BakaText 'DESKTOP' 10 'Normal' $script:accentBrush
$script:windows.BarProfile.Visibility=if($script:config.topBar.showProfile){[System.Windows.Visibility]::Visible}else{[System.Windows.Visibility]::Collapsed}
$script:windows.BarProfile.Margin=[System.Windows.Thickness]::new(12,0,8,0)
$topBarContentHost=Get-BakaWindowContentHost $script:windows.TopBar
if($topBarContentHost -and $topBarContentHost.Children.Count -gt 0){
    $topBarLayout=$topBarContentHost.Children[0]
    if($topBarLayout.Children.Count -gt 2){$rightStack=$topBarLayout.Children[2];$rightStack.Children.Insert(0,$script:windows.BarProfile)|Out-Null}
}
Set-BakaDockAppearance
Update-BakaProfileStatus
New-BakaTrayIcon
$script:app.add_Exit({
    Write-BakaUiLog 'companion-exit-cleanup-start'
    foreach($timer in @($script:dockHideTimer,$script:clockTimer,$script:systemMetricsTimer,$script:profileTimer,$script:runningAppsTimer,$script:smokeTimer)){if($timer){$timer.Stop()}}
    Stop-BakaMetricWorker
    Stop-BakaVideoWallpaper
    Restore-BakaTaskbarMode
    if($script:trayIcon){$script:trayIcon.Visible=$false;$script:trayIcon.Dispose()}
    try{[void](Set-BakaCompanionProfile 'Desktop')}catch{Write-BakaUiLog ('shutdown-restore-failed error="{0}"' -f $_.Exception.Message)}
    try{Exit-BakaCompanionInstance -Lock $script:instanceLock}catch{}
    Write-BakaUiLog 'companion-exit-cleanup-complete'
})
$script:windows.Dock.add_Loaded({
    Start-BakaWindowEntrance $script:windows.Dock
    # Show the Arena welcome once (first run); afterwards it opens only from the dock's Arena button.
    $arenaSeen=Join-Path $settingsDirectory 'arena-welcome-shown'
    if($ArenaSmoke -or -not (Test-Path -LiteralPath $arenaSeen)){Show-BakaDashboard;try{[IO.File]::WriteAllText($arenaSeen,(Get-Date).ToString('o'))}catch{}}
    if($FileSmoke){$script:windows.Dashboard.Hide();Show-BakaFiles}
    if($script:config.topBar.enabled -and -not $script:autoGame){Show-BakaWindow $script:windows.TopBar}
    if($script:config.widgets.enabled -and $script:widgetUserVisible){Show-BakaWidgets}
    Update-BakaClock;Update-BakaProfileStatus
    $script:profileTimer.Start();$script:clockTimer.Start();$script:runningAppsTimer.Start()
    Invoke-BakaTaskbarMode
    if([string]$script:config.wallpaper.mode -ne 'Default'){Invoke-BakaWallpaper}
    if($script:config.widgets.enabled -and $script:widgetUserVisible){Update-BakaWidgetPolling}
    if($script:config.dock.autoHide -and -not $script:autoGame){$script:dockHideTimer.Start()}
    Write-BakaUiLog ('companion-ready release="{0}" profile={1} theme="{2}" widgets={3}' -f $script:uiRelease,$script:activeProfile,$script:config.appearance.theme,$script:config.widgets.enabled)
    if($script:previewMode -and $CapturePath){
        # Design capture: renders only BAKA surfaces over the BAKA wallpaper (never the user's real desktop).
        $script:captureTimer=[System.Windows.Threading.DispatcherTimer]::new();$script:captureTimer.Interval=[TimeSpan]::FromSeconds(4);$script:captureStep=0
        $script:captureTimer.Add_Tick({param($sender,$eventArgs)
            $script:captureStep++
            if($script:captureStep -eq 1){Show-BakaQuickPanel;return}
            $sender.Stop()
            try{
                $screen=[System.Windows.SystemParameters]::PrimaryScreenWidth;$screenH=[System.Windows.SystemParameters]::PrimaryScreenHeight
                $visual=[System.Windows.Media.DrawingVisual]::new();$context=$visual.RenderOpen()
                $wallpaper=Get-BakaShippedWallpaperPath
                if($wallpaper){$image=[System.Windows.Media.Imaging.BitmapImage]::new([Uri]::new($wallpaper));$context.DrawImage($image,[System.Windows.Rect]::new(0,0,$screen,$screenH))}
                foreach($key in @('Dashboard','Dock','TopBar','Quick')){
                    $window=$script:windows[$key]
                    if(-not $window -or -not $window.IsVisible){continue}
                    $surface=$window.Content;$width=[int][math]::Ceiling($window.ActualWidth);$height=[int][math]::Ceiling($window.ActualHeight)
                    if($width -le 0 -or $height -le 0){continue}
                    $bitmap=[System.Windows.Media.Imaging.RenderTargetBitmap]::new($width,$height,96,96,[System.Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($surface)
                    $context.DrawImage($bitmap,[System.Windows.Rect]::new($window.Left-[System.Windows.SystemParameters]::VirtualScreenLeft,$window.Top-[System.Windows.SystemParameters]::VirtualScreenTop,$width,$height))
                }
                $context.Close()
                $output=[System.Windows.Media.Imaging.RenderTargetBitmap]::new([int]$screen,[int]$screenH,96,96,[System.Windows.Media.PixelFormats]::Pbgra32);$output.Render($visual)
                $encoder=[System.Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($output))
                $stream=[IO.File]::Create($CapturePath);try{$encoder.Save($stream)}finally{$stream.Dispose()}
                Write-BakaUiLog ('design-capture-saved path="{0}"' -f $CapturePath)
            }catch{Write-BakaUiLog ('design-capture-failed error="{0}"' -f $_.Exception.Message)}
            Exit-BakaCompanion
        })
        $script:captureTimer.Start()
    }
    if($script:smokeTestMode){
        $script:smokeStage=0
        $script:smokeTimer=[System.Windows.Threading.DispatcherTimer]::new();$script:smokeTimer.Interval=[TimeSpan]::FromMilliseconds(1200)
        $script:smokeTimer.Add_Tick({param($sender,$eventArgs)
            if(-not $script:smokeTestMode){$sender.Stop();return}
            $script:smokeStage++
            try{
                switch($script:smokeStage){
                    1 {
                         Show-BakaDashboard;Show-BakaQuickPanel;Show-BakaSettings
                         if(-not $script:windows.Dashboard.IsVisible -or -not $script:windows.Dock.IsVisible -or -not $script:windows.Quick.IsVisible -or -not $script:windows.Settings.IsVisible -or -not $script:windows.TopBar -or -not $script:windows.TopBar.IsVisible){throw 'A primary BAKA surface did not become visible.'}
                        if($script:theme.name -ne 'BAKA Pop Glass' -or -not $script:popStyle -or -not $script:motionEnabled){throw 'The default BAKA Pop Glass theme did not enable desktop motion.'}
                        $keycapTile=@($script:windows.DockAppPanel.Children|Where-Object {$_ -is [System.Windows.Controls.Button]}|Select-Object -First 1)[0].Content.Children[0]
                        if(-not ($keycapTile.Effect -is [System.Windows.Media.Effects.DropShadowEffect]) -or $keycapTile.Effect.BlurRadius -ne 0 -or -not [object]::ReferenceEquals($keycapTile.BorderBrush,$script:ringBrush)){throw 'Dock tiles did not use the Pop Glass keycap (ring + hard shadow).'}
                        Set-BakaKeycapPressed $keycapTile $true;Set-BakaKeycapPressed $keycapTile $false
                        if(-not $script:windows.Dock.Tag.Tag.Light -or -not $script:windows.Dock.Tag.Tag.Rim){throw 'Glass surfaces are missing the liquid light or specular rim.'}
                        Start-BakaDockBounce @($script:windows.DockAppPanel.Children)[0]
                        Write-BakaUiLog 'ui-smoke-stage=pop-glass-keycaps'
                        Write-BakaUiLog ('glass-smoke-state opaque={0} fallback={1} dockBackground={2} glassBrush={3} surfaceBrush={4}' -f $script:opaqueMode,$script:dwmBackdropUnsupported,$script:windows.Dock.Tag.Background.GetType().FullName,$script:glassBrush.GetType().FullName,$script:surfaceBrush.GetType().FullName)
                         foreach($surfaceKey in @('Dashboard','Dock','Quick','TopBar','Settings')){
                            $surfaceBackground=$script:windows[$surfaceKey].Tag.Background
                            if($script:opaqueMode){if($surfaceBackground -isnot [System.Windows.Media.SolidColorBrush]){throw "The $surfaceKey surface did not use the opaque fallback."}}
                            elseif($surfaceBackground -isnot [System.Windows.Media.LinearGradientBrush]){throw "The $surfaceKey surface did not retain the layered glass fill."}
                        }
                        $settingsLayout=$script:windows.Settings.Tag.Tag.ContentHost.Children[0]
                        if($settingsLayout.Background -ne [System.Windows.Media.Brushes]::Transparent){throw 'The settings layout is covering its glass backdrop.'}
                        $pin=@($script:windows.DockAppPanel.Children|Where-Object {$_ -is [System.Windows.Controls.Button]}|Select-Object -First 1)
                        if(-not $pin){throw 'The dock has no pinned application to animate.'}
                        Set-BakaDockHover $pin[0]
                        if($pin[0].RenderTransform -isnot [System.Windows.Media.ScaleTransform] -or -not $pin[0].RenderTransform.HasAnimatedProperties){throw 'Dock magnification did not create an animated transform.'}
                        $tile=$pin[0].Content.Children[0];Set-BakaButtonHover $pin[0] $true
                        if($tile.RenderTransform -isnot [System.Windows.Media.ScaleTransform] -or -not $tile.RenderTransform.HasAnimatedProperties){throw 'The dock icon lift did not create an animated transform.'}
                        Set-BakaButtonHover $pin[0] $false;Set-BakaDockHover $null
                        Write-BakaUiLog 'ui-smoke-stage=surfaces-visible';Write-BakaUiLog 'ui-smoke-stage=liquid-glass-motion';Write-BakaUiLog 'ui-smoke-stage=glass-surface-coverage';Write-BakaUiLog 'ui-animation=dock-wave centerScale=1.26 neighborScale=1.13'
                    }
                    2 {[void](Set-BakaUiProfile 'CompetitiveGaming' 'Manual');if($script:activeProfile -ne 'CompetitiveGaming'){throw 'Gaming profile switch did not update UI state.'};if(@($script:widgetWindows.Values|Where-Object {$_ -is [System.Windows.Window] -and $_.IsVisible}).Count -gt 0){throw 'Widgets remained visible during Gaming profile.'};if($script:motionEnabled -or -not $script:opaqueMode){throw 'Gaming profile did not suppress UI motion and translucent surfaces.'};Write-BakaUiLog 'ui-smoke-stage=gaming-profile';Write-BakaUiLog 'ui-smoke-stage=gaming-profile-motion-suppressed'}
                    3 {[void](Set-BakaUiProfile 'Benchmark' 'Manual');if($script:activeProfile -ne 'Benchmark'){throw 'Benchmark profile switch did not update UI state.'};if($script:motionEnabled -or -not $script:opaqueMode){throw 'Benchmark profile did not suppress UI motion and translucent surfaces.'};Write-BakaUiLog 'ui-smoke-stage=benchmark-profile';Write-BakaUiLog 'ui-smoke-stage=benchmark-profile-motion-suppressed'}
                    4 {[void](Set-BakaUiProfile 'Desktop' 'Manual');foreach($theme in $script:themeManifest){Set-BakaTheme ([string]$theme.name)};Set-BakaTheme 'BAKA Obsidian';Show-BakaWidgets;if($script:activeProfile -ne 'Desktop'){throw 'Desktop profile restore did not complete.'};Write-BakaUiLog 'ui-smoke-stage=desktop-restore-and-themes'}
                     5 {
                        if(-not $script:systemMetricsTimer.IsEnabled){throw 'Visible System widget did not enable its polling timer.'}
                        if(-not $script:settingsControls -or $script:settingsControls.Keys.Count -lt 12){throw 'Settings editor controls were not initialized.'}
                        $oldSize=[int]$script:config.dock.iconSize;$script:settingsControls.DockSize.Value=56
                        if([int]$script:config.dock.iconSize -ne 56){throw 'Dock editor did not apply its preview value.'}
                        $script:settingsControls.DockSize.Value=$oldSize;Save-BakaSettingsDraft
                        $area=(Get-BakaScreenByName ([string]$script:config.topBar.monitor)).WorkingArea
                        if([math]::Abs([double]$script:windows.TopBar.Top-([double]$area.Top+8)) -gt 1){throw 'Saving settings did not apply the selected top-bar monitor position.'}
                        $oldRefresh=[int]$script:config.widgets.refreshSeconds
                        $testRefresh=if($oldRefresh -eq 9){8}else{9}
                        $script:settingsControls.WidgetRefresh.Value=$testRefresh
                        Save-BakaSettingsDraft
                        if($script:systemMetricsTimer.Interval.TotalSeconds -ne $testRefresh){throw 'Saving settings did not apply the selected system-widget refresh interval.'}
                        $script:settingsControls.WidgetRefresh.Value=$oldRefresh
                        Save-BakaSettingsDraft
                         Write-BakaUiLog 'ui-smoke-stage=widget-and-settings-check'
                        if(-not $script:windows.DockStartButton -or -not $script:windows.DockRunningPanel){throw 'The dock is missing its Start button or open-window strip.'}
                        if(-not $script:settingsControls.WallpaperMode -or -not $script:settingsControls.TaskbarHide){throw 'Wallpaper and taskbar settings controls were not initialized.'}
                        $savedWallpaper=Copy-BakaSettings $script:config.wallpaper
                        $script:config.wallpaper.mode='Video';$script:config.wallpaper.path='C:\BAKA-Preview\loop.mp4'
                        if(-not (Test-BakaDesktopConfiguration $script:config).Valid){throw 'A video wallpaper selection did not validate.'}
                        $script:config.wallpaper.path='C:\BAKA-Preview\loop.txt'
                        if((Test-BakaDesktopConfiguration $script:config).Valid){throw 'An unsupported wallpaper file type was accepted.'}
                        $script:config.wallpaper.mode='Image';$script:config.wallpaper.path='C:\BAKA-Preview\photo.png';$script:wallpaperDirty=$true;Invoke-BakaWallpaper -Force
                        if($script:wallpaperDirty){throw 'Wallpaper apply did not complete.'}
                        $script:config.wallpaper=$savedWallpaper
                        $script:runningAppSignature='';Update-BakaDockRunningApps;Invoke-BakaTaskbarMode
                        Write-BakaUiLog ('ui-smoke-stage=wallpaper-and-taskbar runningApps={0}' -f $script:windows.DockRunningPanel.Children.Count)
                     }
                     6 {Show-BakaFiles;if(-not $script:windows.Files.IsVisible -or -not $script:fileExplorerList -or $script:fileExplorerList.Items.Count -lt 1){throw 'BAKA Files did not load a readable workspace.'};Write-BakaUiLog ('ui-smoke-stage=files-surface items={0}' -f $script:fileExplorerList.Items.Count)}
                     7 {$script:windows.Files.Hide();Write-BakaUiLog 'ui-smoke-stage=files-close'}
                     {$_ -ge 8 -and $script:systemMetricsLast} {Write-BakaUiLog ('ui-smoke-passed metricsCaptured=true profile={0} themePresets={1}' -f $script:activeProfile,$script:themeManifest.Count);$script:smokeTimer.Stop();Exit-BakaCompanion}
                    {$_ -ge 18} {if($script:systemMetricsError){throw ('System widget metrics failed: '+$script:systemMetricsError)};throw 'System widget metrics did not complete within the smoke-test window.'}
                    {$_ -ge 8} {Write-BakaUiLog 'ui-smoke-stage=metrics-pending'}
                }
                    }catch{$script:smokeFailed=$true;Write-BakaUiLog ('ui-smoke-failed stage={0} error="{1}" position="{2}" stack="{3}"' -f $script:smokeStage,$_.Exception.ToString(),$_.InvocationInfo.PositionMessage,$_.ScriptStackTrace);$script:smokeTimer.Stop();try{[void](Set-BakaCompanionProfile 'Desktop')}catch{};$script:allowShutdown=$true;$script:app.Shutdown()}
        })
        $script:smokeTimer.Start()
    }
})

try {
    $runResult=$script:app.Run($script:windows.Dock)
    if($SmokeTest){$exitCode=if($script:smokeFailed){1}else{0};Write-BakaUiLog ('companion-run-returned exitCode={0}' -f $exitCode);exit $exitCode}
} catch {
    Write-BakaUiLog ('companion-fatal error="{0}"' -f $_.Exception.Message)
    try{[void](Set-BakaCompanionProfile 'Desktop')}catch{}
    [System.Windows.Forms.MessageBox]::Show(('BAKA stopped safely. Explorer remains available.`r`n`r`n{0}' -f $_.Exception.Message),'BAKA Liquid',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)|Out-Null
    if($script:instanceLock.Acquired){Exit-BakaCompanionInstance -Lock $script:instanceLock}
}
