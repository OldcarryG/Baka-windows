using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace Baka.Desktop
{
    // Desktop widgets: clock, calendar, a cyan-metered system monitor, GPU, network, storage, media,
    // notes, a focus timer, quick toggles and search. They sit on the desktop below every window, move by
    // their title strip, resize by the grip, and stop updating while hidden or in a game.
    static class Widgets
    {
        public static readonly Dictionary<string, WidgetWindow> Open = new Dictionary<string, WidgetWindow>();
        public static string Title(string id) => id switch
        {
            "clock" => "Clock", "calendar" => "Calendar", "system" => "System", "gpu" => "GPU", "network" => "Network",
            "storage" => "Storage", "notes" => "Notes", "media" => "Media", "timer" => "Focus timer", "toggles" => "Quick toggles", "search" => "Search", _ => "Widget"
        };
        public static readonly string[] Ids = { "clock", "calendar", "system", "gpu", "network", "storage", "notes", "media", "timer", "toggles", "search" };

        public static void ShowEnabled()
        {
            if (App.GameRunning) return;
            bool master = Json.Bool(App.Settings.Widgets, "enabled");
            foreach (var item in App.Settings.WidgetItems.Select(Json.Obj).Where(i => i != null))
            {
                string id = Json.Str(item, "id");
                bool on = master && Json.Bool(item, "enabled");
                // widgets fade and rise into place one after another (desktop profile only)
                if (on && !Open.ContainsKey(id)) { var w = new WidgetWindow(item); Open[id] = w; w.Closed += (o, e) => Open.Remove(id); w.Show(); Ui.FadeIn(w.Frame, 260, 0.94, 12, 50 * Open.Count); }
                else if (on && !Open[id].IsVisible) { Open[id].Show(); Ui.FadeIn(Open[id].Frame, 260, 0.94, 12, 50 * Open.Count); }
                else if (!on && Open.ContainsKey(id)) Open[id].Close();
            }
        }
        public static void HideAll() { foreach (var w in Open.Values.ToList()) w.Hide(); }
        public static void CloseAll() { foreach (var w in Open.Values.ToList()) w.Close(); }
    }

    class WidgetWindow : GlassPanel
    {
        readonly Dictionary<string, object> item;
        readonly string id;
        TextBlock time, date, timerText; Button timerStart;
        int timerMinutes = 25, timerLeft = 25 * 60; DateTime timerEnd; bool timerRunning;
        System.Windows.Threading.DispatcherTimer saveLater;
        readonly List<Action<Metrics>> meters = new List<Action<Metrics>>();

        public WidgetWindow(Dictionary<string, object> item) : base(20)
        {
            this.item = item; id = Json.Str(item, "id");
            Title = "BAKA " + Widgets.Title(id); ShowActivated = false;
            // Each widget is a bubble the size of what it shows: a fixed width that suits its content and a
            // height that follows it, so there is no empty card around it. Only Notes is resizable (it is a
            // text box, its size is your choice).
            if (id == "notes")
            {
                ResizeMode = ResizeMode.CanResizeWithGrip; MinWidth = 220; MinHeight = 140; MaxWidth = 760; MaxHeight = 760;
                Width = Math.Max(220, Json.Int(item, "width", 300)); Height = Math.Max(140, Json.Int(item, "height", 190));
            }
            else
            {
                ResizeMode = ResizeMode.NoResize;
                double w = NaturalWidth(id);
                if (w > 0) { Width = w; SizeToContent = SizeToContent.Height; } else SizeToContent = SizeToContent.WidthAndHeight;
            }
            double left = Json.Int(item, "left", 130);
            if (Json.Str(App.Settings.Dock, "alignment", "Left") == "Left" && left < 110) left = 130; // keep clear of the left dock
            Left = SystemParameters.WorkArea.Left + left; Top = SystemParameters.WorkArea.Top + Json.Int(item, "top", 20);
            Build();
            Theme.Changed += OnTheme; Closed += (o, e) => { Theme.Changed -= OnTheme; App.Tick -= OnTick; };
            App.Tick += OnTick;
            Activated += (o, e) => Pin(true); SourceInitialized += (o, e) => Pin(true);
            saveLater = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(600) };
            saveLater.Tick += (o, e) => { saveLater.Stop(); Save(); };
            SizeChanged += (o, e) => { saveLater.Stop(); saveLater.Start(); };
        }
        void OnTheme() { Paint(); Build(); }
        // The width each widget's content needs (0 = as wide as its content).
        static double NaturalWidth(string id) => id switch
        {
            "clock" => 0, "calendar" => 250, "system" => 260, "gpu" => 230, "network" => 220, "storage" => 230,
            "media" => 300, "timer" => 250, "toggles" => 290, "search" => 320, _ => 260
        };
        // Background: the theme's glass, or the colour / picture / video chosen in Settings > Appearance.
        // Each widget can have its own (Settings > Appearance > Backgrounds), or share the "Widgets" one.
        public override void Paint() { base.Paint(); var b = Surfaces.Background("widget:" + (id ?? "")); if (b != null) Frame.Background = b; }

        void Build()
        {
            meters.Clear();
            var g = new Grid { Margin = new Thickness(14, 12, 14, 14) };
            g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); g.RowDefinitions.Add(new RowDefinition());
            var head = new Grid { Background = Brushes.Transparent, Cursor = Cursors.SizeAll, Margin = new Thickness(2, 0, 0, 8) };
            head.Children.Add(Ui.Text(Widgets.Title(id), 11.5, FontWeights.SemiBold, Theme.Muted));
            // No close button on the card; right-click hides it, Settings > Widgets turns it back on.
            head.MouseLeftButtonDown += (o, e) => { if (e.ButtonState == MouseButtonState.Pressed) { Drag(); Save(); } };
            head.MouseRightButtonUp += (o, e) =>
            {
                e.Handled = true;
                Ui.ShowMenu(head,
                    Ui.Item("Hide this widget", 0xE711, () => { item["enabled"] = false; App.Settings.Save(); Close(); }),
                    Ui.Item("Widget settings", 0xE713, () => SettingsWindow.Open("Widgets")));
            };
            g.Children.Add(head);
            var body = new StackPanel(); Grid.SetRow(body, 1); g.Children.Add(body);
            switch (id)
            {
                case "clock":
                    time = Ui.Text(DateTime.Now.ToString("HH:mm"), 46, FontWeights.SemiBold); body.Children.Add(time);
                    date = Ui.Text(DateTime.Now.ToString("dddd, d MMMM yyyy"), 12.5, null, Theme.Muted); body.Children.Add(date); break;
                case "calendar": BuildCalendar(body); break;
                case "system":
                    body.Children.Add(Bar("CPU", m => (m.Cpu == null ? "—" : m.Cpu + "%", (m.Cpu ?? 0) / 100.0)));
                    body.Children.Add(Bar("GPU", m => (m.Gpu == null ? "—" : m.Gpu + "%", (m.Gpu ?? 0) / 100.0)));
                    body.Children.Add(Bar("RAM", m => (m.MemoryPercent == null ? "—" : m.MemoryUsedGb.ToString("0.0") + "/" + m.MemoryTotalGb.ToString("0") + "G", (m.MemoryPercent ?? 0) / 100.0)));
                    body.Children.Add(Bar("NET", m => ("\u2193" + Speed(m.DownKBs), Math.Min(1, m.DownKBs / 12000.0)))); break;
                case "gpu":
                    var big = Ui.Text("—", 44, FontWeights.SemiBold, Theme.Data); big.HorizontalAlignment = HorizontalAlignment.Left; body.Children.Add(big);
                    var sub = Ui.Text("GPU utilisation", 12, null, Theme.Muted); body.Children.Add(sub);
                    meters.Add(m => big.Text = m.Gpu == null ? "N/A" : m.Gpu + "%");
                    body.Children.Add(Bar("GPU", m => (m.Gpu == null ? "—" : m.Gpu + "%", (m.Gpu ?? 0) / 100.0)));
                    body.Children.Add(Bar("CPU", m => (m.Cpu == null ? "—" : m.Cpu + "%", (m.Cpu ?? 0) / 100.0)));
                    var note = Ui.Muted("Temperature and FPS need vendor tools, not shown.", 10); note.Margin = new Thickness(0, 4, 0, 0); body.Children.Add(note); break;
                case "network":
                    var down = Ui.Text("\u2193 —", 30, FontWeights.SemiBold, Theme.Data); body.Children.Add(down);
                    var up = Ui.Text("\u2191 —", 26, FontWeights.SemiBold); up.Margin = new Thickness(0, 2, 0, 0); body.Children.Add(up);
                    meters.Add(m => { down.Text = "\u2193 " + Speed(m.DownKBs); up.Text = "\u2191 " + Speed(m.UpKBs); }); break;
                case "storage":
                    var free = Ui.Text("—", 30, FontWeights.SemiBold); body.Children.Add(free);
                    var of = Ui.Text("", 12, null, Theme.Muted); body.Children.Add(of);
                    body.Children.Add(Bar("Used", m => (m.DiskTotalGb <= 0 ? "—" : (100 - (int)Math.Round(m.DiskFreeGb / m.DiskTotalGb * 100)) + "%", m.DiskTotalGb <= 0 ? 0 : 1 - m.DiskFreeGb / m.DiskTotalGb)));
                    meters.Add(m => { free.Text = m.DiskFreeGb.ToString("0") + " GB free"; of.Text = "of " + m.DiskTotalGb.ToString("0") + " GB"; }); break;
                case "notes": BuildNotes(body); break;
                case "media": BuildMedia(body); break;
                case "timer": BuildTimer(body); break;
                case "toggles": BuildToggles(body); break;
                case "search": BuildSearch(body); break;
            }
            Content = g;
            OnTick();
        }

        // A labelled progress bar with a cyan fill; the updater is run every refresh with the latest metrics.
        FrameworkElement Bar(string label, Func<Metrics, (string text, double pct)> read)
        {
            var row = new Grid { Margin = new Thickness(0, 0, 0, 9) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(42) });
            row.ColumnDefinitions.Add(new ColumnDefinition());
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            row.RowDefinitions.Add(new RowDefinition { Height = new GridLength(7) });
            var lab = Ui.Text(label, 11, FontWeights.SemiBold, Theme.Muted); row.Children.Add(lab);
            var val = Ui.Text("—", 12, FontWeights.SemiBold); val.HorizontalAlignment = HorizontalAlignment.Right; Grid.SetColumn(val, 2); row.Children.Add(val);
            var track = new Border { Height = 7, CornerRadius = new CornerRadius(3.5), Background = Theme.B(Theme.Current.SurfaceAlt, 150), Margin = new Thickness(0, 5, 0, 0) };
            Grid.SetRow(track, 1); Grid.SetColumnSpan(track, 3); row.Children.Add(track);
            var fill = new Border { Height = 7, CornerRadius = new CornerRadius(3.5), Background = Theme.Data, HorizontalAlignment = HorizontalAlignment.Left, Width = 0 };
            track.Child = fill;
            meters.Add(m =>
            {
                var (t, p) = read(m); val.Text = t;
                double w = track.ActualWidth > 0 ? track.ActualWidth : ActualWidth - 44;
                fill.Width = Math.Max(0, w * Math.Max(0, Math.Min(1, p)));
            });
            return row;
        }

        void BuildCalendar(StackPanel body)
        {
            var cal = new System.Windows.Controls.Primitives.UniformGrid { Columns = 7 };
            var first = new DateTime(DateTime.Today.Year, DateTime.Today.Month, 1);
            body.Children.Add(Ui.Text(first.ToString("MMMM yyyy"), 14, FontWeights.SemiBold));
            foreach (var d in new[] { "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" }) { var t = Ui.Text(d, 10, FontWeights.Bold, Theme.Muted); t.HorizontalAlignment = HorizontalAlignment.Center; cal.Children.Add(t); }
            for (int i = 0; i < ((int)first.DayOfWeek + 6) % 7; i++) cal.Children.Add(new Border());
            for (int day = 1; day <= DateTime.DaysInMonth(first.Year, first.Month); day++)
            {
                bool today = day == DateTime.Today.Day;
                var t = Ui.Text(day.ToString(), 12, today ? FontWeights.Bold : FontWeights.Normal, today ? Theme.OnColor(Theme.AccentHex) : Theme.Text); t.HorizontalAlignment = HorizontalAlignment.Center; t.VerticalAlignment = VerticalAlignment.Center;
                cal.Children.Add(new Border { Height = 26, CornerRadius = new CornerRadius(13), Background = today ? Theme.Accent : Brushes.Transparent, Child = t });
            }
            cal.Margin = new Thickness(0, 6, 0, 0); body.Children.Add(cal);
        }

        void BuildNotes(StackPanel body)
        {
            var box = new TextBox { AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, MinHeight = 90, Height = Math.Max(90, Height - 70) };
            try { if (File.Exists(Paths.Notes)) box.Text = File.ReadAllText(Paths.Notes); } catch { }
            var save = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            save.Tick += (o, e) => { save.Stop(); try { File.WriteAllText(Paths.Notes, box.Text); } catch { } };
            box.TextChanged += (o, e) => { save.Stop(); save.Start(); };
            SizeChanged += (o, e) => box.Height = Math.Max(90, ActualHeight - 70);
            body.Children.Add(box);
            var hint = Ui.Muted("Saved automatically on this PC.", 10.5); hint.Margin = new Thickness(2, 4, 0, 0); body.Children.Add(hint);
        }

        // Album art, title, artist and the app it plays in, from Windows' media controls; the buttons act on
        // that app (media keys when Windows can't tell what is playing).
        Border mediaArt; TextBlock mediaTitle, mediaArtist, mediaSource; Button mediaPlay; bool mediaHooked;
        void BuildMedia(StackPanel body)
        {
            var top = new Grid();
            top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            top.ColumnDefinitions.Add(new ColumnDefinition());
            mediaArt = new Border { Width = 76, Height = 76, CornerRadius = new CornerRadius(14), Margin = new Thickness(0, 0, 12, 0), ClipToBounds = true };
            top.Children.Add(mediaArt);
            var info = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            mediaTitle = Ui.Text("", 14, FontWeights.SemiBold); info.Children.Add(mediaTitle);
            mediaArtist = Ui.Text("", 12, null, Theme.Muted); mediaArtist.Margin = new Thickness(0, 2, 0, 0); info.Children.Add(mediaArtist);
            mediaSource = Ui.Text("", 10.5, FontWeights.SemiBold, Theme.Data); mediaSource.Margin = new Thickness(0, 5, 0, 0); info.Children.Add(mediaSource);
            Grid.SetColumn(info, 1); top.Children.Add(info);
            body.Children.Add(top);
            var controls = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 10, 0, 0) };
            controls.Children.Add(Round(0xE892, "Previous track", NowPlaying.Previous, 36));
            mediaPlay = Round(0xE768, "Play or pause", NowPlaying.PlayPause, 46); controls.Children.Add(mediaPlay);
            controls.Children.Add(Round(0xE893, "Next track", NowPlaying.Next, 36));
            body.Children.Add(controls);
            if (!mediaHooked) { mediaHooked = true; NowPlaying.Changed += UpdateMedia; Closed += (o, e) => NowPlaying.Changed -= UpdateMedia; }
            UpdateMedia();
        }
        void UpdateMedia()
        {
            if (mediaTitle == null) return;
            bool has = NowPlaying.HasMedia;
            mediaTitle.Text = has ? NowPlaying.Title : "Nothing playing";
            mediaArtist.Text = has ? NowPlaying.Artist : "Play something in any app";
            mediaSource.Text = has ? NowPlaying.Source : "";
            if (NowPlaying.Art != null) { mediaArt.Child = null; mediaArt.Background = new ImageBrush(NowPlaying.Art) { Stretch = Stretch.UniformToFill }; }
            else { mediaArt.Background = Theme.B(Theme.Current.SurfaceAlt, 170); mediaArt.Child = Ui.Glyph(0xE8D6, 30, Theme.Muted); }
            if (mediaPlay?.Content is TextBlock g) g.Text = char.ConvertFromUtf32(NowPlaying.Playing ? 0xE769 : 0xE768);
        }

        void BuildTimer(StackPanel body)
        {
            timerText = Ui.Text(Format(timerLeft), 38, FontWeights.SemiBold); timerText.HorizontalAlignment = HorizontalAlignment.Center; body.Children.Add(timerText);
            var presets = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 2, 0, 0) };
            foreach (int min in new[] { 5, 15, 25, 50 }) { int m = min; var p = Ui.Button(m + "m", () => { timerRunning = false; timerMinutes = m; timerLeft = m * 60; UpdateTimer(); }, false, 9, new Thickness(9, 3, 9, 3)); p.Margin = new Thickness(2); presets.Children.Add(p); }
            body.Children.Add(presets);
            var controls = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 8, 0, 0) };
            timerStart = Round(0xE768, "Start or pause", ToggleTimer, 40); controls.Children.Add(timerStart);
            controls.Children.Add(Round(0xE72C, "Reset", () => { timerRunning = false; timerLeft = timerMinutes * 60; UpdateTimer(); }, 40));
            body.Children.Add(controls); UpdateTimer();
        }

        void BuildToggles(StackPanel body)
        {
            var grid = new System.Windows.Controls.Primitives.UniformGrid { Columns = 2, Margin = new Thickness(0, 2, 0, 0) };
            grid.Children.Add(Toggle(0xE74F, "Mute", () => { try { Audio.SetMuted(!Audio.Muted); } catch { } }));
            grid.Children.Add(Toggle(0xE7FC, "Game mode", () =>
            {
                App.SetProfileByHand(Profiles.Active == "CompetitiveGaming" ? "Desktop" : "CompetitiveGaming", "widget");
            }));
            grid.Children.Add(Toggle(0xE995, "Volume up", () => Native.SendMediaKey(0xAF)));
            grid.Children.Add(Toggle(0xE993, "Volume down", () => Native.SendMediaKey(0xAE)));
            grid.Children.Add(Toggle(0xE9E9, "Control Center", () => ControlCenter.Toggle(this)));
            grid.Children.Add(Toggle(0xE713, "Settings", () => SettingsWindow.Open()));
            body.Children.Add(grid);
        }
        FrameworkElement Toggle(int glyph, string label, Action click)
        {
            var sp = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            sp.Children.Add(Ui.Glyph(glyph, 15)); var t = Ui.Text(label, 11.5); t.Margin = new Thickness(8, 0, 0, 0); t.VerticalAlignment = VerticalAlignment.Center; sp.Children.Add(t);
            var b = new Border { Child = sp, Height = 40, CornerRadius = new CornerRadius(12), Background = Theme.B(Theme.Current.SurfaceAlt, 150), Padding = new Thickness(12, 0, 10, 0), Margin = new Thickness(3), Cursor = Cursors.Hand };
            b.MouseEnter += (o, e) => b.Background = Theme.Hover; b.MouseLeave += (o, e) => b.Background = Theme.B(Theme.Current.SurfaceAlt, 150);
            Ui.OnClick(b, () => { try { click(); } catch (Exception ex) { Log.Write("toggle-widget-failed error=\"" + ex.Message + "\""); } });
            System.Windows.Automation.AutomationProperties.SetName(b, label);
            return b;
        }

        void BuildSearch(StackPanel body)
        {
            var sp = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            sp.Children.Add(Ui.Glyph(0xE721, 16, Theme.Muted)); var t = Ui.Text("Search apps, files, settings\u2026", 13, null, Theme.Muted); t.Margin = new Thickness(10, 0, 0, 0); t.VerticalAlignment = VerticalAlignment.Center; sp.Children.Add(t);
            var box = new Border { Child = sp, Height = 44, CornerRadius = new CornerRadius(22), Background = Theme.B(Theme.Current.SurfaceAlt, 170), Padding = new Thickness(16, 0, 16, 0), Cursor = Cursors.Hand, Margin = new Thickness(0, 6, 0, 0) };
            box.MouseEnter += (o, e) => box.Background = Theme.Hover; box.MouseLeave += (o, e) => box.Background = Theme.B(Theme.Current.SurfaceAlt, 170);
            Ui.OnClick(box, () => Launchpad.Toggle(true));
            body.Children.Add(box);
            var hint = Ui.Muted("Opens the Launchpad search.", 10.5); hint.Margin = new Thickness(2, 6, 0, 0); body.Children.Add(hint);
        }

        static Button Round(int glyph, string tip, Action click, double size)
        {
            var b = Ui.Button(Ui.Glyph(glyph, size * 0.38), click, false, size / 2, new Thickness(0)); b.Width = b.Height = size; b.Margin = new Thickness(4, 0, 4, 0); b.ToolTip = tip;
            System.Windows.Automation.AutomationProperties.SetName(b, tip); return b;
        }
        static string Format(int s) => (s / 60).ToString("00") + ":" + (s % 60).ToString("00");
        public void ToggleTimer()
        {
            if (timerRunning) { timerRunning = false; timerLeft = Math.Max(0, (int)Math.Ceiling((timerEnd - DateTime.UtcNow).TotalSeconds)); }
            else { if (timerLeft <= 0) timerLeft = timerMinutes * 60; timerEnd = DateTime.UtcNow.AddSeconds(timerLeft); timerRunning = true; Log.Write("focus-timer-started seconds=" + timerLeft); }
            UpdateTimer();
        }
        public bool TimerRunning => timerRunning;
        public int TimerLeft => timerLeft;
        public string TimerText => timerText?.Text;
        public void FinishTimerForTest() { timerEnd = DateTime.UtcNow.AddSeconds(-1); OnTick(); }
        void UpdateTimer() { if (timerText == null) return; timerText.Text = timerLeft <= 0 && !timerRunning ? "Done" : Format(timerLeft); if (timerStart?.Content is TextBlock g) g.Text = char.ConvertFromUtf32(timerRunning ? 0xE769 : 0xE768); }

        int ticks;
        void OnTick()
        {
            if (!IsVisible && time == null && timerText == null && meters.Count == 0) return;
            if (time != null) { time.Text = DateTime.Now.ToString("HH:mm"); date.Text = DateTime.Now.ToString("dddd, d MMMM yyyy"); }
            if (timerRunning)
            {
                timerLeft = (int)Math.Ceiling((timerEnd - DateTime.UtcNow).TotalSeconds);
                if (timerLeft <= 0) { timerRunning = false; timerLeft = 0; try { System.Media.SystemSounds.Asterisk.Play(); } catch { } Log.Write("focus-timer-finished minutes=" + timerMinutes); }
                UpdateTimer();
            }
            if (meters.Count > 0 && IsVisible && !App.GameRunning && ++ticks % Math.Max(2, Json.Int(App.Settings.Widgets, "refreshSeconds", 3)) == 0)
            {
                var m = Metrics.Latest();
                foreach (var u in meters) { try { u(m); } catch { } }
            }
        }
        static string Speed(double kb) => kb > 1024 ? (kb / 1024).ToString("0.0") + " MB/s" : kb.ToString("0") + " KB/s";

        void Save()
        {
            var area = SystemParameters.WorkArea;
            item["left"] = (int)Math.Max(0, Left - area.Left); item["top"] = (int)Math.Max(0, Top - area.Top);
            // only Notes has a size of its own; the others follow their content
            if (id == "notes") { item["width"] = (int)Math.Max(220, Math.Min(760, ActualWidth)); item["height"] = (int)Math.Max(140, Math.Min(760, ActualHeight)); }
            App.Settings.Save();
        }
    }
}
