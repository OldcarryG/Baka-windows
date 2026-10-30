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

        // A path that exists and ends in a format Windows can show as a wallpaper. Used to reject a missing
        // file or a leftover video path before it is handed to Windows (which would paint the desktop black).
        static bool IsImageFile(string path)
        {
            if (string.IsNullOrEmpty(path) || !File.Exists(path)) return false;
            switch (Path.GetExtension(path).ToLowerInvariant())
            {
                case ".png": case ".jpg": case ".jpeg": case ".bmp": case ".gif": case ".tif": case ".tiff": case ".jfif": case ".dib": return true;
                default: return false;
            }
        }
        // The shipped picture used whenever a video wallpaper stops (failed / display reset), so the fallback
        // is a real image and never the now-dead video path.
        static string FallbackImage() => Paths.Shipped("BAKA-BlackGlass-4K.png") ?? Paths.Shipped("BAKA-Stealth-4K.png") ?? "";

        // WebP pictures. Settings > Wallpaper offers them, but they are not a format Windows' wallpaper setting
        // is given directly, so 12.27.1 rejected them and showed the BAKA picture instead (and saved that over
        // the user's choice). Now BAKA converts the picture once to PNG with Windows' own image decoder (the
        // WebP Image Extension, through WIC), off the UI thread, and gives Windows the PNG. The user's file
        // stays the setting; the PNG is kept in State\Wallpaper and replaced when another picture is converted.
        static bool NeedsConversion(string path) => !string.IsNullOrEmpty(path) && string.Equals(Path.GetExtension(path), ".webp", StringComparison.OrdinalIgnoreCase) && File.Exists(path);
        static string ConvertedPath(string path)
        {
            var fi = new FileInfo(path);
            string key = fi.FullName.ToLowerInvariant() + "|" + fi.Length + "|" + fi.LastWriteTimeUtc.Ticks;
            string hash;
            using (var sha = System.Security.Cryptography.SHA256.Create()) hash = BitConverter.ToString(sha.ComputeHash(System.Text.Encoding.UTF8.GetBytes(key))).Replace("-", "").Substring(0, 12);
            return Path.Combine(Paths.State, "Wallpaper", Path.GetFileNameWithoutExtension(path) + "-" + hash + ".png");
        }
        static string converting, failedConversion;
        static void ConvertThenApply(string source, string target)
        {
            if (converting != null) return;
            converting = source;
            var t = new System.Threading.Thread(() =>
            {
                string error = null; int width = 0, height = 0;
                try
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(target));
                    System.Windows.Media.Imaging.BitmapFrame frame;
                    using (var s = File.OpenRead(source))
                        frame = System.Windows.Media.Imaging.BitmapDecoder.Create(s, System.Windows.Media.Imaging.BitmapCreateOptions.None, System.Windows.Media.Imaging.BitmapCacheOption.OnLoad).Frames[0];
                    width = frame.PixelWidth; height = frame.PixelHeight;
                    var png = new System.Windows.Media.Imaging.PngBitmapEncoder();
                    png.Frames.Add(frame);
                    string tmp = target + ".tmp";
                    using (var o = File.Create(tmp)) png.Save(o);
                    if (File.Exists(target)) File.Delete(target);
                    File.Move(tmp, target);
                    // only the newest converted picture is kept (a 4K PNG is 10 to 30 MB)
                    foreach (var old in Directory.GetFiles(Path.GetDirectoryName(target)))
                        if (!string.Equals(old, target, StringComparison.OrdinalIgnoreCase)) try { File.Delete(old); } catch { }
                }
                catch (Exception e) { error = e.Message; try { File.Delete(target + ".tmp"); } catch { } }
                Post(() =>
                {
                    converting = null;
                    if (error == null) Log.Write("wallpaper-converted from=webp size=" + width + "x" + height);
                    else
                    {
                        failedConversion = source;
                        Log.Write("wallpaper-convert-failed error=\"" + error + "\"");
                        Osd.Show(0xE7BA, "Windows cannot read this picture  ·  BAKA's picture is shown");
                    }
                    Apply(true);
                });
            }) { IsBackground = true, Name = "BAKA wallpaper picture" };
            t.SetApartmentState(System.Threading.ApartmentState.STA); // WPF's image classes
            t.Start();
        }

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
                    // The stored path must be a real picture. A missing file, or a leftover video path (for
                    // example after a video wallpaper failed and fell back to Image), would otherwise be
                    // handed to Windows as the wallpaper and paint the desktop solid black. Fall back to a
                    // shipped picture and remember the correction so the desktop is never black.
                    // A WebP picture is shown through its converted PNG; while it is being converted (the first
                    // time, under a second) the current wallpaper stays.
                    if (NeedsConversion(path))
                    {
                        string png = ConvertedPath(path);
                        if (File.Exists(png)) path = png;
                        else if (!string.Equals(failedConversion, path, StringComparison.OrdinalIgnoreCase)) { ConvertThenApply(path, png); return; }
                    }
                    if (!IsImageFile(path))
                    {
                        path = Paths.Shipped("BAKA-BlackGlass-4K.png") ?? Paths.Shipped("BAKA-Stealth-4K.png");
                        if (path == null) return;
                        if (!string.Equals(Json.Str(w, "path"), path, StringComparison.OrdinalIgnoreCase)) { w["path"] = path; App.Settings.Save(); }
                    }
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
                App.Settings.Wallpaper["mode"] = "Image"; App.Settings.Wallpaper["lastVideoError"] = why;
                App.Settings.Wallpaper["path"] = FallbackImage();
                App.Settings.Save();
                Apply(true);
            });
            video.Open(host, PrimaryInHost());
            if (watch == null)
            {
                watch = new System.Windows.Threading.DispatcherTimer(System.Windows.Threading.DispatcherPriority.Background) { Interval = TimeSpan.FromSeconds(1) };
                watch.Tick += (o, e) => Update();
                Microsoft.Win32.SystemEvents.SessionSwitch += (o, e) => { locked = e.Reason == Microsoft.Win32.SessionSwitchReason.SessionLock || e.Reason == Microsoft.Win32.SessionSwitchReason.ConsoleDisconnect || e.Reason == Microsoft.Win32.SessionSwitchReason.RemoteDisconnect; Post(Update); };
                Microsoft.Win32.SystemEvents.DisplaySettingsChanged += (o, e) => Post(OnDisplayChanged);
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
            bool focus = FocusMode.PausesWallpaper;
            bool play = !coveredNow && !onBattery && !locked && !focus;
            if (!video.Ready) return;
            if (play && !video.Playing) { video.Play(); Log.Write("video-wallpaper-playing"); }
            else if (!play && video.Playing) { video.Pause(); Log.Write("video-wallpaper-paused reason=" + (locked ? "locked" : focus ? "focus" : onBattery ? "battery" : "covered")); }
        }
        // Focus mode changed: play or pause now instead of on the next 1 s check.
        public static void Refresh() => Update();
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
            if (found != IntPtr.Zero) return found;
            // BAKA is the shell: Explorer's desktop WorkerW is gone, so the video goes into BAKA's own backdrop.
            return ShellMode.Active ? BakaBackdrop.EnsureHost() : found;
        }
        // The display driver resetting (a recovered GPU hang / TDR) fires DisplaySettingsChanged. The logs
        // showed a display watchdog event and then a hard freeze while the 4K video wallpaper was decoding, so
        // if the display resets twice within a short window the video is stopped and the picture is shown
        // instead, rather than feeding a struggling GPU a continuous 4K decode. The user can switch it back on.
        static readonly System.Collections.Generic.List<DateTime> displayResets = new System.Collections.Generic.List<DateTime>();
        static void OnDisplayChanged()
        {
            if (video == null) return;
            displayResets.Add(DateTime.Now); displayResets.RemoveAll(t => t < DateTime.Now.AddSeconds(45));
            if (displayResets.Count >= 2)
            {
                Log.Write("video-wallpaper-stopped reason=display-reset count=" + displayResets.Count);
                displayResets.Clear();
                App.Settings.Wallpaper["mode"] = "Image";
                App.Settings.Wallpaper["path"] = FallbackImage();
                App.Settings.Wallpaper["lastVideoError"] = "The video wallpaper was stopped because the display driver reset, which can go with a freeze. Turn it back on in Settings \u203a Wallpaper if you want it.";
                App.Settings.Save();
                Apply(true);
                return;
            }
            video.Place(PrimaryInHost());
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
