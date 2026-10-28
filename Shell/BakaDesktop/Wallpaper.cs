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
        static Window video; static MediaElement media;
        [DllImport("user32.dll")] static extern IntPtr SetParent(IntPtr child, IntPtr parent);
        [DllImport("user32.dll")] static extern bool SetSysColors(int count, int[] elements, int[] colors);

        public static void Apply(bool force)
        {
            var w = App.Settings.Wallpaper;
            string mode = Json.Str(w, "mode", "Image"), path = Paths.Expand(Json.Str(w, "path")), fit = Json.Str(w, "fit", "Fill");
            if (mode != "Video") Stop();
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

        static void StartVideo(string path, string fit, bool muted)
        {
            Stop();
            IntPtr host = DesktopHost();
            if (host == IntPtr.Zero) { Log.Write("video-wallpaper-no-host"); return; }
            var b = System.Windows.Forms.Screen.PrimaryScreen.Bounds;
            video = new Window { WindowStyle = WindowStyle.None, ResizeMode = ResizeMode.NoResize, ShowInTaskbar = false, ShowActivated = false, Background = Brushes.Black, Left = -32000, Top = -32000, Width = 10, Height = 10, Title = "BAKA Video Wallpaper" };
            media = new MediaElement { LoadedBehavior = MediaState.Manual, UnloadedBehavior = MediaState.Manual, IsMuted = muted, Volume = muted ? 0 : 0.5, Source = new Uri(path) };
            media.Stretch = fit == "Fit" ? Stretch.Uniform : fit == "Stretch" ? Stretch.Fill : fit == "Center" ? Stretch.None : Stretch.UniformToFill;
            media.MediaEnded += (o, e) => { media.Position = TimeSpan.Zero; media.Play(); };
            media.MediaFailed += (o, e) => { Log.Write("video-wallpaper-failed error=\"" + e.ErrorException?.Message + "\""); Stop(); App.Settings.Wallpaper["mode"] = "Image"; Apply(true); };
            video.Content = media;
            video.Show();
            var h = new WindowInteropHelper(video).Handle;
            SetParent(h, host);
            Native.SetWindowPos(h, IntPtr.Zero, 0, 0, b.Width, b.Height, Native.SWP_NOACTIVATE | Native.SWP_NOZORDER | Native.SWP_SHOWWINDOW);
            media.Play();
            Log.Write("video-wallpaper-started path=\"" + path + "\"");
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
        public static void Pause(bool pause)
        {
            if (media == null) return;
            if (pause && Json.Bool(App.Settings.Wallpaper, "pauseInGames", true)) media.Pause(); else if (!pause) media.Play();
        }
        public static void Stop()
        {
            try { media?.Stop(); media?.Close(); } catch { }
            try { video?.Close(); } catch { }
            media = null; video = null;
        }
    }
}
