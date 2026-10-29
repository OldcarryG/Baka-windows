using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace Baka.Desktop
{
    // Windows File Explorer keeps running in the background because Windows needs it (tray icons,
    // notifications, file dialogs, Settings pages), but nothing of it is shown: BAKA replaces the taskbar,
    // Start, the desktop icons, Win+E and folder windows. Everything here is undone when BAKA exits or
    // crashes, so a failure always leaves a normal Windows desktop behind.
    static class ExplorerIntegration
    {
        static readonly string[] TrayClasses = { "Shell_TrayWnd", "Shell_SecondaryTrayWnd" };
        public static bool TaskbarHidden { get; private set; }

        // ---- taskbar ----
        public static void HideTaskbar()
        {
            if (Paths.Preview) return;
            SetAutoHide(true);
            foreach (var h in TrayWindows()) Native.ShowWindow(h, Native.SW_HIDE);
            TaskbarHidden = true;
        }
        public static void ShowTaskbar(bool restoreAutoHide)
        {
            foreach (var h in TrayWindows()) Native.ShowWindow(h, Native.SW_SHOW);
            if (restoreAutoHide) SetAutoHide(false);
            TaskbarHidden = false;
        }
        static System.Collections.Generic.IEnumerable<IntPtr> TrayWindows()
        {
            var main = Native.FindWindow("Shell_TrayWnd", null); if (main != IntPtr.Zero) yield return main;
            for (IntPtr h = Native.FindWindowEx(IntPtr.Zero, IntPtr.Zero, "Shell_SecondaryTrayWnd", null); h != IntPtr.Zero; h = Native.FindWindowEx(IntPtr.Zero, h, "Shell_SecondaryTrayWnd", null)) yield return h;
        }
        // Auto-hide gives the taskbar's strip back to apps; hiding the window removes it from view.
        static void SetAutoHide(bool on)
        {
            var d = new Native.APPBARDATA { cbSize = Marshal.SizeOf(typeof(Native.APPBARDATA)), hWnd = Native.FindWindow("Shell_TrayWnd", null) };
            if (d.hWnd == IntPtr.Zero) return;
            d.lParam = new IntPtr(on ? 1 : 2); // ABS_AUTOHIDE / ABS_ALWAYSONTOP
            Native.SHAppBarMessage(Native.ABM_SETSTATE, ref d);
        }
        public static bool TaskbarVisible() { var h = Native.FindWindow("Shell_TrayWnd", null); return h != IntPtr.Zero && Native.IsWindowVisible(h); }

        // ---- desktop icons (BAKA has no desktop icon grid; files live in BAKA Files) ----
        static IntPtr FolderView()
        {
            IntPtr defView = IntPtr.Zero;
            var progman = Native.FindWindow("Progman", null);
            if (progman != IntPtr.Zero) defView = Native.FindWindowEx(progman, IntPtr.Zero, "SHELLDLL_DefView", null);
            if (defView == IntPtr.Zero)
                Native.EnumWindows((h, p) => { var dv = Native.FindWindowEx(h, IntPtr.Zero, "SHELLDLL_DefView", null); if (dv != IntPtr.Zero) { defView = dv; return false; } return true; }, IntPtr.Zero);
            return defView == IntPtr.Zero ? IntPtr.Zero : Native.FindWindowEx(defView, IntPtr.Zero, "SysListView32", null);
        }
        public static void SetDesktopIcons(bool visible)
        {
            if (Paths.Preview && !visible) return;
            var lv = FolderView(); if (lv != IntPtr.Zero) Native.ShowWindow(lv, visible ? Native.SW_SHOW : Native.SW_HIDE);
        }

        // ---- folders open in BAKA Files (per user, reversible) ----
        const string Verb = "BakaFiles";
        public static void SetFolderHandler(bool on, string exe)
        {
            if (Paths.Preview) return;
            foreach (var cls in new[] { "Directory", "Drive" })
            {
                string shell = @"Software\Classes\" + cls + @"\shell";
                try
                {
                    if (on)
                    {
                        using (var k = Registry.CurrentUser.CreateSubKey(shell + @"\" + Verb))
                        { k.SetValue("", "Open in BAKA Files"); k.SetValue("Icon", "\"" + exe + "\""); }
                        using (var k = Registry.CurrentUser.CreateSubKey(shell + @"\" + Verb + @"\command")) k.SetValue("", "\"" + exe + "\" --open \"%1\"");
                        using (var k = Registry.CurrentUser.CreateSubKey(shell)) k.SetValue("", Verb);
                    }
                    else
                    {
                        using (var k = Registry.CurrentUser.OpenSubKey(shell, true)) { if (k != null && (k.GetValue("") as string) == Verb) k.DeleteValue("", false); }
                        Registry.CurrentUser.DeleteSubKeyTree(shell + @"\" + Verb, false);
                    }
                }
                catch (Exception e) { Log.Write("folder-handler-failed class=" + cls + " error=\"" + e.Message + "\""); }
            }
        }

        // ---- the Explorer process ----
        public static bool ExplorerRunning()
        {
            int session = Process.GetCurrentProcess().SessionId;
            foreach (var p in Process.GetProcessesByName("explorer")) { try { if (p.SessionId == session) return true; } catch { } }
            return false;
        }
        // Earlier BAKA releases replaced Explorer as the shell; that left no tray, notifications or file
        // dialogs. Explorer is the shell again and runs in the background.
        public static void UndoOldShellOverride()
        {
            if (Paths.Preview) return;
            try
            {
                using (var k = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows NT\CurrentVersion\Winlogon", true))
                {
                    var v = k?.GetValue("Shell") as string;
                    if (v != null && v.IndexOf("Baka", StringComparison.OrdinalIgnoreCase) >= 0) { k.DeleteValue("Shell", false); Log.Write("old-shell-override-removed value=\"" + v + "\""); }
                }
            }
            catch { }
            // BAKA Desktop starts at sign-in in parallel with Explorer, so Explorer may simply not be up yet.
            // Only if it is still missing after 30 s (an old BAKA shell override) is it started here.
            if (!ExplorerRunning())
                new System.Threading.Thread(() =>
                {
                    for (int i = 0; i < 60 && !ExplorerRunning(); i++) System.Threading.Thread.Sleep(500);
                    if (!ExplorerRunning()) { try { Process.Start(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe")); Log.Write("explorer-started-in-background"); } catch { } }
                }) { IsBackground = true }.Start();
        }

        // Everything back to plain Windows. Safe to call from a crash handler or the supervisor.
        public static void RestoreAll()
        {
            try { ShowTaskbar(true); } catch { }
            try { SetDesktopIcons(true); } catch { }
            try { AppBars.ReleaseAll(); } catch { }
            try { KeyHook.Remove(); } catch { }
        }
    }

    // Explorer's own Win+E (File Explorer), Win+S and Win+Q (Windows search) are switched off with
    // Explorer's documented per-user DisabledHotkeys setting, so BAKA can take these keys without having to
    // swallow them in a keyboard hook. Explorer reads the setting when it starts, so it applies from the next
    // Explorer start; the marker file records when BAKA set it.
    static class ShellHotkeys
    {
        const string Key = @"Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced", Letters = "ESQ";
        static string Marker => Environment.ExpandEnvironmentVariables(@"%LOCALAPPDATA%\BAKA\explorer-hotkeys-off.txt");

        static string Read() { try { using (var k = Registry.CurrentUser.OpenSubKey(Key)) return k?.GetValue("DisabledHotkeys") as string ?? ""; } catch { return ""; } }
        static bool HasAll(string v) { foreach (char c in Letters) if (v.IndexOf(c) < 0) return false; return true; }

        // True when the Explorer running now was started after Win+E/S/Q were switched off.
        public static bool ActiveForThisSession()
        {
            if (Paths.Preview || !HasAll(Read()) || !File.Exists(Marker)) return false;
            var set = File.GetLastWriteTimeUtc(Marker);
            DateTime? start = null;
            int session = Process.GetCurrentProcess().SessionId;
            foreach (var p in Process.GetProcessesByName("explorer"))
                try { if (p.SessionId == session) { var t = p.StartTime.ToUniversalTime(); if (start == null || t < start) start = t; } } catch { }
            return start != null && start.Value > set;
        }
        // Switches Explorer's Win+E/S/Q off for the next Explorer start (sign-in). Returns true if anything changed.
        public static bool Take()
        {
            if (Paths.Preview) return false;
            string v = Read();
            if (HasAll(v) && File.Exists(Marker)) return false;
            foreach (char c in Letters) if (v.IndexOf(c) < 0) v += c;
            try
            {
                using (var k = Registry.CurrentUser.CreateSubKey(Key)) k.SetValue("DisabledHotkeys", v, RegistryValueKind.String);
                Directory.CreateDirectory(Path.GetDirectoryName(Marker)); File.WriteAllText(Marker, DateTime.Now.ToString("o"));
                Log.Write("explorer-hotkeys-off value=" + v + " (from the next sign-in)");
                return true;
            }
            catch (Exception e) { Log.Write("explorer-hotkeys-failed error=\"" + e.Message + "\""); return false; }
        }
        // Gives Win+E/S/Q back to Explorer (Leave BAKA, --restore-windows, feature turned off).
        public static void Release()
        {
            try
            {
                string v = Read(), left = "";
                foreach (char c in v) if (Letters.IndexOf(c) < 0) left += c;
                if (left == v && !File.Exists(Marker)) return;
                using (var k = Registry.CurrentUser.CreateSubKey(Key)) { if (left.Length == 0) k.DeleteValue("DisabledHotkeys", false); else k.SetValue("DisabledHotkeys", left, RegistryValueKind.String); }
                try { File.Delete(Marker); } catch { }
                Log.Write("explorer-hotkeys-restored (from the next sign-in)");
            }
            catch { }
        }
    }

    // Keyboard: a lone Windows key opens the BAKA Launchpad (Start never opens), Win+E opens BAKA Files,
    // Win+S searches in the Launchpad. Every other Win shortcut keeps working. Ctrl+Esc still opens Start.
    //
    // Normally BAKA only *listens* (raw input). Windows copies each key event to BAKA after delivering it
    // and never waits for BAKA, so BAKA adds nothing to the time a key press takes to reach any app.
    // Microsoft's documentation for low-level hooks recommends raw input for exactly this reason.
    // A lone Windows key is stopped from opening Start the moment it goes down, by sending an unassigned key
    // (0xE8) while it is held, which tells Windows the key was used in a combination.
    //
    // Fallback: only in the session in which BAKA first switched off Explorer's Win+E/S/Q (Explorer applies
    // that at its next start), a low-level hook is used, as in R14. Windows waits for a low-level hook on
    // every key press, so the hook runs on its own time-critical thread that does nothing else.
    static class KeyHook
    {
        static Native.HookProc proc; static volatile IntPtr hook;
        static System.Threading.Thread thread; static uint threadId;
        static volatile IntPtr rawWindow; static WndProcDelegate rawProc; static int rawHeader;
        static bool winDown, winUsed; static int raisedVk;
        public static volatile bool Enabled = true;
        public static event Action<string> Pressed;
        public static bool Installed => hook != IntPtr.Zero || rawWindow != IntPtr.Zero;
        public static string Mode => rawWindow != IntPtr.Zero ? "raw-input" : hook != IntPtr.Zero ? "hook" : "off";

        [StructLayout(LayoutKind.Sequential)] struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam, lParam; public uint time; public int x, y; }
        [DllImport("user32.dll")] static extern int GetMessage(out MSG m, IntPtr hwnd, uint min, uint max);
        [DllImport("user32.dll")] static extern IntPtr DispatchMessage(ref MSG m);
        [DllImport("user32.dll")] static extern bool PostThreadMessage(uint thread, uint msg, IntPtr w, IntPtr l);
        [DllImport("kernel32.dll")] static extern bool SetThreadPriority(IntPtr thread, int priority);
        [DllImport("kernel32.dll")] static extern IntPtr GetCurrentThread();
        [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();

        delegate IntPtr WndProcDelegate(IntPtr h, uint msg, IntPtr w, IntPtr l);
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct WNDCLASSEX { public int cbSize; public uint style; public WndProcDelegate lpfnWndProc; public int cbClsExtra, cbWndExtra; public IntPtr hInstance, hIcon, hCursor, hbrBackground; public string lpszMenuName, lpszClassName; public IntPtr hIconSm; }
        [StructLayout(LayoutKind.Sequential)] struct RAWINPUTDEVICE { public ushort usUsagePage, usUsage; public uint dwFlags; public IntPtr hwndTarget; }
        [StructLayout(LayoutKind.Sequential)] struct RAWINPUTHEADER { public uint dwType, dwSize; public IntPtr hDevice, wParam; }
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern ushort RegisterClassEx(ref WNDCLASSEX c);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr CreateWindowEx(uint ex, string cls, string name, uint style, int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr inst, IntPtr param);
        [DllImport("user32.dll")] static extern bool DestroyWindow(IntPtr h);
        [DllImport("user32.dll")] static extern IntPtr DefWindowProc(IntPtr h, uint msg, IntPtr w, IntPtr l);
        [DllImport("user32.dll", SetLastError = true)] static extern bool RegisterRawInputDevices([In] RAWINPUTDEVICE[] d, uint n, uint size);
        [DllImport("user32.dll")] static extern uint GetRawInputData(IntPtr raw, uint cmd, IntPtr data, ref uint size, uint header);
        static bool classRegistered;

        public static bool Install()
        {
            bool rawOk = ShellHotkeys.ActiveForThisSession();
            if (rawWindow != IntPtr.Zero) return true;
            if (hook != IntPtr.Zero) { if (!rawOk) return true; Remove(); } // Explorer restarted with Win+E/S/Q off: switch to listening
            if (!rawOk) ShellHotkeys.Take();
            bool ok = rawOk ? InstallRaw() : InstallHook();
            if (!ok && rawOk) ok = InstallHook();
            Log.Write("keyboard mode=" + Mode);
            return ok;
        }

        static bool InstallRaw()
        {
            var hs = Marshal.SizeOf(typeof(RAWINPUTHEADER)); rawHeader = hs;
            using (var ready = new System.Threading.ManualResetEventSlim())
            {
                thread = new System.Threading.Thread(() =>
                {
                    // time-critical, so the mask key is sent within the first milliseconds of a Windows key
                    // press, long before the key is released (when Windows would open Start)
                    SetThreadPriority(GetCurrentThread(), 15 /*THREAD_PRIORITY_TIME_CRITICAL*/);
                    threadId = GetCurrentThreadId();
                    var inst = Native.GetModuleHandle(null);
                    if (!classRegistered)
                    {
                        rawProc = RawWndProc;
                        var wc = new WNDCLASSEX { cbSize = Marshal.SizeOf(typeof(WNDCLASSEX)), lpfnWndProc = rawProc, hInstance = inst, lpszClassName = "BAKA.KeyListener" };
                        classRegistered = RegisterClassEx(ref wc) != 0;
                    }
                    var h = classRegistered ? CreateWindowEx(0, "BAKA.KeyListener", "", 0, 0, 0, 0, 0, new IntPtr(-3) /*HWND_MESSAGE*/, IntPtr.Zero, inst, IntPtr.Zero) : IntPtr.Zero;
                    // keyboard (usage page 1, usage 6), also while BAKA is not in front; no other flags, so keys are never taken away from apps
                    if (h != IntPtr.Zero && !RegisterRawInputDevices(new[] { new RAWINPUTDEVICE { usUsagePage = 1, usUsage = 6, dwFlags = 0x00000100 /*RIDEV_INPUTSINK*/, hwndTarget = h } }, 1, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE))))
                    { DestroyWindow(h); h = IntPtr.Zero; }
                    rawWindow = h;
                    ready.Set();
                    if (h == IntPtr.Zero) return;
                    while (GetMessage(out MSG m, IntPtr.Zero, 0, 0) > 0) DispatchMessage(ref m);
                    RegisterRawInputDevices(new[] { new RAWINPUTDEVICE { usUsagePage = 1, usUsage = 6, dwFlags = 0x00000001 /*RIDEV_REMOVE*/, hwndTarget = IntPtr.Zero } }, 1, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE)));
                    DestroyWindow(h); rawWindow = IntPtr.Zero;
                }) { IsBackground = true, Name = "BAKA key listener" };
                thread.Start();
                ready.Wait(3000);
            }
            return rawWindow != IntPtr.Zero;
        }

        static IntPtr RawWndProc(IntPtr h, uint msg, IntPtr w, IntPtr l)
        {
            if (msg == 0x00FF /*WM_INPUT*/)
            {
                uint size = 0;
                GetRawInputData(l, 0x10000003 /*RID_INPUT*/, IntPtr.Zero, ref size, (uint)rawHeader);
                if (size > 0 && size <= 256)
                {
                    IntPtr buf = Marshal.AllocHGlobal((int)size);
                    try
                    {
                        if (GetRawInputData(l, 0x10000003, buf, ref size, (uint)rawHeader) == size && Marshal.ReadInt32(buf) == 1 /*RIM_TYPEKEYBOARD*/)
                        {
                            bool injected = Marshal.ReadIntPtr(buf, 8) == IntPtr.Zero; // hDevice is 0 for SendInput/keybd_event
                            int flags = Marshal.ReadInt16(buf, rawHeader + 2), vk = (ushort)Marshal.ReadInt16(buf, rawHeader + 6);
                            OnRawKey(vk, (flags & 1 /*RI_KEY_BREAK*/) == 0, injected);
                        }
                    }
                    finally { Marshal.FreeHGlobal(buf); }
                }
                return DefWindowProc(h, msg, w, l); // lets Windows clean up the raw input buffer
            }
            return DefWindowProc(h, msg, w, l);
        }

        static void OnRawKey(int vk, bool down, bool injected)
        {
            if (vk == 0x5B || vk == 0x5C)
            {
                if (down) { if (!winDown) { winDown = true; winUsed = false; raisedVk = 0; if (Enabled) Mask(); } }
                else { bool lone = winDown && !winUsed && Enabled; winDown = false; raisedVk = 0; if (lone) Raise("launchpad"); }
            }
            // 0xE8 is BAKA's own mask key; 0xFF is a filler some keyboards send. Keys sent by software (an
            // on-screen keyboard, remote desktop tools) count like real ones.
            else if (winDown && vk != 0xE8 && vk != 0xFF)
            {
                winUsed = true;
                if (down && Enabled && vk != raisedVk && (vk == 0x45 || vk == 0x53 || vk == 0x51)) { raisedVk = vk; Raise(vk == 0x45 ? "files" : "search"); } // E, S, Q (Explorer's are off); key repeat opens nothing more
                else if (!down && vk == raisedVk) raisedVk = 0;
            }
        }

        static bool InstallHook()
        {
            if (hook != IntPtr.Zero) return true;
            proc = Callback;
            using (var ready = new System.Threading.ManualResetEventSlim())
            {
                thread = new System.Threading.Thread(() =>
                {
                    SetThreadPriority(GetCurrentThread(), 15 /*THREAD_PRIORITY_TIME_CRITICAL*/);
                    threadId = GetCurrentThreadId();
                    hook = Native.SetWindowsHookEx(13, proc, Native.GetModuleHandle(null), 0);
                    ready.Set();
                    if (hook == IntPtr.Zero) return;
                    while (GetMessage(out MSG m, IntPtr.Zero, 0, 0) > 0) { }
                    Native.UnhookWindowsHookEx(hook); hook = IntPtr.Zero;
                }) { IsBackground = true, Name = "BAKA key hook" };
                thread.Start();
                ready.Wait(3000);
            }
            return hook != IntPtr.Zero;
        }
        public static bool InstallHookForTest() => InstallHook();
        // Test only (--keyhook-test): the way R13 installed the hook, on the calling (UI) thread.
        public static bool InstallOnCurrentThread()
        {
            proc = Callback;
            hook = Native.SetWindowsHookEx(13, proc, Native.GetModuleHandle(null), 0);
            threadId = 0;
            return hook != IntPtr.Zero;
        }
        public static void RemoveFromCurrentThread() { if (hook != IntPtr.Zero && threadId == 0) { Native.UnhookWindowsHookEx(hook); hook = IntPtr.Zero; } }
        public static void Remove()
        {
            if ((hook == IntPtr.Zero && rawWindow == IntPtr.Zero) || threadId == 0) return;
            PostThreadMessage(threadId, 0x0012 /*WM_QUIT*/, IntPtr.Zero, IntPtr.Zero);
            thread?.Join(1000);
            winDown = false;
        }
        // Test only (--keyhook-test raw): listen with raw input regardless of Explorer's hotkey setting.
        public static bool InstallRawForTest() => rawWindow != IntPtr.Zero || InstallRaw();

        // Tells Windows the Win key was "used" so Start does not open: a harmless unassigned key (0xE8).
        static void Mask() { Native.keybd_event(0xE8, 0, 0, UIntPtr.Zero); Native.keybd_event(0xE8, 0, 2, UIntPtr.Zero); }

        static IntPtr Callback(int code, IntPtr w, IntPtr l)
        {
            if (code >= 0)
            {
                int vk = Marshal.ReadInt32(l), msg = w.ToInt32(), flags = Marshal.ReadInt32(l, 8);
                bool down = msg == 0x100 || msg == 0x104, up = msg == 0x101 || msg == 0x105, injected = (flags & 0x10) != 0;
                if (vk == 0x5B || vk == 0x5C)
                {
                    if (down) { if (!winDown) { winDown = true; winUsed = false; } }
                    else if (up)
                    {
                        bool lone = winDown && !winUsed && Enabled; winDown = false;
                        // The Win key-up always passes through, or Windows would keep Win held down.
                        if (lone) { Mask(); Raise("launchpad"); }
                    }
                }
                else if (winDown && !injected && vk != 0xE8)
                {
                    winUsed = true;
                    if (Enabled && (vk == 0x45 || vk == 0x53 || vk == 0x51)) // E, S, Q
                    {
                        if (down) { Mask(); Raise(vk == 0x45 ? "files" : "search"); }
                        return new IntPtr(1); // swallowed: Explorer's window / Windows search do not open
                    }
                }
            }
            return Native.CallNextHookEx(hook, code, w, l);
        }
        static void Raise(string what) { try { Pressed?.Invoke(what); } catch { } }
    }

    // The menu bar and dock reserve their edge of the screen like the Windows taskbar does, so maximized
    // windows (and their close / minimize / maximize buttons) stop below the menu bar instead of under it.
    static class AppBars
    {
        static readonly System.Collections.Generic.Dictionary<IntPtr, uint> registered = new System.Collections.Generic.Dictionary<IntPtr, uint>();
        public static uint CallbackMessage = Native.RegisterWindowMessage("BAKA.AppBar");

        public static void Reserve(IntPtr hwnd, uint edge, Native.RECT rect)
        {
            if (Paths.Preview) return;
            var d = new Native.APPBARDATA { cbSize = Marshal.SizeOf(typeof(Native.APPBARDATA)), hWnd = hwnd, uCallbackMessage = CallbackMessage, uEdge = edge, rc = rect };
            if (!registered.ContainsKey(hwnd)) { Native.SHAppBarMessage(Native.ABM_NEW, ref d); registered[hwnd] = edge; }
            Native.SHAppBarMessage(Native.ABM_QUERYPOS, ref d);
            // QUERYPOS may move the rectangle away from other app bars; keep the requested thickness.
            int thick = edge == Native.ABE_TOP || edge == Native.ABE_BOTTOM ? rect.Height : rect.Width;
            switch (edge)
            {
                case Native.ABE_TOP: d.rc.Bottom = d.rc.Top + thick; break;
                case Native.ABE_BOTTOM: d.rc.Top = d.rc.Bottom - thick; break;
                case Native.ABE_LEFT: d.rc.Right = d.rc.Left + thick; break;
                case Native.ABE_RIGHT: d.rc.Left = d.rc.Right - thick; break;
            }
            Native.SHAppBarMessage(Native.ABM_SETPOS, ref d);
        }
        public static void Release(IntPtr hwnd)
        {
            if (!registered.ContainsKey(hwnd)) return;
            var d = new Native.APPBARDATA { cbSize = Marshal.SizeOf(typeof(Native.APPBARDATA)), hWnd = hwnd };
            Native.SHAppBarMessage(Native.ABM_REMOVE, ref d);
            registered.Remove(hwnd);
        }
        public static void ReleaseAll() { foreach (var h in new System.Collections.Generic.List<IntPtr>(registered.Keys)) Release(h); }
    }
}
