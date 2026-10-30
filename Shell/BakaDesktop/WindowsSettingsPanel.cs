using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace Baka.Desktop
{
    // Windows Settings and the Microsoft Store are Store apps: they cannot open without Explorer (their window
    // frame is built by Explorer's "immersive shell"; activation fails with 0x80040900). With Explorer off, this
    // panel opens instead of a dead end:
    //  - the classic Windows panels that open without Explorer (each tested live with Explorer stopped: Sound,
    //    Date and Time, Mouse, Region, System Properties, Internet Properties, Game Controllers), plus Device
    //    Manager, Services, Disk Management and Task Manager;
    //  - a BAKA display panel (resolution and refresh rate, with a 12-second "keep?" so a bad mode undoes itself);
    //  - BAKA's own Wi-Fi panel;
    //  - and, as a last resort, "Start Explorer hidden" until sign-out, which opens what was asked for.
    // A request for a known Settings page (ms-settings:sound...) goes straight to its classic panel.
    class WindowsSettingsPanel : GlassPanel
    {
        static WindowsSettingsPanel current;
        static readonly (string uriPart, string cpl)[] Direct =
        {
            ("sound", "mmsys.cpl"), ("dateandtime", "timedate.cpl"), ("mousetouchpad", "main.cpl"), ("mouse", "main.cpl"),
            ("regionlanguage", "intl.cpl"), ("region", "intl.cpl"), ("about", "sysdm.cpl"), ("recovery", "sysdm.cpl"),
        };

        // what: the app name or URI that could not open; retry: opens it once Explorer runs.
        public static void Show(string what, Action retry)
        {
            string w = (what ?? "").ToLowerInvariant();
            if (w.StartsWith("ms-settings:"))
            {
                var hit = Direct.FirstOrDefault(d => w.Contains(d.uriPart));
                if (hit.cpl != null) { OpenCpl(hit.cpl); return; }
                if (w.Contains("network") || w.Contains("wifi") || w.Contains("availablenetworks")) { NetworkFlyout.Toggle(App.Bar); return; }
            }
            if (w.StartsWith("ms-availablenetworks")) { NetworkFlyout.Toggle(App.Bar); return; }
            current?.Close();
            current = new WindowsSettingsPanel(what, retry);
            current.Left = (SystemParameters.PrimaryScreenWidth - current.Width) / 2; current.Top = TopBar.BarHeight + 40;
            current.Show(); current.Activate();
        }

        static void OpenCpl(string cpl) => Launcher.Run(cpl, () => System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("rundll32.exe", "shell32.dll,Control_RunDLL " + cpl) { UseShellExecute = false }));
        static void OpenExe(string exe, string args = "") => Launcher.Run(exe, () => System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(exe, args) { UseShellExecute = true }));

        bool closing;
        WindowsSettingsPanel(string what, Action retry) : base(20)
        {
            Title = "BAKA Windows settings"; Width = 460; SizeToContent = SizeToContent.Height; Topmost = true;
            Closing += (o, e) => closing = true;
            Deactivated += (o, e) => { if (!closing && !SelfTest.Running && !keepOpen) { closing = true; try { Close(); } catch { } } };
            KeyDown += (o, e) => { if (e.Key == Key.Escape && !closing) Close(); };
            Closed += (o, e) => { if (current == this) current = null; };
            bool store = (what ?? "").IndexOf("store", StringComparison.OrdinalIgnoreCase) >= 0;
            var sp = new StackPanel { Margin = new Thickness(16) };
            sp.Children.Add(Ui.Text(store ? "Microsoft Store needs Explorer" : "Windows settings", 16, FontWeights.SemiBold));
            var why = Ui.Muted(store
                ? "Store apps only open while Windows Explorer runs, and Explorer is off. Start it hidden until you sign out to open the Store; the taskbar and desktop stay hidden."
                : "The Windows Settings app only opens while Explorer runs, and Explorer is off. These open without it:", 11.5);
            why.TextWrapping = TextWrapping.Wrap; why.Margin = new Thickness(0, 4, 0, 10); sp.Children.Add(why);
            if (!store)
            {
                var grid = new WrapPanel();
                void Tile(int glyph, string label, Action run) { var b = Ui.Labeled(glyph, label, () => { Close(); run(); }); b.Margin = new Thickness(0, 0, 8, 8); b.Width = 200; grid.Children.Add(b); }
                Tile(0xE7F4, "Display", () => DisplayPanel.Open());
                Tile(0xE701, "Wi-Fi and network", () => NetworkFlyout.Toggle(App.Bar));
                Tile(0xE995, "Sound", () => OpenCpl("mmsys.cpl"));
                Tile(0xE962, "Mouse", () => OpenCpl("main.cpl"));
                Tile(0xE787, "Date and time", () => OpenCpl("timedate.cpl"));
                Tile(0xE774, "Region and language", () => OpenCpl("intl.cpl"));
                Tile(0xE7EF, "System and advanced", () => OpenCpl("sysdm.cpl"));
                Tile(0xE7FC, "Game controllers", () => OpenCpl("joy.cpl"));
                Tile(0xE774, "Internet options", () => OpenCpl("inetcpl.cpl"));
                Tile(0xE772, "Device Manager", () => OpenExe("devmgmt.msc"));
                Tile(0xE912, "Services", () => OpenExe("services.msc"));
                Tile(0xEDA2, "Disk Management", () => OpenExe("diskmgmt.msc"));
                Tile(0xE9D9, "Task Manager", () => OpenExe("taskmgr.exe"));
                Tile(0xE713, "BAKA Settings", () => SettingsWindow.Open());
                sp.Children.Add(grid);
            }
            var start = Ui.Button(store ? "Start Explorer hidden and open the Store" : "Open the full Windows Settings (starts Explorer hidden)", () =>
            {
                Close();
                ShellMode.StartHelper("asked-by " + what, true);
                new System.Threading.Thread(() =>
                {
                    for (int i = 0; i < 40 && !ExplorerIntegration.ExplorerRunning(); i++) System.Threading.Thread.Sleep(250);
                    System.Threading.Thread.Sleep(3500);
                    try { retry?.Invoke(); } catch (Exception e) { Log.Write("explorer-needed-retry-failed error=\"" + e.Message + "\""); }
                }) { IsBackground = true }.Start();
            }, store, 10, new Thickness(14, 7, 14, 7));
            start.Margin = new Thickness(0, 6, 0, 0); start.HorizontalAlignment = HorizontalAlignment.Left;
            sp.Children.Add(start);
            Content = sp;
            Ui.FadeIn(Frame, 180, 0.95, -10);
        }
        bool keepOpen = false;
    }

    // Resolution and refresh rate of the main screen, without the Settings app. A new mode is tested first
    // (Windows rejects modes the screen cannot show) and undone after 12 seconds unless you keep it.
    class DisplayPanel : GlassPanel
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct DEVMODE
        {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields;
            public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
            public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
            public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
        }
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int ChangeDisplaySettingsEx(string dev, ref DEVMODE dm, IntPtr hwnd, int flags, IntPtr param);
        const int ENUM_CURRENT = -1, CDS_UPDATEREGISTRY = 1, CDS_TEST = 2, DM_PELS = 0x00180000, DM_FREQ = 0x00400000;

        static DisplayPanel current;
        public static void Open()
        {
            current?.Close();
            current = new DisplayPanel();
            current.Left = (SystemParameters.PrimaryScreenWidth - current.Width) / 2; current.Top = TopBar.BarHeight + 40;
            current.Show(); current.Activate();
        }
        static DEVMODE New() => new DEVMODE { dmSize = (short)Marshal.SizeOf(typeof(DEVMODE)) };
        readonly StackPanel body = new StackPanel { Margin = new Thickness(16) };
        DisplayPanel() : base(20)
        {
            Title = "BAKA Display"; Width = 380; SizeToContent = SizeToContent.Height; Topmost = true;
            KeyDown += (o, e) => { if (e.Key == Key.Escape) Close(); };
            Closed += (o, e) => { if (current == this) current = null; };
            Content = body; Draw();
            Ui.FadeIn(Frame, 180, 0.95, -10);
        }
        void Draw()
        {
            body.Children.Clear();
            var cur = New(); EnumDisplaySettings(null, ENUM_CURRENT, ref cur);
            var modes = new List<DEVMODE>();
            for (int i = 0; ; i++) { var m = New(); if (!EnumDisplaySettings(null, i, ref m)) break; if (m.dmBitsPerPel == 32) modes.Add(m); }
            body.Children.Add(Ui.Text("Display", 16, FontWeights.SemiBold));
            body.Children.Add(Ui.Muted("Now: " + cur.dmPelsWidth + " × " + cur.dmPelsHeight + " at " + cur.dmDisplayFrequency + " Hz", 11.5));
            var sizes = modes.Select(m => (m.dmPelsWidth, m.dmPelsHeight)).Distinct().OrderByDescending(s => s.dmPelsWidth * s.dmPelsHeight).ToList();
            var size = new ComboBox { Margin = new Thickness(0, 12, 0, 6) };
            foreach (var s in sizes) size.Items.Add(s.dmPelsWidth + " × " + s.dmPelsHeight);
            size.SelectedItem = cur.dmPelsWidth + " × " + cur.dmPelsHeight;
            var rate = new ComboBox { Margin = new Thickness(0, 0, 0, 10) };
            void Rates()
            {
                rate.Items.Clear();
                var sel = sizes.ElementAtOrDefault(Math.Max(0, size.SelectedIndex));
                foreach (var f in modes.Where(m => m.dmPelsWidth == sel.dmPelsWidth && m.dmPelsHeight == sel.dmPelsHeight).Select(m => m.dmDisplayFrequency).Distinct().OrderByDescending(f => f)) rate.Items.Add(f + " Hz");
                rate.SelectedItem = cur.dmDisplayFrequency + " Hz"; if (rate.SelectedIndex < 0) rate.SelectedIndex = 0;
            }
            size.SelectionChanged += (o, e) => Rates(); Rates();
            body.Children.Add(Ui.Text("Resolution", 12, FontWeights.SemiBold)); body.Children.Add(size);
            body.Children.Add(Ui.Text("Refresh rate", 12, FontWeights.SemiBold)); body.Children.Add(rate);
            var status = Ui.Muted("", 11.5); status.TextWrapping = TextWrapping.Wrap;
            var apply = Ui.Button("Apply", () =>
            {
                var sel = sizes[Math.Max(0, size.SelectedIndex)];
                int hz = int.TryParse(((string)rate.SelectedItem ?? "").Replace(" Hz", ""), out int r) ? r : cur.dmDisplayFrequency;
                var m = New(); EnumDisplaySettings(null, ENUM_CURRENT, ref m);
                var old = m;
                m.dmPelsWidth = sel.dmPelsWidth; m.dmPelsHeight = sel.dmPelsHeight; m.dmDisplayFrequency = hz; m.dmFields = DM_PELS | DM_FREQ;
                if (ChangeDisplaySettingsEx(null, ref m, IntPtr.Zero, CDS_TEST, IntPtr.Zero) != 0) { status.Text = "The screen does not support that mode."; return; }
                int res = ChangeDisplaySettingsEx(null, ref m, IntPtr.Zero, 0, IntPtr.Zero); // this session only, until kept
                Log.Write("display-mode " + m.dmPelsWidth + "x" + m.dmPelsHeight + "@" + hz + " result=" + res);
                if (res != 0) { status.Text = "Windows could not change the mode (" + res + ")."; return; }
                var keep = MessageBoxCountdown(12);
                if (keep) { ChangeDisplaySettingsEx(null, ref m, IntPtr.Zero, CDS_UPDATEREGISTRY, IntPtr.Zero); status.Text = "Kept."; }
                else { old.dmFields = DM_PELS | DM_FREQ; ChangeDisplaySettingsEx(null, ref old, IntPtr.Zero, 0, IntPtr.Zero); status.Text = "Changed back."; }
                Draw();
            }, true, 10, new Thickness(16, 6, 16, 6));
            apply.HorizontalAlignment = HorizontalAlignment.Left;
            body.Children.Add(apply); body.Children.Add(status);
        }
        // "Keep these display settings?" that answers No by itself after a few seconds.
        bool MessageBoxCountdown(int seconds)
        {
            bool kept = false;
            var w = new Window { Title = "BAKA", Width = 340, SizeToContent = SizeToContent.Height, WindowStartupLocation = WindowStartupLocation.CenterScreen, Topmost = true, ResizeMode = ResizeMode.NoResize, Background = Theme.B(Theme.Current.Surface, 255) };
            var sp = new StackPanel { Margin = new Thickness(18) };
            var t = Ui.Text("Keep these display settings?", 14, FontWeights.SemiBold); sp.Children.Add(t);
            var c = Ui.Muted("Changing back in " + seconds + " s.", 12); c.Margin = new Thickness(0, 6, 0, 12); sp.Children.Add(c);
            var row = new StackPanel { Orientation = Orientation.Horizontal };
            var yes = Ui.Button("Keep", () => { kept = true; w.Close(); }, true, 10, new Thickness(14, 6, 14, 6)); yes.Margin = new Thickness(0, 0, 8, 0);
            row.Children.Add(yes); row.Children.Add(Ui.Button("Change back", () => w.Close(), false, 10, new Thickness(14, 6, 14, 6)));
            sp.Children.Add(row); w.Content = sp;
            int left = seconds;
            var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            timer.Tick += (o, e) => { left--; c.Text = "Changing back in " + left + " s."; if (left <= 0) { timer.Stop(); w.Close(); } };
            timer.Start(); w.ShowDialog(); timer.Stop();
            return kept;
        }
    }
}
