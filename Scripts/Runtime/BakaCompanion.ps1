[CmdletBinding()]
param([switch]$Preview,[switch]$SmokeTest)
$ErrorActionPreference='Stop'
if($SmokeTest -and -not $Preview){throw 'The UI smoke test requires -Preview so profile and settings changes remain isolated.'}

# BAKA Liquid uses Explorer as the shell and hosts all optional desktop surfaces in one WPF process.
$runtimeRoot=$PSScriptRoot
$scriptsRoot=Split-Path -Parent $runtimeRoot
if((Split-Path -Leaf $runtimeRoot) -ieq 'Runtime' -and (Split-Path -Leaf $scriptsRoot) -ieq 'Scripts'){$dataRoot=Split-Path -Parent $scriptsRoot}else{$dataRoot=$scriptsRoot}
$moduleRoot=Join-Path $dataRoot 'Modules'
$script:previewMode=[bool]$Preview
$script:smokeTestMode=[bool]$SmokeTest
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
$script:dockButtons=@{}
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
    $top=[System.Windows.Media.Color]::FromArgb([byte]34,255,255,255)
    $glint=[System.Windows.Media.Color]::FromArgb([byte]24,255,255,255)
    $mid=[System.Windows.Media.Color]::FromArgb($Opacity,$base.R,$base.G,$base.B)
    $low=[System.Windows.Media.Color]::FromArgb([byte][Math]::Max(110,[int]$Opacity-18),$base.R,$base.G,$base.B)
    $brush.GradientStops.Add([System.Windows.Media.GradientStop]::new($top,0.0))
    $brush.GradientStops.Add([System.Windows.Media.GradientStop]::new($glint,0.16))
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
    foreach($key in @('Dock','Quick','TopBar','Settings')){if($script:windows[$key]){Set-BakaWindowSurface $script:windows[$key];Update-BakaVisualTreeTheme $script:windows[$key] $oldBrushes}}
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
    foreach($key in @('Dock','Quick','TopBar','Settings')){
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
    $surface.Child=$root;$surface.Tag=[pscustomobject]@{ContentHost=$contentHost;Sheen=$sheen;SheenBrush=$sheenBrush;SheenTransform=$sheen.RenderTransform}
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
    if(-not $script:motionEnabled -or $script:theme.name -ne 'BAKA Liquid' -or -not $Window.Tag.Tag.SheenTransform){return}
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
    $surface.BeginAnimation([System.Windows.UIElement]::OpacityProperty,$fade)
    $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty,$scaleAnimation);$scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty,$scaleAnimation)
    $translate.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty,$move)
    $tilt.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty,$tiltAnimation)
    Write-BakaUiLog ('ui-animation=surface-entrance title="{0}" profile={1} intensity={2}' -f $Window.Title,$script:activeProfile,$script:config.appearance.animationIntensity)
    Start-BakaGlassSweep $Window
}
function Show-BakaWindow($Window,[switch]$Activate){
    if(-not $Window){return}
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
function New-BakaButton([string]$Label,[scriptblock]$Action,[string]$Glyph='',[string]$AccessibleLabel=$Label,[switch]$ShowIndicator){
    $button=[System.Windows.Controls.Button]::new();$button.Padding=[System.Windows.Thickness]::new(10,8,10,8);$button.Margin=[System.Windows.Thickness]::new(3)
    $button.Background=[System.Windows.Media.Brushes]::Transparent;$button.BorderThickness=[System.Windows.Thickness]::new(0);$button.Foreground=$script:textBrush
    $button.Cursor=[System.Windows.Input.Cursors]::Hand;$button.ToolTip=$AccessibleLabel
    [System.Windows.Automation.AutomationProperties]::SetName($button,$AccessibleLabel)
    $content=[System.Windows.Controls.StackPanel]::new();$content.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center
    $tileSize=[math]::Max(26,[math]::Min(58,([double]$script:config.dock.iconSize-14)))
    $tile=[System.Windows.Controls.Border]::new();$tile.Width=$tileSize;$tile.Height=$tileSize;$tile.Margin=[System.Windows.Thickness]::new(0,0,0,4);$tile.CornerRadius=[System.Windows.CornerRadius]::new([math]::Min(14,$tileSize*0.28));$tile.Background=$script:surfaceAltBrush;$tile.BorderBrush=$script:borderBrush;$tile.BorderThickness=[System.Windows.Thickness]::new(1)
    $iconText=if([string]::IsNullOrWhiteSpace($Glyph)){$Label.Substring(0,1).ToUpperInvariant()}else{$Glyph}
    $monogram=New-BakaText $iconText ([math]::Max(16,[math]::Min(29,$tileSize*0.52))) 'Bold' $script:accentBrush
    if($Glyph){$monogram.FontFamily=[System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')}
    $monogram.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center;$monogram.VerticalAlignment=[System.Windows.VerticalAlignment]::Center;$tile.Child=$monogram;$content.Children.Add($tile)|Out-Null
    $labelText=New-BakaText $Label 10 'Normal' $script:mutedBrush;$labelText.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Center;$content.Children.Add($labelText)|Out-Null
    if($ShowIndicator){
        $indicator=[System.Windows.Shapes.Ellipse]::new();$indicator.Width=5;$indicator.Height=5;$indicator.Margin=[System.Windows.Thickness]::new(0,2,0,0);$indicator.Fill=$script:accentBrush;$indicator.Opacity=0;$indicator.IsHitTestVisible=$false
        $content.Children.Add($indicator)|Out-Null;$button.Resources.Add('BAKA.RunningIndicator',$indicator)
    }
    $button.Content=$content
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
        else{$tile.BorderBrush=$script:borderBrush;$tile.Background=$script:surfaceAltBrush}
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
    $names=[System.Collections.Generic.List[string]]::new()
    foreach($definition in $script:gameDefinitions){if(Get-Process -Name ([string]$definition.processName) -ErrorAction SilentlyContinue|Select-Object -First 1){$names.Add([string]$definition.processName)}}
    Resolve-BakaDetectedGame -RunningProcessNames $names.ToArray() -Definitions $script:gameDefinitions
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
        $process=Get-BakaProcessForApp $App
        if($process){
            $handle=$process.MainWindowHandle
            if([BakaLiquidNative]::GetForegroundWindow() -eq $handle){[void][BakaLiquidNative]::ShowWindow($handle,6)}
            else{[void][BakaLiquidNative]::ShowWindow($handle,9);[void][BakaLiquidNative]::SetForegroundWindow($handle)}
            return
        }
        if([string]$App.kind -eq 'Uri'){Start-Process -FilePath ([string]$App.target);return}
        $target=[Environment]::ExpandEnvironmentVariables([string]$App.target)
        if(-not (Test-Path -LiteralPath $target -PathType Leaf)){[System.Windows.MessageBox]::Show(('Application target not found:`n{0}' -f $target),[string]$App.name,[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Information)|Out-Null;return}
        if([string]::IsNullOrWhiteSpace([string]$App.arguments)){Start-Process -FilePath $target|Out-Null}else{Start-Process -FilePath $target -ArgumentList ([string]$App.arguments)|Out-Null}
        Write-BakaUiLog ('app-launched id={0}' -f $App.id)
    } catch {Write-BakaUiLog ('app-launch-failed id={0} error="{1}"' -f $App.id,$_.Exception.Message);[System.Windows.MessageBox]::Show($_.Exception.Message,'BAKA launch error',[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error)|Out-Null}
}
function Update-BakaProfileStatus {
    $mode=if($script:manualOverride){'MANUAL'}elseif($script:autoGame -and $script:detectedGame){'AUTO · '+$script:detectedGame.ToUpperInvariant()}else{'DESKTOP'}
    $label='{0}  ·  {1}  ·  BALANCED' -f $mode,$script:activeProfile.ToUpperInvariant()
    foreach($key in @('DockStatus','QuickStatus','BarStatus')){if($script:windows[$key]){$script:windows[$key].Text=$label}}
    if($script:windows.BarProfile -and $script:config.topBar.showProfile){$script:windows.BarProfile.Text=$script:activeProfile.ToUpperInvariant()}
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
        }elseif($previous -ne 'Desktop' -and $script:widgetsVisibleBeforeProfile -and $script:config.widgets.enabled){Show-BakaWidgets;$script:widgetsVisibleBeforeProfile=$false}
        if($script:windows.Dock){Set-BakaDockAppearance;Set-BakaDockPosition}
        Set-BakaTheme $script:config.appearance.theme
        Update-BakaProfileStatus
        Update-BakaDockIndicators
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

function New-BakaDock {
    $window=New-BakaWindow 680 94 'BAKA Liquid Dock' $true
    $window.MinWidth=380;$window.MaxWidth=1200;$window.add_KeyDown({param($sender,$eventArgs) if($eventArgs.Key -eq [System.Windows.Input.Key]::Escape){$sender.Hide()}})
    $row=[System.Windows.Controls.StackPanel]::new();$row.Orientation=[System.Windows.Controls.Orientation]::Horizontal;$row.VerticalAlignment=[System.Windows.VerticalAlignment]::Center
    $brand=[System.Windows.Controls.StackPanel]::new();$brand.Width=114;$brand.Margin=[System.Windows.Thickness]::new(4,0,9,0)
    $brand.Children.Add((New-BakaText 'BAKA' 18 'Bold'))|Out-Null
    $status=New-BakaText 'DESKTOP  ·  BALANCED' 9 'Normal' $script:mutedBrush;$status.Name='DockStatus';$script:windows.DockStatus=$status;$brand.Children.Add($status)|Out-Null
    $row.Children.Add($brand)|Out-Null
    $separator=[System.Windows.Controls.Border]::new();$separator.Width=1;$separator.Height=48;$separator.Background=$script:borderBrush;$separator.Margin=[System.Windows.Thickness]::new(4,0,8,0);$row.Children.Add($separator)|Out-Null
    $appPanel=[System.Windows.Controls.StackPanel]::new();$appPanel.Orientation=[System.Windows.Controls.Orientation]::Horizontal
    foreach($app in @($script:config.pinnedApps)){
        $button=New-BakaButton ([string]$app.name) ({param($sender,$eventArgs)Start-BakaPinnedApp $sender.Tag}) ([string]$app.glyph) ("Launch or focus {0}" -f $app.name) -ShowIndicator
        $button.Tag=$app
        $button.Width=[double]$script:config.dock.iconSize+15;$button.Height=[double]$script:config.dock.iconSize+8;$button.Margin=[System.Windows.Thickness]::new([double]$script:config.dock.spacing/2,0,[double]$script:config.dock.spacing/2,0)
        $script:dockButtons[[string]$app.id]=$button;$appPanel.Children.Add($button)|Out-Null
    }
    $row.Children.Add($appPanel)|Out-Null
    $separator2=[System.Windows.Controls.Border]::new();$separator2.Width=1;$separator2.Height=48;$separator2.Background=$script:borderBrush;$separator2.Margin=[System.Windows.Thickness]::new(6,0,7,0);$row.Children.Add($separator2)|Out-Null
    $quick=New-BakaButton 'Control' {Show-BakaQuickPanel} ([string][char]0xE713) 'Open BAKA Quick Panel';$quick.Width=65;$quick.Height=[double]$script:config.dock.iconSize+8;$row.Children.Add($quick)|Out-Null
    $edit=New-BakaButton 'Customize' {Show-BakaSettings} ([string][char]0xE70F) 'Open desktop settings and editor';$edit.Width=75;$edit.Height=[double]$script:config.dock.iconSize+8;$row.Children.Add($edit)|Out-Null
    Set-BakaWindowContent $window $row
    $window.SizeToContent=[System.Windows.SizeToContent]::Width
    $script:windows.DockAppPanel=$appPanel
    $script:windows.DockUtilityButtons=@($quick,$edit)
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

function New-BakaQuickPanel {
    $window=New-BakaWindow 430 560 'BAKA Quick Panel' $true
    $stack=[System.Windows.Controls.StackPanel]::new();$stack.Margin=[System.Windows.Thickness]::new(4)
    $stack.Children.Add((New-BakaHeading 'Quick Panel' 'BAKA Liquid  ·  Windows remains in control of system security and servicing.'))|Out-Null
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
        $link=New-BakaActionButton ([string]$entry.Name) {param($sender,$eventArgs)Open-BakaSystemSettings ([string]$sender.Tag)} ([string]$entry.Glyph)
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
    Set-BakaWindowContent $window $stack;$script:windows.Quick=$window
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
    $systemVisible=$script:activeProfile -eq 'Desktop' -and $script:widgetWindows.ContainsKey('system') -and $script:widgetWindows['system'].IsVisible
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
                $script:systemMetricsLast=$result;$script:systemMetricsError=''
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
    Invoke-BakaSettingsRefresh;Set-BakaDockAppearance;Write-BakaUiLog 'desktop-settings-saved'
}
function Close-BakaSettings {
    if($script:settingsDirty){
        $choice=[System.Windows.Forms.MessageBox]::Show('Save the current BAKA desktop changes before closing?','Unsaved BAKA settings',[System.Windows.Forms.MessageBoxButtons]::YesNoCancel,[System.Windows.Forms.MessageBoxIcon]::Question)
        if($choice -eq [System.Windows.Forms.DialogResult]::Cancel){return}
        if($choice -eq [System.Windows.Forms.DialogResult]::Yes){try{Save-BakaSettingsDraft}catch{[System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Settings not saved',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)|Out-Null;return}}
        else{$script:config=Copy-BakaSettings $script:settingsOriginal;$script:settingsDirty=$false;$script:widgetUserVisible=[bool]$script:config.widgets.enabled;Invoke-BakaSettingsRefresh;Update-BakaSettingsControls;Write-BakaUiLog 'desktop-settings-draft-discarded'}
    }
    if($script:windows.Settings){$script:windows.Settings.Hide()}
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
            $button=New-BakaButton ([string]$app.name) ({param($sender,$eventArgs)Start-BakaPinnedApp $sender.Tag}) ([string]$app.glyph) ("Launch or focus {0}" -f $app.name) -ShowIndicator
            $button.Tag=$app
            $button.Width=[double]$script:config.dock.iconSize+15;$button.Height=[double]$script:config.dock.iconSize+8;$button.Margin=[System.Windows.Thickness]::new([double]$script:config.dock.spacing/2,0,[double]$script:config.dock.spacing/2,0)
            if(Get-BakaProcessForApp $app){$button.BorderBrush=$script:accentBrush;$button.BorderThickness=[System.Windows.Thickness]::new(0,0,0,2)}
            $script:dockButtons[[string]$app.id]=$button;$script:windows.DockAppPanel.Children.Add($button)|Out-Null
        }
    }
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
    $appsList=[System.Windows.Controls.ListBox]::new();$appsList.Height=132;$appsList.Margin=[System.Windows.Thickness]::new(0,8,0,4);$appsList.DisplayMemberPath='name';$appsList.ItemsSource=@($script:config.pinnedApps);$appsList.Background=$script:surfaceAltBrush;$appsList.Foreground=$script:textBrush
    $dockContent.Children.Add((New-BakaText 'Pinned apps' 12 'Bold'))|Out-Null;$dockContent.Children.Add($appsList)|Out-Null
    $appActions=[System.Windows.Controls.WrapPanel]::new()
    $addApp=New-BakaActionButton 'Add application' {param($sender,$eventArgs)$appsList=$sender.Tag;$dialog=[System.Windows.Forms.OpenFileDialog]::new();$dialog.Filter='Applications (*.exe)|*.exe';$dialog.Title='Choose an application to pin';if($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){$base=[IO.Path]::GetFileNameWithoutExtension($dialog.FileName);$id=$base.ToLowerInvariant()+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6);$script:config.pinnedApps=@($script:config.pinnedApps)+@([pscustomobject]@{id=$id;name=$base;kind='Executable';target=$dialog.FileName;arguments='';processName=$base;glyph=[string][char]0xE8A5});$appsList.ItemsSource=@($script:config.pinnedApps);$script:settingsDirty=$true}} ([string][char]0xE8A5)
    $addApp.Tag=$appsList
    $removeApp=New-BakaActionButton 'Remove selected' {param($sender,$eventArgs)$appsList=$sender.Tag;$selected=$appsList.SelectedItem;if($selected){$script:config.pinnedApps=@($script:config.pinnedApps|Where-Object {$_.id -ne $selected.id});$appsList.ItemsSource=@($script:config.pinnedApps);$script:settingsDirty=$true}} ([string][char]0xE74D)
    $removeApp.Tag=$appsList
    $appActions.Children.Add($addApp)|Out-Null;$appActions.Children.Add($removeApp)|Out-Null;$dockContent.Children.Add($appActions)|Out-Null
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
    $reset=New-BakaActionButton 'Reset defaults' {if([System.Windows.Forms.MessageBox]::Show('Reset BAKA appearance, dock, bar, and widget settings to the reviewed defaults?','Reset BAKA settings',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Question) -eq [System.Windows.Forms.DialogResult]::Yes){$script:config=Get-BakaDefaultDesktopConfiguration;$script:widgetUserVisible=[bool]$script:config.widgets.enabled;$script:settingsDirty=$true;Invoke-BakaSettingsRefresh;[System.Windows.Forms.MessageBox]::Show('Defaults are previewed. Choose Save changes to persist them.','BAKA settings',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)|Out-Null}} ([string][char]0xE777)
    $restore=New-BakaActionButton 'Restore previous' {try{$previous=Get-Content -LiteralPath ($script:settingsPath+'.bak') -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop;$valid=Test-BakaDesktopConfiguration $previous;if(-not $valid.Valid){throw ($valid.Errors -join ' ')};$script:config=$previous;$script:widgetUserVisible=[bool]$script:config.widgets.enabled;$script:settingsDirty=$true;Invoke-BakaSettingsRefresh;[System.Windows.Forms.MessageBox]::Show('Previous settings are previewed. Choose Save changes to keep them.','BAKA settings',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)|Out-Null}catch{[System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Previous settings unavailable',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning)|Out-Null}} ([string][char]0xE777)
    $export=New-BakaActionButton 'Export' { $dialog=[System.Windows.Forms.SaveFileDialog]::new();$dialog.Filter='BAKA settings (*.json)|*.json';$dialog.FileName='baka-desktop-settings.json';if($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){Export-BakaDesktopConfiguration -Path $dialog.FileName -Configuration $script:config|Out-Null}} ([string][char]0xE74E)
    $import=New-BakaActionButton 'Import' { try{$dialog=[System.Windows.Forms.OpenFileDialog]::new();$dialog.Filter='BAKA settings (*.json)|*.json';if($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){$candidate=Get-Content -LiteralPath $dialog.FileName -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop;$valid=Test-BakaDesktopConfiguration $candidate;if(-not $valid.Valid){throw ($valid.Errors -join ' ')};$script:config=$candidate;$script:widgetUserVisible=[bool]$script:config.widgets.enabled;$script:settingsDirty=$true;Invoke-BakaSettingsRefresh}}catch{[System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Settings import failed',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning)|Out-Null} } ([string][char]0xE8B5)
    foreach($button in @($import,$export,$restore,$reset,$save)){$footer.Children.Add($button)|Out-Null}
    [System.Windows.Controls.Grid]::SetRow($footer,2);$layout.Children.Add($footer)|Out-Null
    Set-BakaSettingsControlTheme $layout
    Set-BakaWindowContent $window $layout;$script:windows.Settings=$window
    $window.add_Closing({param($sender,$eventArgs) if(-not $script:allowShutdown -and -not $script:allowSettingsClose){$eventArgs.Cancel=$true;Close-BakaSettings}})
    $window.add_KeyDown({param($sender,$eventArgs) if($eventArgs.Key -eq [System.Windows.Input.Key]::Escape){Close-BakaSettings}})
    $script:settingsTabs=$tabs
    $tabs.Add_SelectionChanged({param($sender,$eventArgs)if($sender -is [System.Windows.Controls.TabControl]){foreach($tabItem in $sender.Items){if($tabItem.IsSelected){$tabItem.Foreground=(New-BakaBrush '#17191E' 255)}else{$tabItem.Foreground=$script:textBrush}}}})
    foreach($tabItem in $tabs.Items){if($tabItem.IsSelected){$tabItem.Foreground=(New-BakaBrush '#17191E' 255)}else{$tabItem.Foreground=$script:textBrush}}
    $script:settingsControls=@{Theme=$themeCombo;Accent=$accentInput;Glass=$glass;Motion=$motion;ReducedMotion=$reducedMotion;DockSize=$size;DockSpacing=$spacing;DockAlignment=$align;DockMonitor=$monitorCombo;DockAutoHide=$autoHide;DockMagnify=$magnify;PinnedApps=$appsList;BarEnabled=$barEnabled;BarProfile=$barStatus;BarDate=$barDate;BarMonitor=$barMonitor;WidgetsEnabled=$widgetMaster;WidgetChecks=$widgetChecks;WidgetRefresh=$refresh}
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
    $window.Left=$area.Right-$window.Width-22;$window.Top=$area.Bottom-$window.Height-124
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
$script:systemMetricsTimer.Add_Tick({param($sender,$eventArgs)if($script:activeProfile -eq 'Desktop' -and $script:widgetWindows.ContainsKey('system') -and $script:widgetWindows['system'].IsVisible){Start-BakaMetricRead}else{$sender.Stop()}})
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
    foreach($timer in @($script:dockHideTimer,$script:clockTimer,$script:systemMetricsTimer,$script:profileTimer,$script:smokeTimer)){if($timer){$timer.Stop()}}
    Stop-BakaMetricWorker
    if($script:trayIcon){$script:trayIcon.Visible=$false;$script:trayIcon.Dispose()}
    try{[void](Set-BakaCompanionProfile 'Desktop')}catch{Write-BakaUiLog ('shutdown-restore-failed error="{0}"' -f $_.Exception.Message)}
    try{Exit-BakaCompanionInstance -Lock $script:instanceLock}catch{}
    Write-BakaUiLog 'companion-exit-cleanup-complete'
})
$script:windows.Dock.add_Loaded({
    Start-BakaWindowEntrance $script:windows.Dock
    if($script:config.topBar.enabled -and -not $script:autoGame){Show-BakaWindow $script:windows.TopBar}
    if($script:config.widgets.enabled -and $script:widgetUserVisible){Show-BakaWidgets}
    Update-BakaClock;Update-BakaProfileStatus
    $script:profileTimer.Start();$script:clockTimer.Start()
    if($script:config.widgets.enabled -and $script:widgetUserVisible){Update-BakaWidgetPolling}
    if($script:config.dock.autoHide -and -not $script:autoGame){$script:dockHideTimer.Start()}
    Write-BakaUiLog ('companion-ready profile={0} theme="{1}" widgets={2}' -f $script:activeProfile,$script:config.appearance.theme,$script:config.widgets.enabled)
    if($script:smokeTestMode){
        $script:smokeStage=0
        $script:smokeTimer=[System.Windows.Threading.DispatcherTimer]::new();$script:smokeTimer.Interval=[TimeSpan]::FromMilliseconds(1200)
        $script:smokeTimer.Add_Tick({param($sender,$eventArgs)
            if(-not $script:smokeTestMode){$sender.Stop();return}
            $script:smokeStage++
            try{
                switch($script:smokeStage){
                    1 {
                        Show-BakaQuickPanel;Show-BakaSettings
                        if(-not $script:windows.Dock.IsVisible -or -not $script:windows.Quick.IsVisible -or -not $script:windows.Settings.IsVisible -or -not $script:windows.TopBar -or -not $script:windows.TopBar.IsVisible){throw 'A primary BAKA surface did not become visible.'}
                        if($script:theme.name -ne 'BAKA Liquid' -or -not $script:motionEnabled){throw 'The default BAKA Liquid theme did not enable desktop motion.'}
                        Write-BakaUiLog ('glass-smoke-state opaque={0} fallback={1} dockBackground={2} glassBrush={3} surfaceBrush={4}' -f $script:opaqueMode,$script:dwmBackdropUnsupported,$script:windows.Dock.Tag.Background.GetType().FullName,$script:glassBrush.GetType().FullName,$script:surfaceBrush.GetType().FullName)
                        foreach($surfaceKey in @('Dock','Quick','TopBar','Settings')){
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
}
