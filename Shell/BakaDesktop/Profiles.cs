using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace Baka.Desktop
{
    // Desktop / Competitive Gaming / Benchmark. A game in the foreground switches to Competitive Gaming:
    // the BAKA surfaces hide, transparency and minimize animations go off, Game Mode goes on, background apps
    // pause and Game DVR stops recording. The previous values are saved first and put back on Desktop.
    static class Profiles
    {
        public static string Active = "Desktop";
        public static string Manual;           // set when the user picked a profile by hand
        public static string DetectedGame;
        public static event Action Changed;

        static readonly (string path, string name, object value)[] Values =
        {
            (@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "EnableTransparency", 0),
            (@"Control Panel\Desktop", "MinAnimate", "0"),
            (@"Software\Microsoft\GameBar", "AutoGameModeEnabled", 1),
            (@"Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications", "GlobalUserDisabled", 1),
            (@"System\GameConfigStore", "GameDVR_Enabled", 0),
        };
        static string StatePath => Path.Combine(Paths.State, "profile-baseline.json");
        static Dictionary<string, object> preview = new Dictionary<string, object>();

        // An interrupted Gaming profile (crash, power loss) is undone before anything is shown.
        public static void Recover() { if (File.Exists(StatePath)) { Restore(); Log.Write("profile-recovered"); } }

        public static void Set(string profile, string reason)
        {
            if (profile == Active) return;
            try
            {
                if (profile == "Desktop") Restore();
                else if (profile == "CompetitiveGaming") Apply();
                else if (Active == "CompetitiveGaming") Restore(); // Benchmark records conditions and leaves Windows as it is
                Active = profile;
                TellWindows();
                Log.Write("profile=" + profile + " reason=" + reason);
                try { Process.GetCurrentProcess().PriorityClass = profile == "Desktop" ? ProcessPriorityClass.Normal : ProcessPriorityClass.BelowNormal; } catch { }
            }
            catch (Exception e) { Log.Write("profile-change-failed profile=" + profile + " error=\"" + e.Message + "\""); }
            Changed?.Invoke();
        }

        static void Apply()
        {
            if (!File.Exists(StatePath))
            {
                var snap = Values.Select(v => (object)new Dictionary<string, object> { ["path"] = v.path, ["name"] = v.name, ["existed"] = Read(v.path, v.name) != null, ["value"] = Read(v.path, v.name) }).ToList();
                File.WriteAllText(StatePath, Json.Write(new Dictionary<string, object> { ["schemaVersion"] = 1, ["values"] = snap, ["savedAt"] = DateTime.Now.ToString("o") }));
            }
            foreach (var v in Values) Write(v.path, v.name, v.value);
        }
        static void Restore()
        {
            if (!File.Exists(StatePath)) return;
            var doc = Json.Obj(Json.Parse(File.ReadAllText(StatePath)));
            foreach (var item in Json.Arr(Json.Get(doc, "values")).Select(Json.Obj))
            {
                string p = Json.Str(item, "path"), n = Json.Str(item, "name");
                if (Json.Bool(item, "existed")) Write(p, n, Json.Get(item, "value")); else Delete(p, n);
            }
            File.Delete(StatePath);
        }
        // The values above were only written to the registry, which Windows reads at sign-in: switching to
        // Gaming left transparency and the minimize animation on until the next sign-in, so the profile looked
        // like it did nothing. Windows is told about both now, the way the Settings app does it.
        static void TellWindows()
        {
            if (Paths.Preview) return;
            // off the UI thread: the broadcast waits up to 200 ms for each slow window
            System.Threading.Tasks.Task.Run(() => TellWindowsNow());
        }
        static void TellWindowsNow()
        {
            try
            {
                // minimize / restore animation (SPI_SETANIMATION with ANIMATIONINFO { cbSize, iMinAnimate })
                bool animate = !string.Equals(Read(@"Control Panel\Desktop", "MinAnimate")?.ToString(), "0", StringComparison.Ordinal);
                IntPtr info = System.Runtime.InteropServices.Marshal.AllocHGlobal(8);
                try
                {
                    System.Runtime.InteropServices.Marshal.WriteInt32(info, 0, 8);
                    System.Runtime.InteropServices.Marshal.WriteInt32(info, 4, animate ? 1 : 0);
                    Native.SystemParametersInfoPtr(0x0049 /*SPI_SETANIMATION*/, 8, info, 0x0002 /*SPIF_SENDCHANGE*/);
                }
                finally { System.Runtime.InteropServices.Marshal.FreeHGlobal(info); }
                // transparency: apps and the shell re-read it on this broadcast. SendMessageTimeout with
                // ABORTIFHUNG, so a hung app cannot stall the switch.
                IntPtr area = System.Runtime.InteropServices.Marshal.StringToHGlobalUni("ImmersiveColorSet");
                try { Native.SendMessageTimeout(new IntPtr(0xFFFF) /*HWND_BROADCAST*/, 0x001A /*WM_SETTINGCHANGE*/, IntPtr.Zero, area, 0x0002 /*SMTO_ABORTIFHUNG*/, 200, out _); }
                finally { System.Runtime.InteropServices.Marshal.FreeHGlobal(area); }
            }
            catch (Exception e) { Log.Write("profile-notify-failed error=\"" + e.Message + "\""); }
        }
        static object Read(string path, string name)
        {
            if (Paths.Preview) return preview.TryGetValue(path + "|" + name, out var v) ? v : null;
            using (var k = Registry.CurrentUser.OpenSubKey(path)) return k?.GetValue(name);
        }
        static void Write(string path, string name, object value)
        {
            if (Paths.Preview) { preview[path + "|" + name] = value; return; }
            using (var k = Registry.CurrentUser.CreateSubKey(path))
            {
                if (value is int || value is long) k.SetValue(name, Convert.ToInt32(value), RegistryValueKind.DWord);
                else k.SetValue(name, value?.ToString() ?? "", RegistryValueKind.String);
            }
        }
        static void Delete(string path, string name)
        {
            if (Paths.Preview) { preview.Remove(path + "|" + name); return; }
            using (var k = Registry.CurrentUser.OpenSubKey(path, true)) k?.DeleteValue(name, false);
        }

        // ---- game detection ----
        static Regex helper; static HashSet<string> nonGames, excluded; static List<string> library; static Dictionary<string, string> named;
        static void LoadRules()
        {
            if (helper != null) return;
            named = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase); nonGames = new HashSet<string>(StringComparer.OrdinalIgnoreCase); excluded = new HashSet<string>(StringComparer.OrdinalIgnoreCase); library = new List<string>();
            helper = new Regex("(?i)(crash|redist|setup|install|uninst|launcher|helper|updater|bootstrap|anticheat|webview|overlay)");
            try
            {
                var g = Json.Obj(Json.Get(Json.Obj(Json.Parse(File.ReadAllText(Paths.Shipped("PerformanceProfiles.json")))), "gameDetection"));
                foreach (var p in Json.Arr(Json.Get(g, "processes")).Select(Json.Obj)) named[Json.Str(p, "processName")] = Json.Str(p, "displayName");
                foreach (var s in Json.Arr(Json.Get(g, "nonGameProcesses"))) nonGames.Add(s.ToString());
                foreach (var s in Json.Arr(Json.Get(g, "excludedProcesses"))) excluded.Add(s.ToString());
                foreach (var s in Json.Arr(Json.Get(g, "libraryPathPatterns"))) library.Add(s.ToString().ToLowerInvariant());
                helper = new Regex(Json.Str(g, "helperPattern", helper.ToString()));
            }
            catch (Exception e) { Log.Write("game-rules-unreadable error=\"" + e.Message + "\""); }
            // Launchers and stores live inside the game folders too. R15 took the Riot Client window for a game
            // (it is in "\Riot Games\"), so opening it hid the dock and menu bar and switched profiles.
            foreach (var p in BuiltInNonGames) nonGames.Add(p);
            // VALORANT was excluded only for the VMware tests (Vanguard does not run in a VM). On a real PC it
            // gets Gaming mode like every game, which also removes BAKA's input listener while it runs.
            excluded.RemoveWhere(p => p.StartsWith("VALORANT", StringComparison.OrdinalIgnoreCase));
            named["VALORANT-Win64-Shipping"] = "VALORANT";
            nonGames.Add("VALORANT"); // the small start-up program, not the game
        }
        static readonly string[] BuiltInNonGames =
        {
            "Riot Client", "RiotClientServices", "RiotClientUx", "RiotClientUxRender", "RiotClientCrashHandler", "vgtray",
            "steam", "steamwebhelper", "steamservice", "EpicGamesLauncher", "EpicWebHelper", "GalaxyClient", "GalaxyClient Helper",
            "EADesktop", "EABackgroundService", "Origin", "upc", "UplayWebCore", "UbisoftConnect", "Battle.net", "Agent",
            "XboxPcApp", "XboxApp", "GameBar", "GamingServices", "Playnite.DesktopApp", "Playnite.FullscreenApp", "itch", "Amazon Games UI",
            "HoYoPlay", "launcher", "WhatsApp", "WhatsApp.Root", "Spotify", "Telegram", "Slack", "Zoom", "Notepad", "Photos", "Video.UI",
            "Microsoft.Photos", "SnippingTool", "ScreenClippingHost", "mspaint", "CalculatorApp", "BakaDesktop", "msedgewebview2"
        };

        // The last game was found only because its window was fullscreen (not a named title or in a library):
        // such an app (a video player, a slideshow) leaves Gaming as soon as it leaves fullscreen.
        public static bool DetectedByFullscreen;
        // A game is the foreground app when it is a named title, an executable inside a game library, or a
        // fullscreen / borderless window that is not a browser, player or tool.
        public static string DetectForegroundGame()
        {
            LoadRules();
            IntPtr fg = Native.GetForegroundWindow();
            if (fg == IntPtr.Zero) return null;
            Native.GetWindowThreadProcessId(fg, out uint pid);
            if (pid == Process.GetCurrentProcess().Id) return null;
            string exe = Native.ProcessPath(pid); if (exe == null) return null;
            string proc = Path.GetFileNameWithoutExtension(exe);
            DetectedByFullscreen = false;
            if (excluded.Contains(proc)) return null;
            if (named.TryGetValue(proc, out string display)) return display;
            if (nonGames.Contains(proc) || helper.IsMatch(proc)) return null;
            string lower = exe.ToLowerInvariant();
            if (library.Any(p => lower.Contains(p))) return Native.WindowText(fg) is string t && t.Length > 0 ? t : proc;
            // fullscreen: the window covers its whole monitor and is not the desktop
            if (IsFullscreen(fg)) { DetectedByFullscreen = true; return Native.WindowText(fg) is string t2 && t2.Length > 0 ? t2 : proc; }
            return null;
        }
        // A window that covers its whole monitor. A maximized window with a title bar is a normal app, not a
        // fullscreen game, even though its frame reaches past the screen edge.
        public static bool IsFullscreen(IntPtr h)
        {
            if (h == IntPtr.Zero || !Native.GetWindowRect(h, out Native.RECT r)) return false;
            if (IsDesktop(h)) return false;
            long style = Native.GetWindowLongPtr(h, Native.GWL_STYLE).ToInt64();
            bool caption = (style & 0x00C00000) == 0x00C00000;
            if (Native.IsZoomed(h) && caption) return false;
            var m = Native.MonitorRect(h, false);
            if (r.Left <= m.Left && r.Top <= m.Top && r.Right >= m.Right && r.Bottom >= m.Bottom) return true;
            // Borderless ("windowed fullscreen") games often size themselves to the work area, which is the
            // screen minus BAKA's menu bar and dock strips, so they never covered the whole monitor and were not
            // seen as fullscreen: the bars stayed on top of the game. A window with no title bar and no sizing
            // border that covers the whole work area counts as fullscreen too. Normal apps with their own
            // title bar (browsers, Discord, Spotify) keep a sizing border, so they are not caught by this.
            if (caption || (style & 0x00040000 /*WS_THICKFRAME*/) != 0 || (Native.ExStyle(h) & Native.WS_EX_TOOLWINDOW) != 0) return false;
            var w = Native.MonitorRect(h, true);
            if (w.Right - w.Left >= m.Right - m.Left && w.Bottom - w.Top >= m.Bottom - m.Top) return false; // no strips reserved: the check above decided
            return r.Left <= w.Left && r.Top <= w.Top && r.Right >= w.Right && r.Bottom >= w.Bottom;
        }
        public static bool IsDesktop(IntPtr h)
        {
            string cls = Native.ClassName(h);
            return cls == "Progman" || cls == "WorkerW" || h == Native.GetShellWindow();
        }
    }

    // Windows power plans through powercfg (no PowerShell).
    static class PowerPlans
    {
        public const string BakaGuid = "baca5e00-1d5c-4a6e-9b1f-6a6d6b616b61", Balanced = "381b4222-f694-41f0-9685-ff5bb260df2e";
        public static List<(string guid, string name, bool active)> List()
        {
            var r = new List<(string, string, bool)>();
            foreach (Match m in Regex.Matches(Run("/list"), @"([0-9a-fA-F-]{36})\s+\((.+?)\)(\s*\*)?"))
                r.Add((m.Groups[1].Value.ToLowerInvariant(), m.Groups[2].Value, m.Groups[3].Success));
            return r;
        }
        // powercfg takes 50-100 ms; Control Center and Settings read the list from a short cache instead of
        // running it on every open.
        static List<(string guid, string name, bool active)> cached; static DateTime cachedAt;
        public static List<(string guid, string name, bool active)> ListCached()
        {
            if (cached == null || (DateTime.Now - cachedAt).TotalSeconds > 20) { cached = List(); cachedAt = DateTime.Now; }
            return cached;
        }
        public static void Activate(string guid) { if (!Paths.Preview) Run("/setactive " + guid); cached = null; Log.Write("power-plan-active guid=" + guid + (Paths.Preview ? " (preview)" : "")); }
        static string Run(string args)
        {
            try
            {
                var p = Process.Start(new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "powercfg.exe"), args) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true });
                string o = p.StandardOutput.ReadToEnd(); p.WaitForExit(5000); return o;
            }
            catch { return ""; }
        }
    }
}
