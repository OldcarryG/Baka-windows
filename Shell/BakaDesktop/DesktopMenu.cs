using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Baka.Desktop
{
    // BAKA's own right-click menu on the desktop. With the helper Explorer running, a right-click on the
    // empty desktop went to Explorer's desktop view (its icons are hidden, the view is not), so Windows' own
    // desktop menu appeared. BAKA lays one invisible window over the desktop, just above it and below every
    // app and widget: it costs nothing (no hooks, no input monitoring; it only gets the clicks that land on
    // the bare desktop) and opens the BAKA menu on right-click. Only while desktop icons are hidden (with
    // icons shown, the Windows desktop menu is the useful one) and never during a game.
    static class DesktopMenu
    {
        static Catcher catcher;
        public static bool Wanted => App.Settings != null && !Paths.Preview && !App.BakaHidden
            && Json.Bool(App.Settings.Integration, "hideDesktopIcons", true) && Json.Bool(App.Settings.Integration, "bakaDesktopMenu", true);

        public static void Apply()
        {
            try
            {
                if (!Wanted) { catcher?.Hide(); return; }
                if (catcher == null || catcher.IsDisposed) catcher = new Catcher();
                if (!catcher.Visible) { catcher.Show(); Log.Write("desktop-menu on"); }
                Sink();
            }
            catch (Exception e) { Log.Write("desktop-menu-failed error=\"" + e.Message + "\""); }
        }
        public static void Hide() { try { catcher?.Hide(); } catch { } }

        // Back to the bottom (just above the desktop), below widgets that also sit at the bottom: called after
        // a widget moves itself down, so the catcher never covers a widget.
        public static void Sink()
        {
            if (catcher == null || catcher.IsDisposed || !catcher.Visible) return;
            var b = Screen.PrimaryScreen.Bounds;
            Native.SetWindowPos(catcher.Handle, Native.HWND_BOTTOM, b.X, b.Y, b.Width, b.Height, Native.SWP_NOACTIVATE);
            BakaBackdrop.Sink(); // the wallpaper stays below it
        }

        static void Open()
        {
            Ui.ShowMenuAtPointer(
                Ui.Item("Change wallpaper…", 0xEB9F, () => SettingsWindow.Open("Wallpaper")),
                Ui.Item("Widgets…", 0xF246, () => SettingsWindow.Open("Widgets")),
                Ui.Item("Appearance…", 0xE771, () => SettingsWindow.Open("Appearance")),
                "-",
                Ui.Item("Open BAKA Files", 0xE8B7, () => Files.Open(null)),
                Ui.Item("Open Desktop folder", 0xE8FC, () => Files.Open(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory))),
                Ui.Item("Open Terminal", 0xE756, () => Launcher.Run("terminal", () => { try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("wt.exe") { UseShellExecute = true }); } catch { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("powershell.exe") { UseShellExecute = true }); } })),
                "-",
                Ui.Item("Display settings", 0xE7F4, () => Launcher.Run("ms-settings:display", () => System.Diagnostics.Process.Start("ms-settings:display"))),
                Ui.Item("BAKA Settings", 0xE713, () => SettingsWindow.Open()));
        }

        sealed class Catcher : Form
        {
            [DllImport("user32.dll")] static extern bool SetLayeredWindowAttributes(IntPtr h, uint key, byte alpha, uint flags);
            public Catcher()
            {
                FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; StartPosition = FormStartPosition.Manual;
                BackColor = System.Drawing.Color.Black; Text = "BAKA Desktop";
                var b = Screen.PrimaryScreen.Bounds; Bounds = b;
            }
            protected override CreateParams CreateParams
            {
                get { var cp = base.CreateParams; cp.ExStyle |= 0x00080000 /*LAYERED*/ | 0x80 /*TOOLWINDOW*/ | 0x08000000 /*NOACTIVATE*/; return cp; }
            }
            protected override bool ShowWithoutActivation => true;
            protected override void OnHandleCreated(EventArgs e)
            {
                base.OnHandleCreated(e);
                // alpha 1 of 255: invisible, but still receives the clicks that land on it
                SetLayeredWindowAttributes(Handle, 0, 1, 0x2 /*LWA_ALPHA*/);
            }
            protected override void WndProc(ref Message m)
            {
                if (m.Msg == 0x0021 /*WM_MOUSEACTIVATE*/) { m.Result = (IntPtr)3 /*MA_NOACTIVATE*/; return; }
                if (m.Msg == 0x0205 /*WM_RBUTTONUP*/) { try { App.Ui.BeginInvoke(new Action(Open)); } catch { } return; }
                if (m.Msg == 0x0201 /*WM_LBUTTONDOWN*/) { try { App.Ui.BeginInvoke(new Action(() => { ControlCenter.Current?.Close(); })); } catch { } }
                base.WndProc(ref m);
            }
        }
    }
}
