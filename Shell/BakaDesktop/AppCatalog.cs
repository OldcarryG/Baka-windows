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

        public static void Refresh(bool wait = false)
        {
            var task = Task.Factory.StartNew(Load, System.Threading.CancellationToken.None, TaskCreationOptions.LongRunning, StaScheduler.Instance);
            if (wait) task.Wait(15000);
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
                    list.Add(app);
                }
                Marshal.FinalReleaseComObject(folder); Marshal.FinalReleaseComObject(shell);
            }
            catch (Exception e) { Log.Write("apps-list-failed error=\"" + e.Message + "\""); }
            list = list.GroupBy(a => a.Name, StringComparer.OrdinalIgnoreCase).Select(g => g.First()).OrderBy(a => a.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
            if (list.Count > 0) { apps = list; loaded = DateTime.Now; }
            Log.Write("apps-listed count=" + list.Count);
            System.Windows.Application.Current?.Dispatcher.BeginInvoke(new Action(() => Updated?.Invoke()));
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
            try
            {
                var target = !string.IsNullOrEmpty(app.Exe) && File.Exists(app.Exe) ? app.Exe : app.ParsingName;
                var psi = new ProcessStartInfo(target) { UseShellExecute = true };
                if (admin) psi.Verb = "runas";
                Process.Start(psi);
                Log.Write("app-launched name=\"" + app.Name + "\"");
            }
            catch (Exception e) { Log.Write("app-launch-failed name=\"" + app.Name + "\" error=\"" + e.Message + "\""); }
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
        public static List<OpenWindow> List()
        {
            var result = new List<OpenWindow>(); int me = Process.GetCurrentProcess().Id;
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
                    var w = new OpenWindow { Handle = h, Title = Native.WindowText(h), Pid = pid, Minimized = Native.IsIconic(h), Exe = Native.ProcessPath(pid) ?? "", AppId = Native.WindowAppId(h) };
                    // Explorer's own windows are not shown: BAKA Files replaces them.
                    if (cls == "CabinetWClass" && Path.GetFileName(w.Exe).Equals("explorer.exe", StringComparison.OrdinalIgnoreCase)) { }
                    result.Add(w);
                }
                catch { }
                return true;
            }, IntPtr.Zero);
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
