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
                bool ok = mode == "ui" ? KeyHook.InstallOnCurrentThread() : KeyHook.Install();
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
            if (a.Contains("--restore-windows")) { Paths.Init(false); ExplorerIntegration.RestoreAll(); ExplorerIntegration.SetFolderHandler(false, ""); return 0; }
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
            while (true)
            {
                int code;
                try { using (var p = Process.Start(new ProcessStartInfo(Exe, "--ui") { UseShellExecute = false })) { p.WaitForExit(); code = p.ExitCode; } }
                catch (Exception e) { Log.Write("supervisor-start-failed error=\"" + e.Message + "\""); code = -1; }
                if (code == 0 || code == 3) return 0; // closed on purpose, or already running
                Log.Write("desktop-crashed code=" + code);
                ExplorerIntegration.RestoreAll();
                crashes.Add(DateTime.Now); crashes.RemoveAll(t => t < DateTime.Now.AddMinutes(-2));
                if (crashes.Count >= 3)
                {
                    Log.Write("desktop-gave-up; Windows taskbar restored");
                    System.Windows.Forms.MessageBox.Show("BAKA Desktop stopped three times, so the normal Windows taskbar and desktop are back.\n\nStart BAKA Desktop again from the Start menu. The log is in %LOCALAPPDATA%\\BAKA\\Logs.", "BAKA Desktop", System.Windows.Forms.MessageBoxButtons.OK, System.Windows.Forms.MessageBoxIcon.Warning);
                    return 1;
                }
                Thread.Sleep(1500);
            }
        }

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
            var tray = Native.FindWindow("Shell_TrayWnd", null);
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
            AppDomain.CurrentDomain.UnhandledException += (o, e) => { Log.Write("fatal error=\"" + e.ExceptionObject + "\""); if (!preview) ExplorerIntegration.RestoreAll(); };

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
            if (!preview)
            {
                ExplorerIntegration.UndoOldShellOverride();
                Native.EnsureFullWindowDrag();
            }
            app.Startup += (o, e) => { };
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
            Bar = new TopBar(); Dock = new Dock();
            if (Json.Bool(Settings.TopBar, "enabled", true)) Bar.Show();
            Dock.Show();
            Wallpaper.Apply(false);
            ApplyIntegration();
            if (!preview)
            {
                if (KeyHook.Enabled && !KeyHook.Install()) Log.Write("key-hook-unavailable");
                KeyHook.Pressed += what => Ui.BeginInvoke(new Action(() =>
                {
                    if (what == "launchpad") Launchpad.Toggle(); else if (what == "files") Files.Open(null); else if (what == "search") Launchpad.Toggle(true);
                }));
            }
            Widgets.ShowEnabled();

            clock = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            clock.Tick += (o, e) => { try { Tick?.Invoke(); } catch (Exception ex) { Log.Write("tick-failed error=\"" + ex.Message + "\""); } };
            clock.Start();
            windows = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1500) };
            windows.Tick += (o, e) => { if (!GameRunning) try { CheckFullscreen(); WindowsChanged?.Invoke(); } catch (Exception ex) { Log.Write("windows-refresh-failed error=\"" + ex.Message + "\""); } };
            windows.Start();
            profile = new DispatcherTimer { Interval = TimeSpan.FromSeconds(4) };
            profile.Tick += (o, e) => CheckGame();
            profile.Start();
            // Explorer shows its taskbar again after it restarts; hide it again whenever that happens.
            var guard = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3) };
            guard.Tick += (o, e) => { if (!preview && TaskbarWanted && !peeking && ExplorerIntegration.TaskbarVisible()) ExplorerIntegration.HideTaskbar(); };
            guard.Start();
            new DispatcherTimer(TimeSpan.FromSeconds(25), DispatcherPriority.Background, (o, e) => { ((DispatcherTimer)o).Stop(); TrimMemory("startup"); }, Ui).Start();

            if (selfTest) SelfTest.Start();
            else if (capture != null) SelfTest.Capture(capture);
            Log.Write("desktop-ready");
        }

        // A fullscreen window (video, presentation, borderless app) covers the menu bar and dock, like it
        // covers the Windows taskbar; they come back on top when it leaves fullscreen.
        static bool behindFullscreen;
        static void CheckFullscreen()
        {
            IntPtr fg = Native.GetForegroundWindow(); bool full = false;
            if (fg != IntPtr.Zero && Native.GetWindowRect(fg, out var r))
            {
                Native.GetWindowThreadProcessId(fg, out uint pid);
                string cls = Native.ClassName(fg);
                var m = Native.MonitorRect(fg, false);
                full = pid != Process.GetCurrentProcess().Id && cls != "Progman" && cls != "WorkerW" && fg != Native.GetShellWindow()
                    && r.Left <= m.Left && r.Top <= m.Top && r.Right >= m.Right && r.Bottom >= m.Bottom;
            }
            if (full == behindFullscreen) return;
            behindFullscreen = full;
            foreach (Window w in new Window[] { Bar, Dock }) if (w != null) w.Topmost = !full;
            Log.Write("fullscreen-app=" + full);
        }

        public static bool TaskbarWanted => Json.Bool(Settings.Taskbar, "autoHideWindowsTaskbar", true);
        public static void ApplyIntegration()
        {
            if (Paths.Preview) return;
            if (TaskbarWanted) ExplorerIntegration.HideTaskbar(); else ExplorerIntegration.ShowTaskbar(true);
            ExplorerIntegration.SetDesktopIcons(!Json.Bool(Settings.Integration, "hideDesktopIcons", true));
            ExplorerIntegration.SetFolderHandler(Json.Bool(Settings.Integration, "filesOpensFolders", true), Exe);
            KeyHook.Enabled = Json.Bool(Settings.Integration, "winKeyOpensLaunchpad", true) && !GameRunning;
            // no hook at all when it has nothing to do (feature off or a game running)
            if (!KeyHook.Enabled) KeyHook.Remove(); else if (!KeyHook.Install()) Log.Write("key-hook-unavailable");
            try { CaptionButtons.Apply(Json.Bool(Settings.Integration, "captionButtons", true)); } catch (Exception e) { Log.Write("caption-buttons-failed error=\""+e.Message+"\""); }
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
            if (!Paths.Preview) { KeyHook.Remove(); try { CaptionButtons.Apply(false); } catch { } }
            Profiles.Set("CompetitiveGaming", "game " + name);
            Bar?.Hide(); Dock?.Hide(); Widgets.HideAll(); Launchpad.HideIfOpen(); Wallpaper.Pause(true); CaptionButtons.HideAll(true);
            // give the game the memory BAKA's hidden surfaces were holding
            Ui.BeginInvoke(new Action(() => TrimMemory("game")), DispatcherPriority.ApplicationIdle);
        }
        public static void LeaveGame()
        {
            GameRunning = false; Profiles.DetectedGame = null;
            Profiles.Set("Desktop", "game closed");
            KeyHook.Enabled = Json.Bool(Settings.Integration, "winKeyOpensLaunchpad", true);
            if (!Paths.Preview && KeyHook.Enabled && !KeyHook.Install()) Log.Write("key-hook-unavailable");
            if (!Paths.Preview) try { CaptionButtons.Apply(Json.Bool(Settings.Integration, "captionButtons", true)); } catch { }
            if (Json.Bool(Settings.TopBar, "enabled", true)) Bar?.Show();
            Dock?.Show(); Widgets.ShowEnabled(); Wallpaper.Pause(false); CaptionButtons.HideAll(false);
        }

        public static void TrimMemory(string reason)
        {
            try { GC.Collect(); GC.WaitForPendingFinalizers(); Native.EmptyWorkingSet(Process.GetCurrentProcess().Handle); Log.Write("memory-trimmed reason=" + reason + " workingSetMB=" + (Process.GetCurrentProcess().WorkingSet64 / 1048576)); } catch { }
        }

        static void CreateMessageWindow()
        {
            var p = new HwndSourceParameters(MessageWindowTitle) { Width = 0, Height = 0, WindowStyle = 0 };
            messages = new HwndSource(p);
            uint taskbarCreated = Native.RegisterWindowMessage("TaskbarCreated");
            messages.AddHook((IntPtr h, int msg, IntPtr w, IntPtr l, ref bool handled) =>
            {
                if (msg == 0x004A)
                {
                    var cds = (COPYDATASTRUCT)Marshal.PtrToStructure(l, typeof(COPYDATASTRUCT));
                    if (cds.dwData == new IntPtr(0xBA4A))
                    {
                        string text = Marshal.PtrToStringUni(cds.lpData);
                        Ui.BeginInvoke(new Action(() => HandleRequest(text)));
                        handled = true; return new IntPtr(1);
                    }
                }
                else if (msg == (int)taskbarCreated) Ui.BeginInvoke(new Action(() => { Log.Write("explorer-restarted"); ApplyIntegration(); Bar?.Reserve(); Dock?.Reserve(); }));
                return IntPtr.Zero;
            });
        }
        static void HandleRequest(string text)
        {
            int bar = text.IndexOf('|'); string kind = bar < 0 ? text : text.Substring(0, bar), value = bar < 0 ? "" : text.Substring(bar + 1);
            Log.Write("request kind=" + kind);
            if (kind == "open") Files.Open(value); else if (kind == "settings") SettingsWindow.Open();
            else if (kind == "profile" && value.Equals("gaming", StringComparison.OrdinalIgnoreCase)) { Profiles.Manual = "CompetitiveGaming"; EnterGame("manual"); }
            else if (kind == "profile" && value.Equals("desktop", StringComparison.OrdinalIgnoreCase)) { Profiles.Manual = null; LeaveGame(); }
            else if (kind == "tray") PeekTray();
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
            if (restoreWindows && !Paths.Preview) { Settings.Taskbar["autoHideWindowsTaskbar"] = false; Settings.Save(); }
            Application.Current.Shutdown(0);
        }
        static void Cleanup(bool preview)
        {
            try { Profiles.Set("Desktop", "exit"); } catch { }
            try { Wallpaper.Stop(); } catch { }
            try { CaptionButtons.Apply(false); } catch { }
            if (!preview) ExplorerIntegration.RestoreAll();
            try { messages?.Dispose(); } catch { }
            try { instance?.ReleaseMutex(); } catch { }
        }
    }
}
