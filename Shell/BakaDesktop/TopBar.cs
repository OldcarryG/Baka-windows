using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;

namespace Baka.Desktop
{
    // The menu bar, as "Dynamic Islands": separate floating glass pills along the top edge instead of one
    // full-width black bar. A menu island on the left (BAKA menu, Apps, Files, Arena, Settings, and the app
    // in front), a clock island in the centre that expands on hover to show the full date, and a status
    // island on the right (profile, tray, network, volume, battery, notifications, Control Center).
    // The window spans the top of the screen but is see-through: clicks in the gaps between pills fall
    // through to the desktop (WM_NCHITTEST), so only the pills themselves cover anything.
    class TopBar : Window
    {
        // Reserved strip + the anchor every flyout and the dock measure from. Covers a pill plus its margins.
        public const double BarHeight = 50;
        // The window is taller than the reserved strip so an island can expand downward (date, later media
        // and notifications) into transparent, click-through space.
        const double IslandZone = 240, PillHeight = 34, TopMargin = 8;
        IntPtr handle;
        TextBlock clockText, dateText, frontApp, profileText, volumeGlyph, netGlyph, batteryText, islandTrack, langText;
        Border islandArt; StackPanel islandControls, trayHost; Button islandPlay; bool islandHover;
        IntPtr lastForeground;
        readonly List<FrameworkElement> pills = new List<FrameworkElement>();

        public TopBar()
        {
            WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize; ShowInTaskbar = false; Topmost = true; ShowActivated = false;
            AllowsTransparency = true; Background = Brushes.Transparent; FontFamily = Ui.Font; Title = "BAKA Menu Bar"; UseLayoutRounding = true;
            SourceInitialized += (o, e) =>
            {
                handle = new WindowInteropHelper(this).Handle;
                Native.SetWindowLongPtr(handle, Native.GWL_EXSTYLE, new IntPtr(Native.ExStyle(handle) | Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE));
                var src = HwndSource.FromHwnd(handle);
                if (src?.CompositionTarget != null) src.CompositionTarget.BackgroundColor = Colors.Transparent;
                src?.AddHook(HitTest);
                Place();
            };
            Build();
            Theme.Changed += () => { Build(); Dispatcher.BeginInvoke(new Action(Place), System.Windows.Threading.DispatcherPriority.Loaded); };
            App.Tick += UpdateClock;
            App.WindowsChanged += UpdateFront;
            NowPlaying.Changed += UpdateIsland;
            BakaTray.Changed += () => Dispatcher.BeginInvoke(new Action(UpdateTray));
            Profiles.Changed += () => Dispatcher.BeginInvoke(new Action(UpdateProfile));
            FocusMode.Changed += () => Dispatcher.BeginInvoke(new Action(UpdateFocus));
            Microsoft.Win32.SystemEvents.DisplaySettingsChanged += (o, e) => Dispatcher.BeginInvoke(new Action(Place));
            hideTimer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(150) };
            hideTimer.Tick += (o, e) => AutoHideTick();
            if (AutoHide) hideTimer.Start(); // only while auto-hide is on (it ran 7 times a second for nothing)
        }

        // ---- auto-hide: the islands slide up out of sight and give their strip back to apps; they come
        // back when the pointer touches the top edge of the screen, and stay while it is over them ----
        readonly TranslateTransform slide = new TranslateTransform();
        System.Windows.Threading.DispatcherTimer hideTimer;
        bool slidUp; DateTime lastWanted = DateTime.Now;
        public static bool AutoHide => App.Settings != null && Json.Bool(App.Settings.TopBar, "autoHide");
        void AutoHideTick()
        {
            if (handle == IntPtr.Zero || !IsVisible) return;
            if (!AutoHide || App.GameRunning) { if (slidUp) Slide(false); else if (!AutoHide) hideTimer.Stop(); return; }
            bool wanted = islandHover || pills.Any(p => p.IsMouseOver) || CalendarFlyout.IsOpen || ControlCenter.IsOpen || NetworkFlyout.IsOpen || NotificationCenter.IsOpen;
            if (!wanted && Native.GetCursorPos(out var c)) { var b = System.Windows.Forms.Screen.PrimaryScreen.Bounds; wanted = c.Y <= b.Top + 2 && c.X >= b.Left && c.X < b.Right; }
            if (wanted) { lastWanted = DateTime.Now; if (slidUp) Slide(false); }
            else if (!slidUp && (DateTime.Now - lastWanted).TotalMilliseconds > 700) Slide(true);
        }
        // Re-assert top-of-z-order. WPF's Topmost is not always honoured against a maximized or newly
        // focused app (that app can slot in above us), so on every reveal we push the islands window back to
        // the top with SetWindowPos — without activating it (it must never steal focus from the app).
        void Raise()
        {
            if (handle == IntPtr.Zero) return;
            try { Native.SetWindowPos(handle, Native.HWND_TOPMOST, 0, 0, 0, 0, Native.SWP_NOMOVE | Native.SWP_NOSIZE | Native.SWP_NOACTIVATE); } catch { }
        }
        void Slide(bool up)
        {
            slidUp = up;
            if (!up) Raise(); // coming back into view: make sure we draw above whatever app is in front
            double to = up ? -(BarHeight + 16) : 0;
            if (Theme.Motion) slide.BeginAnimation(TranslateTransform.YProperty, new System.Windows.Media.Animation.DoubleAnimation(to, TimeSpan.FromMilliseconds(160)) { EasingFunction = new System.Windows.Media.Animation.QuadraticEase() });
            else { slide.BeginAnimation(TranslateTransform.YProperty, null); slide.Y = to; }
        }
        // Settings changed: reserve or release the strip at once.
        public void ApplyAutoHide() { Reserve(); if (!AutoHide && slidUp) Slide(false); if (AutoHide) hideTimer.Start(); else if (!slidUp) hideTimer.Stop(); }

        // Clicks over a pill are handled normally; everywhere else the window is transparent to the mouse so
        // the desktop (and app windows) behind the empty gaps keep working.
        IntPtr HitTest(IntPtr h, int msg, IntPtr w, IntPtr l, ref bool handled)
        {
            if (msg != 0x0084) return IntPtr.Zero; // WM_NCHITTEST
            long lp = l.ToInt64();
            double px = (short)(lp & 0xFFFF), py = (short)((lp >> 16) & 0xFFFF);
            foreach (var pill in pills)
            {
                if (pill == null || !pill.IsVisible || pill.ActualWidth <= 0 || pill.ActualHeight <= 0) continue;
                try
                {
                    var tl = pill.PointToScreen(new Point(0, 0));
                    var br = pill.PointToScreen(new Point(pill.ActualWidth, pill.ActualHeight));
                    double x0 = Math.Min(tl.X, br.X), x1 = Math.Max(tl.X, br.X), y0 = Math.Min(tl.Y, br.Y), y1 = Math.Max(tl.Y, br.Y);
                    if (px >= x0 && px < x1 && py >= y0 && py < y1) return IntPtr.Zero; // over a pill: normal handling
                }
                catch { }
            }
            handled = true; return new IntPtr(-1); // HTTRANSPARENT: fall through to whatever is underneath
        }

        // One floating glass pill: rounded, soft-shadowed, dark glass that follows the theme.
        Border Pill(UIElement child)
        {
            return new Border
            {
                Child = child,
                CornerRadius = new CornerRadius(PillHeight / 2 + 3),
                Padding = new Thickness(13, 0, 13, 0),
                MinHeight = PillHeight,
                VerticalAlignment = VerticalAlignment.Top,
                // the theme's glass (follows the transparency slider), or the colour / picture / video chosen
                Background = Surfaces.Background("bar") ?? Theme.Glass,
                BorderBrush = Theme.B(Theme.Current.Border, 90),
                BorderThickness = new Thickness(1),
                Effect = new DropShadowEffect { BlurRadius = 20, ShadowDepth = 2, Direction = 270, Opacity = 0.5, Color = Colors.Black }
            };
        }

        void Build()
        {
            pills.Clear();
            var root = new Grid { RenderTransform = slide };

            // ---- menu island (left) ----
            var menu = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            var logo = Item("BAKA", true); logo.ToolTip = "BAKA menu"; Ui.OnClick(logo, () => LogoMenu(logo));
            menu.Children.Add(logo);
            frontApp = Ui.Text("Desktop", 12.5, FontWeights.SemiBold); frontApp.Margin = new Thickness(6, 0, 8, 0); frontApp.VerticalAlignment = VerticalAlignment.Center; frontApp.MaxWidth = 220;
            menu.Children.Add(frontApp);
            foreach (var (label, action) in new (string, Action)[] { ("Apps", () => Launchpad.Toggle()), ("Files", () => Files.Open(null)), ("Arena", Arena.Open), ("Settings", () => SettingsWindow.Open()) })
            { var it = Item(label, false); Ui.OnClick(it, action); menu.Children.Add(it); }
            var menuPill = Pill(menu); menuPill.HorizontalAlignment = HorizontalAlignment.Left; menuPill.Margin = new Thickness(10, TopMargin, 0, 0);
            AddPill(root, menuPill);

            // ---- clock island (centre): the time, and the album art + track of whatever is playing. It
            // grows to fit the track and, on hover, opens to the date and play controls ----
            var clockStack = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            var clockRow = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, MinHeight = PillHeight - 2 };
            islandArt = new Border { Width = 22, Height = 22, CornerRadius = new CornerRadius(6), Margin = new Thickness(0, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center, Visibility = Visibility.Collapsed };
            clockRow.Children.Add(islandArt);
            islandTrack = Ui.Text("", 12, FontWeights.Normal, Theme.Muted); islandTrack.MaxWidth = 240; islandTrack.Margin = new Thickness(0, 0, 10, 0); islandTrack.VerticalAlignment = VerticalAlignment.Center; islandTrack.Visibility = Visibility.Collapsed;
            clockRow.Children.Add(islandTrack);
            clockText = Ui.Text("", 13.5, FontWeights.SemiBold); clockText.VerticalAlignment = VerticalAlignment.Center;
            clockRow.Children.Add(clockText);
            clockStack.Children.Add(clockRow);
            dateText = Ui.Text("", 11.5, FontWeights.Normal, Theme.Muted); dateText.HorizontalAlignment = HorizontalAlignment.Center; dateText.Margin = new Thickness(0, 0, 0, 4); dateText.Visibility = Visibility.Collapsed;
            clockStack.Children.Add(dateText);
            islandControls = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 0, 0, 6), Visibility = Visibility.Collapsed };
            islandControls.Children.Add(Ui.Icon(0xE892, "Previous track", NowPlaying.Previous, 28, 11));
            islandPlay = Ui.Icon(0xE768, "Play or pause", NowPlaying.PlayPause, 32, 13); islandControls.Children.Add(islandPlay);
            islandControls.Children.Add(Ui.Icon(0xE893, "Next track", NowPlaying.Next, 28, 11));
            clockStack.Children.Add(islandControls);
            var clockPill = Pill(clockStack); clockPill.HorizontalAlignment = HorizontalAlignment.Center; clockPill.Margin = new Thickness(0, TopMargin, 0, 0); clockPill.Cursor = Cursors.Hand; clockPill.ToolTip = "Calendar";
            clockPill.MouseEnter += (o, e) => { islandHover = true; if (!ShowDate) { dateText.Visibility = Visibility.Visible; Ui.FadeIn(dateText, 140); } UpdateIsland(); };
            clockPill.MouseLeave += (o, e) => { islandHover = false; dateText.Visibility = Visibility.Collapsed; UpdateIsland(); };
            Ui.OnClick(clockPill, () => CalendarFlyout.Toggle(this));
            System.Windows.Automation.AutomationProperties.SetName(clockPill, "Calendar");
            AddPill(root, clockPill);

            // ---- status island (right) ----
            var status = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            profileText = Ui.Text("", 10.5, FontWeights.SemiBold, Theme.Accent); profileText.Margin = new Thickness(2, 0, 8, 0); profileText.VerticalAlignment = VerticalAlignment.Center;
            status.Children.Add(profileText);
            langText = Ui.Text("", 11, FontWeights.SemiBold); langText.VerticalAlignment = VerticalAlignment.Center;
            status.Children.Add(Wrap(langText, "Keyboard language", () => Open("ms-settings:regionlanguage")));
            // In shell mode BAKA hosts the tray itself: the real app icons sit here. Otherwise this button
            // briefly shows the Windows tray (Explorer still owns it).
            trayHost = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            // One tray button. With BAKA's own tray (shell mode) it hides / shows the icons next to it; without
            // it, it shows the Windows tray. (Before, shell mode still had the old button, which sent Win+B to
            // a taskbar that was not there and opened the Launchpad search instead.)
            trayToggleGlyph = Ui.Glyph(0xE70E, 12);
            status.Children.Add(Wrap(trayToggleGlyph, "Show or hide tray icons", () => { if (BakaTray.Running) ToggleTray(); else TrayFlyout.Toggle(this); }));
            status.Children.Add(trayHost);
            netGlyph = Ui.Glyph(0xE701, 13); status.Children.Add(Wrap(netGlyph, "Network", () => NetworkFlyout.Toggle(this)));
            volumeGlyph = Ui.Glyph(0xE995, 13); status.Children.Add(Wrap(volumeGlyph, "Volume", () => ControlCenter.Toggle(this)));
            batteryText = Ui.Text("", 11.5); batteryText.VerticalAlignment = VerticalAlignment.Center; batteryText.Margin = new Thickness(4, 0, 4, 0); status.Children.Add(batteryText);
            // the moon while Focus is on (no pop-ups); a click turns Focus off
            focusIcon = Wrap(Ui.Glyph(0xE708, 13, Theme.Accent), "Focus is on: no pop-ups. Click to turn it off (Ctrl+Alt+D).", () => FocusMode.Set(false, "menu bar"));
            status.Children.Add(focusIcon);
            status.Children.Add(Glyphed(0xE7E7, "Notifications", () => NotificationCenter.Toggle(this)));
            status.Children.Add(Glyphed(0xE9E9, "Control Center", () => ControlCenter.Toggle(this)));
            var statusPill = Pill(status); statusPill.HorizontalAlignment = HorizontalAlignment.Right; statusPill.Margin = new Thickness(0, TopMargin, 10, 0);
            AddPill(root, statusPill);

            base.Content = root;
            UpdateClock(); UpdateProfile(); UpdateFront(); UpdateIsland(); UpdateTray(); UpdateFocus();
        }
        FrameworkElement focusIcon;
        void UpdateFocus() { if (focusIcon != null) focusIcon.Visibility = FocusMode.On ? Visibility.Visible : Visibility.Collapsed; }

        // The app tray icons BAKA is hosting (shell mode): left-click and right-click are sent to the app so
        // its own action and menu work.
        TextBlock trayToggleGlyph;
        public static bool TrayCollapsed => App.Settings != null && Json.Bool(App.Settings.TopBar, "trayCollapsed");
        public void ToggleTray()
        {
            App.Settings.TopBar["trayCollapsed"] = !TrayCollapsed; App.Settings.Save();
            UpdateTray();
            if (!TrayCollapsed && Theme.Motion) Ui.FadeIn(trayHost, 160, 0.9);
        }
        void UpdateTray()
        {
            if (trayHost == null) return;
            trayHost.Children.Clear();
            if (trayToggleGlyph != null) trayToggleGlyph.Text = char.ConvertFromUtf32(!BakaTray.Running ? 0xE70E : TrayCollapsed ? 0xE76B : 0xE76C);
            if (!BakaTray.Running) return;
            trayHost.Visibility = TrayCollapsed ? Visibility.Collapsed : Visibility.Visible;
            foreach (var it in BakaTray.Items.Where(i => i.Image != null).ToList())
            {
                var item = it;
                var img = new System.Windows.Controls.Image { Source = it.Image, Width = 18, Height = 18 };
                RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality);
                var b = new Border { Child = img, Padding = new Thickness(5, 4, 5, 4), CornerRadius = new CornerRadius(7), Cursor = Cursors.Hand, Background = Brushes.Transparent, ToolTip = string.IsNullOrEmpty(it.Tip) ? null : it.Tip, Margin = new Thickness(1, 0, 1, 0), VerticalAlignment = VerticalAlignment.Center };
                b.MouseEnter += (o, e) => b.Background = Theme.Hover; b.MouseLeave += (o, e) => b.Background = Brushes.Transparent;
                Ui.OnClick(b, () => BakaTray.Click(item, false));
                b.MouseRightButtonUp += (o, e) => { e.Handled = true; BakaTray.Click(item, true); };
                trayHost.Children.Add(b);
            }
        }

        // The clock island shows the album art and "title · artist" while something plays (dimmed when
        // paused), and the play controls while the pointer is over it.
        void UpdateIsland()
        {
            if (islandArt == null) return;
            bool has = NowPlaying.HasMedia;
            if (has && NowPlaying.Art != null) { islandArt.Background = new ImageBrush(NowPlaying.Art) { Stretch = Stretch.UniformToFill }; islandArt.Child = null; }
            else { islandArt.Background = Theme.B(Theme.Current.SurfaceAlt, 200); islandArt.Child = Ui.Glyph(0xE8D6, 11, Theme.Muted); }
            islandArt.Visibility = has ? Visibility.Visible : Visibility.Collapsed;
            islandTrack.Text = !has ? "" : string.IsNullOrEmpty(NowPlaying.Artist) ? NowPlaying.Title : NowPlaying.Title + "  \u00B7  " + NowPlaying.Artist;
            islandTrack.Visibility = has ? Visibility.Visible : Visibility.Collapsed;
            islandTrack.Opacity = islandArt.Opacity = NowPlaying.Playing ? 1 : 0.6;
            islandControls.Visibility = has && islandHover ? Visibility.Visible : Visibility.Collapsed;
            if (islandPlay?.Content is TextBlock g) g.Text = char.ConvertFromUtf32(NowPlaying.Playing ? 0xE769 : 0xE768);
        }
        void AddPill(Grid root, Border pill) { root.Children.Add(pill); pills.Add(pill); if (Theme.Motion) Ui.FadeIn(pill, 180); }
        // off the UI thread: ms-settings:/shell URIs can block when BAKA is the shell
        static void Open(string uri) => Launcher.Run(uri, () => System.Diagnostics.Process.Start(uri));

        FrameworkElement Item(string label, bool bold)
        {
            var t = Ui.Text(label, 12.5, bold ? FontWeights.Bold : FontWeights.Normal);
            var b = new Border { Child = t, Padding = new Thickness(8, 4, 8, 4), CornerRadius = new CornerRadius(8), Cursor = Cursors.Hand, Background = Brushes.Transparent, Margin = new Thickness(0, 0, 1, 0), VerticalAlignment = VerticalAlignment.Center };
            b.MouseEnter += (o, e) => b.Background = Theme.Hover; b.MouseLeave += (o, e) => b.Background = Brushes.Transparent;
            return b;
        }
        FrameworkElement Glyphed(int glyph, string tip, Action click) => Wrap(Ui.Glyph(glyph, 13), tip, click);
        FrameworkElement Wrap(FrameworkElement inner, string tip, Action click)
        {
            var b = new Border { Child = inner, Padding = new Thickness(7, 4, 7, 4), CornerRadius = new CornerRadius(8), Cursor = Cursors.Hand, Background = Brushes.Transparent, ToolTip = tip, Margin = new Thickness(1, 0, 1, 0), VerticalAlignment = VerticalAlignment.Center };
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
                Ui.Item("Task Manager", 0xE9D9, () => Open("taskmgr")), Ui.Item("Show tray icons", 0xE70E, () => TrayFlyout.Toggle(this)),
                "-",
                Ui.Item("Lock", 0xE72E, () => Native.LockWorkStation(), "Win+L"), Ui.Item("Sleep", 0xE708, Power.Sleep), Ui.Item("Restart", 0xE777, Power.Restart), Ui.Item("Shut down", 0xE7E8, Power.Shutdown), Ui.Item("Sign out", 0xF3B1, Power.SignOut),
                "-",
                Ui.Item("Use the Windows taskbar instead", 0xE7C4, () => App.Quit(true)));
        }

        public static bool ShowDate => App.Settings != null && Json.Bool(App.Settings.TopBar, "showDate", false);
        public string ClockText => clockText?.Text ?? ""; // self-test
        // Settings changed the date switch: redraw the clock now, not at the next second
        public void RefreshClock() => UpdateClock();
        void UpdateClock()
        {
            if (clockText == null) return;
            var now = DateTime.Now;
            // Settings > Menu bar > Show the date: the short date next to the time. Off, the date shows when the
            // pointer is over the clock. (12.27.1 ignored the switch and always showed the time only.)
            string clock = ShowDate ? now.ToString("ddd d MMM") + "   " + now.ToString("HH:mm") : now.ToString("HH:mm");
            if (clockText.Text != clock) clockText.Text = clock;
            if (dateText != null) dateText.Text = now.ToString("dddd, d MMMM");
            if (now.Second % 5 == 0)
            {
                try { int? v = Audio.Level; bool m = Audio.Muted; volumeGlyph.Text = char.ConvertFromUtf32(m || v == 0 ? 0xE74F : v < 34 ? 0xE993 : v < 67 ? 0xE994 : 0xE995); } catch { }
                bool online = System.Net.NetworkInformation.NetworkInterface.GetIsNetworkAvailable();
                netGlyph.Text = char.ConvertFromUtf32(online ? 0xE701 : 0xEB55);
                if (Native.GetSystemPowerStatus(out var p) && p.BatteryFlag != 128 && p.BatteryLifePercent <= 100) batteryText.Text = (p.ACLineStatus == 1 ? "\u26A1" : "") + p.BatteryLifePercent + "%"; else batteryText.Text = "";
                if (langText != null) { try { langText.Text = ShellExtras.LayoutCount() > 1 ? ShellExtras.CurrentLanguage() : ""; langText.Visibility = string.IsNullOrEmpty(langText.Text) ? Visibility.Collapsed : Visibility.Visible; } catch { } }
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
                    string appId = Native.WindowAppId(fg), file = System.IO.Path.GetFileName(exe);
                    var hit = (!string.IsNullOrEmpty(appId) ? AppCatalog.Apps.FirstOrDefault(a => string.Equals(a.AppId, appId, StringComparison.OrdinalIgnoreCase)) : null)
                           ?? AppCatalog.Apps.FirstOrDefault(a => !string.IsNullOrEmpty(a.Exe) && a.Exe.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) && System.IO.Path.GetFileName(a.Exe).Equals(file, StringComparison.OrdinalIgnoreCase));
                    if (hit != null) name = hit.Name;
                    else
                    {
                        try { name = System.Diagnostics.FileVersionInfo.GetVersionInfo(exe).FileDescription; } catch { name = null; }
                        if (string.IsNullOrWhiteSpace(name)) name = System.IO.Path.GetFileNameWithoutExtension(exe);
                        if (exe.EndsWith("ApplicationFrameHost.exe", StringComparison.OrdinalIgnoreCase)) name = Native.WindowText(fg);
                    }
                }
            }
            if (frontApp.Text == name) return;
            frontApp.Text = name;
            Ui.FadeIn(frontApp, 150, 1.0, 6); // the app name slides in when you switch apps
        }

        public void Place()
        {
            if (handle == IntPtr.Zero) return;
            // Layered (see-through) window: drive size/position through WPF, not SetWindowPos.
            Left = 0; Top = 0;
            Width = SystemParameters.PrimaryScreenWidth;
            Height = IslandZone;
            Reserve();
        }
        public void Reserve()
        {
            if (handle == IntPtr.Zero || !IsVisible) return;
            if (AutoHide) { AppBars.Release(handle); return; } // hidden until needed: apps get the whole height
            var screen = System.Windows.Forms.Screen.PrimaryScreen.Bounds;
            int h = (int)Math.Round(BarHeight * Ui.Scale(this));
            AppBars.Reserve(handle, Native.ABE_TOP, new Native.RECT { Left = screen.Left, Top = screen.Top, Right = screen.Right, Bottom = screen.Top + h });
        }
        public new void Hide() { if (handle != IntPtr.Zero) AppBars.Release(handle); hideTimer?.Stop(); base.Hide(); }
        public new void Show()
        {
            base.Show(); Place();
            if (AutoHide) hideTimer?.Start();
            // back from a game: the islands drop in one after another (desktop profile only)
            if (Theme.Motion) for (int i = 0; i < pills.Count; i++) Ui.FadeIn(pills[i], 220, 0.9, -14, i * 60);
        }
    }

    static class Power
    {
        public static void Sleep() { if (!Paths.Preview) Native.SetSuspendState(false, false, false); }
        // EWX_* flags; forcing only hung apps (FORCEIFHUNG) lets responsive apps still save first.
        public static void Restart() { if (Confirm("Restart now?")) Exit(0x02 /*REBOOT*/, "/r /t 0 /f"); }
        public static void Shutdown() { if (Confirm("Shut down now?")) Exit(0x01 /*SHUTDOWN*/ | 0x08 /*POWEROFF*/, "/s /t 0 /f"); }
        public static void SignOut() { if (Confirm("Sign out now?")) Exit(0x00 /*LOGOFF*/, "/l"); }

        // The Win32 API first: it does not depend on shutdown.exe being found, nor on the /hybrid fast-startup
        // flag (which this machine's firmware/hypervisor does not support, so the old "/s /hybrid" failed
        // silently). shutdown.exe is kept as a fallback, now with the full path and no /hybrid.
        static void Exit(uint flags, string fallbackArgs)
        {
            if (Paths.Preview) { Log.Write("power-preview " + fallbackArgs); return; }
            Native.EnableShutdownPrivilege();
            if (Native.ExitWindowsEx(flags | 0x10 /*FORCEIFHUNG*/, 0x80000000 /*planned*/)) { Log.Write("power flags=" + flags); return; }
            int err = System.Runtime.InteropServices.Marshal.GetLastWin32Error();
            Log.Write("power-api-failed flags=" + flags + " err=" + err + " -> shutdown.exe");
            try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(System.IO.Path.Combine(System.Environment.SystemDirectory, "shutdown.exe"), fallbackArgs) { UseShellExecute = false, CreateNoWindow = true }); }
            catch (Exception e) { Log.Write("power-run-failed args=\"" + fallbackArgs + "\" error=\"" + e.Message + "\""); }
        }

        // The confirmation must sit on top of whatever app is in front (BAKA is the shell), or the user never
        // sees it and the button looks dead. A tiny topmost owner window off-screen guarantees that.
        static bool Confirm(string q)
        {
            if (Paths.Preview) return true;
            var owner = new Window { Width = 1, Height = 1, Left = -4000, Top = -4000, WindowStyle = WindowStyle.None, ShowInTaskbar = false, Topmost = true, AllowsTransparency = true, Background = Brushes.Transparent };
            try { owner.Show(); owner.Activate(); return MessageBox.Show(owner, q, "BAKA", MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes; }
            catch { return MessageBox.Show(q, "BAKA", MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes; }
            finally { try { owner.Close(); } catch { } }
        }
    }
}
