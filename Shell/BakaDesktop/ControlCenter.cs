using System;
using System.Globalization;
using System.Linq;
using System.Management;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace Baka.Desktop
{
    // Control Center: network, Bluetooth, focus, volume, brightness, profile, power plan, theme, media and
    // power, in one panel under the menu bar.
    class ControlCenter : GlassPanel
    {
        static ControlCenter current;
        public static bool IsOpen => current != null && current.IsVisible;
        public static ControlCenter Current => current;
        Slider volume; Button mute;

        public static void Toggle(Window anchor)
        {
            if (IsOpen) { current.Close(); return; }
            current = new ControlCenter();
            current.Left = SystemParameters.PrimaryScreenWidth - current.Width - 10; current.Top = TopBar.BarHeight + 8;
            current.Show(); current.Activate();
        }
        ControlCenter() : base(20)
        {
            Title = "BAKA Control Center"; Width = 380; SizeToContent = SizeToContent.Height; Topmost = true;
            Build();
            Deactivated += (o, e) => { if (!SelfTest.Running) Close(); };
            KeyDown += (o, e) => { if (e.Key == Key.Escape) Close(); };
            Closed += (o, e) => { if (current == this) current = null; };
            Ui.FadeIn(Frame, 150);
        }

        void Build()
        {
            var sp = new StackPanel { Margin = new Thickness(14) };
            var quick = new UniformGrid4();
            quick.Add(Quick(0xE701, "Wi-Fi", "ms-availablenetworks:")); quick.Add(Quick(0xE702, "Bluetooth", "ms-settings:bluetooth"));
            quick.Add(Quick(0xE708, "Focus", "ms-settings:quiethours")); quick.Add(Quick(0xE706, "Night light", "ms-settings:nightlight"));
            quick.Add(QuickAction(0xE70E, "Tray", App.PeekTray)); quick.Add(QuickAction(0xE7F4, "Display", () => Run("ms-settings:display")));
            quick.Add(QuickAction(0xE72E, "Ad block", () => SettingsWindow.Open("Privacy & ads"))); quick.Add(QuickAction(0xE713, "Settings", () => Run("ms-settings:")));
            sp.Children.Add(quick.Panel);

            sp.Children.Add(Caption("Sound"));
            var vr = new Grid(); vr.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); vr.ColumnDefinitions.Add(new ColumnDefinition()); vr.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            mute = Ui.Icon(Audio.Muted ? 0xE74F : 0xE995, "Mute", () => { Audio.SetMuted(!Audio.Muted); UpdateVolume(); }, 32, 14); vr.Children.Add(mute);
            volume = new Slider { Minimum = 0, Maximum = 100, Value = Audio.Level ?? 50, Margin = new Thickness(8, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center };
            volume.ValueChanged += (o, e) => { Audio.SetLevel((int)volume.Value); UpdateVolume(); };
            Grid.SetColumn(volume, 1); vr.Children.Add(volume);
            var outDev = Ui.Icon(0xE7F5, "Sound output", () => Run("ms-settings:sound"), 32, 13); Grid.SetColumn(outDev, 2); vr.Children.Add(outDev);
            sp.Children.Add(vr);
            int? bright = Brightness.Get();
            if (bright != null)
            {
                sp.Children.Add(Caption("Brightness"));
                var b = new Slider { Minimum = 0, Maximum = 100, Value = bright.Value, Margin = new Thickness(40, 0, 40, 0) };
                b.ValueChanged += (o, e) => Brightness.Set((int)b.Value);
                sp.Children.Add(b);
            }
            sp.Children.Add(Caption("Media"));
            var media = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
            media.Children.Add(Ui.Icon(0xE892, "Previous", () => Native.SendMediaKey(0xB1), 36, 14));
            media.Children.Add(Ui.Icon(0xE768, "Play / pause", () => Native.SendMediaKey(0xB3), 42, 17));
            media.Children.Add(Ui.Icon(0xE893, "Next", () => Native.SendMediaKey(0xB0), 36, 14));
            sp.Children.Add(media);

            sp.Children.Add(Caption("Profile"));
            sp.Children.Add(Ui.Choice(new[] { "Desktop", "Gaming", "Benchmark" }, Profiles.Active == "CompetitiveGaming" ? "Gaming" : Profiles.Active, v =>
            {
                string p = v == "Gaming" ? "CompetitiveGaming" : v;
                Profiles.Manual = p == "Desktop" ? null : p;
                Profiles.Set(p, "manual");
            }));
            var plans = PowerPlans.List();
            if (plans.Count > 0)
            {
                sp.Children.Add(Caption("Power plan"));
                sp.Children.Add(Ui.Choice(plans.Select(p => p.name), plans.FirstOrDefault(p => p.active).name, name => PowerPlans.Activate(plans.First(p => p.name == name).guid)));
            }
            sp.Children.Add(Caption("Theme"));
            var swatches = new WrapPanel();
            foreach (var t in Theme.All)
            {
                var theme = t;
                var sw = new Border { Width = 26, Height = 26, CornerRadius = new CornerRadius(13), Margin = new Thickness(0, 0, 7, 7), Cursor = Cursors.Hand, ToolTip = t.Name, BorderThickness = new Thickness(t == Theme.Current ? 2.5 : 1), BorderBrush = t == Theme.Current ? Theme.Text : Theme.Border };
                var g = new LinearGradientBrush(Theme.C(t.Surface), Theme.C(t.Accent), 45); g.Freeze(); sw.Background = g;
                sw.MouseLeftButtonUp += (o, e) => { App.Settings.Appearance["theme"] = theme.Name; App.Settings.Appearance["accentColor"] = theme.Accent; App.Settings.Save(); Theme.Apply(theme.Name, theme.Accent); Build(); };
                swatches.Children.Add(sw);
            }
            sp.Children.Add(swatches);
            var row = new Grid { Margin = new Thickness(0, 6, 0, 0) }; row.ColumnDefinitions.Add(new ColumnDefinition()); row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.Children.Add(Ui.Text("Desktop widgets", 13));
            var tog = Ui.Toggle(Json.Bool(App.Settings.Widgets, "enabled"), on => { App.Settings.Widgets["enabled"] = on; App.Settings.Save(); if (on) Widgets.ShowEnabled(); else Widgets.HideAll(); });
            Grid.SetColumn(tog, 1); row.Children.Add(tog);
            sp.Children.Add(row);

            var power = new UniformGrid4 { Columns = 4 };
            power.Add(QuickAction(0xE72E, "Lock", () => Native.LockWorkStation())); power.Add(QuickAction(0xE708, "Sleep", Power.Sleep));
            power.Add(QuickAction(0xE777, "Restart", Power.Restart)); power.Add(QuickAction(0xE7E8, "Shut down", Power.Shutdown));
            power.Panel.Margin = new Thickness(0, 14, 0, 0);
            sp.Children.Add(power.Panel);
            Content = sp;
            UpdateVolume();
        }
        void UpdateVolume() { if (mute?.Content is TextBlock t) t.Text = char.ConvertFromUtf32(Audio.Muted || volume?.Value == 0 ? 0xE74F : 0xE995); }
        static TextBlock Caption(string t) { var c = Ui.Text(t.ToUpperInvariant(), 10.5, FontWeights.Bold, Theme.Muted); c.Margin = new Thickness(2, 14, 0, 6); return c; }
        static void Run(string uri) { try { System.Diagnostics.Process.Start(uri); } catch { } }
        FrameworkElement Quick(int glyph, string label, string uri) => QuickAction(glyph, label, () => { Close(); Run(uri); });
        FrameworkElement QuickAction(int glyph, string label, Action act)
        {
            var sp = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center };
            var circle = new Border { Width = 44, Height = 44, CornerRadius = new CornerRadius(14), Background = Theme.SurfaceAlt, BorderBrush = Theme.Border, BorderThickness = new Thickness(1), Child = Ui.Glyph(glyph, 16), HorizontalAlignment = HorizontalAlignment.Center };
            sp.Children.Add(circle);
            var t = Ui.Text(label, 10.5, null, Theme.Muted); t.HorizontalAlignment = HorizontalAlignment.Center; t.Margin = new Thickness(0, 5, 0, 0); sp.Children.Add(t);
            var b = new Border { Child = sp, Cursor = Cursors.Hand, Padding = new Thickness(2, 4, 2, 4), Background = Brushes.Transparent, ToolTip = label };
            b.MouseEnter += (o, e) => circle.Background = Theme.B(Theme.AccentHex, 70); b.MouseLeave += (o, e) => circle.Background = Theme.SurfaceAlt;
            Ui.OnClick(b, () => { try { act(); } catch (Exception ex) { Log.Write("control-center-failed item=" + label + " error=\"" + ex.Message + "\""); } });
            System.Windows.Automation.AutomationProperties.SetName(b, label);
            return b;
        }
        class UniformGrid4
        {
            public readonly System.Windows.Controls.Primitives.UniformGrid Panel = new System.Windows.Controls.Primitives.UniformGrid { Columns = 4 };
            public int Columns { set => Panel.Columns = value; }
            public void Add(UIElement e) => Panel.Children.Add(e);
        }
    }

    // Laptop screen brightness (WMI); not shown on desktop monitors.
    static class Brightness
    {
        public static int? Get()
        {
            try { using (var s = new ManagementObjectSearcher(@"root\WMI", "SELECT CurrentBrightness FROM WmiMonitorBrightness")) foreach (ManagementObject o in s.Get()) return Convert.ToInt32(o["CurrentBrightness"]); } catch { }
            return null;
        }
        public static void Set(int v)
        {
            try { using (var s = new ManagementObjectSearcher(@"root\WMI", "SELECT * FROM WmiMonitorBrightnessMethods")) foreach (ManagementObject o in s.Get()) o.InvokeMethod("WmiSetBrightness", new object[] { 1, (byte)Math.Max(0, Math.Min(100, v)) }); } catch { }
        }
    }

    // The month calendar under the clock.
    class CalendarFlyout : GlassPanel
    {
        static CalendarFlyout current;
        DateTime month = new DateTime(DateTime.Today.Year, DateTime.Today.Month, 1);
        public static void Toggle(Window anchor)
        {
            if (current != null && current.IsVisible) { current.Close(); return; }
            current = new CalendarFlyout();
            current.Left = SystemParameters.PrimaryScreenWidth - current.Width - 150; current.Top = TopBar.BarHeight + 8;
            current.Show(); current.Activate();
        }
        CalendarFlyout() : base(18)
        {
            Title = "BAKA Calendar"; Width = 320; SizeToContent = SizeToContent.Height; Topmost = true;
            Build();
            Deactivated += (o, e) => Close();
            KeyDown += (o, e) => { if (e.Key == Key.Escape) Close(); };
            Ui.FadeIn(Frame, 140);
        }
        void Build()
        {
            var sp = new StackPanel { Margin = new Thickness(14) };
            var big = Ui.Text(DateTime.Now.ToString("dddd"), 13, FontWeights.SemiBold, Theme.Accent); sp.Children.Add(big);
            sp.Children.Add(Ui.Text(DateTime.Now.ToString("d MMMM yyyy"), 20, FontWeights.SemiBold));
            var head = new Grid { Margin = new Thickness(0, 12, 0, 6) };
            head.Children.Add(Ui.Text(month.ToString("MMMM yyyy"), 13, FontWeights.SemiBold));
            var nav = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
            nav.Children.Add(Ui.Icon(0xE70E, "Previous month", () => { month = month.AddMonths(-1); Build(); }, 26, 10));
            nav.Children.Add(Ui.Icon(0xE70D, "Next month", () => { month = month.AddMonths(1); Build(); }, 26, 10));
            head.Children.Add(nav); sp.Children.Add(head);
            var grid = new System.Windows.Controls.Primitives.UniformGrid { Columns = 7 };
            var culture = CultureInfo.CurrentCulture; int first = (int)culture.DateTimeFormat.FirstDayOfWeek;
            for (int i = 0; i < 7; i++) { var d = Ui.Text(culture.DateTimeFormat.AbbreviatedDayNames[(first + i) % 7].Substring(0, 2), 10.5, FontWeights.Bold, Theme.Muted); d.HorizontalAlignment = HorizontalAlignment.Center; grid.Children.Add(d); }
            int offset = ((int)month.DayOfWeek - first + 7) % 7;
            for (int i = 0; i < offset; i++) grid.Children.Add(new Border());
            for (int day = 1; day <= DateTime.DaysInMonth(month.Year, month.Month); day++)
            {
                bool today = month.Year == DateTime.Today.Year && month.Month == DateTime.Today.Month && day == DateTime.Today.Day;
                var t = Ui.Text(day.ToString(), 12.5, today ? FontWeights.Bold : FontWeights.Normal, today ? Theme.OnColor(Theme.AccentHex) : Theme.Text); t.HorizontalAlignment = HorizontalAlignment.Center; t.VerticalAlignment = VerticalAlignment.Center;
                grid.Children.Add(new Border { Height = 32, Width = 32, CornerRadius = new CornerRadius(16), Background = today ? Theme.Accent : Brushes.Transparent, Child = t });
            }
            sp.Children.Add(grid);
            var settings = Ui.Labeled(0xE787, "Date and time settings", () => { Close(); try { System.Diagnostics.Process.Start("ms-settings:dateandtime"); } catch { } });
            settings.Margin = new Thickness(0, 10, 0, 0); settings.HorizontalAlignment = HorizontalAlignment.Left;
            sp.Children.Add(settings);
            Content = sp;
        }
    }
}
