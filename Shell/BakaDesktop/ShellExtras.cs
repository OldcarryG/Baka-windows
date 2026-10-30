using System;
using System.Runtime.InteropServices;

namespace Baka.Desktop
{
    // Small shell jobs that Explorer normally does and that stop without it: the pop-up when a USB drive is
    // plugged in (Explorer's AutoPlay), and the keyboard-language badge. Only active in shell mode.
    static class ShellExtras
    {
        // WM_DEVICECHANGE with DBT_DEVICEARRIVAL (0x8000) for a volume: show a "new drive" notice that opens
        // it in BAKA Files. Volume device messages are broadcast to top-level windows, so no registration is
        // needed.
        static DateTime lastDrive = DateTime.MinValue;
        public static void OnDeviceChange(IntPtr wParam, IntPtr lParam)
        {
            try
            {
                if (wParam.ToInt64() != 0x8000 || lParam == IntPtr.Zero) return;
                if (Marshal.ReadInt32(lParam, 4) != 2 /*DBT_DEVTYP_VOLUME*/) return;
                if ((DateTime.Now - lastDrive).TotalMilliseconds < 800) return; // one message can repeat
                lastDrive = DateTime.Now;
                int mask = Marshal.ReadInt32(lParam, 12);
                for (int i = 0; i < 26; i++)
                {
                    if ((mask & (1 << i)) == 0) continue;
                    string drive = (char)('A' + i) + ":";
                    string label = DriveLabel(drive);
                    Log.Write("usb-drive-arrived " + drive);
                    NotificationPopup.Show(new NoteItem { App = "Drive", Title = "New drive " + drive + (string.IsNullOrEmpty(label) ? "" : " (" + label + ")"), Body = "Open in BAKA Files", Click = () => Files.Open(drive + "\\") });
                }
            }
            catch (Exception e) { Log.Write("device-change-failed error=\"" + e.Message + "\""); }
        }
        static string DriveLabel(string drive)
        {
            try { var d = new System.IO.DriveInfo(drive); return d.IsReady ? d.VolumeLabel : ""; } catch { return ""; }
        }

        // ---- keyboard language ----
        [DllImport("user32.dll")] static extern int GetKeyboardLayoutList(int count, [Out] IntPtr[] list);
        [DllImport("user32.dll")] static extern IntPtr GetKeyboardLayout(uint threadId);
        [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
        // How many layouts are installed (the badge only shows when there is more than one to switch between).
        public static int LayoutCount() { try { return GetKeyboardLayoutList(0, null); } catch { return 1; } }
        // The two-letter code of the layout the focused window is using (EN, FR, HI...).
        public static string CurrentLanguage()
        {
            try
            {
                uint t = GetWindowThreadProcessId(GetForegroundWindow(), out _);
                int lcid = GetKeyboardLayout(t).ToInt32() & 0xFFFF;
                if (lcid == 0) lcid = System.Globalization.CultureInfo.CurrentCulture.LCID;
                var c = new System.Globalization.CultureInfo(lcid);
                return c.TwoLetterISOLanguageName.ToUpperInvariant();
            }
            catch { return ""; }
        }
    }
}
