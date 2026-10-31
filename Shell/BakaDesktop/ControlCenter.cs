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
        Slider volume; Button mute; MixerPanel mixer;

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
            // Deactivated also fires while the window is already closing (a quick action closes it, which
            // deactivates it): a second Close() then threw "Cannot ... while a Window is closing" (logged).
            bool closing = false;
            Closing += (o, e) => closing = true;
            Deactivated += (o, e) => { if (!SelfTest.Running && !closing) { closing = true; try { Close(); } catch { } } };
            KeyDown += (o, e) => { if (e.Key == Key.Escape && !closing) Close(); };
            Closed += (o, e) => { if (current == this) current = null; mixer?.Dispose(); mixer = null; };
            Ui.FadeIn(Frame, 170, 0.96, -12); // drops down from the menu bar
        }

        void Build()
        {
            var sp = new StackPanel { Margin = new Thickness(14) };
            // Focus and the game overlay are switches with a state, so they get the wide tiles; the
            // Windows Focus settings page moved to Settings > Focus & games.
            var switches = new System.Windows.Controls.Primitives.UniformGrid { Columns = 2, Margin = new Thickness(0, 0, 0, 8) };
            switches.Children.Add(Switch(0xE708, "Focus", FocusMode.On, FocusMode.On ? "On  ·  no pop-ups" : "Off", () => FocusMode.Toggle("control center")));
            switches.Children.Add(Switch(0xEC4A, "Game overlay", GameOverlay.Enabled, !GameOverlay.Enabled ? "Off" : GameOverlay.When == "Always" ? "On" : "On in games", () => GameOverlay.SetEnabled(!GameOverlay.Enabled, "control center")));
            sp.Children.Add(switches);
            var quick = new UniformGrid4();
            quick.Add(QuickAction(0xE701, "Wi-Fi", () => { Close(); NetworkFlyout.Toggle(App.Bar); })); quick.Add(Quick(0xE702, "Bluetooth", "ms-settings:bluetooth"));
            quick.Add(QuickAction(0xE7FC, "Arena", () => { Close(); Arena.Open(); })); quick.Add(Quick(0xE706, "Night light", "ms-settings:nightlight"));
            quick.Add(QuickAction(0xE70E, "Tray", () => { Close(); TrayFlyout.Toggle(this); })); quick.Add(QuickAction(0xE7F4, "Display", () => Run("ms-settings:display")));
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
            // each app's own volume (Windows' volume mixer, in the panel)
            mixer?.Dispose();
            try { mixer = new MixerPanel(); mixer.Root.Margin = new Thickness(0, 6, 0, 0); sp.Children.Add(mixer.Root); }
            catch (Exception e) { Log.Write("mixer-failed error=\"" + e.Message + "\""); }
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
                App.SetProfileByHand(v == "Gaming" ? "CompetitiveGaming" : v, "manual");
            }));
            var plans = PowerPlans.ListCached();
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
        // off the UI thread: ms-settings:/shell URIs can block when BAKA is the shell
        static void Run(string uri) => Launcher.Run(uri, () => System.Diagnostics.Process.Start(uri));
        FrameworkElement Quick(int glyph, string label, string uri) => QuickAction(glyph, label, () => { Close(); Run(uri); });
        // A wide on/off tile: the round icon fills with the accent while it is on. Right-click opens its settings.
        FrameworkElement Switch(int glyph, string title, bool on, string state, Action toggle)
        {
            var g = new Grid(); g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); g.ColumnDefinitions.Add(new ColumnDefinition());
            var circle = new Border { Width = 34, Height = 34, CornerRadius = new CornerRadius(11), Background = on ? Theme.Accent : Theme.SurfaceAlt, BorderBrush = on ? Theme.Accent : Theme.Border, BorderThickness = new Thickness(1), Child = Ui.Glyph(glyph, 14, on ? Theme.OnColor(Theme.AccentHex) : Theme.Text), VerticalAlignment = VerticalAlignment.Center };
            g.Children.Add(circle);
            var text = new StackPanel { Margin = new Thickness(9, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
            text.Children.Add(Ui.Text(title, 12.5, FontWeights.SemiBold));
            text.Children.Add(Ui.Text(state, 10.5, null, on ? Theme.Accent : Theme.Muted));
            Grid.SetColumn(text, 1); g.Children.Add(text);
            var b = new Border { Child = g, Cursor = Cursors.Hand, Padding = new Thickness(8), Margin = new Thickness(3), CornerRadius = new CornerRadius(14), Background = Theme.B(Theme.Current.SurfaceAlt, 110), BorderBrush = Theme.B(Theme.Current.Border, 70), BorderThickness = new Thickness(1), ToolTip = title + ": click to turn " + (on ? "off" : "on") + ", right-click for settings" };
            b.MouseEnter += (o, e) => b.Background = Theme.B(Theme.AccentHex, 40); b.MouseLeave += (o, e) => b.Background = Theme.B(Theme.Current.SurfaceAlt, 110);
            Ui.OnClick(b, () => { try { toggle(); } catch (Exception ex) { Log.Write("control-center-failed item=" + title + " error=\"" + ex.Message + "\""); } Build(); });
            b.MouseRightButtonUp += (o, e) => { e.Handled = true; Close(); SettingsWindow.Open("Focus & games"); };
            System.Windows.Automation.AutomationProperties.SetName(b, title);
            return b;
        }
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
        // Desktop monitors have no brightness control through WMI; once that is known the (slow, 0.1 to
        // 0.5 s) WMI query is not run again on every Control Center open.
        static bool unsupported;
        public static int? Get()
        {
            if (unsupported) return null;
            try { using (var s = new ManagementObjectSearcher(@"root\WMI", "SELECT CurrentBrightness FROM WmiMonitorBrightness")) foreach (ManagementObject o in s.Get()) return Convert.ToInt32(o["CurrentBrightness"]); } catch { }
            unsupported = true;
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
        public static bool IsOpen => current != null && current.IsVisible;
        DateTime month = new DateTime(DateTime.Today.Year, DateTime.Today.Month, 1);
        public static void Toggle(Window anchor)
        {
            if (current != null && current.IsVisible) { current.Close(); return; }
            current = new CalendarFlyout();
            // opens under the clock island, which sits in the middle of the screen
            current.Left = (SystemParameters.PrimaryScreenWidth - current.Width) / 2; current.Top = TopBar.BarHeight + 4;
            current.Show(); current.Activate();
        }
        CalendarFlyout() : base(18)
        {
            Title = "BAKA Calendar"; Width = 320; SizeToContent = SizeToContent.Height; Topmost = true;
            Build();
            bool closing = false;
            Closing += (o, e) => closing = true;
            Deactivated += (o, e) => { if (!closing) { closing = true; try { Close(); } catch { } } };
            KeyDown += (o, e) => { if (e.Key == Key.Escape && !closing) Close(); };
            Ui.FadeIn(Frame, 170, 0.96, -12);
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
            var settings = Ui.Labeled(0xE787, "Date and time settings", () => { Close(); Launcher.Run("ms-settings:dateandtime", () => System.Diagnostics.Process.Start("ms-settings:dateandtime")); });
            settings.Margin = new Thickness(0, 10, 0, 0); settings.HorizontalAlignment = HorizontalAlignment.Left;
            sp.Children.Add(settings);
            Content = sp;
        }
    }
}
