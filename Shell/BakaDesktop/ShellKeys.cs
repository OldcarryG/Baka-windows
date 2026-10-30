using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows;

namespace Baka.Desktop
{
    // The Win+ shortcuts that Explorer normally provides (Win+I Settings, Win+D show desktop, Win+A quick
    // settings, Win+Shift+S snip) stop working when BAKA is the shell, because Explorer is not there to
    // handle them. BAKA claims them with RegisterHotKey, which only succeeds when nothing else owns them, so
    // while Explorer is running these do nothing (Windows keeps them) and BAKA takes over only in shell mode.
    static class ShellKeys
    {
        [DllImport("user32.dll", SetLastError = true)] static extern bool RegisterHotKey(IntPtr h, int id, uint mod, uint vk);
        [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr h, int id);
        const uint MOD_SHIFT = 0x0004, MOD_WIN = 0x0008, MOD_NOREPEAT = 0x4000;
        public const int WM_HOTKEY = 0x0312;

        static IntPtr win;
        static bool on;
        static DateTime lastRelease = DateTime.MinValue;
        static readonly Dictionary<int, Action> actions = new Dictionary<int, Action>();

        // Called at startup and whenever Explorer starts or stops: registers the shortcuts in shell mode,
        // releases them otherwise.
        public static void Apply(IntPtr messageWindow)
        {
            if (Paths.Preview) return;
            win = messageWindow;
            // Not while the helper Explorer is used: Explorer registers these keys itself when it starts, and a
            // key BAKA holds at that moment is lost to Explorer for the whole sign-in (Win+I, Win+D, Win+A,
            // Win+Shift+S and Win+N then did nothing at all).
            bool want = ShellMode.Active && win != IntPtr.Zero && !(ShellMode.Chosen && ShellMode.Helper);
            // a release for Explorer stays released while Explorer is being started
            if (want && (DateTime.Now - lastRelease).TotalSeconds < 30) want = false;
            if (want == on) return;
            foreach (var id in new List<int>(actions.Keys)) UnregisterHotKey(win, id);
            actions.Clear();
            on = want;
            if (!want) { Log.Write("shell-keys off"); return; }
            var failed = new List<string>();
            void Reg(int id, uint mod, uint vk, Action a, bool repeat = false)
            { if (RegisterHotKey(win, id, mod | (repeat ? 0 : MOD_NOREPEAT), vk)) actions[id] = a; else failed.Add(id + ":" + Marshal.GetLastWin32Error()); }
            // Win+I: Windows' Settings app needs Explorer, so it opens BAKA's Windows settings panel
            Reg(1, MOD_WIN, 0x49 /*I*/, () => WindowsSettingsPanel.Show("Settings", null));
            Reg(2, MOD_WIN, 0x44 /*D*/, ShowDesktop);
            // Win+A, Win+Tab, Win+arrows, Win+Shift+S (snip) and PrintScreen (snip) are either reserved by
            // Windows (RegisterHotKey returns 1409) or need to see Shift, so BAKA's keyboard hook handles those
            // when Explorer is off (see ExplorerIntegration.CallbackCore); Windows handles them when Explorer is
            // on. Registering them here as well only ever failed or double-fired.
            Reg(13, MOD_WIN, 0x4D /*M*/, WindowKeys.MinimizeAll);
            for (int n = 1; n <= 9; n++) { int k = n; Reg(20 + n, MOD_WIN, (uint)(0x30 + n), () => App.Dock?.OpenNumber(k)); }
            // Win+E is handled by BAKA's Win-key hook (opens Files); registering it here too just failed and
            // showed as 4 of 5. Win+N opens the notification centre instead.
            Reg(5, MOD_WIN, 0x4E /*N*/, () => NotificationCenter.Toggle(App.Bar));
            // Win+R: the Windows Run box lives in shell32 and opens without Explorer
            Reg(6, MOD_WIN, 0x52 /*R*/, () => Launcher.Run("run", () => RunFileDlg(IntPtr.Zero, IntPtr.Zero, null, null, null, 0)));
            // Win+X: BAKA's Control Center (power, volume, settings)
            Reg(7, MOD_WIN, 0x58 /*X*/, () => ControlCenter.Toggle(App.Bar));
            Log.Write("shell-keys on count=" + actions.Count + (failed.Count > 0 ? " failed=" + string.Join(",", failed) : ""));
        }
        [DllImport("shell32.dll", EntryPoint = "#61", CharSet = CharSet.Unicode)] static extern int RunFileDlg(IntPtr owner, IntPtr icon, string dir, string title, string prompt, uint flags);

        // Before Explorer starts (on demand): it must be able to take these keys itself.
        public static void ReleaseAll()
        {
            if (win != IntPtr.Zero) foreach (var id in new List<int>(actions.Keys)) UnregisterHotKey(win, id);
            if (actions.Count > 0) Log.Write("shell-keys released for Explorer");
            actions.Clear(); on = false; lastRelease = DateTime.Now;
        }

        public static void Handle(IntPtr id)
        {
            int n = id.ToInt32();
            if (actions.TryGetValue(n, out var a)) { Log.Write("shell-key id=" + n); try { App.Ui.BeginInvoke(a); } catch (Exception e) { Log.Write("shell-key-failed id=" + n + " error=\"" + e.Message + "\""); } }
            else Log.Write("shell-key-unknown id=" + n);
        }

        // off the UI thread: shell activation can block when BAKA is the shell
        static void Run(string uri) => Launcher.Run(uri, () => System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(uri) { UseShellExecute = true }));

        // Minimize every app window so the desktop shows; press again and they come back (like Win+D).
        static bool desktopShown;
        static readonly List<IntPtr> restore = new List<IntPtr>();
        static void ShowDesktop()
        {
            try
            {
                if (!desktopShown)
                {
                    restore.Clear();
                    uint me = (uint)System.Diagnostics.Process.GetCurrentProcess().Id;
                    Native.EnumWindows((h, p) =>
                    {
                        if (!Native.IsWindowVisible(h) || Native.IsIconic(h)) return true;
                        if ((Native.ExStyle(h) & Native.WS_EX_TOOLWINDOW) != 0) return true;
                        Native.GetWindowThreadProcessId(h, out uint pid); if (pid == me) return true;
                        string cls = Native.ClassName(h); if (cls == "Progman" || cls == "WorkerW") return true;
                        if (Native.GetWindowTextLength(h) == 0) return true;
                        restore.Add(h); Native.ShowWindowAsync(h, Native.SW_MINIMIZE); return true;
                    }, IntPtr.Zero);
                    desktopShown = true;
                }
                else { foreach (var h in restore) if (Native.IsWindow(h)) Native.ShowWindowAsync(h, 9 /*SW_RESTORE*/); restore.Clear(); desktopShown = false; }
            }
            catch (Exception e) { Log.Write("show-desktop-failed error=\"" + e.Message + "\""); }
        }
    }
}
