using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;

namespace Baka.Desktop
{
    static class App
    {
        public static Settings Settings;
        public static bool GameRunning;
        public static IntPtr GameWindow; // the game's window while GameRunning (the overlay follows it); zero when not known
        public static Dispatcher Ui;
        public static string Exe => Process.GetCurrentProcess().MainModule.FileName;
        public static string Version => typeof(App).Assembly.GetName().Version.ToString(3);
        public static readonly string MessageWindowTitle = "BAKA.Desktop.Messages";
        static Mutex instance;
        static HwndSource messages;
        static DispatcherTimer clock, windows, profile;
        public static TopBar Bar; public static Dock Dock;
        public static event Action Tick;         // every second (clock, timers)
        public static event Action WindowsChanged; // open windows changed

        [STAThread]
        static int Main(string[] args)
        {
            var a = new HashSet<string>(args.Select(x => x.ToLowerInvariant()));
            string Arg(string name) { int i = Array.FindIndex(args, x => x.Equals(name, StringComparison.OrdinalIgnoreCase)); return i >= 0 && i + 1 < args.Length ? args[i + 1] : null; }

            if (a.Contains("--open")) return Forward("open|" + (Arg("--open") ?? ""), () => Process.Start(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe"), "\"" + Arg("--open") + "\""));
            if (a.Contains("--settings")) return Forward("settings|", () => { });
            // --profile gaming|desktop: what Arena does, from the command line (used by the VM benchmark)
            if (a.Contains("--profile")) return Forward("profile|" + (Arg("--profile") ?? ""), () => { });
            // --tray: what Control Center's tray button does (shows the Windows tray icons for a few seconds)
            if (a.Contains("--tray")) return Forward("tray|", () => { });
            // --wallpaper <picture or video>: sets the desktop background on the running desktop
            if (a.Contains("--wallpaper")) return Forward("wallpaper|" + Path.GetFullPath(Arg("--wallpaper") ?? "."), () => { });
            if (a.Contains("--adblock")) return AdBlockDns.Run(!string.Equals(Arg("--adblock"), "off", StringComparison.OrdinalIgnoreCase));
            // --focus on|off|toggle and --overlay on|off|toggle: Focus mode and the game overlay on the running desktop
            if (a.Contains("--focus")) return Forward("focus|" + (Arg("--focus") ?? "toggle"), () => { });
            if (a.Contains("--overlay")) return Forward("overlay|" + (Arg("--overlay") ?? "toggle"), () => { });
            // --fps-access on|off --user <SID>: elevated, from Settings > Focus & games (Performance Log Users)
            if (a.Contains("--fps-access")) return FpsAccess.Run(Arg("--fps-access"), Arg("--user"));
            // --fps-probe <seconds> <result.json>: what Windows' graphics event log reports (elevated test)
            if (a.Contains("--fps-probe"))
            {
                int i = Array.FindIndex(args, x => x.Equals("--fps-probe", StringComparison.OrdinalIgnoreCase));
                int sec = i + 1 < args.Length && int.TryParse(args[i + 1], out int s) ? s : 8;
                return Fps.Probe(sec, i + 2 < args.Length ? args[i + 2] : Path.Combine(Path.GetTempPath(), "baka-fps-probe.json"), a.Contains("filtered"));
            }
            // --overlay-test <result.json>: the game overlay and the per-app volume list, checked on this PC
            if (a.Contains("--overlay-test")) return GameOverlay.Test(Arg("--overlay-test") ?? Path.Combine(Path.GetTempPath(), "baka-overlay-test.json"));
            if (a.Contains("--status")) return Status(Arg("--status"));
            // --keyhook-test thread|ui <seconds>: installs only the keyboard hook (Windows-key actions off, every
            // key passes through) while the main thread is kept busy like a UI thread drawing frames
            // (40 ms of work, then messages are handled). Used to measure what the hook adds to key latency.
            if (a.Contains("--keyhook-test"))
            {
                int i = Array.FindIndex(args, x => x.Equals("--keyhook-test", StringComparison.OrdinalIgnoreCase));
                string mode = i + 1 < args.Length ? args[i + 1] : "thread";
                int sec = i + 2 < args.Length && int.TryParse(args[i + 2], out int s) ? s : 30;
                KeyHook.Enabled = false;
                bool ok = mode == "ui" ? KeyHook.InstallOnCurrentThread() : mode == "raw" ? KeyHook.InstallRawForTest() : KeyHook.InstallHookForTest();
                var end = DateTime.UtcNow.AddSeconds(sec);
                while (DateTime.UtcNow < end)
                {
                    var busy = DateTime.UtcNow.AddMilliseconds(40); while (DateTime.UtcNow < busy) { }
                    System.Windows.Forms.Application.DoEvents(); System.Threading.Thread.Sleep(10);
                }
                if (mode == "ui") KeyHook.RemoveFromCurrentThread(); else KeyHook.Remove();
                return ok ? 0 : 1;
            }
            // --video-test <file> <result.json> [seconds]: checks the video wallpaper player on this PC
            if (a.Contains("--video-test"))
            {
                int i = Array.FindIndex(args, x => x.Equals("--video-test", StringComparison.OrdinalIgnoreCase));
                if (i + 2 >= args.Length) return 2;
                Paths.Init(true);
                return VideoTest.Run(args[i + 1], args[i + 2], i + 3 < args.Length && int.TryParse(args[i + 3], out int sec) ? sec : 20);
            }
            if (a.Contains("--restore-windows")) { Paths.Init(false); ExplorerIntegration.RestoreAll(); ExplorerIntegration.SetFolderHandler(false, ""); ShellHotkeys.Release(); WindowsBanners.Restore(); return 0; }
            // --shellcheck <result.json>: exercises the shell-mode components in-process (no Explorer kill, no
            // registry change) so the tray protocol parsing, icon rendering, audio and language code are tested.
            if (a.Contains("--shellcheck")) return ShellCheck.Run(Arg("--shellcheck") ?? System.IO.Path.Combine(System.IO.Path.GetTempPath(), "shellcheck.json"));
            // --tray-test <result.json>: borrows the real tray into a BAKA flyout and gives it straight back,
            // then records whether the tray is present before and after, so the reparent + restore can be
            // checked without a game or sign-out.
            if (a.Contains("--tray-test")) { try { System.IO.File.WriteAllText(Arg("--tray-test") ?? System.IO.Path.Combine(System.IO.Path.GetTempPath(), "t.json"), "{\"skipped\":\"tray reparent was reverted\"}"); } catch { } return 0; }
            bool preview = a.Contains("--preview") || a.Contains("--selftest") || a.Contains("--capture") || a.Contains("--icon-sheet");
            if (!a.Contains("--ui") && !preview) return Supervise();
            return RunUi(preview, a.Contains("--selftest"), Arg("--capture"), Arg("--icon-sheet"));
        }

        // The supervisor: starts the desktop, starts it again if it ever crashes, and after three crashes in
        // two minutes gives the user a normal Windows taskbar and desktop instead of a broken screen.
        static int Supervise()
        {
            Paths.Init(false);
            var crashes = new List<DateTime>();
            string logon = DateTime.Now.ToString("yyyyMMddHHmmss");
            while (true)
            {
                int code;
                try
                {
                    var psi = new ProcessStartInfo(Exe, "--ui") { UseShellExecute = false };
                    psi.EnvironmentVariables["BAKA_LOGON"] = logon; // one sign-in, however often the desktop restarts
                    using (var p = Process.Start(psi)) { p.WaitForExit(); code = p.ExitCode; }
                }
                catch (Exception e) { Log.Write("supervisor-start-failed error=\"" + e.Message + "\""); code = -1; }
                if (code == 0 || code == 3) return 0; // closed on purpose, or already running
                // Signing out, restarting or shutting down: Windows ends the desktop (0x40010004). That is not a
                // crash. Nothing is restored, so the next sign-in starts with the taskbar still hidden instead of
                // showing it until BAKA Desktop hides it again, and nothing is restarted while Windows shuts down.
                if (code == unchecked((int)0x40010004) || SessionEnding())
                {
                    Log.Write("desktop-ended-with-session code=" + code);
                    return 0;
                }
                Log.Write("desktop-crashed code=" + code);
                ExplorerIntegration.RestoreAll();
                try { Fps.StopLeftover(); } catch { } // the crashed desktop's frame counter session
                // the crashed desktop's tray host is gone with it: tray icons go back to Explorer's tray
                BakaTray.AnnounceToExplorer();
                crashes.Add(DateTime.Now); crashes.RemoveAll(t => t < DateTime.Now.AddMinutes(-2));
                if (crashes.Count >= 3)
                {
                    Log.Write("desktop-gave-up; Windows taskbar restored");
                    ShellHotkeys.Release();
                    try { WindowsBanners.Restore(); } catch { } // no BAKA pop-ups now: Windows' banners back
                    // A crash during the Gaming profile left transparency, animations and background apps off
                    // for the rest of the session: only a normal BAKA start undid it, and none follows here.
                    try { Profiles.Recover(); } catch { }
                    // BAKA is the shell: there is no taskbar to bring back, so Explorer is started as the shell
                    // for this sign-in (the BAKA choice stays; the next sign-in tries BAKA again).
                    if (!ExplorerIntegration.ExplorerRunning())
                    {
                        try { Process.Start(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe")); Log.Write("explorer-started-after-crashes"); } catch { }
                    }
                    System.Windows.Forms.MessageBox.Show("BAKA Desktop stopped three times, so the normal Windows taskbar and desktop are back.\n\nStart BAKA Desktop again from the Start menu. The log is in %LOCALAPPDATA%\\BAKA\\Logs.", "BAKA Desktop", System.Windows.Forms.MessageBoxButtons.OK, System.Windows.Forms.MessageBoxIcon.Warning);
                    return 1;
                }
                Thread.Sleep(1500);
            }
        }

        [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
        static bool SessionEnding() => sessionEnding || GetSystemMetrics(0x2000 /*SM_SHUTTINGDOWN*/) != 0;
        static volatile bool sessionEnding;

        static string LastLogLine(string marker)
        {
            try
            {
                string f = Environment.ExpandEnvironmentVariables(@"%LOCALAPPDATA%\BAKA\Logs\Desktop.log");
                using (var s = new FileStream(f, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                using (var r = new StreamReader(s)) { string line, last = ""; while ((line = r.ReadLine()) != null) if (line.Contains(marker)) last = line; return last; }
            }
            catch { return ""; }
        }
        // What a person would see, as JSON (used by the VM acceptance test from inside the user's session).
        static int Status(string path)
        {
            var work = new Native.RECT(); Native.SystemParametersInfo(0x0030, 0, ref work, 0);
            var tray = ExplorerIntegration.ExplorerTaskbar(); // Explorer's, not BAKA's tray host of the same class
            int session = Process.GetCurrentProcess().SessionId;
            bool Running(string n) => Process.GetProcessesByName(n).Any(p => { try { return p.SessionId == session; } catch { return false; } });
            string verb = null;
            try { using (var k = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Classes\Directory\shell")) verb = k?.GetValue("") as string; } catch { }
            string shell = null;
            try { using (var k = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows NT\CurrentVersion\Winlogon")) shell = k?.GetValue("Shell") as string; } catch { }
            var doc = new Dictionary<string, object>
            {
                ["time"] = DateTime.Now.ToString("o"), ["user"] = Environment.UserName, ["session"] = session,
                ["bakaDesktopRunning"] = Process.GetProcessesByName("BakaDesktop").Count(p => { try { return p.SessionId == session; } catch { return false; } }),
                ["explorerRunning"] = Running("explorer"), ["taskbarVisible"] = tray != IntPtr.Zero && Native.IsWindowVisible(tray),
                ["menuBarWindow"] = Native.FindWindow(null, "BAKA Menu Bar") != IntPtr.Zero, ["dockWindow"] = Native.FindWindow(null, "BAKA Dock") != IntPtr.Zero,
                ["workAreaTop"] = work.Top, ["workAreaLeft"] = work.Left, ["dockWidth"] = DockWidth(), ["folderVerb"] = verb ?? "", ["shellOverride"] = shell ?? "",
                ["adBlockDns"] = AdBlockDns.On, ["edgeInstalled"] = System.IO.File.Exists(Environment.ExpandEnvironmentVariables(@"%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe")),
                ["videoWallpaper"] = LastLogLine("video-"),
                ["keyboardMode"] = LastLogLine("keyboard mode="),
                ["webView2Installed"] = System.IO.Directory.Exists(Environment.ExpandEnvironmentVariables(@"%ProgramFiles(x86)%\Microsoft\EdgeWebView\Application")),
                ["bakaBrowserInstalled"] = System.IO.File.Exists(Environment.ExpandEnvironmentVariables(@"%LOCALAPPDATA%\BakaBrowser\current\baka.exe")),
            };
            string json = Json.Write(doc);
            if (string.IsNullOrEmpty(path)) Console.WriteLine(json); else System.IO.File.WriteAllText(path, json);
            return 0;
        }

        static int DockWidth() { var h = Native.FindWindow(null, "BAKA Dock"); return h != IntPtr.Zero && Native.GetWindowRect(h, out var r) ? r.Right - r.Left : 0; }

        // Hands a request (open a folder, open Settings) to the running desktop.
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, ref COPYDATASTRUCT l);
        [StructLayout(LayoutKind.Sequential)] struct COPYDATASTRUCT { public IntPtr dwData; public int cbData; public IntPtr lpData; }
        static int Forward(string message, Action fallback)
        {
            IntPtr target = Native.FindWindow(null, MessageWindowTitle);
            if (target == IntPtr.Zero) { try { fallback(); } catch { } return 0; }
            IntPtr text = Marshal.StringToHGlobalUni(message);
            try { var cds = new COPYDATASTRUCT { dwData = new IntPtr(0xBA4A), cbData = (message.Length + 1) * 2, lpData = text }; SendMessage(target, 0x004A, IntPtr.Zero, ref cds); }
            finally { Marshal.FreeHGlobal(text); }
            return 0;
        }

        static int RunUi(bool preview, bool selfTest, string capture, string iconSheet)
        {
            Paths.Init(preview);
            string sid = System.Security.Principal.WindowsIdentity.GetCurrent().User.Value;
            if (!preview)
            {
                instance = new Mutex(true, @"Local\BAKA.Desktop." + sid.Replace('-', '_'), out bool first);
                if (!first) { Forward("settings|", () => { }); return 3; }
            }
            Log.Write("desktop-start version=" + Version + " preview=" + preview);
            AppDomain.CurrentDomain.UnhandledException += (o, e) => { Log.Write("fatal error=\"" + e.ExceptionObject + "\""); try { Fps.Stop(); } catch { } if (!preview) ExplorerIntegration.RestoreAll(); };
            // An error inside a WinForms window (the BAKA window buttons) or a background task is logged and
            // survived; it must never end the desktop or show the WinForms error dialog.
            System.Windows.Forms.Application.SetUnhandledExceptionMode(System.Windows.Forms.UnhandledExceptionMode.CatchException);
            System.Windows.Forms.Application.ThreadException += (o, e) => Log.Write("forms-exception error=\"" + e.Exception.Message + "\"");
            System.Threading.Tasks.TaskScheduler.UnobservedTaskException += (o, e) => { Log.Write("task-exception error=\"" + e.Exception.GetBaseException().Message + "\""); e.SetObserved(); };

            var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            Ui = app.Dispatcher;
            app.DispatcherUnhandledException += (o, e) => { Log.Write("ui-exception error=\"" + e.Exception + "\""); if (SelfTest.Running) SelfTest.Fail(e.Exception.Message); e.Handled = true; };
            Settings = Settings.Load();
            Profiles.Recover();
            Theme.Load();
            Theme.Apply(Json.Str(Settings.Appearance, "theme"), Json.Str(Settings.Appearance, "accentColor"));
            Styles.Install(app);

            if (iconSheet != null) { app.Dispatcher.BeginInvoke(new Action(() => { try { SelfTest.IconSheet(iconSheet); } finally { app.Shutdown(0); } })); app.Run(); return 0; }

            AppCatalog.Refresh();
            AppCatalog.Watch();
            if (!preview)
            {
                ExplorerIntegration.UndoOldShellOverride();
                Native.EnsureFullWindowDrag();
            }
            app.Startup += (o, e) => { };
            // Sign-out or shutdown: exit at once and leave Windows as it is (taskbar hidden, BAKA settings),
            // so Windows does not wait for BAKA and the next sign-in starts clean.
            app.SessionEnding += (o, e) => { sessionEnding = true; Log.Write("session-ending reason=" + e.ReasonSessionEnding); try { app.Shutdown(0); } catch { } };
            app.Dispatcher.BeginInvoke(new Action(() => Start(preview, selfTest, capture)));
            int exit = 0;
            app.Exit += (o, e) => exit = e.ApplicationExitCode;
            app.Run();
            Cleanup(preview);
            Log.Write("desktop-exit code=" + exit);
            return exit;
        }

        static void Start(bool preview, bool selfTest, string capture)
        {
            CreateMessageWindow();
            // BAKA is the shell: the menu bar and dock keep their edges through the work area (no Explorer)
            AppBars.UseWorkArea = ShellMode.Active;
            FocusMode.Init(); // before the dock is placed: Focus can keep it tucked away
            Bar = new TopBar(); Dock = new Dock();
            if (Json.Bool(Settings.TopBar, "enabled", true)) Bar.Show();
            Dock.Show();
            Wallpaper.Apply(false);
            if (!preview) CaptionButtons.RestoreOrphans(); // a previous BAKA that was killed left apps without buttons
            ApplyIntegration();
            if (!preview)
            {
                if (KeyHook.Enabled && !KeyHook.Install()) Log.Write("key-hook-unavailable");
                KeyHook.Pressed += what => Ui.BeginInvoke(new Action(() =>
                {
                    // Win on its own: held about a second shows the shortcut cheat sheet (released, it goes
                    // away); tapped, it opens the Launchpad as before. The Launchpad only opens when the
                    // "Windows key opens Launchpad" setting is on; the other shortcuts work either way.
                    if (what == "cheat-sheet-hold") CheatSheet.HoldFired();
                    else if (what == "win-up") CheatSheet.WinUp();
                    else if (what == "win-up-lone") { if (!CheatSheet.WinUp() && WinKeyOpensLaunchpad) Launchpad.Toggle(); }
                    else if (what == "cheat-sheet") CheatSheet.Toggle();
                    else if (what == "cheat-escape") CheatSheet.Escape();
                    else if (what == "win-down" || what == "win-used") { }
                    else if (what == "launchpad") Launchpad.Toggle(); else if (what == "files") Files.Open(null); else if (what == "search") Launchpad.Toggle(true);
                    // the Win / Alt shortcuts Windows reserves, handled by BAKA's keyboard hook when Explorer is off
                    else if (what == "switcher") Switcher.Toggle();
                    else if (what == "alt-tab") Switcher.Step(false);
                    else if (what == "alt-tab-back") Switcher.Step(true);
                    else if (what == "alt-commit") Switcher.Commit();
                    else if (what == "control-center") ControlCenter.Toggle(Bar);
                    else if (what == "snip") Snip.Start();
                    else if (what.StartsWith("snap-")) WindowKeys.Snap(what.Substring(5));
                    // volume keys only act when BAKA is the shell (otherwise Windows already handles them)
                    else if ((what == "volup" || what == "voldown" || what == "volmute") && ShellMode.Active) VolumeOsd.Key(what);
                }));
            }
            Widgets.ShowEnabled();
            // what is playing (album art for the media widget and the clock island)
            NowPlaying.Start();
            // notifications: history behind the bell always; pop-ups only in shell mode
            Notifications.Start();
            // BAKA is the shell: start the sign-in apps, hide minimized windows, keep the edges free
            ShellMode.Start();
            // BAKA chosen as the shell but restarted while the helper Explorer runs: host the tray icons again
            if (!preview && ShellMode.Chosen && !ShellMode.Active) BakaTray.Start();
            explorerSeen = ExplorerIntegration.ExplorerRunning(); lastExplorerTray = ExplorerTrayWindow();
            ShellKeys.Apply(messages?.Handle ?? IntPtr.Zero);
            if (!preview) { Fps.StopLeftover(); FeatureKeys(); }
            GameOverlay.Update();
            // BAKA shows the notification pop-ups: Windows' own banners off, so each one comes once
            if (!preview) System.Threading.Tasks.Task.Run(() => WindowsBanners.Update());

            clock = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            clock.Tick += (o, e) => { try { Tick?.Invoke(); } catch (Exception ex) { Log.Write("tick-failed error=\"" + ex.Message + "\""); } };
            clock.Start();
            // The dock and menu bar follow window changes as Windows reports them (a window opens, closes,
            // comes to the front, minimizes), within about 0.1 s. A slow poll stays as a safety net.
            windows = new DispatcherTimer { Interval = TimeSpan.FromSeconds(4) };
            windows.Tick += (o, e) => RefreshWindows();
            windows.Start();
            // 50 ms after Windows reports a change is enough to group bursts (a window opening sends several)
            windowsSoon = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(50) };
            windowsSoon.Tick += (o, e) => { windowsSoon.Stop(); RefreshWindows(); };
            if (!preview) WatchWindows(true);
            profile = new DispatcherTimer { Interval = TimeSpan.FromSeconds(4) };
            profile.Tick += (o, e) => CheckGame();
            profile.Start();
            // Explorer shows its taskbar again after it restarts; hide it again whenever that happens.
            var guard = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3) };
            guard.Tick += (o, e) =>
            {
                if (preview) return;
                if (TaskbarWanted && !peeking && ExplorerIntegration.TaskbarVisible()) ExplorerIntegration.HideTaskbar();
                if (!ShellMode.Chosen || GameRunning) return; // nothing here while a game runs
                bool explorer = ExplorerIntegration.ExplorerRunning();
                if (explorer) { BakaTray.Claim(); AppBars.Verify(); } // tray icons to BAKA; dock + menu bar edges kept free
                if (explorer != explorerSeen)
                {
                    explorerSeen = explorer; ShellMode.ForgetActive();
                    if (explorer)
                    {
                        // Explorer is up: track its new taskbar window so the event hook can hide it the instant
                        // it shows, and hide it on a tight timer for a few seconds so it never flashes into view.
                        lastExplorerTray = ExplorerTrayWindow();
                        if (TaskbarWanted) HideTaskbarBurst(6);
                        // its notification host is now available, so BAKA retries the notification listener it
                        // could not get while Explorer was off.
                        Notifications.Retry();
                    }
                    else
                    {
                        // the helper Explorer ended: BAKA takes the shell jobs back
                        Log.Write("explorer-exited");
                        AppBars.UseWorkArea = ShellMode.Active; AppBars.Forget(); Bar?.Reserve(); Dock?.Reserve();
                        ShellKeys.Apply(messages?.Handle ?? IntPtr.Zero); BakaTray.Start();
                    }
                    // switch the keyboard between the low-level hook (Explorer off: BAKA owns the shortcuts) and
                    // raw-input listening (Explorer on); off the UI thread, since swapping joins a hook thread.
                    if (KeyHook.Enabled) System.Threading.Tasks.Task.Run(() => { try { KeyHook.Install(); } catch { } });
                }
                // Always mode keeps Explorer up; On-demand closes it again once nothing needs it.
                if (!explorer) ShellMode.StartHelper("explorer-exited");
                else ShellMode.MaybeCloseIdleHelper();
            };
            guard.Start();
            // the Launchpad is built while nothing else is happening, so the first Windows key press is instant
            new DispatcherTimer(TimeSpan.FromSeconds(4), DispatcherPriority.ApplicationIdle, (o, e) => { ((DispatcherTimer)o).Stop(); try { if (!GameRunning) Launchpad.Prepare(); } catch (Exception ex) { Log.Write("launchpad-prepare-failed error=\"" + ex.Message + "\""); } }, Ui).Start();
            new DispatcherTimer(TimeSpan.FromSeconds(25), DispatcherPriority.Background, (o, e) => { ((DispatcherTimer)o).Stop(); TrimMemory("startup", false); }, Ui).Start();

            if (selfTest) SelfTest.Start();
            else if (capture != null) SelfTest.Capture(capture);
            Log.Write("desktop-ready");
        }

        static DispatcherTimer windowsSoon;
        static IntPtr windowHook, foregroundHook, minimizeHook;
        static Native.WinEventProc windowProc; // kept alive: Windows calls into it
        static void RefreshWindows()
        {
            if (GameRunning) return;
            try { CheckFullscreen(); WindowsChanged?.Invoke(); } catch (Exception ex) { Log.Write("windows-refresh-failed error=\"" + ex.Message + "\""); }
        }
        // Window shown, hidden or destroyed, foreground change, minimize / restore. Out of context: nothing
        // runs inside other apps and they never wait for BAKA. Removed while a game runs.
        public static void WatchWindows(bool on)
        {
            if (Paths.Preview) return;
            if (on && windowHook == IntPtr.Zero)
            {
                windowProc = (hook, ev, h, idObject, idChild, thread, time) =>
                {
                    try
                    {
                        // The helper Explorer shows its taskbar again on some events (an app opening, the Store
                        // starting): hide it the moment it appears instead of up to 3 s later, which looked
                        // like "Windows Explorer starting".
                        if (ev == 0x8002 /*EVENT_OBJECT_SHOW*/ && idObject == 0 && h != IntPtr.Zero && h == lastExplorerTray && TaskbarWanted && !peeking) { Native.ShowWindow(h, Native.SW_HIDE); return; }
                        // top-level windows only: a control inside an app showing or hiding (menus, tooltips,
                        // list items) changes nothing in the dock and ran a full window refresh each time
                        // A destroyed window can no longer be asked for its parent (events arrive after the fact),
                        // so a destroy always counts: a window closed from the dock menu stayed in the dock until the
                        // 4 s poll otherwise.
                        if (idObject == 0 && idChild == 0 && !GameRunning && windowsSoon != null && !windowsSoon.IsEnabled
                            && (ev < 0x8000 || ev == 0x8001 /*DESTROY*/ || !Native.IsWindow(h) || Native.GetAncestor(h, 2 /*GA_ROOT*/) == h)) windowsSoon.Start();
                    }
                    catch { }
                };
                windowHook = Native.SetWinEventHook(Native.EVENT_OBJECT_DESTROY, Native.EVENT_OBJECT_HIDE, IntPtr.Zero, windowProc, 0, 0, Native.WINEVENT_OUTOFCONTEXT | Native.WINEVENT_SKIPOWNPROCESS);
                // Only the window in front changing, and minimize / restore. The range 3..0x17 used before also
                // carried mouse capture, menus, move/size, drag-and-drop and scrolling, so nearly every click in
                // any app made BAKA re-read every window.
                foregroundHook = Native.SetWinEventHook(3 /*EVENT_SYSTEM_FOREGROUND*/, 3, IntPtr.Zero, windowProc, 0, 0, Native.WINEVENT_OUTOFCONTEXT | Native.WINEVENT_SKIPOWNPROCESS);
                minimizeHook = Native.SetWinEventHook(Native.EVENT_SYSTEM_MINIMIZESTART, Native.EVENT_SYSTEM_MINIMIZEEND, IntPtr.Zero, windowProc, 0, 0, Native.WINEVENT_OUTOFCONTEXT | Native.WINEVENT_SKIPOWNPROCESS);
            }
            else if (!on)
            {
                if (windowHook != IntPtr.Zero) Native.UnhookWinEvent(windowHook);
                if (foregroundHook != IntPtr.Zero) Native.UnhookWinEvent(foregroundHook);
                if (minimizeHook != IntPtr.Zero) Native.UnhookWinEvent(minimizeHook);
                windowHook = foregroundHook = minimizeHook = IntPtr.Zero;
            }
        }

        // A fullscreen window (video, presentation, borderless app) covers the menu bar and dock, like it
        // covers the Windows taskbar; they come back on top when it leaves fullscreen.
        static bool behindFullscreen;
        static void CheckFullscreen()
        {
            IntPtr fg = Native.GetForegroundWindow(); bool full = false;
            if (fg != IntPtr.Zero)
            {
                Native.GetWindowThreadProcessId(fg, out uint pid);
                full = pid != Process.GetCurrentProcess().Id && Profiles.IsFullscreen(fg);
            }
            if (full == behindFullscreen) return;
            behindFullscreen = full;
            foreach (Window w in new Window[] { Bar, Dock }) if (w != null) w.Topmost = !full;
            Log.Write("fullscreen-app=" + full);
        }

        public static bool TaskbarWanted => Json.Bool(Settings.Taskbar, "autoHideWindowsTaskbar", true);
        public static bool WinKeyOpensLaunchpad => Json.Bool(Settings.Integration, "winKeyOpensLaunchpad", true);

        // When the helper Explorer starts it can show its taskbar for a moment before the event hook catches
        // it. Hide it on a tight timer for a few seconds so it never flashes into view during the handover.
        static DispatcherTimer taskbarBurst; static DateTime taskbarBurstUntil;
        static void HideTaskbarBurst(double seconds)
        {
            if (Paths.Preview) return;
            taskbarBurstUntil = DateTime.Now.AddSeconds(seconds);
            if (taskbarBurst == null)
            {
                taskbarBurst = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(120) };
                taskbarBurst.Tick += (o, e) =>
                {
                    if (DateTime.Now >= taskbarBurstUntil) { taskbarBurst.Stop(); return; }
                    if (TaskbarWanted && !peeking && ExplorerIntegration.TaskbarVisible()) ExplorerIntegration.HideTaskbar();
                };
            }
            if (!taskbarBurst.IsEnabled) taskbarBurst.Start();
        }

        public static void ApplyIntegration()
        {
            if (Paths.Preview) return;
            if (TaskbarWanted) ExplorerIntegration.HideTaskbar(); else ExplorerIntegration.ShowTaskbar(true);
            ExplorerIntegration.SetDesktopIcons(!Json.Bool(Settings.Integration, "hideDesktopIcons", true));
            ExplorerIntegration.SetFolderHandler(Json.Bool(Settings.Integration, "filesOpensFolders", true), Exe);
            // The keyboard listener also carries Alt+Tab, Win+Tab, Win+arrows, the snip and the cheat sheet, so
            // it stays on when "Windows key opens Launchpad" is off (it used to be removed, and all of those
            // stopped working); the setting only decides whether a tap of Win opens the Launchpad. Only a game
            // removes it. When BAKA is not the shell, the Launchpad setting off means nothing is needed.
            bool winKey = WinKeyOpensLaunchpad;
            bool cheatHold = Json.Bool(Settings.Integration, "cheatSheetOnHold", true);
            KeyHook.MaskWin = winKey;
            KeyHook.CheatHold = cheatHold;
            KeyHook.MaskHeld = winKey || cheatHold;
            KeyHook.Enabled = !GameRunning && (winKey || ShellMode.Chosen);
            if (!winKey && !ShellMode.Chosen) ShellHotkeys.Release();
            if (!KeyHook.Enabled) KeyHook.Remove(); else if (!KeyHook.Install()) Log.Write("key-hook-unavailable");
            try { CaptionButtons.Apply(!GameRunning && Json.Bool(Settings.Integration, "captionButtons", false)); } catch (Exception e) { Log.Write("caption-buttons-failed error=\"" + e.Message + "\""); }
            DesktopMenu.Apply(); // BAKA's right-click menu on the desktop instead of Windows'
        }

        // Shows the Windows taskbar for a few seconds: its tray holds Discord, Steam and driver icons.
        static bool peeking;
        public static void PeekTray()
        {
            if (Paths.Preview) return;
            peeking = true; ExplorerIntegration.ShowTaskbar(false);
            Native.SendKeys(0x5B, 0x42); // Win+B focuses the tray
            new DispatcherTimer(TimeSpan.FromSeconds(12), DispatcherPriority.Normal, (o, e) => { ((DispatcherTimer)o).Stop(); peeking = false; if (TaskbarWanted) ExplorerIntegration.HideTaskbar(); }, Ui).Start();
        }

        // Ctrl+Alt+G leaves a game mode turned on by hand. Manual game mode hides the menu bar, dock and
        // widgets (the Game mode switch with them) and removes BAKA's keyboard listener, so there was no way
        // back on screen. While it is on, BAKA keeps this one hotkey registered (no hook: Windows only tells
        // BAKA about this single combination, so games are not slowed).
        const int GameExitHotkey = 90;
        [DllImport("wtsapi32.dll")] static extern bool WTSRegisterSessionNotification(IntPtr hwnd, int flags);
        [DllImport("user32.dll", SetLastError = true)] static extern bool RegisterHotKey(IntPtr h, int id, uint mod, uint vk);
        [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr h, int id);
        // Ctrl+Alt+F (game overlay) and Ctrl+Alt+D (Focus) work everywhere, games included, so they are
        // registered hotkeys, not keyboard-hook keys (the hook is removed during games).
        const int OverlayHotkey = 91, FocusHotkey = 92;
        static void FeatureKeys()
        {
            var h = messages?.Handle ?? IntPtr.Zero;
            if (h == IntPtr.Zero) return;
            if (!RegisterHotKey(h, OverlayHotkey, 0x0001 | 0x0002 | 0x4000 /*ALT|CTRL|NOREPEAT*/, 0x46 /*F*/)) Log.Write("overlay-key-failed err=" + Marshal.GetLastWin32Error());
            if (!RegisterHotKey(h, FocusHotkey, 0x0001 | 0x0002 | 0x4000, 0x44 /*D*/)) Log.Write("focus-key-failed err=" + Marshal.GetLastWin32Error());
        }
        static bool gameExitKey;
        static void GameExitKey(bool on)
        {
            var h = messages?.Handle ?? IntPtr.Zero;
            if (h == IntPtr.Zero || on == gameExitKey) return;
            if (on) { gameExitKey = RegisterHotKey(h, GameExitHotkey, 0x0001 | 0x0002 | 0x4000 /*ALT|CTRL|NOREPEAT*/, 0x47 /*G*/); if (!gameExitKey) Log.Write("game-exit-key-failed err=" + Marshal.GetLastWin32Error()); }
            else { UnregisterHotKey(h, GameExitHotkey); gameExitKey = false; }
        }
        static void CheckGame()
        {
            try
            {
                if (Profiles.Manual != null) return;
                string game = Paths.Preview ? null : Profiles.DetectForegroundGame();
                if (game != null && !GameRunning) EnterGame(game);
                else if (game == null && GameRunning) LeaveGame();
            }
            catch (Exception e) { Log.Write("game-check-failed error=\"" + e.Message + "\""); }
        }
        public static void EnterGame(string name)
        {
            // The keyboard hook is removed, not just switched off: while it is installed every key press of the
            // game would make a round trip through BAKA's thread before reaching the game.
            // BAKA's window-event hooks (for the BAKA window buttons) are removed too, so Windows sends BAKA
            // no notifications about the game's window while it runs.
            GameRunning = true; Profiles.DetectedGame = name; KeyHook.Enabled = false;
            // the game is the window in front when it is detected (a game mode started by hand from BAKA has none)
            GameWindow = Native.GetForegroundWindow();
            Native.GetWindowThreadProcessId(GameWindow, out uint gamePid);
            if (gamePid == 0 || gamePid == (uint)Process.GetCurrentProcess().Id) GameWindow = IntPtr.Zero;
            Notifications.Pause(true);
            if (!Paths.Preview) { KeyHook.Remove(); WatchWindows(false); try { CaptionButtons.Apply(false); } catch { } }
            Profiles.Set("CompetitiveGaming", "game " + name);
            Bar?.Hide(); Dock?.Hide(); Widgets.HideAll(); Launchpad.HideIfOpen(); ControlCenter.Current?.Close(); Wallpaper.Pause(true); CaptionButtons.HideAll(true); Surfaces.Pause(true); DesktopMenu.Hide();
            try { CheatSheet.Escape(); } catch { }
            try { FocusMode.GameStarted(); } catch (Exception e) { Log.Write("focus-failed error=\"" + e.Message + "\""); }
            GameOverlay.Update(); // after everything else is hidden: the overlay is the one BAKA window in a game
            if (Profiles.Manual != null && !Paths.Preview) { GameExitKey(true); Osd.Show(0xE7FC, "Game mode on  ·  Ctrl+Alt+G to leave"); }
            // The prepared Launchpad is kept: freeing it and building it again after every game made the
            // desktop slow right after a game. Its memory goes back only when Windows is short of memory.
            Ui.BeginInvoke(new Action(() => TrimMemory("game", true)), DispatcherPriority.ApplicationIdle);
        }
        public static void LeaveGame()
        {
            GameRunning = false; Profiles.DetectedGame = null; GameWindow = IntPtr.Zero;
            GameExitKey(false);
            // Focus that the game turned on goes off first, so the dock and wallpaper below come back as they should
            try { FocusMode.GameEnded(); } catch (Exception e) { Log.Write("focus-failed error=\"" + e.Message + "\""); }
            Notifications.Pause(false);
            Profiles.Set("Desktop", "game closed");
            KeyHook.MaskWin = WinKeyOpensLaunchpad;
            KeyHook.CheatHold = Json.Bool(Settings.Integration, "cheatSheetOnHold", true);
            KeyHook.MaskHeld = WinKeyOpensLaunchpad || KeyHook.CheatHold;
            KeyHook.Enabled = WinKeyOpensLaunchpad || ShellMode.Chosen;
            if (!Paths.Preview && KeyHook.Enabled && !KeyHook.Install()) Log.Write("key-hook-unavailable");
            if (!Paths.Preview) { WatchWindows(true); try { CaptionButtons.Apply(Json.Bool(Settings.Integration, "captionButtons", false)); } catch { } }
            if (Json.Bool(Settings.TopBar, "enabled", true)) Bar?.Show();
            Dock?.Show(); Widgets.ShowEnabled(); Wallpaper.Pause(false); CaptionButtons.HideAll(false); Surfaces.Pause(false); DesktopMenu.Apply();
            GameOverlay.Update(); // "in games" hides it, "always" keeps it
            RefreshWindows();
            Ui.BeginInvoke(new Action(() => { try { if (!GameRunning) Launchpad.Prepare(); } catch { } }), DispatcherPriority.ApplicationIdle);
        }

        // Frees memory BAKA no longer uses. Paging BAKA's memory out entirely (EmptyWorkingSet) only happens
        // when Windows is short of memory: on a PC with plenty of RAM it gains the game nothing and makes the
        // dock, Launchpad and menus stutter afterwards while Windows reads the pages back in.
        public static void TrimMemory(string reason, bool pageOutWhenLow = true)
        {
            try
            {
                GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect();
                var m = new Native.MEMORYSTATUSEX { dwLength = (uint)Marshal.SizeOf(typeof(Native.MEMORYSTATUSEX)) };
                bool low = Native.GlobalMemoryStatusEx(ref m) && m.dwMemoryLoad >= 80;
                if (pageOutWhenLow && low) Native.EmptyWorkingSet(Process.GetCurrentProcess().Handle);
                Log.Write("memory-trimmed reason=" + reason + " pagedOut=" + (pageOutWhenLow && low) + " workingSetMB=" + (Process.GetCurrentProcess().WorkingSet64 / 1048576));
            }
            catch { }
        }

        static void CreateMessageWindow()
        {
            var p = new HwndSourceParameters(MessageWindowTitle) { Width = 0, Height = 0, WindowStyle = 0 };
            messages = new HwndSource(p);
            // lock / unlock notifications, so keys held before a lock are forgotten (see KeyHook.ForgetKeys)
            try { WTSRegisterSessionNotification(messages.Handle, 0 /*NOTIFY_FOR_THIS_SESSION*/); } catch { }
            uint taskbarCreated = Native.RegisterWindowMessage("TaskbarCreated");
            messages.AddHook((IntPtr h, int msg, IntPtr w, IntPtr l, ref bool handled) =>
            {
                if (msg == ShellKeys.WM_HOTKEY && w.ToInt32() == GameExitHotkey) { Log.Write("game-exit-key"); Ui.BeginInvoke(new Action(() => { Profiles.Manual = null; LeaveGame(); Osd.Show(0xE7FC, "Game mode off"); })); handled = true; return IntPtr.Zero; }
                if (msg == ShellKeys.WM_HOTKEY && w.ToInt32() == OverlayHotkey) { Ui.BeginInvoke(new Action(GameOverlay.ToggleFromKey)); handled = true; return IntPtr.Zero; }
                if (msg == ShellKeys.WM_HOTKEY && w.ToInt32() == FocusHotkey) { Ui.BeginInvoke(new Action(() => FocusMode.Toggle("key"))); handled = true; return IntPtr.Zero; }
                if (msg == ShellKeys.WM_HOTKEY) { ShellKeys.Handle(w); handled = true; return IntPtr.Zero; }
                // locked / unlocked or user switched (WM_WTSSESSION_CHANGE): keys held before are not held now
                if (msg == 0x02B1) { KeyHook.ForgetKeys(); Ui.BeginInvoke(new Action(() => { try { CheatSheet.Escape(); } catch { } })); if (w.ToInt32() == 8 /*WTS_SESSION_UNLOCK*/) Log.Write("session-unlocked keys-reset"); }
                if (MinimizeTarget.Message != 0 && msg == (int)MinimizeTarget.Message) { var r = MinimizeTarget.Handle(w, l); if (r != IntPtr.Zero) { handled = true; return r; } return IntPtr.Zero; }
                if (msg == 0x0219 && ShellMode.Active) ShellExtras.OnDeviceChange(w, l); // WM_DEVICECHANGE: USB drive
                if (msg == 0x004A)
                {
                    var cds = (COPYDATASTRUCT)Marshal.PtrToStructure(l, typeof(COPYDATASTRUCT));
                    if (cds.dwData == new IntPtr(0xBA4A) && cds.lpData != IntPtr.Zero && cds.cbData >= 2 && cds.cbData <= 64 * 1024)
                    {
                        // read exactly what was sent: a string without its terminating zero made BAKA read past the
                        // sender's buffer (any app in the session can send this message)
                        string text = Marshal.PtrToStringUni(cds.lpData, cds.cbData / 2).TrimEnd('\0');
                        Ui.BeginInvoke(new Action(() => HandleRequest(text)));
                        handled = true; return new IntPtr(1);
                    }
                }
                // A restarted Explorer has forgotten every reserved screen edge: register them again.
                else if (msg == (int)taskbarCreated) Ui.BeginInvoke(new Action(() =>
                {
                    // BAKA's own tray broadcasts TaskbarCreated too (so apps re-add their icons to it); that one
                    // is not an Explorer restart and must not start another claim + broadcast round.
                    var explorerTray = ExplorerTrayWindow();
                    if (BakaTray.JustBroadcast && explorerTray == lastExplorerTray) return;
                    lastExplorerTray = explorerTray;
                    ShellMode.ForgetActive(); // Explorer is up now: the cached "BAKA does the shell's jobs" is stale
                    Log.Write("explorer-restarted");
                    AppBars.UseWorkArea = ShellMode.Active; AppBars.Forget(); ApplyIntegration(); Bar?.Reserve(); Dock?.Reserve(); ShellKeys.Apply(messages?.Handle ?? IntPtr.Zero);
                    if (TaskbarWanted) HideTaskbarBurst(6); // Explorer re-shows its taskbar as it restarts; keep it hidden
                    // BAKA chosen as the shell: BAKA keeps hosting the tray icons, also next to the helper Explorer
                    if (ShellMode.Active || ShellMode.Chosen) { BakaTray.Start(); BakaTray.Claim(true); } else BakaTray.Stop();
                    MinimizeTarget.Register(messages?.Handle ?? IntPtr.Zero, true);
                }));
                return IntPtr.Zero;
            });
            if (!Paths.Preview) MinimizeTarget.Register(messages.Handle, false);
        }
        static bool explorerSeen;
        static IntPtr lastExplorerTray;
        // Explorer's own taskbar window (not BAKA's tray host, which has the same class name).
        static IntPtr ExplorerTrayWindow()
        {
            uint me = (uint)Process.GetCurrentProcess().Id;
            for (IntPtr h = Native.FindWindowEx(IntPtr.Zero, IntPtr.Zero, "Shell_TrayWnd", null); h != IntPtr.Zero; h = Native.FindWindowEx(IntPtr.Zero, h, "Shell_TrayWnd", null))
            { Native.GetWindowThreadProcessId(h, out uint pid); if (pid != me) return h; }
            return IntPtr.Zero;
        }
        static void HandleRequest(string text)
        {
            int bar = text.IndexOf('|'); string kind = bar < 0 ? text : text.Substring(0, bar), value = bar < 0 ? "" : text.Substring(bar + 1);
            Log.Write("request kind=" + kind);
            if (kind == "open") Files.Open(value); else if (kind == "settings") SettingsWindow.Open();
            else if (kind == "profile" && value.Equals("gaming", StringComparison.OrdinalIgnoreCase)) { Profiles.Manual = "CompetitiveGaming"; EnterGame("manual"); }
            else if (kind == "profile" && value.Equals("desktop", StringComparison.OrdinalIgnoreCase)) { Profiles.Manual = null; LeaveGame(); }
            else if (kind == "tray") PeekTray();
            else if (kind == "focus") FocusMode.Set(value == "toggle" ? !FocusMode.On : value.Equals("on", StringComparison.OrdinalIgnoreCase), "command");
            else if (kind == "overlay") GameOverlay.SetEnabled(value == "toggle" ? !GameOverlay.Enabled : value.Equals("on", StringComparison.OrdinalIgnoreCase), "command");
            else if (kind == "wallpaper" && File.Exists(value))
            {
                bool vid = new[] { ".mp4", ".m4v", ".mov", ".wmv", ".mkv", ".webm", ".avi" }.Contains(Path.GetExtension(value).ToLowerInvariant());
                Settings.Wallpaper["mode"] = vid ? "Video" : "Image"; Settings.Wallpaper["path"] = value; Settings.Wallpaper.Remove("lastVideoError"); Settings.Save();
                Wallpaper.Apply(true);
            }
        }

        public static void Quit(bool restoreWindows)
        {
            Log.Write("desktop-quit restoreWindows=" + restoreWindows);
            if (restoreWindows && !Paths.Preview) { Settings.Taskbar["autoHideWindowsTaskbar"] = false; Settings.Save(); ShellHotkeys.Release(); try { WindowsBanners.Restore(); } catch { } }
            Application.Current.Shutdown(0);
        }
        static void Cleanup(bool preview)
        {
            try { Profiles.Set("Desktop", "exit"); } catch { }
            try { GameOverlay.Close(); } catch { }
            try { Fps.Stop(); } catch { }
            try { TrayFlyout.Restore(); } catch { }
            try { Wallpaper.Stop(); } catch { }
            try { WatchWindows(false); } catch { }
            try { CaptionButtons.Apply(false); } catch { }
            if (!preview && !SessionEnding()) ExplorerIntegration.RestoreAll();
            else if (!preview) { try { KeyHook.Remove(); } catch { } }
            try { messages?.Dispose(); } catch { }
            try { instance?.ReleaseMutex(); } catch { }
        }
    }
}
