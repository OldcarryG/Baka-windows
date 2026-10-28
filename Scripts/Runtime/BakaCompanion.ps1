[CmdletBinding()]
param([switch]$Preview,[switch]$SmokeTest,[switch]$FileSmoke,[switch]$ArenaSmoke,[string]$CapturePath,[switch]$OpenSettings,[switch]$IdleDesktop)
$ErrorActionPreference='Stop'
if($SmokeTest -and -not $Preview){throw 'The UI smoke test requires -Preview so profile and settings changes remain isolated.'}
# -IdleDesktop (preview only) skips the first-run Arena welcome so the resource sample measures the everyday desktop: dock + menu bar.
if($IdleDesktop -and -not $Preview){throw '-IdleDesktop is a measurement switch and requires -Preview.'}

# BAKA Liquid uses Explorer as the shell and hosts all optional desktop surfaces in one WPF process.
$runtimeRoot=$PSScriptRoot
$scriptsRoot=Split-Path -Parent $runtimeRoot
if((Split-Path -Leaf $runtimeRoot) -ieq 'Runtime' -and (Split-Path -Leaf $scriptsRoot) -ieq 'Scripts'){$dataRoot=Split-Path -Parent $scriptsRoot}else{$dataRoot=$scriptsRoot}
$moduleRoot=Join-Path $dataRoot 'Modules'
$script:previewMode=[bool]$Preview
$script:smokeTestMode=[bool]$SmokeTest
$script:uiRelease='R6 Liquid Desktop'
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
  [StructLayout(LayoutKind.Sequential)] struct ACCENTPOLICY { public int AccentState; public int AccentFlags; public uint GradientColor; public int AnimationId; }
  [StructLayout(LayoutKind.Sequential)] struct COMPOSITIONDATA { public int Attribute; public IntPtr Data; public int SizeOfData; }
  [DllImport("user32.dll")] static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref COMPOSITIONDATA data);
  [DllImport("user32.dll")] public static extern int SetWindowRgn(IntPtr hwnd, IntPtr region, bool redraw);
  [DllImport("gdi32.dll")] public static extern IntPtr CreateRoundRectRgn(int left, int top, int right, int bottom, int widthEllipse, int heightEllipse);
  [DllImport("powrprof.dll", SetLastError=true)] public static extern bool SetSuspendState(bool hibernate, bool forceCritical, bool disableWakeEvent);
  [DllImport("user32.dll")] public static extern bool LockWorkStation();
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd, System.Text.StringBuilder text, int count);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
  // Frosted glass behind a BAKA window (the blur Windows uses for its own flyouts). The window region is
  // rounded first so the blur follows the BAKA corner radius. Returns false when Windows refuses it.
  public static bool EnableBlur(IntPtr hwnd, int width, int height, int radius) {
    if (width > 0 && height > 0) { SetWindowRgn(hwnd, CreateRoundRectRgn(0, 0, width + 1, height + 1, radius * 2, radius * 2), true); }
    ACCENTPOLICY accent = new ACCENTPOLICY(); accent.AccentState = 3; accent.AccentFlags = 0; accent.GradientColor = 0;
    int size = Marshal.SizeOf(accent); IntPtr pointer = Marshal.AllocHGlobal(size);
    try { Marshal.StructureToPtr(accent, pointer, false); COMPOSITIONDATA data = new COMPOSITIONDATA(); data.Attribute = 19; data.Data = pointer; data.SizeOfData = size; return SetWindowCompositionAttribute(hwnd, ref data) != 0; }
    finally { Marshal.FreeHGlobal(pointer); }
  }
  public static string GetForegroundTitle(out uint processId) {
    IntPtr hwnd = GetForegroundWindow(); processId = 0;
    if (hwnd == IntPtr.Zero) return "";
    GetWindowThreadProcessId(hwnd, out processId);
    System.Text.StringBuilder text = new System.Text.StringBuilder(256); GetWindowText(hwnd, text, 256); return text.ToString();
  }
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
$script:powerModuleAvailable=$false
if(Test-Path -LiteralPath (Join-Path $moduleRoot 'PowerPlan.psm1')){Import-Module (Join-Path $moduleRoot 'PowerPlan.psm1') -Force;$script:powerModuleAvailable=$true}
$script:openSettingsRequest=Join-Path $settingsDirectory 'open-settings.request'
$script:instanceLock=Enter-BakaCompanionInstance
if(-not $script:instanceLock.Acquired){
    # A second launch (Start menu "BAKA Settings", Startup shortcut) hands its request to the running desktop.
    if($OpenSettings){try{[IO.File]::WriteAllText($script:openSettingsRequest,(Get-Date).ToString('o'))}catch{}}
    # Exit code 3 tells the BAKA shell launcher that another desktop is running (not a hand-over).
    Write-BakaUiLog 'second-launch-rejected';exit 3
}

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
    $requiredThemeNames=@('BAKA Liquid Glass','BAKA Obsidian','BAKA Liquid','BAKA Minimal','BAKA Gaming')
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
    # App icons follow the theme (monochrome themes tint every icon), so a theme change redraws the dock.
    if($script:lastIconTheme -and $script:lastIconTheme -ne $script:theme.name -and $script:windows.Dock -and (Get-Command Set-BakaDockAppearance -ErrorAction SilentlyContinue)){Set-BakaDockAppearance}
    $script:lastIconTheme=$script:theme.name
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
function Update-BakaWindowBlur($Window){
    # Per-pixel transparent BAKA windows get real frosted glass: a rounded window region plus the Windows
    # blur-behind accent. No black corners, and the blur follows the BAKA corner radius.
    if(-not $Window -or $script:dwmBackdropUnsupported){return}
    try{
        $source=[System.Windows.Interop.HwndSource]::FromVisual($Window)
        if(-not $source -or -not $source.CompositionTarget){return}
        $matrix=$source.CompositionTarget.TransformToDevice
        $width=[int][math]::Ceiling($Window.ActualWidth*$matrix.M11);$height=[int][math]::Ceiling($Window.ActualHeight*$matrix.M22)
        $radius=0;if($Window.Tag -is [System.Windows.Controls.Border]){$radius=[int][math]::Round($Window.Tag.CornerRadius.TopLeft*$matrix.M11)}
        if($script:opaqueMode -or $script:theme.backdrop -eq 'Opaque'){if($width -gt 0){[void][BakaLiquidNative]::SetWindowRgn($source.Handle,[BakaLiquidNative]::CreateRoundRectRgn(0,0,$width+1,$height+1,$radius*2,$radius*2),$true)};return}
        if(-not [BakaLiquidNative]::EnableBlur($source.Handle,$width,$height,$radius)){Write-BakaUiLog ('blur-unavailable title="{0}"' -f $Window.Title)}
    }catch{Write-BakaUiLog ('blur-failed title="{0}" error="{1}"' -f $Window.Title,$_.Exception.Message)}
}
function Apply-BakaWindowBackdrop($Window){
    if($script:opaqueMode){Update-BakaWindowBlur $Window;return}
    try{
        $source=[System.Windows.Interop.HwndSource]::FromVisual($Window)
        if(-not $source){return}
        # Rounded DWM corners for the native frame; the glass itself comes from Update-BakaWindowBlur.
        $corners=2;[void][BakaLiquidNative]::DwmSetWindowAttribute($source.Handle,33,[ref]$corners,4)
        Update-BakaWindowBlur $Window
    }catch{Set-BakaOpaqueFallback $Window;Write-BakaUiLog ('backdrop-fallback title="{0}" error="{1}"' -f $Window.Title,$_.Exception.ToString())}
}
function Set-BakaWindowSurface($Window){
    if($Window.Tag -and $Window.Tag -is [System.Windows.Controls.Border]){
        $Window.Tag.Background=$script:glassBrush;$Window.Tag.BorderBrush=$script:rimBrush
        # No blur-shadow effect: on a per-pixel transparent window WPF re-renders the whole surface in
        # software for every change, which was the main source of lag. The rim and glass carry the depth.
        $Window.Tag.Effect=$null
    }
    $Window.Background=[System.Windows.Media.Brushes]::Transparent
    if($script:backdropHookedWindows.Add($Window)){$Window.add_SourceInitialized({param($sender,$eventArgs) Apply-BakaWindowBackdrop $sender})}
    else{Apply-BakaWindowBackdrop $Window}
}
Set-BakaTheme $script:config.appearance.theme
function New-BakaWindowChrome($Window,[string]$Title){
    # macOS-style title strip: close (red) and hide (amber) lights on the left, centered title, drag to move.
    $bar=[System.Windows.Controls.Grid]::new();$bar.Height=30;$bar.Margin=[System.Windows.Thickness]::new(0,-6,0,8);$bar.Background=[System.Windows.Media.Brushes]::Transparent
    $lights=[System.Windows.Controls.StackPanel]::new();$lights.Orientation=[System.Windows.Controls.Orientation]::Horizontal;$lights.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Left;$lights.VerticalAlignment=[System.Windows.VerticalAlignment]::Center
    foreach($spec in @(@{Kind='Close';Color='#FF5F57';Glyph=[string][char]0xE8BB;Tip='Close'},@{Kind='Hide';Color='#FEBC2E';Glyph=[string][char]0xE921;Tip='Hide'})){
        $button=[System.Windows.Controls.Button]::new();$button.Width=16;$button.Height=16;$button.Margin=[System.Windows.Thickness]::new(0,0,8,0);$button.Cursor=[System.Windows.Input.Cursors]::Hand
        $button.Background=New-BakaBrush $spec.Color 255;$button.BorderBrush=New-BakaBrush '#000000' 60;$button.BorderThickness=[System.Windows.Thickness]::new(0.6);$button.Template=Get-BakaPillTemplate 8
        $button.ToolTip=('{0} {1}' -f $spec.Tip,$Title);[System.Windows.Automation.AutomationProperties]::SetName($button,('{0} {1}' -f $spec.Tip,$Title))
        $mark=[System.Windows.Controls.TextBlock]::new();$mark.Text=$spec.Glyph;$mark.FontFamily=[System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets');$mark.FontSize=7;$mark.Foreground=New-BakaBrush '#4A1410' 220;$mark.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center;$mark.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$mark.Opacity=0;$button.Content=$mark
        $button.Add_MouseEnter({param($sender,$eventArgs)$sender.Content.Opacity=1});$button.Add_MouseLeave({param($sender,$eventArgs)$sender.Content.Opacity=0})
        $button.Tag=[pscustomobject]@{Window=$Window;Kind=$spec.Kind}
        $button.Add_Click({param($sender,$eventArgs)$info=$sender.Tag;if($info.Kind -eq 'Close'){$info.Window.Close()}else{Hide-BakaWindow $info.Window}})
        $lights.Children.Add($button)|Out-Null
    }
    $bar.Children.Add($lights)|Out-Null
    $caption=New-BakaText $Title 12 'Bold' $script:mutedBrush;$caption.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center;$caption.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$caption.IsHitTestVisible=$false;$caption.TextWrapping=[System.Windows.TextWrapping]::NoWrap
    $bar.Children.Add($caption)|Out-Null
    $bar.Tag=$Window
    $bar.Add_MouseLeftButtonDown({param($sender,$eventArgs)if($eventArgs.ButtonState -eq [System.Windows.Input.MouseButtonState]::Pressed -and $eventArgs.OriginalSource -isnot [System.Windows.Controls.Button]){try{$sender.Tag.DragMove()}catch{}}})
    return $bar
}
function New-BakaWindow([double]$Width,[double]$Height,[string]$Name,[bool]$Topmost=$false,[bool]$Chrome=$false){
    $window=[System.Windows.Window]::new();$window.Title=$Name;$window.Width=$Width;$window.Height=$Height
    $window.WindowStyle=[System.Windows.WindowStyle]::None;$window.ResizeMode=[System.Windows.ResizeMode]::NoResize
    # Per-pixel transparency: rounded glass corners instead of a black rectangle behind every BAKA surface.
    $window.AllowsTransparency=$true
    $window.add_SizeChanged({param($sender,$eventArgs)Update-BakaWindowBlur $sender})
    $window.ShowInTaskbar=$false;$window.Topmost=$Topmost;$window.ShowActivated=$false
    $window.Background=[System.Windows.Media.Brushes]::Transparent
    $surface=[System.Windows.Controls.Border]::new();$surface.CornerRadius=[System.Windows.CornerRadius]::new(20)
    $surface.BorderThickness=[System.Windows.Thickness]::new(1);$surface.Padding=[System.Windows.Thickness]::new(16)
    $surface.Background=$script:glassBrush;$surface.BorderBrush=$script:rimBrush
    $surface.ClipToBounds=$true
    $root=[System.Windows.Controls.Grid]::new()
    $contentHost=[System.Windows.Controls.Grid]::new();$contentHost.Background=[System.Windows.Media.Brushes]::Transparent;$contentHost.Tag='BAKAContentHost'
    $frame=[System.Windows.Controls.Grid]::new();$frame.Background=[System.Windows.Media.Brushes]::Transparent
    $chromeRow=[System.Windows.Controls.RowDefinition]::new();$chromeRow.Height=[System.Windows.GridLength]::Auto;$frame.RowDefinitions.Add($chromeRow)
    $bodyRow=[System.Windows.Controls.RowDefinition]::new();$bodyRow.Height=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star);$frame.RowDefinitions.Add($bodyRow)
    if($Chrome){
        $frame.Children.Add((New-BakaWindowChrome $window $Name))|Out-Null
        $window.add_KeyDown({param($sender,$eventArgs)if($eventArgs.Key -eq [System.Windows.Input.Key]::Escape){$sender.Close()}})
    }
    [System.Windows.Controls.Grid]::SetRow($contentHost,1);$frame.Children.Add($contentHost)|Out-Null
    $root.Children.Add($frame)|Out-Null
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
    # The pointer-following light is off: repainting a 260 px gradient on every mouse move forced a
    # full software redraw of the window and made the whole desktop feel laggy.
    $light.Visibility=[System.Windows.Visibility]::Collapsed
    $surface.CornerRadius=[System.Windows.CornerRadius]::new(26)
    $surface.Child=$root;$surface.Tag=[pscustomobject]@{ContentHost=$contentHost;Sheen=$sheen;SheenBrush=$sheenBrush;SheenTransform=$sheen.RenderTransform;Light=$light;LightTransform=$lightTransform;Root=$root;Rim=$rim;HidePending=$false}
    $window.Content=$surface;$window.Tag=$surface
    Set-BakaWindowSurface $window
    return $window
}
function Set-BakaCompactScale($Window,[double]$Scale=0.82){
    # Big BAKA windows (Arena, Files, Settings) are laid out at full size and drawn smaller, so text,
    # cards, and spacing shrink together instead of clipping.
    if(-not $Window -or -not $Window.Tag -or -not $Window.Tag.Child){return}
    $Window.Tag.Child.LayoutTransform=[System.Windows.Media.ScaleTransform]::new($Scale,$Scale)
    $Window.Width=[math]::Round($Window.Width*$Scale);$Window.Height=[math]::Round($Window.Height*$Scale)
    $Window.Tag.Padding=[System.Windows.Thickness]::new(12)
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
    if(-not $script:motionEnabled -or ($script:theme.name -ne 'BAKA Liquid' -and [string]$script:theme.style -ne 'Liquid' -and -not $script:popStyle) -or -not $Window.Tag.Tag.SheenTransform){return}
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
    $cacheKey='exe|'+$expanded+'|'+[bool](Test-BakaThemedIcons)+'|'+$script:theme.text
    if($script:iconCache.ContainsKey($cacheKey)){return $script:iconCache[$cacheKey]}
    try{
        $icon=[System.Drawing.Icon]::ExtractAssociatedIcon($expanded)
        if(-not $icon){return $null}
        $source=[System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($icon.Handle,[System.Windows.Int32Rect]::Empty,[System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
        $source.Freeze();$icon.Dispose()
        $source=ConvertTo-BakaThemedIcon $source
        $script:iconCache[$cacheKey]=$source;return $source
    }catch{$script:iconCache[$cacheKey]=$null;return $null}
}
function Get-BakaAppIconSource($App){
    # Custom icon first, then the app's real Windows icon, then the BAKA glyph as a fallback.
    $custom=[string]$App.iconPath
    if($custom){$source=Get-BakaImageSource $custom 96;if($source){return $source}}
    if([string]$App.kind -eq 'Executable'){
        $target=[Environment]::ExpandEnvironmentVariables([string]$App.target)
        if(Test-Path -LiteralPath $target -PathType Leaf){$source=Get-BakaShellIconSource $target 96;if($source){return $source};return Get-BakaExecutableIconSource $target}
    }
    if([string]$App.kind -eq 'Uri' -and [string]$App.target -like 'ms-settings:*'){return Get-BakaShellIconSource 'shell:AppsFolder\windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel' 96}
    return $null
}
function Test-BakaPinnedAppAvailable($App){
    # Pinned programs that are not installed (for example Steam before it is installed) stay out of the dock.
    if([string]$App.kind -ne 'Executable' -or [string]$App.id -eq 'baka-browser'){return $true}
    return (Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables([string]$App.target)) -PathType Leaf)
}
function New-BakaButton([string]$Label,[scriptblock]$Action,[string]$Glyph='',[string]$AccessibleLabel=$Label,[switch]$ShowIndicator,[System.Windows.Media.ImageSource]$IconSource=$null){
    $button=[System.Windows.Controls.Button]::new();$button.Padding=[System.Windows.Thickness]::new(10,8,10,8);$button.Margin=[System.Windows.Thickness]::new(3)
    $button.Background=[System.Windows.Media.Brushes]::Transparent;$button.BorderThickness=[System.Windows.Thickness]::new(0);$button.Foreground=$script:textBrush
    $button.Cursor=[System.Windows.Input.Cursors]::Hand;$button.ToolTip=$AccessibleLabel
    [System.Windows.Automation.AutomationProperties]::SetName($button,$AccessibleLabel)
    $content=[System.Windows.Controls.StackPanel]::new();$content.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center
    # macOS-style dock tile: big icon, no caption (the name is the tooltip), running dot underneath.
    $tileSize=[math]::Max(30,[math]::Min(64,([double]$script:config.dock.iconSize-6)))
    $tile=[System.Windows.Controls.Border]::new();$tile.Width=$tileSize;$tile.Height=$tileSize;$tile.Margin=[System.Windows.Thickness]::new(0,0,0,2);$tile.CornerRadius=[System.Windows.CornerRadius]::new([math]::Min(16,$tileSize*0.26));$tile.Background=New-BakaBrush $script:theme.surfaceAlt 210;$tile.BorderBrush=New-BakaBrush '#FFFFFF' 30;$tile.BorderThickness=[System.Windows.Thickness]::new(1)
    Set-BakaKeycap $tile 4
    $iconText=if([string]::IsNullOrWhiteSpace($Glyph)){$Label.Substring(0,1).ToUpperInvariant()}else{$Glyph}
    $monogram=New-BakaText $iconText ([math]::Max(16,[math]::Min(29,$tileSize*0.52))) 'Bold' $script:accentBrush
    if($Glyph){$monogram.FontFamily=[System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')}
    $monogram.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center;$monogram.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$tile.Child=$monogram
    if($IconSource){
        $iconImage=[System.Windows.Controls.Image]::new();$iconImage.Source=$IconSource;$iconImage.Stretch=[System.Windows.Media.Stretch]::Uniform
        # Real application icons stand on their own, without a tile behind them.
        $iconImage.Width=$tileSize;$iconImage.Height=$tileSize;$iconImage.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center;$iconImage.VerticalAlignment=[System.Windows.VerticalAlignment]::Center
        [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($iconImage,[System.Windows.Media.BitmapScalingMode]::HighQuality);$tile.Child=$iconImage
        $tile.Background=[System.Windows.Media.Brushes]::Transparent;$tile.BorderThickness=[System.Windows.Thickness]::new(0);$tile.Effect=$null
    }
    $content.Children.Add($tile)|Out-Null
    $labelText=New-BakaText $Label 10 'Normal' $script:mutedBrush;$labelText.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center;$labelText.Visibility=[System.Windows.Visibility]::Collapsed;$content.Children.Add($labelText)|Out-Null
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
function Protect-BakaComboWheel($Combo){
    # Scrolling over a closed drop-down must scroll the panel, not silently change the theme or setting.
    if(-not $Combo -or $Combo.Resources.Contains('BAKA.WheelGuard')){return}
    $Combo.Resources.Add('BAKA.WheelGuard',$true)
    $Combo.Add_PreviewMouseWheel({param($sender,$eventArgs)
        if($sender.IsDropDownOpen){return}
        $eventArgs.Handled=$true
        $parent=[System.Windows.Media.VisualTreeHelper]::GetParent($sender)
        while($parent -and -not ($parent -is [System.Windows.Controls.ScrollViewer])){$parent=[System.Windows.Media.VisualTreeHelper]::GetParent($parent)}
        if($parent){$parent.ScrollToVerticalOffset($parent.VerticalOffset-($eventArgs.Delta/3))}
    })
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
            Protect-BakaComboWheel $control
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
        $bounds=$screen.Bounds;$scale=Get-BakaScreenScale
        $bar=$script:windows.TopBar
        $bar.Width=$bounds.Width/$scale;$bar.Left=$bounds.Left/$scale;$bar.Top=$bounds.Top/$scale
        if($script:previewMode -or -not $bar.IsVisible){return}
        # Reserve the top edge (like the taskbar) so maximized windows start below the menu bar.
        $handle=[System.Windows.Interop.WindowInteropHelper]::new($bar).Handle
        if($handle -eq [IntPtr]::Zero){return}
        $thickness=[int][math]::Ceiling($bar.Height*$scale)
        $rect=Register-BakaAppBar -Handle $handle -Edge Top -Left $bounds.Left -Top $bounds.Top -Right $bounds.Right -Bottom $bounds.Bottom -Thickness $thickness
        $script:topBarReserved=$true
        if($rect){$bar.Top=$rect.Top/$scale}
    }catch{Write-BakaUiLog ('topbar-position-failed error="{0}" stack="{1}"' -f $_.Exception.ToString(),$_.ScriptStackTrace)}
}
function Remove-BakaDockReservation {
    if(-not $script:dockReserved -or -not $script:windows.Dock){return}
    try{Unregister-BakaAppBar -Handle ([System.Windows.Interop.WindowInteropHelper]::new($script:windows.Dock).Handle)}catch{}
    $script:dockReserved=$false
}
function Set-BakaDockPosition {
    if(-not $script:windows.Dock -or -not $script:windows.Dock.IsVisible){return}
    try{
        $screen=Get-BakaActiveScreen
        if(-not $screen){throw 'No active display is available for the BAKA dock.'}
        # Screen bounds, not the work area: the dock's own reservation would otherwise push it upward.
        $bounds=$screen.Bounds;$scale=Get-BakaScreenScale
        $left=$bounds.Left/$scale;$right=$bounds.Right/$scale;$bottom=$bounds.Bottom/$scale;$width=$right-$left
        $dock=$script:windows.Dock
        $top=$bounds.Top/$scale;$height=$bottom-$top
        # Carbon layout: dock on the left edge, vertically centered. Bottom stays available as an option.
        $edge=switch([string]$script:config.dock.alignment){'Left'{'Left'}'Right'{'Right'}default{'Bottom'}}
        if($edge -eq 'Left'){$dock.Left=$left+10;$dock.Top=$top+[math]::Max(0,($height-$dock.ActualHeight)/2)}
        elseif($edge -eq 'Right'){$dock.Left=$right-$dock.ActualWidth-10;$dock.Top=$top+[math]::Max(0,($height-$dock.ActualHeight)/2)}
        else{$dock.Left=$left+($width-$dock.ActualWidth)/2;$dock.Top=$bottom-$dock.ActualHeight-8}
        if($script:previewMode){return}
        $handle=[System.Windows.Interop.WindowInteropHelper]::new($dock).Handle
        if($handle -eq [IntPtr]::Zero){return}
        if($script:config.dock.autoHide -or $script:activeProfile -ne 'Desktop'){Remove-BakaDockReservation;return}
        # Maximized windows stop at the dock instead of sliding underneath it.
        $thickness=if($edge -eq 'Bottom'){[int][math]::Ceiling(($dock.ActualHeight+12)*$scale)}else{[int][math]::Ceiling(($dock.ActualWidth+14)*$scale)}
        $signature='{0}|{1}|{2}|{3}' -f $screen.DeviceName,$thickness,$bounds.Bottom,$edge
        if($script:dockReserved -and $script:dockReservationSignature -eq $signature){return}
        if($script:dockReserved){Remove-BakaDockReservation}
        [void](Register-BakaAppBar -Handle $handle -Edge $edge -Left $bounds.Left -Top $bounds.Top -Right $bounds.Right -Bottom $bounds.Bottom -Thickness $thickness)
        $script:dockReserved=$true;$script:dockReservationSignature=$signature
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
        if(-not (Test-Path -LiteralPath $target -PathType Leaf) -and [string]$App.id -eq 'baka-browser'){Start-BakaBrowserRepair -Interactive;return}
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
        $icon=if($app.Path){$shellIcon=Get-BakaShellIconSource $app.Path 96;if($shellIcon){$shellIcon}else{Get-BakaExecutableIconSource $app.Path}}else{$null}
        $button=New-BakaButton $label {param($sender,$eventArgs)$info=$sender.Tag;$process=Get-Process -Id $info.ProcessId -ErrorAction SilentlyContinue;if(-not $process -or $process.MainWindowHandle -eq [IntPtr]::Zero){$process=Get-Process -Name $info.ProcessName -ErrorAction SilentlyContinue|Where-Object {$_.MainWindowHandle -ne [IntPtr]::Zero}|Select-Object -First 1};if($process){Switch-BakaWindowFocus $process.MainWindowHandle}} '' ('Switch to {0}' -f $app.Title) -ShowIndicator -IconSource $icon
        $button.Tag=$app;$button.ToolTip=$app.Title
        $button.Width=[double]$script:config.dock.iconSize+15;$button.Height=[double]$script:config.dock.iconSize+8;$button.Margin=if($script:dockVertical){[System.Windows.Thickness]::new(0,[double]$script:config.dock.spacing/2,0,[double]$script:config.dock.spacing/2)}else{[System.Windows.Thickness]::new([double]$script:config.dock.spacing/2,0,[double]$script:config.dock.spacing/2,0)}
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
            # Auto-hide gives the screen space back; hiding the window removes the taskbar completely.
            [void](Set-BakaTaskbarVisibility -Visible $false -Confirm:$false)
            Write-BakaUiLog 'taskbar-hidden'
        }else{Restore-BakaTaskbarMode}
    }catch{Write-BakaUiLog ('taskbar-mode-failed error="{0}"' -f $_.Exception.Message)}
}
function Restore-BakaTaskbarMode {
    if($script:previewMode){return}
    try{[void](Set-BakaTaskbarVisibility -Visible $true -Confirm:$false)}catch{}
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
    foreach($candidate in @((Join-Path $dataRoot 'Assets\BAKA-Stealth-4K.png'),(Join-Path $dataRoot 'Assets\Wallpapers\BAKA-Stealth-4K.png'),(Join-Path $dataRoot 'Assets\BAKA-BlackGlass-4K.png'),(Join-Path $dataRoot 'Assets\Wallpapers\BAKA-BlackGlass-4K.png'),(Join-Path $dataRoot 'Assets\BAKA-Liquid-Ribbon.png'),(Join-Path $dataRoot 'Assets\Wallpapers\BAKA-Liquid-Ribbon.png'))){if(Test-Path -LiteralPath $candidate -PathType Leaf){return $candidate}}
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
    if($script:shellMode){try{Update-BakaDesktopBackground}catch{Write-BakaUiLog ('desktop-background-failed error="{0}"' -f $_.Exception.Message)}}
    $script:wallpaperDirty=$false
}

function Update-BakaProfileStatus {
    $mode=if($script:manualOverride){'MANUAL'}elseif($script:autoGame -and $script:detectedGame){'AUTO · '+$script:detectedGame.ToUpperInvariant()}else{'AUTO'}
    $power=if($script:powerPlanLabel){$script:powerPlanLabel}else{'POWER'}
    $label='{0}  ·  {1}  ·  {2}' -f $mode,$script:activeProfile.ToUpperInvariant(),$power
    foreach($key in @('DockStatus','QuickStatus','BarStatus')){if($script:windows[$key]){$script:windows[$key].Text=$label}}
    if($script:windows.BarProfile -and $script:config.topBar.showProfile){$script:windows.BarProfile.Text=$script:activeProfile.ToUpperInvariant()}
    if($script:windows.DashNavStatus){$script:windows.DashNavStatus.Text=('{0}  /  {1}' -f $mode,$script:activeProfile.ToUpperInvariant())}
    if($script:windows.DashActiveProfile){$script:windows.DashActiveProfile.Text=$script:activeProfile.ToUpperInvariant()}
    Update-BakaArenaProfileTiles
}
if(-not ('BakaMemory' -as [type])){
    Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class BakaMemory{[DllImport("psapi.dll")] public static extern bool EmptyWorkingSet(IntPtr process);}' -ErrorAction SilentlyContinue
}
function Optimize-BakaFootprint([string]$Reason='idle'){
    # Gives memory back to Windows: full GC, then the working set is trimmed so pages the desktop is
    # not using right now go to the standby list (they are read back only if needed).
    try{
        [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
        $self=[Diagnostics.Process]::GetCurrentProcess()
        # Only BAKA's own process is trimmed, so preview runs do it too and measure the real behaviour.
        [void][BakaMemory]::EmptyWorkingSet($self.Handle)
        Write-BakaUiLog ('footprint-trimmed reason={0} workingSetMiB={1:N0}' -f $Reason,([Diagnostics.Process]::GetCurrentProcess().WorkingSet64/1MB))
    }catch{}
}
function Set-BakaGamePriority([bool]$Gaming){
    # While a game runs, the desktop drops to below-normal priority so it never takes CPU time from it.
    if($script:previewMode){return}
    try{$self=[Diagnostics.Process]::GetCurrentProcess();$self.PriorityClass=if($Gaming){[Diagnostics.ProcessPriorityClass]::BelowNormal}else{[Diagnostics.ProcessPriorityClass]::Normal}}catch{}
}
function Switch-BakaProfilePowerPlan([string]$Profile){
    # Gaming and Benchmark run on the BAKA Gaming plan; going back to Desktop restores the plan the user had.
    if($script:previewMode -or -not $script:powerModuleAvailable){return}
    try{
        $bakaGuid=Get-BakaPowerPlanGuid
        $active=Get-BakaActivePowerScheme
        if($Profile -ne 'Desktop'){
            if($active -and $active.Guid -ne $bakaGuid -and @(Get-BakaPowerSchemes|Where-Object {$_.Guid -eq $bakaGuid}).Count){$script:powerPlanBeforeGame=$active.Guid;[void](Set-BakaActivePowerScheme -Guid $bakaGuid -Confirm:$false);Write-BakaUiLog 'power-plan-gaming'}
        }elseif($script:powerPlanBeforeGame){[void](Set-BakaActivePowerScheme -Guid $script:powerPlanBeforeGame -Confirm:$false);$script:powerPlanBeforeGame=$null;Write-BakaUiLog 'power-plan-restored'}
        Update-BakaPowerPlanState
    }catch{Write-BakaUiLog ('power-plan-switch-failed error="{0}"' -f $_.Exception.Message)}
}
function Set-BakaUiProfile([string]$Profile,[string]$Reason='Manual'){
    $previous=$script:activeProfile
    $previousOverride=$script:manualOverride
    try {
        $result=Set-BakaCompanionProfile -Profile $Profile
        $script:activeProfile=$Profile
        Switch-BakaProfilePowerPlan $Profile
        Set-BakaGamePriority ($Profile -ne 'Desktop')
        if($Profile -ne 'Desktop'){Optimize-BakaFootprint 'game-start'}
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
    if($script:windows.DashTelemetry){$script:windows.DashTelemetry.Text=('Live Windows numbers  ·  updated {0}' -f (Get-Date -Format 'HH:mm:ss'))}
}
function Show-BakaDashboard {
    # Built on first use: Arena is the heaviest surface and most sessions never open it.
    if(-not $script:windows.Dashboard){$script:windows.Dashboard=New-BakaDashboard}
    if(-not $script:windows.Dashboard){return}
    $area=(Get-BakaActiveScreen).WorkingArea;$window=$script:windows.Dashboard
    $window.Left=$area.Left+([math]::Max(20,($area.Width-$window.Width)/2));$window.Top=$area.Top+([math]::Max(24,($area.Height-$window.Height)/2-22))
    Show-BakaWindow $window -Activate;Update-BakaWidgetPolling;Start-BakaMetricRead
}
function New-BakaArenaTile([string]$Label,[string]$Copy,[string]$Glyph,[scriptblock]$Action){
    # One compact tile: mono line icon, a title and one line of detail. The whole tile is the button.
    $button=[System.Windows.Controls.Button]::new();$button.Template=Get-BakaPillTemplate 12;$button.Cursor=[System.Windows.Input.Cursors]::Hand
    $button.Padding=[System.Windows.Thickness]::new(12,9,12,9);$button.Margin=[System.Windows.Thickness]::new(4);$button.HorizontalContentAlignment=[System.Windows.HorizontalAlignment]::Left
    $button.Background=New-BakaBrush $script:theme.surfaceAlt 200;$button.BorderBrush=$script:borderBrush;$button.BorderThickness=[System.Windows.Thickness]::new(1);$button.Foreground=$script:textBrush
    [System.Windows.Automation.AutomationProperties]::SetName($button,$Label)
    $row=[System.Windows.Controls.StackPanel]::new();$row.Orientation=[System.Windows.Controls.Orientation]::Horizontal
    $icon=New-BakaText $Glyph 15 'Normal' $script:textBrush;$icon.FontFamily=[System.Windows.Media.FontFamily]::new('Segoe Fluent Icons, Segoe MDL2 Assets');$icon.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$icon.Margin=[System.Windows.Thickness]::new(0,0,10,0);$row.Children.Add($icon)|Out-Null
    $text=[System.Windows.Controls.StackPanel]::new();$text.Children.Add((New-BakaText $Label 11 'Bold'))|Out-Null
    if($Copy){$detail=New-BakaText $Copy 9.5 'Normal' $script:mutedBrush;$detail.TextTrimming=[System.Windows.TextTrimming]::CharacterEllipsis;$text.Children.Add($detail)|Out-Null}
    $row.Children.Add($text)|Out-Null;$button.Content=$row
    $button.Add_MouseEnter({param($sender,$eventArgs)if($sender.Tag -ne 'Active'){$sender.Background=New-BakaBrush $script:theme.surfaceAlt 255}})
    $button.Add_MouseLeave({param($sender,$eventArgs)if($sender.Tag -ne 'Active'){$sender.Background=New-BakaBrush $script:theme.surfaceAlt 200}})
    [void]$button.Add_Click($Action);return $button
}
function Update-BakaArenaProfileTiles {
    # The active profile's tile is outlined in the accent colour; the others stay plain.
    if(-not $script:arenaProfileTiles){return}
    foreach($pair in $script:arenaProfileTiles.GetEnumerator()){
        $active=$pair.Key -eq $script:activeProfile;$tile=$pair.Value
        $tile.Tag=if($active){'Active'}else{$null}
        $tile.BorderBrush=if($active){$script:accentBrush}else{$script:borderBrush}
        $tile.BorderThickness=[System.Windows.Thickness]::new($(if($active){1.5}else{1}))
        $tile.Background=New-BakaBrush $script:theme.surfaceAlt $(if($active){255}else{200})
    }
}
function New-BakaArenaSection([string]$Text){
    $label=New-BakaText $Text 9 'Bold' $script:mutedBrush;$label.Margin=[System.Windows.Thickness]::new(8,10,0,2);return $label
}
function New-BakaDashboard {
    # Compact Arena at its real size (no scale transform): header, profile switch, live numbers, quick
    # actions, and what Gaming mode changes. About a third of the old window's area.
    $window=New-BakaWindow 720 470 'BAKA Arena' $false $true;$window.ShowInTaskbar=$false;$window.Topmost=[bool]$ArenaSmoke
    $root=[System.Windows.Controls.StackPanel]::new();$root.Margin=[System.Windows.Thickness]::new(8,0,8,4)
    $nav=[System.Windows.Controls.Grid]::new();$nav.Margin=[System.Windows.Thickness]::new(4,0,4,2)
    foreach($w in @('Auto','*','Auto')){$col=[System.Windows.Controls.ColumnDefinition]::new();$col.Width=if($w -eq '*'){[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)}else{[System.Windows.GridLength]::Auto};$nav.ColumnDefinitions.Add($col)}
    $brand=[System.Windows.Controls.StackPanel]::new();$brand.Orientation=[System.Windows.Controls.Orientation]::Horizontal
    $brand.Children.Add((New-BakaText 'BAKA' 15 'Bold'))|Out-Null;$name=New-BakaText '  Arena' 14 'Normal' $script:mutedBrush;$brand.Children.Add($name)|Out-Null;$nav.Children.Add($brand)|Out-Null
    $chip=[System.Windows.Controls.Border]::new();$chip.CornerRadius=[System.Windows.CornerRadius]::new(10);$chip.Padding=[System.Windows.Thickness]::new(10,3,10,3);$chip.Background=New-BakaBrush $script:theme.surfaceAlt 220;$chip.BorderBrush=$script:borderBrush;$chip.BorderThickness=[System.Windows.Thickness]::new(1);$chip.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Right;$chip.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$chip.Margin=[System.Windows.Thickness]::new(0,0,12,0)
    $navStatus=New-BakaText 'AUTO  /  DESKTOP' 9 'Bold' $script:mutedBrush;$navStatus.Name='DashNavStatus';$script:windows.DashNavStatus=$navStatus;$chip.Child=$navStatus;[System.Windows.Controls.Grid]::SetColumn($chip,1);$nav.Children.Add($chip)|Out-Null
    $clock=New-BakaText (Get-Date -Format 'HH:mm') 13 'Bold' $script:textBrush;$clock.Name='DashClock';$script:windows.DashClock=$clock;$clock.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;[System.Windows.Controls.Grid]::SetColumn($clock,2);$nav.Children.Add($clock)|Out-Null
    $root.Children.Add($nav)|Out-Null

    $root.Children.Add((New-BakaArenaSection 'PROFILE'))|Out-Null
    $profiles=[System.Windows.Controls.Primitives.UniformGrid]::new();$profiles.Columns=3;$script:arenaProfileTiles=@{}
    foreach($data in @(
        [pscustomobject]@{Name='Desktop';Label='Desktop';Glyph=[string][char]0xE80F;Copy='Widgets and motion on'},
        [pscustomobject]@{Name='CompetitiveGaming';Label='Gaming';Glyph=[string][char]0xE7FC;Copy='Game Mode, low overhead'},
        [pscustomobject]@{Name='Benchmark';Label='Benchmark';Glyph=[string][char]0xE9D2;Copy='Clean, repeatable runs'})){
        $profileName=$data.Name
        $tile=New-BakaArenaTile $data.Label $data.Copy $data.Glyph ([scriptblock]::Create("try{[void](Set-BakaUiProfile '$profileName' 'Manual');Update-BakaArenaProfileTiles}catch{[System.Windows.Forms.MessageBox]::Show(`$_.Exception.Message,'BAKA profile',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)|Out-Null}"))
        $script:arenaProfileTiles[$data.Name]=$tile;$profiles.Children.Add($tile)|Out-Null
    }
    $root.Children.Add($profiles)|Out-Null

    $root.Children.Add((New-BakaArenaSection 'SYSTEM'))|Out-Null
    $metrics=[System.Windows.Controls.Primitives.UniformGrid]::new();$metrics.Columns=4
    foreach($item in @(
        [pscustomobject]@{Name='DashCpu';Label='CPU';Glyph=[string][char]0xE9D9;Value='--'},
        [pscustomobject]@{Name='DashMemory';Label='Memory in use';Glyph=[string][char]0xE964;Value='--'},
        [pscustomobject]@{Name='DashGpu';Label='GPU engine';Glyph=[string][char]0xE7F4;Value='N/A'},
        [pscustomobject]@{Name='DashDisk';Label='Free on C:';Glyph=[string][char]0xEDA2;Value='--'})){
        $card=[System.Windows.Controls.Border]::new();$card.CornerRadius=[System.Windows.CornerRadius]::new(12);$card.Margin=[System.Windows.Thickness]::new(4);$card.Padding=[System.Windows.Thickness]::new(12,8,12,9);$card.Background=New-BakaBrush $script:theme.surfaceAlt 200;$card.BorderBrush=$script:borderBrush;$card.BorderThickness=[System.Windows.Thickness]::new(1)
        $stack=[System.Windows.Controls.StackPanel]::new();$head=[System.Windows.Controls.StackPanel]::new();$head.Orientation=[System.Windows.Controls.Orientation]::Horizontal
        $g=New-BakaText $item.Glyph 11 'Normal' $script:mutedBrush;$g.FontFamily=[System.Windows.Media.FontFamily]::new('Segoe Fluent Icons, Segoe MDL2 Assets');$g.Margin=[System.Windows.Thickness]::new(0,1,6,0);$head.Children.Add($g)|Out-Null;$head.Children.Add((New-BakaText $item.Label 9.5 'Normal' $script:mutedBrush))|Out-Null;$stack.Children.Add($head)|Out-Null
        $value=New-BakaText $item.Value 18 'Bold' $script:textBrush;$value.Name=$item.Name;$script:windows[$item.Name]=$value;$stack.Children.Add($value)|Out-Null;$card.Child=$stack;$metrics.Children.Add($card)|Out-Null
    }
    $root.Children.Add($metrics)|Out-Null

    $lower=[System.Windows.Controls.Grid]::new();$c1=[System.Windows.Controls.ColumnDefinition]::new();$c1.Width=[System.Windows.GridLength]::new(1.15,[System.Windows.GridUnitType]::Star);$c2=[System.Windows.Controls.ColumnDefinition]::new();$c2.Width=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star);$lower.ColumnDefinitions.Add($c1);$lower.ColumnDefinitions.Add($c2)
    $actionsStack=[System.Windows.Controls.StackPanel]::new();$actionsStack.Children.Add((New-BakaArenaSection 'QUICK ACTIONS'))|Out-Null
    $actions=[System.Windows.Controls.Primitives.UniformGrid]::new();$actions.Columns=2
    $actions.Children.Add((New-BakaArenaTile 'Control Center' '' ([string][char]0xE9E9) {Show-BakaQuickPanel}))|Out-Null
    $actions.Children.Add((New-BakaArenaTile 'Files' '' ([string][char]0xE8B7) {Show-BakaFiles}))|Out-Null
    $actions.Children.Add((New-BakaArenaTile 'All apps' '' ([string][char]0xE8A9) {Show-BakaLaunchpad}))|Out-Null
    $actions.Children.Add((New-BakaArenaTile 'Customize' '' ([string][char]0xE771) {Show-BakaSettings}))|Out-Null
    $actionsStack.Children.Add($actions)|Out-Null
    $auto=New-BakaArenaTile 'Detect games automatically' 'Switches to Gaming when a game starts' ([string][char]0xE768) {$script:manualOverride=$null;if($script:profileTimer -and -not $script:profileTimer.IsEnabled){$script:profileTimer.Start()};Update-BakaProfileStatus;Update-BakaArenaProfileTiles}
    $actionsStack.Children.Add($auto)|Out-Null
    $lower.Children.Add($actionsStack)|Out-Null
    $ledgerStack=[System.Windows.Controls.StackPanel]::new();$ledgerStack.Children.Add((New-BakaArenaSection 'GAMING CHANGES'))|Out-Null
    $ledger=[System.Windows.Controls.Border]::new();$ledger.CornerRadius=[System.Windows.CornerRadius]::new(12);$ledger.Margin=[System.Windows.Thickness]::new(4);$ledger.Padding=[System.Windows.Thickness]::new(12,8,12,8);$ledger.Background=New-BakaBrush $script:theme.surfaceAlt 200;$ledger.BorderBrush=$script:borderBrush;$ledger.BorderThickness=[System.Windows.Thickness]::new(1)
    $lines=[System.Windows.Controls.StackPanel]::new()
    foreach($line in @('Windows Game Mode on','Background apps paused','Game DVR capture off','BAKA Gaming power plan','Security and recovery untouched')){
        $r=[System.Windows.Controls.StackPanel]::new();$r.Orientation=[System.Windows.Controls.Orientation]::Horizontal;$r.Margin=[System.Windows.Thickness]::new(0,3,0,3)
        $check=New-BakaText ([string][char]0xE73E) 10 'Normal' $script:textBrush;$check.FontFamily=[System.Windows.Media.FontFamily]::new('Segoe Fluent Icons, Segoe MDL2 Assets');$check.Margin=[System.Windows.Thickness]::new(0,1,8,0);$r.Children.Add($check)|Out-Null
        $r.Children.Add((New-BakaText $line 10 'Normal' $script:textBrush))|Out-Null;$lines.Children.Add($r)|Out-Null
    }
    $ledger.Child=$lines;$ledgerStack.Children.Add($ledger)|Out-Null;[System.Windows.Controls.Grid]::SetColumn($ledgerStack,1);$lower.Children.Add($ledgerStack)|Out-Null
    $root.Children.Add($lower)|Out-Null
    $telemetry=New-BakaText 'Live Windows numbers  ·  waiting' 9 'Normal' $script:mutedBrush;$telemetry.Name='DashTelemetry';$script:windows.DashTelemetry=$telemetry;$telemetry.Margin=[System.Windows.Thickness]::new(8,6,0,0);$root.Children.Add($telemetry)|Out-Null
    Set-BakaWindowContent $window $root;$script:windows.Dashboard=$window;Update-BakaArenaProfileTiles
    $window.add_Closing({param($sender,$eventArgs)if(-not $script:allowShutdown){$eventArgs.Cancel=$true;$sender.Hide()}});return $window
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
    $window=New-BakaWindow 1280 790 'BAKA Files' $false $true;$window.ShowInTaskbar=$true;$window.Topmost=[bool]$FileSmoke
    $layout=[System.Windows.Controls.Grid]::new();$layout.Margin=[System.Windows.Thickness]::new(4)
    $toolbarRow=[System.Windows.Controls.RowDefinition]::new();$toolbarRow.Height=[System.Windows.GridLength]::new(68,[System.Windows.GridUnitType]::Pixel);$layout.RowDefinitions.Add($toolbarRow)
    $bodyRow=[System.Windows.Controls.RowDefinition]::new();$bodyRow.Height=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star);$layout.RowDefinitions.Add($bodyRow)
    $statusRow=[System.Windows.Controls.RowDefinition]::new();$statusRow.Height=[System.Windows.GridLength]::new(30,[System.Windows.GridUnitType]::Pixel);$layout.RowDefinitions.Add($statusRow)
    $toolbar=[System.Windows.Controls.Grid]::new();$toolbar.Margin=[System.Windows.Thickness]::new(4,0,4,10)
    foreach($width in @([System.Windows.GridLength]::new(48,[System.Windows.GridUnitType]::Pixel),[System.Windows.GridLength]::new(48,[System.Windows.GridUnitType]::Pixel),[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star),[System.Windows.GridLength]::new(52,[System.Windows.GridUnitType]::Pixel),[System.Windows.GridLength]::new(230,[System.Windows.GridUnitType]::Pixel),[System.Windows.GridLength]::new(128,[System.Windows.GridUnitType]::Pixel))){$column=[System.Windows.Controls.ColumnDefinition]::new();$column.Width=$width;$toolbar.ColumnDefinitions.Add($column)}
    $back=New-BakaArenaButton '' {if($script:fileExplorerHistory.Count -gt 0){Navigate-BakaFiles $script:fileExplorerHistory.Pop()}} ([string][char]0xE72B);$back.ToolTip='Back';$back.Margin=[System.Windows.Thickness]::new(2);[System.Windows.Controls.Grid]::SetColumn($back,0);$toolbar.Children.Add($back)|Out-Null
    $up=New-BakaArenaButton '' {try{ $parent=[IO.Directory]::GetParent($script:fileExplorerCurrent);if($parent){Navigate-BakaFiles $parent.FullName -Remember}}catch{}} ([string][char]0xE74A);$up.ToolTip='Up';$up.Margin=[System.Windows.Thickness]::new(2);[System.Windows.Controls.Grid]::SetColumn($up,1);$toolbar.Children.Add($up)|Out-Null
    $address=[System.Windows.Controls.TextBox]::new();$address.Text=$script:fileExplorerCurrent;$address.Padding=[System.Windows.Thickness]::new(12,8,12,8);$address.FontSize=12;$address.Background=New-BakaBrush $script:theme.surfaceAlt 210;$address.Foreground=$script:textBrush;$address.BorderBrush=$script:borderBrush;$address.VerticalContentAlignment=[System.Windows.VerticalAlignment]::Center;$script:fileExplorerAddress=$address;[System.Windows.Controls.Grid]::SetColumn($address,2);$toolbar.Children.Add($address)|Out-Null
    $go=New-BakaArenaButton '' {Navigate-BakaFiles ([string]$script:fileExplorerAddress.Text)} ([string][char]0xE72A);$go.ToolTip='Go';[System.Windows.Automation.AutomationProperties]::SetName($go,'Go');$go.Margin=[System.Windows.Thickness]::new(4,2,4,2);[System.Windows.Controls.Grid]::SetColumn($go,3);$toolbar.Children.Add($go)|Out-Null
    $search=[System.Windows.Controls.TextBox]::new();$search.Text='Search this folder';$search.Padding=[System.Windows.Thickness]::new(12,8,12,8);$search.FontSize=11;$search.Background=New-BakaBrush $script:theme.surfaceAlt 210;$search.Foreground=$script:mutedBrush;$search.BorderBrush=$script:borderBrush;$search.VerticalContentAlignment=[System.Windows.VerticalAlignment]::Center;$search.Tag='Placeholder';$script:fileExplorerSearch=$search;$search.Add_GotFocus({param($sender,$eventArgs)if($sender.Tag -eq 'Placeholder'){$sender.Text='';$sender.Tag=''}});$search.Add_LostFocus({param($sender,$eventArgs)if([string]::IsNullOrWhiteSpace($sender.Text)){$sender.Text='Search this folder';$sender.Tag='Placeholder'}});$search.Add_KeyDown({param($sender,$eventArgs)if($eventArgs.Key -eq [System.Windows.Input.Key]::Enter){$query=if($sender.Tag -eq 'Placeholder'){''}else{[string]$sender.Text};Load-BakaFilesDirectory $script:fileExplorerCurrent $query}});[System.Windows.Controls.Grid]::SetColumn($search,4);$toolbar.Children.Add($search)|Out-Null
    $explorerButton=New-BakaArenaButton 'Explorer' {try{Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList ('"{0}"' -f $script:fileExplorerCurrent)|Out-Null}catch{}} ([string][char]0xE8DA);$explorerButton.ToolTip='Open this folder in Windows File Explorer';$explorerButton.Margin=[System.Windows.Thickness]::new(4,2,0,2);[System.Windows.Controls.Grid]::SetColumn($explorerButton,5);$toolbar.Children.Add($explorerButton)|Out-Null;$layout.Children.Add($toolbar)|Out-Null
    # Sidebar column sizes to the sidebar; with a default (star) column it floated in the middle of the window.
    $body=[System.Windows.Controls.Grid]::new();$sideColumn=[System.Windows.Controls.ColumnDefinition]::new();$sideColumn.Width=[System.Windows.GridLength]::Auto;$body.ColumnDefinitions.Add($sideColumn);$mainColumn=[System.Windows.Controls.ColumnDefinition]::new();$mainColumn.Width=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star);$body.ColumnDefinitions.Add($mainColumn);[System.Windows.Controls.Grid]::SetRow($body,1);$layout.Children.Add($body)|Out-Null
    $sidebar=[System.Windows.Controls.Border]::new();$sidebar.Width=210;$sidebar.Margin=[System.Windows.Thickness]::new(4,0,8,0);$sidebar.Padding=[System.Windows.Thickness]::new(8);$sidebar.Background=New-BakaBrush $script:theme.surface 178;$sidebar.BorderBrush=$script:borderBrush;$sidebar.BorderThickness=[System.Windows.Thickness]::new(1);$sideStack=[System.Windows.Controls.StackPanel]::new();$sideStack.Children.Add((New-BakaText 'BAKA FILES' 17 'Bold' $script:accentBrush))|Out-Null;$sideStack.Children.Add((New-BakaText 'Your Windows workspace' 10 'Normal' $script:mutedBrush))|Out-Null
    foreach($entry in @([pscustomobject]@{Name='Home';Glyph=[string][char]0xE80F},[pscustomobject]@{Name='Desktop';Glyph=[string][char]0xE7F4},[pscustomobject]@{Name='Downloads';Glyph=[string][char]0xE896},[pscustomobject]@{Name='Documents';Glyph=[string][char]0xE8A5},[pscustomobject]@{Name='Pictures';Glyph=[string][char]0xEB9F})){$button=New-BakaArenaButton $entry.Name {param($sender,$eventArgs)$path=Get-BakaKnownFolderPath ([string]$sender.Tag);if($path){Navigate-BakaFiles $path -Remember}} $entry.Glyph;$button.Tag=$entry.Name;$button.HorizontalContentAlignment=[System.Windows.HorizontalAlignment]::Left;$button.Margin=[System.Windows.Thickness]::new(0,5,0,0);$sideStack.Children.Add($button)|Out-Null}
    $sideStack.Children.Add((New-BakaText 'DRIVES' 10 'Bold' $script:mutedBrush))|Out-Null
    foreach($drive in @(Get-PSDrive -PSProvider FileSystem|Where-Object {$_.Root}|Sort-Object Name)){$button=New-BakaArenaButton ('{0}  {1}' -f $drive.Name,$drive.Root) {param($sender,$eventArgs)Navigate-BakaFiles ([string]$sender.Tag) -Remember} ([string][char]0xE7F4);$button.Tag=$drive.Root;$button.HorizontalContentAlignment=[System.Windows.HorizontalAlignment]::Left;$button.Margin=[System.Windows.Thickness]::new(0,5,0,0);$sideStack.Children.Add($button)|Out-Null}
    $sidebar.Child=$sideStack;[System.Windows.Controls.Grid]::SetColumn($sidebar,0);$body.Children.Add($sidebar)|Out-Null
    $main=[System.Windows.Controls.Grid]::new();$main.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new());$main.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new());$main.RowDefinitions[0].Height=[System.Windows.GridLength]::new(52,[System.Windows.GridUnitType]::Pixel);$main.RowDefinitions[1].Height=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star);[System.Windows.Controls.Grid]::SetColumn($main,1);$body.Children.Add($main)|Out-Null
    $heading=[System.Windows.Controls.StackPanel]::new();$heading.Orientation=[System.Windows.Controls.Orientation]::Horizontal;$heading.Children.Add((New-BakaText 'WORKSPACE' 13 'Bold'))|Out-Null;$heading.Children.Add((New-BakaText '  /  FILES' 13 'Bold' $script:accentBrush))|Out-Null;[System.Windows.Controls.Grid]::SetRow($heading,0);$main.Children.Add($heading)|Out-Null
    $list=[System.Windows.Controls.ListView]::new();$list.Background=New-BakaBrush $script:theme.surface 138;$list.Foreground=$script:textBrush;$list.BorderBrush=$script:borderBrush;$list.BorderThickness=[System.Windows.Thickness]::new(1);$list.Padding=[System.Windows.Thickness]::new(8);$view=[System.Windows.Controls.GridView]::new()
    # Column headers in the theme colours (the stock header is a white Win32-style bar).
    $headerStyle=[System.Windows.Style]::new([System.Windows.Controls.GridViewColumnHeader])
    foreach($setter in @(@([System.Windows.Controls.Control]::BackgroundProperty,(New-BakaBrush $script:theme.surface 255)),@([System.Windows.Controls.Control]::ForegroundProperty,$script:mutedBrush),@([System.Windows.Controls.Control]::BorderBrushProperty,$script:borderBrush),@([System.Windows.Controls.Control]::BorderThicknessProperty,[System.Windows.Thickness]::new(0,0,0,1)),@([System.Windows.Controls.Control]::PaddingProperty,[System.Windows.Thickness]::new(8,5,8,5)),@([System.Windows.Controls.Control]::HorizontalContentAlignmentProperty,[System.Windows.HorizontalAlignment]::Left),@([System.Windows.Controls.Control]::FontSizeProperty,[double]10))){$headerStyle.Setters.Add([System.Windows.Setter]::new($setter[0],$setter[1]))}
    $headerTemplate=[System.Windows.Markup.XamlReader]::Parse('<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="GridViewColumnHeader"><Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"/></Border></ControlTemplate>')
    $headerStyle.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.Control]::TemplateProperty,$headerTemplate))
    $view.ColumnHeaderContainerStyle=$headerStyle
    foreach($column in @([pscustomobject]@{Header='NAME';Path='Name';Width=390},[pscustomobject]@{Header='TYPE';Path='Type';Width=120},[pscustomobject]@{Header='MODIFIED';Path='Modified';Width=180},[pscustomobject]@{Header='SIZE';Path='Size';Width=110})){$gridColumn=[System.Windows.Controls.GridViewColumn]::new();$gridColumn.Header=$column.Header;$gridColumn.Width=$column.Width;$gridColumn.DisplayMemberBinding=[System.Windows.Data.Binding]::new($column.Path);$view.Columns.Add($gridColumn)|Out-Null};$list.View=$view;$script:fileExplorerList=$list;$list.Add_MouseDoubleClick({param($sender,$eventArgs)Open-BakaFileSelection $sender.SelectedItem});[System.Windows.Controls.Grid]::SetRow($list,1);$main.Children.Add($list)|Out-Null
    $status=New-BakaText 'Loading BAKA Files…' 10 'Normal' $script:mutedBrush;$status.Margin=[System.Windows.Thickness]::new(14,4,0,0);$script:fileExplorerStatus=$status;[System.Windows.Controls.Grid]::SetRow($status,2);$layout.RowDefinitions[2].Height=[System.Windows.GridLength]::new(30,[System.Windows.GridUnitType]::Pixel);$layout.Children.Add($status)|Out-Null
    Set-BakaSettingsControlTheme $layout;Set-BakaWindowContent $window $layout;Set-BakaCompactScale $window 0.8;$script:windows.Files=$window;$window.add_Closing({param($sender,$eventArgs)if(-not $script:allowShutdown){$eventArgs.Cancel=$true;$sender.Hide()}});return $window
}

function New-BakaDock {
    $window=New-BakaWindow 820 82 'BAKA Arena Dock' $true
    $window.Tag.Padding=[System.Windows.Thickness]::new(10,5,10,3);$window.Tag.CornerRadius=[System.Windows.CornerRadius]::new(22)
    if($window.Tag.Tag.Rim){$window.Tag.Tag.Rim.CornerRadius=[System.Windows.CornerRadius]::new(21);$window.Tag.Tag.Rim.Margin=[System.Windows.Thickness]::new(-9,-4,-9,-2)}
    if(([string]$script:config.dock.alignment) -notin @('Left','Right')){$window.MinWidth=380;$window.MaxWidth=[math]::Max(760,[System.Windows.SystemParameters]::WorkArea.Width-36)};$window.add_KeyDown({param($sender,$eventArgs) if($eventArgs.Key -eq [System.Windows.Input.Key]::Escape){$sender.Hide()}})
    $script:dockVertical=([string]$script:config.dock.alignment -in @('Left','Right'))
    $dockOrientation=if($script:dockVertical){[System.Windows.Controls.Orientation]::Vertical}else{[System.Windows.Controls.Orientation]::Horizontal}
    $row=[System.Windows.Controls.StackPanel]::new();$row.Orientation=$dockOrientation;$row.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$row.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center
    $brand=[System.Windows.Controls.StackPanel]::new();$brand.Width=154;$brand.Margin=[System.Windows.Thickness]::new(8,0,9,0)
    $brand.Children.Add((New-BakaText 'BAKA  /  ARENA' 17 'Bold'))|Out-Null
    $status=New-BakaText 'DESKTOP  ·  BALANCED' 9 'Normal' $script:accentBrush;$status.Name='DockStatus';$script:windows.DockStatus=$status;$brand.Children.Add($status)|Out-Null
    $start=New-BakaButton 'Apps' {try{Show-BakaLaunchpad}catch{Write-BakaUiLog ('launchpad-failed error="{0}"' -f $_.Exception.Message)}} ([string][char]0xE71D) 'All apps (Launchpad). The Windows key still opens Start.'
    $start.Width=[double]$script:config.dock.iconSize+15;$start.Height=[double]$script:config.dock.iconSize+8
    $start.Visibility=if([bool]$script:config.taskbar.showStartButton){[System.Windows.Visibility]::Visible}else{[System.Windows.Visibility]::Collapsed}
    $script:windows.DockStartButton=$start;$row.Children.Add($start)|Out-Null
    $row.Children.Add($brand)|Out-Null
    $separator=[System.Windows.Controls.Border]::new();if($script:dockVertical){$separator.Height=1;$separator.Width=40}else{$separator.Width=1;$separator.Height=48};$separator.Background=$script:borderBrush;$separator.Margin=if($script:dockVertical){[System.Windows.Thickness]::new(0,6,0,6)}else{[System.Windows.Thickness]::new(4,0,8,0)};$row.Children.Add($separator)|Out-Null
    # Pop Glass keeps the dock clean like macOS: icons only, no wordmark.
    $brand.Visibility=[System.Windows.Visibility]::Collapsed
    $appPanel=[System.Windows.Controls.StackPanel]::new();$appPanel.Orientation=$dockOrientation
    foreach($app in @($script:config.pinnedApps|Where-Object {Test-BakaPinnedAppAvailable $_})){
        $button=New-BakaButton ([string]$app.name) ({param($sender,$eventArgs)Start-BakaPinnedApp $sender.Tag}) ([string]$app.glyph) ("Launch or focus {0}" -f $app.name) -ShowIndicator -IconSource (Get-BakaAppIconSource $app)
        $button.Tag=$app
        $button.Width=[double]$script:config.dock.iconSize+15;$button.Height=[double]$script:config.dock.iconSize+8;$button.Margin=if($script:dockVertical){[System.Windows.Thickness]::new(0,[double]$script:config.dock.spacing/2,0,[double]$script:config.dock.spacing/2)}else{[System.Windows.Thickness]::new([double]$script:config.dock.spacing/2,0,[double]$script:config.dock.spacing/2,0)}
        $script:dockButtons[[string]$app.id]=$button;$appPanel.Children.Add($button)|Out-Null
    }
    $row.Children.Add($appPanel)|Out-Null
    $runningSeparator=[System.Windows.Controls.Border]::new();if($script:dockVertical){$runningSeparator.Height=1;$runningSeparator.Width=32}else{$runningSeparator.Width=1;$runningSeparator.Height=36};$runningSeparator.Background=$script:borderBrush;$runningSeparator.Margin=[System.Windows.Thickness]::new(6,0,6,0);$runningSeparator.Visibility=[System.Windows.Visibility]::Collapsed;$row.Children.Add($runningSeparator)|Out-Null
    $runningPanel=[System.Windows.Controls.StackPanel]::new();$runningPanel.Orientation=$dockOrientation;$row.Children.Add($runningPanel)|Out-Null
    $script:windows.DockRunningPanel=$runningPanel;$script:windows.DockRunningSeparator=$runningSeparator
    $separator2=[System.Windows.Controls.Border]::new();if($script:dockVertical){$separator2.Height=1;$separator2.Width=40}else{$separator2.Width=1;$separator2.Height=48};$separator2.Background=$script:borderBrush;$separator2.Margin=if($script:dockVertical){[System.Windows.Thickness]::new(0,6,0,6)}else{[System.Windows.Thickness]::new(6,0,7,0)};$row.Children.Add($separator2)|Out-Null
    $utilityWidth=[double]$script:config.dock.iconSize+15
    $arena=New-BakaButton 'Arena' {Show-BakaDashboard} ([string][char]0xE7FC) 'BAKA Arena: gaming dashboard';$arena.Width=$utilityWidth;$arena.Height=[double]$script:config.dock.iconSize+8;$row.Children.Add($arena)|Out-Null
    $files=New-BakaButton 'Files' {Show-BakaFiles} ([string][char]0xE8B7) 'BAKA Files';$files.Width=$utilityWidth;$files.Height=[double]$script:config.dock.iconSize+8;$row.Children.Add($files)|Out-Null
    $quick=New-BakaButton 'Control Center' {Show-BakaQuickPanel} ([string][char]0xE9E9) 'Control Center: volume, power plan, profiles, wallpaper';$quick.Width=$utilityWidth;$quick.Height=[double]$script:config.dock.iconSize+8;$row.Children.Add($quick)|Out-Null
    $edit=New-BakaButton 'BAKA Settings' {Show-BakaSettings} ([string][char]0xE771) 'BAKA Settings: theme, wallpaper, dock, power, tools';$edit.Width=$utilityWidth;$edit.Height=[double]$script:config.dock.iconSize+8;$row.Children.Add($edit)|Out-Null
    Set-BakaWindowContent $window $row
    $window.SizeToContent=if($script:dockVertical){[System.Windows.SizeToContent]::Height}else{[System.Windows.SizeToContent]::Width}
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
function Invoke-BakaPowerAction([string]$Action){
    # Lock, sleep, restart, shut down, or sign out from the BAKA menu bar and Control Center.
    if($script:previewMode){Write-BakaUiLog ('power-action-preview action={0}' -f $Action);return}
    $confirm=@{Restart='Restart this PC now?';Shutdown='Shut down this PC now?';SignOut='Sign out of Windows now? Unsaved work in open apps may be lost.'}
    if($confirm.ContainsKey($Action)){if([System.Windows.Forms.MessageBox]::Show($confirm[$Action],'BAKA',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Question) -ne [System.Windows.Forms.DialogResult]::Yes){return}}
    $shutdown=Join-Path $env:WINDIR 'System32\shutdown.exe'
    try{
        switch($Action){
            'Lock'{[void][BakaLiquidNative]::LockWorkStation()}
            'Sleep'{[void][BakaLiquidNative]::SetSuspendState($false,$false,$false)}
            'Restart'{Start-Process -FilePath $shutdown -ArgumentList @('/r','/t','0') -WindowStyle Hidden}
            'Shutdown'{Start-Process -FilePath $shutdown -ArgumentList @('/s','/t','0') -WindowStyle Hidden}
            'SignOut'{Start-Process -FilePath $shutdown -ArgumentList @('/l') -WindowStyle Hidden}
        }
        Write-BakaUiLog ('power-action action={0}' -f $Action)
    }catch{Write-BakaUiLog ('power-action-failed action={0} error="{1}"' -f $Action,$_.Exception.Message)}
}
function Update-BakaPowerPlanState {
    # Reads the active Windows power plan (powercfg) and refreshes every label and button that shows it.
    $script:powerPlanLabel='POWER'
    $choices=@()
    if($script:powerModuleAvailable){try{$choices=@(Get-BakaPowerPlanChoices);$active=Get-BakaActivePowerScheme;if($active){$script:powerPlanLabel=([string]$active.Name).ToUpperInvariant()}}catch{Write-BakaUiLog ('power-plan-read-failed error="{0}"' -f $_.Exception.Message)}}
    $panel=$script:windows.QuickPowerPanel
    if($panel){
        $panel.Children.Clear()
        if(-not $choices.Count){$panel.Children.Add((New-BakaText 'Power plans are managed in Windows Settings on this PC.' 10 'Normal' $script:mutedBrush))|Out-Null}
        foreach($choice in $choices){
            $glyph=if($choice.Label -eq 'BAKA Gaming'){[string][char]0xE945}elseif($choice.Label -eq 'Balanced'){[string][char]0xE83F}else{[string][char]0xEBAA}
            $button=New-BakaActionButton $choice.Label {param($sender,$eventArgs)Set-BakaPowerPlanChoice ([string]$sender.Tag)} $glyph
            $button.Tag=$choice.Guid
            if($choice.Active){$button.Background=New-BakaBrush $script:theme.accent 96;$button.BorderBrush=$script:accentBrush}
            $panel.Children.Add($button)|Out-Null
        }
    }
    Update-BakaProfileStatus
}
function Set-BakaPowerPlanChoice([string]$Guid){
    if($script:previewMode){Write-BakaUiLog ('power-plan-preview guid={0}' -f $Guid);return}
    try{if(Set-BakaActivePowerScheme -Guid $Guid -Confirm:$false){Write-BakaUiLog ('power-plan-selected guid={0}' -f $Guid)}}catch{Write-BakaUiLog ('power-plan-select-failed error="{0}"' -f $_.Exception.Message)}
    Update-BakaPowerPlanState
}
function Get-BakaWallpaperGallery {
    # The shipped BAKA wallpapers plus any picture the user dropped into ProgramData\BAKA\Assets.
    $seen=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach($folder in @((Join-Path $dataRoot 'Assets'),(Join-Path $dataRoot 'Assets\Wallpapers'))){
        if(-not (Test-Path -LiteralPath $folder -PathType Container)){continue}
        foreach($file in @(Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue|Where-Object {$_.Extension -in @('.png','.jpg','.jpeg','.bmp','.webp')}|Sort-Object @{Expression={$_.Name -notlike 'BAKA-Stealth*'}},Name)){
            if($seen.Add($file.Name)){[pscustomobject]@{Name=($file.BaseName -replace '^BAKA-','' -replace '-4K$','' -replace '-',' ');Path=$file.FullName}}
        }
    }
}
function Set-BakaWallpaperChoice([string]$Path){
    $script:config.wallpaper.mode='Image';$script:config.wallpaper.path=$Path;$script:wallpaperDirty=$true
    try{Save-BakaDesktopConfiguration -Path $script:settingsPath -Configuration $script:config|Out-Null}catch{Write-BakaUiLog ('wallpaper-choice-save-failed error="{0}"' -f $_.Exception.Message)}
    Invoke-BakaWallpaper -Force
    if($script:settingsControls){Update-BakaSettingsControls}
    Write-BakaUiLog ('wallpaper-chosen path="{0}"' -f $Path)
}
function New-BakaWallpaperGallery([int]$Columns=3,[double]$ThumbWidth=112){
    $wrap=[System.Windows.Controls.WrapPanel]::new();$wrap.Margin=[System.Windows.Thickness]::new(-4,2,0,2)
    foreach($item in @(Get-BakaWallpaperGallery)){
        $thumb=[System.Windows.Controls.Button]::new();$thumb.Width=$ThumbWidth;$thumb.Height=[math]::Round($ThumbWidth*0.5625)+22;$thumb.Margin=[System.Windows.Thickness]::new(4);$thumb.Padding=[System.Windows.Thickness]::new(3);$thumb.Cursor=[System.Windows.Input.Cursors]::Hand
        $thumb.Background=$script:surfaceAltBrush;$thumb.BorderBrush=$script:borderBrush;$thumb.BorderThickness=[System.Windows.Thickness]::new(1);$thumb.Template=Get-BakaPillTemplate 10;$thumb.ToolTip=('Use {0} as the wallpaper' -f $item.Name)
        [System.Windows.Automation.AutomationProperties]::SetName($thumb,('Wallpaper {0}' -f $item.Name))
        $content=[System.Windows.Controls.StackPanel]::new()
        $image=[System.Windows.Controls.Image]::new();$image.Height=[math]::Round(($ThumbWidth-6)*0.5625);$image.Stretch=[System.Windows.Media.Stretch]::UniformToFill;$image.Source=Get-BakaImageSource $item.Path 240
        $content.Children.Add($image)|Out-Null
        $label=New-BakaText $item.Name 10 'Normal' $script:textBrush;$label.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center;$label.TextWrapping=[System.Windows.TextWrapping]::NoWrap;$content.Children.Add($label)|Out-Null
        $thumb.Content=$content;$thumb.Tag=$item.Path
        $thumb.Add_Click({param($sender,$eventArgs)Set-BakaWallpaperChoice ([string]$sender.Tag)})
        $wrap.Children.Add($thumb)|Out-Null
    }
    return $wrap
}
function New-BakaQuickSection([string]$Title){
    $label=New-BakaText $Title.ToUpperInvariant() 10 'Bold' $script:mutedBrush;$label.Margin=[System.Windows.Thickness]::new(2,14,0,4);return $label
}
function Update-BakaVolumeControls {
    if(-not $script:windows.QuickVolume){return}
    $state=$null;try{$state=Get-BakaVolume}catch{}
    $script:volumeLoading=$true
    try{
        if($state -and $state.Level -ge 0){$script:windows.QuickVolume.IsEnabled=$true;$script:windows.QuickVolume.Value=[double]$state.Level;$script:windows.QuickMute.Content.Children[0].Text=if($state.Muted){[string][char]0xE74F}else{[string][char]0xE767}}
        else{$script:windows.QuickVolume.IsEnabled=$false}
    }finally{$script:volumeLoading=$false}
}
function New-BakaQuickPanel {
    $window=New-BakaWindow 400 700 'BAKA Quick Panel' $true $true
    $stack=[System.Windows.Controls.StackPanel]::new();$stack.Margin=[System.Windows.Thickness]::new(2,0,6,6)
    $status=New-BakaText 'DESKTOP  ·  BAKA GAMING' 11 'Bold' $script:accentBrush;$status.Name='QuickStatus';$script:windows.QuickStatus=$status;$stack.Children.Add($status)|Out-Null
    $network=New-BakaText 'Network status is provided by Windows.' 10 'Normal' $script:mutedBrush;$network.Name='QuickNetwork';$script:windows.QuickNetwork=$network;$network.Margin=[System.Windows.Thickness]::new(0,3,0,2);$stack.Children.Add($network)|Out-Null
    $links=[System.Windows.Controls.WrapPanel]::new();$links.Margin=[System.Windows.Thickness]::new(-4,6,0,0)
    foreach($entry in @(
        [pscustomobject]@{Name='Network';Uri='ms-settings:network-status';Glyph=[string][char]0xE774},
        [pscustomobject]@{Name='Bluetooth';Uri='ms-settings:bluetooth';Glyph=[string][char]0xE702},
        [pscustomobject]@{Name='Display';Uri='ms-settings:display';Glyph=[string][char]0xE7F4},
        [pscustomobject]@{Name='Sound';Uri='ms-settings:sound';Glyph=[string][char]0xE767},
        [pscustomobject]@{Name='Microphone';Uri='ms-settings:privacy-microphone';Glyph=[string][char]0xE720},
        [pscustomobject]@{Name='Notifications';Uri='ms-settings:notifications';Glyph=[string][char]0xEA8F},
        [pscustomobject]@{Name='Apps';Uri='ms-settings:appsfeatures';Glyph=[string][char]0xE71D},
        [pscustomobject]@{Name='Updates';Uri='ms-settings:windowsupdate';Glyph=[string][char]0xE895}
    )){
        $link=New-BakaQuickTile ([string]$entry.Name) ([string]$entry.Glyph) {param($sender,$eventArgs)Open-BakaSystemSettings ([string]$sender.Tag)}
        $link.Width=80;$link.Height=64;$link.Margin=[System.Windows.Thickness]::new(3);$link.Tag=[string]$entry.Uri
        $links.Children.Add($link)|Out-Null
    }
    $stack.Children.Add($links)|Out-Null

    $stack.Children.Add((New-BakaQuickSection 'Sound'))|Out-Null
    $soundRow=[System.Windows.Controls.Grid]::new();$muteColumn=[System.Windows.Controls.ColumnDefinition]::new();$muteColumn.Width=[System.Windows.GridLength]::Auto;$soundRow.ColumnDefinitions.Add($muteColumn);$soundRow.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
    $mute=New-BakaActionButton '' {param($sender,$eventArgs)try{$state=Get-BakaVolume;[void](Set-BakaVolume -Muted (-not [bool]$state.Muted))}catch{};Update-BakaVolumeControls} ([string][char]0xE767);$mute.ToolTip='Mute or unmute';$script:windows.QuickMute=$mute
    $soundRow.Children.Add($mute)|Out-Null
    $volume=[System.Windows.Controls.Slider]::new();$volume.Minimum=0;$volume.Maximum=100;$volume.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$volume.Margin=[System.Windows.Thickness]::new(8,0,4,0);$volume.Foreground=$script:accentBrush;$volume.IsMoveToPointEnabled=$true
    [System.Windows.Automation.AutomationProperties]::SetName($volume,'Volume')
    $volume.Add_ValueChanged({param($sender,$eventArgs)if(-not $script:volumeLoading){try{[void](Set-BakaVolume -Level ([int]$sender.Value))}catch{}}})
    [System.Windows.Controls.Grid]::SetColumn($volume,1);$soundRow.Children.Add($volume)|Out-Null;$script:windows.QuickVolume=$volume
    $stack.Children.Add($soundRow)|Out-Null

    $stack.Children.Add((New-BakaQuickSection 'Power plan'))|Out-Null
    $powerPanel=[System.Windows.Controls.WrapPanel]::new();$powerPanel.Margin=[System.Windows.Thickness]::new(-4,0,0,0);$script:windows.QuickPowerPanel=$powerPanel;$stack.Children.Add($powerPanel)|Out-Null

    $stack.Children.Add((New-BakaQuickSection 'Performance profile'))|Out-Null
    $profiles=[System.Windows.Controls.WrapPanel]::new();$profiles.Margin=[System.Windows.Thickness]::new(-4,0,0,0)
    foreach($profile in @([pscustomobject]@{Name='Desktop';Glyph=[string][char]0xE80F},[pscustomobject]@{Name='CompetitiveGaming';Glyph=[string][char]0xE7FC},[pscustomobject]@{Name='Benchmark';Glyph=[string][char]0xE9D2})){
        $label=if($profile.Name -eq 'CompetitiveGaming'){'Gaming'}else{$profile.Name}
        $button=New-BakaActionButton $label {param($sender,$eventArgs)try{[void](Set-BakaUiProfile ([string]$sender.Tag) 'Manual')}catch{[System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Profile change failed',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)|Out-Null}} $profile.Glyph
        $button.Tag=[string]$profile.Name;$profiles.Children.Add($button)|Out-Null
    }
    $stack.Children.Add($profiles)|Out-Null
    $autoDetect=New-BakaActionButton 'Detect games automatically' {
        $script:manualOverride=$null
        $game=Get-BakaDetectedGame
        if($game){$script:autoGame=$true;$script:detectedGame=$game.DisplayName;[void](Set-BakaUiProfile 'CompetitiveGaming' 'Auto')}
        else{$script:autoGame=$false;$script:detectedGame=$null;[void](Set-BakaUiProfile 'Desktop' 'Auto')}
    } ([string][char]0xE768)
    $autoDetect.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Left;$stack.Children.Add($autoDetect)|Out-Null

    $stack.Children.Add((New-BakaQuickSection 'Look'))|Out-Null
    $themeCombo=[System.Windows.Controls.ComboBox]::new();$themeCombo.MinWidth=160;$themeCombo.Margin=[System.Windows.Thickness]::new(0,2,0,4);Protect-BakaComboWheel $themeCombo
    foreach($theme in @($script:themeManifest)){$themeCombo.Items.Add([string]$theme.name)|Out-Null};$themeCombo.SelectedItem=[string]$script:config.appearance.theme
    $themeCombo.Add_SelectionChanged({param($sender,$eventArgs)if($sender.SelectedItem){$script:config.appearance.theme=[string]$sender.SelectedItem;$picked=Get-BakaTheme $script:config.appearance.theme;if($picked){$script:config.appearance.accentColor=[string]$picked.accent};Set-BakaTheme $script:config.appearance.theme;Save-BakaDesktopConfiguration -Path $script:settingsPath -Configuration $script:config|Out-Null;Write-BakaUiLog ('theme-selected name="{0}"' -f $script:config.appearance.theme)}})
    # The narrow Quick Panel has no room for a title/description column; the Look header names the picker.
    $themeCombo.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Stretch;$themeCombo.ToolTip='Colors for every BAKA surface'
    [System.Windows.Automation.AutomationProperties]::SetName($themeCombo,'Theme')
    $stack.Children.Add($themeCombo)|Out-Null
    $stack.Children.Add((New-BakaWallpaperGallery 3 96))|Out-Null
    $widgetsToggle=[System.Windows.Controls.CheckBox]::new();$widgetsToggle.Content='Show desktop widgets';$widgetsToggle.IsChecked=[bool]$script:config.widgets.enabled;$widgetsToggle.Foreground=$script:textBrush;$widgetsToggle.Margin=[System.Windows.Thickness]::new(2,6,0,4)
    $widgetsToggle.Add_Click({param($sender,$eventArgs)$script:config.widgets.enabled=[bool]$sender.IsChecked;Save-BakaDesktopConfiguration -Path $script:settingsPath -Configuration $script:config|Out-Null;if($script:config.widgets.enabled){Show-BakaWidgets}else{Hide-BakaWidgets};Write-BakaUiLog ('widgets-enabled={0}' -f $script:config.widgets.enabled)})
    $stack.Children.Add($widgetsToggle)|Out-Null

    $stack.Children.Add((New-BakaQuickSection 'Open'))|Out-Null
    $buttons=[System.Windows.Controls.WrapPanel]::new();$buttons.Margin=[System.Windows.Thickness]::new(-4,0,0,0)
    $buttons.Children.Add((New-BakaActionButton 'BAKA Settings' {Show-BakaSettings} ([string][char]0xE771)))|Out-Null
    $buttons.Children.Add((New-BakaActionButton 'Windows Settings' {Start-Process 'ms-settings:'|Out-Null} ([string][char]0xE713)))|Out-Null
    $buttons.Children.Add((New-BakaActionButton 'Task Manager' {Start-Process (Join-Path $env:WINDIR 'System32\Taskmgr.exe')|Out-Null} ([string][char]0xE9D9)))|Out-Null
    $stack.Children.Add($buttons)|Out-Null

    $stack.Children.Add((New-BakaQuickSection 'Power'))|Out-Null
    $power=[System.Windows.Controls.WrapPanel]::new();$power.Margin=[System.Windows.Thickness]::new(-4,0,0,0)
    foreach($action in @(@{Label='Lock';Action='Lock';Glyph=[string][char]0xE72E},@{Label='Sleep';Action='Sleep';Glyph=[string][char]0xE708},@{Label='Restart';Action='Restart';Glyph=[string][char]0xE777},@{Label='Shut down';Action='Shutdown';Glyph=[string][char]0xE7E8},@{Label='Sign out';Action='SignOut';Glyph=[string][char]0xE748})){
        $button=New-BakaActionButton $action.Label {param($sender,$eventArgs)Invoke-BakaPowerAction ([string]$sender.Tag)} $action.Glyph;$button.Tag=$action.Action;$power.Children.Add($button)|Out-Null
    }
    $stack.Children.Add($power)|Out-Null
    $quickScroll=[System.Windows.Controls.ScrollViewer]::new();$quickScroll.VerticalScrollBarVisibility=[System.Windows.Controls.ScrollBarVisibility]::Auto;$quickScroll.Background=[System.Windows.Media.Brushes]::Transparent;$quickScroll.Content=$stack
    Set-BakaSettingsControlTheme $quickScroll
    Set-BakaWindowContent $window $quickScroll;Set-BakaCompactScale $window 0.85;$script:windows.Quick=$window
    $window.add_Closing({param($sender,$eventArgs) if(-not $script:allowShutdown){$eventArgs.Cancel=$true;Hide-BakaWindow $sender}})
    # Like a system flyout: clicking anywhere else closes it.
    $window.add_Deactivated({param($sender,$eventArgs)if(-not $script:smokeTestMode -and $sender.IsVisible){Hide-BakaWindow $sender}})
    return $window
}

function New-BakaBarButton([string]$Text,[string]$Glyph,[scriptblock]$Action,[string]$Tip){
    # Flat menu-bar item: glyph and/or text, highlight on hover, no keycap chrome.
    $button=[System.Windows.Controls.Button]::new();$button.Padding=[System.Windows.Thickness]::new(7,1,7,1);$button.Margin=[System.Windows.Thickness]::new(1,0,1,0);$button.Height=22
    $button.Background=[System.Windows.Media.Brushes]::Transparent;$button.BorderThickness=[System.Windows.Thickness]::new(0);$button.Foreground=$script:textBrush;$button.Cursor=[System.Windows.Input.Cursors]::Hand
    $button.Template=Get-BakaPillTemplate 7;$button.ToolTip=$Tip;[System.Windows.Automation.AutomationProperties]::SetName($button,$Tip)
    $content=[System.Windows.Controls.StackPanel]::new();$content.Orientation=[System.Windows.Controls.Orientation]::Horizontal;$content.VerticalAlignment=[System.Windows.VerticalAlignment]::Center
    if($Glyph){$icon=New-BakaText $Glyph 12 'Normal' $script:textBrush;$icon.FontFamily=[System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets');$icon.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$content.Children.Add($icon)|Out-Null}
    $label=New-BakaText $Text 11 'Normal' $script:textBrush;$label.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$label.TextWrapping=[System.Windows.TextWrapping]::NoWrap
    if($Glyph -and $Text){$label.Margin=[System.Windows.Thickness]::new(6,0,0,0)}
    if($Text){$content.Children.Add($label)|Out-Null}
    $button.Content=$content
    $button.Add_MouseEnter({param($sender,$eventArgs)$sender.Background=New-BakaBrush '#FFFFFF' 34})
    $button.Add_MouseLeave({param($sender,$eventArgs)$sender.Background=[System.Windows.Media.Brushes]::Transparent})
    if($Action){$button.Add_Click($Action)}
    return $button
}
function Show-BakaMenu($Anchor,[object[]]$Items){
    # Drop-down menu under a menu-bar item. Items: @{Label;Glyph;Action} or '-' for a separator.
    $menu=[System.Windows.Controls.ContextMenu]::new();$menu.PlacementTarget=$Anchor;$menu.Placement=[System.Windows.Controls.Primitives.PlacementMode]::Bottom
    $menu.Background=New-BakaBrush $script:theme.surface 248;$menu.Foreground=$script:textBrush;$menu.BorderBrush=$script:borderBrush;$menu.Padding=[System.Windows.Thickness]::new(4)
    foreach($item in $Items){
        if($item -is [string] -and $item -eq '-'){$menu.Items.Add([System.Windows.Controls.Separator]::new())|Out-Null;continue}
        $entry=[System.Windows.Controls.MenuItem]::new();$entry.Header=$item.Label;$entry.Foreground=$script:textBrush;$entry.Padding=[System.Windows.Thickness]::new(6,5,18,5);$entry.FontFamily=[System.Windows.Media.FontFamily]::new('Segoe UI Variable');$entry.FontSize=12
        if($item.Glyph){$glyph=New-BakaText $item.Glyph 13 'Normal' $script:accentBrush;$glyph.FontFamily=[System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets');$entry.Icon=$glyph}
        $entry.Tag=$item.Action;$entry.Add_Click({param($sender,$eventArgs)try{& $sender.Tag}catch{Write-BakaUiLog ('menu-action-failed error="{0}"' -f $_.Exception.Message)}})
        $menu.Items.Add($entry)|Out-Null
    }
    $menu.IsOpen=$true
}
function Get-BakaScreenScale {
    try{$source=if($script:windows.TopBar){[System.Windows.PresentationSource]::FromVisual($script:windows.TopBar)}else{$null};if($source -and $source.CompositionTarget){return [double]$source.CompositionTarget.TransformToDevice.M11}}catch{}
    try{return [double]([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width/[System.Windows.SystemParameters]::PrimaryScreenWidth)}catch{}
    return 1.0
}
function New-BakaTopBar {
    # BAKA menu bar: logo menu, the app in front, status, then tray, network, volume, battery, clock, and
    # Control Center. It reserves the top edge like a real taskbar, so maximized windows stop under it.
    $window=New-BakaWindow 1280 28 'BAKA Liquid System Bar' $true
    $window.Tag.CornerRadius=[System.Windows.CornerRadius]::new(0);$window.Tag.Padding=[System.Windows.Thickness]::new(8,0,8,0);$window.Tag.BorderThickness=[System.Windows.Thickness]::new(0,0,0,1)
    if($window.Tag.Tag.Rim){$window.Tag.Tag.Rim.Visibility=[System.Windows.Visibility]::Collapsed}
    if($window.Tag.Tag.Light){$window.Tag.Tag.Light.Visibility=[System.Windows.Visibility]::Collapsed}
    $grid=[System.Windows.Controls.Grid]::new();$grid.VerticalAlignment=[System.Windows.VerticalAlignment]::Center
    $leftColumn=[System.Windows.Controls.ColumnDefinition]::new();$leftColumn.Width=[System.Windows.GridLength]::Auto;$grid.ColumnDefinitions.Add($leftColumn)
    $grid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
    $rightColumn=[System.Windows.Controls.ColumnDefinition]::new();$rightColumn.Width=[System.Windows.GridLength]::Auto;$grid.ColumnDefinitions.Add($rightColumn)
    $left=[System.Windows.Controls.StackPanel]::new();$left.Orientation=[System.Windows.Controls.Orientation]::Horizontal;$left.VerticalAlignment=[System.Windows.VerticalAlignment]::Center
    $logo=New-BakaBarButton 'BAKA' ([string][char]0xE7FC) $null 'BAKA menu'
    $logo.Content.Children[0].Foreground=$script:accentBrush;$logo.Content.Children[1].FontWeight=[System.Windows.FontWeights]::Bold
    $logo.Add_Click({param($sender,$eventArgs)Show-BakaMenu $sender @(
        @{Label='About this PC  ·  BAKA Arena';Glyph=[string][char]0xE946;Action={Show-BakaDashboard}},
        @{Label='BAKA Settings…';Glyph=[string][char]0xE771;Action={Show-BakaSettings}},
        @{Label='Windows Settings';Glyph=[string][char]0xE713;Action={Start-Process 'ms-settings:'|Out-Null}},
        @{Label='Task Manager';Glyph=[string][char]0xE9D9;Action={Start-Process (Join-Path $env:WINDIR 'System32\Taskmgr.exe')|Out-Null}},
        '-',
        @{Label='Lock';Glyph=[string][char]0xE72E;Action={Invoke-BakaPowerAction 'Lock'}},
        @{Label='Sleep';Glyph=[string][char]0xE708;Action={Invoke-BakaPowerAction 'Sleep'}},
        @{Label='Restart…';Glyph=[string][char]0xE777;Action={Invoke-BakaPowerAction 'Restart'}},
        @{Label='Shut down…';Glyph=[string][char]0xE7E8;Action={Invoke-BakaPowerAction 'Shutdown'}},
        @{Label='Sign out…';Glyph=[string][char]0xE748;Action={Invoke-BakaPowerAction 'SignOut'}},
        '-',
        @{Label='Return to the Windows shell';Glyph=[string][char]0xE711;Action={Restore-BakaWindowsShell}}
    )})
    $left.Children.Add($logo)|Out-Null
    $app=New-BakaText 'Desktop' 11 'Bold' $script:textBrush;$app.Name='BarApp';$app.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$app.Margin=[System.Windows.Thickness]::new(8,0,10,0);$app.TextWrapping=[System.Windows.TextWrapping]::NoWrap;$app.MaxWidth=320;$app.TextTrimming=[System.Windows.TextTrimming]::CharacterEllipsis;$script:windows.BarApp=$app;$left.Children.Add($app)|Out-Null
    foreach($menuItem in @(@{Text='Apps';Glyph='';Action={Show-BakaLaunchpad};Tip='All apps (Launchpad)'},@{Text='Files';Glyph='';Action={Show-BakaFiles};Tip='BAKA Files'},@{Text='Arena';Glyph='';Action={Show-BakaDashboard};Tip='BAKA Arena gaming dashboard'})){
        $left.Children.Add((New-BakaBarButton $menuItem.Text $menuItem.Glyph $menuItem.Action $menuItem.Tip))|Out-Null
    }
    $grid.Children.Add($left)|Out-Null
    $status=New-BakaText 'DESKTOP  ·  BAKA GAMING' 10 'Normal' $script:mutedBrush;$status.Name='BarStatus';$script:windows.BarStatus=$status;$status.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center;$status.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$status.TextWrapping=[System.Windows.TextWrapping]::NoWrap;$status.Visibility=[System.Windows.Visibility]::Collapsed;[System.Windows.Controls.Grid]::SetColumn($status,1);$grid.Children.Add($status)|Out-Null
    $rightStack=[System.Windows.Controls.StackPanel]::new();$rightStack.Orientation=[System.Windows.Controls.Orientation]::Horizontal;$rightStack.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Right;$rightStack.VerticalAlignment=[System.Windows.VerticalAlignment]::Center
    $tray=New-BakaBarButton '' ([string][char]0xE70E) {Show-BakaTaskbarPeek} 'Show the Windows tray icons (Discord, Steam, …) for a few seconds';$rightStack.Children.Add($tray)|Out-Null
    $network=New-BakaBarButton '' ([string][char]0xE774) {Open-BakaSystemSettings 'ms-settings:network-status'} 'Network';$network.Name='BarNetworkButton';$script:windows.BarNetworkGlyph=$network.Content.Children[0];$rightStack.Children.Add($network)|Out-Null
    $networkText=New-BakaText 'OFFLINE' 10 'Normal' $script:mutedBrush;$networkText.Name='BarNetwork';$networkText.Visibility=[System.Windows.Visibility]::Collapsed;$script:windows.BarNetwork=$networkText;$rightStack.Children.Add($networkText)|Out-Null
    $volume=New-BakaBarButton '' ([string][char]0xE767) {Show-BakaQuickPanel} 'Volume and Control Center';$script:windows.BarVolumeGlyph=$volume.Content.Children[0];$rightStack.Children.Add($volume)|Out-Null
    $battery=New-BakaText '' 11 'Normal' $script:textBrush;$battery.Name='BarBattery';$script:windows.BarBattery=$battery;$battery.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$battery.Margin=[System.Windows.Thickness]::new(6,0,6,0);$battery.TextWrapping=[System.Windows.TextWrapping]::NoWrap;$rightStack.Children.Add($battery)|Out-Null
    $clock=New-BakaText (Get-Date -Format 'ddd d MMM  HH:mm') 11 'Bold' $script:textBrush;$clock.Name='BarClock';$script:windows.BarClock=$clock;$clock.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$clock.Margin=[System.Windows.Thickness]::new(8,0,6,0);$clock.TextWrapping=[System.Windows.TextWrapping]::NoWrap;$rightStack.Children.Add($clock)|Out-Null
    $quick=New-BakaBarButton '' ([string][char]0xE9E9) {Show-BakaQuickPanel} 'Control Center';$rightStack.Children.Add($quick)|Out-Null
    [System.Windows.Controls.Grid]::SetColumn($rightStack,2);$grid.Children.Add($rightStack)|Out-Null
    Set-BakaWindowContent $window $grid;$script:windows.TopBar=$window
    $window.add_SourceInitialized({param($sender,$eventArgs) Set-BakaTopBarPosition})
    $window.add_IsVisibleChanged({param($sender,$eventArgs)if($sender.IsVisible){Set-BakaTopBarPosition}else{Remove-BakaTopBarReservation}})
    $window.add_Closing({param($sender,$eventArgs) if(-not $script:allowShutdown){$eventArgs.Cancel=$true;$sender.Hide()}})
    return $window
}
function Remove-BakaTopBarReservation {
    if(-not $script:topBarReserved -or -not $script:windows.TopBar){return}
    try{Unregister-BakaAppBar -Handle ([System.Windows.Interop.WindowInteropHelper]::new($script:windows.TopBar).Handle);Write-BakaUiLog 'menubar-reservation-removed'}catch{}
    $script:topBarReserved=$false
}
function Update-BakaForegroundApp {
    if(-not $script:windows.BarApp -or -not $script:windows.TopBar.IsVisible){return}
    try{
        # Only look the process up when the foreground window changes (this runs every second).
        $foreground=[BakaLiquidNative]::GetForegroundWindow()
        if($foreground -eq $script:lastForegroundWindow){return}
        $script:lastForegroundWindow=$foreground
        $processId=[uint32]0;$title=[BakaLiquidNative]::GetForegroundTitle([ref]$processId)
        $name='Desktop'
        if($processId -and $processId -ne $PID){
            $process=Get-Process -Id $processId -ErrorAction SilentlyContinue
            if($process -and $process.ProcessName -notin @('explorer','ShellExperienceHost','SearchHost','StartMenuExperienceHost')){
                $name=try{[string]$process.MainModule.FileVersionInfo.FileDescription}catch{''}
                if([string]::IsNullOrWhiteSpace($name)){$name=$process.ProcessName}
            }
        }elseif($processId -eq $PID){$name='Desktop'}
        if($script:windows.BarApp.Text -ne $name){$script:windows.BarApp.Text=$name}
    }catch{}
}

# ---- Launchpad: every installed app (desktop and Store) with real icons and instant search ----
function ConvertTo-BakaBitmapSource($Icon){
    if(-not $Icon){return $null}
    try{$bitmap=[System.Windows.Media.Imaging.BitmapSource]::Create($Icon.Width,$Icon.Height,96,96,[System.Windows.Media.PixelFormats]::Pbgra32,$null,$Icon.Pixels,$Icon.Width*4);$bitmap.Freeze();return $bitmap}catch{return $null}
}
if(-not ('BakaIconTint' -as [type])){
    Add-Type -TypeDefinition @'
public static class BakaIconTint {
  // Re-colours premultiplied BGRA icon pixels to one tint, keeping the icon's shape (alpha) and shading
  // (brightness), so every app icon matches a monochrome theme. 0.42..1.0 keeps dark details readable.
  public static byte[] Mono(byte[] px, int r, int g, int b) {
    byte[] o = new byte[px.Length];
    for (int i = 0; i + 3 < px.Length; i += 4) {
      int a = px[i + 3];
      if (a == 0) continue;
      double lum = (0.0722 * px[i] + 0.7152 * px[i + 1] + 0.2126 * px[i + 2]) / a;   // unpremultiplied 0..1
      if (lum > 1) lum = 1;
      double f = (0.42 + 0.58 * lum) * a / 255.0;
      o[i] = (byte)(b * f); o[i + 1] = (byte)(g * f); o[i + 2] = (byte)(r * f); o[i + 3] = (byte)a;
    }
    return o;
  }
}
'@ -ErrorAction SilentlyContinue
}
function Test-BakaThemedIcons {
    $override=$script:config.appearance.PSObject.Properties['themedIcons']
    if($override -and $null -ne $override.Value){return [bool]$override.Value}
    return ([string]$script:theme.iconStyle -eq 'Mono')
}
function ConvertTo-BakaThemedIcon($Source){
    # Applied to every dock, Launchpad, and open-window icon when the theme asks for matching icons.
    if(-not $Source -or -not (Test-BakaThemedIcons)){return $Source}
    try{
        $converted=[System.Windows.Media.Imaging.FormatConvertedBitmap]::new($Source,[System.Windows.Media.PixelFormats]::Pbgra32,$null,0)
        $width=$converted.PixelWidth;$height=$converted.PixelHeight;$stride=$width*4
        $pixels=[byte[]]::new($stride*$height);$converted.CopyPixels($pixels,$stride,0)
        $tint=ConvertTo-BakaColor ([string]$script:theme.text)
        $mono=[BakaIconTint]::Mono($pixels,$tint.R,$tint.G,$tint.B)
        $bitmap=[System.Windows.Media.Imaging.BitmapSource]::Create($width,$height,96,96,[System.Windows.Media.PixelFormats]::Pbgra32,$null,$mono,$stride);$bitmap.Freeze()
        return $bitmap
    }catch{return $Source}
}
function Get-BakaShellIconSource([string]$ParsingName,[int]$Size=64){
    if([string]::IsNullOrWhiteSpace($ParsingName)){return $null}
    $key='shell|'+$ParsingName+'|'+$Size+'|'+[bool](Test-BakaThemedIcons)+'|'+$script:theme.text
    if($script:iconCache.ContainsKey($key)){return $script:iconCache[$key]}
    $source=$null
    try{$source=ConvertTo-BakaThemedIcon (ConvertTo-BakaBitmapSource (Get-BakaShellIconPixels -ParsingName $ParsingName -Size $Size))}catch{}
    $script:iconCache[$key]=$source
    return $source
}
function Get-BakaLaunchpadApps {
    $hidden='^(Uninstall|Read ?me|Help|Website|Release Notes)|uninstall'
    @(Get-StartApps -ErrorAction SilentlyContinue|Where-Object {$_.Name -and $_.AppID -and $_.Name -notmatch $hidden}|Sort-Object Name -Unique)
}
function Start-BakaLaunchpadApp($App){
    try{
        Hide-BakaWindow $script:windows.Launchpad
        Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList ('shell:AppsFolder\{0}' -f $App.AppID)|Out-Null
        Write-BakaUiLog ('launchpad-launch app="{0}"' -f $App.Name)
    }catch{Write-BakaUiLog ('launchpad-launch-failed app="{0}" error="{1}"' -f $App.Name,$_.Exception.Message)}
}
function Update-BakaLaunchpadFilter {
    $query=if($script:launchpadSearch -and $script:launchpadSearch.Tag -ne 'Placeholder'){[string]$script:launchpadSearch.Text}else{''}
    foreach($tile in @($script:launchpadGrid.Children)){
        $tile.Visibility=if([string]::IsNullOrWhiteSpace($query) -or ([string]$tile.Tag.Name) -like ('*'+$query.Trim()+'*')){[System.Windows.Visibility]::Visible}else{[System.Windows.Visibility]::Collapsed}
    }
}
function New-BakaLaunchpad {
    $screen=(Get-BakaActiveScreen).Bounds;$scale=Get-BakaScreenScale
    $window=New-BakaWindow ($screen.Width/$scale) ($screen.Height/$scale) 'BAKA Launchpad' $true
    $window.AllowsTransparency=$false
    $window.Left=$screen.Left/$scale;$window.Top=$screen.Top/$scale
    $window.Tag.CornerRadius=[System.Windows.CornerRadius]::new(0);$window.Tag.BorderThickness=[System.Windows.Thickness]::new(0);$window.Tag.Padding=[System.Windows.Thickness]::new(60,40,60,40)
    $window.Tag.Background=New-BakaBrush $script:theme.canvas 255;$window.Background=New-BakaBrush $script:theme.canvas 255
    if($window.Tag.Tag.Rim){$window.Tag.Tag.Rim.Visibility=[System.Windows.Visibility]::Collapsed}
    $layout=[System.Windows.Controls.Grid]::new()
    $topRow=[System.Windows.Controls.RowDefinition]::new();$topRow.Height=[System.Windows.GridLength]::Auto;$layout.RowDefinitions.Add($topRow);$layout.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new())
    $search=[System.Windows.Controls.TextBox]::new();$search.Width=440;$search.Height=40;$search.FontSize=15;$search.Padding=[System.Windows.Thickness]::new(16,8,16,8);$search.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center;$search.VerticalContentAlignment=[System.Windows.VerticalAlignment]::Center
    $search.Background=New-BakaBrush $script:theme.surfaceAlt 220;$search.Foreground=$script:mutedBrush;$search.BorderBrush=$script:borderBrush;$search.Text='Search apps';$search.Tag='Placeholder';$search.FontFamily=[System.Windows.Media.FontFamily]::new('Segoe UI Variable')
    [System.Windows.Automation.AutomationProperties]::SetName($search,'Search apps')
    $search.Add_GotFocus({param($sender,$eventArgs)if($sender.Tag -eq 'Placeholder'){$sender.Text='';$sender.Tag='';$sender.Foreground=$script:textBrush}})
    $search.Add_TextChanged({param($sender,$eventArgs)if($sender.Tag -ne 'Placeholder' -and $script:launchpadGrid){Update-BakaLaunchpadFilter}})
    $search.Add_KeyDown({param($sender,$eventArgs)if($eventArgs.Key -eq [System.Windows.Input.Key]::Enter){$first=@($script:launchpadGrid.Children|Where-Object {$_.Visibility -eq [System.Windows.Visibility]::Visible}|Select-Object -First 1);if($first){Start-BakaLaunchpadApp $first[0].Tag}}})
    $script:launchpadSearch=$search;$layout.Children.Add($search)|Out-Null
    $close=[System.Windows.Controls.Button]::new();$close.Width=36;$close.Height=36;$close.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Right;$close.VerticalAlignment=[System.Windows.VerticalAlignment]::Top;$close.Cursor=[System.Windows.Input.Cursors]::Hand
    $close.Background=New-BakaBrush $script:theme.surfaceAlt 220;$close.BorderBrush=$script:borderBrush;$close.BorderThickness=[System.Windows.Thickness]::new(1);$close.Template=Get-BakaPillTemplate 18;$close.ToolTip='Close (Esc)';[System.Windows.Automation.AutomationProperties]::SetName($close,'Close Launchpad')
    $closeGlyph=New-BakaText ([string][char]0xE711) 13 'Normal' $script:textBrush;$closeGlyph.FontFamily=[System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets');$closeGlyph.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center;$closeGlyph.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$close.Content=$closeGlyph
    $close.Add_Click({Hide-BakaWindow $script:windows.Launchpad});$layout.Children.Add($close)|Out-Null
    $scroll=[System.Windows.Controls.ScrollViewer]::new();$scroll.VerticalScrollBarVisibility=[System.Windows.Controls.ScrollBarVisibility]::Auto;$scroll.Margin=[System.Windows.Thickness]::new(0,30,0,0);[System.Windows.Controls.Grid]::SetRow($scroll,1)
    $grid=[System.Windows.Controls.WrapPanel]::new();$grid.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center;$script:launchpadGrid=$grid;$scroll.Content=$grid;$layout.Children.Add($scroll)|Out-Null
    foreach($app in @(Get-BakaLaunchpadApps)){
        $tile=[System.Windows.Controls.Button]::new();$tile.Width=96;$tile.Height=92;$tile.Margin=[System.Windows.Thickness]::new(6);$tile.Background=[System.Windows.Media.Brushes]::Transparent;$tile.BorderThickness=[System.Windows.Thickness]::new(0);$tile.Cursor=[System.Windows.Input.Cursors]::Hand;$tile.Template=Get-BakaPillTemplate 16
        $tile.ToolTip=$app.Name;[System.Windows.Automation.AutomationProperties]::SetName($tile,$app.Name)
        $content=[System.Windows.Controls.StackPanel]::new();$content.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center
        $icon=[System.Windows.Controls.Image]::new();$icon.Width=44;$icon.Height=44;$icon.Margin=[System.Windows.Thickness]::new(0,6,0,5);[System.Windows.Media.RenderOptions]::SetBitmapScalingMode($icon,[System.Windows.Media.BitmapScalingMode]::HighQuality)
        $icon.Source=Get-BakaShellIconSource ('shell:AppsFolder\'+$app.AppID) 96
        $content.Children.Add($icon)|Out-Null
        $label=New-BakaText ([string]$app.Name) 10 'Normal' $script:textBrush;$label.TextAlignment=[System.Windows.TextAlignment]::Center;$label.MaxHeight=28;$label.TextTrimming=[System.Windows.TextTrimming]::CharacterEllipsis;$label.Width=90
        $content.Children.Add($label)|Out-Null
        $tile.Content=$content;$tile.Tag=$app
        $tile.Add_MouseEnter({param($sender,$eventArgs)$sender.Background=New-BakaBrush '#FFFFFF' 26});$tile.Add_MouseLeave({param($sender,$eventArgs)$sender.Background=[System.Windows.Media.Brushes]::Transparent})
        $tile.Add_Click({param($sender,$eventArgs)Start-BakaLaunchpadApp $sender.Tag})
        $grid.Children.Add($tile)|Out-Null
    }
    Set-BakaWindowContent $window $layout;$script:windows.Launchpad=$window
    $window.add_KeyDown({param($sender,$eventArgs)if($eventArgs.Key -eq [System.Windows.Input.Key]::Escape){Hide-BakaWindow $sender}})
    $window.add_MouseLeftButtonDown({param($sender,$eventArgs)if($eventArgs.OriginalSource -is [System.Windows.Controls.Border] -or $eventArgs.OriginalSource -is [System.Windows.Controls.ScrollViewer]){Hide-BakaWindow $sender}})
    $window.add_Deactivated({param($sender,$eventArgs)if(-not $script:smokeTestMode -and $sender.IsVisible){Hide-BakaWindow $sender}})
    $window.add_Closing({param($sender,$eventArgs)if(-not $script:allowShutdown){$eventArgs.Cancel=$true;Hide-BakaWindow $sender}})
    Write-BakaUiLog ('launchpad-built apps={0}' -f $grid.Children.Count)
    return $window
}
function Show-BakaLaunchpad {
    if(-not $script:windows.Launchpad){[void](New-BakaLaunchpad)}
    $window=$script:windows.Launchpad
    if($window.IsVisible){Hide-BakaWindow $window;return}
    if($script:launchpadSearch){$script:launchpadSearch.Text='Search apps';$script:launchpadSearch.Tag='Placeholder';$script:launchpadSearch.Foreground=$script:mutedBrush;Update-BakaLaunchpadFilter}
    Show-BakaWindow $window -Activate
    if($script:launchpadSearch){[void]$script:launchpadSearch.Focus()}
}

# ---- Windows taskbar: fully hidden while the BAKA desktop runs; the tray can be peeked from the menu bar ----
function Show-BakaTaskbarPeek {
    if($script:previewMode){Write-BakaUiLog 'taskbar-peek-preview';return}
    try{$script:taskbarPeekUntil=(Get-Date).AddSeconds(15);[void](Set-BakaTaskbarAutoHide -Enabled $false -Confirm:$false);[void](Set-BakaTaskbarVisibility -Visible $true -Confirm:$false);Write-BakaUiLog 'taskbar-peek'}catch{Write-BakaUiLog ('taskbar-peek-failed error="{0}"' -f $_.Exception.Message)}
}
function Update-BakaTaskbarGuard {
    # Explorer shows the taskbar again after restarts and some shell events; keep it hidden unless peeking.
    # As the shell there is no Windows taskbar to guard, so skip the window lookups entirely.
    if($script:previewMode -or $script:shellMode -or -not [bool]$script:config.taskbar.autoHideWindowsTaskbar){return}
    try{
        if($script:taskbarPeekUntil -and (Get-Date) -lt $script:taskbarPeekUntil){return}
        if($script:taskbarPeekUntil){$script:taskbarPeekUntil=$null;[void](Set-BakaTaskbarAutoHide -Enabled $true -Confirm:$false)}
        if(Test-BakaTaskbarVisible){[void](Set-BakaTaskbarAutoHide -Enabled $true -Confirm:$false);[void](Set-BakaTaskbarVisibility -Visible $false -Confirm:$false)}
    }catch{Write-BakaUiLog ('taskbar-guard-failed error="{0}"' -f $_.Exception.Message)}
}

# ---- BAKA tools: run the bundled maintenance scripts without a console window ----
function Invoke-BakaTool([string]$Script,[string[]]$Arguments=@()){
    $path=Join-Path $dataRoot ('Scripts\'+$Script)
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){$path=Join-Path $runtimeRoot $Script}
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){[System.Windows.Forms.MessageBox]::Show(('This BAKA tool is not installed: {0}' -f $Script),'BAKA tools','OK','Information')|Out-Null;return $null}
    if($script:previewMode){Write-BakaUiLog ('tool-preview script={0}' -f $Script);return $null}
    $powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argumentList=@('-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $path))+$Arguments
    Write-BakaUiLog ('tool-started script={0}' -f $Script)
    return (Start-Process -FilePath $powershell -ArgumentList $argumentList -WindowStyle Hidden -PassThru)
}
function Start-BakaBrowserRepair([switch]$Interactive){
    # Installs Baka Browser from the copy shipped in the image when it is missing (self-repair).
    if($script:browserRepair -and -not $script:browserRepair.HasExited){if($Interactive){[System.Windows.Forms.MessageBox]::Show('Baka Browser is being installed. It appears in the dock in a moment.','Baka Browser','OK','Information')|Out-Null};return}
    $script:browserRepair=Invoke-BakaTool 'Install-SelectedApps.ps1' @('-Silent')
    if($script:browserRepair){Write-BakaUiLog 'browser-repair-started';if($Interactive){[System.Windows.Forms.MessageBox]::Show('Baka Browser is being installed. It appears in the dock in a moment.','Baka Browser','OK','Information')|Out-Null}}
}
function Update-BakaBrowserRepair {
    if(-not $script:browserRepair -or -not $script:browserRepair.HasExited){return}
    Write-BakaUiLog ('browser-repair-finished exitCode={0}' -f $script:browserRepair.ExitCode)
    $script:browserRepair=$null
    if($script:windows.Dock){$script:iconCache.Clear();Set-BakaDockAppearance}
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
            # Only the pipeline is disposed; the runspace stays open for the next read.
            try{$script:metricsPowerShell.Dispose()}catch{}
            $script:metricsPowerShell=$null;$script:metricsAsyncResult=$null
        }
    }
    if($script:metricsPowerShell){return}
    try{
        # One minimal runspace for the whole session. Creating a full default runspace on every read
        # (every 3 seconds) made the desktop's memory climb by tens of MiB between collections.
        $runspace=$script:metricsRunspace
        if(-not $runspace -or $runspace.RunspaceStateInfo.State -ne [System.Management.Automation.Runspaces.RunspaceState]::Opened){
            if($runspace){try{$runspace.Dispose()}catch{}}
            $initialState=[System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
            $initialState.ExecutionPolicy=[Microsoft.PowerShell.ExecutionPolicy]::Bypass
            $initialState.ImportPSModule([string[]]@('Microsoft.PowerShell.Utility','CimCmdlets',$script:monitoringModulePath))
            $runspace=[System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($initialState)
            $runspace.Open()
            $script:metricsRunspace=$runspace
            Write-BakaUiLog 'metrics-runspace-opened'
        }
        $worker=[System.Management.Automation.PowerShell]::Create();$worker.Runspace=$runspace
        [void]$worker.AddCommand('Get-BakaSystemMetrics')
        $script:metricsPowerShell=$worker;$script:metricsAsyncResult=$worker.BeginInvoke()
        Write-BakaUiLog 'metrics-query-started'
    }catch{
        Write-BakaUiLog ('metrics-worker-start-failed error="{0}"' -f $_.Exception.ToString())
        if($worker){try{$worker.Dispose()}catch{}}
        if($script:metricsRunspace){try{$script:metricsRunspace.Close();$script:metricsRunspace.Dispose()}catch{}}
        $script:metricsPowerShell=$null;$script:metricsRunspace=$null;$script:metricsAsyncResult=$null
    }
}
function Stop-BakaMetricWorker {
    $worker=$script:metricsPowerShell;$async=$script:metricsAsyncResult;$runspace=$script:metricsRunspace
    if(-not $worker){if($runspace){try{$runspace.Close();$runspace.Dispose()}catch{}};$script:metricsRunspace=$null;return}
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
    if($script:dockVertical){$script:windows.Dock.Width=[double]$script:config.dock.iconSize+$(if($script:activeProfile -eq 'Desktop'){34}else{28})}
    else{$script:windows.Dock.Height=[double]$script:config.dock.iconSize+$(if($script:activeProfile -eq 'Desktop'){30}else{24})}
    $script:windows.Dock.Tag.Background=$script:glassBrush;$script:windows.Dock.Tag.BorderBrush=$script:rimBrush
    foreach($button in @($script:windows.DockUtilityButtons)){$button.Height=[double]$script:config.dock.iconSize+8}
    if($script:windows.DockAppPanel){
        $script:windows.DockAppPanel.Children.Clear()
        $script:dockButtons.Clear()
        foreach($app in @($script:config.pinnedApps|Where-Object {Test-BakaPinnedAppAvailable $_})){
            $button=New-BakaButton ([string]$app.name) ({param($sender,$eventArgs)Start-BakaPinnedApp $sender.Tag}) ([string]$app.glyph) ("Launch or focus {0}" -f $app.name) -ShowIndicator -IconSource (Get-BakaAppIconSource $app)
            $button.Tag=$app
            $button.Width=[double]$script:config.dock.iconSize+15;$button.Height=[double]$script:config.dock.iconSize+8;$button.Margin=if($script:dockVertical){[System.Windows.Thickness]::new(0,[double]$script:config.dock.spacing/2,0,[double]$script:config.dock.spacing/2)}else{[System.Windows.Thickness]::new([double]$script:config.dock.spacing/2,0,[double]$script:config.dock.spacing/2,0)}
            if(Get-BakaProcessForApp $app){$button.BorderBrush=$script:accentBrush;$button.BorderThickness=[System.Windows.Thickness]::new(0,0,0,2)}
            $script:dockButtons[[string]$app.id]=$button;$script:windows.DockAppPanel.Children.Add($button)|Out-Null
        }
    }
    if($script:windows.DockStartButton){$script:windows.DockStartButton.Visibility=if([bool]$script:config.taskbar.showStartButton){[System.Windows.Visibility]::Visible}else{[System.Windows.Visibility]::Collapsed}}
    $script:runningAppSignature='';Update-BakaDockRunningApps
    Set-BakaDockPosition
}

function New-BakaSettings {
    $window=New-BakaWindow 920 660 'BAKA Liquid Settings' $true $true
    $layout=[System.Windows.Controls.Grid]::new();$layout.Background=[System.Windows.Media.Brushes]::Transparent
    $headerRow=[System.Windows.Controls.RowDefinition]::new();$headerRow.Height=[System.Windows.GridLength]::Auto;$layout.RowDefinitions.Add($headerRow)
    $bodyRow=[System.Windows.Controls.RowDefinition]::new();$bodyRow.Height=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star);$layout.RowDefinitions.Add($bodyRow)
    $footerRow=[System.Windows.Controls.RowDefinition]::new();$footerRow.Height=[System.Windows.GridLength]::Auto;$layout.RowDefinitions.Add($footerRow)
    $header=[System.Windows.Controls.DockPanel]::new();$header.LastChildFill=$true;$header.Height=56
    $header.Children.Add((New-BakaHeading 'BAKA Settings' 'Theme, wallpaper, dock, menu bar, widgets, power, and BAKA tools. Close with the red light or Esc.'))|Out-Null
    $layout.Children.Add($header)|Out-Null
    $tabs=[System.Windows.Controls.TabControl]::new();$tabs.Margin=[System.Windows.Thickness]::new(0,4,0,8);[System.Windows.Controls.Grid]::SetRow($tabs,1);$layout.Children.Add($tabs)|Out-Null

    $appearanceTab=[System.Windows.Controls.TabItem]::new();$appearanceTab.Header='Appearance';$appearanceScroll=[System.Windows.Controls.ScrollViewer]::new();$appearanceScroll.VerticalScrollBarVisibility=[System.Windows.Controls.ScrollBarVisibility]::Auto
    $appearance=[System.Windows.Controls.StackPanel]::new();$appearance.Margin=[System.Windows.Thickness]::new(14)
    $appearance.Children.Add((New-BakaHeading 'Theme and surface' 'Preset colors are shared by every BAKA surface; high contrast and remote sessions use opaque fallbacks.'))|Out-Null
    $themeCombo=[System.Windows.Controls.ComboBox]::new();$themeCombo.MinWidth=190;$themeCombo.Margin=[System.Windows.Thickness]::new(0,4,0,8)
    foreach($theme in @($script:themeManifest)){$themeCombo.Items.Add([string]$theme.name)|Out-Null};$themeCombo.SelectedItem=[string]$script:config.appearance.theme
    $themeCombo.Add_SelectionChanged({param($sender,$eventArgs)if($sender.SelectedItem -and -not $script:settingsLoading){$script:config.appearance.theme=[string]$sender.SelectedItem;$picked=Get-BakaTheme $script:config.appearance.theme;if($picked){$script:config.appearance.accentColor=[string]$picked.accent;if($script:settingsControls -and $script:settingsControls.Accent){$script:settingsControls.Accent.Text=$script:config.appearance.accentColor}};Set-BakaTheme $script:config.appearance.theme;$script:settingsDirty=$true}})
    $appearance.Children.Add((New-BakaRow 'Preset' 'Pop Glass (ice blue), Pop Sunset, Pop Mint, Pop Sakura, plus Obsidian, Liquid, Minimal, Gaming, and Violet.' $themeCombo))|Out-Null
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
    $wallpaperContent.Children.Add((New-BakaHeading 'Your desktop, your media' 'Pick a BAKA wallpaper, or use any picture, a looping video, or a solid color. Videos play muted behind your desktop icons and pause during games.'))|Out-Null
    $wallpaperContent.Children.Add((New-BakaText 'BAKA wallpapers (applied instantly)' 12 'Bold'))|Out-Null
    $wallpaperContent.Children.Add((New-BakaWallpaperGallery 5 150))|Out-Null
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
    $taskbarHide=[System.Windows.Controls.CheckBox]::new();$taskbarHide.Content='Replace the Windows taskbar with the BAKA menu bar and dock (the taskbar comes back if BAKA exits)';$taskbarHide.IsChecked=[bool]$script:config.taskbar.autoHideWindowsTaskbar;$taskbarHide.Foreground=$script:textBrush
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

    $barTab=[System.Windows.Controls.TabItem]::new();$barTab.Header='Menu bar';$barContent=[System.Windows.Controls.StackPanel]::new();$barContent.Margin=[System.Windows.Thickness]::new(14)
    $barContent.Children.Add((New-BakaHeading 'Menu bar' 'BAKA menu, the app in front, tray, network, volume, battery, clock, and Control Center. It hides while a game is running.'))|Out-Null
    $barEnabled=[System.Windows.Controls.CheckBox]::new();$barEnabled.Content='Show the BAKA menu bar';$barEnabled.IsChecked=[bool]$script:config.topBar.enabled;$barEnabled.Foreground=$script:textBrush
    $barEnabled.Add_Click({param($sender,$eventArgs)if(-not $script:settingsLoading){$script:config.topBar.enabled=[bool]$sender.IsChecked;$script:settingsDirty=$true}});$barContent.Children.Add($barEnabled)|Out-Null
    $barStatus=[System.Windows.Controls.CheckBox]::new();$barStatus.Content='Show active profile';$barStatus.IsChecked=[bool]$script:config.topBar.showProfile;$barStatus.Foreground=$script:textBrush
    $barStatus.Add_Click({param($sender,$eventArgs)if(-not $script:settingsLoading){$script:config.topBar.showProfile=[bool]$sender.IsChecked;$script:settingsDirty=$true}});$barContent.Children.Add($barStatus)|Out-Null
    $barDate=[System.Windows.Controls.CheckBox]::new();$barDate.Content='Show date and time';$barDate.IsChecked=[bool]$script:config.topBar.showDate;$barDate.Foreground=$script:textBrush
    $barDate.Add_Click({param($sender,$eventArgs)if(-not $script:settingsLoading){$script:config.topBar.showDate=[bool]$sender.IsChecked;$script:settingsDirty=$true}});$barContent.Children.Add($barDate)|Out-Null
    $barMonitor=[System.Windows.Controls.ComboBox]::new();[void]$barMonitor.Items.Add('Primary');foreach($screen in [System.Windows.Forms.Screen]::AllScreens){[void]$barMonitor.Items.Add($screen.DeviceName)};$barMonitor.SelectedItem=[string]$script:config.topBar.monitor
    $barMonitor.Add_SelectionChanged({param($sender,$eventArgs)if($sender.SelectedItem -and -not $script:settingsLoading){$script:config.topBar.monitor=[string]$sender.SelectedItem;$script:settingsDirty=$true}})
    $barContent.Children.Add((New-BakaRow 'Display' 'Choose where the menu bar appears.' $barMonitor))|Out-Null
    $barContent.Children.Add((New-BakaText 'Tray icons (Discord, Steam, and others) are one click away: the arrow at the right of the menu bar shows the Windows tray for a few seconds. Notifications still come from Windows.' 11 'Normal' $script:mutedBrush))|Out-Null
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

    # System: power plan and the BAKA maintenance tools (no PowerShell window, no desktop shortcuts).
    $systemTab=[System.Windows.Controls.TabItem]::new();$systemTab.Header='System';$systemScroll=[System.Windows.Controls.ScrollViewer]::new();$systemScroll.VerticalScrollBarVisibility=[System.Windows.Controls.ScrollBarVisibility]::Auto
    $systemContent=[System.Windows.Controls.StackPanel]::new();$systemContent.Margin=[System.Windows.Thickness]::new(14)
    $systemContent.Children.Add((New-BakaHeading 'Power and maintenance' 'Everything BAKA installs is managed here. Tools run in the background and report back when they finish.'))|Out-Null
    $planInfo=New-BakaText ('BAKA Gaming power plan: {0}' -f ((@(if($script:powerModuleAvailable){Get-BakaPowerPlanTweaks|ForEach-Object Purpose}) -join '  ·  '))) 10 'Normal' $script:mutedBrush;$planInfo.Margin=[System.Windows.Thickness]::new(0,0,0,8)
    $systemContent.Children.Add($planInfo)|Out-Null
    $systemPower=[System.Windows.Controls.WrapPanel]::new()
    $systemPower.Children.Add((New-BakaActionButton 'Use BAKA Gaming plan' {if($script:powerModuleAvailable){Set-BakaPowerPlanChoice (Get-BakaPowerPlanGuid)}} ([string][char]0xE945)))|Out-Null
    $systemPower.Children.Add((New-BakaActionButton 'Use Balanced plan' {if($script:powerModuleAvailable){Set-BakaPowerPlanChoice (Get-BakaBalancedPowerPlanGuid)}} ([string][char]0xE83F)))|Out-Null
    $systemPower.Children.Add((New-BakaActionButton 'Power Options' {Start-Process -FilePath (Join-Path $env:WINDIR 'System32\control.exe') -ArgumentList 'powercfg.cpl'|Out-Null} ([string][char]0xE7E8)))|Out-Null
    $systemContent.Children.Add($systemPower)|Out-Null
    $systemContent.Children.Add((New-BakaText 'Tools' 12 'Bold'))|Out-Null
    foreach($tool in @(
        @{Label='Reinstall Baka Browser';Script='Install-SelectedApps.ps1';Glyph=[string][char]0xE774;Copy='Installs or repairs Baka Browser from the copy inside BAKA and makes it the default browser at the next sign-in.'},
        @{Label='Install hardware drivers';Script='Install-SelectedDrivers.ps1';Glyph=[string][char]0xE964;Copy='Detects your hardware and installs only reviewed, vendor-signed driver packages.'},
        @{Label='Restore Windows Update';Script='Restore-WindowsUpdate.ps1';Glyph=[string][char]0xE895;Copy='Turns Windows Update back on. Asks for administrator approval.'},
        @{Label='Restore BAKA system tuning';Script='Restore-SystemTuning.ps1';Glyph=[string][char]0xE777;Copy='Undoes BAKA service, task, privacy, power plan, and default-browser changes. Asks for administrator approval.'}
    )){
        $button=New-BakaActionButton $tool.Label {param($sender,$eventArgs)[void](Invoke-BakaTool ([string]$sender.Tag))} $tool.Glyph;$button.Tag=$tool.Script;$button.MinWidth=230;$button.HorizontalContentAlignment=[System.Windows.HorizontalAlignment]::Left
        $systemContent.Children.Add((New-BakaRow $tool.Label $tool.Copy $button))|Out-Null
    }
    $systemContent.Children.Add((New-BakaText 'Windows shell' 12 'Bold'))|Out-Null
    $shellButtons=[System.Windows.Controls.WrapPanel]::new()
    $shellButtons.Children.Add((New-BakaActionButton 'Use BAKA as the Windows shell' {Enable-BakaShellReplacement} ([string][char]0xE7F4)))|Out-Null
    $shellButtons.Children.Add((New-BakaActionButton 'Return to the Windows shell' {Restore-BakaWindowsShell} ([string][char]0xE777)))|Out-Null
    $systemContent.Children.Add($shellButtons)|Out-Null
    $systemContent.Children.Add((New-BakaText 'As the shell, BAKA replaces the Windows taskbar, Start menu, and desktop completely; Explorer does not run. Recovery: Ctrl+Alt+Shift+E, or Ctrl+Alt+Del > Task Manager > Run "explorer".' 10 'Normal' $script:mutedBrush))|Out-Null
    $systemScroll.Content=$systemContent;$systemTab.Content=$systemScroll;$tabs.Items.Add($systemTab)|Out-Null

    $footer=[System.Windows.Controls.WrapPanel]::new();$footer.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Right
    $save=New-BakaActionButton 'Save changes' {try{Save-BakaSettingsDraft}catch{[System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Settings not saved',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)|Out-Null}} ([string][char]0xE74E)
    $reset=New-BakaActionButton 'Reset defaults' {if([System.Windows.Forms.MessageBox]::Show('Reset BAKA appearance, dock, bar, and widget settings to the reviewed defaults?','Reset BAKA settings',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Question) -eq [System.Windows.Forms.DialogResult]::Yes){$script:config=Get-BakaDefaultDesktopConfiguration;$script:wallpaperDirty=$true;$script:widgetUserVisible=[bool]$script:config.widgets.enabled;$script:settingsDirty=$true;Invoke-BakaSettingsRefresh;[System.Windows.Forms.MessageBox]::Show('Defaults are previewed. Choose Save changes to persist them.','BAKA settings',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)|Out-Null}} ([string][char]0xE777)
    $restore=New-BakaActionButton 'Restore previous' {try{$previous=Get-Content -LiteralPath ($script:settingsPath+'.bak') -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop;$valid=Test-BakaDesktopConfiguration $previous;if(-not $valid.Valid){throw ($valid.Errors -join ' ')};$script:config=Complete-BakaDesktopConfiguration -Configuration $previous;$script:wallpaperDirty=$true;$script:widgetUserVisible=[bool]$script:config.widgets.enabled;$script:settingsDirty=$true;Invoke-BakaSettingsRefresh;[System.Windows.Forms.MessageBox]::Show('Previous settings are previewed. Choose Save changes to keep them.','BAKA settings',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)|Out-Null}catch{[System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Previous settings unavailable',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning)|Out-Null}} ([string][char]0xE777)
    $export=New-BakaActionButton 'Export' { $dialog=[System.Windows.Forms.SaveFileDialog]::new();$dialog.Filter='BAKA settings (*.json)|*.json';$dialog.FileName='baka-desktop-settings.json';if($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){Export-BakaDesktopConfiguration -Path $dialog.FileName -Configuration $script:config|Out-Null}} ([string][char]0xE74E)
    $import=New-BakaActionButton 'Import' { try{$dialog=[System.Windows.Forms.OpenFileDialog]::new();$dialog.Filter='BAKA settings (*.json)|*.json';if($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){$candidate=Get-Content -LiteralPath $dialog.FileName -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop;$valid=Test-BakaDesktopConfiguration $candidate;if(-not $valid.Valid){throw ($valid.Errors -join ' ')};$script:config=Complete-BakaDesktopConfiguration -Configuration $candidate;$script:wallpaperDirty=$true;$script:widgetUserVisible=[bool]$script:config.widgets.enabled;$script:settingsDirty=$true;Invoke-BakaSettingsRefresh}}catch{[System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Settings import failed',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning)|Out-Null} } ([string][char]0xE8B5)
    foreach($button in @($import,$export,$restore,$reset,$save)){$footer.Children.Add($button)|Out-Null}
    [System.Windows.Controls.Grid]::SetRow($footer,2);$layout.Children.Add($footer)|Out-Null
    Set-BakaSettingsControlTheme $layout
    Set-BakaWindowContent $window $layout;Set-BakaCompactScale $window 0.85;$script:windows.Settings=$window
    $window.add_Closing({param($sender,$eventArgs) if(-not $script:allowShutdown -and -not $script:allowSettingsClose){$eventArgs.Cancel=$true;Close-BakaSettings}})
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
    if($window.IsVisible -and -not $script:smokeTestMode){Hide-BakaWindow $window;return}
    # Drops down from the menu bar on the right, like Control Center.
    $area=(Get-BakaActiveScreen).WorkingArea;$scale=Get-BakaScreenScale
    # Always below the menu bar, even when the bar's edge reservation is not active (preview, first frame).
    $barBottom=if($script:windows.TopBar -and $script:windows.TopBar.IsVisible){$script:windows.TopBar.Top+$script:windows.TopBar.ActualHeight}else{$area.Top/$scale}
    $window.Height=[math]::Min(600,$area.Bottom/$scale-$barBottom-20)
    $window.Left=$area.Right/$scale-$window.Width-10;$window.Top=[math]::Max($area.Top/$scale,$barBottom)+8
    Update-BakaVolumeControls;Update-BakaPowerPlanState
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
        if($script:config.topBar.showDate){$script:windows.BarClock.Text=Get-Date -Format 'ddd d MMM  HH:mm'}else{$script:windows.BarClock.Text=Get-Date -Format 'HH:mm'}
    }
    $script:clockTicks=[int]$script:clockTicks+1
    Update-BakaForegroundApp
    if($script:clockTicks % 2 -eq 0){Update-BakaTaskbarGuard}
    if($script:clockTicks % 3 -eq 0 -and $script:windows.BarVolumeGlyph){try{$volume=Get-BakaVolume;$script:windows.BarVolumeGlyph.Text=if($volume.Muted -or $volume.Level -eq 0){[string][char]0xE74F}elseif($volume.Level -lt 34){[string][char]0xE993}elseif($volume.Level -lt 67){[string][char]0xE994}else{[string][char]0xE995}}catch{}}
    if($script:openSettingsRequest -and (Test-Path -LiteralPath $script:openSettingsRequest -PathType Leaf)){Remove-Item -LiteralPath $script:openSettingsRequest -Force -ErrorAction SilentlyContinue;Show-BakaSettings}
    if($script:widgetWindows.ContainsKey('clockTime') -and $script:widgetWindows['clockTime'].IsVisible){$script:widgetWindows['clockTime'].Text=Get-Date -Format 'HH:mm';$script:widgetWindows['clockDate'].Text=Get-Date -Format 'dddd, d MMMM yyyy'}
    if($script:windows.BarNetwork){
        $online=[System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()
        $script:windows.BarNetwork.Text=if($online){'ONLINE'}else{'OFFLINE'}
        if($script:windows.BarNetworkGlyph){$script:windows.BarNetworkGlyph.Text=if($online){[string][char]0xE774}else{[string][char]0xF384};$script:windows.BarNetworkGlyph.Opacity=if($online){1.0}else{0.55}}
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
        # As the shell, exiting would leave an empty screen: hand the session back to Explorer instead.
        if($script:shellMode){Restore-BakaWindowsShell -Quiet;return}
        $script:app.Shutdown(0)
    } catch {
        Write-BakaUiLog ('exit-blocked profile-restore-failed error="{0}"' -f $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show(('BAKA kept running because it could not restore your prior desktop settings.`r`n`r`n{0}' -f $_.Exception.Message),'BAKA safe exit',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)|Out-Null
    }
}
# ---- Shell mode: BAKA is the Windows shell (Explorer's taskbar, Start, and desktop never load) ----
$script:shellRegistryPath='HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon'
function Test-BakaShellMode {
    # True when BAKA runs as the shell: no Explorer process owns the desktop or taskbar in this session.
    if($script:previewMode){return $false}
    $session=(Get-Process -Id $PID).SessionId
    return (@(Get-Process -Name explorer -ErrorAction SilentlyContinue|Where-Object {$_.SessionId -eq $session}).Count -eq 0)
}
function Get-BakaShellCommand {
    # The windowless native launcher, never powershell.exe directly: on Windows 11 a console program as the
    # shell opens a visible Windows Terminal window, and nothing would restart BAKA if it stopped.
    return ('"{0}"' -f (Join-Path $dataRoot 'Scripts\BakaShell.exe'))
}
function Restore-BakaWindowsShell([switch]$Quiet){
    # Recovery (Ctrl+Alt+Shift+E or BAKA menu): Explorer becomes the shell again, now and at every sign-in.
    if($script:previewMode){Write-BakaUiLog 'shell-restore-preview';return}
    try{Remove-ItemProperty -LiteralPath $script:shellRegistryPath -Name 'Shell' -ErrorAction SilentlyContinue}catch{}
    try{$script:config.taskbar.autoHideWindowsTaskbar=$false;Save-BakaDesktopConfiguration -Path $script:settingsPath -Configuration $script:config|Out-Null}catch{}
    Write-BakaUiLog 'shell-restored-to-explorer'
    if(Test-BakaShellMode){Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe')|Out-Null}
    if(-not $Quiet){[System.Windows.Forms.MessageBox]::Show('The Windows shell (Explorer, taskbar, Start) is back. Turn BAKA shell on again in BAKA Settings > System.','BAKA','OK','Information')|Out-Null}
    $script:allowShutdown=$true;$script:app.Shutdown(0)
}
function Enable-BakaShellReplacement {
    if($script:previewMode){Write-BakaUiLog 'shell-enable-preview';return}
    if(-not (Test-Path -LiteralPath (Join-Path $dataRoot 'Scripts\BakaShell.exe') -PathType Leaf)){[System.Windows.Forms.MessageBox]::Show('The BAKA shell launcher is missing; Explorer stays the shell.','BAKA','OK','Warning')|Out-Null;return}
    if(-not (Test-Path -LiteralPath $script:shellRegistryPath)){New-Item -Path $script:shellRegistryPath -Force|Out-Null}
    New-ItemProperty -LiteralPath $script:shellRegistryPath -Name 'Shell' -PropertyType String -Value (Get-BakaShellCommand) -Force|Out-Null
    Write-BakaUiLog 'shell-replacement-enabled'
    [System.Windows.Forms.MessageBox]::Show('BAKA will be the Windows shell from the next sign-in. Recovery: Ctrl+Alt+Shift+E brings Explorer back.','BAKA','OK','Information')|Out-Null
}
function Invoke-BakaStartupApps {
    # Without Explorer nobody runs the Run keys and Startup folders (Discord, Steam, drivers). BAKA does,
    # once per sign-in; HKCU\Volatile Environment is cleared at sign-out, so it is the per-session marker.
    if($script:previewMode){return}
    $volatile='HKCU:\Volatile Environment'
    if((Get-ItemProperty -LiteralPath $volatile -Name 'BakaStartupDone' -ErrorAction SilentlyContinue).BakaStartupDone){return}
    New-ItemProperty -LiteralPath $volatile -Name 'BakaStartupDone' -PropertyType String -Value '1' -Force|Out-Null
    $started=0
    foreach($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run','HKCU:\Software\Microsoft\Windows\CurrentVersion\Run')){
        $item=Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if(-not $item){continue}
        foreach($property in @($item.PSObject.Properties|Where-Object {$_.Name -notlike 'PS*'})){
            $command=[Environment]::ExpandEnvironmentVariables([string]$property.Value)
            if([string]::IsNullOrWhiteSpace($command) -or $command -match 'BakaCompanion\.ps1'){continue}
            try{Start-Process -FilePath (Join-Path $env:WINDIR 'System32\cmd.exe') -ArgumentList ('/c start "" '+$command) -WindowStyle Hidden|Out-Null;$started++}catch{Write-BakaUiLog ('startup-run-failed name="{0}" error="{1}"' -f $property.Name,$_.Exception.Message)}
        }
    }
    foreach($folder in @([Environment]::GetFolderPath('Startup'),[Environment]::GetFolderPath('CommonStartup'))){
        foreach($entry in @(Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue|Where-Object {$_.Name -ne 'BAKA Liquid Desktop.lnk' -and $_.Extension -ne '.ini'})){
            try{Start-Process -FilePath $entry.FullName|Out-Null;$started++}catch{Write-BakaUiLog ('startup-item-failed name="{0}" error="{1}"' -f $entry.Name,$_.Exception.Message)}
        }
    }
    Write-BakaUiLog ('shell-startup-apps started={0}' -f $started)
}
function Update-BakaDesktopBackground {
    # In shell mode there is no Explorer desktop, so BAKA draws the wallpaper (image, color, or video).
    $window=$script:windows.Desktop
    if(-not $window){return}
    $settings=$script:config.wallpaper
    $path=[Environment]::ExpandEnvironmentVariables([string]$settings.path)
    $stretch=switch([string]$settings.fit){'Fit'{[System.Windows.Media.Stretch]::Uniform}'Stretch'{[System.Windows.Media.Stretch]::Fill}'Center'{[System.Windows.Media.Stretch]::None}default{[System.Windows.Media.Stretch]::UniformToFill}}
    $mode=[string]$settings.mode
    if($mode -eq 'Default' -or ($mode -in @('Image','Video') -and -not (Test-Path -LiteralPath $path -PathType Leaf))){$mode='Image';$path=Get-BakaShippedWallpaperPath}
    if($mode -eq 'Color'){$window.Content=$null;$window.Background=New-BakaBrush ([string]$settings.color) 255}
    elseif($mode -eq 'Video'){
        $media=[System.Windows.Controls.MediaElement]::new();$media.LoadedBehavior=[System.Windows.Controls.MediaState]::Manual;$media.IsMuted=[bool]$settings.muted;$media.Stretch=$stretch;$media.Source=[Uri]::new($path)
        $media.Add_MediaEnded({param($sender,$eventArgs)$sender.Position=[TimeSpan]::Zero;$sender.Play()})
        $window.Background=[System.Windows.Media.Brushes]::Black;$window.Content=$media;$media.Play()
        $script:videoWallpaper=@{Window=$null;Media=$media;Path=$path}
    }else{
        $image=[System.Windows.Controls.Image]::new();$image.Stretch=$stretch
        if($path){try{$bitmap=[System.Windows.Media.Imaging.BitmapImage]::new();$bitmap.BeginInit();$bitmap.CacheOption=[System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad;$bitmap.UriSource=[Uri]::new($path);$bitmap.EndInit();$bitmap.Freeze();$image.Source=$bitmap}catch{Write-BakaUiLog ('desktop-image-failed error="{0}"' -f $_.Exception.Message)}}
        $window.Background=New-BakaBrush ([string]$settings.color) 255;$window.Content=$image
    }
    Write-BakaUiLog ('desktop-background mode={0}' -f $mode)
}
function New-BakaDesktopWindow {
    $screen=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds;$scale=Get-BakaScreenScale
    $window=[System.Windows.Window]::new();$window.Title='BAKA Desktop';$window.WindowStyle=[System.Windows.WindowStyle]::None;$window.ResizeMode=[System.Windows.ResizeMode]::NoResize
    $window.ShowInTaskbar=$false;$window.ShowActivated=$false;$window.Left=$screen.Left/$scale;$window.Top=$screen.Top/$scale;$window.Width=$screen.Width/$scale;$window.Height=$screen.Height/$scale
    $window.add_SourceInitialized({param($sender,$eventArgs)Set-BakaWindowBottom $sender})
    $window.add_Activated({param($sender,$eventArgs)Set-BakaWindowBottom $sender})
    $window.add_MouseRightButtonUp({param($sender,$eventArgs)Show-BakaMenu $sender @(
        @{Label='Change wallpaper…';Glyph=[string][char]0xE771;Action={Show-BakaSettings 'Wallpaper'}},
        @{Label='Open Files';Glyph=[string][char]0xE8B7;Action={Show-BakaFiles}},
        @{Label='All apps';Glyph=[string][char]0xE71D;Action={Show-BakaLaunchpad}},
        '-',
        @{Label='Windows Settings';Glyph=[string][char]0xE713;Action={Open-BakaSystemSettings 'ms-settings:'}}
    )})
    $window.add_Closing({param($sender,$eventArgs)if(-not $script:allowShutdown){$eventArgs.Cancel=$true}})
    $script:windows.Desktop=$window
    Update-BakaDesktopBackground
    $window.Show()
    return $window
}
function Set-BakaWindowBottom($Window){
    try{$handle=[System.Windows.Interop.WindowInteropHelper]::new($Window).Handle;if($handle -ne [IntPtr]::Zero){[void][BakaShellKeys]::SetWindowPos($handle,[IntPtr]::new(1),0,0,0,0,0x0013)}}catch{}
}
if(-not ('BakaShellKeys' -as [type])){
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BakaShellKeys {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll", SetLastError=true)] static extern IntPtr SetWindowsHookEx(int id, HookProc proc, IntPtr module, uint thread);
  [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hook);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name);
  delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  static HookProc proc; static IntPtr hook = IntPtr.Zero; static bool winDown, winUsed;
  public static volatile int Pending; // incremented when the Windows key is tapped alone
  public static volatile bool Enabled = true;
  // Low-level keyboard hook: a lone tap of the Windows key opens the BAKA launcher in shell mode.
  public static bool Install() {
    if (hook != IntPtr.Zero) return true;
    proc = Callback; hook = SetWindowsHookEx(13, proc, GetModuleHandle(null), 0);
    return hook != IntPtr.Zero;
  }
  public static void Remove() { if (hook != IntPtr.Zero) { UnhookWindowsHookEx(hook); hook = IntPtr.Zero; } }
  static IntPtr Callback(int code, IntPtr wParam, IntPtr lParam) {
    if (code >= 0) {
      int vk = Marshal.ReadInt32(lParam); int msg = wParam.ToInt32(); bool down = msg == 0x100 || msg == 0x104; bool up = msg == 0x101 || msg == 0x105;
      int flags = Marshal.ReadInt32(lParam, 8);
      bool injected = (flags & 0x10) != 0;
      if (vk == 0x5B || vk == 0x5C) {
        if (down) { if (!winDown) { winDown = true; winUsed = false; } }
        else if (up) {
          bool lone = winDown && !winUsed && Enabled; winDown = false;
          if (lone) {
            // A harmless unassigned key (0xE8) between Win-down and Win-up tells Windows the key was
            // "used", so Start does not open. The Win-up itself passes through: never swallow it, or
            // Windows keeps Win logically held down and every later key becomes a Win shortcut.
            keybd_event(0xE8, 0, 0, UIntPtr.Zero); keybd_event(0xE8, 0, 2, UIntPtr.Zero);
            Pending++;
          }
        }
      } else if (down && winDown && !injected) { winUsed = true; }
    }
    return CallNextHookEx(hook, code, wParam, lParam);
  }
}
'@ -ErrorAction Stop
}
function Initialize-BakaShellMode {
    $script:shellMode=Test-BakaShellMode
    if(-not $script:shellMode){return}
    Write-BakaUiLog 'shell-mode=active (Explorer is not running)'
    [void](New-BakaDesktopWindow)
    Invoke-BakaStartupApps
}
function Initialize-BakaWindowsKey {
    # The Windows key opens the BAKA launcher, as the shell and with Explorer running. Win+other keys
    # (Win+E, Win+R, Win+D, Win+Tab...) keep working; Ctrl+Esc still opens the Windows Start menu.
    if($script:previewMode){return}
    if(-not [BakaShellKeys]::Install()){Write-BakaUiLog 'win-key-hook-unavailable';return}
    $script:winKeyTimer=[System.Windows.Threading.DispatcherTimer]::new();$script:winKeyTimer.Interval=[TimeSpan]::FromMilliseconds(60);$script:winKeySeen=[BakaShellKeys]::Pending
    $script:winKeyTimer.Add_Tick({
        # No polling cost during games: the launcher never opens over a running game.
        [BakaShellKeys]::Enabled=($script:activeProfile -eq 'Desktop')
        if([BakaShellKeys]::Pending -ne $script:winKeySeen){$script:winKeySeen=[BakaShellKeys]::Pending;try{Show-BakaLaunchpad}catch{Write-BakaUiLog ('launchpad-open-failed error="{0}"' -f $_.Exception.Message)}}
    })
    $script:winKeyTimer.Start()
    Write-BakaUiLog 'win-key=launcher'
}
function Register-BakaRecoveryHotkey($Window){
    # Ctrl+Alt+Shift+E: always returns to the normal Windows shell, even if BAKA's UI is broken.
    try{
        $source=[System.Windows.Interop.HwndSource]::FromVisual($Window)
        if(-not $source){return}
        if([BakaLiquidNative]::RegisterHotKey($source.Handle,0xBA6A,7,0x45)){
            $source.AddHook([System.Windows.Interop.HwndSourceHook]{param($hwnd,$msg,$wParam,$lParam,[ref]$handled)if($msg -eq 0x0312 -and $wParam.ToInt32() -eq 0xBA6A){$handled.Value=$true;Restore-BakaWindowsShell};[IntPtr]::Zero})
            Write-BakaUiLog 'recovery-hotkey=Ctrl+Alt+Shift+E'
        }
    }catch{Write-BakaUiLog ('recovery-hotkey-failed error="{0}"' -f $_.Exception.Message)}
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
$script:runningAppsTimer.Add_Tick({param($sender,$eventArgs)try{Update-BakaBrowserRepair;if($script:windows.Dock -and $script:windows.Dock.IsVisible){Update-BakaDockRunningApps;Update-BakaDockIndicators}}catch{Write-BakaUiLog ('running-apps-refresh-failed error="{0}"' -f $_.Exception.Message)}})
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

$script:windows.Dashboard=$null
$script:windows.Dock=New-BakaDock
$script:windows.Quick=$null
$script:windows.TopBar=New-BakaTopBar
$script:windows.Settings=$null
$script:windows.BarProfile=New-BakaText 'DESKTOP' 10 'Normal' $script:accentBrush
$script:windows.BarProfile.Visibility=if($script:config.topBar.showProfile){[System.Windows.Visibility]::Visible}else{[System.Windows.Visibility]::Collapsed}
$script:windows.BarProfile.Margin=[System.Windows.Thickness]::new(12,0,8,0);$script:windows.BarProfile.VerticalAlignment=[System.Windows.VerticalAlignment]::Center
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
    if($script:winKeyTimer){$script:winKeyTimer.Stop()}
    if($script:trimTimer){$script:trimTimer.Stop()}
    try{[BakaShellKeys]::Remove()}catch{}
    Stop-BakaVideoWallpaper
    Remove-BakaTopBarReservation
    Remove-BakaDockReservation
    Restore-BakaTaskbarMode
    if($script:trayIcon){$script:trayIcon.Visible=$false;$script:trayIcon.Dispose()}
    try{[void](Set-BakaCompanionProfile 'Desktop')}catch{Write-BakaUiLog ('shutdown-restore-failed error="{0}"' -f $_.Exception.Message)}
    try{Exit-BakaCompanionInstance -Lock $script:instanceLock}catch{}
    Write-BakaUiLog 'companion-exit-cleanup-complete'
})
$script:windows.Dock.add_Loaded({
    # First sign-in: Explorer started as the shell before BAKA was configured. If BAKA is now the
    # configured shell, Explorer is closed once so this session already runs on the BAKA shell.
    if(-not $script:previewMode){
        try{
            $configured=[string](Get-ItemProperty -LiteralPath $script:shellRegistryPath -Name 'Shell' -ErrorAction SilentlyContinue).Shell
            if($configured -match 'BakaShell\.exe' -and -not (Test-BakaShellMode)){
                $session=(Get-Process -Id $PID).SessionId
                Get-Process -Name explorer -ErrorAction SilentlyContinue|Where-Object {$_.SessionId -eq $session}|Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 800
                Write-BakaUiLog 'shell-takeover explorer-stopped'
            }
        }catch{Write-BakaUiLog ('shell-takeover-failed error="{0}"' -f $_.Exception.Message)}
    }
    Initialize-BakaShellMode
    Initialize-BakaWindowsKey
    Register-BakaRecoveryHotkey $script:windows.Dock
    Start-BakaWindowEntrance $script:windows.Dock
    # Show the Arena welcome once (first run); afterwards it opens only from the dock's Arena button.
    $arenaSeen=Join-Path $settingsDirectory 'arena-welcome-shown'
    if($ArenaSmoke -or (-not $IdleDesktop -and -not (Test-Path -LiteralPath $arenaSeen))){Show-BakaDashboard;try{[IO.File]::WriteAllText($arenaSeen,(Get-Date).ToString('o'))}catch{}}
    if($FileSmoke){$script:windows.Dashboard.Hide();Show-BakaFiles}
    if($script:config.topBar.enabled -and -not $script:autoGame){Show-BakaWindow $script:windows.TopBar}
    if($script:config.widgets.enabled -and $script:widgetUserVisible){Show-BakaWidgets}
    Update-BakaPowerPlanState
    Update-BakaClock;Update-BakaProfileStatus
    $script:profileTimer.Start();$script:clockTimer.Start();$script:runningAppsTimer.Start()
    if(-not $script:previewMode){
        $browserApp=@($script:config.pinnedApps|Where-Object {$_.id -eq 'baka-browser'}|Select-Object -First 1)
        if($browserApp -and -not (Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables([string]$browserApp[0].target)) -PathType Leaf)){Start-BakaBrowserRepair}
    }
    if($OpenSettings){Show-BakaSettings}
    # Startup allocates far more than the desktop needs afterwards; trim once it has settled, then every
    # 10 minutes while nothing BAKA is open.
    $script:trimTimer=[System.Windows.Threading.DispatcherTimer]::new();$script:trimTimer.Interval=[TimeSpan]::FromSeconds(20)
    $script:trimTimer.Add_Tick({param($sender,$eventArgs)
        $sender.Interval=[TimeSpan]::FromMinutes(10)
        $busy=@('Dashboard','Files','Quick','Settings','Launchpad'|Where-Object {$script:windows[$_] -and $script:windows[$_].IsVisible}).Count
        if(-not $busy){Optimize-BakaFootprint $(if($sender.Tag){'idle'}else{'startup'})};$sender.Tag='started'
    })
    $script:trimTimer.Start()
    Invoke-BakaTaskbarMode
    if([string]$script:config.wallpaper.mode -ne 'Default'){Invoke-BakaWallpaper}
    if($script:config.widgets.enabled -and $script:widgetUserVisible){Update-BakaWidgetPolling}
    if($script:config.dock.autoHide -and -not $script:autoGame){$script:dockHideTimer.Start()}
    Write-BakaUiLog ('companion-ready release="{0}" profile={1} theme="{2}" widgets={3}' -f $script:uiRelease,$script:activeProfile,$script:config.appearance.theme,$script:config.widgets.enabled)
    if($script:previewMode -and $CapturePath){
        # Design capture: renders only BAKA surfaces over the BAKA wallpaper (never the user's real desktop).
        # The main file shows Arena and Control Center; -desktop, -launchpad, -settings and -files sit next to it.
        # script: scope, because the timer ticks after the startup code that defines them has returned.
        function script:Save-BakaDesignCapture([string]$Path,[string[]]$Keys){
            try{
                $screen=[System.Windows.SystemParameters]::PrimaryScreenWidth;$screenH=[System.Windows.SystemParameters]::PrimaryScreenHeight
                $visual=[System.Windows.Media.DrawingVisual]::new();$context=$visual.RenderOpen()
                $wallpaper=Get-BakaShippedWallpaperPath
                if($wallpaper){$image=[System.Windows.Media.Imaging.BitmapImage]::new([Uri]::new($wallpaper));$context.DrawImage($image,[System.Windows.Rect]::new(0,0,$screen,$screenH))}
                foreach($key in $Keys){
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
                $stream=[IO.File]::Create($Path);try{$encoder.Save($stream)}finally{$stream.Dispose()}
                Write-BakaUiLog ('design-capture-saved path="{0}"' -f $Path)
            }catch{Write-BakaUiLog ('design-capture-failed path="{0}" error="{1}"' -f $Path,$_.Exception.Message)}
        }
        function script:Get-BakaCapturePath([string]$Suffix){
            $folder=Split-Path -Parent $script:capturePathValue;$name=[IO.Path]::GetFileNameWithoutExtension($script:capturePathValue)
            return (Join-Path $folder ('{0}-{1}.png' -f $name,$Suffix))
        }
        $script:capturePathValue=$CapturePath
        $script:captureTimer=[System.Windows.Threading.DispatcherTimer]::new();$script:captureTimer.Interval=[TimeSpan]::FromSeconds(3);$script:captureStep=0
        $script:captureTimer.Add_Tick({param($sender,$eventArgs)
            $script:captureStep++
            # Any failure ends the capture run instead of leaving a preview desktop open.
            trap {Write-BakaUiLog ('design-capture-step-failed step={0} error="{1}"' -f $script:captureStep,$_.Exception.Message);$sender.Stop();Exit-BakaCompanion;break}
            switch($script:captureStep){
                1 {Show-BakaQuickPanel}
                2 {Save-BakaDesignCapture $script:capturePathValue @('Dashboard','Dock','TopBar','Quick');foreach($k in 'Quick','Dashboard'){if($script:windows[$k]){$script:windows[$k].Hide()}}}
                3 {Save-BakaDesignCapture (Get-BakaCapturePath 'desktop') @('Dock','TopBar');Show-BakaLaunchpad}
                4 {Save-BakaDesignCapture (Get-BakaCapturePath 'launchpad') @('Dock','TopBar','Launchpad');if($script:windows.Launchpad){$script:windows.Launchpad.Hide()};Show-BakaSettings}
                5 {Save-BakaDesignCapture (Get-BakaCapturePath 'settings') @('Dock','TopBar','Settings');$script:allowSettingsClose=$true;if($script:windows.Settings){$script:windows.Settings.Hide()};Show-BakaFiles}
                6 {Save-BakaDesignCapture (Get-BakaCapturePath 'files') @('Dock','TopBar','Files');$sender.Stop();Exit-BakaCompanion}
            }
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
                        if($script:theme.name -ne 'BAKA Carbon' -or -not $script:motionEnabled){throw 'The default BAKA Carbon theme did not enable desktop motion.'}
                        foreach($surfaceKey in @('Dashboard','Dock','Quick','TopBar','Settings')){if(-not $script:windows[$surfaceKey].AllowsTransparency){throw "The $surfaceKey surface is not per-pixel transparent (black corners)."}}
                        $dockTile=@($script:windows.DockAppPanel.Children|Where-Object {$_ -is [System.Windows.Controls.Button]}|Select-Object -First 1)[0].Content
                        if($dockTile.Children[1].Visibility -ne [System.Windows.Visibility]::Collapsed){throw 'Dock icons still show text captions.'}
                        if(-not $script:windows.Dock.Tag.Tag.Light -or -not $script:windows.Dock.Tag.Tag.Rim){throw 'Glass surfaces are missing the liquid light or specular rim.'}
                        Start-BakaDockBounce @($script:windows.DockAppPanel.Children)[0]
                        Write-BakaUiLog 'ui-smoke-stage=liquid-glass-desktop'
                        foreach($chromeKey in @('Dashboard','Quick','Settings')){
                            $frame=$script:windows[$chromeKey].Tag.Tag.Root.Children[0]
                            $lights=@($frame.Children|Where-Object {[System.Windows.Controls.Grid]::GetRow($_) -eq 0})
                            if(-not $lights.Count){throw "The $chromeKey window has no close/hide title strip."}
                        }
                        Write-BakaUiLog 'ui-smoke-stage=window-chrome'
                        if(-not $script:windows.QuickVolume -or -not $script:windows.QuickPowerPanel){throw 'Control Center is missing its volume slider or power plan selector.'}
                        Write-BakaUiLog 'ui-smoke-stage=control-center'
                        if($script:windows.TopBar.Height -gt 40 -or [math]::Abs($script:windows.TopBar.Width-(Get-BakaScreenByName ([string]$script:config.topBar.monitor)).Bounds.Width/(Get-BakaScreenScale)) -gt 2){throw 'The menu bar does not span the top edge of the screen.'}
                        Write-BakaUiLog 'ui-smoke-stage=menu-bar'
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
                        $bounds=(Get-BakaScreenByName ([string]$script:config.topBar.monitor)).Bounds
                        if([math]::Abs([double]$script:windows.TopBar.Top-([double]$bounds.Top/(Get-BakaScreenScale))) -gt 1){throw 'Saving settings did not apply the selected menu-bar monitor position.'}
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
                     7 {
                        $script:windows.Files.Close();if($script:windows.Files.IsVisible){throw 'The Files close light did not close BAKA Files.'};Write-BakaUiLog 'ui-smoke-stage=files-close'
                        Show-BakaLaunchpad
                        if(-not $script:windows.Launchpad -or -not $script:windows.Launchpad.IsVisible -or -not $script:launchpadGrid){throw 'Launchpad window or app grid did not open.'}
                        # Get-StartApps can return nothing in some sessions; only exercise the filter when apps exist.
                        if($script:launchpadGrid.Children.Count -gt 0){
                            $script:launchpadSearch.Text='zzzz-no-such-app';$script:launchpadSearch.Tag='';Update-BakaLaunchpadFilter
                            if(@($script:launchpadGrid.Children|Where-Object {$_.Visibility -eq [System.Windows.Visibility]::Visible}).Count -ne 0){throw 'Launchpad search did not filter the app grid.'}
                        }
                        $script:windows.Launchpad.Hide()
                        Write-BakaUiLog ('ui-smoke-stage=launchpad apps={0}' -f $script:launchpadGrid.Children.Count)
                     }
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
    # Non-zero: the BAKA shell launcher restarts the desktop (or falls back to Explorer after 3 tries).
    exit 1
}
