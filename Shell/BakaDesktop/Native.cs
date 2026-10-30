using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace Baka.Desktop
{
    // Every Win32 call BAKA Desktop makes, in one place.
    static class Native
    {
        public const int SW_HIDE = 0, SW_SHOWNORMAL = 1, SW_SHOWMINIMIZED = 2, SW_SHOW = 5, SW_MINIMIZE = 6, SW_SHOWNA = 8, SW_RESTORE = 9;
        public const int GWL_STYLE = -16, GWL_EXSTYLE = -20;
        public const long WS_EX_TOOLWINDOW = 0x80, WS_EX_APPWINDOW = 0x40000, WS_EX_NOACTIVATE = 0x08000000, WS_VISIBLE = 0x10000000, WS_MINIMIZE = 0x20000000;
        public const uint SWP_NOSIZE = 1, SWP_NOMOVE = 2, SWP_NOZORDER = 4, SWP_NOACTIVATE = 0x10, SWP_SHOWWINDOW = 0x40;
        public static readonly IntPtr HWND_BOTTOM = new IntPtr(1), HWND_TOPMOST = new IntPtr(-1), HWND_NOTOPMOST = new IntPtr(-2);

        [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; public int Width => Right - Left; public int Height => Bottom - Top; }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)] public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }
        [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }

        [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cls, string title);
        [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int cmd);
        [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hwnd, int cmd);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern void SwitchToThisWindow(IntPtr hwnd, bool altTab);
        [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint from, uint to, bool attach);
        [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
        [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hwnd, uint cmd);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int count);
        [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hwnd);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hwnd, StringBuilder text, int count);
        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] public static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
        [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] public static extern IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value);
        [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
        [DllImport("user32.dll", EntryPoint = "SetParent")] public static extern IntPtr SetParentWindow(IntPtr child, IntPtr parent);
        [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr w, IntPtr l);
        [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
        [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
        [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern uint RegisterWindowMessage(string name);
        [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hwnd, int id, uint mods, uint vk);
        [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hwnd, int id);
        [DllImport("user32.dll")] public static extern bool LockWorkStation();
        [DllImport("powrprof.dll")] public static extern bool SetSuspendState(bool hibernate, bool force, bool disableWake);

        // ---- reliable shut down / restart / sign out (no dependency on shutdown.exe or the /hybrid flag) ----
        [DllImport("user32.dll", SetLastError = true)] public static extern bool ExitWindowsEx(uint flags, uint reason);
        [StructLayout(LayoutKind.Sequential)] struct LUID { public uint Low; public int High; }
        [StructLayout(LayoutKind.Sequential)] struct TOKEN_PRIVILEGES { public uint Count; public LUID Luid; public uint Attributes; }
        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool LookupPrivilegeValue(string system, string name, out LUID luid);
        [DllImport("advapi32.dll", SetLastError = true)] static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TOKEN_PRIVILEGES newState, uint len, IntPtr prev, IntPtr prevLen);
        [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
        // ExitWindowsEx needs SeShutdownPrivilege enabled in the process token; the user has it, but it is off
        // by default and must be switched on first.
        public static bool EnableShutdownPrivilege()
        {
            if (!OpenProcessToken(GetCurrentProcess(), 0x0020 /*ADJUST_PRIVILEGES*/ | 0x0008 /*QUERY*/, out IntPtr tok)) return false;
            try
            {
                if (!LookupPrivilegeValue(null, "SeShutdownPrivilege", out LUID luid)) return false;
                var tp = new TOKEN_PRIVILEGES { Count = 1, Luid = luid, Attributes = 0x0002 /*SE_PRIVILEGE_ENABLED*/ };
                return AdjustTokenPrivileges(tok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
            }
            finally { CloseHandle(tok); }
        }
        [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
        [DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint action, uint param, ref RECT value, uint winIni);
        [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW", CharSet = CharSet.Unicode)] public static extern bool SystemParametersInfoString(uint action, uint param, string value, uint winIni);
        [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW")] public static extern bool SystemParametersInfoInt(uint action, uint param, ref int value, uint winIni);
        [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW")] public static extern bool SystemParametersInfoPtr(uint action, uint param, IntPtr value, uint winIni);
        [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
        [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out int value, int size);
        [DllImport("user32.dll")] public static extern IntPtr GetShellWindow();
        [DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
        [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
        [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern bool QueryFullProcessImageName(IntPtr process, uint flags, StringBuilder name, ref int size);
        [DllImport("psapi.dll")] public static extern bool EmptyWorkingSet(IntPtr process);
        [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr obj);
        [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr icon);
        [DllImport("user32.dll")] public static extern int SetWindowRgn(IntPtr hwnd, IntPtr region, bool redraw);
        [DllImport("gdi32.dll")] public static extern IntPtr CreateRoundRectRgn(int l, int t, int r, int b, int w, int h);

        // ---- window events from other apps (out of context: nothing is loaded into their process) ----
        public delegate void WinEventProc(IntPtr hook, uint ev, IntPtr hwnd, int idObject, int idChild, uint thread, uint time);
        [DllImport("user32.dll")] public static extern IntPtr SetWinEventHook(uint min, uint max, IntPtr module, WinEventProc proc, uint pid, uint thread, uint flags);
        [DllImport("user32.dll")] public static extern bool UnhookWinEvent(IntPtr hook);
        [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
        public const uint WINEVENT_OUTOFCONTEXT = 0, WINEVENT_SKIPOWNPROCESS = 2;
        public const uint EVENT_SYSTEM_MOVESIZESTART = 0x000A, EVENT_SYSTEM_MOVESIZEEND = 0x000B, EVENT_SYSTEM_MINIMIZESTART = 0x0016, EVENT_SYSTEM_MINIMIZEEND = 0x0017;
        public const uint EVENT_OBJECT_DESTROY = 0x8001, EVENT_OBJECT_SHOW = 0x8002, EVENT_OBJECT_HIDE = 0x8003, EVENT_OBJECT_LOCATIONCHANGE = 0x800B;
        [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out RECT value, int size);

        // WM_NCHITTEST at a screen point, with a short timeout so a hung app cannot stall the desktop
        public static int HitTest(IntPtr hwnd, int x, int y)
        {
            IntPtr l = new IntPtr((y << 16) | (x & 0xFFFF));
            return SendMessageTimeout(hwnd, 0x0084, IntPtr.Zero, l, 0x0002 /*SMTO_ABORTIFHUNG*/, 150, out IntPtr r) == IntPtr.Zero ? -1 : r.ToInt32();
        }
        [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hwnd);
        [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hwnd, IntPtr dc);
        [DllImport("gdi32.dll")] static extern uint GetPixel(IntPtr dc, int x, int y);
        public static System.Drawing.Color? ScreenPixel(int x, int y)
        {
            IntPtr dc = GetDC(IntPtr.Zero); if (dc == IntPtr.Zero) return null;
            try { uint c = GetPixel(dc, x, y); if (c == 0xFFFFFFFF) return null; return System.Drawing.Color.FromArgb((int)(c & 0xFF), (int)((c >> 8) & 0xFF), (int)((c >> 16) & 0xFF)); }
            finally { ReleaseDC(IntPtr.Zero, dc); }
        }
        [DllImport("advapi32.dll")] static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
        [DllImport("advapi32.dll")] static extern bool GetTokenInformation(IntPtr token, int cls, out int info, int size, out int ret);
        // true for elevated processes (and ones we cannot even open, e.g. system processes)
        public static bool IsElevated(uint pid)
        {
            IntPtr p = OpenProcess(0x1000, false, pid); if (p == IntPtr.Zero) return true;
            try
            {
                if (!OpenProcessToken(p, 0x0008 /*TOKEN_QUERY*/, out IntPtr t)) return true;
                try { return GetTokenInformation(t, 20 /*TokenElevation*/, out int elevated, 4, out _) && elevated != 0; }
                finally { CloseHandle(t); }
            }
            finally { CloseHandle(p); }
        }

        public delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr param);
        [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc proc, IntPtr param);

        public static string WindowText(IntPtr hwnd) { int n = GetWindowTextLength(hwnd); if (n <= 0) return ""; var sb = new StringBuilder(n + 1); GetWindowText(hwnd, sb, sb.Capacity); return sb.ToString(); }
        public static string ClassName(IntPtr hwnd) { var sb = new StringBuilder(256); GetClassName(hwnd, sb, 256); return sb.ToString(); }
        public static long ExStyle(IntPtr hwnd) => GetWindowLongPtr(hwnd, GWL_EXSTYLE).ToInt64();
        public static bool IsCloaked(IntPtr hwnd) { return DwmGetWindowAttribute(hwnd, 14, out int c, 4) == 0 && c != 0; }

        // The app id of a packaged program's process (WhatsApp, Spotify from the Store...). Their windows often
        // carry no app id of their own, so this is what ties the window to the app's dock pin.
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern int GetApplicationUserModelId(IntPtr process, ref int length, StringBuilder id);
        public static string ProcessAppId(uint pid)
        {
            IntPtr h = OpenProcess(0x1000, false, pid);
            if (h == IntPtr.Zero) return null;
            try { int len = 256; var sb = new StringBuilder(len); return GetApplicationUserModelId(h, ref len, sb) == 0 ? sb.ToString() : null; }
            catch { return null; }
            finally { CloseHandle(h); }
        }
        public static string ProcessPath(uint pid)
        {
            IntPtr h = OpenProcess(0x1000, false, pid); // PROCESS_QUERY_LIMITED_INFORMATION
            if (h == IntPtr.Zero) return null;
            try { var sb = new StringBuilder(1024); int size = sb.Capacity; return QueryFullProcessImageName(h, 0, sb, ref size) ? sb.ToString() : null; }
            finally { CloseHandle(h); }
        }

        // Brings a window to the front even when Windows' foreground lock would refuse it.
        public static void Activate(IntPtr hwnd)
        {
            if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
            IntPtr fg = GetForegroundWindow();
            uint fgThread = GetWindowThreadProcessId(fg, out _), me = GetCurrentThreadId();
            bool attached = fgThread != me && AttachThreadInput(me, fgThread, true);
            try { BringWindowToTop(hwnd); SetForegroundWindow(hwnd); }
            finally { if (attached) AttachThreadInput(me, fgThread, false); }
            if (GetForegroundWindow() != hwnd) SwitchToThisWindow(hwnd, true);
        }

        public static void SendKeys(params byte[] keys)
        {
            foreach (var k in keys) keybd_event(k, 0, 0, UIntPtr.Zero);
            for (int i = keys.Length - 1; i >= 0; i--) keybd_event(keys[i], 0, 2, UIntPtr.Zero);
        }
        public static void SendMediaKey(byte key) { keybd_event(key, 0, 1, UIntPtr.Zero); keybd_event(key, 0, 3, UIntPtr.Zero); }

        public static RECT MonitorRect(IntPtr hwnd, bool work)
        {
            var info = new MONITORINFO { cbSize = Marshal.SizeOf(typeof(MONITORINFO)) };
            GetMonitorInfo(MonitorFromWindow(hwnd, 2), ref info);
            return work ? info.rcWork : info.rcMonitor;
        }

        // ---- glass: the blur Windows uses for its own flyouts ----
        [StructLayout(LayoutKind.Sequential)] struct ACCENTPOLICY { public int AccentState, AccentFlags; public uint GradientColor; public int AnimationId; }
        [StructLayout(LayoutKind.Sequential)] struct COMPOSITIONDATA { public int Attribute; public IntPtr Data; public int SizeOfData; }
        [DllImport("user32.dll")] static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref COMPOSITIONDATA data);
        public static bool SetBlur(IntPtr hwnd, bool on)
        {
            var accent = new ACCENTPOLICY { AccentState = on ? 3 : 0 };
            int size = Marshal.SizeOf(accent); IntPtr p = Marshal.AllocHGlobal(size);
            try { Marshal.StructureToPtr(accent, p, false); var d = new COMPOSITIONDATA { Attribute = 19, Data = p, SizeOfData = size }; return SetWindowCompositionAttribute(hwnd, ref d) != 0; }
            finally { Marshal.FreeHGlobal(p); }
        }
        public static void RoundCorners(IntPtr hwnd) { int pref = 2; DwmSetWindowAttribute(hwnd, 33, ref pref, 4); }

        // ---- launching a Store app by its app id, the shell-free way ----
        // Process.Start on "shell:AppsFolder\<id>" leans on the running shell; this COM call is the documented
        // way to start a packaged app and works when BAKA is the shell (Explorer not running).
        [ComImport, Guid("2E941141-7F97-4756-BA1D-9DECDE894A3D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IApplicationActivationManager
        {
            int ActivateApplication([MarshalAs(UnmanagedType.LPWStr)] string appUserModelId, [MarshalAs(UnmanagedType.LPWStr)] string arguments, int options, out uint processId);
        }
        [ComImport, Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")] class ApplicationActivationManager { }
        public static bool LaunchAppId(string aumid, string args)
        {
            if (string.IsNullOrEmpty(aumid)) return false;
            try { var mgr = (IApplicationActivationManager)new ApplicationActivationManager(); return mgr.ActivateApplication(aumid, args ?? "", 0, out _) == 0; }
            catch (Exception e) { Log.Write("activate-appid-failed id=\"" + aumid + "\" error=\"" + e.Message + "\""); return false; }
        }
        public static void DarkFrame(IntPtr hwnd) { int on = 1; DwmSetWindowAttribute(hwnd, 20, ref on, 4); }

        // Windows falls back to outline dragging when "show window contents while dragging" is off.
        public static void EnsureFullWindowDrag()
        {
            int on = 0; SystemParametersInfoInt(0x0026, 0, ref on, 0);
            if (on == 0) SystemParametersInfoPtr(0x0025, 1, IntPtr.Zero, 3);
        }

        // ---- app bars: the menu bar and dock reserve their screen edge so maximized windows stop at them ----
        [StructLayout(LayoutKind.Sequential)] public struct APPBARDATA { public int cbSize; public IntPtr hWnd; public uint uCallbackMessage; public uint uEdge; public RECT rc; public IntPtr lParam; }
        [DllImport("shell32.dll")] public static extern UIntPtr SHAppBarMessage(uint msg, ref APPBARDATA data);
        public const uint ABM_NEW = 0, ABM_REMOVE = 1, ABM_QUERYPOS = 2, ABM_SETPOS = 3, ABM_GETSTATE = 4, ABM_SETSTATE = 10, ABE_LEFT = 0, ABE_TOP = 1, ABE_RIGHT = 2, ABE_BOTTOM = 3;

        // ---- shell icons for any parsing name (file, folder, shell:AppsFolder\<AppID>) ----
        [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IShellItemImageFactory { [PreserveSig] int GetImage(SIZE size, int flags, out IntPtr hbitmap); }
        [StructLayout(LayoutKind.Sequential)] struct SIZE { public int cx, cy; }
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
        static extern void SHCreateItemFromParsingName(string path, IntPtr bindCtx, [MarshalAs(UnmanagedType.LPStruct)] Guid iid, [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory item);
        [DllImport("gdi32.dll")] static extern int GetObject(IntPtr h, int size, out BITMAP bmp);
        [DllImport("gdi32.dll")] static extern int GetBitmapBits(IntPtr h, int size, byte[] bits);
        [StructLayout(LayoutKind.Sequential)] struct BITMAP { public int bmType, bmWidth, bmHeight, bmWidthBytes; public ushort bmPlanes, bmBitsPixel; public IntPtr bmBits; }

        // Returns premultiplied BGRA pixels top-down, or null.
        public static byte[] ShellIconPixels(string parsingName, int size, out int width, out int height)
        {
            width = height = 0;
            IShellItemImageFactory factory = null; IntPtr hbmp = IntPtr.Zero;
            try
            {
                SHCreateItemFromParsingName(parsingName, IntPtr.Zero, typeof(IShellItemImageFactory).GUID, out factory);
                // SIIGBF_ICONONLY (4) | SIIGBF_BIGGERSIZEOK (1): the app icon, never a thumbnail
                if (factory.GetImage(new SIZE { cx = size, cy = size }, 0x5, out hbmp) != 0 || hbmp == IntPtr.Zero) return null;
                GetObject(hbmp, Marshal.SizeOf(typeof(BITMAP)), out BITMAP bmp);
                if (bmp.bmBitsPixel != 32) return null;
                width = bmp.bmWidth; height = Math.Abs(bmp.bmHeight);
                var bits = new byte[width * height * 4];
                GetBitmapBits(hbmp, bits.Length, bits);
                return bits;
            }
            catch { return null; }
            finally { if (hbmp != IntPtr.Zero) DeleteObject(hbmp); if (factory != null) Marshal.ReleaseComObject(factory); }
        }

        // ---- the AppUserModelID of a window (groups UWP apps hosted by ApplicationFrameHost) ----
        [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IPropertyStore { int GetCount(out uint c); int GetAt(uint i, out PROPERTYKEY k); int GetValue(ref PROPERTYKEY k, out PROPVARIANT v); int SetValue(ref PROPERTYKEY k, ref PROPVARIANT v); int Commit(); }
        [StructLayout(LayoutKind.Sequential, Pack = 4)] struct PROPERTYKEY { public Guid fmtid; public uint pid; }
        [StructLayout(LayoutKind.Explicit)] struct PROPVARIANT { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr p; [FieldOffset(16)] public IntPtr pad; }
        [DllImport("shell32.dll")] static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid iid, out IPropertyStore store);
        [DllImport("ole32.dll")] static extern int PropVariantClear(ref PROPVARIANT pv);
        public static string WindowAppId(IntPtr hwnd)
        {
            var iid = typeof(IPropertyStore).GUID;
            if (SHGetPropertyStoreForWindow(hwnd, ref iid, out IPropertyStore store) != 0 || store == null) return null;
            try
            {
                var key = new PROPERTYKEY { fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = 5 };
                if (store.GetValue(ref key, out PROPVARIANT v) != 0) return null;
                try { return v.vt == 31 ? Marshal.PtrToStringUni(v.p) : null; } finally { PropVariantClear(ref v); }
            }
            catch { return null; }
            finally { Marshal.ReleaseComObject(store); }
        }

        // ---- shell file operations: copy, move and delete with Windows' own progress and Recycle Bin ----
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct SHFILEOPSTRUCT { public IntPtr hwnd; public uint wFunc; public string pFrom; public string pTo; public ushort fFlags; public bool fAnyOperationsAborted; public IntPtr hNameMappings; public string lpszProgressTitle; }
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern int SHFileOperation(ref SHFILEOPSTRUCT op);
        public const uint FO_MOVE = 1, FO_COPY = 2, FO_DELETE = 3, FO_RENAME = 4;
        public static bool FileOperation(IntPtr owner, uint func, IEnumerable<string> from, string to, bool recycle)
        {
            var op = new SHFILEOPSTRUCT { hwnd = owner, wFunc = func, pFrom = string.Join("\0", from) + "\0\0", pTo = to == null ? null : to + "\0\0" };
            ushort flags = 0x0008; // FOF_RENAMEONCOLLISION for copies into the same folder
            if (recycle) flags |= 0x0040; // FOF_ALLOWUNDO: deletes go to the Recycle Bin
            op.fFlags = func == FO_DELETE ? (ushort)(recycle ? 0x0040 : 0) : flags;
            return SHFileOperation(ref op) == 0 && !op.fAnyOperationsAborted;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct SHELLEXECUTEINFO { public int cbSize; public uint fMask; public IntPtr hwnd; public string lpVerb, lpFile, lpParameters, lpDirectory; public int nShow; public IntPtr hInstApp, lpIDList; public string lpClass; public IntPtr hkeyClass; public uint dwHotKey; public IntPtr hIcon, hProcess; }
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern bool ShellExecuteEx(ref SHELLEXECUTEINFO info);
        public static bool ShellVerb(string path, string verb)
        {
            var info = new SHELLEXECUTEINFO { cbSize = Marshal.SizeOf(typeof(SHELLEXECUTEINFO)), fMask = 0x0000000C, lpVerb = verb, lpFile = path, nShow = SW_SHOWNORMAL };
            return ShellExecuteEx(ref info);
        }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SHEmptyRecycleBin(IntPtr hwnd, string root, uint flags);
        [DllImport("shell32.dll")] public static extern void SHChangeNotify(int eventId, uint flags, IntPtr item1, IntPtr item2);

        // ---- the process list with each process's parent (one Toolhelp snapshot, a few ms) ----
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct PROCESSENTRY32W { public uint dwSize, cntUsage, th32ProcessID; public IntPtr th32DefaultHeapID; public uint th32ModuleID, cntThreads, th32ParentProcessID; public int pcPriClassBase; public uint dwFlags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szExeFile; }
        [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint pid);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool Process32FirstW(IntPtr snap, ref PROCESSENTRY32W e);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool Process32NextW(IntPtr snap, ref PROCESSENTRY32W e);
        public static Dictionary<uint, (uint parent, string exe)> Processes()
        {
            var r = new Dictionary<uint, (uint, string)>();
            IntPtr snap = CreateToolhelp32Snapshot(0x00000002 /*TH32CS_SNAPPROCESS*/, 0);
            if (snap == IntPtr.Zero || snap == new IntPtr(-1)) return r;
            try
            {
                var e = new PROCESSENTRY32W { dwSize = (uint)Marshal.SizeOf(typeof(PROCESSENTRY32W)) };
                for (bool ok = Process32FirstW(snap, ref e); ok; ok = Process32NextW(snap, ref e)) r[e.th32ProcessID] = (e.th32ParentProcessID, e.szExeFile ?? "");
            }
            finally { CloseHandle(snap); }
            return r;
        }

        // ---- system numbers ----
        [StructLayout(LayoutKind.Sequential)] public struct MEMORYSTATUSEX { public uint dwLength, dwMemoryLoad; public ulong ullTotalPhys, ullAvailPhys, ullTotalPageFile, ullAvailPageFile, ullTotalVirtual, ullAvailVirtual, ullAvailExtendedVirtual; }
        [DllImport("kernel32.dll")] public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX m);
        [DllImport("kernel32.dll")] public static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
        [StructLayout(LayoutKind.Sequential)] public struct SYSTEM_POWER_STATUS { public byte ACLineStatus, BatteryFlag, BatteryLifePercent, SystemStatusFlag; public int BatteryLifeTime, BatteryFullLifeTime; }
        [DllImport("kernel32.dll")] public static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS s);

        // ---- keyboard hook ----
        public delegate IntPtr HookProc(int code, IntPtr w, IntPtr l);
        [DllImport("user32.dll", SetLastError = true)] public static extern IntPtr SetWindowsHookEx(int id, HookProc proc, IntPtr module, uint thread);
        [DllImport("user32.dll")] public static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr w, IntPtr l);
        [DllImport("user32.dll")] public static extern bool UnhookWindowsHookEx(IntPtr hook);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr GetModuleHandle(string name);
        [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
        [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    }

    // Windows' master volume (Core Audio).
    static class Audio
    {
        [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator { }
        [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IMMDeviceEnumerator { int NotImpl1(); [PreserveSig] int GetDefaultAudioEndpoint(int flow, int role, out IMMDevice device); }
        [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IMMDevice { [PreserveSig] int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); }
        [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IAudioEndpointVolume
        {
            int RegisterControlChangeNotify(IntPtr p); int UnregisterControlChangeNotify(IntPtr p); int GetChannelCount(out int c);
            int SetMasterVolumeLevel(float level, Guid ctx); int SetMasterVolumeLevelScalar(float level, ref Guid ctx);
            int GetMasterVolumeLevel(out float level); int GetMasterVolumeLevelScalar(out float level);
            int SetChannelVolumeLevel(uint ch, float level, Guid ctx); int SetChannelVolumeLevelScalar(uint ch, float level, Guid ctx);
            int GetChannelVolumeLevel(uint ch, out float level); int GetChannelVolumeLevelScalar(uint ch, out float level);
            int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid ctx); int GetMute(out bool mute);
        }
        // The default output device, looked up again every few seconds (so switching speakers / headphones is
        // followed) instead of on every call: the volume slider calls this for every pixel it moves.
        static IAudioEndpointVolume endpoint; static DateTime endpointAt;
        static IAudioEndpointVolume Endpoint()
        {
            if (endpoint != null && (DateTime.Now - endpointAt).TotalSeconds < 5) return endpoint;
            try
            {
                var e = (IMMDeviceEnumerator)new MMDeviceEnumerator();
                if (e.GetDefaultAudioEndpoint(0, 1, out IMMDevice dev) != 0) { endpoint = null; return null; }
                var iid = typeof(IAudioEndpointVolume).GUID;
                dev.Activate(ref iid, 23, IntPtr.Zero, out object o);
                endpoint = o as IAudioEndpointVolume; endpointAt = DateTime.Now;
                return endpoint;
            }
            catch { endpoint = null; return null; }
        }
        public static int? Level { get { var v = Endpoint(); if (v == null) return null; v.GetMasterVolumeLevelScalar(out float l); return (int)Math.Round(l * 100); } }
        public static bool Muted { get { var v = Endpoint(); if (v == null) return false; v.GetMute(out bool m); return m; } }
        public static void SetLevel(int percent) { var v = Endpoint(); if (v == null) return; var g = Guid.Empty; v.SetMasterVolumeLevelScalar(Math.Max(0, Math.Min(100, percent)) / 100f, ref g); if (percent > 0) v.SetMute(false, ref g); }
        public static void SetMuted(bool mute) { var v = Endpoint(); if (v == null) return; var g = Guid.Empty; v.SetMute(mute, ref g); }
    }
}
