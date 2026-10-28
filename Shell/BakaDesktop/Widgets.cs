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
    // Desktop widgets: clock, calendar, system monitor, notes, media and a focus timer. They sit on the
    // desktop below every window, move by their title strip, and stop updating while hidden or in a game.
    static class Widgets
    {
        public static readonly Dictionary<string, WidgetWindow> Open = new Dictionary<string, WidgetWindow>();
        public static string Title(string id) => id switch { "clock" => "Clock", "calendar" => "Calendar", "system" => "System monitor", "notes" => "Notes", "media" => "Media", "timer" => "Focus timer", _ => "Widget" };
        public static readonly string[] Ids = { "clock", "calendar", "system", "notes", "media", "timer" };

        public static void ShowEnabled()
        {
            if (App.GameRunning) return;
            bool master = Json.Bool(App.Settings.Widgets, "enabled");
            foreach (var item in App.Settings.WidgetItems.Select(Json.Obj).Where(i => i != null))
            {
                string id = Json.Str(item, "id");
                bool on = master && Json.Bool(item, "enabled");
                if (on && !Open.ContainsKey(id)) { var w = new WidgetWindow(item); Open[id] = w; w.Closed += (o, e) => Open.Remove(id); w.Show(); }
                else if (on && !Open[id].IsVisible) Open[id].Show();
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
        TextBlock time, date, readout, timerText; Button timerStart;
        int timerMinutes = 25, timerLeft = 25 * 60; DateTime timerEnd; bool timerRunning;
        System.Windows.Threading.DispatcherTimer saveLater;

        public WidgetWindow(Dictionary<string, object> item) : base(18)
        {
            this.item = item; id = Json.Str(item, "id");
            Title = "BAKA " + Widgets.Title(id); ShowActivated = false; ResizeMode = ResizeMode.CanResizeWithGrip;
            double minH = id == "clock" ? 150 : id == "media" ? 180 : id == "timer" ? 190 : 110;
            MinWidth = 200; MinHeight = minH; MaxWidth = 720; MaxHeight = 720;
            Width = Math.Max(200, Json.Int(item, "width", 260)); Height = Math.Max(minH, Json.Int(item, "height", 160));
            double left = Json.Int(item, "left", 104);
            if (Json.Str(App.Settings.Dock, "alignment", "Left") == "Left" && left < 100) left = 104; // older layouts sat under the dock
            Left = SystemParameters.WorkArea.Left + left; Top = SystemParameters.WorkArea.Top + Json.Int(item, "top", 48);
            Build();
            Theme.Changed += OnTheme; Closed += (o, e) => { Theme.Changed -= OnTheme; App.Tick -= OnTick; };
            App.Tick += OnTick;
            Activated += (o, e) => Pin(true); SourceInitialized += (o, e) => Pin(true);
            saveLater = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(600) };
            saveLater.Tick += (o, e) => { saveLater.Stop(); Save(); };
            SizeChanged += (o, e) => { saveLater.Stop(); saveLater.Start(); };
        }
        void OnTheme() { Paint(); Build(); }

        void Build()
        {
            var g = new Grid { Margin = new Thickness(10) };
            g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); g.RowDefinitions.Add(new RowDefinition());
            var head = new Grid { Background = Brushes.Transparent, Cursor = Cursors.SizeAll, Margin = new Thickness(2, 0, 0, 6) };
            head.Children.Add(Ui.Text(Widgets.Title(id), 11.5, FontWeights.SemiBold, Theme.Muted));
            var close = Ui.Icon(0xE711, "Hide this widget", () => { item["enabled"] = false; App.Settings.Save(); Close(); }, 22, 9); close.HorizontalAlignment = HorizontalAlignment.Right;
            head.Children.Add(close);
            head.MouseLeftButtonDown += (o, e) => { if (e.ButtonState == MouseButtonState.Pressed && !(e.OriginalSource is TextBlock tb && tb.Parent is Button)) { Drag(); Save(); } };
            g.Children.Add(head);
            var body = new StackPanel(); Grid.SetRow(body, 1); g.Children.Add(body);
            switch (id)
            {
                case "clock":
                    time = Ui.Text(DateTime.Now.ToString("HH:mm"), 44, FontWeights.SemiBold); body.Children.Add(time);
                    date = Ui.Text(DateTime.Now.ToString("dddd, d MMMM yyyy"), 12.5, null, Theme.Muted); body.Children.Add(date); break;
                case "calendar":
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
                    cal.Margin = new Thickness(0, 6, 0, 0); body.Children.Add(cal); break;
                case "system":
                    readout = Ui.Text("Reading Windows counters…", 12.5); readout.TextTrimming = TextTrimming.None; body.Children.Add(readout); Metrics.Read(); break;
                case "notes":
                    var box = new TextBox { AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, MinHeight = 90, Height = Math.Max(90, Height - 70) };
                    try { if (File.Exists(Paths.Notes)) box.Text = File.ReadAllText(Paths.Notes); } catch { }
                    var save = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
                    save.Tick += (o, e) => { save.Stop(); try { File.WriteAllText(Paths.Notes, box.Text); } catch { } };
                    box.TextChanged += (o, e) => { save.Stop(); save.Start(); };
                    SizeChanged += (o, e) => box.Height = Math.Max(90, ActualHeight - 70);
                    body.Children.Add(box);
                    var hint = Ui.Muted("Saved automatically on this PC.", 10.5); hint.Margin = new Thickness(2, 4, 0, 0); body.Children.Add(hint); break;
                case "media":
                    var m1 = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 6, 0, 0) };
                    m1.Children.Add(Round(0xE892, "Previous track", () => Native.SendMediaKey(0xB1), 38)); m1.Children.Add(Round(0xE768, "Play or pause", () => Native.SendMediaKey(0xB3), 48)); m1.Children.Add(Round(0xE893, "Next track", () => Native.SendMediaKey(0xB0), 38));
                    var m2 = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 10, 0, 0) };
                    m2.Children.Add(Round(0xE74F, "Mute", () => Native.SendMediaKey(0xAD), 34)); m2.Children.Add(Round(0xE993, "Volume down", () => Native.SendMediaKey(0xAE), 34)); m2.Children.Add(Round(0xE995, "Volume up", () => Native.SendMediaKey(0xAF), 34));
                    body.Children.Add(Ui.Muted("Controls whatever is playing: music, video, browser.", 10.5)); body.Children.Add(m1); body.Children.Add(m2); break;
                case "timer":
                    timerText = Ui.Text(Format(timerLeft), 38, FontWeights.SemiBold); timerText.HorizontalAlignment = HorizontalAlignment.Center; body.Children.Add(timerText);
                    var presets = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 2, 0, 0) };
                    foreach (int min in new[] { 5, 15, 25, 50 }) { int m = min; var p = Ui.Button(m + "m", () => { timerRunning = false; timerMinutes = m; timerLeft = m * 60; UpdateTimer(); }, false, 9, new Thickness(9, 3, 9, 3)); p.Margin = new Thickness(2); presets.Children.Add(p); }
                    body.Children.Add(presets);
                    var controls = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 8, 0, 0) };
                    timerStart = Round(0xE768, "Start or pause", ToggleTimer, 40); controls.Children.Add(timerStart);
                    controls.Children.Add(Round(0xE72C, "Reset", () => { timerRunning = false; timerLeft = timerMinutes * 60; UpdateTimer(); }, 40));
                    body.Children.Add(controls); UpdateTimer(); break;
            }
            Content = g;
            OnTick();
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
            if (!IsVisible && time == null && timerText == null) return;
            if (time != null) { time.Text = DateTime.Now.ToString("HH:mm"); date.Text = DateTime.Now.ToString("dddd, d MMMM yyyy"); }
            if (timerRunning)
            {
                timerLeft = (int)Math.Ceiling((timerEnd - DateTime.UtcNow).TotalSeconds);
                if (timerLeft <= 0) { timerRunning = false; timerLeft = 0; try { System.Media.SystemSounds.Asterisk.Play(); } catch { } Log.Write("focus-timer-finished minutes=" + timerMinutes); }
                UpdateTimer();
            }
            if (readout != null && IsVisible && !App.GameRunning && ++ticks % Math.Max(2, Json.Int(App.Settings.Widgets, "refreshSeconds", 3)) == 0)
            {
                var m = Metrics.Read();
                readout.Text = (m.Cpu == null ? "CPU —" : m.Cpu + "% CPU") + "\n" + (m.MemoryPercent == null ? "Memory —" : m.MemoryUsedGb.ToString("0.0") + " / " + m.MemoryTotalGb.ToString("0") + " GB memory (" + m.MemoryPercent + "%)") +
                    "\n" + (m.Gpu == null ? "GPU — (no counter)" : m.Gpu + "% GPU") + "\n" + m.DiskFreeGb.ToString("0") + " GB free of " + m.DiskTotalGb.ToString("0") + " GB" + "\n↓ " + Speed(m.DownKBs) + "   ↑ " + Speed(m.UpKBs) + (m.Battery != null ? "\nBattery " + m.Battery + "%" + (m.Charging ? " (charging)" : "") : "");
                Log.Write("metrics-read cpu=" + m.Cpu + " gpu=" + m.Gpu);
            }
        }
        static string Speed(double kb) => kb > 1024 ? (kb / 1024).ToString("0.0") + " MB/s" : kb.ToString("0") + " KB/s";

        void Save()
        {
            var area = SystemParameters.WorkArea;
            item["left"] = (int)Math.Max(0, Left - area.Left); item["top"] = (int)Math.Max(0, Top - area.Top);
            item["width"] = (int)Math.Max(200, Math.Min(720, ActualWidth)); item["height"] = (int)Math.Max(100, Math.Min(720, ActualHeight));
            App.Settings.Save();
        }
    }
}
