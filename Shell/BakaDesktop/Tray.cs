using System;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;

namespace Baka.Desktop
{
    // BAKA's system tray. BAKA hides the Windows taskbar, so the notification icons (Discord, Steam, drivers,
    // GPU tools...) have nowhere to show. Instead of un-hiding the whole taskbar, BAKA moves Windows' real
    // notification-icons window (TrayNotifyWnd) into a small BAKA flyout while it is open, and moves it
    // straight back to the taskbar when the flyout closes. The icons are the genuine ones, so their clicks and
    // right-click menus work. If moving it fails, it falls back to briefly showing the Windows taskbar.
    //
    // The flyout is a plain (non-layered) window: a per-pixel-transparent WPF window cannot host a child
    // window from another process, so this one uses a solid themed surface with DWM rounded corners.
    class TrayFlyout : Window
    {
        static TrayFlyout current;
        public static bool IsOpen => current != null && current.IsVisible;
        static IntPtr grabbed, trayOwner;       // the moved TrayNotifyWnd and the Shell_TrayWnd it came from
        static Native.RECT trayRect;            // where it sat in the taskbar
        const int Pad = 8;
        IntPtr handle;

        public static void CloseIfOpen() { if (current != null) try { current.Close(); } catch { } }

        // Borrowing Windows' real tray into a BAKA flyout was tested (--tray-test) and did NOT reliably hand
        // the tray back to the taskbar, which would lose the icons until a restart. So the tray button shows
        // the Windows tray for a few seconds (PeekTray) for now; a native BAKA tray that receives the icons
        // itself (the Shell_NotifyIcon protocol) is the real fix and is a larger, separate piece of work.
        // With BAKA's own tray running, the icons are already in the status island: this hides / shows them.
        public static void Toggle(Window anchor) { if (Paths.Preview) return; if (BakaTray.Running && App.Bar != null) App.Bar.ToggleTray(); else App.PeekTray(); }

        // kept only so the --tray-test harness can still exercise the reparent path for future work
        internal static void GrabForTest(Window host) { }

        TrayFlyout()
        {
            WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize; ShowInTaskbar = false; Topmost = true;
            AllowsTransparency = false; Background = Theme.B(Theme.Current.Surface, 255); Title = "BAKA Tray"; UseLayoutRounding = true;
            Deactivated += (o, e) => { if (!SelfTest.Running) Close(); };
            KeyDown += (o, e) => { if (e.Key == System.Windows.Input.Key.Escape) Close(); };
            Closed += (o, e) => { Restore(); if (current == this) current = null; };
            SourceInitialized += (o, e) => { handle = new WindowInteropHelper(this).Handle; Native.DarkFrame(handle); Native.RoundCorners(handle); Native.SetWindowLongPtr(handle, Native.GWL_EXSTYLE, new IntPtr(Native.ExStyle(handle) | Native.WS_EX_TOOLWINDOW)); };
        }

        bool Grab()
        {
            try
            {
                trayOwner = ExplorerIntegration.ExplorerTaskbar(); // Explorer's, not BAKA's tray host of the same class
                if (trayOwner == IntPtr.Zero) return false;
                var tray = Native.FindWindowEx(trayOwner, IntPtr.Zero, "TrayNotifyWnd", null);
                if (tray == IntPtr.Zero || !Native.GetWindowRect(tray, out trayRect)) return false;
                int w = trayRect.Right - trayRect.Left, h = trayRect.Bottom - trayRect.Top;
                if (w < 20 || h < 10) return false;
                var helper = new WindowInteropHelper(this); handle = helper.EnsureHandle();
                double s = Ui.Scale(this); if (s <= 0) s = 1;
                Width = w / s + Pad * 2; Height = h / s + Pad * 2;
                Left = SystemParameters.PrimaryScreenWidth - Width - 10;
                Top = TopBar.BarHeight + 8;
                Native.SetParentWindow(tray, handle);
                int px = (int)Math.Round(Pad * s);
                Native.SetWindowPos(tray, IntPtr.Zero, px, px, w, h, Native.SWP_NOZORDER | Native.SWP_SHOWWINDOW);
                Native.ShowWindow(tray, Native.SW_SHOW);
                grabbed = tray;
                Log.Write("tray-grabbed size=" + w + "x" + h);
                return true;
            }
            catch (Exception e) { Log.Write("tray-grab-failed error=\"" + e.Message + "\""); try { Restore(); } catch { } return false; }
        }

        // Always safe to call. Puts the tray back under the taskbar and asks Explorer to re-lay it out.
        public static void Restore()
        {
            if (grabbed == IntPtr.Zero) return;
            var tray = grabbed; grabbed = IntPtr.Zero;
            try
            {
                if (trayOwner != IntPtr.Zero && Native.IsWindow(trayOwner))
                {
                    Native.SetParentWindow(tray, trayOwner);
                    if (Native.GetWindowRect(trayOwner, out var ob))
                        Native.SetWindowPos(tray, IntPtr.Zero, trayRect.Left - ob.Left, trayRect.Top - ob.Top, trayRect.Right - trayRect.Left, trayRect.Bottom - trayRect.Top, Native.SWP_NOZORDER);
                    // nudge Explorer to rebuild the tray layout (WM_SETTINGCHANGE)
                    Native.SendMessageTimeout(trayOwner, 0x001A, IntPtr.Zero, IntPtr.Zero, 0, 300, out _);
                    Log.Write("tray-restored");
                }
            }
            catch (Exception e) { Log.Write("tray-restore-failed error=\"" + e.Message + "\""); }
        }

        // On BAKA start: if the taskbar exists but its tray window is gone, a previous BAKA ended while the
        // tray was still borrowed, so Explorer is restarted once to rebuild the tray. Only acts when the tray
        // is genuinely missing, so a normal start never restarts Explorer.
        public static void HealOnStart()
        {
            if (Paths.Preview) return;
            try
            {
                // Explorer's own taskbar only: BAKA's tray host has the same class and must never be mistaken
                // for a broken Explorer tray (that would restart Explorer for nothing)
                var owner = ExplorerIntegration.ExplorerTaskbar();
                if (owner == IntPtr.Zero) return;
                if (Native.FindWindowEx(owner, IntPtr.Zero, "TrayNotifyWnd", null) != IntPtr.Zero) return;
                System.Threading.Thread.Sleep(1500);
                owner = ExplorerIntegration.ExplorerTaskbar();
                if (owner != IntPtr.Zero && Native.FindWindowEx(owner, IntPtr.Zero, "TrayNotifyWnd", null) == IntPtr.Zero)
                {
                    Log.Write("tray-missing-on-start; restarting Explorer to rebuild it");
                    foreach (var p in System.Diagnostics.Process.GetProcessesByName("explorer")) { try { if (p.SessionId == System.Diagnostics.Process.GetCurrentProcess().SessionId) p.Kill(); } catch { } }
                }
            }
            catch { }
        }
    }
}
