Set-StrictMode -Version Latest

# BAKA desktop-shell helpers: user wallpaper (image, solid color, or video behind the desktop icons)
# and the reversible native-taskbar auto-hide used when the BAKA dock acts as the primary launcher.
# Every function here changes only per-user state and can be undone from BAKA Settings.

$script:ImageExtensions=@('.jpg','.jpeg','.jfif','.png','.bmp','.gif','.webp')
$script:VideoExtensions=@('.mp4','.m4v','.mov','.wmv','.avi','.mkv','.webm')
$script:WallpaperStyles=@{ Fill=@{Style='10';Tile='0'}; Fit=@{Style='6';Tile='0'}; Stretch=@{Style='2';Tile='0'}; Center=@{Style='0';Tile='0'}; Span=@{Style='22';Tile='0'} }

function Initialize-BakaDesktopShellNative {
    if('BakaDesktopShellNative' -as [type]){return}
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BakaDesktopShellNative {
  public delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct APPBARDATA { public int cbSize; public IntPtr hWnd; public uint uCallbackMessage; public uint uEdge; public RECT rc; public IntPtr lParam; }
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)] public static extern bool SystemParametersInfo(uint action, uint param, string value, uint flags);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string className, string windowName);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string className, string windowName);
  [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
  [DllImport("user32.dll")] public static extern IntPtr SetParent(IntPtr child, IntPtr parent);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hwnd, int index);
  [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hwnd, int index, int value);
  [DllImport("user32.dll")] public static extern bool SetSysColors(int count, int[] elements, int[] colors);
  [DllImport("shell32.dll")] public static extern UIntPtr SHAppBarMessage(uint message, ref APPBARDATA data);
  [DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);

  // Returns the WorkerW window that hosts the desktop wallpaper behind the icon view.
  // Windows 11 24H2+ creates it as a child of Progman; earlier builds create a top-level sibling.
  public static IntPtr GetWallpaperHost() {
    IntPtr progman = FindWindow("Progman", null);
    if (progman == IntPtr.Zero) return IntPtr.Zero;
    IntPtr ignored;
    SendMessageTimeout(progman, 0x052C, new IntPtr(0xD), new IntPtr(0x1), 0x0002, 1000, out ignored);
    SendMessageTimeout(progman, 0x052C, IntPtr.Zero, IntPtr.Zero, 0x0002, 1000, out ignored);
    IntPtr child = FindWindowEx(progman, IntPtr.Zero, "WorkerW", null);
    if (child != IntPtr.Zero) return child;
    IntPtr host = IntPtr.Zero;
    EnumWindows(delegate(IntPtr top, IntPtr param) {
      IntPtr view = FindWindowEx(top, IntPtr.Zero, "SHELLDLL_DefView", null);
      if (view != IntPtr.Zero) { host = FindWindowEx(IntPtr.Zero, top, "WorkerW", null); }
      return true;
    }, IntPtr.Zero);
    return host;
  }
}
'@ -ErrorAction Stop
}

function Get-BakaWallpaperKind {
    param([string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){return 'None'}
    $extension=[IO.Path]::GetExtension($Path).ToLowerInvariant()
    if($extension -in $script:ImageExtensions){return 'Image'}
    if($extension -in $script:VideoExtensions){return 'Video'}
    return 'Unsupported'
}

function Get-BakaSupportedWallpaperExtensions {
    [pscustomobject]@{ Image=@($script:ImageExtensions); Video=@($script:VideoExtensions) }
}

function Set-BakaStaticWallpaper {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory)][string]$Path,[ValidateSet('Fill','Fit','Stretch','Center','Span')][string]$Fit='Fill')
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){throw "Wallpaper image not found: $Path"}
    if((Get-BakaWallpaperKind $Path) -ne 'Image'){throw "Unsupported wallpaper image type: $Path"}
    if(-not $PSCmdlet.ShouldProcess($Path,'Set desktop wallpaper')){return $false}
    Initialize-BakaDesktopShellNative
    $desktopKey='HKCU:\Control Panel\Desktop'
    $style=$script:WallpaperStyles[$Fit]
    Set-ItemProperty -LiteralPath $desktopKey -Name WallpaperStyle -Value $style.Style
    Set-ItemProperty -LiteralPath $desktopKey -Name TileWallpaper -Value $style.Tile
    $ok=[BakaDesktopShellNative]::SystemParametersInfo(20,0,(Resolve-Path -LiteralPath $Path).ProviderPath,3)
    if(-not $ok){throw "Windows rejected the wallpaper image: $Path"}
    return $true
}

function Set-BakaSolidColorWallpaper {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory)][ValidatePattern('^#[0-9A-Fa-f]{6}$')][string]$Color)
    if(-not $PSCmdlet.ShouldProcess($Color,'Set solid desktop color')){return $false}
    Initialize-BakaDesktopShellNative
    $r=[Convert]::ToInt32($Color.Substring(1,2),16);$g=[Convert]::ToInt32($Color.Substring(3,2),16);$b=[Convert]::ToInt32($Color.Substring(5,2),16)
    Set-ItemProperty -LiteralPath 'HKCU:\Control Panel\Colors' -Name Background -Value ('{0} {1} {2}' -f $r,$g,$b)
    [void][BakaDesktopShellNative]::SetSysColors(1,[int[]]@(1),[int[]]@($r -bor ($g -shl 8) -bor ($b -shl 16)))
    [void][BakaDesktopShellNative]::SystemParametersInfo(20,0,'',3)
    return $true
}

function Get-BakaWallpaperHostHandle {
    Initialize-BakaDesktopShellNative
    return [BakaDesktopShellNative]::GetWallpaperHost()
}

function Set-BakaWindowAsWallpaper {
    # Re-parents a WPF window handle into the desktop wallpaper host so it renders behind desktop icons.
    param([Parameter(Mandatory)][IntPtr]$Handle,[Parameter(Mandatory)][int]$Left,[Parameter(Mandatory)][int]$Top,[Parameter(Mandatory)][int]$Width,[Parameter(Mandatory)][int]$Height)
    Initialize-BakaDesktopShellNative
    $hostHandle=[BakaDesktopShellNative]::GetWallpaperHost()
    if($hostHandle -eq [IntPtr]::Zero){return $false}
    $style=[BakaDesktopShellNative]::GetWindowLong($Handle,-16)
    $style=[int](($style -band [int]0x7FFFFFFF) -bor [int]0x40000000)  # remove WS_POPUP (high bit), add WS_CHILD
    [void][BakaDesktopShellNative]::SetWindowLong($Handle,-16,$style)
    [void][BakaDesktopShellNative]::SetParent($Handle,$hostHandle)
    [void][BakaDesktopShellNative]::SetWindowPos($Handle,[IntPtr]::Zero,$Left,$Top,$Width,$Height,0x0040 -bor 0x0010)
    return $true
}

function Get-BakaTaskbarAutoHide {
    Initialize-BakaDesktopShellNative
    $data=New-Object BakaDesktopShellNative+APPBARDATA
    $data.cbSize=[Runtime.InteropServices.Marshal]::SizeOf($data)
    $data.hWnd=[BakaDesktopShellNative]::FindWindow('Shell_TrayWnd',$null)
    if($data.hWnd -eq [IntPtr]::Zero){return $null}
    $state=[BakaDesktopShellNative]::SHAppBarMessage(4,[ref]$data).ToUInt32()
    return [bool]($state -band 1)
}

function Set-BakaTaskbarAutoHide {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory)][bool]$Enabled)
    Initialize-BakaDesktopShellNative
    $data=New-Object BakaDesktopShellNative+APPBARDATA
    $data.cbSize=[Runtime.InteropServices.Marshal]::SizeOf($data)
    $data.hWnd=[BakaDesktopShellNative]::FindWindow('Shell_TrayWnd',$null)
    if($data.hWnd -eq [IntPtr]::Zero){return $false}
    if(-not $PSCmdlet.ShouldProcess('Windows taskbar',$(if($Enabled){'Enable auto-hide'}else{'Disable auto-hide'}))){return $false}
    $data.lParam=[IntPtr]$(if($Enabled){1}else{2})
    [void][BakaDesktopShellNative]::SHAppBarMessage(10,[ref]$data)
    return $true
}

function Invoke-BakaStartMenu {
    Initialize-BakaDesktopShellNative
    [BakaDesktopShellNative]::keybd_event(0x5B,0,0,[UIntPtr]::Zero)
    [BakaDesktopShellNative]::keybd_event(0x5B,0,2,[UIntPtr]::Zero)
}

Export-ModuleMember -Function Get-BakaWallpaperKind,Get-BakaSupportedWallpaperExtensions,Set-BakaStaticWallpaper,Set-BakaSolidColorWallpaper,Get-BakaWallpaperHostHandle,Set-BakaWindowAsWallpaper,Get-BakaTaskbarAutoHide,Set-BakaTaskbarAutoHide,Invoke-BakaStartMenu
