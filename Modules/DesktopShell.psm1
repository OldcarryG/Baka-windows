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
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int command);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern uint RegisterWindowMessage(string name);

  // Every Windows taskbar: the primary Shell_TrayWnd and one Shell_SecondaryTrayWnd per extra monitor.
  public static IntPtr[] GetTaskbarWindows() {
    var list = new System.Collections.Generic.List<IntPtr>();
    IntPtr primary = FindWindow("Shell_TrayWnd", null);
    if (primary != IntPtr.Zero) list.Add(primary);
    IntPtr after = IntPtr.Zero;
    while (true) {
      after = FindWindowEx(IntPtr.Zero, after, "Shell_SecondaryTrayWnd", null);
      if (after == IntPtr.Zero) break;
      list.Add(after);
    }
    return list.ToArray();
  }

  // Registers a BAKA window as a desktop toolbar (app bar) so maximized windows stop at its edge,
  // exactly like the Windows taskbar. Edge: 1 = top, 3 = bottom. Coordinates are physical pixels.
  public static RECT SetAppBar(IntPtr hwnd, uint edge, int left, int top, int right, int bottom, int thickness) {
    APPBARDATA data = new APPBARDATA();
    data.cbSize = Marshal.SizeOf(typeof(APPBARDATA));
    data.hWnd = hwnd;
    data.uCallbackMessage = RegisterWindowMessage("BAKA.AppBar");
    SHAppBarMessage(0, ref data);            // ABM_NEW (FALSE when already registered; harmless)
    data.uEdge = edge;
    data.rc.Left = left; data.rc.Right = right; data.rc.Top = top; data.rc.Bottom = bottom;
    if (edge == 1) { data.rc.Bottom = top + thickness; } else { data.rc.Top = bottom - thickness; }
    SHAppBarMessage(2, ref data);            // ABM_QUERYPOS
    if (edge == 1) { data.rc.Bottom = data.rc.Top + thickness; } else { data.rc.Top = data.rc.Bottom - thickness; }
    SHAppBarMessage(3, ref data);            // ABM_SETPOS
    return data.rc;
  }
  public static void RemoveAppBar(IntPtr hwnd) {
    APPBARDATA data = new APPBARDATA();
    data.cbSize = Marshal.SizeOf(typeof(APPBARDATA));
    data.hWnd = hwnd;
    SHAppBarMessage(1, ref data);            // ABM_REMOVE
  }
}

// Real application icons (desktop apps, Store apps, folders) from the Windows shell, as BGRA pixels.
[ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IBakaShellItemImageFactory { [PreserveSig] int GetImage(BakaShellSize size, int flags, out IntPtr bitmap); }
[StructLayout(LayoutKind.Sequential)] public struct BakaShellSize { public int cx; public int cy; }
public static class BakaShellIcons {
  [StructLayout(LayoutKind.Sequential)] struct BITMAP { public int bmType; public int bmWidth; public int bmHeight; public int bmWidthBytes; public ushort bmPlanes; public ushort bmBitsPixel; public IntPtr bmBits; }
  [StructLayout(LayoutKind.Sequential)] struct BITMAPINFOHEADER { public int biSize; public int biWidth; public int biHeight; public short biPlanes; public short biBitCount; public int biCompression; public int biSizeImage; public int biXPelsPerMeter; public int biYPelsPerMeter; public int biClrUsed; public int biClrImportant; }
  [DllImport("shell32.dll", CharSet=CharSet.Unicode, PreserveSig=false)] static extern void SHCreateItemFromParsingName(string path, IntPtr bindContext, [MarshalAs(UnmanagedType.LPStruct)] Guid riid, [MarshalAs(UnmanagedType.Interface)] out IBakaShellItemImageFactory item);
  [DllImport("gdi32.dll")] static extern int GetObject(IntPtr handle, int size, ref BITMAP bitmap);
  [DllImport("gdi32.dll")] static extern int GetDIBits(IntPtr dc, IntPtr bitmap, uint start, uint lines, byte[] bits, ref BITMAPINFOHEADER info, uint usage);
  [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr handle);
  [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hwnd);
  [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hwnd, IntPtr dc);
  // Returns premultiplied BGRA rows (top-down) or null when the shell has no image for the item.
  public static byte[] GetImage(string parsingName, int size, out int width, out int height) {
    width = 0; height = 0;
    IBakaShellItemImageFactory factory = null;
    IntPtr bitmap = IntPtr.Zero;
    try {
      SHCreateItemFromParsingName(parsingName, IntPtr.Zero, typeof(IBakaShellItemImageFactory).GUID, out factory);
      BakaShellSize requested = new BakaShellSize(); requested.cx = size; requested.cy = size;
      if (factory.GetImage(requested, 0, out bitmap) != 0 || bitmap == IntPtr.Zero) return null;
      BITMAP info = new BITMAP();
      GetObject(bitmap, Marshal.SizeOf(typeof(BITMAP)), ref info);
      width = info.bmWidth; height = Math.Abs(info.bmHeight);
      BITMAPINFOHEADER header = new BITMAPINFOHEADER();
      header.biSize = Marshal.SizeOf(typeof(BITMAPINFOHEADER)); header.biWidth = width; header.biHeight = -height; header.biPlanes = 1; header.biBitCount = 32;
      byte[] pixels = new byte[width * height * 4];
      IntPtr dc = GetDC(IntPtr.Zero);
      try { if (GetDIBits(dc, bitmap, 0, (uint)height, pixels, ref header, 0) == 0) return null; } finally { ReleaseDC(IntPtr.Zero, dc); }
      return pixels;
    } catch { return null; }
    finally {
      if (bitmap != IntPtr.Zero) DeleteObject(bitmap);
      if (factory != null) Marshal.ReleaseComObject(factory);
    }
  }
}

// Master volume through the Windows Core Audio endpoint (the same control as the tray volume flyout).
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class BakaMMDeviceEnumerator { }
[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IBakaMMDeviceEnumerator { int NotImpl1(); [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IBakaMMDevice device); }
[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IBakaMMDevice { [PreserveSig] int Activate(ref Guid iid, int context, IntPtr parameters, [MarshalAs(UnmanagedType.IUnknown)] out object endpoint); }
[ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IBakaAudioEndpointVolume {
  int RegisterControlChangeNotify(IntPtr notify); int UnregisterControlChangeNotify(IntPtr notify); int GetChannelCount(out uint count);
  int SetMasterVolumeLevel(float level, ref Guid context); int SetMasterVolumeLevelScalar(float level, ref Guid context);
  int GetMasterVolumeLevel(out float level); int GetMasterVolumeLevelScalar(out float level);
  int SetChannelVolumeLevel(uint channel, float level, ref Guid context); int SetChannelVolumeLevelScalar(uint channel, float level, ref Guid context);
  int GetChannelVolumeLevel(uint channel, out float level); int GetChannelVolumeLevelScalar(uint channel, out float level);
  int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid context); int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
}
public static class BakaAudio {
  static IBakaAudioEndpointVolume Endpoint() {
    IBakaMMDeviceEnumerator enumerator = (IBakaMMDeviceEnumerator)(new BakaMMDeviceEnumerator());
    IBakaMMDevice device;
    if (enumerator.GetDefaultAudioEndpoint(0, 1, out device) != 0 || device == null) return null;
    Guid iid = typeof(IBakaAudioEndpointVolume).GUID; object endpoint;
    if (device.Activate(ref iid, 23, IntPtr.Zero, out endpoint) != 0) return null;
    return (IBakaAudioEndpointVolume)endpoint;
  }
  // Volume 0-100, or -1 when no output device is present.
  public static int GetVolume() { try { var e = Endpoint(); if (e == null) return -1; float v; e.GetMasterVolumeLevelScalar(out v); return (int)Math.Round(v * 100); } catch { return -1; } }
  public static bool SetVolume(int percent) { try { var e = Endpoint(); if (e == null) return false; Guid g = Guid.Empty; e.SetMasterVolumeLevelScalar(Math.Max(0, Math.Min(100, percent)) / 100f, ref g); return true; } catch { return false; } }
  public static bool GetMute() { try { var e = Endpoint(); if (e == null) return false; bool m; e.GetMute(out m); return m; } catch { return false; } }
  public static bool SetMute(bool mute) { try { var e = Endpoint(); if (e == null) return false; Guid g = Guid.Empty; e.SetMute(mute, ref g); return true; } catch { return false; } }
}

public static class BakaDesktopWallpaperHost {
  // Returns the WorkerW window that hosts the desktop wallpaper behind the icon view.
  // Windows 11 24H2+ creates it as a child of Progman; earlier builds create a top-level sibling.
  public static IntPtr GetWallpaperHost() {
    IntPtr progman = BakaDesktopShellNative.FindWindow("Progman", null);
    if (progman == IntPtr.Zero) return IntPtr.Zero;
    IntPtr ignored;
    BakaDesktopShellNative.SendMessageTimeout(progman, 0x052C, new IntPtr(0xD), new IntPtr(0x1), 0x0002, 1000, out ignored);
    BakaDesktopShellNative.SendMessageTimeout(progman, 0x052C, IntPtr.Zero, IntPtr.Zero, 0x0002, 1000, out ignored);
    IntPtr child = BakaDesktopShellNative.FindWindowEx(progman, IntPtr.Zero, "WorkerW", null);
    if (child != IntPtr.Zero) return child;
    IntPtr host = IntPtr.Zero;
    BakaDesktopShellNative.EnumWindows(delegate(IntPtr top, IntPtr param) {
      IntPtr view = BakaDesktopShellNative.FindWindowEx(top, IntPtr.Zero, "SHELLDLL_DefView", null);
      if (view != IntPtr.Zero) { host = BakaDesktopShellNative.FindWindowEx(IntPtr.Zero, top, "WorkerW", null); }
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
    return [BakaDesktopWallpaperHost]::GetWallpaperHost()
}

function Set-BakaWindowAsWallpaper {
    # Re-parents a WPF window handle into the desktop wallpaper host so it renders behind desktop icons.
    param([Parameter(Mandatory)][IntPtr]$Handle,[Parameter(Mandatory)][int]$Left,[Parameter(Mandatory)][int]$Top,[Parameter(Mandatory)][int]$Width,[Parameter(Mandatory)][int]$Height)
    Initialize-BakaDesktopShellNative
    $hostHandle=[BakaDesktopWallpaperHost]::GetWallpaperHost()
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

function Set-BakaTaskbarVisibility {
    # Hides (or shows again) every Windows taskbar window. BAKA calls this together with auto-hide so the
    # work area is reclaimed, and re-applies it on a timer because Explorer re-shows the taskbar after restarts.
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory)][bool]$Visible)
    Initialize-BakaDesktopShellNative
    $handles=@([BakaDesktopShellNative]::GetTaskbarWindows())
    if(-not $handles.Count){return $false}
    if(-not $PSCmdlet.ShouldProcess('Windows taskbar',$(if($Visible){'Show'}else{'Hide'}))){return $false}
    foreach($handle in $handles){
        $isVisible=[BakaDesktopShellNative]::IsWindowVisible($handle)
        if($Visible -and -not $isVisible){[void][BakaDesktopShellNative]::ShowWindow($handle,5)}
        elseif(-not $Visible -and $isVisible){[void][BakaDesktopShellNative]::ShowWindow($handle,0)}
    }
    return $true
}

function Test-BakaTaskbarVisible {
    Initialize-BakaDesktopShellNative
    foreach($handle in @([BakaDesktopShellNative]::GetTaskbarWindows())){if([BakaDesktopShellNative]::IsWindowVisible($handle)){return $true}}
    return $false
}

function Register-BakaAppBar {
    # Reserves a screen edge for a BAKA bar so maximized windows stop at it. Values are physical pixels.
    param([Parameter(Mandatory)][IntPtr]$Handle,[Parameter(Mandatory)][ValidateSet('Top','Bottom')][string]$Edge,[Parameter(Mandatory)][int]$Left,[Parameter(Mandatory)][int]$Top,[Parameter(Mandatory)][int]$Right,[Parameter(Mandatory)][int]$Bottom,[Parameter(Mandatory)][int]$Thickness)
    Initialize-BakaDesktopShellNative
    $code=if($Edge -eq 'Top'){1}else{3}
    return [BakaDesktopShellNative]::SetAppBar($Handle,[uint32]$code,$Left,$Top,$Right,$Bottom,$Thickness)
}

function Unregister-BakaAppBar {
    param([Parameter(Mandatory)][IntPtr]$Handle)
    Initialize-BakaDesktopShellNative
    [BakaDesktopShellNative]::RemoveAppBar($Handle)
}

function Get-BakaShellIconPixels {
    # Real shell icon for an executable, shortcut, folder, or Store app ("shell:AppsFolder\<AppID>").
    param([Parameter(Mandatory)][string]$ParsingName,[int]$Size=64)
    Initialize-BakaDesktopShellNative
    $width=0;$height=0
    $pixels=[BakaShellIcons]::GetImage($ParsingName,$Size,[ref]$width,[ref]$height)
    if(-not $pixels){return $null}
    [pscustomobject]@{Pixels=$pixels;Width=$width;Height=$height}
}

function Get-BakaVolume { Initialize-BakaDesktopShellNative; [pscustomobject]@{Level=[BakaAudio]::GetVolume();Muted=[BakaAudio]::GetMute()} }
function Set-BakaVolume {
    param([ValidateRange(0,100)][int]$Level=-1,[Nullable[bool]]$Muted=$null)
    Initialize-BakaDesktopShellNative
    $ok=$true
    if($Level -ge 0){$ok=[BakaAudio]::SetVolume($Level) -and $ok}
    if($null -ne $Muted){$ok=[BakaAudio]::SetMute([bool]$Muted) -and $ok}
    return $ok
}

Export-ModuleMember -Function Get-BakaWallpaperKind,Get-BakaSupportedWallpaperExtensions,Set-BakaStaticWallpaper,Set-BakaSolidColorWallpaper,Get-BakaWallpaperHostHandle,Set-BakaWindowAsWallpaper,Get-BakaTaskbarAutoHide,Set-BakaTaskbarAutoHide,Invoke-BakaStartMenu,Set-BakaTaskbarVisibility,Test-BakaTaskbarVisible,Register-BakaAppBar,Unregister-BakaAppBar,Get-BakaShellIconPixels,Get-BakaVolume,Set-BakaVolume
