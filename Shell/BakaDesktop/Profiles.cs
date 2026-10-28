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
                Log.Write("profile=" + profile + " reason=" + reason);
                try { Process.GetCurrentProcess().PriorityClass = profile == "Desktop" ? ProcessPriorityClass.Normal : ProcessPriorityClass.BelowNormal; } catch { }
                if (profile != "Desktop") App.TrimMemory("game-start");
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
        }

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
            if (excluded.Contains(proc)) return null;
            if (named.TryGetValue(proc, out string display)) return display;
            if (nonGames.Contains(proc) || helper.IsMatch(proc)) return null;
            string lower = exe.ToLowerInvariant();
            if (library.Any(p => lower.Contains(p))) return Native.WindowText(fg) is string t && t.Length > 0 ? t : proc;
            // fullscreen: the window covers its whole monitor and is not the desktop
            if (Native.GetWindowRect(fg, out Native.RECT r))
            {
                var m = Native.MonitorRect(fg, false);
                string cls = Native.ClassName(fg);
                if (r.Left <= m.Left && r.Top <= m.Top && r.Right >= m.Right && r.Bottom >= m.Bottom && cls != "Progman" && cls != "WorkerW" && fg != Native.GetShellWindow())
                    return Native.WindowText(fg) is string t2 && t2.Length > 0 ? t2 : proc;
            }
            return null;
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
        public static void Activate(string guid) { if (!Paths.Preview) Run("/setactive " + guid); Log.Write("power-plan-active guid=" + guid + (Paths.Preview ? " (preview)" : "")); }
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
