using System;
using System.Collections.Generic;
using System.Data.OleDb;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

namespace Baka.Desktop
{
    // Launchpad (the Windows key): every installed app, and one search box for apps, Windows settings and
    // files. Typing filters instantly; Enter opens the first result; arrows move; Esc clears, then closes.
    class Launchpad : Window
    {
        static Launchpad current;
        public static bool IsOpen => current != null && current.IsVisible;
        IntPtr handle;
        TextBox search; TextBlock hint; Button clear; Border pill;
        WrapPanel grid; StackPanel results; ScrollViewer scroll;
        readonly List<FrameworkElement> focusable = new List<FrameworkElement>();
        int selected = -1;
        int queryVersion;

        // The Launchpad window is built once (in the background, shortly after the desktop starts) and then
        // only shown and hidden. Building it, a full-screen window with a tile for every app, took about
        // 0.6 s in the test VM, which is what a person felt on every Windows key press when it was rebuilt
        // each time. A new theme or accent builds it again.
        bool reallyClose; string themeKey;
        static string ThemeKey() => Theme.Current?.Name + "|" + Theme.AccentHex + "|" + Theme.Motion + "|" + (App.Settings == null ? "" : Json.Write(App.Settings.Appearance));
        public static void Toggle(bool focusSearch = false)
        {
            if (App.BakaHidden) return; // "Light" gaming: the Windows key opens the Launchpad, not Start
            // Win+S / Win+Q / the search widget: an open Launchpad focuses its search box instead of closing
            if (IsOpen && focusSearch) { try { current.Activate(); Native.Activate(new WindowInteropHelper(current).Handle); current.search.Focus(); current.search.SelectAll(); } catch { } return; }
            if (IsOpen) { current.Close(); return; }
            if (current != null && current.themeKey != ThemeKey()) { current.Dispose(); current = null; }
            if (current == null) current = new Launchpad();
            // a backstop for installs the folder watch could not see; the list is read in the background and
            // the Launchpad updates itself if anything changed
            if ((DateTime.Now - AppCatalog.Loaded).TotalSeconds > 90) AppCatalog.Refresh();
            current.Reset();
            current.Show(); current.Activate();
            // BAKA only listens to the keyboard, so Windows does not count it as the app that got the key
            // press and may refuse to bring the Launchpad to the front; force it, so typing goes to the search box
            try { Native.Activate(new WindowInteropHelper(current).Handle); } catch { }
            current.search.Focus();
        }
        // Builds the hidden Launchpad ahead of the first Windows key press.
        public static void Prepare()
        {
            if (current != null || App.GameRunning) return;
            current = new Launchpad();
            var h = new WindowInteropHelper(current); h.EnsureHandle();
            Log.Write("launchpad-prepared apps=" + AppCatalog.Apps.Count);
        }
        void Dispose() { reallyClose = true; try { Close(); } catch { } }
        bool stale;
        void Reset()
        {
            if (!string.IsNullOrEmpty(search.Text)) search.Text = ""; else if (grid.Visibility != Visibility.Visible || stale) ShowAll();
            if (selected >= 0 && selected < focusable.Count) ((Border)focusable[selected]).Background = Brushes.Transparent;
            selected = -1; scroll.ScrollToTop();
            Ui.FadeIn((UIElement)Content, 150, 0.95); // zooms in a little, like a launcher opening
            // the first rows of apps rise in one after another (desktop profile only; ~0.4 s in total)
            if (Theme.Motion && grid.Visibility == Visibility.Visible)
                for (int i = 0; i < Math.Min(28, grid.Children.Count); i++) Ui.FadeIn(grid.Children[i], 170, 0.88, 10, 40 + i * 11);
        }
        public static void HideIfOpen() { if (IsOpen) current.Close(); }
        public static Launchpad Current => current;

        Launchpad()
        {
            WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize; ShowInTaskbar = false; Topmost = true; Title = "BAKA Launchpad";
            Background = Brushes.Transparent; FontFamily = Ui.Font; UseLayoutRounding = true;
            var area = System.Windows.Forms.Screen.PrimaryScreen.Bounds;
            Left = 0; Top = 0; Width = SystemParameters.PrimaryScreenWidth; Height = SystemParameters.PrimaryScreenHeight;
            SourceInitialized += (o, e) =>
            {
                handle = new WindowInteropHelper(this).Handle;
                HwndSource.FromHwnd(handle).CompositionTarget.BackgroundColor = Colors.Transparent;
                int none = 1; Native.DwmSetWindowAttribute(handle, 33, ref none, 4);
                int kind = Theme.Current.Backdrop == "Opaque" ? 1 : 3;
                bool ok = Native.DwmSetWindowAttribute(handle, 38, ref kind, 4) == 0 && kind != 1;
                ((Grid)Content).Background = Theme.B(Theme.Current.Canvas, (byte)(ok ? 175 : 250));
            };
            Build();
            themeKey = ThemeKey();
            Deactivated += (o, e) => { if (!SelfTest.Running && IsVisible) Close(); };
            PreviewKeyDown += OnKey;
            Closed += (o, e) => { if (current == this) current = null; };
            // Closing only hides it; it is really closed for a new theme, a game or when BAKA exits.
            Closing += (o, e) =>
            {
                if (SelfTest.Running) Log.Write("launchpad-closing stack=\"" + Environment.StackTrace.Replace("\r", "").Replace("\n", " | ") + "\"");
                if (!reallyClose && !Dispatcher.HasShutdownStarted && Application.Current != null) { e.Cancel = true; Hide(); }
            };
            AppCatalog.Updated += OnAppsUpdated;
            Closed += (o, e) => AppCatalog.Updated -= OnAppsUpdated;
            Log.Write("launchpad-built apps=" + AppCatalog.Apps.Count);
        }
        // A hidden Launchpad is redrawn when it is next opened; an open one at once (and a search runs again).
        void OnAppsUpdated()
        {
            if (!IsVisible) { stale = true; return; }
            if (string.IsNullOrEmpty(search.Text)) ShowAll(); else Query(search.Text);
        }

        void Build()
        {
            var root = new Grid();
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition());
            root.MouseLeftButtonDown += (o, e) => { if (e.OriginalSource == root || e.OriginalSource == scroll) Close(); };

            pill = new Border { Width = 560, Height = 48, CornerRadius = new CornerRadius(24), Margin = new Thickness(0, 54, 0, 22), HorizontalAlignment = HorizontalAlignment.Center, Background = Theme.B(Theme.Current.SurfaceAlt, 235), BorderBrush = Theme.Border, BorderThickness = new Thickness(1.4) };
            var pg = new Grid();
            pg.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(50) }); pg.ColumnDefinitions.Add(new ColumnDefinition()); pg.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(46) });
            pg.Children.Add(Ui.Glyph(0xE721, 16, Theme.Muted));
            hint = Ui.Text("Search apps, settings and files", 15.5, null, Theme.Muted); hint.VerticalAlignment = VerticalAlignment.Center; hint.IsHitTestVisible = false; Grid.SetColumn(hint, 1); pg.Children.Add(hint);
            search = new TextBox { FontSize = 15.5, Background = Brushes.Transparent, BorderThickness = new Thickness(0), VerticalAlignment = VerticalAlignment.Center, Padding = new Thickness(0) };
            search.Template = (ControlTemplate)System.Windows.Markup.XamlReader.Parse("<ControlTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' TargetType='TextBox'><ScrollViewer x:Name='PART_ContentHost' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'/></ControlTemplate>");
            System.Windows.Automation.AutomationProperties.SetName(search, "Search");
            Grid.SetColumn(search, 1); pg.Children.Add(search);
            clear = Ui.Icon(0xE711, "Clear search", () => { search.Clear(); search.Focus(); }, 28, 11); clear.Visibility = Visibility.Collapsed; Grid.SetColumn(clear, 2); pg.Children.Add(clear);
            pill.Child = pg;
            search.GotFocus += (o, e) => pill.BorderBrush = Theme.Accent; search.LostFocus += (o, e) => pill.BorderBrush = Theme.Border;
            search.TextChanged += (o, e) => { bool empty = string.IsNullOrEmpty(search.Text); hint.Visibility = empty ? Visibility.Visible : Visibility.Collapsed; clear.Visibility = empty ? Visibility.Collapsed : Visibility.Visible; Query(search.Text); };
            root.Children.Add(pill);
            var close = Ui.Icon(0xE711, "Close (Esc)", Close, 38, 13); close.HorizontalAlignment = HorizontalAlignment.Right; close.VerticalAlignment = VerticalAlignment.Top; close.Margin = new Thickness(0, 58, 48, 0);
            root.Children.Add(close);

            grid = new WrapPanel { HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(60, 0, 60, 40), MaxWidth = 1500 };
            results = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, Width = 760, Margin = new Thickness(0, 0, 0, 40), Visibility = Visibility.Collapsed };
            var host = new Grid(); host.Children.Add(grid); host.Children.Add(results);
            scroll = Ui.Scroll(host); Grid.SetRow(scroll, 1);
            root.Children.Add(scroll);
            Content = root;
            ShowAll();
        }

        void ShowAll()
        {
            stale = false;
            grid.Children.Clear(); focusable.Clear(); selected = -1;
            results.Visibility = Visibility.Collapsed; grid.Visibility = Visibility.Visible;
            if (AppCatalog.Apps.Count == 0) { var t = Ui.Text("Loading apps…", 14, null, Theme.Muted); t.Margin = new Thickness(0, 40, 0, 0); grid.Children.Add(t); return; }
            hint.Text = "Search " + AppCatalog.Apps.Count + " apps, settings and files";
            foreach (var app in AppCatalog.Apps) { var tile = AppTile(app); grid.Children.Add(tile); focusable.Add(tile); }
        }
        FrameworkElement AppTile(AppRef app)
        {
            var sp = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Top };
            var img = new Image { Source = Icons.For(app), Width = 56, Height = 56, Margin = new Thickness(0, 8, 0, 6) }; RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality);
            sp.Children.Add(img);
            var label = Ui.Text(app.Name, 11.5); label.TextAlignment = TextAlignment.Center; label.TextWrapping = TextWrapping.Wrap; label.MaxHeight = 32; label.Width = 100;
            sp.Children.Add(label);
            var b = new Border { Width = 112, Height = 112, Margin = new Thickness(4), CornerRadius = new CornerRadius(16), Child = sp, Background = Brushes.Transparent, Cursor = Cursors.Hand, ToolTip = app.Name, Tag = app };
            b.MouseEnter += (o, e) => b.Background = Theme.Hover; b.MouseLeave += (o, e) => { if (focusable.IndexOf(b) != selected) b.Background = Brushes.Transparent; };
            Clickable(b, () => Run(b));
            b.MouseRightButtonUp += (o, e) => { e.Handled = true; AppMenu(b, app); };
            System.Windows.Automation.AutomationProperties.SetName(b, app.Name);
            return b;
        }
        // A tile runs only when the press also started on it. The Launchpad opens full screen under the mouse,
        // so a button release left over from the click that opened it (or from another window) must not launch
        // whatever app happens to be under the cursor. Found by the self-test: a stray release closed the
        // Launchpad and started an app.
        static void Clickable(FrameworkElement b, Action run) => Ui.OnClick(b, run);
        void AppMenu(FrameworkElement anchor, AppRef app)
        {
            bool pinned = Dock.IsPinned(app);
            Ui.ShowMenu(anchor,
                Ui.Item("Open", 0xE8A7, () => { Close(); AppCatalog.Launch(app); }),
                Ui.Item("Run as administrator", 0xE7EF, () => { Close(); AppCatalog.Launch(app, true); }, null, !string.IsNullOrEmpty(app.Exe)),
                Ui.Item(pinned ? "Remove from dock" : "Keep in dock", pinned ? 0xE77A : 0xE718, () => { if (pinned) Dock.Unpin(app); else Dock.Pin(app); }),
                Ui.Item("Open file location", 0xE838, () => { Close(); AppCatalog.OpenLocation(app); }, null, !string.IsNullOrEmpty(app.Exe) && File.Exists(app.Exe)),
                "-",
                Ui.Item("Uninstall…", 0xE74D, () => { Close(); Launcher.Run("ms-settings:appsfeatures", () => System.Diagnostics.Process.Start("ms-settings:appsfeatures")); }));
        }

        // ---- search ----
        void Query(string text)
        {
            int version = ++queryVersion;
            if (string.IsNullOrWhiteSpace(text)) { ShowAll(); return; }
            grid.Visibility = Visibility.Collapsed; results.Visibility = Visibility.Visible;
            results.Children.Clear(); focusable.Clear(); selected = -1;
            string lq = text.Trim().ToLowerInvariant();
            var apps = AppCatalog.Apps.Select(a => (a, s: AppCatalog.ScoreApp(a, text))).Where(x => x.s > 0).OrderByDescending(x => x.s).ThenBy(x => x.a.Name).Take(12).ToList();
            var pages = SettingsPages.All.Select(p => (p, s: Math.Max(AppCatalog.Score(p.name, text), p.words.Split(' ').Any(w => w == lq) ? 850 : p.words.Split(' ').Any(w => w.StartsWith(lq)) ? 500 : 0))).Where(x => x.s > 0).OrderByDescending(x => x.s).Take(5).ToList();
            var baka = BakaActions().Select(x => (x, s: AppCatalog.Score(x.name, text))).Where(x => x.s > 0).OrderByDescending(x => x.s).Take(3).ToList();
            // the section with the best match comes first, so "wifi" opens Wi-Fi settings and "steam" opens Steam
            var sections = new List<(int best, Action draw)>();
            if (apps.Count > 0) sections.Add((apps[0].s, () => { Section("Apps"); foreach (var (a, _) in apps) Result(Icons.For(a), a.Name, AppKind(a), () => AppCatalog.Launch(a), b => AppMenu(b, a)); }));
            if (baka.Count > 0) sections.Add((baka[0].s - 1, () => { Section("BAKA"); foreach (var (x, _) in baka) Result(Icons.ForId(x.icon), x.name, x.detail, x.run, null); }));
            if (pages.Count > 0) sections.Add((pages[0].s - 2, () => { Section("Settings"); foreach (var (p, _) in pages) { var uri = p.uri; Result(Icons.ForId("settings"), p.name, "Windows Settings", () => Launcher.Run(uri, () => System.Diagnostics.Process.Start(uri)), null); } }));
            foreach (var s in sections.OrderByDescending(s => s.best)) s.draw();
            if (apps.Count + pages.Count + baka.Count == 0) { var none = Ui.Text("No apps or settings match \"" + text + "\". Looking in your files…", 13, null, Theme.Muted); none.Margin = new Thickness(8, 6, 0, 10); results.Children.Add(none); }
            if (focusable.Count > 0) Select(0);
            string q = text.Trim();
            if (q.Length >= 2) Task.Run(() => FileSearch(q)).ContinueWith(t => { if (version == queryVersion && t.Result.Count > 0) Dispatcher.BeginInvoke(new Action(() => { if (version != queryVersion) return; Section("Files"); foreach (var f in t.Result) Result(Icons.ForFile(f, 48), Path.GetFileName(f), Path.GetDirectoryName(f), () => Files.OpenItem(f), b => Ui.ShowMenu(b, Ui.Item("Open file location", 0xE838, () => { Close(); Files.Open(Path.GetDirectoryName(f), f); }))); if (selected < 0) Select(0); })); });
        }
        static string AppKind(AppRef a) => a.AppId.Contains("!") ? "App" : a.AppId.StartsWith("http", StringComparison.OrdinalIgnoreCase) ? "Web link" : "Program";
        static IEnumerable<(string name, string detail, string icon, Action run)> BakaActions() => new (string, string, string, Action)[]
        {
            ("BAKA Settings", "Theme, wallpaper, dock, widgets", "baka-settings", () => SettingsWindow.Open()), ("BAKA Files", "Your files and drives", "baka-files", () => Files.Open(null)),
            ("BAKA Arena", "Gaming profiles, games and performance", "baka-arena", Arena.Open), ("Lock", "Lock this PC", "secpol", () => Native.LockWorkStation()),
            ("Restart", "Restart Windows", "run", Power.Restart), ("Shut down", "Turn off the PC", "run", Power.Shutdown), ("Sleep", "Put the PC to sleep", "clock", Power.Sleep),
        };
        void Section(string title) { var t = Ui.Text(title.ToUpperInvariant(), 11, FontWeights.Bold, Theme.Muted); t.Margin = new Thickness(10, results.Children.Count == 0 ? 0 : 14, 0, 6); results.Children.Add(t); }
        void Result(ImageSource icon, string name, string detail, Action run, Action<FrameworkElement> menu)
        {
            var g = new Grid(); g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(48) }); g.ColumnDefinitions.Add(new ColumnDefinition());
            var img = new Image { Source = icon, Width = 36, Height = 36 }; RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality); g.Children.Add(img);
            var sp = new StackPanel { VerticalAlignment = VerticalAlignment.Center }; Grid.SetColumn(sp, 1);
            sp.Children.Add(Ui.Text(name, 14, FontWeights.SemiBold)); var d = Ui.Text(detail ?? "", 11.5, null, Theme.Muted); sp.Children.Add(d);
            g.Children.Add(sp);
            var b = new Border { Child = g, Padding = new Thickness(10, 7, 10, 7), CornerRadius = new CornerRadius(12), Background = Brushes.Transparent, Cursor = Cursors.Hand, Tag = run };
            b.MouseEnter += (o, e) => Select(focusable.IndexOf(b));
            Clickable(b, () => Run(b));
            if (menu != null) b.MouseRightButtonUp += (o, e) => { e.Handled = true; menu(b); };
            results.Children.Add(b); focusable.Add(b);
        }
        void Select(int i)
        {
            if (focusable.Count == 0) return;
            i = Math.Max(0, Math.Min(focusable.Count - 1, i));
            if (selected >= 0 && selected < focusable.Count) ((Border)focusable[selected]).Background = Brushes.Transparent;
            selected = i;
            var b = (Border)focusable[i]; b.Background = Theme.B(Theme.AccentHex, 46);
            b.BringIntoView();
        }
        void Run(FrameworkElement e)
        {
            Close();
            if (e.Tag is AppRef a) AppCatalog.Launch(a);
            else if (e.Tag is Action act) { try { act(); } catch (Exception ex) { Log.Write("launchpad-action-failed error=\"" + ex.Message + "\""); } }
        }
        void OnKey(object sender, KeyEventArgs e)
        {
            int perRow = grid.Visibility == Visibility.Visible ? Math.Max(1, (int)(grid.ActualWidth / 120)) : 1;
            switch (e.Key)
            {
                case Key.Escape: if (!string.IsNullOrEmpty(search.Text)) search.Clear(); else Close(); e.Handled = true; break;
                case Key.Enter: if (selected < 0 && focusable.Count > 0) Select(0); if (selected >= 0) Run(focusable[selected]); e.Handled = true; break;
                case Key.Down: Select(selected < 0 ? 0 : selected + perRow); e.Handled = true; break;
                case Key.Up: Select(selected - perRow); e.Handled = true; break;
                case Key.Right: if (grid.Visibility == Visibility.Visible && string.IsNullOrEmpty(search.Text)) { Select(selected + 1); e.Handled = true; } break;
                case Key.Left: if (grid.Visibility == Visibility.Visible && string.IsNullOrEmpty(search.Text)) { Select(selected - 1); e.Handled = true; } break;
            }
        }

        // Files through the Windows Search index (instant, includes file contents), limited to the user's
        // own folders. Falls back to a quick name scan when the index service is off.
        static List<string> FileSearch(string q)
        {
            var found = new List<string>();
            string esc = q.Replace("'", "''");
            try
            {
                using (var c = new OleDbConnection("Provider=Search.CollatorDSO;Extended Properties='Application=Windows';"))
                {
                    c.Open();
                    string scope = "file:" + Environment.GetFolderPath(Environment.SpecialFolder.UserProfile).Replace('\\', '/').Replace("'", "''");
                    var cmd = new OleDbCommand("SELECT TOP 8 System.ItemPathDisplay FROM SYSTEMINDEX WHERE SCOPE='" + scope + "' AND System.FileName LIKE '%" + esc + "%' ORDER BY System.DateModified DESC", c);
                    using (var r = cmd.ExecuteReader()) while (r.Read()) if (!r.IsDBNull(0)) found.Add(r.GetString(0));
                }
            }
            catch
            {
                try
                {
                    foreach (var root in new[] { Environment.SpecialFolder.Desktop, Environment.SpecialFolder.MyDocuments }.Select(Environment.GetFolderPath).Concat(new[] { Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads") }))
                    {
                        if (!Directory.Exists(root)) continue;
                        foreach (var f in Directory.EnumerateFileSystemEntries(root).Where(f => Path.GetFileName(f).IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0).Take(8 - found.Count)) found.Add(f);
                        if (found.Count >= 8) break;
                    }
                }
                catch { }
            }
            return found;
        }

        public void TypeForTest(string text) => search.Text = text;
        public int ResultCount => focusable.Count;
        public string FirstResultName() => focusable.Count == 0 ? null : focusable[0].Tag is AppRef a ? a.Name : ((focusable[0] as Border)?.Child as Grid)?.Children.OfType<StackPanel>().FirstOrDefault()?.Children.OfType<TextBlock>().FirstOrDefault()?.Text;
        public bool HintVisible => hint.Visibility == Visibility.Visible;
        public bool ClearVisible => clear.Visibility == Visibility.Visible;
    }
}
