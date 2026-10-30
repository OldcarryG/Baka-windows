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
        // Explorer's taskbar windows only. BAKA's own tray host has the same class name ("Shell_TrayWnd", so apps
        // send it their icons) and BAKA keeps it first in z-order, so FindWindow returned BAKA's invisible host:
        // the taskbar check never saw Explorer's taskbar, and leaving BAKA "showed" BAKA's host while the real
        // taskbar stayed hidden (measured: both windows exist, BAKA's first).
        // Owned by explorer.exe, not merely "not this process": --status and --restore-windows run as their own
        // process, where BAKA Desktop's tray host is someone else's window too.
        // Asked fresh each time (two or three windows, every few seconds): a cached answer could outlive the
        // process and match a new one that got the same id.
        static bool IsExplorerPid(uint pid)
        {
            try { using (var p = Process.GetProcessById((int)pid)) return p.ProcessName.Equals("explorer", StringComparison.OrdinalIgnoreCase); }
            catch { return false; }
        }
        static System.Collections.Generic.IEnumerable<IntPtr> TrayWindows()
        {
            foreach (var cls in TrayClasses)
                for (IntPtr h = Native.FindWindowEx(IntPtr.Zero, IntPtr.Zero, cls, null); h != IntPtr.Zero; h = Native.FindWindowEx(IntPtr.Zero, h, cls, null))
                { Native.GetWindowThreadProcessId(h, out uint pid); if (IsExplorerPid(pid)) yield return h; }
        }
        public static IntPtr ExplorerTaskbar() { foreach (var h in TrayWindows()) if (Native.ClassName(h) == "Shell_TrayWnd") return h; return IntPtr.Zero; }
        // Auto-hide gives the taskbar's strip back to apps; hiding the window removes it from view.
        static void SetAutoHide(bool on)
        {
            var d = new Native.APPBARDATA { cbSize = Marshal.SizeOf(typeof(Native.APPBARDATA)), hWnd = ExplorerTaskbar() };
            if (d.hWnd == IntPtr.Zero) return;
            d.lParam = new IntPtr(on ? 1 : 2); // ABS_AUTOHIDE / ABS_ALWAYSONTOP
            Native.SHAppBarMessage(Native.ABM_SETSTATE, ref d);
        }
        public static bool TaskbarVisible() { foreach (var h in TrayWindows()) if (Native.IsWindowVisible(h)) return true; return false; }

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
        static readonly int mySession = Process.GetCurrentProcess().SessionId;
        public static bool ExplorerRunning()
        {
            bool found = false;
            foreach (var p in Process.GetProcessesByName("explorer")) { try { if (!found && p.SessionId == mySession) found = true; } catch { } finally { p.Dispose(); } }
            return found;
        }
        // Earlier BAKA releases replaced Explorer as the shell; that left no tray, notifications or file
        // dialogs. Explorer is the shell again and runs in the background.
        public static void UndoOldShellOverride()
        {
            if (Paths.Preview) return;
            // BAKA chosen as the shell in Settings > Windows: that is wanted, nothing to undo, and Explorer is
            // not started behind it. Only an override left by an old release (not chosen) is removed.
            if (string.Equals(Json.Str(App.Settings?.Integration, "shell"), "BAKA", StringComparison.OrdinalIgnoreCase) && ShellMode.Chosen) return;
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
            // BAKA's tray host goes first, so apps send their icons back to Explorer's tray
            try { BakaTray.Stop(); } catch { }
            try { TrayFlyout.Restore(); } catch { }
            try { CaptionButtons.RestoreOrphans(); } catch { } // apps' own window buttons back on
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
        static bool altDown, shiftDown, altTabbing;
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
        // Install and Remove run one at a time. They are called from the UI thread (settings, Explorer
        // restart, a game ending) and from the guard's background task (Explorer up / down) at nearly the same
        // moment; without the lock both installed a hook, two hook threads ran, Remove stopped only one (it
        // kept hooking keys during games) and a lone Win press opened and closed the Launchpad.
        static readonly object installLock = new object();

        public static bool Install()
        {
            lock (installLock)
            {
                // a game started while this call waited for the lock: it must not put the hook back
                if (!Enabled) return false;
                bool rawOk = ShellHotkeys.ActiveForThisSession();
                // raw input listens but cannot swallow; the low-level hook can. When Explorer is running (and its
                // Win+E/S/Q are off) raw input is enough. When Explorer closes, switch back to the hook so BAKA
                // can own Win+Tab, Alt+Tab, Win+arrows etc. again.
                if (rawWindow != IntPtr.Zero) { if (rawOk) return true; RemoveLocked(); }
                if (hook != IntPtr.Zero) { if (!rawOk) return true; RemoveLocked(); } // Explorer started with Win+E/S/Q off: switch to listening
                if (!rawOk) ShellHotkeys.Take();
                bool ok = rawOk ? InstallRaw() : InstallHook();
                if (!ok && rawOk) ok = InstallHook();
                Log.Write("keyboard mode=" + Mode);
                return ok;
            }
        }

        // Win+L, Ctrl+Alt+Del and UAC prompts switch to the secure desktop; the key-up of Win or Alt happens
        // there and BAKA never hears it, so BAKA kept believing the key was held: after unlocking, typing E/S/Q
        // opened Files or search, and every Tab opened the switcher. Before acting on a held Win or Alt, BAKA
        // asks Windows whether it really is down, and forgets it if not.
        static bool Held(int vk) => (Native.GetAsyncKeyState(vk) & 0x8000) != 0;
        static bool WinReallyDown() => Held(0x5B) || Held(0x5C);
        static void ResetKeys() { winDown = winUsed = altDown = shiftDown = altTabbing = false; raisedVk = 0; }

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
                    if (rawWindow == h)
                        RegisterRawInputDevices(new[] { new RAWINPUTDEVICE { usUsagePage = 1, usUsage = 6, dwFlags = 0x00000001 /*RIDEV_REMOVE*/, hwndTarget = IntPtr.Zero } }, 1, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE)));
                    DestroyWindow(h);
                    if (rawWindow == h) rawWindow = IntPtr.Zero;
                }) { IsBackground = true, Name = "BAKA key listener" };
                thread.Start();
                ready.Wait(3000);
            }
            return rawWindow != IntPtr.Zero;
        }

        // Windows calls this from outside .NET; an exception escaping it would end BAKA Desktop.
        static IntPtr RawWndProc(IntPtr h, uint msg, IntPtr w, IntPtr l)
        {
            try { return RawWndProcCore(h, msg, w, l); }
            catch { return DefWindowProc(h, msg, w, l); }
        }
        static IntPtr RawWndProcCore(IntPtr h, uint msg, IntPtr w, IntPtr l)
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
            // volume keys: BAKA changes the volume and shows a bar only when it is the shell (App decides);
            // raw input never swallows, so Windows' own handling is untouched when Explorer is running
            if (down && (vk == 0xAD || vk == 0xAE || vk == 0xAF)) { Raise(vk == 0xAD ? "volmute" : vk == 0xAE ? "voldown" : "volup"); return; }
            if (vk == 0x10 || vk == 0xA0 || vk == 0xA1) { shiftDown = down; }   // track Shift for Win+Shift+S
            // Raw input is used while the helper Explorer runs, and then Windows' Snipping Tool answers
            // PrintScreen itself (measured: "Snipping Tool Overlay" opened). Raw input cannot swallow the key,
            // so BAKA leaving PrintScreen alone here is what keeps two screenshot tools from opening at once.
            // Win+Shift+S is different: with Explorer's Win+S switched off Windows opens nothing (measured),
            // so BAKA's snip answers it.
            if (vk == 0x2C) { if (down && winDown && !winUsed) { winUsed = true; Raise("win-used"); } return; }
            if (down && vk == 0x1B && CheatSheetOpen) Raise("cheat-escape");
            if (vk == 0x5B || vk == 0x5C)
            {
                // The mask (0xE8, which tells Windows the Win key was "used" so Start/Search does not open)
                // goes out on the first press when a tap of Win opens the Launchpad, and again on EVERY
                // auto-repeat while the key is held. Masking only the first press was not enough: a held Win
                // repeats its key-down about every 33 ms, and those unmasked repeats re-armed Windows, so
                // letting go after holding for the cheat sheet opened Search (measured 5/5; masking each
                // repeat fixed it 0/3). Repeats are also masked while the cheat sheet is up even if a tap does
                // not open the Launchpad, so holding for the sheet never opens Start either.
                if (down)
                {
                    if (!winDown) { winDown = true; winUsed = false; raisedVk = 0; winDownTick = Environment.TickCount; cheatRaised = false; if (Enabled) { if (MaskWin) Mask(); Raise("win-down"); } }
                    else { if (Enabled && MaskHeld) Mask(); HoldTick(); }
                }
                else { bool lone = winDown && !winUsed && Enabled; winDown = false; raisedVk = 0; Raise(lone ? "win-up-lone" : "win-up"); }
            }
            // 0xE8 is BAKA's own mask key; 0xFF is a filler some keyboards send. Keys sent by software (an
            // on-screen keyboard, remote desktop tools) count like real ones.
            else if (winDown && vk != 0xE8 && vk != 0xFF)
            {
                // the Win key-up happened on the secure desktop (Win+L, Ctrl+Alt+Del): forget the stale press
                if (down && !WinReallyDown()) { winDown = false; raisedVk = 0; return; }
                if (!winUsed) { winUsed = true; Raise("win-used"); }
                if (down && Enabled && vk != raisedVk)
                {
                    if (vk == 0x53 && shiftDown && Held(0x10)) { raisedVk = vk; Raise("snip"); }                     // Win+Shift+S -> snip
                    else if (vk == 0x45 || vk == 0x53 || vk == 0x51) { raisedVk = vk; Raise(vk == 0x45 ? "files" : "search"); } // E, S, Q (Explorer's are off); key repeat opens nothing more
                    // Win+/ only here: raw input cannot swallow, and Explorer's own Win+F1 would open Windows Help too
                    else if (vk == 0xBF) { raisedVk = vk; Raise("cheat-sheet"); }
                }
                else if (!down && vk == raisedVk) raisedVk = 0;
            }
        }
        public static volatile bool CheatSheetOpen;
        // Whether a tap of Win is BAKA's (Launchpad) and so must be masked from Windows' Start.
        public static volatile bool MaskWin = true;
        // Whether a HELD Win must be masked on every auto-repeat (so letting go never opens Start): true when
        // the Win key opens the Launchpad, or when holding Win shows the cheat sheet.
        public static volatile bool MaskHeld = true;
        // Whether holding Win shows the shortcut cheat sheet.
        public static volatile bool CheatHold = true;
        static int winDownTick; static bool cheatRaised;
        // Called on each auto-repeat of a held, so-far-unused Win key. When it has been held about 0.7 s the
        // cheat sheet is asked for (once). The hold is timed here, on the keyboard thread, because a UI timer
        // was starved by the auto-repeat itself. winUsed is set now so the release opens neither Start nor the
        // Launchpad.
        static void HoldTick()
        {
            if (!Enabled || !CheatHold || winUsed || cheatRaised) return;
            if (Environment.TickCount - winDownTick < 700) return;
            cheatRaised = true; winUsed = true; Mask(); Raise("cheat-sheet-hold");
        }

        static bool InstallHook()
        {
            if (hook != IntPtr.Zero) return true;
            // made once and kept: a new delegate per install let the one Windows still held be collected
            if (proc == null) proc = Callback;
            using (var ready = new System.Threading.ManualResetEventSlim())
            {
                thread = new System.Threading.Thread(() =>
                {
                    SetThreadPriority(GetCurrentThread(), 15 /*THREAD_PRIORITY_TIME_CRITICAL*/);
                    threadId = GetCurrentThreadId();
                    // this thread's own hook, so a late exit never unhooks a newer one installed meanwhile
                    var mine = Native.SetWindowsHookEx(13, proc, Native.GetModuleHandle(null), 0);
                    hook = mine;
                    ready.Set();
                    if (mine == IntPtr.Zero) return;
                    while (GetMessage(out MSG m, IntPtr.Zero, 0, 0) > 0) { }
                    Native.UnhookWindowsHookEx(mine);
                    if (hook == mine) hook = IntPtr.Zero;
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
            if (proc == null) proc = Callback;
            hook = Native.SetWindowsHookEx(13, proc, Native.GetModuleHandle(null), 0);
            threadId = 0;
            return hook != IntPtr.Zero;
        }
        public static void RemoveFromCurrentThread() { if (hook != IntPtr.Zero && threadId == 0) { Native.UnhookWindowsHookEx(hook); hook = IntPtr.Zero; } }
        public static void Remove() { lock (installLock) RemoveLocked(); }
        static void RemoveLocked()
        {
            if ((hook == IntPtr.Zero && rawWindow == IntPtr.Zero) || threadId == 0) return;
            PostThreadMessage(threadId, 0x0012 /*WM_QUIT*/, IntPtr.Zero, IntPtr.Zero);
            thread?.Join(1000);
            ResetKeys();
        }
        // The session was locked / unlocked or switched: any key held before is not held now.
        public static void ForgetKeys() => ResetKeys();
        // Test only (--keyhook-test raw): listen with raw input regardless of Explorer's hotkey setting.
        public static bool InstallRawForTest() => rawWindow != IntPtr.Zero || InstallRaw();

        // Tells Windows the Win key was "used" so Start does not open: a harmless unassigned key (0xE8).
        static void Mask() { Native.keybd_event(0xE8, 0, 0, UIntPtr.Zero); Native.keybd_event(0xE8, 0, 2, UIntPtr.Zero); }

        static IntPtr Callback(int code, IntPtr w, IntPtr l)
        {
            try { return CallbackCore(code, w, l); }
            catch { return Native.CallNextHookEx(hook, code, w, l); }
        }
        static IntPtr CallbackCore(int code, IntPtr w, IntPtr l)
        {
            if (code >= 0)
            {
                int vk = Marshal.ReadInt32(l), msg = w.ToInt32(), flags = Marshal.ReadInt32(l, 8);
                bool down = msg == 0x100 || msg == 0x104, up = msg == 0x101 || msg == 0x105, injected = (flags & 0x10) != 0;
                if (down && (vk == 0xAD || vk == 0xAE || vk == 0xAF)) Raise(vk == 0xAD ? "volmute" : vk == 0xAE ? "voldown" : "volup"); // not swallowed
                // track Shift and Alt so Alt+Tab (and Alt+Shift+Tab) can be handled; Alt comes as a syskey
                if (vk == 0x10 || vk == 0xA0 || vk == 0xA1) shiftDown = down || (up ? false : shiftDown);
                if (vk == 0x12 || vk == 0xA4 || vk == 0xA5)
                {
                    altDown = down;
                    if (up && altTabbing)
                    {
                        // The app saw Alt down and Alt up with nothing in between (Tab was swallowed) and would
                        // treat it as a lone Alt press: its menu bar or Office's key tips opened. The mask key
                        // between them makes it a combination.
                        altTabbing = false; Mask(); Raise("alt-commit"); // let go of Alt: switch to the chosen window
                    }
                }
                if (down && vk == 0x1B && CheatSheetOpen) Raise("cheat-escape");
                if (vk == 0x5B || vk == 0x5C)
                {
                    if (down)
                    {
                        if (!winDown) { winDown = true; winUsed = false; raisedVk = 0; winDownTick = Environment.TickCount; cheatRaised = false; if (Enabled) { if (MaskWin) Mask(); Raise("win-down"); } }
                        // a held Win auto-repeats: mask each repeat so letting go never opens Start (see the
                        // raw-input branch for why the first mask alone was not enough), and time the hold here
                        else { if (Enabled && MaskHeld) Mask(); HoldTick(); }
                    }
                    else if (up)
                    {
                        bool lone = winDown && !winUsed && Enabled; winDown = false; raisedVk = 0;
                        // The Win key-up always passes through, or Windows would keep Win held down.
                        if (lone && MaskWin) Mask();
                        Raise(lone ? "win-up-lone" : "win-up");
                    }
                }
                // Alt+Tab: BAKA's own switcher instead of Windows' (which needs Explorer). The hook drives it so
                // it works while Alt is held without the window ever taking focus. Alt released on the secure
                // desktop (Ctrl+Alt+Del) is not seen: confirmed with Windows before every Tab is taken.
                else if (altDown && !injected && Enabled && vk == 0x09 /*Tab*/ && down)
                {
                    if (!Held(0x12)) { altDown = false; altTabbing = false; return Native.CallNextHookEx(hook, code, w, l); }
                    altTabbing = true; Raise(shiftDown ? "alt-tab-back" : "alt-tab");
                    return new IntPtr(1);
                }
                // PrintScreen on its own: BAKA's snip (Windows' own would need the Snipping Tool / Explorer).
                // Swallowed so Windows does not also copy the whole screen to the clipboard behind BAKA's snip.
                else if (vk == 0x2C && down && !injected && Enabled && !altDown) { if (winDown && !winUsed) { winUsed = true; Raise("win-used"); } Raise("snip"); return new IntPtr(1); }
                else if (winDown && vk != 0xE8)
                {
                    // the Win key-up happened on the secure desktop (Win+L, Ctrl+Alt+Del): forget it, pass the key
                    if (down && !WinReallyDown()) { winDown = false; raisedVk = 0; return Native.CallNextHookEx(hook, code, w, l); }
                    // Any other key while Win is held makes it a combination (so Start does not open), also one
                    // BAKA sent itself. Injected keys are never swallowed.
                    if (!winUsed) { winUsed = true; Raise("win-used"); }
                    if (up && vk == raisedVk) raisedVk = 0;
                    if (!injected && Enabled && down)
                    {
                        // Win shortcuts that Windows reserves (RegisterHotKey is refused: Win+Tab, Win+arrows,
                        // Win+A) are handled here in the hook, which sees every key first. A held key repeats its
                        // key-down: those that open something act once per press (Win+E held opened a Files
                        // window per repeat, Win+Tab and Win+/ flickered), the arrows repeat like Windows' own.
                        switch (vk)
                        {
                            case 0x45: return Once(vk, "files");                                // E
                            case 0x53: return Once(vk, shiftDown ? "snip" : "search");           // Win+Shift+S = snip, Win+S = search
                            case 0x51: return Once(vk, "search");                               // Q
                            case 0x09: return Once(vk, "switcher");                             // Tab
                            case 0x25: Mask(); Raise("snap-left"); return new IntPtr(1);       // Left
                            case 0x27: Mask(); Raise("snap-right"); return new IntPtr(1);      // Right
                            case 0x26: Mask(); Raise("snap-up"); return new IntPtr(1);         // Up
                            case 0x28: Mask(); Raise("snap-down"); return new IntPtr(1);       // Down
                            case 0x41: return Once(vk, "control-center");                       // A
                            case 0xBF: case 0x70: return Once(vk, "cheat-sheet");               // / or F1
                        }
                    }
                }
            }
            return Native.CallNextHookEx(hook, code, w, l);
        }
        static void Raise(string what) { try { Pressed?.Invoke(what); } catch { } }
        // a Win shortcut that opens something: swallowed every time, acted on once per press
        static IntPtr Once(int vk, string what) { Mask(); if (raisedVk != vk) { raisedVk = vk; Raise(what); } return new IntPtr(1); }
        // The cheat sheet opened by holding Win: the press counts as a combination from here on, so its release
        // neither opens the Launchpad (BAKA) nor Start / Search (Windows).
        public static void MaskNow() { winUsed = true; if (winDown) Mask(); }
    }

    // The menu bar and dock reserve their edge of the screen like the Windows taskbar does, so maximized
    // windows (and their close / minimize / maximize buttons) stop below the menu bar instead of under it.
    static class AppBars
    {
        static readonly System.Collections.Generic.Dictionary<IntPtr, uint> registered = new System.Collections.Generic.Dictionary<IntPtr, uint>();
        static readonly System.Collections.Generic.Dictionary<IntPtr, Native.RECT> reserved = new System.Collections.Generic.Dictionary<IntPtr, Native.RECT>();
        public static uint CallbackMessage = Native.RegisterWindowMessage("BAKA.AppBar");

        // Explorer restarted: it no longer knows BAKA's reservations, so they are made again from scratch.
        // lastWork is forgotten too: Explorer changed the real work area, so the next one must be set even if
        // it equals what BAKA set before Explorer started (it was skipped, and maximized windows slid under
        // the dock when only the dock reserved space).
        public static void Forget() { registered.Clear(); reserved.Clear(); reRegisters = 0; gaveUp = false; lastWork = default(Native.RECT); }

        // BAKA is the shell: Explorer's app-bar manager is not there, so the edges are kept free by setting the
        // screen's work area directly (what that manager would do), from the same reservations.
        public static bool UseWorkArea;
        static Native.RECT lastWork;
        // The work area BAKA's reservations ask for (screen minus the menu bar and dock strips).
        static Native.RECT Desired()
        {
            var b = System.Windows.Forms.Screen.PrimaryScreen.Bounds;
            var work = new Native.RECT { Left = b.Left, Top = b.Top, Right = b.Right, Bottom = b.Bottom };
            foreach (var kv in reserved)
            {
                if (!registered.TryGetValue(kv.Key, out uint edge)) continue;
                var r = kv.Value;
                if (edge == Native.ABE_TOP) work.Top = Math.Max(work.Top, r.Bottom);
                else if (edge == Native.ABE_BOTTOM) work.Bottom = Math.Min(work.Bottom, r.Top);
                else if (edge == Native.ABE_LEFT) work.Left = Math.Max(work.Left, r.Right);
                else if (edge == Native.ABE_RIGHT) work.Right = Math.Min(work.Right, r.Left);
            }
            return work;
        }

        // Next to the helper Explorer the reservations go through Explorer's app-bar manager, which applied the
        // menu bar but dropped the dock (measured: work area 0,50-1920,1080 with the dock on the left, so
        // maximized apps slid under it). Every few seconds BAKA checks the real work area and, if a strip is
        // missing, sets it directly. If Explorer keeps undoing it, BAKA stops after 5 tries a minute, so the
        // two never fight (each change moves every maximized window).
        // Setting the work area directly does not stick next to Explorer (measured: Explorer put it back to
        // 0,50-1920,1080 within 3 s, every time), and fighting it would move every maximized window again and
        // again. So BAKA re-registers its app bars with Explorer instead (remove + new + set position), which
        // is the way Explorer's own manager is meant to learn about them; at most 3 times, then it stops and
        // logs, so nothing ever loops.
        static int reRegisters; static bool gaveUp;
        public static void Verify()
        {
            if (UseWorkArea || Paths.Preview || reserved.Count == 0 || gaveUp) return;
            var want = Desired();
            var cur = new Native.RECT();
            if (!Native.SystemParametersInfo(0x0030 /*SPI_GETWORKAREA*/, 0, ref cur, 0)) return;
            if (cur.Left >= want.Left && cur.Top >= want.Top && cur.Right <= want.Right && cur.Bottom <= want.Bottom) return;
            // Next to the helper Explorer, Explorer's app-bar manager honours the top menu bar but refuses a
            // left/right dock from a non-shell process: it recomputes the work area from its own known bars and
            // forces the dock's edge back to zero within a few seconds (measured), so maximized windows slide
            // under the dock. Re-registering (remove + new) only made it worse, dropping even the menu bar.
            // BAKA sets the work area directly once; on a Windows build where that sticks the dock is reserved
            // for good, and where Explorer overrides it BAKA stops immediately rather than flicker every
            // maximized window by fighting. The top menu bar stays reserved either way.
            if (reRegisters >= 1) { gaveUp = true; Log.Write("work-area-mismatch was=" + cur.Left + "," + cur.Top + "-" + cur.Right + "," + cur.Bottom + " want=" + want.Left + "," + want.Top + "-" + want.Right + "," + want.Bottom + " (Explorer overrides a left/right dock; the menu bar stays reserved)"); return; }
            reRegisters++;
            var set = want;
            Native.SystemParametersInfo(0x002F /*SPI_SETWORKAREA*/, 0, ref set, 0x0002 /*SPIF_SENDCHANGE*/);
            Log.Write("work-area-set try=" + reRegisters + " was=" + cur.Left + "," + cur.Top + "-" + cur.Right + "," + cur.Bottom + " -> " + want.Left + "," + want.Top + "-" + want.Right + "," + want.Bottom);
        }

        public static void ApplyWorkArea()
        {
            if (!UseWorkArea || Paths.Preview) return;
            var work = Desired();
            if (work.Left == lastWork.Left && work.Top == lastWork.Top && work.Right == lastWork.Right && work.Bottom == lastWork.Bottom) return;
            lastWork = work;
            Native.SystemParametersInfo(0x002F /*SPI_SETWORKAREA*/, 0, ref work, 0x0002 /*SPIF_SENDCHANGE*/);
            Log.Write("work-area left=" + work.Left + " top=" + work.Top + " right=" + work.Right + " bottom=" + work.Bottom);
        }

        public static void Reserve(IntPtr hwnd, uint edge, Native.RECT rect)
        {
            if (Paths.Preview) return;
            if (UseWorkArea) { registered[hwnd] = edge; reserved[hwnd] = rect; ApplyWorkArea(); return; }
            // Every reservation makes Windows move every maximized window; R15 sent one each time the dock
            // refreshed, so maximized apps jumped whenever an app opened or closed. Only real changes are sent.
            if (registered.TryGetValue(hwnd, out uint was) && was == edge && reserved.TryGetValue(hwnd, out var last)
                && last.Left == rect.Left && last.Top == rect.Top && last.Right == rect.Right && last.Bottom == rect.Bottom) return;
            reserved[hwnd] = rect;
            var d = new Native.APPBARDATA { cbSize = Marshal.SizeOf(typeof(Native.APPBARDATA)), hWnd = hwnd, uCallbackMessage = CallbackMessage, uEdge = edge, rc = rect };
            bool fresh = !registered.ContainsKey(hwnd);
            ulong added = fresh ? Native.SHAppBarMessage(Native.ABM_NEW, ref d).ToUInt64() : 1;
            registered[hwnd] = edge;
            Native.SHAppBarMessage(Native.ABM_QUERYPOS, ref d);
            if (fresh) Log.Write("appbar-new edge=" + edge + " ok=" + added + " asked=" + rect.Left + "," + rect.Top + "-" + rect.Right + "," + rect.Bottom + " got=" + d.rc.Left + "," + d.rc.Top + "-" + d.rc.Right + "," + d.rc.Bottom);
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
            if (UseWorkArea) { registered.Remove(hwnd); reserved.Remove(hwnd); ApplyWorkArea(); return; }
            var d = new Native.APPBARDATA { cbSize = Marshal.SizeOf(typeof(Native.APPBARDATA)), hWnd = hwnd };
            Native.SHAppBarMessage(Native.ABM_REMOVE, ref d);
            registered.Remove(hwnd); reserved.Remove(hwnd);
        }
        public static void ReleaseAll() { foreach (var h in new System.Collections.Generic.List<IntPtr>(registered.Keys)) Release(h); }
    }
}
