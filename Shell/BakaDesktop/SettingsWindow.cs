using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Baka.Desktop
{
    // BAKA Settings. Every change applies at once and is saved at once; there is no Apply button to forget.
    class SettingsWindow : AppWindow
    {
        static SettingsWindow current;
        public static SettingsWindow Current => current;
        string page = "Appearance";
        static readonly (string id, int glyph)[] Pages = { ("Appearance", 0xE771), ("Wallpaper", 0xEB9F), ("Dock", 0xE8A9), ("Menu bar", 0xE8FD), ("Widgets", 0xF246), ("Windows", 0xE7F4), ("Privacy & ads", 0xE72E), ("Focus & games", 0xE7FC), ("Power", 0xE945), ("About", 0xE946) };
        public static IEnumerable<string> PageNames => Pages.Select(p => p.id);
        Settings S => App.Settings;

        public static void Open(string page = null)
        {
            if (current == null) { current = new SettingsWindow(); current.Closed += (o, e) => current = null; current.Show(); }
            if (page != null) current.Go(page);
            if (current.WindowState == WindowState.Minimized) current.WindowState = WindowState.Normal;
            current.Activate();
            try { Native.Activate(current.Handle); } catch { }
        }
        SettingsWindow() : base("BAKA Settings", 980, 680) { Rebuild(); }
        public void Go(string p) { page = Pages.Any(x => x.id == p) ? p : "Appearance"; Rebuild(); }
        public string CurrentPage => page;

        // Every change redraws the page (so it shows the new state); the scroll position is kept, so changing a
        // setting far down the page no longer jumps back to the top.
        ScrollViewer pageScroll; string scrolledPage;
        public override void Rebuild()
        {
            double keep = pageScroll != null && scrolledPage == page ? pageScroll.VerticalOffset : 0;
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(220) }); g.ColumnDefinitions.Add(new ColumnDefinition());
            var nav = new StackPanel { Margin = new Thickness(14, 2, 10, 14) };
            foreach (var (id, glyph) in Pages)
            {
                bool on = id == page;
                var sp = new StackPanel { Orientation = Orientation.Horizontal };
                sp.Children.Add(Ui.Glyph(glyph, 14, on ? Theme.Accent : Theme.Text)); var t = Ui.Text(id, 13, on ? FontWeights.SemiBold : FontWeights.Normal); t.Margin = new Thickness(12, 0, 0, 0); sp.Children.Add(t);
                var b = new Border { Child = sp, Padding = new Thickness(12, 9, 12, 9), CornerRadius = new CornerRadius(9), Cursor = Cursors.Hand, Margin = new Thickness(0, 0, 0, 2), Background = on ? Theme.B(Theme.AccentHex, 46) : Brushes.Transparent };
                string pid = id;
                b.MouseEnter += (o, e) => { if (pid != page) b.Background = Theme.Hover; }; b.MouseLeave += (o, e) => { if (pid != page) b.Background = Brushes.Transparent; };
                Ui.OnClick(b, () => Go(pid));
                System.Windows.Automation.AutomationProperties.SetName(b, id);
                nav.Children.Add(b);
            }
            g.Children.Add(nav);
            var content = new StackPanel { Margin = new Thickness(18, 2, 30, 30) };
            switch (page)
            {
                case "Appearance": Appearance(content); break;
                case "Wallpaper": WallpaperPage(content); break;
                case "Dock": DockPage(content); break;
                case "Menu bar": BarPage(content); break;
                case "Widgets": WidgetsPage(content); break;
                case "Windows": WindowsPage(content); break;
                case "Privacy & ads": PrivacyPage(content); break;
                case "Focus & games": FocusGamesPage(content); break;
                case "Power": PowerPage(content); break;
                default: About(content); break;
            }
            var scroll = Ui.Scroll(content); Grid.SetColumn(scroll, 1); g.Children.Add(scroll);
            if (keep > 0) { scroll.Loaded += (o, e) => scroll.ScrollToVerticalOffset(keep); }
            else if (scrolledPage != page) Ui.FadeIn(content, 160, 1.0, 10); // a new page slides in a little
            pageScroll = scroll; scrolledPage = page;
            Body.Content = g;
        }
        void Save() => S.Save();
        static void Run(string uri) { try { Process.Start(uri); } catch { } }

        void Appearance(StackPanel c)
        {
            c.Children.Add(Ui.Heading("Appearance", "Theme, accent colour, glass, motion and app icons. Changes show everywhere at once."));
            var grid = new WrapPanel { Margin = new Thickness(0, 0, 0, 8) };
            foreach (var t in Theme.All)
            {
                var theme = t; bool on = t == Theme.Current;
                var preview = new Border { Width = 168, Height = 92, CornerRadius = new CornerRadius(12), Background = Theme.B(t.Canvas), BorderBrush = on ? Theme.Accent : Theme.B(t.Border, 120), BorderThickness = new Thickness(on ? 2.4 : 1), Margin = new Thickness(0, 0, 10, 4), Cursor = Cursors.Hand, ClipToBounds = true };
                var inner = new Grid();
                inner.Children.Add(new Border { Width = 120, Height = 52, CornerRadius = new CornerRadius(9), Background = Theme.B(t.Surface), BorderBrush = Theme.B(t.Border, 140), BorderThickness = new Thickness(1), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
                var dots = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
                dots.Children.Add(new Border { Width = 18, Height = 18, CornerRadius = new CornerRadius(5), Background = Theme.B(t.Accent), Margin = new Thickness(3) });
                dots.Children.Add(new Border { Width = 18, Height = 18, CornerRadius = new CornerRadius(5), Background = Theme.B(t.Accent2.Length > 0 ? t.Accent2 : t.Accent), Margin = new Thickness(3) });
                dots.Children.Add(new Border { Width = 18, Height = 18, CornerRadius = new CornerRadius(5), Background = Theme.B(t.SurfaceAlt), Margin = new Thickness(3) });
                inner.Children.Add(dots);
                preview.Child = inner;
                var name = Ui.Text(t.Name.Replace("BAKA ", ""), 12, on ? FontWeights.SemiBold : FontWeights.Normal); name.Margin = new Thickness(2, 0, 0, 12);
                var sp = new StackPanel(); sp.Children.Add(preview); sp.Children.Add(name);
                Ui.OnClick(preview, () => { S.Appearance["theme"] = theme.Name; S.Appearance["accentColor"] = theme.Accent; Save(); Theme.Apply(theme.Name, theme.Accent); });
                grid.Children.Add(sp);
            }
            c.Children.Add(grid);
            var accent = new StackPanel { Orientation = Orientation.Horizontal };
            foreach (var hex in new[] { "#FAFAFA", "#FB5668", "#FF8A4C", "#F5B73B", "#34D399", "#2DD4BF", "#38BDF8", "#5AC8FA", "#7C83FF", "#C59BFF", "#FF7EB6" })
            {
                string h = hex;
                var sw = new Border { Width = 24, Height = 24, CornerRadius = new CornerRadius(12), Background = Theme.B(h), Margin = new Thickness(0, 0, 6, 0), Cursor = Cursors.Hand, BorderBrush = Theme.Text, BorderThickness = new Thickness(string.Equals(Theme.AccentHex, h, StringComparison.OrdinalIgnoreCase) ? 2.4 : 0), ToolTip = h };
                Ui.OnClick(sw, () => { S.Appearance["accentColor"] = h; Save(); Theme.Apply(Theme.Current.Name, h); });
                accent.Children.Add(sw);
            }
            c.Children.Add(Ui.Row("Accent colour", "Buttons, focus rings, selections and neon icon tiles.", accent));
            var glass = new Slider { Minimum = 0, Maximum = 90, Width = 220, Value = Json.Int(S.Appearance, "glassIntensity", 34), TickFrequency = 5, IsSnapToTickEnabled = true };
            // A new glass level redraws every BAKA surface: applied once the slider stops, not for every step.
            var applyGlass = Ui.Debounce(() => { Save(); Theme.Apply(Theme.Current.Name, Theme.AccentHex); }, 300);
            glass.ValueChanged += (o, e) => { S.Appearance["glassIntensity"] = (int)glass.Value; applyGlass(); };
            c.Children.Add(Ui.Row("Glass / transparency", "How see-through the dock, menu bar and widgets are. Low = solid, high = the wallpaper shows through.", glass));
            c.Children.Add(Ui.Row("Motion", "Full: dock wave, springy panels. Off: no animations. Games always turn motion off.", Ui.Choice(new[] { "Off", "Subtle", "Full" }, Json.Str(S.Appearance, "animationIntensity", "Full"), v => { S.Appearance["animationIntensity"] = v; Save(); })));
            c.Children.Add(Ui.Row("App icons", "BAKA: every app gets a BAKA-drawn icon in this theme's style (apps without one keep their own icon on a BAKA tile). Original: icons exactly as the apps ship them.",
                Ui.Choice(new[] { "BAKA", "Original" }, Icons.Style == "Original" ? "Original" : "BAKA", v => { S.Appearance["iconStyle"] = v == "Original" ? "Original" : "Themed"; Save(); Theme.Apply(Theme.Current.Name, Theme.AccentHex); })));
            // preview of the icon set in this theme
            var row = new WrapPanel { Margin = new Thickness(0, 4, 0, 0) };
            foreach (var id in new[] { "baka-browser", "baka-files", "settings", "store", "steam", "discord", "spotify", "media-player", "terminal", "taskmgr", "notepad", "calculator", "paint", "photos", "vscode", "nvidia" })
                row.Children.Add(new Image { Source = Icons.ForId(id), Width = 44, Height = 44, Margin = new Thickness(0, 0, 8, 8), ToolTip = id });
            c.Children.Add(Ui.Card(row));

            // Backgrounds of the dock, menu bar and widgets
            var head = Ui.Text("Backgrounds", 16, FontWeights.SemiBold); head.Margin = new Thickness(0, 14, 0, 2); c.Children.Add(head);
            var sub = Ui.Muted("The dock, the menu bar islands and the widgets can each use the theme's glass, a colour, a picture or a looping video (muted, stopped during games). A video uses a little of the graphics card while it plays."); sub.Margin = new Thickness(0, 0, 0, 10); c.Children.Add(sub);
            foreach (var sid in Surfaces.Ids) c.Children.Add(SurfaceRow(sid));
            // each widget on its own: its own picture or video, or the same as all widgets
            var wh = Ui.Text("Each widget", 13.5, FontWeights.SemiBold); wh.Margin = new Thickness(0, 12, 0, 2); c.Children.Add(wh);
            var ws = Ui.Muted("Give a widget its own colour, picture or video, or leave it on \"Same\" to use the Widgets background above.", 11.5); ws.Margin = new Thickness(0, 0, 0, 6); c.Children.Add(ws);
            foreach (var wid in Widgets.Ids) c.Children.Add(SurfaceRow("widget:" + wid));
        }

        // One surface: Glass / Colour / Picture / Video, then the colour or the file and how dark the veil is.
        FrameworkElement SurfaceRow(string sid)
        {
            var s = Surfaces.Of(sid);
            bool perWidget = sid.StartsWith("widget:");
            string kind = perWidget && !Surfaces.OwnBackground(sid) ? "Same" : Surfaces.Kind(sid);
            void Apply() { Save(); Surfaces.Reset(); Theme.Apply(Theme.Current.Name, Theme.AccentHex); }
            var panel = new StackPanel();
            var labels = perWidget ? new[] { "Same", "Glass", "Colour", "Picture", "Video" } : new[] { "Glass", "Colour", "Picture", "Video" };
            var kinds = perWidget ? new[] { "Same", "Glass", "Color", "Image", "Video" } : new[] { "Glass", "Color", "Image", "Video" };
            panel.Children.Add(Ui.Choice(labels, labels[Math.Max(0, Array.IndexOf(kinds, kind))], v =>
            {
                string k = kinds[Array.IndexOf(labels, v)];
                if (k == "Same") { s.Remove("kind"); Apply(); return; }
                s["kind"] = k;
                if (k == "Image" || k == "Video")
                {
                    string have = Paths.Expand(Json.Str(s, "path"));
                    bool fits = File.Exists(have) && (k == "Video") == Surfaces.IsVideo(have);
                    if (!fits && !PickSurfaceFile(s, k == "Video")) { s["kind"] = kind; Rebuild(); return; }
                }
                Apply();
            }));
            if (kind == "Color")
            {
                var colors = new WrapPanel { Margin = new Thickness(0, 4, 0, 0) };
                foreach (var hex in new[] { "#0B0B0E", "#16161A", "#26262C", "#1E1B2E", "#2A1A3E", "#0F1A2A", "#0E2433", "#0F1F17", "#2A1414", "#3A2410", Theme.AccentHex })
                {
                    string h = hex; bool on = string.Equals(Json.Str(s, "color"), h, StringComparison.OrdinalIgnoreCase);
                    var sw = new Border { Width = 26, Height = 26, CornerRadius = new CornerRadius(13), Background = Theme.B(h), Margin = new Thickness(0, 0, 6, 6), Cursor = Cursors.Hand, BorderBrush = Theme.Text, BorderThickness = new Thickness(on ? 2.4 : 1), ToolTip = h };
                    Ui.OnClick(sw, () => { s["color"] = h; Apply(); });
                    colors.Children.Add(sw);
                }
                panel.Children.Add(colors);
            }
            else if (kind == "Image" || kind == "Video")
            {
                var line = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 4, 0, 0) };
                var file = Ui.Muted(Path.GetFileName(Paths.Expand(Json.Str(s, "path"))), 11.5); file.VerticalAlignment = VerticalAlignment.Center; file.MaxWidth = 260; file.Margin = new Thickness(0, 0, 10, 0);
                line.Children.Add(file);
                line.Children.Add(Ui.Button("Change…", () => { if (PickSurfaceFile(s, kind == "Video")) Apply(); }, false, 9, new Thickness(12, 5, 12, 5)));
                panel.Children.Add(line);
                var dim = new Slider { Minimum = 0, Maximum = 85, Width = 220, Value = Json.Int(s, "dim", 45), TickFrequency = 5, IsSnapToTickEnabled = true, Margin = new Thickness(0, 8, 0, 0), ToolTip = "How dark the veil over the picture is, so text stays readable" };
                var applyDim = Ui.Debounce(Apply, 350);
                dim.ValueChanged += (o, e) => { s["dim"] = (int)dim.Value; applyDim(); };
                panel.Children.Add(dim);
            }
            if (perWidget) return Ui.Row(Widgets.Title(sid.Substring(7)), null, panel);
            string desc = sid == "dock" ? "Behind the app icons." : sid == "bar" ? "Each menu bar island (menu, clock, status)." : "Every widget card (unless a widget has its own below).";
            return Ui.Row(Surfaces.Title(sid), desc, panel);
        }
        bool PickSurfaceFile(Dictionary<string, object> s, bool video)
        {
            var d = new Microsoft.Win32.OpenFileDialog { Filter = video ? "Videos|*.mp4;*.m4v;*.mov;*.wmv;*.mkv;*.webm;*.avi" : "Pictures|*.jpg;*.jpeg;*.png;*.bmp;*.gif" };
            if (d.ShowDialog(this) != true) return false;
            s["path"] = d.FileName; s["kind"] = video ? "Video" : "Image";
            return true;
        }

        // Decoding a 4K PNG takes about 0.1 s; R15 decoded every wallpaper again each time the page was drawn,
        // so picking a wallpaper froze Settings for most of a second. Thumbnails are decoded once.
        static readonly Dictionary<string, BitmapSource> thumbs = new Dictionary<string, BitmapSource>(StringComparer.OrdinalIgnoreCase);
        static BitmapSource Thumbnail(string file)
        {
            if (thumbs.TryGetValue(file, out var t)) return t;
            try { var b = new BitmapImage(); b.BeginInit(); b.DecodePixelWidth = 352; b.CacheOption = BitmapCacheOption.OnLoad; b.UriSource = new Uri(file); b.EndInit(); b.Freeze(); t = b; } catch { t = null; }
            return thumbs[file] = t;
        }
        void WallpaperPage(StackPanel c)
        {
            c.Children.Add(Ui.Heading("Wallpaper", "A BAKA wallpaper, any picture, a looping video or a solid colour."));
            var gallery = new WrapPanel();
            foreach (var f in Paths.Wallpapers())
            {
                string file = f;
                var img = new Border { Width = 176, Height = 99, CornerRadius = new CornerRadius(10), Margin = new Thickness(0, 0, 10, 10), Cursor = Cursors.Hand, ToolTip = Path.GetFileNameWithoutExtension(f), BorderThickness = new Thickness(string.Equals(Paths.Expand(Json.Str(S.Wallpaper, "path")), f, StringComparison.OrdinalIgnoreCase) ? 2.4 : 0), BorderBrush = Theme.Accent };
                var thumb = Thumbnail(f); if (thumb != null) img.Background = new ImageBrush(thumb) { Stretch = Stretch.UniformToFill };
                Ui.OnClick(img, () => { S.Wallpaper["mode"] = "Image"; S.Wallpaper["path"] = file; Save(); Wallpaper.Apply(true); Rebuild(); });
                gallery.Children.Add(img);
            }
            c.Children.Add(gallery);
            var pick = Ui.Labeled(0xE8E5, "Choose a picture or video…", () =>
            {
                var d = new Microsoft.Win32.OpenFileDialog { Filter = "Pictures and videos|*.jpg;*.jpeg;*.png;*.bmp;*.gif;*.webp;*.mp4;*.m4v;*.mov;*.wmv;*.mkv;*.webm;*.avi" };
                if (d.ShowDialog(this) == true)
                {
                    bool vid = new[] { ".mp4", ".m4v", ".mov", ".wmv", ".mkv", ".webm", ".avi" }.Contains(Path.GetExtension(d.FileName).ToLowerInvariant());
                    S.Wallpaper["mode"] = vid ? "Video" : "Image"; S.Wallpaper["path"] = d.FileName; S.Wallpaper.Remove("lastVideoError"); Save(); Wallpaper.Apply(true); Rebuild();
                }
            });
            c.Children.Add(Ui.Row("Your own", "Pictures: JPG, PNG, BMP, GIF, WebP. Videos up to 4K (and higher if your graphics card decodes it): MP4, MOV, MKV, WebM, WMV, AVI with H.264, HEVC, VP9 or AV1. They loop behind the desktop, decoded by the graphics card.", pick));
            string lastError = Json.Str(S.Wallpaper, "lastVideoError");
            if (!string.IsNullOrEmpty(lastError)) c.Children.Add(Ui.Row("Last video could not play", lastError, Ui.Button("Clear", () => { S.Wallpaper.Remove("lastVideoError"); Save(); Rebuild(); })));
            c.Children.Add(Ui.Row("Fit", null, Ui.Choice(new[] { "Fill", "Fit", "Stretch", "Center", "Span" }, Json.Str(S.Wallpaper, "fit", "Fill"), v => { S.Wallpaper["fit"] = v; Save(); Wallpaper.Apply(true); })));
            var colors = new StackPanel { Orientation = Orientation.Horizontal };
            foreach (var hex in new[] { "#05060A", "#101014", "#0B1220", "#1A1026", "#0F1A14", "#2A1414" })
            { string h = hex; var sw = new Border { Width = 26, Height = 26, CornerRadius = new CornerRadius(6), Background = Theme.B(h), Margin = new Thickness(0, 0, 6, 0), Cursor = Cursors.Hand, BorderBrush = Theme.Border, BorderThickness = new Thickness(1) }; Ui.OnClick(sw, () => { S.Wallpaper["mode"] = "Color"; S.Wallpaper["color"] = h; Save(); Wallpaper.Apply(true); }); colors.Children.Add(sw); }
            c.Children.Add(Ui.Row("Solid colour", "No picture at all, the lightest option.", colors));
            c.Children.Add(Ui.Row("Video sound", null, Ui.Toggle(!Json.Bool(S.Wallpaper, "muted", true), on => { S.Wallpaper["muted"] = !on; Save(); Wallpaper.Apply(true); })));
            c.Children.Add(Ui.Row("Close the video during games", "Frees the decoder and its video memory while a game runs; it continues where it was afterwards.", Ui.Toggle(Json.Bool(S.Wallpaper, "pauseInGames", true), on => { S.Wallpaper["pauseInGames"] = on; Save(); })));
            c.Children.Add(Ui.Row("Pause when a window covers the desktop", "A maximized or fullscreen app hides the wallpaper, so it stops drawing.", Ui.Toggle(Json.Bool(S.Wallpaper, "pauseWhenCovered", true), on => { S.Wallpaper["pauseWhenCovered"] = on; Save(); })));
            c.Children.Add(Ui.Row("Pause on battery", null, Ui.Toggle(Json.Bool(S.Wallpaper, "pauseOnBattery", true), on => { S.Wallpaper["pauseOnBattery"] = on; Save(); })));
        }

        void DockPage(StackPanel c)
        {
            c.Children.Add(Ui.Heading("Dock", "Your apps and open windows. Right-click an app in the dock or Launchpad to keep it here."));
            c.Children.Add(Ui.Row("Position", null, Ui.Choice(new[] { "Left", "Center", "Right" }, Json.Str(S.Dock, "alignment", "Left"), v => { S.Dock["alignment"] = v; Save(); App.Dock.Build(); })));
            var rebuildDock = Ui.Debounce(() => { Save(); App.Dock.Build(); }, 150);
            var size = new Slider { Minimum = 32, Maximum = 72, Width = 220, Value = Json.Int(S.Dock, "iconSize", 40), TickFrequency = 4, IsSnapToTickEnabled = true };
            size.ValueChanged += (o, e) => { S.Dock["iconSize"] = (int)size.Value; rebuildDock(); };
            c.Children.Add(Ui.Row("Icon size", null, size));
            var spacing = new Slider { Minimum = 4, Maximum = 18, Width = 220, Value = Json.Int(S.Dock, "spacing", 6), TickFrequency = 1, IsSnapToTickEnabled = true };
            spacing.ValueChanged += (o, e) => { S.Dock["spacing"] = (int)spacing.Value; rebuildDock(); };
            c.Children.Add(Ui.Row("Spacing", null, spacing));
            c.Children.Add(Ui.Row("Magnify icons under the pointer", null, Ui.Toggle(Json.Bool(S.Dock, "magnification", true), on => { S.Dock["magnification"] = on; Save(); })));
            c.Children.Add(Ui.Row("Hide the dock until the pointer reaches it", null, Ui.Toggle(Json.Bool(S.Dock, "autoHide"), on => { S.Dock["autoHide"] = on; Save(); App.ReserveEdges(); })));
            c.Children.Add(Ui.Row("Show open windows of other apps", null, Ui.Toggle(Json.Bool(S.Taskbar, "showRunningApps", true), on => { S.Taskbar["showRunningApps"] = on; Save(); App.Dock.Build(); })));
            var list = new StackPanel();
            foreach (var p in S.Pinned.Select(Json.Obj).Where(p => p != null).ToList())
            {
                var pin = p;
                var r = new Grid { Margin = new Thickness(0, 0, 0, 6) }; r.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(40) }); r.ColumnDefinitions.Add(new ColumnDefinition()); r.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                r.Children.Add(new Image { Source = Icons.For(new AppRef { Name = Json.Str(p, "name"), Exe = Json.Str(p, "kind") == "Executable" ? Paths.Expand(Json.Str(p, "target")) : "" }), Width = 30, Height = 30 });
                var n = Ui.Text(Json.Str(p, "name"), 13); n.VerticalAlignment = VerticalAlignment.Center; Grid.SetColumn(n, 1); r.Children.Add(n);
                var actions = new StackPanel { Orientation = Orientation.Horizontal }; Grid.SetColumn(actions, 2);
                int idx = S.Pinned.IndexOf(p);
                actions.Children.Add(Ui.Icon(0xE70E, "Move up", () => { int i = S.Pinned.IndexOf(pin); if (i > 0) { S.Pinned.RemoveAt(i); S.Pinned.Insert(i - 1, pin); Save(); App.Dock.Build(); Rebuild(); } }, 28, 11));
                actions.Children.Add(Ui.Icon(0xE70D, "Move down", () => { int i = S.Pinned.IndexOf(pin); if (i < S.Pinned.Count - 1) { S.Pinned.RemoveAt(i); S.Pinned.Insert(i + 1, pin); Save(); App.Dock.Build(); Rebuild(); } }, 28, 11));
                actions.Children.Add(Ui.Icon(0xE8B9, "Custom icon", () => { var d = new Microsoft.Win32.OpenFileDialog { Filter = "Pictures|*.png;*.jpg;*.jpeg;*.ico;*.bmp;*.gif" }; if (d.ShowDialog(this) == true) { pin["iconPath"] = d.FileName; Save(); App.Dock.Build(); } }, 28, 11));
                actions.Children.Add(Ui.Icon(0xE74D, "Remove from dock", () => { S.Pinned.Remove(pin); Save(); App.Dock.Build(); Rebuild(); }, 28, 11));
                r.Children.Add(actions);
                list.Children.Add(r);
            }
            var add = Ui.Labeled(0xE710, "Add a program…", () => { var d = new Microsoft.Win32.OpenFileDialog { Filter = "Programs|*.exe" }; if (d.ShowDialog(this) == true) { Dock.Pin(new AppRef { Name = Path.GetFileNameWithoutExtension(d.FileName), Exe = d.FileName }); Rebuild(); } });
            add.HorizontalAlignment = HorizontalAlignment.Left; add.Margin = new Thickness(0, 6, 0, 0); list.Children.Add(add);
            c.Children.Add(Ui.Text("Kept in the dock", 14, FontWeights.SemiBold)); c.Children.Add(Ui.Card(list));
        }

        void BarPage(StackPanel c)
        {
            c.Children.Add(Ui.Heading("Menu bar", "The strip at the top. Maximized windows stop below it, so their buttons are never covered."));
            c.Children.Add(Ui.Row("Show the menu bar", null, Ui.Toggle(Json.Bool(S.TopBar, "enabled", true), on => { S.TopBar["enabled"] = on; Save(); if (on) App.Bar.Show(); else App.Bar.Hide(); App.ReserveEdges(); })));
            c.Children.Add(Ui.Row("Show the date", "Next to the time in the clock island. Off, the date shows when the pointer is over the clock.", Ui.Toggle(TopBar.ShowDate, on => { S.TopBar["showDate"] = on; Save(); App.Bar?.RefreshClock(); })));
            c.Children.Add(Ui.Row("Show the active profile", "DESKTOP, GAMING or BENCHMARK next to the tray.", Ui.Toggle(Json.Bool(S.TopBar, "showProfile", true), on => { S.TopBar["showProfile"] = on; Save(); Theme.Apply(Theme.Current.Name, Theme.AccentHex); })));
            c.Children.Add(Ui.Row("Hide the menu bar until the pointer reaches the top", "The islands slide up out of sight and apps get the whole screen height; touch the top edge to bring them back.", Ui.Toggle(Json.Bool(S.TopBar, "autoHide"), on => { S.TopBar["autoHide"] = on; Save(); App.Bar.ApplyAutoHide(); App.ReserveEdges(); })));
        }

        void WidgetsPage(StackPanel c)
        {
            c.Children.Add(Ui.Heading("Widgets", "Small cards on the desktop. Drag them by their title, resize from the corner, right-click the title to hide one."));
            c.Children.Add(Ui.Row("Show widgets", null, Ui.Toggle(Json.Bool(S.Widgets, "enabled"), on => { S.Widgets["enabled"] = on; Save(); if (on) Widgets.ShowEnabled(); else Widgets.CloseAll(); })));
            foreach (var item in S.WidgetItems.Select(Json.Obj).Where(i => i != null))
            {
                var it = item; string id = Json.Str(it, "id");
                c.Children.Add(Ui.Row(Widgets.Title(id), id == "media" ? "Play, pause, skip and volume for whatever is playing." : id == "timer" ? "5 to 50 minute focus timer with a sound at the end." : id == "system" ? "CPU, GPU, memory, disk and network, read from Windows." : null,
                    Ui.Toggle(Json.Bool(it, "enabled"), on => { it["enabled"] = on; if (on) S.Widgets["enabled"] = true; Save(); Widgets.ShowEnabled(); })));
            }
            var refresh = new Slider { Minimum = 2, Maximum = 30, Width = 220, Value = Json.Int(S.Widgets, "refreshSeconds", 3), TickFrequency = 1, IsSnapToTickEnabled = true };
            var saveLater = Ui.Debounce(Save, 300);
            refresh.ValueChanged += (o, e) => { S.Widgets["refreshSeconds"] = (int)refresh.Value; saveLater(); };
            c.Children.Add(Ui.Row("System monitor refresh", "Seconds between reads.", refresh));
        }

        void WindowsPage(StackPanel c)
        {
            c.Children.Add(Ui.Heading("Windows integration", "BAKA replaces the taskbar, Start, desktop icons and folder windows. By default Windows File Explorer keeps running hidden in the background; BAKA can also replace it completely."));
            bool chosen = ShellMode.Chosen;
            var shellText = Ui.Muted(
                (chosen ? "On: Windows starts BAKA instead of Explorer when you sign in" + (ShellMode.Active ? " (active now)." : " (from the next sign-in).") : "Off: Explorer runs hidden behind BAKA.") +
                " As the shell, BAKA hosts the tray icons in the menu bar and keeps the menu bar and dock edges free. " +
                "Way back: this switch, or Ctrl+Alt+Del > Task Manager > Run new task > explorer.exe. If BAKA stops three times in a row, Explorer starts on its own.", 11.5);
            shellText.Margin = new Thickness(0, 4, 0, 0);
            var shellRow = new StackPanel(); shellRow.Children.Add(Ui.Text("Use BAKA as the Windows shell (no Explorer)", 13, FontWeights.SemiBold)); shellRow.Children.Add(shellText);
            var shellGrid = new Grid(); shellGrid.ColumnDefinitions.Add(new ColumnDefinition()); shellGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            shellGrid.Children.Add(shellRow);
            var shellToggle = Ui.Toggle(chosen, on => { ShellMode.Choose(on); Rebuild(); }); shellToggle.Margin = new Thickness(16, 0, 0, 0); shellToggle.VerticalAlignment = VerticalAlignment.Center; Grid.SetColumn(shellToggle, 1);
            shellGrid.Children.Add(shellToggle);
            c.Children.Add(Ui.Card(shellGrid, new Thickness(14, 11, 14, 11)));
            if (chosen)
            {
                c.Children.Add(Ui.Row("Windows Explorer in the background",
                    "BAKA replaces everything it can (shortcuts, switcher, snip, Wi-Fi, settings panel, tray, volume, notification pop-ups). Explorer is only needed for the few things that depend on it: the Microsoft Store, the full Windows Settings app, Windows' Snipping Tool and Salad's WSL check.\n" +
                    "On (default): one Explorer stays hidden in the background the whole session, so the Store, Settings and Salad all work and open instantly (about 300 MB). Its taskbar and desktop stay hidden.\n" +
                    "Off: no Explorer at all, so BAKA uses the least memory. The Store, the full Settings app and Salad's WSL check then do not work; BAKA opens its own panels where it can. Notifications are shown by BAKA either way.",
                    Ui.Toggle(ShellMode.HelperMode != "Off", on => { S.Integration["explorerMode"] = on ? "Always" : "Off"; S.Integration.Remove("windowsAppsHelper"); Save(); if (on) ShellMode.StartHelper("settings", true); else ShellMode.CloseHelper("settings-off"); })));
            }
            c.Children.Add(Ui.Row("Hide the Windows taskbar", "The menu bar and dock take its place. It comes back by itself if BAKA ever stops.", Ui.Toggle(App.TaskbarWanted, on => { S.Taskbar["autoHideWindowsTaskbar"] = on; Save(); App.ApplyIntegration(); })));
            c.Children.Add(Ui.Row("Windows key opens Launchpad", "Win+E opens BAKA Files, Win+S searches. Ctrl+Esc still opens the Windows Start menu.", Ui.Toggle(Json.Bool(S.Integration, "winKeyOpensLaunchpad", true), on => { S.Integration["winKeyOpensLaunchpad"] = on; Save(); App.ApplyIntegration(); })));
            c.Children.Add(Ui.Row("Hold the Windows key for the shortcut cheat sheet", "Hold Win for a second to see every BAKA shortcut; let go and it disappears. Win+/ keeps it open.", Ui.Toggle(Json.Bool(S.Integration, "cheatSheetOnHold", true), on => { S.Integration["cheatSheetOnHold"] = on; Save(); })));
            c.Children.Add(Ui.Row("Folders open in BAKA Files", "Folders opened from any app, the desktop or a download open in BAKA Files instead of File Explorer.", Ui.Toggle(Json.Bool(S.Integration, "filesOpensFolders", true), on => { S.Integration["filesOpensFolders"] = on; Save(); App.ApplyIntegration(); })));
            c.Children.Add(Ui.Row("BAKA buttons style", "Chips: rounded buttons that light up in the accent colour (close turns red). Lights: coloured circles with their symbols.",
                Ui.Choice(new[] { "Chips", "Lights" }, Json.Str(S.Integration, "captionStyle", "BAKA") == "Lights" ? "Lights" : "Chips", v => { S.Integration["captionStyle"] = v == "Lights" ? "Lights" : "BAKA"; Save(); CaptionButtons.Apply(false); App.ApplyIntegration(); })));
            c.Children.Add(Ui.Row("Cover other apps' own buttons", "Apps that draw their own title bar (Chrome, Discord, Kiro, the Store and Settings) cannot have their buttons removed, so BAKA leaves them alone. Turn this on to paint BAKA buttons over them anyway (it can look like a patch on the title bar).",
                Ui.Toggle(Json.Bool(S.Integration, "captionCover", false), on => { S.Integration["captionCover"] = on; Save(); CaptionButtons.Apply(false); App.ApplyIntegration(); })));
            c.Children.Add(Ui.Row("BAKA buttons on every window", "Close, minimize and maximize in BAKA colours on other apps' windows too. Nothing is loaded into the apps; windows with their own title bar style, admin windows and games keep theirs. Off by default: apps with their own title bar keep the Windows buttons, so with this on, apps look different from each other.", Ui.Toggle(Json.Bool(S.Integration, "captionButtons", false), on => { S.Integration["captionButtons"] = on; Save(); App.ApplyIntegration(); })));
            c.Children.Add(Ui.Row("Hide desktop icons", "Your Desktop folder is in BAKA Files under Places.", Ui.Toggle(Json.Bool(S.Integration, "hideDesktopIcons", true), on => { S.Integration["hideDesktopIcons"] = on; Save(); App.ApplyIntegration(); })));
            var restore = Ui.Labeled(0xE7C4, "Use the normal Windows desktop", () => { if (MessageBox.Show(this, "BAKA Desktop closes and the Windows taskbar, Start and desktop icons come back. Start BAKA Desktop from the Start menu to return.", "BAKA", MessageBoxButton.OKCancel, MessageBoxImage.Question) == MessageBoxResult.OK) App.Quit(true); });
            c.Children.Add(Ui.Row("Leave BAKA", "Everything BAKA changed in Windows is put back.", restore));
            c.Children.Add(Ui.Muted("Recovery: if the screen ever looks wrong, press Ctrl+Shift+Esc for Task Manager and run \"BakaDesktop.exe --restore-windows\", or sign out and in again.", 11.5));
        }

        void PrivacyPage(StackPanel c)
        {
            c.Children.Add(Ui.Heading("Privacy & ads", "BAKA turns off Windows ads, suggestions, Copilot, Recall and telemetry it is allowed to, and can block ads and trackers for every app."));
            bool on = AdBlockDns.On;
            var status = Ui.Text(on ? "On: AdGuard DNS (encrypted)" : "Off: your network's DNS", 12.5, FontWeights.SemiBold, on ? Theme.Accent : Theme.Muted);
            var buttons = new StackPanel { Orientation = Orientation.Horizontal };
            var en = Ui.Labeled(0xE72E, "Block ads in every app", () => { AdBlockDns.RequestElevated(true); WaitAndRefresh(); }, !on); en.Margin = new Thickness(0, 0, 8, 0);
            buttons.Children.Add(en); buttons.Children.Add(Ui.Labeled(0xE777, "Use my normal DNS", () => { AdBlockDns.RequestElevated(false); WaitAndRefresh(); }));
            var sp = new StackPanel(); sp.Children.Add(status); var m = Ui.Muted("Ads, trackers and analytics domains are blocked for every app, game launcher and browser through encrypted DNS. Asks for administrator approval. Baka Browser also blocks ads inside pages with uBlock Origin Lite.", 11.5); m.Margin = new Thickness(0, 4, 0, 8); sp.Children.Add(m); sp.Children.Add(buttons);
            c.Children.Add(Ui.Card(sp));
            c.Children.Add(Ui.Row("Windows privacy settings", null, Ui.Button("Open", () => Run("ms-settings:privacy"))));
            c.Children.Add(Ui.Row("App permissions (camera, microphone, location)", null, Ui.Button("Open", () => Run("ms-settings:privacy-webcam"))));
        }
        void WaitAndRefresh()
        {
            var t = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(2) }; int n = 0; bool start = AdBlockDns.On;
            t.Tick += (o, e) => { if (AdBlockDns.On != start || ++n > 15) { t.Stop(); if (page == "Privacy & ads") Rebuild(); } };
            t.Start();
        }

        void FocusGamesPage(StackPanel c)
        {
            c.Children.Add(Ui.Heading("Focus & games", "Quiet time without pop-ups, and an FPS / CPU / GPU overlay for games."));
            c.Children.Add(Section("Focus"));
            c.Children.Add(Ui.Row("Focus", "No notification pop-ups; they still collect behind the bell. Ctrl+Alt+D turns it on or off.", Ui.Toggle(FocusMode.On, on => { FocusMode.Set(on, "settings"); Rebuild(); })));
            c.Children.Add(Ui.Row("Turn on by itself while a game runs", "And off again when the game closes. A summary shows how many notifications came in.", Ui.Toggle(Json.Bool(S.Focus, "autoInGames", true), on => { S.Focus["autoInGames"] = on; Save(); })));
            c.Children.Add(Ui.Row("Tuck the dock away", "While Focus is on, the dock slides off its edge and comes back when the pointer reaches it.", Ui.Toggle(Json.Bool(S.Focus, "hideDock", true), on => { S.Focus["hideDock"] = on; Save(); App.Dock?.Place(); })));
            c.Children.Add(Ui.Row("Pause the video wallpaper", "While Focus is on. It continues where it was afterwards.", Ui.Toggle(Json.Bool(S.Focus, "pauseWallpaper", true), on => { S.Focus["pauseWallpaper"] = on; Save(); Wallpaper.Refresh(); })));
            c.Children.Add(Ui.Row("Windows Focus sessions", "Windows' own timed focus sessions and notification rules.", Ui.Button("Open", () => Run("ms-settings:quiethours"))));
            c.Children.Add(Ui.Row("Hide Windows' own notification pop-ups", "BAKA shows each notification, so Windows' banner in the corner is switched off for every app (alarms and calls keep it). Notifications still collect in the notification list. Turning this off gives Windows' banners back as they were.", Ui.Toggle(Json.Bool(S.Integration, "hideWindowsBanners", true), on => { S.Integration["hideWindowsBanners"] = on; Save(); System.Threading.Tasks.Task.Run(() => WindowsBanners.Update()); })));

            c.Children.Add(Section("Game overlay"));
            c.Children.Add(Ui.Row("Show the overlay", "A small see-through strip with FPS, CPU and GPU. Clicks go through it to the game. Ctrl+Alt+F shows or hides it, also in a game.", Ui.Toggle(GameOverlay.Enabled, on => { GameOverlay.SetEnabled(on, "settings"); Rebuild(); })));
            c.Children.Add(Ui.Row("When", null, Ui.Choice(new[] { "In games", "Always" }, GameOverlay.When == "Always" ? "Always" : "In games", v => { S.Overlay["when"] = v == "Always" ? "Always" : "Games"; Save(); GameOverlay.Apply(); })));
            var positions = new[] { ("Top left", "TopLeft"), ("Top right", "TopRight"), ("Bottom left", "BottomLeft"), ("Bottom right", "BottomRight") };
            c.Children.Add(Ui.Row("Position", null, Ui.Choice(positions.Select(p => p.Item1), positions.FirstOrDefault(p => p.Item2 == GameOverlay.Position).Item1 ?? "Top left", v => { S.Overlay["position"] = positions.First(p => p.Item1 == v).Item2; Save(); GameOverlay.Apply(); })));
            var details = new[] { ("FPS only", "FPS"), ("Standard", "Standard"), ("Full", "Full") };
            c.Children.Add(Ui.Row("Detail", "Standard: FPS, CPU, GPU load and GPU temperature. Full adds the 1% low, frame time, video memory, GPU power and RAM.", Ui.Choice(details.Select(d => d.Item1), details.First(d => d.Item2 == GameOverlay.Detail).Item1, v => { S.Overlay["detail"] = details.First(d => d.Item1 == v).Item2; Save(); GameOverlay.Apply(); })));

            // FPS needs Windows' permission to read the graphics event log
            bool now = FpsAccess.InToken, granted = FpsAccess.Granted;
            var sp = new StackPanel();
            sp.Children.Add(Ui.Text(now ? "FPS counter: on" : granted ? "FPS counter: sign out and back in to finish" : "FPS counter: needs your permission once", 12.5, FontWeights.SemiBold, now ? Theme.Accent : Theme.Text));
            string about = now
                ? "BAKA reads each game's frames from Windows' graphics event log (the way Xbox Game Bar and PresentMon measure FPS). Nothing is added to the game."
                : granted
                    ? "Your account is in Windows' \"Performance Log Users\" group now. Windows applies that at the next sign-in; until then the overlay shows — for FPS."
                    : "Windows only lets a program read frame times from its graphics event log if you allow it. BAKA adds your account to Windows' \"Performance Log Users\" group, the same step Xbox Game Bar asks for. That group can record performance counters and event logs; it cannot change settings or install anything. Asks for administrator approval; FPS shows after you sign out and back in. CPU, GPU and temperature work without it.";
            var m = Ui.Muted(about, 11.5); m.Margin = new Thickness(0, 4, 0, 8); sp.Children.Add(m);
            var buttons = new StackPanel { Orientation = Orientation.Horizontal };
            if (!now && !granted) buttons.Children.Add(Ui.Labeled(0xE7EF, "Allow the FPS counter", () => { FpsAccess.RequestElevated(true); WaitForFpsAccess(); }, true));
            if (!now && granted) { var so = Ui.Labeled(0xF3B1, "Sign out now", Power.SignOut, true); so.Margin = new Thickness(0, 0, 8, 0); buttons.Children.Add(so); }
            if (granted || now) buttons.Children.Add(Ui.Labeled(0xE711, "Remove the permission", () => { FpsAccess.RequestElevated(false); WaitForFpsAccess(); }));
            sp.Children.Add(buttons);
            c.Children.Add(Ui.Card(sp));
            string gpu = Nvml.Available ? Nvml.GpuName + ": load, temperature, video memory and power from the NVIDIA driver." : "GPU load from Windows. Temperature and power need an NVIDIA GPU (NVIDIA's driver reports them).";
            c.Children.Add(Ui.Row("Graphics card", gpu, null));
            c.Children.Add(Ui.Row("Exclusive fullscreen", "The overlay shows over borderless and windowed games. A game in exclusive fullscreen is drawn above every window, so choose borderless (or windowed fullscreen) in the game to see it.", null));
            c.Children.Add(Ui.Row("Per-app volume", "Each app's volume is in Control Center, under the main volume (Win+A).", null));
        }
        static TextBlock Section(string t) { var x = Ui.Text(t.ToUpperInvariant(), 10.5, FontWeights.Bold, Theme.Muted); x.Margin = new Thickness(2, 10, 0, 8); return x; }
        void WaitForFpsAccess()
        {
            var t = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(2) }; int n = 0; bool start = FpsAccess.Granted;
            t.Tick += (o, e) => { if (FpsAccess.Granted != start || ++n > 30) { t.Stop(); Fps.Retry(); if (page == "Focus & games") Rebuild(); } };
            t.Start();
        }

        void PowerPage(StackPanel c)
        {
            c.Children.Add(Ui.Heading("Power", "Power plan and profiles. Games switch to Gaming by themselves."));
            var plans = PowerPlans.ListCached();
            if (plans.Count > 0) c.Children.Add(Ui.Row("Power plan", "BAKA Gaming: Ultimate Performance tuned for games (no core parking, no USB sleep).", Ui.Choice(plans.Select(p => p.name), plans.FirstOrDefault(p => p.active).name, n => PowerPlans.Activate(plans.First(p => p.name == n).guid))));
            c.Children.Add(Ui.Row("Profile", null, Ui.Choice(new[] { "Desktop", "Gaming", "Benchmark" }, Profiles.Active == "CompetitiveGaming" ? "Gaming" : Profiles.Active, v => App.SetProfileByHand(v == "Gaming" ? "CompetitiveGaming" : v, "settings"))));
            c.Children.Add(Ui.Row("Windows power options", null, Ui.Button("Open", () => Run("ms-settings:powersleep"))));
        }

        void About(StackPanel c)
        {
            c.Children.Add(Ui.Heading("BAKA Windows Gaming Edition", "BAKA Desktop " + App.Version + " · .NET Framework " + Environment.Version));
            string os = "";
            try { using (var k = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion")) os = k.GetValue("ProductName") + " " + k.GetValue("DisplayVersion") + " (build " + k.GetValue("CurrentBuild") + "." + k.GetValue("UBR") + ")"; } catch { }
            var m = Metrics.Read();
            c.Children.Add(Ui.Row("Windows", os, null));
            c.Children.Add(Ui.Row("Memory", m.MemoryTotalGb.ToString("0") + " GB", null));
            c.Children.Add(Ui.Row("BAKA log", Path.Combine(Paths.Logs, "Desktop.log"), Ui.Button("Open folder", () => Files.Open(Paths.Logs))));
            c.Children.Add(Ui.Row("Source and releases", "github.com/OldcarryG/Baka-windows", Ui.Button("Open", () => Run("https://github.com/OldcarryG/Baka-windows"))));
        }
    }
}
