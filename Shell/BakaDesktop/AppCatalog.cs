using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace Baka.Desktop
{
    // Every app in the Windows "All apps" list (Store apps, desktop programs and shortcuts), read from the
    // same shell folder the Start menu uses, so the list matches what Windows itself knows exactly.
    static class AppCatalog
    {
        static List<AppRef> apps = new List<AppRef>();
        static DateTime loaded = DateTime.MinValue;
        public static event Action Updated;
        static readonly Regex Hidden = new Regex(@"^(uninstall|read ?me|help|website|release notes|license)\b|uninstall|\buninst\b", RegexOptions.IgnoreCase);

        public static IReadOnlyList<AppRef> Apps => apps;
        public static DateTime Loaded => loaded;

        // One load at a time; a request during a load runs one more load right after it.
        static int loading; static volatile bool again;
        public static void Refresh(bool wait = false)
        {
            if (System.Threading.Interlocked.Exchange(ref loading, 1) == 1) { again = true; return; }
            var task = Task.Factory.StartNew(() =>
            {
                try { do { again = false; Load(); } while (again); }
                finally { System.Threading.Interlocked.Exchange(ref loading, 0); }
            }, System.Threading.CancellationToken.None, TaskCreationOptions.LongRunning, StaScheduler.Instance);
            if (wait) task.Wait(15000);
        }
        // The list follows installs and uninstalls by itself: desktop programs add or remove a Start menu
        // shortcut, Store apps add or remove their package folder. R15 read the list only once at sign-in,
        // so new apps were missing from search and removed ones stayed.
        static readonly List<FileSystemWatcher> watchers = new List<FileSystemWatcher>();
        static System.Windows.Threading.DispatcherTimer settle;
        public static void Watch()
        {
            if (Paths.Preview || watchers.Count > 0) return;
            settle = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(3) };
            // Windows adds a new shortcut to its app list some seconds after the file appears (measured: the
            // list read 3 s after an install did not have it yet), so the list is read once more a bit later.
            var recheck = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(12) };
            recheck.Tick += (o, e) => { recheck.Stop(); Refresh(); };
            settle.Tick += (o, e) => { settle.Stop(); Log.Write("apps-changed"); Refresh(); recheck.Stop(); recheck.Start(); };
            void Add(string dir, bool sub)
            {
                try
                {
                    if (!Directory.Exists(dir)) return;
                    var w = new FileSystemWatcher(dir) { IncludeSubdirectories = sub, NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName, InternalBufferSize = 32768 };
                    FileSystemEventHandler h = (o, e) => { try { System.Windows.Application.Current?.Dispatcher.BeginInvoke(new Action(() => { settle.Stop(); settle.Start(); })); } catch { } };
                    w.Created += h; w.Deleted += h; w.Renamed += (o, e) => h(o, e);
                    w.Error += (o, e) => h(o, null);
                    w.EnableRaisingEvents = true; watchers.Add(w);
                }
                catch (Exception e) { Log.Write("apps-watch-failed dir=\"" + dir + "\" error=\"" + e.Message + "\""); }
            }
            Add(Environment.GetFolderPath(Environment.SpecialFolder.Programs), true);
            Add(Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms), true);
            Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Packages"), false);
            Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "WindowsApps"), false);
        }
        static void Load()
        {
            var list = new List<AppRef>();
            try
            {
                var type = Type.GetTypeFromProgID("Shell.Application");
                dynamic shell = Activator.CreateInstance(type);
                dynamic folder = shell.NameSpace("shell:AppsFolder");
                foreach (dynamic item in folder.Items())
                {
                    string name = item.Name, id = item.Path;
                    if (string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(id) || Hidden.IsMatch(name)) continue;
                    var app = new AppRef { Name = name, AppId = id };
                    // Desktop programs are listed by a path (or a known-folder GUID + relative path).
                    if (id.Contains("\\") && !id.Contains("!")) app.Exe = ResolveKnownFolder(id);
                    // Entries listed by an app id instead of a path: ask Windows which program they start, so a
                    // pin of them can be matched to its windows (otherwise the dock showed the app twice).
                    else if (!id.Contains("!"))
                    {
                        try { object t = item.ExtendedProperty("System.Link.TargetParsingPath"); if (t is string s && s.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) app.Target = s; } catch { }
                    }
                    list.Add(app);
                }
                Marshal.FinalReleaseComObject(folder); Marshal.FinalReleaseComObject(shell);
            }
            catch (Exception e) { Log.Write("apps-list-failed error=\"" + e.Message + "\""); }
            list = list.GroupBy(a => a.Name, StringComparer.OrdinalIgnoreCase).Select(g => g.First()).OrderBy(a => a.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
            if (list.Count == 0) { Log.Write("apps-listed count=0 (kept the previous list)"); return; }
            string before = string.Join("\n", apps.Select(a => a.Key)), after = string.Join("\n", list.Select(a => a.Key));
            loaded = DateTime.Now;
            if (before == after) return; // nothing installed or removed: nothing to redraw
            var added = list.Where(a => !apps.Any(b => b.Key == a.Key)).Select(a => a.Name).ToList();
            var removed = apps.Where(a => !list.Any(b => b.Key == a.Key)).Select(a => a.Name).ToList();
            bool first = apps.Count == 0;
            apps = list;
            Log.Write("apps-listed count=" + list.Count + (first ? "" : " added=\"" + string.Join(", ", added) + "\" removed=\"" + string.Join(", ", removed) + "\""));
            System.Windows.Application.Current?.Dispatcher.BeginInvoke(new Action(() => { Icons.ForgetMissing(); Updated?.Invoke(); }));
        }
        static string ResolveKnownFolder(string id)
        {
            var m = Regex.Match(id, @"^\{([0-9A-Fa-f-]{36})\}\\(.*)$");
            if (!m.Success) return id;
            try { if (SHGetKnownFolderPath(new Guid(m.Groups[1].Value), 0, IntPtr.Zero, out string root) == 0) return Path.Combine(root, m.Groups[2].Value); } catch { }
            return id;
        }
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern int SHGetKnownFolderPath([MarshalAs(UnmanagedType.LPStruct)] Guid id, uint flags, IntPtr token, out string path);

        public static void Launch(AppRef app, bool admin = false)
        {
            // Off the UI thread: shell/UWP activation can block for seconds and would freeze BAKA when it is
            // the shell (this is what hung the whole desktop when opening the Microsoft Store).
            Launcher.Run(app.Name, () =>
            {
                // a Store app (its id carries "!"): start it the shell-free way so it also works when BAKA is
                // the shell and Explorer is not running
                if (!admin && (string.IsNullOrEmpty(app.Exe) || !File.Exists(app.Exe)) && !string.IsNullOrEmpty(app.AppId) && app.AppId.Contains("!") && Native.LaunchAppId(app.AppId, null))
                { Log.Write("app-launched name=\"" + app.Name + "\" via=aumid"); return; }
                var target = !string.IsNullOrEmpty(app.Exe) && File.Exists(app.Exe) ? app.Exe : app.ParsingName;
                var psi = new ProcessStartInfo(target) { UseShellExecute = true };
                if (admin) psi.Verb = "runas";
                Process.Start(psi);
                Log.Write("app-launched name=\"" + app.Name + "\"");
            });
        }
        public static void OpenLocation(AppRef app)
        {
            string path = app.Exe;
            if (string.IsNullOrEmpty(path) || !File.Exists(path)) return;
            if (path.EndsWith(".lnk", StringComparison.OrdinalIgnoreCase)) path = ShortcutTarget(path) ?? path;
            Files.Open(Path.GetDirectoryName(path), path);
        }
        public static string ShortcutTarget(string lnk)
        {
            try { dynamic sh = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell")); dynamic s = sh.CreateShortcut(lnk); string t = s.TargetPath; return string.IsNullOrEmpty(t) ? null : t; } catch { return null; }
        }

        // An app also matches its program name: "cmd" is Command Prompt, "regedit" is Registry Editor.
        public static int ScoreApp(AppRef a, string query)
        {
            int s = Score(a.Name, query);
            string exe = string.IsNullOrEmpty(a.Exe) ? "" : Path.GetFileNameWithoutExtension(a.Exe);
            if (exe.Length > 0 && exe.Equals(query.Trim(), StringComparison.OrdinalIgnoreCase)) s = Math.Max(s, 950);
            return s;
        }

        // ---- search: exact, word-start, initials and fuzzy matches, best first ----
        public static int Score(string name, string query)
        {
            if (string.IsNullOrEmpty(query)) return 1;
            string n = name.ToLowerInvariant(), q = query.ToLowerInvariant().Trim();
            if (n == q) return 1000;
            if (n.StartsWith(q)) return 900 - n.Length;
            var words = Regex.Split(n, @"[^\p{L}\p{N}]+").Where(w => w.Length > 0).ToArray();
            if (words.Any(w => w.StartsWith(q))) return 800 - n.Length;
            string initials = string.Concat(words.Select(w => w[0]));
            if (q.Length >= 2 && initials.StartsWith(q)) return 700;
            int at = n.IndexOf(q, StringComparison.Ordinal);
            if (at >= 0) return 600 - at;
            // every query letter appears in order, starting at a word (e.g. "vsc" -> Visual Studio Code)
            int i = 0; foreach (char c in n) if (i < q.Length && c == q[i]) i++;
            if (i == q.Length && q.Length >= 2 && initials.IndexOf(q[0]) >= 0) return 400 - n.Length;
            // one typo in a word ("discrod", "stema")
            if (q.Length >= 4 && words.Any(w => Typo(w, q))) return 300;
            return 0;
        }
        static bool Typo(string word, string q)
        {
            if (Math.Abs(word.Length - q.Length) > 1) { if (word.Length > q.Length && Typo(word.Substring(0, q.Length), q)) return true; return false; }
            int[,] d = new int[word.Length + 1, q.Length + 1];
            for (int i = 0; i <= word.Length; i++) d[i, 0] = i;
            for (int j = 0; j <= q.Length; j++) d[0, j] = j;
            for (int i = 1; i <= word.Length; i++) for (int j = 1; j <= q.Length; j++)
                {
                    int cost = word[i - 1] == q[j - 1] ? 0 : 1;
                    d[i, j] = Math.Min(Math.Min(d[i - 1, j] + 1, d[i, j - 1] + 1), d[i - 1, j - 1] + cost);
                    if (i > 1 && j > 1 && word[i - 1] == q[j - 2] && word[i - 2] == q[j - 1]) d[i, j] = Math.Min(d[i, j], d[i - 2, j - 2] + 1);
                }
            return d[word.Length, q.Length] <= 1;
        }
    }

    // Windows Settings pages the search can open directly.
    static class SettingsPages
    {
        public static readonly (string name, string uri, string words)[] All =
        {
            ("Display", "ms-settings:display", "screen resolution scale brightness monitor hdr refresh rate"), ("Sound", "ms-settings:sound", "audio volume speakers microphone output input"),
            ("Bluetooth & devices", "ms-settings:bluetooth", "bluetooth pair headphones mouse keyboard controller"), ("Wi-Fi", "ms-settings:network-wifi", "wifi wireless internet network"),
            ("Network & internet", "ms-settings:network", "ethernet internet vpn proxy dns ip"), ("VPN", "ms-settings:network-vpn", "vpn"),
            ("Windows Update", "ms-settings:windowsupdate", "update updates patch upgrade"), ("Apps & features", "ms-settings:appsfeatures", "uninstall remove programs apps installed"),
            ("Default apps", "ms-settings:defaultapps", "default browser open with association"), ("Startup apps", "ms-settings:startupapps", "startup boot login autostart"),
            ("Storage", "ms-settings:storagesense", "disk space storage cleanup"), ("Power & battery", "ms-settings:powersleep", "power sleep battery screen off"),
            ("Mouse", "ms-settings:mousetouchpad", "mouse pointer cursor speed sensitivity"), ("Keyboard", "ms-settings:typing", "keyboard typing"),
            ("Language & region", "ms-settings:regionlanguage", "language region keyboard layout ime"), ("Date & time", "ms-settings:dateandtime", "date time clock timezone"),
            ("Accounts", "ms-settings:yourinfo", "account user profile picture"), ("Sign-in options", "ms-settings:signinoptions", "password pin hello sign in"),
            ("Privacy & security", "ms-settings:privacy", "privacy permissions location camera microphone"), ("Windows Security", "windowsdefender:", "antivirus defender virus security firewall"),
            ("Gaming", "ms-settings:gaming-gamemode", "game mode gaming"), ("Graphics", "ms-settings:display-advancedgraphics", "gpu graphics performance preference"),
            ("Printers & scanners", "ms-settings:printers", "printer scanner print"), ("Notifications", "ms-settings:notifications", "notifications do not disturb focus"),
            ("Multitasking", "ms-settings:multitasking", "snap windows alt tab virtual desktops"), ("Clipboard", "ms-settings:clipboard", "clipboard history copy paste"),
            ("About this PC", "ms-settings:about", "about pc name specs rename windows version"), ("Recovery", "ms-settings:recovery", "reset recovery restore"),
            ("Activation", "ms-settings:activation", "activate product key license"), ("Night light", "ms-settings:nightlight", "night light blue light"),
            ("Accessibility", "ms-settings:easeofaccess", "accessibility narrator magnifier contrast"), ("Optional features", "ms-settings:optionalfeatures", "features optional"),
            ("Device Manager", "devmgmt.msc", "drivers hardware device manager"), ("Disk Management", "diskmgmt.msc", "partition format drive volume disk management"),
        };
    }

    // COM objects such as Shell.Application need a single-threaded apartment; this runs work on one.
    class StaScheduler : TaskScheduler
    {
        public static readonly StaScheduler Instance = new StaScheduler();
        protected override void QueueTask(Task task) { var t = new System.Threading.Thread(() => TryExecuteTask(task)) { IsBackground = true }; t.SetApartmentState(System.Threading.ApartmentState.STA); t.Start(); }
        protected override bool TryExecuteTaskInline(Task task, bool previouslyQueued) => false;
        protected override IEnumerable<Task> GetScheduledTasks() => Enumerable.Empty<Task>();
    }

    // Open windows, for the dock and the app switcher.
    class OpenWindow { public IntPtr Handle; public string Title, Exe, AppId; public uint Pid; public bool Minimized; }

    static class Windows
    {
        static readonly HashSet<string> Skip = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Windows.UI.Core.CoreWindow", "Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "XamlExplorerHostIslandWindow" };
        static readonly int me = Process.GetCurrentProcess().Id;
        // A window's program and app id do not change, so they are read once per window instead of on every
        // refresh (opening each process and asking the shell for each window's properties is the costly part).
        static readonly Dictionary<IntPtr, (uint pid, string exe, string appId, DateTime at)> known = new Dictionary<IntPtr, (uint, string, string, DateTime)>();
        public static List<OpenWindow> List()
        {
            var result = new List<OpenWindow>(); var seen = new HashSet<IntPtr>();
            Native.EnumWindows((h, p) =>
            {
                try
                {
                    if (!Native.IsWindowVisible(h) || Native.GetWindow(h, 4) != IntPtr.Zero) return true; // owned windows (dialogs) are skipped
                    long ex = Native.ExStyle(h);
                    if ((ex & Native.WS_EX_TOOLWINDOW) != 0 && (ex & Native.WS_EX_APPWINDOW) == 0) return true;
                    if (Native.IsCloaked(h) || Native.GetWindowTextLength(h) == 0) return true;
                    string cls = Native.ClassName(h); if (Skip.Contains(cls)) return true;
                    Native.GetWindowThreadProcessId(h, out uint pid);
                    if (pid == me) return true;
                    seen.Add(h);
                    // Store apps get their app id a moment after the window appears: re-read it for a few seconds.
                    if (!known.TryGetValue(h, out var info) || info.pid != pid || (string.IsNullOrEmpty(info.appId) && (DateTime.Now - info.at).TotalSeconds < 8))
                    {
                        var at = known.TryGetValue(h, out var old) && old.pid == pid ? old.at : DateTime.Now;
                        string exe = Native.ProcessPath(pid) ?? "";
                        // a window without an app id of its own takes its packaged process's app id (WhatsApp)
                        string appId = Native.WindowAppId(h);
                        if (string.IsNullOrEmpty(appId) && !exe.EndsWith("ApplicationFrameHost.exe", StringComparison.OrdinalIgnoreCase)) appId = Native.ProcessAppId(pid);
                        info = (pid, exe, appId, at); known[h] = info;
                    }
                    result.Add(new OpenWindow { Handle = h, Title = Native.WindowText(h), Pid = pid, Minimized = Native.IsIconic(h), Exe = info.exe, AppId = info.appId });
                }
                catch { }
                return true;
            }, IntPtr.Zero);
            foreach (var h in known.Keys.Where(k => !seen.Contains(k)).ToList()) known.Remove(h);
            return result;
        }
        public static void Toggle(OpenWindow w)
        {
            if (Native.GetForegroundWindow() == w.Handle && !Native.IsIconic(w.Handle)) Native.ShowWindowAsync(w.Handle, Native.SW_MINIMIZE);
            else Native.Activate(w.Handle);
        }
        public static void Close(IntPtr h) => Native.PostMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero);
    }
}
