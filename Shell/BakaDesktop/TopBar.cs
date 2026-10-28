using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

namespace Baka.Desktop
{
    // The menu bar along the top edge: BAKA menu, Apps, Files, the app in front, then tray, network,
    // volume, battery, profile, date and time, notifications and Control Center. It reserves its strip of
    // the screen, so maximized windows keep their title bar buttons below it.
    class TopBar : Window
    {
        public const double BarHeight = 30;
        IntPtr handle;
        TextBlock clockText, frontApp, profileText, volumeGlyph, netGlyph, batteryText;
        IntPtr lastForeground;

        public TopBar()
        {
            WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize; ShowInTaskbar = false; Topmost = true; ShowActivated = false;
            Background = Brushes.Transparent; FontFamily = Ui.Font; Title = "BAKA Menu Bar"; UseLayoutRounding = true;
            SourceInitialized += (o, e) =>
            {
                handle = new WindowInteropHelper(this).Handle;
                Native.SetWindowLongPtr(handle, Native.GWL_EXSTYLE, new IntPtr(Native.ExStyle(handle) | Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE));
                var src = HwndSource.FromHwnd(handle); src.CompositionTarget.BackgroundColor = Colors.Transparent;
                int none = 1; Native.DwmSetWindowAttribute(handle, 33, ref none, 4); // square corners
                Backdrop();
                Place();
            };
            Build();
            Theme.Changed += () => { Build(); Backdrop(); };
            App.Tick += UpdateClock;
            App.WindowsChanged += UpdateFront;
            Profiles.Changed += () => Dispatcher.BeginInvoke(new Action(UpdateProfile));
            Microsoft.Win32.SystemEvents.DisplaySettingsChanged += (o, e) => Dispatcher.BeginInvoke(new Action(Place));
        }

        void Backdrop()
        {
            if (handle == IntPtr.Zero) return;
            int kind = Theme.Current.Backdrop == "Opaque" ? 1 : 3;
            bool ok = Native.DwmSetWindowAttribute(handle, 38, ref kind, 4) == 0 && kind != 1;
            ((Border)Content).Background = Theme.B(Theme.Current.Canvas, (byte)(ok ? 150 : 250));
        }

        void Build()
        {
            var root = new Border { BorderBrush = Theme.B(Theme.Current.Border, 70), BorderThickness = new Thickness(0, 0, 0, 1) };
            var g = new Grid { Margin = new Thickness(8, 0, 6, 0) };
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.ColumnDefinitions.Add(new ColumnDefinition());
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var left = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            var logo = Item(null, "BAKA", true); logo.ToolTip = "BAKA menu";
            Ui.OnClick(logo, () => LogoMenu(logo));
            left.Children.Add(logo);
            frontApp = Ui.Text("Desktop", 12.5, FontWeights.SemiBold); frontApp.Margin = new Thickness(6, 0, 10, 0); frontApp.VerticalAlignment = VerticalAlignment.Center; frontApp.MaxWidth = 260;
            left.Children.Add(frontApp);
            foreach (var (label, action) in new (string, Action)[] { ("Apps", () => Launchpad.Toggle()), ("Files", () => Files.Open(null)), ("Arena", Arena.Open), ("Settings", () => SettingsWindow.Open()) })
            { var it = Item(null, label, false); Ui.OnClick(it, action); left.Children.Add(it); }
            g.Children.Add(left);

            var right = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            Grid.SetColumn(right, 2);
            profileText = Ui.Text("", 10.5, FontWeights.SemiBold, Theme.Accent); profileText.Margin = new Thickness(0, 0, 10, 0); profileText.VerticalAlignment = VerticalAlignment.Center;
            right.Children.Add(profileText);
            right.Children.Add(Glyphed(0xE70E, "Tray icons (Discord, Steam, drivers)", App.PeekTray));
            netGlyph = Ui.Glyph(0xE701, 13); right.Children.Add(Wrap(netGlyph, "Network", () => Open("ms-availablenetworks:")));
            volumeGlyph = Ui.Glyph(0xE995, 13); right.Children.Add(Wrap(volumeGlyph, "Volume", () => ControlCenter.Toggle(this)));
            batteryText = Ui.Text("", 11.5); batteryText.VerticalAlignment = VerticalAlignment.Center; batteryText.Margin = new Thickness(6, 0, 6, 0); right.Children.Add(batteryText);
            clockText = Ui.Text("", 12, FontWeights.SemiBold); clockText.VerticalAlignment = VerticalAlignment.Center;
            var clockItem = Wrap(clockText, "Calendar", () => CalendarFlyout.Toggle(this)); right.Children.Add(clockItem);
            right.Children.Add(Glyphed(0xE7E7, "Notifications", () => Native.SendKeys(0x5B, 0x4E)));
            right.Children.Add(Glyphed(0xE9E9, "Control Center", () => ControlCenter.Toggle(this)));
            g.Children.Add(right);
            root.Child = g;
            Content = root;
            UpdateClock(); UpdateProfile(); UpdateFront();
        }
        static void Open(string uri) { try { System.Diagnostics.Process.Start(uri); } catch { } }
        FrameworkElement Item(object _, string label, bool bold)
        {
            var t = Ui.Text(label, 12.5, bold ? FontWeights.Bold : FontWeights.Normal);
            var b = new Border { Child = t, Padding = new Thickness(9, 3, 9, 3), CornerRadius = new CornerRadius(6), Cursor = Cursors.Hand, Background = Brushes.Transparent, Margin = new Thickness(0, 0, 2, 0) };
            b.MouseEnter += (o, e) => b.Background = Theme.Hover; b.MouseLeave += (o, e) => b.Background = Brushes.Transparent;
            return b;
        }
        FrameworkElement Glyphed(int glyph, string tip, Action click) => Wrap(Ui.Glyph(glyph, 13), tip, click);
        FrameworkElement Wrap(FrameworkElement inner, string tip, Action click)
        {
            var b = new Border { Child = inner, Padding = new Thickness(8, 3, 8, 3), CornerRadius = new CornerRadius(6), Cursor = Cursors.Hand, Background = Brushes.Transparent, ToolTip = tip, Margin = new Thickness(1, 0, 1, 0) };
            b.MouseEnter += (o, e) => b.Background = Theme.Hover; b.MouseLeave += (o, e) => b.Background = Brushes.Transparent;
            Ui.OnClick(b, () => { try { click?.Invoke(); } catch (Exception ex) { Log.Write("bar-click-failed error=\"" + ex.Message + "\""); } });
            System.Windows.Automation.AutomationProperties.SetName(b, tip);
            return b;
        }

        void LogoMenu(FrameworkElement anchor)
        {
            Ui.ShowMenu(anchor,
                Ui.Item("About BAKA", 0xE946, () => SettingsWindow.Open("About")),
                Ui.Item("BAKA Settings", 0xE713, () => SettingsWindow.Open()), Ui.Item("Windows Settings", 0xE770, () => Open("ms-settings:")),
                "-",
                Ui.Item("Task Manager", 0xE9D9, () => Open("taskmgr")), Ui.Item("Show tray icons", 0xE70E, App.PeekTray),
                "-",
                Ui.Item("Lock", 0xE72E, () => Native.LockWorkStation(), "Win+L"), Ui.Item("Sleep", 0xE708, Power.Sleep), Ui.Item("Restart", 0xE777, Power.Restart), Ui.Item("Shut down", 0xE7E8, Power.Shutdown), Ui.Item("Sign out", 0xF3B1, Power.SignOut),
                "-",
                Ui.Item("Use the Windows taskbar instead", 0xE7C4, () => App.Quit(true)));
        }

        void UpdateClock()
        {
            if (clockText == null) return;
            var now = DateTime.Now;
            clockText.Text = Json.Bool(App.Settings.TopBar, "showDate", true) ? now.ToString("ddd d MMM  HH:mm") : now.ToString("HH:mm");
            if (now.Second % 5 == 0)
            {
                try { int? v = Audio.Level; bool m = Audio.Muted; volumeGlyph.Text = char.ConvertFromUtf32(m || v == 0 ? 0xE74F : v < 34 ? 0xE993 : v < 67 ? 0xE994 : 0xE995); } catch { }
                bool online = System.Net.NetworkInformation.NetworkInterface.GetIsNetworkAvailable();
                netGlyph.Text = char.ConvertFromUtf32(online ? 0xE701 : 0xEB55);
                if (Native.GetSystemPowerStatus(out var p) && p.BatteryFlag != 128 && p.BatteryLifePercent <= 100) batteryText.Text = (p.ACLineStatus == 1 ? "⚡" : "") + p.BatteryLifePercent + "%"; else batteryText.Text = "";
            }
        }
        void UpdateProfile()
        {
            if (profileText == null) return;
            profileText.Visibility = Json.Bool(App.Settings.TopBar, "showProfile", true) ? Visibility.Visible : Visibility.Collapsed;
            profileText.Text = Profiles.Active == "CompetitiveGaming" ? "GAMING" : Profiles.Active == "Benchmark" ? "BENCHMARK" : "DESKTOP";
        }
        void UpdateFront()
        {
            var fg = Native.GetForegroundWindow();
            if (fg == lastForeground || fg == handle) return;
            lastForeground = fg;
            Native.GetWindowThreadProcessId(fg, out uint pid);
            string name;
            if (pid == System.Diagnostics.Process.GetCurrentProcess().Id)
            {
                string t = Native.WindowText(fg);
                name = t.Contains("BAKA Files") ? "BAKA Files" : t.StartsWith("BAKA ") && !t.Contains("Menu Bar") && !t.Contains("Dock") ? t : "Desktop";
            }
            else
            {
                string exe = Native.ProcessPath(pid) ?? "";
                string cls = Native.ClassName(fg);
                if (cls == "Progman" || cls == "WorkerW" || exe.EndsWith("explorer.exe", StringComparison.OrdinalIgnoreCase) && cls != "CabinetWClass") name = "Desktop";
                else
                {
                    try { name = System.Diagnostics.FileVersionInfo.GetVersionInfo(exe).FileDescription; } catch { name = null; }
                    if (string.IsNullOrWhiteSpace(name)) name = System.IO.Path.GetFileNameWithoutExtension(exe);
                    if (exe.EndsWith("ApplicationFrameHost.exe", StringComparison.OrdinalIgnoreCase)) name = Native.WindowText(fg);
                }
            }
            frontApp.Text = name;
        }

        public void Place()
        {
            if (handle == IntPtr.Zero) return;
            var screen = System.Windows.Forms.Screen.PrimaryScreen.Bounds;
            double s = Ui.Scale(this);
            int h = (int)Math.Round(BarHeight * s);
            Native.SetWindowPos(handle, Native.HWND_TOPMOST, screen.Left, screen.Top, screen.Width, h, Native.SWP_NOACTIVATE | Native.SWP_SHOWWINDOW);
            Reserve();
        }
        public void Reserve()
        {
            if (handle == IntPtr.Zero || !IsVisible) return;
            var screen = System.Windows.Forms.Screen.PrimaryScreen.Bounds;
            int h = (int)Math.Round(BarHeight * Ui.Scale(this));
            AppBars.Reserve(handle, Native.ABE_TOP, new Native.RECT { Left = screen.Left, Top = screen.Top, Right = screen.Right, Bottom = screen.Top + h });
        }
        public new void Hide() { if (handle != IntPtr.Zero) AppBars.Release(handle); base.Hide(); }
        public new void Show() { base.Show(); Place(); }
    }

    static class Power
    {
        static void Run(string args) { if (Paths.Preview) { Log.Write("power-preview " + args); return; } try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("shutdown.exe", args) { UseShellExecute = false, CreateNoWindow = true }); } catch { } }
        public static void Sleep() { if (!Paths.Preview) Native.SetSuspendState(false, false, false); }
        public static void Restart() { if (Confirm("Restart now?")) Run("/r /t 0"); }
        public static void Shutdown() { if (Confirm("Shut down now?")) Run("/s /hybrid /t 0"); }
        public static void SignOut() { if (Confirm("Sign out now?")) Run("/l"); }
        static bool Confirm(string q) => Paths.Preview || MessageBox.Show(q, "BAKA", MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes;
    }
}
