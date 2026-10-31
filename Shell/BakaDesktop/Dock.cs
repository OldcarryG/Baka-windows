using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace Baka.Desktop
{
    // The dock: Launchpad, pinned apps, open windows of other apps, and the BAKA tools. It replaces the
    // Windows taskbar: click opens or switches to an app, click again minimizes it, right-click has the rest.
    class Dock : GlassPanel
    {
        StackPanel panel;
        readonly List<(Border tile, AppRef app, string pinId)> tiles = new List<(Border, AppRef, string)>();
        string signature = "";
        bool Vertical => Json.Str(App.Settings.Dock, "alignment", "Left") != "Center";
        string Edge => Json.Str(App.Settings.Dock, "alignment", "Left");
        double IconSize => Math.Max(32, Math.Min(72, Json.Int(App.Settings.Dock, "iconSize", 40)));

        public Dock() : base(22)
        {
            Title = "BAKA Dock"; Topmost = true; ShowActivated = false;
            Build();
            Theme.Changed += () => { Paint(); Build(); };
            App.WindowsChanged += () => Refresh(false);
            SizeChanged += (o, e) => Place();
            MouseLeave += (o, e) => { foreach (var t in tiles) Magnify(t.tile, 1); };
            MouseMove += OnMouseMove;
            SourceInitialized += (o, e) =>
            {
                Native.SetWindowLongPtr(Handle, Native.GWL_EXSTYLE, new IntPtr(Native.ExStyle(Handle) | Native.WS_EX_NOACTIVATE));
                System.Windows.Interop.HwndSource.FromHwnd(Handle)?.AddHook(AppBars.Hook); // Explorer: a fullscreen window opened or closed
            };
            // checks the screen edge every 120 ms, so a hidden dock is back almost as soon as the pointer arrives
            autoHideTimer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(120) };
            autoHideTimer.Tick += (o, e) => AutoHideTick();
            autoHideTimer.Start();
        }

        public void Build()
        {
            tiles.Clear();
            panel = new StackPanel { Orientation = Vertical ? Orientation.Vertical : Orientation.Horizontal, Margin = new Thickness(6) };
            Content = panel;
            AddTool(0xE71D, "Apps (Win)", "launchpad", () => Launchpad.Toggle());
            foreach (var p in App.Settings.Pinned.Select(Json.Obj).Where(p => p != null)) AddPinned(p);
            Refresh(true);
        }
        // Background: the theme's glass, or the colour / picture / video chosen in Settings > Appearance.
        public override void Paint() { base.Paint(); var b = Surfaces.Background("dock"); if (b != null) Frame.Background = b; }
        // A thin, faint line with generous spacing: one cohesive dock, not a stack of boxes. R15 drew a solid
        // divider between every section, which read as "many black bars".
        void Separator() { var d = new Border { Background = Theme.B(Theme.Current.Border, 55), CornerRadius = new CornerRadius(1), Margin = Vertical ? new Thickness(16, 7, 16, 7) : new Thickness(7, 16, 7, 16) }; if (Vertical) d.Height = 1; else d.Width = 1; panel.Children.Add(d); }

        public const string SettingsAppId = "windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel";
        AppRef PinRef(Dictionary<string, object> p)
        {
            string kind = Json.Str(p, "kind"), target = Paths.Expand(Json.Str(p, "target"));
            if (kind == "Baka") return new AppRef { Name = target == "files" ? "BAKA Files" : Json.Str(p, "name") };
            var app = new AppRef { Name = Json.Str(p, "name"), Exe = kind == "Executable" ? target : "", AppId = kind == "AppId" ? target : "", Process = Json.Str(p, "processName") };
            // Windows Settings is pinned as a link (ms-settings:); its window is the Settings app.
            if (kind == "Uri" && target.StartsWith("ms-settings", StringComparison.OrdinalIgnoreCase)) app.MatchId = SettingsAppId;
            // A program pinned through its Start menu shortcut: match its windows by the program it starts.
            if (kind == "AppId" && string.IsNullOrEmpty(app.Process)) app.Process = ProcessOfShortcut(target);
            return app;
        }
        static readonly Dictionary<string, string> shortcutProcess = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        public static string ProcessOfShortcut(string appId)
        {
            if (string.IsNullOrEmpty(appId) || appId.Contains("!")) return "";
            if (shortcutProcess.TryGetValue(appId, out var known)) return known;
            string exe = "";
            try
            {
                var hit = AppCatalog.Apps.FirstOrDefault(a => string.Equals(a.AppId, appId, StringComparison.OrdinalIgnoreCase));
                // entries listed by an app id (Discord, Kiro): the program Windows says the entry starts
                string path = !string.IsNullOrEmpty(hit?.Exe) ? hit.Exe : hit?.Target ?? "";
                if (path.EndsWith(".lnk", StringComparison.OrdinalIgnoreCase)) path = AppCatalog.ShortcutTarget(path) ?? "";
                if (path.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) exe = Path.GetFileNameWithoutExtension(path);
            }
            catch { }
            if (exe.Length > 0 || AppCatalog.Apps.Count > 0) shortcutProcess[appId] = exe;
            return exe;
        }
        void AddPinned(Dictionary<string, object> p)
        {
            var app = PinRef(p);
            ImageSource icon = null;
            string custom = Paths.Expand(Json.Str(p, "iconPath"));
            if (!string.IsNullOrEmpty(custom) && File.Exists(custom)) try { icon = new System.Windows.Media.Imaging.BitmapImage(new Uri(custom)); } catch { }
            if (icon == null && Json.Str(p, "id") == "settings") icon = Icons.ForId("settings", 96, true);
            if (icon == null) icon = Icons.For(app, 96, true);
            var tile = Tile(icon, Json.Str(p, "name"));
            Ui.OnClick(tile, () => Click(app, p));
            tile.MouseRightButtonUp += (o, e) => { e.Handled = true; PinMenu(tile, app, p); };
            tiles.Add((tile, app, Json.Str(p, "id")));
            panel.Children.Add(tile);
        }
        void AddTool(int glyph, string tip, string id, Action click)
        {
            // Same transparent, icon-only look as app tiles, so the BAKA tools (Launchpad, Arena, Control
            // Center, Settings) sit in the dock as one row instead of standing out as boxed buttons.
            var g = Ui.Glyph(glyph, IconSize * 0.42);
            var tile = new Border { Width = IconSize, Height = IconSize, CornerRadius = new CornerRadius(IconSize * 0.28), Background = Brushes.Transparent, Child = g, ToolTip = tip, Cursor = Cursors.Hand, Margin = Gap(), RenderTransformOrigin = Origin() };
            tile.MouseEnter += (o, e) => tile.Background = Theme.Hover; tile.MouseLeave += (o, e) => tile.Background = Brushes.Transparent;
            Ui.OnClick(tile, () => { Bounce(tile); click(); });
            System.Windows.Automation.AutomationProperties.SetName(tile, tip);
            tiles.Add((tile, null, id));
            panel.Children.Add(tile);
        }
        Thickness Gap() { double s = Json.Int(App.Settings.Dock, "spacing", 6) / 2.0; return Vertical ? new Thickness(0, s, 0, s) : new Thickness(s, 0, s, 0); }
        // Icons grow from their centre and only as far as the dock's padding, so a magnified icon is never cut
        // off at the dock's edge (R15 grew them outwards by 26% and the window clipped them).
        Point Origin() => new Point(0.5, 0.5);
        const double MaxMagnify = 1.16;
        Border Tile(ImageSource icon, string tip)
        {
            var grid = new Grid();
            var img = new Image { Source = icon, Width = IconSize, Height = IconSize }; RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality);
            grid.Children.Add(img);
            var dot = new Border { Width = 5, Height = 5, CornerRadius = new CornerRadius(2.5), Background = Theme.Accent, Visibility = Visibility.Hidden };
            if (Edge == "Left") { dot.HorizontalAlignment = HorizontalAlignment.Left; dot.VerticalAlignment = VerticalAlignment.Center; dot.Margin = new Thickness(-7, 0, 0, 0); }
            else if (Edge == "Right") { dot.HorizontalAlignment = HorizontalAlignment.Right; dot.VerticalAlignment = VerticalAlignment.Center; dot.Margin = new Thickness(0, 0, -7, 0); }
            else { dot.HorizontalAlignment = HorizontalAlignment.Center; dot.VerticalAlignment = VerticalAlignment.Bottom; dot.Margin = new Thickness(0, 0, 0, -7); }
            grid.Children.Add(dot);
            var tile = new Border { Child = grid, ToolTip = tip, Cursor = Cursors.Hand, Margin = Gap(), Background = Brushes.Transparent, RenderTransformOrigin = Origin(), Tag = dot };
            tile.MouseEnter += (o, e) => tile.Background = Theme.Hover; tile.MouseLeave += (o, e) => tile.Background = Brushes.Transparent;
            System.Windows.Automation.AutomationProperties.SetName(tile, tip);
            return tile;
        }

        // ---- open windows ----
        Dictionary<string, List<OpenWindow>> groups = new Dictionary<string, List<OpenWindow>>();
        readonly HashSet<string> shownOpen = new HashSet<string>(); // open-app icons already shown ("" = the dock has been drawn once)
        static string GroupKey(OpenWindow w) => !string.IsNullOrEmpty(w.AppId) ? w.AppId.ToLowerInvariant() : Path.GetFileName(w.Exe).ToLowerInvariant();
        // Which open windows belong to a pinned app. Each window goes to the pin that matches it best, so an
        // app pinned from the Launchpad no longer gets a second "open" icon next to its pin when it starts:
        //  100 same app id   95 Windows Settings link   90 same program   80 the program its shortcut starts
        //   60 same app name   40 a helper program inside the pinned program's own folder (Steam's window
        //      belongs to steamwebhelper.exe, not Steam.exe)
        static int Score(AppRef pin, OpenWindow w)
        {
            if (pin == null || pin.Name == "BAKA Files") return 0;
            if (!string.IsNullOrEmpty(w.AppId))
            {
                if (!string.IsNullOrEmpty(pin.AppId) && string.Equals(pin.AppId, w.AppId, StringComparison.OrdinalIgnoreCase)) return 100;
                if (!string.IsNullOrEmpty(pin.MatchId) && string.Equals(pin.MatchId, w.AppId, StringComparison.OrdinalIgnoreCase)) return 95;
            }
            string exe = Path.GetFileNameWithoutExtension(w.Exe ?? "");
            if (exe.Length == 0 || exe.Equals("ApplicationFrameHost", StringComparison.OrdinalIgnoreCase)) return 0;
            if (!string.IsNullOrEmpty(pin.Exe) && Path.GetFileNameWithoutExtension(pin.Exe).Equals(exe, StringComparison.OrdinalIgnoreCase)) return 90;
            if (!string.IsNullOrEmpty(pin.Process) && pin.Process.Equals(exe, StringComparison.OrdinalIgnoreCase)) return 80;
            if (!string.IsNullOrEmpty(pin.Name) && string.Equals(NameOf(w), pin.Name, StringComparison.OrdinalIgnoreCase)) return 60;
            if (InOwnFolder(pin.Exe, w.Exe)) return 40;
            return 0;
        }
        bool Belongs(AppRef pin, OpenWindow w)
        {
            int s = Score(pin, w);
            if (s == 0) return false;
            foreach (var t in tiles)
                if (t.app != null && !ReferenceEquals(t.app, pin) && t.pinId != "open" && t.pinId != "tool" && Score(t.app, w) > s) return false;
            return true;
        }
        static readonly Dictionary<string, string> names = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        static string NameOf(OpenWindow w)
        {
            string key = (w.AppId ?? "") + "|" + (w.Exe ?? "");
            if (!names.TryGetValue(key, out var n)) { try { n = AppName(w); } catch { n = ""; } names[key] = n ?? ""; }
            return n;
        }
        // A program in its own install folder (not Windows, not a shared root like Program Files or AppData).
        static readonly string[] SharedRoots = new[]
        {
            Environment.SpecialFolder.ProgramFiles, Environment.SpecialFolder.ProgramFilesX86, Environment.SpecialFolder.LocalApplicationData, Environment.SpecialFolder.ApplicationData,
            Environment.SpecialFolder.CommonApplicationData, Environment.SpecialFolder.UserProfile, Environment.SpecialFolder.Desktop
        }.Select(Environment.GetFolderPath).Where(p => !string.IsNullOrEmpty(p))
         .Concat(new[] { Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs"), Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads") })
         .Select(p => p.TrimEnd('\\')).ToArray();
        static bool InOwnFolder(string pinExe, string windowExe)
        {
            if (string.IsNullOrEmpty(pinExe) || string.IsNullOrEmpty(windowExe) || !pinExe.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) return false;
            string dir;
            try { dir = Path.GetDirectoryName(Paths.Expand(pinExe))?.TrimEnd('\\'); } catch { return false; }
            if (string.IsNullOrEmpty(dir) || dir.Length <= 3) return false;
            string win = Environment.GetFolderPath(Environment.SpecialFolder.Windows).TrimEnd('\\');
            if (dir.StartsWith(win, StringComparison.OrdinalIgnoreCase)) return false;
            if (SharedRoots.Any(r => string.Equals(r, dir, StringComparison.OrdinalIgnoreCase))) return false;
            return windowExe.StartsWith(dir + "\\", StringComparison.OrdinalIgnoreCase);
        }
        public void Refresh(bool force)
        {
            if (!Json.Bool(App.Settings.Taskbar, "showRunningApps", true)) { if (force) Place(); return; }
            var open = Windows.List();
            groups = open.GroupBy(GroupKey).ToDictionary(g => g.Key, g => g.ToList());
            // Only the pinned apps decide which open apps need their own icon. R15 also compared against the
            // open-app icons of the previous refresh, so every running app counted as "pinned" and vanished,
            // then came back on the next refresh: the dock's open apps blinked in and out every 1.5 s.
            var pinned = tiles.Where(t => t.pinId != "open" && t.pinId != "tool" && t.app != null).ToList();
            var unpinned = groups.Where(g => !pinned.Any(t => g.Value.Any(w => Belongs(t.app, w)))).Select(g => g.Key).OrderBy(k => k).ToList();
            string sig = string.Join("|", unpinned.Select(k => k + groups[k].Count)) + "#" + (Files.Last != null) + "#" + string.Join("|", pinned.Select(t => t.pinId + (open.Any(w => Belongs(t.app, w)) ? "*" : "")));
            if (!force && sig == signature) return;
            signature = sig;
            // running indicators on pinned apps (BAKA Files: one of its own windows is open)
            foreach (var t in tiles) if (t.tile.Tag is Border dot) dot.Visibility = t.app != null && (open.Any(w => Belongs(t.app, w)) || (t.app.Name == "BAKA Files" && Files.Last != null)) ? Visibility.Visible : Visibility.Hidden;
            // rebuild the open-apps section (after the Launchpad + pinned apps) and the tools
            int pinnedEnd = 1 + App.Settings.Pinned.Count;
            while (panel.Children.Count > pinnedEnd) panel.Children.RemoveAt(panel.Children.Count - 1);
            tiles.RemoveAll(t => t.pinId == "open" || t.pinId == "tool");
            if (unpinned.Count > 0) Separator();
            foreach (var key in unpinned)
            {
                var ws = groups[key]; var w = ws[0];
                var app = new AppRef { Name = AppName(w), Exe = w.Exe, AppId = w.AppId };
                var tile = Tile(Icons.For(app, 96, true), app.Name + (ws.Count > 1 ? " (" + ws.Count + " windows)" : ""));
                ((Border)tile.Tag).Visibility = Visibility.Visible;
                Ui.OnClick(tile, () => { var list = groups.TryGetValue(key, out var l) ? l : ws; if (list.Count == 1) Windows.Toggle(list[0]); else WindowMenu(tile, list); });
                tile.MouseRightButtonUp += (o, e) => { e.Handled = true; OpenMenu(tile, app, groups.TryGetValue(key, out var l) ? l : ws); };
                tiles.Add((tile, app, "open"));
                panel.Children.Add(tile);
                // an app that just opened pops into the dock (desktop profile only, see Theme.Motion)
                if (shownOpen.Count > 0 && !shownOpen.Contains(key)) Ui.FadeIn(tile, 260, 0.4);
            }
            shownOpen.Clear(); foreach (var k in unpinned) shownOpen.Add(k); shownOpen.Add("");
            Separator();
            foreach (var (g, tip, act) in new (int, string, Action)[] { (0xE7FC, "BAKA Arena", Arena.Open), (0xE9E9, "Control Center", () => ControlCenter.Toggle(this)), (0xE713, "BAKA Settings", () => SettingsWindow.Open()) })
            {
                AddTool(g, tip, "tool", act);
            }
            Dispatcher.BeginInvoke(new Action(Place), System.Windows.Threading.DispatcherPriority.Loaded);
        }
        // Win+1..9: the n-th app in the dock (pinned first, then open apps), like the Windows taskbar.
        public void OpenNumber(int n)
        {
            var apps = tiles.Where(t => t.app != null && t.pinId != "tool").ToList();
            if (n < 1 || n > apps.Count) return;
            var t = apps[n - 1];
            Bounce(t.tile);
            if (t.pinId == "open")
            {
                var ws = groups.Values.SelectMany(l => l).Where(w => (!string.IsNullOrEmpty(t.app.AppId) && string.Equals(w.AppId, t.app.AppId, StringComparison.OrdinalIgnoreCase)) || (!string.IsNullOrEmpty(t.app.Exe) && string.Equals(w.Exe, t.app.Exe, StringComparison.OrdinalIgnoreCase))).ToList();
                if (ws.Count > 0) Windows.Toggle(ws[0]);
            }
            else
            {
                var pin = App.Settings.Pinned.Select(Json.Obj).FirstOrDefault(p => p != null && Json.Str(p, "id") == t.pinId);
                if (pin != null) Click(t.app, pin);
            }
            Log.Write("dock-number n=" + n);
        }
        // Where a window's minimize animation should go: its app's dock icon, or the dock when it has none.
        public bool TargetFor(IntPtr hwnd, out Native.RECT r)
        {
            r = default;
            if (Handle == IntPtr.Zero || !IsVisible) return false;
            OpenWindow win = null;
            foreach (var l in groups.Values) { win = l.FirstOrDefault(x => x.Handle == hwnd); if (win != null) break; }
            FrameworkElement tile = null;
            if (win != null)
            {
                foreach (var t in tiles)
                {
                    if (t.app == null || t.pinId == "tool") continue;
                    bool mine = t.pinId == "open"
                        ? (!string.IsNullOrEmpty(win.AppId) ? string.Equals(t.app.AppId, win.AppId, StringComparison.OrdinalIgnoreCase) : string.Equals(Path.GetFileName(t.app.Exe ?? ""), Path.GetFileName(win.Exe ?? ""), StringComparison.OrdinalIgnoreCase))
                        : Belongs(t.app, win);
                    if (mine) { tile = t.tile; break; }
                }
            }
            try
            {
                if (tile != null && tile.IsVisible && PresentationSource.FromVisual(tile) != null)
                {
                    var a = tile.PointToScreen(new Point(0, 0)); var b = tile.PointToScreen(new Point(tile.ActualWidth, tile.ActualHeight));
                    r = new Native.RECT { Left = (int)Math.Min(a.X, b.X), Top = (int)Math.Min(a.Y, b.Y), Right = (int)Math.Max(a.X, b.X), Bottom = (int)Math.Max(a.Y, b.Y) };
                    return r.Right > r.Left;
                }
                if (!Native.GetWindowRect(Handle, out var d)) return false;
                int cx = (d.Left + d.Right) / 2, cy = (d.Top + d.Bottom) / 2;
                r = new Native.RECT { Left = cx - 20, Top = cy - 20, Right = cx + 20, Bottom = cy + 20 };
                return true;
            }
            catch { return false; }
        }
        static string AppName(OpenWindow w)
        {
            if (!string.IsNullOrEmpty(w.AppId)) { var hit = AppCatalog.Apps.FirstOrDefault(a => string.Equals(a.AppId, w.AppId, StringComparison.OrdinalIgnoreCase)); if (hit != null) return hit.Name; }
            var byExe = AppCatalog.Apps.FirstOrDefault(a => !string.IsNullOrEmpty(a.Exe) && Path.GetFileName(a.Exe).Equals(Path.GetFileName(w.Exe), StringComparison.OrdinalIgnoreCase));
            if (byExe != null) return byExe.Name;
            try { var d = System.Diagnostics.FileVersionInfo.GetVersionInfo(w.Exe).FileDescription; if (!string.IsNullOrWhiteSpace(d)) return d; } catch { }
            return string.IsNullOrEmpty(w.Exe) ? w.Title : Path.GetFileNameWithoutExtension(w.Exe);
        }

        // When an app was just started from the dock, more clicks before its window appears do not start it
        // again (clicking fast used to open three copies).
        readonly Dictionary<string, DateTime> launched = new Dictionary<string, DateTime>();
        void Click(AppRef app, Dictionary<string, object> pin)
        {
            if (Json.Str(pin, "kind") == "Baka")
            {
                var last = Files.Last;
                if (last == null) Files.Open(null);
                else if (last.WindowState == WindowState.Minimized || !last.IsActive) { if (last.WindowState == WindowState.Minimized) last.WindowState = WindowState.Normal; last.Activate(); }
                else last.WindowState = WindowState.Minimized;
                return;
            }
            var mine = groups.Values.SelectMany(l => l).Where(w => Belongs(app, w) && Native.IsWindow(w.Handle)).ToList();
            if (mine.Count == 1) { Windows.Toggle(mine[0]); return; }
            var tile = tiles.FirstOrDefault(x => x.app == app).tile;
            if (mine.Count > 1) { if (tile != null) WindowMenu(tile, mine); return; }
            string id = Json.Str(pin, "id");
            if (launched.TryGetValue(id, out var at) && (DateTime.Now - at).TotalSeconds < 4) return;
            launched[id] = DateTime.Now;
            if (tile != null) Bounce(tile);
            Launch(pin);
        }
        public static void Launch(Dictionary<string, object> pin)
        {
            string kind = Json.Str(pin, "kind"), target = Paths.Expand(Json.Str(pin, "target")), args = Json.Str(pin, "arguments");
            string name = Json.Str(pin, "name");
            // BAKA's own Files window is WPF: open it on the UI thread.
            if (kind == "Baka") { try { Files.Open(null); } catch (Exception e) { Log.Write("dock-launch-failed name=\"BAKA\" error=\"" + e.Message + "\""); } return; }
            if (kind == "Executable" && !File.Exists(target)) { MessageBox.Show(name + " is not installed at\n" + target, "BAKA", MessageBoxButton.OK, MessageBoxImage.Information); return; }
            // Everything else starts another program: do it off the UI thread so a slow shell/UWP activation
            // can't freeze BAKA when it is the shell.
            Launcher.Run(name, () =>
            {
                // a Store app by its app id: the shell-free launcher first, so it works with Explorer stopped
                if (kind == "AppId" && target.Contains("!") && Native.LaunchAppId(target, args)) { Log.Write("dock-launch name=\"" + name + "\" via=aumid"); return; }
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(kind == "AppId" ? "shell:AppsFolder\\" + target : target, args) { UseShellExecute = true });
                Log.Write("dock-launch name=\"" + name + "\"");
            });
        }

        void WindowMenu(FrameworkElement anchor, List<OpenWindow> list)
        {
            Ui.ShowMenu(anchor, list.Select(w => (object)Ui.Item(w.Title.Length > 60 ? w.Title.Substring(0, 60) + "…" : w.Title, 0xE737, () => Native.Activate(w.Handle))).ToArray());
        }
        void PinMenu(FrameworkElement anchor, AppRef app, Dictionary<string, object> pin)
        {
            var mine = groups.Values.SelectMany(l => l).Where(w => Belongs(app, w)).ToList();
            var items = new List<object>();
            foreach (var w in mine) items.Add(Ui.Item(w.Title.Length > 60 ? w.Title.Substring(0, 60) + "…" : w.Title, 0xE737, () => Native.Activate(w.Handle)));
            if (mine.Count > 0) items.Add("-");
            items.Add(Ui.Item(mine.Count > 0 ? "New window" : "Open", 0xE8A7, () => Launch(pin)));
            if (Json.Str(pin, "kind") == "Executable") { var tgt = Paths.Expand(Json.Str(pin, "target")); items.Add(Ui.Item("Run as administrator", 0xE7EF, () => Launcher.Run(tgt, () => System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(tgt) { UseShellExecute = true, Verb = "runas" })))); }
            if (Json.Str(pin, "kind") == "Executable") items.Add(Ui.Item("Open file location", 0xE838, () => { string t = Paths.Expand(Json.Str(pin, "target")); Files.Open(Path.GetDirectoryName(t), t); }));
            items.Add(Ui.Item("Unpin from dock", 0xE77A, () => { App.Settings.Pinned.Remove(pin); App.Settings.Save(); Build(); }));
            if (mine.Count > 0) { items.Add("-"); items.Add(Ui.Item(mine.Count > 1 ? "Close all windows" : "Close window", 0xE8BB, () => mine.ForEach(w => Windows.Close(w.Handle)))); }
            Ui.ShowMenu(anchor, items.ToArray());
        }
        void OpenMenu(FrameworkElement anchor, AppRef app, List<OpenWindow> list)
        {
            var items = new List<object>();
            foreach (var w in list) items.Add(Ui.Item(w.Title.Length > 60 ? w.Title.Substring(0, 60) + "…" : w.Title, 0xE737, () => Native.Activate(w.Handle)));
            items.Add("-");
            if (!string.IsNullOrEmpty(app.Exe) || !string.IsNullOrEmpty(app.AppId)) items.Add(Ui.Item("Keep in dock", 0xE718, () => { Pin(app); }));
            items.Add(Ui.Item(list.Count > 1 ? "Close all windows" : "Close window", 0xE8BB, () => list.ForEach(w => Windows.Close(w.Handle))));
            Ui.ShowMenu(anchor, items.ToArray());
        }
        public static void Pin(AppRef app)
        {
            if (IsPinned(app)) return;
            // Store apps are pinned by their app id (their window belongs to ApplicationFrameHost.exe, which
            // R15 pinned by mistake); programs by their .exe; Start menu shortcuts by their entry.
            bool store = !string.IsNullOrEmpty(app.AppId) && app.AppId.Contains("!");
            bool exe = !store && !string.IsNullOrEmpty(app.Exe) && File.Exists(app.Exe) && app.Exe.EndsWith(".exe", StringComparison.OrdinalIgnoreCase);
            if (!exe && string.IsNullOrEmpty(app.AppId)) return;
            string process = exe ? Path.GetFileNameWithoutExtension(app.Exe) : "";
            if (!exe && !store) { string lnk = app.Exe ?? ""; string t = lnk.EndsWith(".lnk", StringComparison.OrdinalIgnoreCase) ? AppCatalog.ShortcutTarget(lnk) : null; if (t != null && t.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) process = Path.GetFileNameWithoutExtension(t); }
            // an entry listed by app id (Discord, Kiro): remember the program it starts for window matching
            if (!exe && !store && process.Length == 0 && !string.IsNullOrEmpty(app.Target)) process = Path.GetFileNameWithoutExtension(app.Target);
            App.Settings.Pinned.Add(new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase)
            {
                ["id"] = Guid.NewGuid().ToString("N").Substring(0, 10), ["name"] = app.Name, ["kind"] = exe ? "Executable" : "AppId",
                ["target"] = exe ? app.Exe : app.AppId, ["arguments"] = "", ["processName"] = process, ["glyph"] = "", ["iconPath"] = ""
            });
            App.Settings.Save(); App.Dock?.Build();
            Log.Write("dock-pinned name=\"" + app.Name + "\"");
        }
        static bool SamePin(Dictionary<string, object> p, AppRef app)
        {
            if (p == null) return false;
            string t = Paths.Expand(Json.Str(p, "target"));
            return (!string.IsNullOrEmpty(app.Exe) && string.Equals(t, app.Exe, StringComparison.OrdinalIgnoreCase))
                || (!string.IsNullOrEmpty(app.AppId) && string.Equals(t, app.AppId, StringComparison.OrdinalIgnoreCase));
        }
        public static bool IsPinned(AppRef app) => App.Settings.Pinned.Select(Json.Obj).Any(p => SamePin(p, app));
        public static void Unpin(AppRef app)
        {
            var hit = App.Settings.Pinned.Select(Json.Obj).FirstOrDefault(p => SamePin(p, app));
            if (hit != null) { App.Settings.Pinned.Remove(hit); App.Settings.Save(); App.Dock?.Build(); }
        }

        // ---- motion ----
        void OnMouseMove(object sender, MouseEventArgs e)
        {
            if (!Json.Bool(App.Settings.Dock, "magnification", true) || !Theme.Motion) return;
            var p = e.GetPosition(panel);
            foreach (var t in tiles)
            {
                var c = t.tile.TranslatePoint(new Point(t.tile.ActualWidth / 2, t.tile.ActualHeight / 2), panel);
                double d = Vertical ? Math.Abs(c.Y - p.Y) : Math.Abs(c.X - p.X);
                double k = Math.Max(0, 1 - d / (IconSize * 2.0));
                Magnify(t.tile, 1 + (MaxMagnify - 1) * k * k);
            }
        }
        static void Magnify(FrameworkElement e, double s)
        {
            if (!(e.RenderTransform is ScaleTransform st) || st.IsFrozen) { st = new ScaleTransform(1, 1); e.RenderTransform = st; }
            if (Math.Abs(st.ScaleX - s) < 0.004) return; // no new animation for every mouse pixel
            var a = new DoubleAnimation(s, TimeSpan.FromMilliseconds(90)) { EasingFunction = new QuadraticEase() };
            st.BeginAnimation(ScaleTransform.ScaleXProperty, a); st.BeginAnimation(ScaleTransform.ScaleYProperty, a);
        }
        // The launch bounce moves the icon inside its tile, so it never fights the magnification.
        void Bounce(Border tile)
        {
            if (!Theme.Motion || !(tile.Child is FrameworkElement inner)) return;
            var tt = new TranslateTransform(); inner.RenderTransform = tt;
            var a = new DoubleAnimationUsingKeyFrames { Duration = TimeSpan.FromMilliseconds(480) };
            double dir = Edge == "Left" ? 1 : -1;
            a.KeyFrames.Add(new EasingDoubleKeyFrame(6 * dir, KeyTime.FromPercent(0.35), new QuadraticEase { EasingMode = EasingMode.EaseOut }));
            a.KeyFrames.Add(new EasingDoubleKeyFrame(0, KeyTime.FromPercent(1), new BounceEase { Bounces = 1, Bounciness = 3 }));
            a.Completed += (o, x) => inner.RenderTransform = Transform.Identity;
            tt.BeginAnimation(Vertical ? TranslateTransform.XProperty : TranslateTransform.YProperty, a);
        }
        // ---- auto-hide: slide the dock off its edge and give the space back; reveal when the pointer
        // reaches the edge. R15 only set the window to 1% opacity, so the icons vanished but the dock still
        // sat there taking the same space.
        System.Windows.Threading.DispatcherTimer autoHideTimer;
        bool collapsed;
        // Settings > Dock > hide until the pointer reaches it, or Focus mode tucking the dock away for now
        public static bool AutoHiding => App.Settings != null && (Json.Bool(App.Settings.Dock, "autoHide") || FocusMode.HidesDock);
        void AutoHideTick()
        {
            if (Handle == IntPtr.Zero || !IsVisible) return;
            // a fullscreen game is in front and the dock waits behind it: the pointer at the screen edge (aiming
            // in a game) must not slide it in and out
            if (App.BehindFullscreen) return;
            bool on = AutoHiding && !App.BakaHidden;
            // auto-hide off: the edge check stops completely (it ran 8 times a second for nothing, part of the
            // idle CPU the benchmark showed); Place / Show start it again when auto-hide is turned on
            if (!on) { if (collapsed) Slide(false); else autoHideTimer.Stop(); return; }
            if (IsMouseOver) { if (collapsed) Slide(false); return; }
            if (CursorAtEdge()) { if (collapsed) Slide(false); }
            else { if (!collapsed) Slide(true); }
        }
        bool CursorAtEdge()
        {
            if (!Native.GetCursorPos(out var p)) return false;
            var b = System.Windows.Forms.Screen.PrimaryScreen.Bounds; int t = 3;
            if (Edge == "Left") return p.X <= b.Left + t;
            if (Edge == "Right") return p.X >= b.Right - 1 - t;
            return p.Y >= b.Bottom - 1 - t;
        }
        void Slide(bool hide)
        {
            collapsed = hide;
            double screenW = SystemParameters.PrimaryScreenWidth, screenH = SystemParameters.PrimaryScreenHeight;
            if (Edge == "Left" || Edge == "Right")
            {
                double to = !hide ? shownLeft : (Edge == "Left" ? -(ActualWidth + 60) : screenW + 60);
                var a = new DoubleAnimation(to, TimeSpan.FromMilliseconds(hide ? 180 : 130)) { EasingFunction = new QuadraticEase() };
                BeginAnimation(LeftProperty, a);
            }
            else
            {
                double to = !hide ? shownTop : screenH + 60;
                var a = new DoubleAnimation(to, TimeSpan.FromMilliseconds(hide ? 180 : 130)) { EasingFunction = new QuadraticEase() };
                BeginAnimation(TopProperty, a);
            }
            Log.Write("dock-autohide " + (hide ? "collapsed" : "revealed"));
        }

        bool minimumReset;
        double shownLeft, shownTop;
        // ---- position: centred on its screen edge, below the menu bar ----
        public void Place()
        {
            if (Handle == IntPtr.Zero) return;
            if (!minimumReset)
            {
                // Make Windows ask for the minimum size again now that the 1 x 1 hook is in place (the first
                // answer, about 136 px, was given before it existed and WPF keeps it).
                minimumReset = true;
                SizeToContent = SizeToContent.Manual;
                Native.SetWindowPos(Handle, IntPtr.Zero, 0, 0, 1, 1, 0x0002 | 0x0004 | 0x0010);
            }
            SizeToContent = SizeToContent.WidthAndHeight;
            var screen = new Rect(0, 0, SystemParameters.PrimaryScreenWidth, SystemParameters.PrimaryScreenHeight);
            double top = Json.Bool(App.Settings.TopBar, "enabled", true) ? TopBar.BarHeight : 0;
            double avail = screen.Height - top;
            // Too many open apps for the screen edge: the whole dock shrinks to fit instead of running off it.
            panel.LayoutTransform = Transform.Identity;
            panel.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            double need = Vertical ? panel.DesiredSize.Height + 2 : panel.DesiredSize.Width + 2, room = (Vertical ? avail : screen.Width) - 24;
            if (need > room && need > 0) { double f = Math.Max(0.45, room / need); panel.LayoutTransform = new ScaleTransform(f, f); }
            UpdateLayout();
            // Fully rounded ends so the dock reads as one floating pill, not a bar with square-ish ends.
            double pill = Math.Max(16, Math.Min(Vertical ? ActualWidth : ActualHeight, 72) / 2);
            if (Math.Abs(Radius - pill) > 0.5) { Radius = pill; Frame.CornerRadius = new CornerRadius(pill); UpdateBlur(); }
            if (Edge == "Left") { shownLeft = 12; shownTop = top + Math.Max(8, (avail - ActualHeight) / 2); }
            else if (Edge == "Right") { shownLeft = screen.Width - ActualWidth - 12; shownTop = top + Math.Max(8, (avail - ActualHeight) / 2); }
            else { shownLeft = (screen.Width - ActualWidth) / 2; shownTop = screen.Height - ActualHeight - 12; }
            BeginAnimation(LeftProperty, null); BeginAnimation(TopProperty, null);
            Top = shownTop; Left = shownLeft;
            // Auto-hide: if it is on and the pointer isn't on the dock or its screen edge, tuck the whole
            // window off-screen right now (not just on the next timer tick), so enabling it hides immediately
            // and no icon-less bar is ever left behind.
            if (AutoHiding && !App.BakaHidden && !IsMouseOver && !CursorAtEdge())
            {
                collapsed = true;
                if (Edge == "Left") Left = -(ActualWidth + 60);
                else if (Edge == "Right") Left = screen.Width + 60;
                else Top = screen.Height + 60;
            }
            Reserve();
        }
        // The dock floats over the desktop; maximized windows end next to it instead of under it.
        public void Reserve()
        {
            CheckAutoHide();
            if (Handle == IntPtr.Zero || !IsVisible) return;
            double s = Ui.Scale(this);
            var b = System.Windows.Forms.Screen.PrimaryScreen.Bounds;
            int thick = (int)Math.Round(((Vertical ? ActualWidth : ActualHeight) + 14) * s);
            uint edge = Edge == "Left" ? Native.ABE_LEFT : Edge == "Right" ? Native.ABE_RIGHT : Native.ABE_BOTTOM;
            var r = new Native.RECT { Left = b.Left, Top = b.Top, Right = b.Right, Bottom = b.Bottom };
            // A left/right dock starts below the menu bar's reserved strip. Two app bars must not overlap at
            // the top corner: when the dock spanned the full height it overlapped the menu bar there, and next
            // to the helper Explorer its app-bar manager then dropped the dock's reservation, so maximized
            // windows slid under the dock. Below the menu bar the two form an L and both stick.
            if ((edge == Native.ABE_LEFT || edge == Native.ABE_RIGHT) && App.Bar != null && App.Bar.IsVisible && !TopBar.AutoHide)
                r.Top = b.Top + (int)Math.Round(TopBar.BarHeight * s);
            if (edge == Native.ABE_LEFT) r.Right = b.Left + thick; else if (edge == Native.ABE_RIGHT) r.Left = b.Right - thick; else r.Top = b.Bottom - thick;
            if (AutoHiding) { AppBars.Release(Handle); return; }
            AppBars.Reserve(Handle, edge, r);
        }
        public new void Hide() { if (Handle != IntPtr.Zero) AppBars.Release(Handle); autoHideTimer?.Stop(); base.Hide(); }
        public new void Show()
        {
            collapsed = false; base.Show(); Opacity = 1; Dispatcher.BeginInvoke(new Action(Place), System.Windows.Threading.DispatcherPriority.Loaded);
            // back from a game: the dock rises in again (desktop profile only)
            if (Theme.Motion) Ui.FadeIn(Frame, 260, 0.92, Vertical ? 0 : 16);
        }
        public void CheckAutoHide() { if (autoHideTimer != null && (AutoHiding || collapsed) && !autoHideTimer.IsEnabled) autoHideTimer.Start(); }
    }
}
