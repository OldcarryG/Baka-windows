using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Web.Script.Serialization;

namespace Baka.Desktop
{
    // Where BAKA keeps its files. -preview (tests, design captures) uses a throw-away folder so a test
    // never touches the real settings, registry profile or wallpaper.
    static class Paths
    {
        public static bool Preview;
        public static string Data;      // %ProgramData%\BAKA (shipped config, assets)
        public static string Local;     // %LOCALAPPDATA%\BAKA (settings, logs, state)
        public static string Settings => Path.Combine(Local, "Settings", "desktop-settings.json");
        public static string Notes => Path.Combine(Local, "Settings", "notes.txt");
        public static string Logs => Path.Combine(Local, "Logs");
        public static string State => Path.Combine(Local, "State");

        public static void Init(bool preview)
        {
            Preview = preview;
            string exeDir = AppDomain.CurrentDomain.BaseDirectory;
            // Installed: ProgramData\BAKA\Desktop\BakaDesktop.exe. Development: <repo>\Shell\BakaDesktop\bin\out.
            Data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "BAKA");
            string repo = FindRepo(exeDir);
            if (!File.Exists(Path.Combine(Data, "DesktopThemes.json")) && repo != null) Data = repo;
            Local = preview ? Path.Combine(Path.GetTempPath(), "BAKA-Desktop-Preview-" + Guid.NewGuid().ToString("N"))
                            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BAKA");
            foreach (var d in new[] { Path.GetDirectoryName(Settings), Logs, State }) Directory.CreateDirectory(d);
        }
        static string FindRepo(string dir)
        {
            for (var d = new DirectoryInfo(dir); d != null; d = d.Parent)
                if (File.Exists(Path.Combine(d.FullName, "Config", "DesktopThemes.json"))) return d.FullName;
            return null;
        }
        // Shipped files live in the data root (installed) or its Config\ / Assets\Wallpapers\ (repository).
        public static string Shipped(string name)
        {
            foreach (var c in new[] { Path.Combine(Data, name), Path.Combine(Data, "Config", name), Path.Combine(Data, "Assets", name), Path.Combine(Data, "Assets", "Wallpapers", name) })
                if (File.Exists(c)) return c;
            return null;
        }
        public static IEnumerable<string> Wallpapers()
        {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var dir in new[] { Path.Combine(Data, "Assets"), Path.Combine(Data, "Assets", "Wallpapers") })
            {
                if (!Directory.Exists(dir)) continue;
                foreach (var f in Directory.GetFiles(dir).Where(f => f.EndsWith(".png", StringComparison.OrdinalIgnoreCase) || f.EndsWith(".jpg", StringComparison.OrdinalIgnoreCase)).OrderBy(f => f))
                    if (seen.Add(Path.GetFileName(f))) yield return f;
            }
        }
        public static string Expand(string p) => string.IsNullOrEmpty(p) ? p : Environment.ExpandEnvironmentVariables(p);
    }

    static class Log
    {
        static readonly object Gate = new object();
        public static readonly List<string> Lines = new List<string>();
        public static void Write(string message)
        {
            string line = DateTime.Now.ToString("o") + " " + message;
            lock (Gate)
            {
                Lines.Add(line); if (Lines.Count > 4000) Lines.RemoveRange(0, 1000);
                try { File.AppendAllText(Path.Combine(Paths.Logs, "Desktop.log"), line + Environment.NewLine, Encoding.UTF8); } catch { }
            }
        }
    }

    // JSON as nested dictionaries/lists, with case-insensitive lookups so the settings file written by
    // earlier BAKA releases (and the PowerShell schema validator) keeps working unchanged.
    static class Json
    {
        static JavaScriptSerializer S => new JavaScriptSerializer { MaxJsonLength = int.MaxValue, RecursionLimit = 64 };
        public static object Parse(string text) => Normalize(S.DeserializeObject(text));
        static object Normalize(object o)
        {
            if (o is Dictionary<string, object> d)
            {
                var r = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
                foreach (var kv in d) r[kv.Key] = Normalize(kv.Value);
                return r;
            }
            if (o is object[] a) return a.Select(Normalize).ToList();
            if (o is ArrayList al) return al.Cast<object>().Select(Normalize).ToList();
            return o;
        }
        // Indented output: settings are read by people too.
        public static string Write(object o) { var sb = new StringBuilder(); WriteValue(sb, o, 0); return sb.ToString(); }
        static void WriteValue(StringBuilder sb, object o, int indent)
        {
            switch (o)
            {
                case null: sb.Append("null"); break;
                case bool b: sb.Append(b ? "true" : "false"); break;
                case string s: sb.Append(S.Serialize(s)); break;
                case IDictionary d:
                    if (d.Count == 0) { sb.Append("{}"); break; }
                    sb.Append("{\n"); int i = 0;
                    foreach (DictionaryEntry kv in d) { sb.Append(' ', (indent + 1) * 2).Append(S.Serialize(kv.Key.ToString())).Append(": "); WriteValue(sb, kv.Value, indent + 1); if (++i < d.Count) sb.Append(','); sb.Append('\n'); }
                    sb.Append(' ', indent * 2).Append('}'); break;
                case IEnumerable e:
                    var items = e.Cast<object>().ToList();
                    if (items.Count == 0) { sb.Append("[]"); break; }
                    sb.Append("[\n");
                    for (int j = 0; j < items.Count; j++) { sb.Append(' ', (indent + 1) * 2); WriteValue(sb, items[j], indent + 1); if (j < items.Count - 1) sb.Append(','); sb.Append('\n'); }
                    sb.Append(' ', indent * 2).Append(']'); break;
                default: sb.Append(Convert.ToString(o, System.Globalization.CultureInfo.InvariantCulture)); break;
            }
        }
        public static Dictionary<string, object> Obj(object o) => o as Dictionary<string, object>;
        public static List<object> Arr(object o) => o as List<object> ?? new List<object>();
        public static object Get(Dictionary<string, object> d, string key) => d != null && d.TryGetValue(key, out object v) ? v : null;
        public static string Str(Dictionary<string, object> d, string key, string def = "") => Get(d, key)?.ToString() ?? def;
        public static int Int(Dictionary<string, object> d, string key, int def = 0) { var v = Get(d, key); try { return v == null ? def : Convert.ToInt32(v); } catch { return def; } }
        public static bool Bool(Dictionary<string, object> d, string key, bool def = false) { var v = Get(d, key); return v is bool b ? b : def; }
        public static Dictionary<string, object> Section(Dictionary<string, object> d, string key)
        {
            if (Get(d, key) is Dictionary<string, object> s) return s;
            s = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase); d[key] = s; return s;
        }
    }

    // The desktop settings file: same schema and file as before, so nothing a user set is lost.
    class Settings
    {
        public Dictionary<string, object> Root;
        public Dictionary<string, object> Appearance => Json.Section(Root, "appearance");
        public Dictionary<string, object> Wallpaper => Json.Section(Root, "wallpaper");
        public Dictionary<string, object> Taskbar => Json.Section(Root, "taskbar");
        public Dictionary<string, object> Dock => Json.Section(Root, "dock");
        public Dictionary<string, object> TopBar => Json.Section(Root, "topBar");
        public Dictionary<string, object> Widgets => Json.Section(Root, "widgets");
        public Dictionary<string, object> Integration => Json.Section(Root, "integration");
        public List<object> Pinned { get { if (!(Json.Get(Root, "pinnedApps") is List<object> l)) { l = new List<object>(); Root["pinnedApps"] = l; } return l; } }
        public List<object> WidgetItems { get { if (!(Json.Get(Widgets, "items") is List<object> l)) { l = new List<object>(); Widgets["items"] = l; } return l; } }

        public static Settings Load()
        {
            var s = new Settings();
            foreach (var candidate in new[] { Paths.Settings, Paths.Settings + ".bak", Paths.Shipped("DesktopSettings.default.json") })
            {
                try
                {
                    if (candidate == null || !File.Exists(candidate)) continue;
                    if (Json.Parse(File.ReadAllText(candidate)) is Dictionary<string, object> d && Json.Get(d, "appearance") != null) { s.Root = d; break; }
                }
                catch (Exception e) { Log.Write("settings-unreadable path=\"" + candidate + "\" error=\"" + e.Message + "\""); }
            }
            if (s.Root == null) s.Root = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase) { ["schemaVersion"] = 1 };
            s.Complete();
            return s;
        }

        // Fills sections that older settings files do not have. Existing values are never overwritten.
        void Complete()
        {
            Def(Appearance, "theme", "BAKA Carbon"); Def(Appearance, "accentColor", "#FAFAFA"); Def(Appearance, "glassIntensity", 34);
            Def(Appearance, "animationIntensity", "Full"); Def(Appearance, "reducedMotion", false); Def(Appearance, "iconStyle", "Themed");
            Def(Wallpaper, "mode", "Image"); Def(Wallpaper, "path", @"%ProgramData%\BAKA\Assets\BAKA-Stealth-4K.png"); Def(Wallpaper, "fit", "Fill");
            Def(Wallpaper, "color", "#05060A"); Def(Wallpaper, "muted", true); Def(Wallpaper, "pauseInGames", true);
            Def(Taskbar, "autoHideWindowsTaskbar", true); Def(Taskbar, "showRunningApps", true); Def(Taskbar, "showStartButton", true);
            Def(Dock, "alignment", "Left"); Def(Dock, "iconSize", 40); Def(Dock, "spacing", 6); Def(Dock, "autoHide", false); Def(Dock, "magnification", true); Def(Dock, "monitor", "Primary");
            Def(TopBar, "enabled", true); Def(TopBar, "showProfile", true); Def(TopBar, "showDate", true); Def(TopBar, "monitor", "Primary");
            Def(Widgets, "enabled", false); Def(Widgets, "refreshSeconds", 3);
            Def(Integration, "filesOpensFolders", true); Def(Integration, "hideDesktopIcons", true); Def(Integration, "winKeyOpensLaunchpad", true);
            var known = WidgetItems.Select(i => Json.Str(Json.Obj(i), "id")).ToList();
            foreach (var w in new[] { ("clock", true, 104, 48, 260, 160), ("calendar", false, 104, 222, 260, 250), ("system", false, 380, 48, 300, 190), ("notes", false, 380, 252, 300, 190), ("media", false, 696, 48, 280, 190), ("timer", false, 696, 252, 280, 200) })
                if (!known.Contains(w.Item1)) WidgetItems.Add(new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase) { ["id"] = w.Item1, ["enabled"] = w.Item2, ["left"] = w.Item3, ["top"] = w.Item4, ["width"] = w.Item5, ["height"] = w.Item6 });
            foreach (var p in Pinned.Select(Json.Obj).Where(p => p != null))
            {
                Def(p, "iconPath", ""); Def(p, "arguments", ""); Def(p, "glyph", "");
                // Files used to open Windows File Explorer; it is BAKA Files now.
                if (Json.Str(p, "id") == "explorer" && Json.Str(p, "target").EndsWith("explorer.exe", StringComparison.OrdinalIgnoreCase)) { p["kind"] = "Baka"; p["target"] = "files"; }
            }
            if (Json.Get(Root, "schemaVersion") == null) Root["schemaVersion"] = 1;
        }
        static void Def(Dictionary<string, object> d, string k, object v) { if (!d.ContainsKey(k)) d[k] = v; }

        public void Save()
        {
            try
            {
                string tmp = Paths.Settings + ".tmp";
                File.WriteAllText(tmp, Json.Write(Root), new UTF8Encoding(true));
                if (File.Exists(Paths.Settings)) { File.Copy(Paths.Settings, Paths.Settings + ".bak", true); File.Replace(tmp, Paths.Settings, null); }
                else File.Move(tmp, Paths.Settings);
            }
            catch (Exception e) { Log.Write("settings-save-failed error=\"" + e.Message + "\""); }
        }
    }
}
