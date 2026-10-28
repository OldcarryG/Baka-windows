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
            MouseLeave += (o, e) => { foreach (var t in tiles) Magnify(t.tile, 1); if (Json.Bool(App.Settings.Dock, "autoHide")) AutoHideLater(); };
            MouseMove += OnMouseMove;
            SourceInitialized += (o, e) => Native.SetWindowLongPtr(Handle, Native.GWL_EXSTYLE, new IntPtr(Native.ExStyle(Handle) | Native.WS_EX_NOACTIVATE));
        }

        public void Build()
        {
            tiles.Clear();
            panel = new StackPanel { Orientation = Vertical ? Orientation.Vertical : Orientation.Horizontal, Margin = new Thickness(8) };
            Content = panel;
            AddTool(0xE71D, "Apps (Win)", "launchpad", () => Launchpad.Toggle());
            Divider();
            foreach (var p in App.Settings.Pinned.Select(Json.Obj).Where(p => p != null)) AddPinned(p);
            Refresh(true);
        }
        void Divider() { var d = new Border { Background = Theme.B(Theme.Current.Border, 90), Margin = Vertical ? new Thickness(8, 6, 8, 6) : new Thickness(6, 8, 6, 8) }; if (Vertical) d.Height = 1; else d.Width = 1; panel.Children.Add(d); }

        AppRef PinRef(Dictionary<string, object> p)
        {
            string kind = Json.Str(p, "kind"), target = Paths.Expand(Json.Str(p, "target"));
            if (kind == "Baka") return new AppRef { Name = target == "files" ? "BAKA Files" : Json.Str(p, "name") };
            return new AppRef { Name = Json.Str(p, "name"), Exe = kind == "Executable" ? target : "", AppId = kind == "AppId" ? target : "" };
        }
        void AddPinned(Dictionary<string, object> p)
        {
            var app = PinRef(p);
            ImageSource icon = null;
            string custom = Paths.Expand(Json.Str(p, "iconPath"));
            if (!string.IsNullOrEmpty(custom) && File.Exists(custom)) try { icon = new System.Windows.Media.Imaging.BitmapImage(new Uri(custom)); } catch { }
            if (icon == null && Json.Str(p, "id") == "settings") icon = Icons.ForId("settings");
            if (icon == null) icon = Icons.For(app);
            var tile = Tile(icon, Json.Str(p, "name"));
            Ui.OnClick(tile, () => Click(app, p));
            tile.MouseRightButtonUp += (o, e) => { e.Handled = true; PinMenu(tile, app, p); };
            tiles.Add((tile, app, Json.Str(p, "id")));
            panel.Children.Add(tile);
        }
        void AddTool(int glyph, string tip, string id, Action click)
        {
            var g = Ui.Glyph(glyph, IconSize * 0.42);
            var tile = new Border { Width = IconSize, Height = IconSize, CornerRadius = new CornerRadius(IconSize * 0.28), Background = Theme.B(Theme.Current.SurfaceAlt, 160), BorderBrush = Theme.B(Theme.Current.Border, 70), BorderThickness = new Thickness(1), Child = g, ToolTip = tip, Cursor = Cursors.Hand, Margin = Gap(), RenderTransformOrigin = Origin() };
            Ui.OnClick(tile, () => { Bounce(tile); click(); });
            tiles.Add((tile, null, id));
            panel.Children.Add(tile);
        }
        Thickness Gap() { double s = Json.Int(App.Settings.Dock, "spacing", 6) / 2.0; return Vertical ? new Thickness(0, s, 0, s) : new Thickness(s, 0, s, 0); }
        Point Origin() => Edge == "Left" ? new Point(0, 0.5) : Edge == "Right" ? new Point(1, 0.5) : new Point(0.5, 1);
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
            System.Windows.Automation.AutomationProperties.SetName(tile, tip);
            return tile;
        }

        // ---- open windows ----
        Dictionary<string, List<OpenWindow>> groups = new Dictionary<string, List<OpenWindow>>();
        static string GroupKey(OpenWindow w) => !string.IsNullOrEmpty(w.AppId) ? w.AppId.ToLowerInvariant() : Path.GetFileName(w.Exe).ToLowerInvariant();
        static bool Belongs(AppRef pin, OpenWindow w)
        {
            if (pin == null) return false;
            if (pin.Name == "BAKA Files") return false;
            if (!string.IsNullOrEmpty(pin.AppId) && string.Equals(pin.AppId, w.AppId, StringComparison.OrdinalIgnoreCase)) return true;
            return !string.IsNullOrEmpty(pin.Exe) && Path.GetFileName(pin.Exe).Equals(Path.GetFileName(w.Exe), StringComparison.OrdinalIgnoreCase);
        }
        public void Refresh(bool force)
        {
            if (!Json.Bool(App.Settings.Taskbar, "showRunningApps", true)) { if (force) Place(); return; }
            var open = Windows.List();
            groups = open.GroupBy(GroupKey).ToDictionary(g => g.Key, g => g.ToList());
            var unpinned = groups.Where(g => !tiles.Any(t => g.Value.Any(w => Belongs(t.app, w)))).Select(g => g.Key).OrderBy(k => k).ToList();
            string sig = string.Join("|", unpinned) + "#" + string.Join("|", tiles.Select(t => t.pinId + (t.app != null && open.Any(w => Belongs(t.app, w)) ? "*" : "")));
            if (!force && sig == signature) return;
            signature = sig;
            // running indicators on pinned apps
            foreach (var t in tiles) if (t.tile.Tag is Border dot) dot.Visibility = t.app != null && open.Any(w => Belongs(t.app, w)) ? Visibility.Visible : Visibility.Hidden;
            // rebuild the open-apps section (after the pinned apps) and the tools
            int pinnedEnd = 2 + App.Settings.Pinned.Count;
            while (panel.Children.Count > pinnedEnd) panel.Children.RemoveAt(panel.Children.Count - 1);
            tiles.RemoveAll(t => t.pinId == "open" || t.pinId == "tool");
            if (unpinned.Count > 0) Divider();
            foreach (var key in unpinned)
            {
                var ws = groups[key]; var w = ws[0];
                var app = new AppRef { Name = AppName(w), Exe = w.Exe, AppId = w.AppId };
                var tile = Tile(Icons.For(app), app.Name + (ws.Count > 1 ? " (" + ws.Count + " windows)" : ""));
                ((Border)tile.Tag).Visibility = Visibility.Visible;
                Ui.OnClick(tile, () => { var list = groups.TryGetValue(key, out var l) ? l : ws; if (list.Count == 1) Windows.Toggle(list[0]); else WindowMenu(tile, list); });
                tile.MouseRightButtonUp += (o, e) => { e.Handled = true; OpenMenu(tile, app, groups.TryGetValue(key, out var l) ? l : ws); };
                tiles.Add((tile, app, "open"));
                panel.Children.Add(tile);
            }
            Divider();
            foreach (var (g, tip, act) in new (int, string, Action)[] { (0xE7FC, "BAKA Arena", Arena.Open), (0xE9E9, "Control Center", () => ControlCenter.Toggle(this)), (0xE713, "BAKA Settings", () => SettingsWindow.Open()) })
            {
                AddTool(g, tip, "tool", act);
            }
            Dispatcher.BeginInvoke(new Action(Place), System.Windows.Threading.DispatcherPriority.Loaded);
        }
        static string AppName(OpenWindow w)
        {
            if (!string.IsNullOrEmpty(w.AppId)) { var hit = AppCatalog.Apps.FirstOrDefault(a => string.Equals(a.AppId, w.AppId, StringComparison.OrdinalIgnoreCase)); if (hit != null) return hit.Name; }
            var byExe = AppCatalog.Apps.FirstOrDefault(a => !string.IsNullOrEmpty(a.Exe) && Path.GetFileName(a.Exe).Equals(Path.GetFileName(w.Exe), StringComparison.OrdinalIgnoreCase));
            if (byExe != null) return byExe.Name;
            try { var d = System.Diagnostics.FileVersionInfo.GetVersionInfo(w.Exe).FileDescription; if (!string.IsNullOrWhiteSpace(d)) return d; } catch { }
            return string.IsNullOrEmpty(w.Exe) ? w.Title : Path.GetFileNameWithoutExtension(w.Exe);
        }

        void Click(AppRef app, Dictionary<string, object> pin)
        {
            if (Json.Str(pin, "kind") == "Baka") { Files.Open(null); return; }
            var mine = groups.Values.SelectMany(l => l).Where(w => Belongs(app, w)).ToList();
            if (mine.Count == 1) { Windows.Toggle(mine[0]); return; }
            if (mine.Count > 1) { var t = tiles.First(x => x.app == app).tile; WindowMenu(t, mine); return; }
            Bounce(tiles.First(x => x.app == app).tile);
            Launch(pin);
        }
        public static void Launch(Dictionary<string, object> pin)
        {
            string kind = Json.Str(pin, "kind"), target = Paths.Expand(Json.Str(pin, "target")), args = Json.Str(pin, "arguments");
            try
            {
                if (kind == "Baka") { Files.Open(null); return; }
                if (kind == "Executable" && !File.Exists(target)) { MessageBox.Show(Json.Str(pin, "name") + " is not installed at\n" + target, "BAKA", MessageBoxButton.OK, MessageBoxImage.Information); return; }
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(kind == "AppId" ? "shell:AppsFolder\\" + target : target, args) { UseShellExecute = true });
                Log.Write("dock-launch name=\"" + Json.Str(pin, "name") + "\"");
            }
            catch (Exception e) { Log.Write("dock-launch-failed name=\"" + Json.Str(pin, "name") + "\" error=\"" + e.Message + "\""); }
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
            if (Json.Str(pin, "kind") == "Executable") items.Add(Ui.Item("Run as administrator", 0xE7EF, () => { try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(Paths.Expand(Json.Str(pin, "target"))) { UseShellExecute = true, Verb = "runas" }); } catch { } }));
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
            if (!string.IsNullOrEmpty(app.Exe)) items.Add(Ui.Item("Keep in dock", 0xE718, () => { Pin(app); }));
            items.Add(Ui.Item(list.Count > 1 ? "Close all windows" : "Close window", 0xE8BB, () => list.ForEach(w => Windows.Close(w.Handle))));
            Ui.ShowMenu(anchor, items.ToArray());
        }
        public static void Pin(AppRef app)
        {
            if (App.Settings.Pinned.Select(Json.Obj).Any(p => string.Equals(Paths.Expand(Json.Str(p, "target")), string.IsNullOrEmpty(app.Exe) ? app.AppId : app.Exe, StringComparison.OrdinalIgnoreCase))) return;
            bool exe = !string.IsNullOrEmpty(app.Exe) && File.Exists(app.Exe) && !app.Exe.EndsWith(".lnk", StringComparison.OrdinalIgnoreCase);
            App.Settings.Pinned.Add(new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase)
            {
                ["id"] = Guid.NewGuid().ToString("N").Substring(0, 10), ["name"] = app.Name, ["kind"] = exe ? "Executable" : "AppId",
                ["target"] = exe ? app.Exe : app.AppId, ["arguments"] = "", ["processName"] = exe ? Path.GetFileNameWithoutExtension(app.Exe) : "", ["glyph"] = "", ["iconPath"] = ""
            });
            App.Settings.Save(); App.Dock?.Build();
            Log.Write("dock-pinned name=\"" + app.Name + "\"");
        }
        public static bool IsPinned(AppRef app) => App.Settings.Pinned.Select(Json.Obj).Any(p => string.Equals(Paths.Expand(Json.Str(p, "target")), string.IsNullOrEmpty(app.Exe) ? app.AppId : app.Exe, StringComparison.OrdinalIgnoreCase) || string.Equals(Json.Str(p, "target"), app.AppId, StringComparison.OrdinalIgnoreCase));
        public static void Unpin(AppRef app)
        {
            var hit = App.Settings.Pinned.Select(Json.Obj).FirstOrDefault(p => string.Equals(Paths.Expand(Json.Str(p, "target")), app.Exe, StringComparison.OrdinalIgnoreCase) || string.Equals(Json.Str(p, "target"), app.AppId, StringComparison.OrdinalIgnoreCase));
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
                double k = Math.Max(0, 1 - d / (IconSize * 2.2));
                Magnify(t.tile, 1 + 0.26 * k * k);
            }
        }
        static void Magnify(FrameworkElement e, double s)
        {
            if (!(e.RenderTransform is ScaleTransform st) || st.IsFrozen) { st = new ScaleTransform(1, 1); e.RenderTransform = st; }
            var a = new DoubleAnimation(s, TimeSpan.FromMilliseconds(110)) { EasingFunction = new QuadraticEase() };
            st.BeginAnimation(ScaleTransform.ScaleXProperty, a); st.BeginAnimation(ScaleTransform.ScaleYProperty, a);
        }
        void Bounce(FrameworkElement e)
        {
            if (!Theme.Motion) return;
            var tt = new TranslateTransform(); var group = new TransformGroup(); group.Children.Add(e.RenderTransform as ScaleTransform ?? new ScaleTransform(1, 1)); group.Children.Add(tt); e.RenderTransform = group;
            var a = new DoubleAnimationUsingKeyFrames { Duration = TimeSpan.FromMilliseconds(520) };
            double dir = Edge == "Left" ? 1 : Edge == "Right" ? -1 : -1;
            a.KeyFrames.Add(new EasingDoubleKeyFrame(10 * dir, KeyTime.FromPercent(0.35), new QuadraticEase { EasingMode = EasingMode.EaseOut }));
            a.KeyFrames.Add(new EasingDoubleKeyFrame(0, KeyTime.FromPercent(1), new BounceEase { Bounces = 1, Bounciness = 3 }));
            a.Completed += (o, x) => e.RenderTransform = new ScaleTransform(1, 1);
            tt.BeginAnimation(Vertical ? TranslateTransform.XProperty : TranslateTransform.YProperty, a);
        }
        void AutoHideLater()
        {
            var t = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1200) };
            t.Tick += (o, e) => { t.Stop(); if (!IsMouseOver && Json.Bool(App.Settings.Dock, "autoHide")) Opacity = 0.01; };
            t.Start();
        }

        bool minimumReset;
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
            var work = SystemParameters.WorkArea;
            var screen = new Rect(0, 0, SystemParameters.PrimaryScreenWidth, SystemParameters.PrimaryScreenHeight);
            double top = Json.Bool(App.Settings.TopBar, "enabled", true) ? TopBar.BarHeight : 0;
            double avail = screen.Height - top;
            if (Vertical && ActualHeight > avail - 20) { panel.Margin = new Thickness(6); }
            if (Edge == "Left") { Left = 10; Top = top + Math.Max(8, (avail - ActualHeight) / 2); }
            else if (Edge == "Right") { Left = screen.Width - ActualWidth - 10; Top = top + Math.Max(8, (avail - ActualHeight) / 2); }
            else { Left = (screen.Width - ActualWidth) / 2; Top = screen.Height - ActualHeight - 10; }
            Reserve();
        }
        // The dock floats over the desktop; maximized windows end next to it instead of under it.
        public void Reserve()
        {
            if (Handle == IntPtr.Zero || !IsVisible) return;
            double s = Ui.Scale(this);
            var b = System.Windows.Forms.Screen.PrimaryScreen.Bounds;
            int thick = (int)Math.Round(((Vertical ? ActualWidth : ActualHeight) + 14) * s);
            uint edge = Edge == "Left" ? Native.ABE_LEFT : Edge == "Right" ? Native.ABE_RIGHT : Native.ABE_BOTTOM;
            var r = new Native.RECT { Left = b.Left, Top = b.Top, Right = b.Right, Bottom = b.Bottom };
            if (edge == Native.ABE_LEFT) r.Right = b.Left + thick; else if (edge == Native.ABE_RIGHT) r.Left = b.Right - thick; else r.Top = b.Bottom - thick;
            if (Json.Bool(App.Settings.Dock, "autoHide")) { AppBars.Release(Handle); return; }
            AppBars.Reserve(Handle, edge, r);
        }
        public new void Hide() { if (Handle != IntPtr.Zero) AppBars.Release(Handle); base.Hide(); }
        public new void Show() { base.Show(); Opacity = 1; Dispatcher.BeginInvoke(new Action(Place), System.Windows.Threading.DispatcherPriority.Loaded); }
        protected override void OnMouseEnter(MouseEventArgs e) { base.OnMouseEnter(e); Opacity = 1; }
    }
}
