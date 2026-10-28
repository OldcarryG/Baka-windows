using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Baka.Desktop
{
    // One app the desktop knows about: a Start-menu entry, a pinned app or an open window.
    class AppRef
    {
        public string Name = "", AppId = "", Exe = "";
        public string ParsingName => string.IsNullOrEmpty(AppId) ? Exe : "shell:AppsFolder\\" + AppId;
        public string Key => (Name + "|" + AppId + "|" + Exe).ToLowerInvariant();
    }

    // A layer of a BAKA icon, drawn in a 100 x 100 box.
    //  role m = main mark colour, s = soft mark, a = the app's signature colour, c = cut-out (tile colour),
    //  #RRGGBB = a fixed colour (multi-colour icons such as Paint); Stroke > 0 draws the path as a line.
    class IconLayer
    {
        public string Path, Role = "m", Text; public double Stroke, TextSize = 40, TextX = 50, TextY = 50; public FontWeight Weight = FontWeights.Bold;
        Geometry geometry;
        public Geometry Geometry
        {
            get
            {
                if (geometry != null) return geometry;
                if (Text != null)
                {
                    var ft = new FormattedText(Text, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, new Typeface(Ui.Display, FontStyles.Normal, Weight, FontStretches.Normal), TextSize, Brushes.White, 1.0);
                    var g = ft.BuildGeometry(new Point(0, 0)); var b = g.Bounds;
                    g.Transform = new TranslateTransform(TextX - b.X - b.Width / 2, TextY - b.Y - b.Height / 2);
                    geometry = g;
                }
                else geometry = System.Windows.Media.Geometry.Parse(Path);
                geometry.Freeze();
                return geometry;
            }
        }
    }

    class IconDef
    {
        public string Id, Hue; public Regex Name, Target; public List<IconLayer> Layers = new List<IconLayer>();
        public bool Matches(AppRef a)
            => (Name != null && Name.IsMatch(a.Name ?? "")) || (Target != null && (Target.IsMatch(a.AppId ?? "") || Target.IsMatch(System.IO.Path.GetFileName(a.Exe ?? ""))));
    }

    static partial class Icons
    {
        static readonly Dictionary<string, ImageSource> cache = new Dictionary<string, ImageSource>();
        public static void ClearCache() => cache.Clear();
        public static string Style => App.Settings == null ? "Themed" : Json.Str(App.Settings.Appearance, "iconStyle", "Themed") == "Original" ? "Original" : "Themed";

        public static IconDef Find(AppRef app) => Library.FirstOrDefault(d => d.Matches(app));
        public static IconDef ById(string id) => Library.FirstOrDefault(d => d.Id == id);

        // The icon for an app: its hand-made BAKA icon when there is one, otherwise the app's own icon on the
        // theme's tile (or untouched with the Original style).
        public static ImageSource For(AppRef app, int size = 96)
        {
            string key = Style + "|" + app.Key + "|" + size;
            if (cache.TryGetValue(key, out var hit)) return hit;
            ImageSource result = null;
            try
            {
                var def = Style == "Themed" ? Find(app) : null;
                if (def != null) result = Draw(def, null, app.Name, size);
                else
                {
                    var shell = ShellIcon(app.ParsingName, 64) ?? (string.IsNullOrEmpty(app.Exe) ? null : ShellIcon(app.Exe, 64));
                    result = Style == "Original" ? (shell ?? Draw(null, null, app.Name, size)) : Draw(null, shell, app.Name, size);
                }
            }
            catch (Exception e) { Log.Write("icon-failed app=\"" + app.Name + "\" error=\"" + e.Message + "\""); }
            cache[key] = result;
            return result;
        }
        public static ImageSource ForId(string id, int size = 96)
        {
            string key = "id|" + id + "|" + size;
            if (cache.TryGetValue(key, out var hit)) return hit;
            var def = ById(id);
            return cache[key] = def == null ? null : Draw(def, null, id, size);
        }
        public static ImageSource ForFile(string path, int size = 32)
        {
            string ext = System.IO.Directory.Exists(path) ? "<dir>" + (path.Length <= 3 ? path : "") : System.IO.Path.GetExtension(path).ToLowerInvariant();
            bool own = ext == ".exe" || ext == ".lnk" || ext == ".ico" || ext == ".url" || ext.StartsWith("<dir>") && path.Length <= 3;
            string key = "file|" + (own ? path : ext) + "|" + size;
            if (cache.TryGetValue(key, out var hit)) return hit;
            return cache[key] = ShellIcon(path, size);
        }

        public static BitmapSource ShellIcon(string parsingName, int size)
        {
            if (string.IsNullOrEmpty(parsingName)) return null;
            var px = Native.ShellIconPixels(parsingName, size, out int w, out int h);
            if (px == null) return null;
            var bmp = BitmapSource.Create(w, h, 96, 96, PixelFormats.Pbgra32, null, px, w * 4);
            bmp.Freeze(); return bmp;
        }

        // ---- drawing ----
        static Geometry TileShape(string shape, double x, double y, double s)
        {
            switch (shape)
            {
                case "Circle": return new EllipseGeometry(new Rect(x, y, s, s));
                case "Hexagon":
                    {
                        var f = new PathFigure { IsClosed = true }; double cx = x + s / 2, cy = y + s / 2, r = s / 2;
                        for (int i = 0; i < 6; i++) { double a = Math.PI / 180 * (60 * i - 90); var p = new Point(cx + r * Math.Cos(a), cy + r * Math.Sin(a)); if (i == 0) f.StartPoint = p; else f.Segments.Add(new LineSegment(p, true)); }
                        var g = new PathGeometry(); g.Figures.Add(f); return g;
                    }
                case "Keycap": return new RectangleGeometry(new Rect(x, y, s, s), s * 0.22, s * 0.22);
                default: return new RectangleGeometry(new Rect(x, y, s, s), s * 0.26, s * 0.26);
            }
        }
        static Brush Grad(Color a, Color b, bool diagonal = false) { var g = new LinearGradientBrush(a, b, diagonal ? 45 : 90); g.Freeze(); return g; }
        static Color WithA(Color c, byte a) => Color.FromArgb(a, c.R, c.G, c.B);
        static Color Gray(Color c) { byte v = (byte)(0.3 * c.R + 0.59 * c.G + 0.11 * c.B); return Color.FromArgb(c.A, v, v, v); }

        public static BitmapSource Draw(IconDef def, BitmapSource real, string name, int n)
        {
            var t = Theme.Current;
            Color accent = Theme.C(Theme.AccentHex), accent2 = Theme.C(t.Accent2), text = Theme.C(t.Text), canvas = Theme.C(t.Canvas), surface = Theme.C(t.Surface), surfaceAlt = Theme.C(t.SurfaceAlt), shadow = Theme.C(t.Shadow);
            Color hue = def?.Hue != null ? Theme.C(def.Hue) : accent;
            if (t.Mono) hue = Theme.Mix(Gray(hue), text, 0.35);
            double drop = t.Shape == "Keycap" ? n * 0.05 : 0, pad = t.Fill == "Neon" ? n * 0.085 : n * 0.05;
            double s = n - pad * 2 - drop, x = pad, y = pad;
            var shape = TileShape(t.Shape, x, y, s);
            var dv = new DrawingVisual(); RenderOptions.SetBitmapScalingMode(dv, BitmapScalingMode.HighQuality);
            using (var dc = dv.RenderOpen())
            {
                // 1. the tile: the theme's material, tinted by the app's colour where the material allows it
                Color tileColor = canvas;
                if (drop > 0) { var sh = shape.Clone(); sh.Transform = new TranslateTransform(0, drop); dc.DrawGeometry(new SolidColorBrush(WithA(shadow, 235)), null, sh); }
                switch (t.Fill)
                {
                    case "Metal":
                        dc.DrawGeometry(Grad(Color.FromRgb(0x4A, 0x4A, 0x50), Color.FromRgb(0x12, 0x12, 0x14)), new Pen(Grad(Color.FromRgb(0x9C, 0x9C, 0xA4), Color.FromRgb(0x2A, 0x2A, 0x2E)), n / 70.0), shape);
                        dc.PushClip(shape); dc.DrawRectangle(Grad(Color.FromArgb(34, 255, 255, 255), Color.FromArgb(0, 255, 255, 255)), null, new Rect(x, y, s, s * 0.45)); dc.Pop();
                        tileColor = Color.FromRgb(0x2A, 0x2A, 0x2E); break;
                    case "Neon":
                        foreach (var (w, a) in new[] { (9.0, (byte)28), (5.0, (byte)60) }) dc.DrawGeometry(null, new Pen(new SolidColorBrush(WithA(accent, a)), n * w / 96), shape);
                        dc.DrawGeometry(Grad(Theme.Mix(surface, hue, 0.12), canvas), new Pen(new SolidColorBrush(accent), n * 2.2 / 96), shape);
                        tileColor = Theme.Mix(surface, canvas, 0.5); break;
                    case "Glass":
                        {
                            var tint = Theme.Mix(hue, accent, 0.25);
                            dc.DrawGeometry(Grad(WithA(tint, 200), WithA(Theme.Mix(tint, accent2, 0.5), 150), true), new Pen(new SolidColorBrush(Color.FromArgb(170, 255, 255, 255)), n * 1.4 / 96), shape);
                            dc.PushClip(shape); dc.DrawEllipse(Grad(Color.FromArgb(120, 255, 255, 255), Color.FromArgb(0, 255, 255, 255)), null, new Point(x + s / 2, y + s * 0.16), s * 0.44, s * 0.24); dc.Pop();
                            tileColor = Theme.Mix(tint, canvas, 0.35); break;
                        }
                    case "Candy":
                        dc.DrawGeometry(Grad(accent, accent2, true), new Pen(new SolidColorBrush(Theme.C(t.Border)), n * 2 / 96), shape);
                        dc.PushClip(shape); dc.DrawRectangle(Grad(Color.FromArgb(70, 255, 255, 255), Color.FromArgb(0, 255, 255, 255)), null, new Rect(x, y, s, s * 0.4)); dc.Pop();
                        tileColor = Theme.Mix(accent, accent2, 0.5); break;
                    case "Outline":
                        dc.DrawGeometry(new SolidColorBrush(WithA(surface, 140)), new Pen(new SolidColorBrush(WithA(text, 210)), n * 1.6 / 96), shape);
                        tileColor = surface; break;
                    default:
                        {
                            var deep = new RadialGradientBrush(Theme.Mix(surfaceAlt, hue, 0.28), canvas) { GradientOrigin = new Point(0.3, 0.2) }; deep.Freeze();
                            dc.DrawGeometry(deep, new Pen(new SolidColorBrush(WithA(Theme.Mix(accent, hue, 0.5), 160)), n * 1.6 / 96), shape);
                            tileColor = Theme.Mix(surfaceAlt, canvas, 0.4); break;
                        }
                }
                double cx = x + s / 2, cy = y + s / 2;
                // 2. the mark
                Brush main, soft, sig, cut = new SolidColorBrush(tileColor);
                switch (t.Mark)
                {
                    case "Silver": main = Grad(Colors.White, Color.FromRgb(0xA4, 0xA6, 0xAE)); soft = new SolidColorBrush(Color.FromArgb(120, 230, 230, 235)); sig = new SolidColorBrush(Theme.Mix(hue, Colors.White, 0.35)); break;
                    case "Glow": main = new SolidColorBrush(Theme.Mix(text, accent, 0.15)); soft = new SolidColorBrush(WithA(accent, 140)); sig = new SolidColorBrush(Theme.Mix(hue, accent, 0.35)); break;
                    case "Ink": main = new SolidColorBrush(shadow); soft = new SolidColorBrush(WithA(shadow, 120)); sig = Brushes.White; break;
                    case "Duotone": main = Grad(text, Theme.Mix(text, accent, 0.5), true); soft = new SolidColorBrush(WithA(text, 110)); sig = new SolidColorBrush(Theme.Mix(hue, accent, 0.25)); break;
                    case "Line": main = new SolidColorBrush(text); soft = new SolidColorBrush(WithA(text, 110)); sig = new SolidColorBrush(Theme.Mix(hue, text, 0.4)); break;
                    default: main = Brushes.White; soft = new SolidColorBrush(Color.FromArgb(130, 255, 255, 255)); sig = new SolidColorBrush(Theme.Mix(hue, Colors.White, 0.15)); break;
                }
                if (t.Fill == "Glass" || t.Fill == "Candy") sig = t.Fill == "Candy" ? (Brush)Brushes.White : new SolidColorBrush(Theme.Mix(hue, Colors.White, 0.55));
                if (def != null)
                {
                    double box = s * (t.Shape == "Hexagon" ? 0.56 : 0.64), k = box / 100.0;
                    var map = new TransformGroup(); map.Children.Add(new ScaleTransform(k, k)); map.Children.Add(new TranslateTransform(cx - box / 2, cy - box / 2)); map.Freeze();
                    dc.PushTransform(map);
                    if (t.Mark == "Glow") foreach (var l in def.Layers.Where(l => l.Role == "m")) dc.DrawGeometry(null, new Pen(new SolidColorBrush(WithA(accent, 60)), (l.Stroke > 0 ? l.Stroke : 0) + 6) { LineJoin = PenLineJoin.Round, StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round }, l.Geometry);
                    else if (t.Mark == "White" || t.Mark == "Silver") { dc.PushTransform(new TranslateTransform(0, 1.6)); foreach (var l in def.Layers.Where(l => l.Role == "m")) Paint(dc, l, new SolidColorBrush(Color.FromArgb(70, 0, 0, 0))); dc.Pop(); }
                    foreach (var l in def.Layers)
                    {
                        Brush b = l.Role == "m" ? main : l.Role == "s" ? soft : l.Role == "a" ? sig : l.Role == "c" ? cut : Fixed(l.Role, t);
                        Paint(dc, l, b);
                    }
                    dc.Pop();
                }
                else if (real != null)
                {
                    double box = s * (t.Shape == "Hexagon" ? 0.58 : 0.66);
                    var rect = new Rect(cx - box / 2, cy - box / 2, box, box);
                    var mask = new ImageBrush(real) { Stretch = Stretch.Uniform };
                    if (t.Fill != "Outline") { dc.PushOpacityMask(mask); dc.DrawRectangle(new SolidColorBrush(Color.FromArgb(110, 0, 0, 0)), null, new Rect(rect.X, rect.Y + n * 0.025, box, box)); dc.Pop(); }
                    dc.DrawImage(real, rect);
                }
                else
                {
                    string mono = Monogram(name);
                    var ft = new FormattedText(mono, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, new Typeface(Ui.Display, FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal), s * (mono.Length > 1 ? 0.34 : 0.44), main, 1.0);
                    dc.DrawText(ft, new Point(cx - ft.Width / 2, cy - ft.Height / 2));
                }
            }
            var rtb = new RenderTargetBitmap(n, n, 96, 96, PixelFormats.Pbgra32); rtb.Render(dv); rtb.Freeze();
            return rtb;
        }
        static Brush Fixed(string hex, ThemeInfo t)
        {
            var c = Theme.C(hex);
            if (t.Mono) c = Theme.Mix(Gray(c), Theme.C(t.Text), 0.3);
            else if (t.Mark == "Ink") c = Theme.Mix(c, Theme.C(t.Shadow), 0.25);
            return new SolidColorBrush(c);
        }
        static void Paint(DrawingContext dc, IconLayer l, Brush b)
        {
            if (l.Stroke > 0) dc.DrawGeometry(null, new Pen(b, l.Stroke) { LineJoin = PenLineJoin.Round, StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round }, l.Geometry);
            else dc.DrawGeometry(b, null, l.Geometry);
        }
        public static string Monogram(string name)
        {
            var words = Regex.Replace(name ?? "", @"\(.*?\)|\.exe$", "").Split(new[] { ' ', '-', '_', '.' }, StringSplitOptions.RemoveEmptyEntries).Where(w => char.IsLetterOrDigit(w[0])).ToList();
            if (words.Count == 0) return "B";
            return words.Count == 1 ? words[0].Substring(0, 1).ToUpperInvariant() : (words[0].Substring(0, 1) + words[1].Substring(0, 1)).ToUpperInvariant();
        }
    }
}
