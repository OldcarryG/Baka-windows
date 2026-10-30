using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Baka.Desktop
{
    // The background of the dock, the menu bar islands and the widgets: the theme's glass (default), a
    // colour, a picture or a looping muted video, chosen in Settings > Appearance. Pictures and videos are
    // drawn filling the surface, with a dark veil on top so the icons and text stay readable. Every
    // surface that uses the same video shares one player, and videos stop while a game runs.
    static class Surfaces
    {
        public static readonly string[] Ids = { "dock", "bar", "widgets" };
        public static readonly string[] VideoExtensions = { ".mp4", ".m4v", ".mov", ".wmv", ".mkv", ".webm", ".avi" };
        public static string Title(string id) => id == "dock" ? "Dock" : id == "bar" ? "Menu bar" : "Widgets";

        public static Dictionary<string, object> Of(string id) => Json.Section(Json.Section(App.Settings.Appearance, "surfaces"), id);
        public static string Kind(string id)
        {
            if (App.Settings == null) return "Glass";
            string k = Json.Str(Of(id), "kind", "Glass");
            return k == "Color" || k == "Image" || k == "Video" ? k : "Glass";
        }
        // Each widget can have its own background ("widget:clock", "widget:media", ...); a widget left on
        // "Same as all widgets" uses the shared "widgets" one.
        public static bool OwnBackground(string id) { var k = Json.Str(Of(id), "kind", ""); return k == "Glass" || k == "Color" || k == "Image" || k == "Video"; }
        public static string Resolve(string id) => id != null && id.StartsWith("widget:") && !OwnBackground(id) ? "widgets" : id;

        static readonly Dictionary<string, Brush> brushes = new Dictionary<string, Brush>(StringComparer.OrdinalIgnoreCase);
        static readonly Dictionary<string, SurfaceVideo> players = new Dictionary<string, SurfaceVideo>(StringComparer.OrdinalIgnoreCase);
        static bool paused;

        // null = keep the theme's glass
        public static Brush Background(string id)
        {
            try
            {
                id = Resolve(id);
                string kind = Kind(id);
                if (kind == "Glass") return null;
                var s = Of(id);
                if (kind == "Color")
                {
                    string hex = Json.Str(s, "color", "#16161A");
                    return Theme.B(Theme.IsHex(hex) ? hex : "#16161A", 240);
                }
                string path = Paths.Expand(Json.Str(s, "path"));
                if (string.IsNullOrEmpty(path) || !File.Exists(path)) return null;
                int dim = Math.Max(0, Math.Min(85, Json.Int(s, "dim", 45)));
                string key = kind + "|" + path + "|" + dim;
                if (brushes.TryGetValue(key, out var hit)) return hit;
                var veil = new GeometryDrawing(new SolidColorBrush(Color.FromArgb((byte)(255 * dim / 100), 0, 0, 0)), null, null);
                var group = new DrawingGroup();
                Brush brush;
                if (kind == "Image")
                {
                    var bmp = new BitmapImage(); bmp.BeginInit(); bmp.CacheOption = BitmapCacheOption.OnLoad; bmp.DecodePixelWidth = 1600; bmp.UriSource = new Uri(path); bmp.EndInit(); bmp.Freeze();
                    var rect = new Rect(0, 0, bmp.PixelWidth, bmp.PixelHeight);
                    veil.Geometry = new RectangleGeometry(rect);
                    group.Children.Add(new ImageDrawing(bmp, rect)); group.Children.Add(veil);
                    brush = new DrawingBrush(group) { Stretch = Stretch.UniformToFill }; brush.Freeze();
                }
                else
                {
                    // WPF's own video player needs Windows Media Player, which this Windows does not have
                    // ("Windows Media Player version 10 or later is required"), so the frames come from
                    // Windows' media engine instead (SurfaceVideo) into a small picture that is redrawn.
                    var sv = Video(path);
                    var rect = new Rect(0, 0, SurfaceVideo.W, SurfaceVideo.H);
                    veil.Geometry = new RectangleGeometry(rect);
                    group.Children.Add(new ImageDrawing(sv.Bitmap, rect)); group.Children.Add(veil);
                    brush = new DrawingBrush(group) { Stretch = Stretch.UniformToFill };
                }
                brushes[key] = brush;
                return brush;
            }
            catch (Exception e) { Log.Write("surface-background-failed id=" + id + " error=\"" + e.Message + "\""); return null; }
        }

        // One player per video file, shared by every surface that shows it.
        static SurfaceVideo Video(string path)
        {
            if (players.TryGetValue(path, out var v)) return v;
            v = new SurfaceVideo(path, paused || App.GameRunning);
            players[path] = v;
            return v;
        }

        // Settings changed: drop every cached picture and close every video, the surfaces are redrawn next.
        public static void Reset()
        {
            foreach (var p in players.Values) { try { p.Dispose(); } catch { } }
            players.Clear(); brushes.Clear();
        }
        // Games: videos stop decoding (the surfaces are hidden anyway) and continue afterwards.
        public static void Pause(bool pause)
        {
            paused = pause;
            foreach (var p in players.Values) { try { p.SetPaused(pause); } catch { } }
        }
        public static bool IsVideo(string path) => VideoExtensions.Contains(Path.GetExtension(path ?? "").ToLowerInvariant());
    }
}
