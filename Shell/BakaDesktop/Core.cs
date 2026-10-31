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
        public Dictionary<string, object> Focus => Json.Section(Root, "focus");
        public Dictionary<string, object> Overlay => Json.Section(Root, "overlay");
        public Dictionary<string, object> Gaming => Json.Section(Root, "gaming");
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
            Def(TopBar, "enabled", true); Def(TopBar, "showProfile", true); Def(TopBar, "showDate", false); Def(TopBar, "monitor", "Primary");
            Def(Widgets, "enabled", false); Def(Widgets, "refreshSeconds", 3);
            Def(Integration, "filesOpensFolders", true); Def(Integration, "hideDesktopIcons", true); Def(Integration, "winKeyOpensLaunchpad", true); Def(Integration, "captionButtons", false);
            // 12.27: the bell's "Do not disturb" became Focus mode
            if (Integration.ContainsKey("doNotDisturb")) { if (!Focus.ContainsKey("enabled")) Focus["enabled"] = Json.Bool(Integration, "doNotDisturb"); Integration.Remove("doNotDisturb"); }
            Def(Focus, "enabled", false); Def(Focus, "autoInGames", true); Def(Focus, "hideDock", true); Def(Focus, "pauseWallpaper", true);
            Def(Overlay, "enabled", false); Def(Overlay, "when", "Games"); Def(Overlay, "position", "TopLeft"); Def(Overlay, "detail", "Standard");
            // 12.28: "Light" keeps the menu bar, dock and Launchpad working in games; "Hidden" is the old way.
            // Store apps listed in backgroundAllowed keep running in the background while a game runs.
            Def(Gaming, "desktop", "Light"); Def(Gaming, "pauseBackgroundApps", true); Def(Gaming, "backgroundAllowed", new List<object>());
            // R16: BAKA's painted window buttons can only cover windows with the standard Windows title bar, so
            // every app looked different (BAKA buttons on some, Windows buttons on others, doubled buttons on
            // some). Windows' own buttons are the default again; the BAKA ones stay available in Settings.
            if (Json.Int(Root, "desktopRevision", 0) < 16) { Integration["captionButtons"] = false; Root["desktopRevision"] = 16; }
            var known = WidgetItems.Select(i => Json.Str(Json.Obj(i), "id")).ToList();
            foreach (var w in new[] { ("clock", true, 130, 20, 260, 150), ("calendar", false, 130, 190, 260, 250), ("system", false, 130, 185, 300, 210), ("gpu", false, 450, 20, 280, 220), ("network", false, 450, 260, 280, 150), ("storage", false, 750, 20, 280, 180), ("notes", false, 450, 430, 300, 190), ("media", false, 450, 20, 300, 170), ("timer", false, 750, 220, 280, 200), ("toggles", false, 750, 440, 300, 170), ("search", false, 130, 410, 360, 120) })
                if (!known.Contains(w.Item1)) WidgetItems.Add(new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase) { ["id"] = w.Item1, ["enabled"] = w.Item2, ["left"] = w.Item3, ["top"] = w.Item4, ["width"] = w.Item5, ["height"] = w.Item6 });
            // R17: the widget overhaul. Turn widgets on with a tasteful starter set (clock, system monitor,
            // media) placed clear of the left dock, once. The user can hide any with its × or in Settings.
            if (!Paths.Preview && Json.Int(Root, "desktopRevision", 0) < 17)
            {
                Widgets["enabled"] = true;
                EnableWidget("clock", 130, 20, 260, 150);
                EnableWidget("system", 130, 190, 300, 210);
                EnableWidget("media", 450, 20, 300, 170);
                Root["desktopRevision"] = 17;
                Save();
            }
            // 12.27.2: Settings > Menu bar > "Show the date" works again. Since the menu bar redesign the clock
            // showed only the time whatever the switch said, while the switch read "on" (its old default). It is
            // set to off once, so the menu bar looks the same after the update; turning it on shows the date.
            if (!Paths.Preview && Json.Int(Root, "desktopRevision", 0) < 18)
            {
                TopBar["showDate"] = false;
                Root["desktopRevision"] = 18;
                Save();
            }
            foreach (var p in Pinned.Select(Json.Obj).Where(p => p != null))
            {
                Def(p, "iconPath", ""); Def(p, "arguments", ""); Def(p, "glyph", "");
                // Files used to open Windows File Explorer; it is BAKA Files now.
                if (Json.Str(p, "id") == "explorer" && Json.Str(p, "target").EndsWith("explorer.exe", StringComparison.OrdinalIgnoreCase)) { p["kind"] = "Baka"; p["target"] = "files"; }
            }
            if (Json.Get(Root, "schemaVersion") == null) Root["schemaVersion"] = 1;
        }
        static void Def(Dictionary<string, object> d, string k, object v) { if (!d.ContainsKey(k)) d[k] = v; }
        // Turns a widget on and places it (used by the one-time R17 enable). Creates the entry if missing.
        void EnableWidget(string id, int left, int top, int width, int height)
        {
            var it = WidgetItems.Select(Json.Obj).FirstOrDefault(i => i != null && Json.Str(i, "id") == id);
            if (it == null) { it = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase) { ["id"] = id }; WidgetItems.Add(it); }
            it["enabled"] = true; it["left"] = left; it["top"] = top; it["width"] = width; it["height"] = height;
        }

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
