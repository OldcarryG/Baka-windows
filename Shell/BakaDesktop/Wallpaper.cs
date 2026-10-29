using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using Microsoft.Win32;

namespace Baka.Desktop
{
    // The desktop background: a picture or colour through Windows itself, or a looping video placed behind
    // the desktop (it pauses during games and when a window covers the screen).
    static class Wallpaper
    {
        static VideoPlayer video;
        static System.Windows.Threading.DispatcherTimer watch;
        static bool inGame, locked, coveredNow, onBattery;
        [DllImport("user32.dll")] static extern bool SetSysColors(int count, int[] elements, int[] colors);
        public static VideoPlayer Current => video;
        public static string State => video == null ? "off" : video.Suspended ? "suspended" : video.Playing ? "playing" : "paused";

        public static void Apply(bool force)
        {
            var w = App.Settings.Wallpaper;
            string mode = Json.Str(w, "mode", "Image"), path = Paths.Expand(Json.Str(w, "path")), fit = Json.Str(w, "fit", "Fill");
            if (mode != "Video") Stop();
            else if (!force && video != null && string.Equals(video.Path, path, StringComparison.OrdinalIgnoreCase)) { video.Fit = fit; video.SetMuted(Json.Bool(w, "muted", true)); return; }
            if (Paths.Preview) { Log.Write("wallpaper-preview mode=" + mode); return; }
            try
            {
                if (mode == "Image")
                {
                    if (!File.Exists(path)) path = Paths.Shipped("BAKA-Stealth-4K.png") ?? Paths.Shipped("BAKA-BlackGlass-4K.png");
                    if (path == null) return;
                    string current = Registry.CurrentUser.OpenSubKey(@"Control Panel\Desktop")?.GetValue("WallPaper") as string;
                    if (!force && string.Equals(current, path, StringComparison.OrdinalIgnoreCase)) return;
                    var style = fit switch { "Fit" => ("6", "0"), "Stretch" => ("2", "0"), "Center" => ("0", "0"), "Span" => ("22", "0"), _ => ("10", "0") };
                    using (var k = Registry.CurrentUser.CreateSubKey(@"Control Panel\Desktop")) { k.SetValue("WallpaperStyle", style.Item1); k.SetValue("TileWallpaper", style.Item2); }
                    Native.SystemParametersInfoString(20, 0, path, 3);
                    Log.Write("wallpaper-image path=\"" + path + "\"");
                }
                else if (mode == "Color")
                {
                    var c = Theme.C(Json.Str(w, "color", "#05060A"));
                    SetSysColors(1, new[] { 1 }, new[] { c.R | (c.G << 8) | (c.B << 16) });
                    using (var k = Registry.CurrentUser.CreateSubKey(@"Control Panel\Colors")) k.SetValue("Background", c.R + " " + c.G + " " + c.B);
                    Native.SystemParametersInfoString(20, 0, "", 3);
                }
                else if (mode == "Video" && File.Exists(path)) StartVideo(path, fit, Json.Bool(w, "muted", true));
            }
            catch (Exception e) { Log.Write("wallpaper-failed error=\"" + e.Message + "\""); }
        }

        // The video covers the primary monitor (other monitors keep the Windows picture). It is drawn by
        // Media Foundation on the GPU (see VideoPlayer), and it only plays while you can see it: it pauses when
        // a maximized or fullscreen window covers the desktop, on battery, and while the PC is locked, and it
        // is closed entirely (decoder and video memory freed) while a game runs.
        static void StartVideo(string path, string fit, bool muted)
        {
            Stop();
            IntPtr host = DesktopHost();
            if (host == IntPtr.Zero) { Log.Write("video-wallpaper-no-host"); return; }
            video = new VideoPlayer(path, fit, muted);
            // a video Windows cannot play falls back to the picture; Settings > Wallpaper shows why
            video.Failed += why => Post(() =>
            {
                Stop();
                App.Settings.Wallpaper["mode"] = "Image"; App.Settings.Wallpaper["lastVideoError"] = why; App.Settings.Save();
                Apply(true);
            });
            video.Open(host, PrimaryInHost());
            if (watch == null)
            {
                watch = new System.Windows.Threading.DispatcherTimer(System.Windows.Threading.DispatcherPriority.Background) { Interval = TimeSpan.FromSeconds(1) };
                watch.Tick += (o, e) => Update();
                Microsoft.Win32.SystemEvents.SessionSwitch += (o, e) => { locked = e.Reason == Microsoft.Win32.SessionSwitchReason.SessionLock || e.Reason == Microsoft.Win32.SessionSwitchReason.ConsoleDisconnect || e.Reason == Microsoft.Win32.SessionSwitchReason.RemoteDisconnect; Post(Update); };
                Microsoft.Win32.SystemEvents.DisplaySettingsChanged += (o, e) => Post(() => video?.Place(PrimaryInHost()));
            }
            watch.Start();
            Log.Write("video-wallpaper-started path=\"" + path + "\" fit=" + fit);
        }
        // the primary monitor in the coordinates of the desktop host window (which spans every monitor)
        static System.Drawing.Rectangle PrimaryInHost()
        {
            var b = System.Windows.Forms.Screen.PrimaryScreen.Bounds; var v = System.Windows.Forms.SystemInformation.VirtualScreen;
            return new System.Drawing.Rectangle(b.X - v.X, b.Y - v.Y, b.Width, b.Height);
        }
        // Plays only while it can be seen and nothing more important needs the GPU.
        static void Update()
        {
            if (video == null) return;
            var w = App.Settings.Wallpaper;
            coveredNow = Json.Bool(w, "pauseWhenCovered", true) && DesktopCovered();
            onBattery = Json.Bool(w, "pauseOnBattery", true) && System.Windows.Forms.SystemInformation.PowerStatus.PowerLineStatus == System.Windows.Forms.PowerLineStatus.Offline;
            if (inGame && Json.Bool(w, "pauseInGames", true)) { if (!video.Suspended) { video.Suspend(); Log.Write("video-wallpaper-suspended reason=game"); } return; }
            if (video.Suspended) { video.Resume(); Log.Write("video-wallpaper-resumed"); return; }
            bool play = !coveredNow && !onBattery && !locked;
            if (!video.Ready) return;
            if (play && !video.Playing) { video.Play(); Log.Write("video-wallpaper-playing"); }
            else if (!play && video.Playing) { video.Pause(); Log.Write("video-wallpaper-paused reason=" + (locked ? "locked" : onBattery ? "battery" : "covered")); }
        }
        // Any visible, not minimized window (not BAKA's own, not the shell) that is maximized or covers the whole
        // primary monitor hides the wallpaper, whether or not it is the window in front.
        static readonly uint myPid = (uint)System.Diagnostics.Process.GetCurrentProcess().Id;
        static bool DesktopCovered()
        {
            var p = System.Windows.Forms.Screen.PrimaryScreen; var b = p.Bounds; bool covered = false;
            Native.EnumWindows((h, l) =>
            {
                if (!Native.IsWindowVisible(h) || Native.IsIconic(h) || Native.IsCloaked(h)) return true;
                if ((Native.ExStyle(h) & Native.WS_EX_TOOLWINDOW) != 0) return true;
                Native.GetWindowThreadProcessId(h, out uint pid);
                if (pid == myPid) return true;
                string cls = Native.ClassName(h);
                if (cls == "Progman" || cls == "WorkerW" || cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd") return true;
                if (!Native.GetWindowRect(h, out var r)) return true;
                bool onPrimary = r.Left < b.Right && r.Right > b.Left && r.Top < b.Bottom && r.Bottom > b.Top && System.Windows.Forms.Screen.FromHandle(h).DeviceName == p.DeviceName;
                if (!onPrimary) return true;
                if (Native.IsZoomed(h) || (r.Left <= b.Left && r.Top <= b.Top && r.Right >= b.Right && r.Bottom >= b.Bottom)) { covered = true; return false; }
                return true;
            }, IntPtr.Zero);
            return covered;
        }
        // The window that sits between the wallpaper and the desktop icons (Windows creates it on request).
        static IntPtr DesktopHost()
        {
            var progman = Native.FindWindow("Progman", null);
            Native.SendMessageTimeout(progman, 0x052C, new IntPtr(0xD), new IntPtr(1), 2, 1000, out _);
            Native.SendMessageTimeout(progman, 0x052C, IntPtr.Zero, IntPtr.Zero, 2, 1000, out _);
            // Windows 11 24H2 and later: the WorkerW is a child of Progman.
            var child = Native.FindWindowEx(progman, IntPtr.Zero, "WorkerW", null);
            if (child != IntPtr.Zero) return child;
            IntPtr found = IntPtr.Zero;
            Native.EnumWindows((h, p) =>
            {
                if (Native.FindWindowEx(h, IntPtr.Zero, "SHELLDLL_DefView", null) != IntPtr.Zero) found = Native.FindWindowEx(IntPtr.Zero, h, "WorkerW", null);
                return found == IntPtr.Zero;
            }, IntPtr.Zero);
            return found;
        }
        static void Post(Action a) { try { App.Ui?.BeginInvoke(a); } catch { } }
        // called when a game starts (true) and ends (false)
        public static void Pause(bool pause) { inGame = pause; Update(); }
        public static void Stop()
        {
            watch?.Stop();
            try { video?.Dispose(); } catch { }
            video = null;
        }
    }
}
