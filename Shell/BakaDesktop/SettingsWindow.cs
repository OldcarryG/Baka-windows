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
        static readonly (string id, int glyph)[] Pages = { ("Appearance", 0xE771), ("Wallpaper", 0xEB9F), ("Dock", 0xE8A9), ("Menu bar", 0xE8FD), ("Widgets", 0xF246), ("Windows", 0xE7F4), ("Privacy & ads", 0xE72E), ("Power", 0xE945), ("About", 0xE946) };
        public static IEnumerable<string> PageNames => Pages.Select(p => p.id);
        Settings S => App.Settings;

        public static void Open(string page = null)
        {
            if (current == null) { current = new SettingsWindow(); current.Closed += (o, e) => current = null; current.Show(); }
            if (page != null) current.Go(page);
            current.Activate();
        }
        SettingsWindow() : base("BAKA Settings", 980, 680) { Rebuild(); }
        public void Go(string p) { page = Pages.Any(x => x.id == p) ? p : "Appearance"; Rebuild(); }
        public string CurrentPage => page;

        public override void Rebuild()
        {
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
                b.MouseLeftButtonUp += (o, e) => Go(pid);
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
                case "Power": PowerPage(content); break;
                default: About(content); break;
            }
            var scroll = Ui.Scroll(content); Grid.SetColumn(scroll, 1); g.Children.Add(scroll);
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
                preview.MouseLeftButtonUp += (o, e) => { S.Appearance["theme"] = theme.Name; S.Appearance["accentColor"] = theme.Accent; Save(); Theme.Apply(theme.Name, theme.Accent); };
                grid.Children.Add(sp);
            }
            c.Children.Add(grid);
            var accent = new StackPanel { Orientation = Orientation.Horizontal };
            foreach (var hex in new[] { "#FAFAFA", "#FB5668", "#FF8A4C", "#F5B73B", "#34D399", "#2DD4BF", "#38BDF8", "#5AC8FA", "#7C83FF", "#C59BFF", "#FF7EB6" })
            {
                string h = hex;
                var sw = new Border { Width = 24, Height = 24, CornerRadius = new CornerRadius(12), Background = Theme.B(h), Margin = new Thickness(0, 0, 6, 0), Cursor = Cursors.Hand, BorderBrush = Theme.Text, BorderThickness = new Thickness(string.Equals(Theme.AccentHex, h, StringComparison.OrdinalIgnoreCase) ? 2.4 : 0), ToolTip = h };
                sw.MouseLeftButtonUp += (o, e) => { S.Appearance["accentColor"] = h; Save(); Theme.Apply(Theme.Current.Name, h); };
                accent.Children.Add(sw);
            }
            c.Children.Add(Ui.Row("Accent colour", "Buttons, focus rings, selections and neon icon tiles.", accent));
            var glass = new Slider { Minimum = 0, Maximum = 45, Width = 220, Value = Json.Int(S.Appearance, "glassIntensity", 34), TickFrequency = 5, IsSnapToTickEnabled = true };
            glass.ValueChanged += (o, e) => { S.Appearance["glassIntensity"] = (int)glass.Value; Save(); Theme.Apply(Theme.Current.Name, Theme.AccentHex); };
            c.Children.Add(Ui.Row("Glass", "How much of the wallpaper shows through menus and panels.", glass));
            c.Children.Add(Ui.Row("Motion", "Full: dock wave, springy panels. Off: no animations. Games always turn motion off.", Ui.Choice(new[] { "Off", "Subtle", "Full" }, Json.Str(S.Appearance, "animationIntensity", "Full"), v => { S.Appearance["animationIntensity"] = v; Save(); })));
            c.Children.Add(Ui.Row("App icons", "BAKA: every app gets a BAKA-drawn icon in this theme's style (apps without one keep their own icon on a BAKA tile). Original: icons exactly as the apps ship them.",
                Ui.Choice(new[] { "BAKA", "Original" }, Icons.Style == "Original" ? "Original" : "BAKA", v => { S.Appearance["iconStyle"] = v == "Original" ? "Original" : "Themed"; Save(); Theme.Apply(Theme.Current.Name, Theme.AccentHex); })));
            // preview of the icon set in this theme
            var row = new WrapPanel { Margin = new Thickness(0, 4, 0, 0) };
            foreach (var id in new[] { "baka-browser", "baka-files", "settings", "store", "steam", "discord", "spotify", "media-player", "terminal", "taskmgr", "notepad", "calculator", "paint", "photos", "vscode", "nvidia" })
                row.Children.Add(new Image { Source = Icons.ForId(id), Width = 44, Height = 44, Margin = new Thickness(0, 0, 8, 8), ToolTip = id });
            c.Children.Add(Ui.Card(row));
        }

        void WallpaperPage(StackPanel c)
        {
            c.Children.Add(Ui.Heading("Wallpaper", "A BAKA wallpaper, any picture, a looping video or a solid colour."));
            var gallery = new WrapPanel();
            foreach (var f in Paths.Wallpapers())
            {
                string file = f;
                var img = new Border { Width = 176, Height = 99, CornerRadius = new CornerRadius(10), Margin = new Thickness(0, 0, 10, 10), Cursor = Cursors.Hand, ToolTip = Path.GetFileNameWithoutExtension(f), BorderThickness = new Thickness(string.Equals(Paths.Expand(Json.Str(S.Wallpaper, "path")), f, StringComparison.OrdinalIgnoreCase) ? 2.4 : 0), BorderBrush = Theme.Accent };
                try { var b = new BitmapImage(); b.BeginInit(); b.DecodePixelWidth = 352; b.CacheOption = BitmapCacheOption.OnLoad; b.UriSource = new Uri(f); b.EndInit(); b.Freeze(); img.Background = new ImageBrush(b) { Stretch = Stretch.UniformToFill }; } catch { }
                img.MouseLeftButtonUp += (o, e) => { S.Wallpaper["mode"] = "Image"; S.Wallpaper["path"] = file; Save(); Wallpaper.Apply(true); Rebuild(); };
                gallery.Children.Add(img);
            }
            c.Children.Add(gallery);
            var pick = Ui.Labeled(0xE8E5, "Choose a picture or video…", () =>
            {
                var d = new Microsoft.Win32.OpenFileDialog { Filter = "Pictures and videos|*.jpg;*.jpeg;*.png;*.bmp;*.gif;*.webp;*.mp4;*.m4v;*.mov;*.wmv;*.mkv;*.webm" };
                if (d.ShowDialog(this) == true)
                {
                    bool vid = new[] { ".mp4", ".m4v", ".mov", ".wmv", ".mkv", ".webm" }.Contains(Path.GetExtension(d.FileName).ToLowerInvariant());
                    S.Wallpaper["mode"] = vid ? "Video" : "Image"; S.Wallpaper["path"] = d.FileName; Save(); Wallpaper.Apply(true); Rebuild();
                }
            });
            c.Children.Add(Ui.Row("Your own", "Pictures: JPG, PNG, BMP, GIF, WebP. Videos loop muted behind the desktop and pause in games.", pick));
            c.Children.Add(Ui.Row("Fit", null, Ui.Choice(new[] { "Fill", "Fit", "Stretch", "Center", "Span" }, Json.Str(S.Wallpaper, "fit", "Fill"), v => { S.Wallpaper["fit"] = v; Save(); Wallpaper.Apply(true); })));
            var colors = new StackPanel { Orientation = Orientation.Horizontal };
            foreach (var hex in new[] { "#05060A", "#101014", "#0B1220", "#1A1026", "#0F1A14", "#2A1414" })
            { string h = hex; var sw = new Border { Width = 26, Height = 26, CornerRadius = new CornerRadius(6), Background = Theme.B(h), Margin = new Thickness(0, 0, 6, 0), Cursor = Cursors.Hand, BorderBrush = Theme.Border, BorderThickness = new Thickness(1) }; sw.MouseLeftButtonUp += (o, e) => { S.Wallpaper["mode"] = "Color"; S.Wallpaper["color"] = h; Save(); Wallpaper.Apply(true); }; colors.Children.Add(sw); }
            c.Children.Add(Ui.Row("Solid colour", "No picture at all, the lightest option.", colors));
            c.Children.Add(Ui.Row("Video sound", null, Ui.Toggle(!Json.Bool(S.Wallpaper, "muted", true), on => { S.Wallpaper["muted"] = !on; Save(); Wallpaper.Apply(true); })));
            c.Children.Add(Ui.Row("Pause video during games", null, Ui.Toggle(Json.Bool(S.Wallpaper, "pauseInGames", true), on => { S.Wallpaper["pauseInGames"] = on; Save(); })));
        }

        void DockPage(StackPanel c)
        {
            c.Children.Add(Ui.Heading("Dock", "Your apps and open windows. Right-click an app in the dock or Launchpad to keep it here."));
            c.Children.Add(Ui.Row("Position", null, Ui.Choice(new[] { "Left", "Center", "Right" }, Json.Str(S.Dock, "alignment", "Left"), v => { S.Dock["alignment"] = v; Save(); App.Dock.Build(); })));
            var size = new Slider { Minimum = 32, Maximum = 72, Width = 220, Value = Json.Int(S.Dock, "iconSize", 40), TickFrequency = 4, IsSnapToTickEnabled = true };
            size.ValueChanged += (o, e) => { S.Dock["iconSize"] = (int)size.Value; Save(); App.Dock.Build(); };
            c.Children.Add(Ui.Row("Icon size", null, size));
            var spacing = new Slider { Minimum = 4, Maximum = 18, Width = 220, Value = Json.Int(S.Dock, "spacing", 6), TickFrequency = 1, IsSnapToTickEnabled = true };
            spacing.ValueChanged += (o, e) => { S.Dock["spacing"] = (int)spacing.Value; Save(); App.Dock.Build(); };
            c.Children.Add(Ui.Row("Spacing", null, spacing));
            c.Children.Add(Ui.Row("Magnify icons under the pointer", null, Ui.Toggle(Json.Bool(S.Dock, "magnification", true), on => { S.Dock["magnification"] = on; Save(); })));
            c.Children.Add(Ui.Row("Hide the dock until the pointer reaches it", null, Ui.Toggle(Json.Bool(S.Dock, "autoHide"), on => { S.Dock["autoHide"] = on; Save(); App.Dock.Place(); })));
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
            c.Children.Add(Ui.Row("Show the menu bar", null, Ui.Toggle(Json.Bool(S.TopBar, "enabled", true), on => { S.TopBar["enabled"] = on; Save(); if (on) App.Bar.Show(); else App.Bar.Hide(); App.Dock.Place(); })));
            c.Children.Add(Ui.Row("Show the date", null, Ui.Toggle(Json.Bool(S.TopBar, "showDate", true), on => { S.TopBar["showDate"] = on; Save(); })));
            c.Children.Add(Ui.Row("Show the active profile", "DESKTOP, GAMING or BENCHMARK next to the tray.", Ui.Toggle(Json.Bool(S.TopBar, "showProfile", true), on => { S.TopBar["showProfile"] = on; Save(); Theme.Apply(Theme.Current.Name, Theme.AccentHex); })));
        }

        void WidgetsPage(StackPanel c)
        {
            c.Children.Add(Ui.Heading("Widgets", "Small cards on the desktop. Drag them by their title, resize from the corner."));
            c.Children.Add(Ui.Row("Show widgets", null, Ui.Toggle(Json.Bool(S.Widgets, "enabled"), on => { S.Widgets["enabled"] = on; Save(); if (on) Widgets.ShowEnabled(); else Widgets.CloseAll(); })));
            foreach (var item in S.WidgetItems.Select(Json.Obj).Where(i => i != null))
            {
                var it = item; string id = Json.Str(it, "id");
                c.Children.Add(Ui.Row(Widgets.Title(id), id == "media" ? "Play, pause, skip and volume for whatever is playing." : id == "timer" ? "5 to 50 minute focus timer with a sound at the end." : id == "system" ? "CPU, GPU, memory, disk and network, read from Windows." : null,
                    Ui.Toggle(Json.Bool(it, "enabled"), on => { it["enabled"] = on; if (on) S.Widgets["enabled"] = true; Save(); Widgets.ShowEnabled(); })));
            }
            var refresh = new Slider { Minimum = 2, Maximum = 30, Width = 220, Value = Json.Int(S.Widgets, "refreshSeconds", 3), TickFrequency = 1, IsSnapToTickEnabled = true };
            refresh.ValueChanged += (o, e) => { S.Widgets["refreshSeconds"] = (int)refresh.Value; Save(); };
            c.Children.Add(Ui.Row("System monitor refresh", "Seconds between reads.", refresh));
        }

        void WindowsPage(StackPanel c)
        {
            c.Children.Add(Ui.Heading("Windows integration", "BAKA replaces the taskbar, Start, desktop icons and folder windows. Windows File Explorer keeps running in the background only because Windows needs it for tray icons, notifications and file dialogs."));
            c.Children.Add(Ui.Row("Hide the Windows taskbar", "The menu bar and dock take its place. It comes back by itself if BAKA ever stops.", Ui.Toggle(App.TaskbarWanted, on => { S.Taskbar["autoHideWindowsTaskbar"] = on; Save(); App.ApplyIntegration(); })));
            c.Children.Add(Ui.Row("Windows key opens Launchpad", "Win+E opens BAKA Files, Win+S searches. Ctrl+Esc still opens the Windows Start menu.", Ui.Toggle(Json.Bool(S.Integration, "winKeyOpensLaunchpad", true), on => { S.Integration["winKeyOpensLaunchpad"] = on; Save(); App.ApplyIntegration(); })));
            c.Children.Add(Ui.Row("Folders open in BAKA Files", "Folders opened from any app, the desktop or a download open in BAKA Files instead of File Explorer.", Ui.Toggle(Json.Bool(S.Integration, "filesOpensFolders", true), on => { S.Integration["filesOpensFolders"] = on; Save(); App.ApplyIntegration(); })));
            c.Children.Add(Ui.Row("BAKA buttons on every window", "Close, minimize and maximize in BAKA colours on other apps' windows too. Nothing is loaded into the apps; windows with their own title bar style, admin windows and games keep theirs.", Ui.Toggle(Json.Bool(S.Integration, "captionButtons", true), on => { S.Integration["captionButtons"] = on; Save(); App.ApplyIntegration(); })));
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

        void PowerPage(StackPanel c)
        {
            c.Children.Add(Ui.Heading("Power", "Power plan and profiles. Games switch to Gaming by themselves."));
            var plans = PowerPlans.List();
            if (plans.Count > 0) c.Children.Add(Ui.Row("Power plan", "BAKA Gaming: Ultimate Performance tuned for games (no core parking, no USB sleep).", Ui.Choice(plans.Select(p => p.name), plans.FirstOrDefault(p => p.active).name, n => PowerPlans.Activate(plans.First(p => p.name == n).guid))));
            c.Children.Add(Ui.Row("Profile", null, Ui.Choice(new[] { "Desktop", "Gaming", "Benchmark" }, Profiles.Active == "CompetitiveGaming" ? "Gaming" : Profiles.Active, v => { string p = v == "Gaming" ? "CompetitiveGaming" : v; Profiles.Manual = p == "Desktop" ? null : p; Profiles.Set(p, "settings"); })));
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
