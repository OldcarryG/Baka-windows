using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;

namespace Baka.Desktop
{
    class NoteItem { public long Id, Arrival; public string App = "", AppId = "", Title = "", Body = "", Launch = ""; public DateTime When; public Action Click; }

    // BAKA's notification centre. BAKA cannot use Windows' notification listener: Windows only gives it to
    // apps with a package identity, so it threw "Element not found" (0x80070490) for BAKA every time. And
    // with BAKA as the shell, Windows draws no banners either (measured: a test notification arrived, no
    // window appeared). Windows still records every notification it receives, for its own notification
    // centre, in the user's notification database (%LOCALAPPDATA%\Microsoft\Windows\Notifications\
    // wpndatabase.db, SQLite). BAKA reads that database, read-only, through the SQLite library that ships
    // with Windows (winsqlite3.dll): when it changes, the new notifications are shown as BAKA pop-ups and
    // the list behind the bell. Nothing is installed and nothing is written. Clear only hides them in BAKA.
    static class Notifications
    {
        public static event Action Changed;
        public static readonly List<NoteItem> History = new List<NoteItem>();
        public static bool Available;
        static readonly object gate = new object();
        static readonly HashSet<long> seen = new HashSet<long>();
        static long dismissedBefore;           // Clear: notifications that arrived before this are hidden
        static bool started, primed;
        static System.Threading.Timer poll, soon;
        static int reading;
        static string Folder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "Windows", "Notifications");
        static string Db => Path.Combine(Folder, "wpndatabase.db");

        public static void Start()
        {
            if (started || Paths.Preview) return; started = true;
            try { long.TryParse(Json.Str(App.Settings?.Integration, "notificationsClearedAt", "0"), out dismissedBefore); } catch { }
            if (!File.Exists(Db)) { Log.Write("notifications-unavailable reason=\"no notification database\""); return; }
            // Every 2 s BAKA asks the database one tiny question (how many toasts, the newest arrival: 0.8 ms,
            // measured) and reads the notifications only when that changed. A folder watch was used first, but
            // Windows keeps the database open and its change events came late or not at all: pop-ups showed up
            // to 20 s after the notification (measured), only when the slow backstop ran.
            soon = new System.Threading.Timer(_ => Read(true), null, System.Threading.Timeout.Infinite, System.Threading.Timeout.Infinite);
            poll = new System.Threading.Timer(_ => { if (WpnDatabase.Changed()) Read(true); }, null, 2000, 2000);
            System.Threading.ThreadPool.QueueUserWorkItem(_ => { WpnDatabase.Changed(); Read(false); });
        }
        // Explorer came up: nothing to retry any more (the database is always there); kept for callers.
        public static void Retry() { if (started && !Paths.Preview) soon?.Change(400, System.Threading.Timeout.Infinite); }
        // A game: the 2 s check pauses (nothing pops up during a game anyway); after it, one read catches up.
        public static void Pause(bool paused)
        {
            if (!started || poll == null) return;
            try { if (paused) poll.Change(System.Threading.Timeout.Infinite, System.Threading.Timeout.Infinite); else { poll.Change(2000, 2000); soon?.Change(300, System.Threading.Timeout.Infinite); } } catch { }
        }

        // Reads the newest toasts. popNew: show pop-ups for ones not seen before (false for the first read, so
        // BAKA does not pop up a burst of old notifications when it starts).
        static void Read(bool popNew)
        {
            if (App.GameRunning && popNew) { /* still read, so the bell is current; pop-ups are skipped below */ }
            if (System.Threading.Interlocked.Exchange(ref reading, 1) == 1) return;
            try
            {
                var rows = WpnDatabase.Toasts(60);
                if (rows == null) return;
                var items = new List<NoteItem>(); var fresh = new List<NoteItem>();
                lock (gate)
                {
                    foreach (var r in rows)
                    {
                        if (r.Arrival <= dismissedBefore) continue;
                        var it = Parse(r);
                        if (it == null) continue;
                        items.Add(it);
                        if (seen.Add(r.Id) && primed && popNew && (DateTime.Now - it.When).TotalMinutes < 2) fresh.Add(it);
                    }
                    if (!primed) { primed = true; Available = true; Log.Write("notifications-ready source=wpndatabase count=" + items.Count); }
                }
                App.Ui?.BeginInvoke(new Action(() =>
                {
                    // Clear may have run while this read was in flight: its cut-off applies here too
                    var keep = items.Where(i => i.Arrival > dismissedBefore).OrderByDescending(i => i.When).Take(50).ToList();
                    // the open bell panel is rebuilt only when the list really changed (Windows writes this
                    // database for badges and tiles too, and each rebuild lost the panel's scroll position)
                    bool same = keep.Count == History.Count && keep.Select(i => i.Id).SequenceEqual(History.Select(i => i.Id));
                    if (!same) { History.Clear(); History.AddRange(keep); try { Changed?.Invoke(); } catch { } }
                    foreach (var f in fresh) if (f.Arrival > dismissedBefore) { Log.Write("notification app=\"" + f.App + "\""); NotificationPopup.Show(f); }
                }));
            }
            catch (Exception e) { Log.Write("notifications-read-failed error=\"" + e.Message + "\""); }
            finally { System.Threading.Interlocked.Exchange(ref reading, 0); }
        }

        static NoteItem Parse(WpnDatabase.Row r)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(r.Payload)) return null;
                var doc = new System.Xml.XmlDocument { XmlResolver = null };
                doc.LoadXml(r.Payload);
                var toast = doc.DocumentElement; if (toast == null) return null;
                // the main binding's text lines: the first is the title, the rest the body
                var texts = toast.SelectNodes("visual/binding/text").Cast<System.Xml.XmlNode>()
                    .Where(t => t.Attributes?["placement"] == null).Select(t => (t.InnerText ?? "").Trim()).Where(t => t.Length > 0).ToList();
                if (texts.Count == 0) return null;
                var it = new NoteItem { Id = r.Id, Arrival = r.Arrival, AppId = r.AppId, Title = texts[0], Body = string.Join("  ", texts.Skip(1)) };
                it.Launch = toast.Attributes?["launch"]?.Value ?? "";
                // Windows stores the arrival time as a FILETIME (100 ns ticks since 1601, UTC)
                try { it.When = DateTime.FromFileTimeUtc(r.Arrival).ToLocalTime(); } catch { it.When = DateTime.Now; }
                it.App = AppName(r.AppId);
                string id = r.AppId;
                it.Click = () => OpenApp(id);
                return it;
            }
            catch { return null; }
        }

        // The name Windows shows for an app id: the Start-menu entry with that id, else the name an app
        // registered for its notifications, else a tidied-up id.
        static readonly Dictionary<string, string> names = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        static string AppName(string appId)
        {
            if (string.IsNullOrEmpty(appId)) return "";
            lock (names) if (names.TryGetValue(appId, out var known)) return known;
            string name = null;
            try { name = AppCatalog.Apps.FirstOrDefault(a => string.Equals(a.AppId, appId, StringComparison.OrdinalIgnoreCase))?.Name; } catch { }
            if (string.IsNullOrEmpty(name))
                foreach (var root in new[] { Microsoft.Win32.Registry.CurrentUser, Microsoft.Win32.Registry.LocalMachine })
                {
                    try { using (var k = root.OpenSubKey(@"Software\Classes\AppUserModelId\" + appId)) { var dn = k?.GetValue("DisplayName") as string; if (!string.IsNullOrEmpty(dn) && !dn.StartsWith("@")) { name = dn; break; } } } catch { }
                }
            bool guessed = false;
            if (string.IsNullOrEmpty(name))
            {
                // "{GUID}\WindowsPowerShell\v1.0\powershell.exe" -> "Powershell"
                // "Microsoft.Teams_8wekyb3d8bbwe!App" -> "Teams";  "com.squirrel.Discord.Discord" -> "Discord"
                guessed = true;
                string s = appId;
                int bang = s.IndexOf('!'); if (bang > 0) s = s.Substring(0, bang);
                s = s.Replace('/', '\\').Split('\\').Last();
                if (s.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) s = s.Substring(0, s.Length - 4);
                int us = s.IndexOf('_'); if (us > 0) s = s.Substring(0, us);       // package family hash
                int dot = s.LastIndexOf('.'); if (dot >= 0 && dot < s.Length - 1) s = s.Substring(dot + 1);
                name = s.Length > 0 ? char.ToUpper(s[0]) + s.Substring(1) : appId;
            }
            // a guess is not remembered while BAKA's app list is still loading: the real name comes with it
            if (!guessed || AppCatalog.Loaded != DateTime.MinValue) lock (names) names[appId] = name;
            return name;
        }

        // A click on a notification brings its app to the front: an open window of it if there is one,
        // otherwise the app is started from its Start-menu entry.
        static void OpenApp(string appId)
        {
            try
            {
                var app = AppCatalog.Apps.FirstOrDefault(a => string.Equals(a.AppId, appId, StringComparison.OrdinalIgnoreCase));
                if (app != null) { AppCatalog.Launch(app); return; }
                if (appId.Contains("!")) Launcher.Run(appId, () => Native.LaunchAppId(appId, null));
            }
            catch (Exception e) { Log.Write("notification-open-failed error=\"" + e.Message + "\""); }
        }

        public static void Clear()
        {
            // the exact arrival stamp Windows stored, so the cut-off matches the database to the tick
            long newest = 0;
            foreach (var n in History) newest = Math.Max(newest, n.Arrival);
            dismissedBefore = Math.Max(dismissedBefore, newest);
            try { if (App.Settings != null) { App.Settings.Integration["notificationsClearedAt"] = dismissedBefore.ToString(); App.Settings.Save(); } } catch { }
            History.Clear(); try { Changed?.Invoke(); } catch { }
        }
    }

    // Read-only access to Windows' notification database through winsqlite3.dll (part of Windows 10/11).
    static class WpnDatabase
    {
        public class Row { public long Id, Arrival; public string AppId = "", Payload = ""; }
        const int SQLITE_OPEN_READONLY = 0x1, SQLITE_ROW = 100, SQLITE_OK = 0;
        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.StdCall)] static extern int sqlite3_open_v2(byte[] file, out IntPtr db, int flags, IntPtr vfs);
        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.StdCall)] static extern int sqlite3_close(IntPtr db);
        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.StdCall)] static extern int sqlite3_busy_timeout(IntPtr db, int ms);
        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.StdCall, CharSet = CharSet.Unicode)] static extern int sqlite3_prepare16_v2(IntPtr db, string sql, int bytes, out IntPtr stmt, IntPtr tail);
        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.StdCall)] static extern int sqlite3_step(IntPtr stmt);
        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.StdCall)] static extern int sqlite3_finalize(IntPtr stmt);
        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.StdCall)] static extern long sqlite3_column_int64(IntPtr stmt, int col);
        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.StdCall)] static extern IntPtr sqlite3_column_text16(IntPtr stmt, int col);
        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.StdCall)] static extern IntPtr sqlite3_column_blob(IntPtr stmt, int col);
        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.StdCall)] static extern int sqlite3_column_bytes(IntPtr stmt, int col);
        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.StdCall)] static extern IntPtr sqlite3_errmsg16(IntPtr db);

        static string lastError;
        static readonly string file = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "Windows", "Notifications", "wpndatabase.db");
        static string lastStamp = "";
        static int checking;
        // True when the toasts changed since the last call (one new, one removed). Cheap: count + newest stamp.
        public static bool Changed()
        {
            if (System.Threading.Interlocked.Exchange(ref checking, 1) == 1) return false;
            IntPtr db = IntPtr.Zero, st = IntPtr.Zero;
            try
            {
                if (sqlite3_open_v2(Encoding.UTF8.GetBytes(file + "\0"), out db, SQLITE_OPEN_READONLY, IntPtr.Zero) != SQLITE_OK) return false;
                sqlite3_busy_timeout(db, 300);
                if (sqlite3_prepare16_v2(db, "select count(*), max(ArrivalTime), max(Id) from Notification where Type = 'toast'", -1, out st, IntPtr.Zero) != SQLITE_OK) return false;
                if (sqlite3_step(st) != SQLITE_ROW) return false;
                string stamp = sqlite3_column_int64(st, 0) + ":" + sqlite3_column_int64(st, 1) + ":" + sqlite3_column_int64(st, 2);
                if (stamp == lastStamp) return false;
                lastStamp = stamp;
                return true;
            }
            catch { return false; }
            finally { if (st != IntPtr.Zero) sqlite3_finalize(st); if (db != IntPtr.Zero) sqlite3_close(db); System.Threading.Interlocked.Exchange(ref checking, 0); }
        }
        public static List<Row> Toasts(int max)
        {
            IntPtr db = IntPtr.Zero, st = IntPtr.Zero;
            try
            {
                if (sqlite3_open_v2(Encoding.UTF8.GetBytes(file + "\0"), out db, SQLITE_OPEN_READONLY, IntPtr.Zero) != SQLITE_OK) { Fail(db, "open"); return null; }
                sqlite3_busy_timeout(db, 1500); // Windows may be writing at this moment
                const string sql = "select n.Id, n.ArrivalTime, h.PrimaryId, n.Payload from Notification n left join NotificationHandler h on h.RecordId = n.HandlerId where n.Type = 'toast' order by n.ArrivalTime desc limit ";
                if (sqlite3_prepare16_v2(db, sql + Math.Max(1, max), -1, out st, IntPtr.Zero) != SQLITE_OK) { Fail(db, "prepare"); return null; }
                var list = new List<Row>();
                int rc;
                while ((rc = sqlite3_step(st)) == SQLITE_ROW)
                {
                    var r = new Row { Id = sqlite3_column_int64(st, 0), Arrival = sqlite3_column_int64(st, 1) };
                    IntPtr t = sqlite3_column_text16(st, 2); if (t != IntPtr.Zero) r.AppId = Marshal.PtrToStringUni(t) ?? "";
                    // the payload is a blob of UTF-8 XML
                    int n = sqlite3_column_bytes(st, 3); IntPtr b = sqlite3_column_blob(st, 3);
                    if (b != IntPtr.Zero && n > 0 && n < 512 * 1024) { var bytes = new byte[n]; Marshal.Copy(b, bytes, 0, n); r.Payload = Encoding.UTF8.GetString(bytes).TrimStart('\uFEFF').Trim('\0'); }
                    list.Add(r);
                }
                // anything but "done" (busy, I/O error) is a failed read, not an empty or shorter list: the
                // bell would otherwise empty until the next read
                if (rc != 101 /*SQLITE_DONE*/) { Fail(db, "step rc=" + rc); return null; }
                lastError = null;
                return list;
            }
            catch (DllNotFoundException) { if (lastError != "dll") { lastError = "dll"; Log.Write("notifications-unavailable reason=\"winsqlite3.dll missing\""); } return null; }
            catch (Exception e) { if (lastError != e.Message) { lastError = e.Message; Log.Write("notifications-db-failed error=\"" + e.Message + "\""); } return null; }
            finally { if (st != IntPtr.Zero) sqlite3_finalize(st); if (db != IntPtr.Zero) sqlite3_close(db); }
        }
        static void Fail(IntPtr db, string what)
        {
            string m = "";
            try { if (db != IntPtr.Zero) m = Marshal.PtrToStringUni(sqlite3_errmsg16(db)); } catch { }
            if (lastError != what + m) { lastError = what + m; Log.Write("notifications-db-failed step=" + what + " error=\"" + m + "\""); }
        }
    }

    // A single pop-up that slides in top-right, stacks under the ones already showing, and fades after a few
    // seconds. Click dismisses it.
    class NotificationPopup : GlassPanel
    {
        static readonly List<NotificationPopup> open = new List<NotificationPopup>();
        DispatcherTimer life;

        public static void Show(NoteItem n)
        {
            // BAKA as the shell: Windows draws no banners, also next to the helper Explorer (measured: a test
            // notification arrived and no window appeared), so BAKA's pop-up is the only one. Before, this
            // returned whenever Explorer ran, so no notification was ever shown. With Explorer as the real shell
            // (BAKA not chosen) Windows shows its own banner and BAKA stays quiet. Never during a game or with
            // "Do not disturb" on; the notification still goes to the list behind the bell.
            if (Paths.Preview || !ShellMode.Chosen) return;
            // alarms and calls keep Windows' own banner (see WindowsBanners): no second pop-up from BAKA
            if (WindowsBanners.Wanted && WindowsBanners.Keeps(n.AppId)) return;
            if (FocusMode.On) { FocusMode.Held(); return; } // Focus (also on by itself in games): counted for the summary
            if (App.GameRunning) return;
            if (open.Count >= 4) open[0].Dismiss(); // a burst (an app sending ten at once) keeps four on screen
            try { new NotificationPopup(n).Appear(); } catch (Exception e) { Log.Write("notification-popup-failed error=\"" + e.Message + "\""); }
        }

        NotificationPopup(NoteItem n) : base(16)
        {
            Title = "BAKA Notification"; Width = 360; SizeToContent = SizeToContent.Height; ShowActivated = false; Topmost = true;
            var sp = new StackPanel { Margin = new Thickness(14, 12, 14, 12) };
            var head = new StackPanel { Orientation = Orientation.Horizontal };
            head.Children.Add(Ui.Glyph(0xE7E7, 13, Theme.Accent));
            var app = Ui.Text(string.IsNullOrEmpty(n.App) ? "Notification" : n.App, 11, FontWeights.SemiBold, Theme.Muted); app.Margin = new Thickness(8, 0, 0, 0); app.VerticalAlignment = VerticalAlignment.Center; head.Children.Add(app);
            sp.Children.Add(head);
            if (!string.IsNullOrEmpty(n.Title)) { var t = Ui.Text(n.Title, 14, FontWeights.SemiBold); t.TextWrapping = TextWrapping.Wrap; t.Margin = new Thickness(0, 6, 0, 0); sp.Children.Add(t); }
            if (!string.IsNullOrEmpty(n.Body)) { var b = Ui.Muted(n.Body, 12); b.Margin = new Thickness(0, 3, 0, 0); b.MaxHeight = 80; sp.Children.Add(b); }
            Content = sp;
            if (n.Click != null) Frame.Cursor = System.Windows.Input.Cursors.Hand;
            Ui.OnClick(Frame, () => { try { n.Click?.Invoke(); } catch { } Dismiss(); });
            life = new DispatcherTimer { Interval = TimeSpan.FromSeconds(6) };
            life.Tick += (o, e) => Dismiss();
            Closed += (o, e) => { open.Remove(this); Reflow(); };
        }
        void Appear()
        {
            open.Add(this);
            Show();
            Reflow();
            life.Start();
            Ui.FadeIn(Frame, 180, 0.96, -12);
        }
        static void Reflow()
        {
            double top = TopBar.BarHeight + 10;
            for (int i = 0; i < open.Count; i++)
            {
                var w = open[i];
                w.Left = SystemParameters.PrimaryScreenWidth - w.Width - 12;
                w.Top = top; top += (w.ActualHeight > 0 ? w.ActualHeight : 80) + 8;
            }
        }
        bool dismissed;
        public void Dismiss() { if (dismissed) return; dismissed = true; life?.Stop(); open.Remove(this); try { Close(); } catch { } }
    }

    // The bell's flyout: the recent notifications, newest first, with a Clear button.
    class NotificationCenter : GlassPanel
    {
        static NotificationCenter current;
        static DateTime closedAt = DateTime.MinValue;
        public static bool IsOpen => current != null && current.IsVisible;
        public static void Toggle(Window anchor)
        {
            if (current != null && current.IsVisible) { current.Close(); return; }
            // a click right after the panel closed itself (it closes when it loses focus, which the click on
            // the bell causes) must not open it again at once
            if ((DateTime.Now - closedAt).TotalMilliseconds < 300) return;
            current = new NotificationCenter();
            current.Left = SystemParameters.PrimaryScreenWidth - current.Width - 10; current.Top = TopBar.BarHeight + 6;
            current.Show(); current.Activate();
        }
        NotificationCenter() : base(18)
        {
            Title = "BAKA Notifications"; Width = 360; SizeToContent = SizeToContent.Height; Topmost = true;
            bool closing = false;
            Closing += (o, e) => closing = true;
            Deactivated += (o, e) => { if (!SelfTest.Running && !closing) { closing = true; try { Close(); } catch { } } };
            Closed += (o, e) => { if (current == this) current = null; closedAt = DateTime.Now; };
            Build();
            Notifications.Changed += Build;
            Closed += (o, e) => Notifications.Changed -= Build;
            Ui.FadeIn(Frame, 170, 0.96, -12);
        }
        void Build()
        {
            var sp = new StackPanel { Margin = new Thickness(14) };
            var head = new Grid();
            head.Children.Add(Ui.Text("Notifications", 15, FontWeights.SemiBold));
            var clear = Ui.Button("Clear", () => { Notifications.Clear(); }, false, 9, new Thickness(10, 4, 10, 4)); clear.HorizontalAlignment = HorizontalAlignment.Right;
            head.Children.Add(clear); sp.Children.Add(head);
            // Focus: notifications still arrive here, but no pop-ups (it was "Do not disturb" before 12.27)
            bool dnd = FocusMode.On;
            var dndRow = new Grid { Margin = new Thickness(0, 8, 0, 6) };
            dndRow.ColumnDefinitions.Add(new ColumnDefinition()); dndRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var dndText = Ui.Text("Focus  ·  no pop-ups", 12, FontWeights.SemiBold, dnd ? Theme.Accent : Theme.Muted); dndText.VerticalAlignment = VerticalAlignment.Center;
            dndText.ToolTip = "Also tucks the dock away and pauses the video wallpaper (Settings > Focus & games). Ctrl+Alt+D";
            dndRow.Children.Add(dndText);
            var dndToggle = Ui.Toggle(dnd, on => { FocusMode.Set(on, "bell"); Build(); });
            Grid.SetColumn(dndToggle, 1); dndRow.Children.Add(dndToggle); sp.Children.Add(dndRow);
            if (Notifications.History.Count == 0)
            {
                var m = Ui.Muted(Notifications.Available ? "Nothing new." : "BAKA cannot read Windows' notifications on this PC.", 12); m.Margin = new Thickness(0, 6, 0, 2); sp.Children.Add(m);
            }
            foreach (var n in Notifications.History.Take(30))
            {
                var card = new StackPanel();
                var top = new Grid(); top.ColumnDefinitions.Add(new ColumnDefinition()); top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                top.Children.Add(Ui.Text(string.IsNullOrEmpty(n.App) ? "Notification" : n.App, 10.5, FontWeights.SemiBold, Theme.Muted));
                var when = Ui.Text(Ago(n.When), 10.5, null, Theme.Muted); Grid.SetColumn(when, 1); top.Children.Add(when);
                card.Children.Add(top);
                if (!string.IsNullOrEmpty(n.Title)) { var t = Ui.Text(n.Title, 13, FontWeights.SemiBold); t.TextWrapping = TextWrapping.Wrap; card.Children.Add(t); }
                if (!string.IsNullOrEmpty(n.Body)) { var b = Ui.Muted(n.Body, 11.5); b.MaxHeight = 64; card.Children.Add(b); }
                var c = Ui.Card(card);
                if (n.Click != null) { c.Cursor = System.Windows.Input.Cursors.Hand; c.ToolTip = "Open " + (string.IsNullOrEmpty(n.App) ? "the app" : n.App); var item = n; Ui.OnClick(c, () => { try { item.Click(); } catch { } Close(); }); }
                sp.Children.Add(c);
            }
            Content = Ui.Scroll(sp); MaxHeight = SystemParameters.PrimaryScreenHeight * 0.7;
        }
        static string Ago(DateTime t)
        {
            var d = DateTime.Now - t;
            if (d.TotalMinutes < 1) return "now";
            if (d.TotalHours < 1) return (int)d.TotalMinutes + " min ago";
            if (t.Date == DateTime.Today) return t.ToString("t");
            if (t.Date == DateTime.Today.AddDays(-1)) return "Yesterday " + t.ToString("t");
            return t.ToString("d MMM");
        }
    }
}
