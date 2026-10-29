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
            if (!ExplorerRunning()) { try { Process.Start(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe")); Log.Write("explorer-started-in-background"); } catch { } }
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

    // Keyboard: a lone Windows key opens the BAKA Launchpad (Start never opens), Win+E opens BAKA Files,
    // Win+S searches in the Launchpad. Every other Win shortcut keeps working. Ctrl+Esc still opens Start.
    static class KeyHook
    {
        // The hook runs on its own thread with time-critical priority and a bare message loop. Windows calls a
        // low-level hook on the thread that installed it and holds every key press until it answers, so on
        // the UI thread a busy frame (layout, rendering, a Settings page loading) delayed keys for every app.
        // This thread does nothing else, so it answers in microseconds.
        static Native.HookProc proc; static volatile IntPtr hook;
        static System.Threading.Thread thread; static uint threadId;
        static bool winDown, winUsed;
        public static volatile bool Enabled = true;
        public static event Action<string> Pressed;
        public static bool Installed => hook != IntPtr.Zero;

        [StructLayout(LayoutKind.Sequential)] struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam, lParam; public uint time; public int x, y; }
        [DllImport("user32.dll")] static extern int GetMessage(out MSG m, IntPtr hwnd, uint min, uint max);
        [DllImport("user32.dll")] static extern bool PostThreadMessage(uint thread, uint msg, IntPtr w, IntPtr l);
        [DllImport("kernel32.dll")] static extern bool SetThreadPriority(IntPtr thread, int priority);
        [DllImport("kernel32.dll")] static extern IntPtr GetCurrentThread();
        [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();

        public static bool Install()
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
            if (hook == IntPtr.Zero || threadId == 0) return;
            PostThreadMessage(threadId, 0x0012 /*WM_QUIT*/, IntPtr.Zero, IntPtr.Zero);
            thread?.Join(1000);
        }

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
