using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows.Media;

namespace Baka.Desktop
{
    class ThemeInfo
    {
        public string Name, Canvas, Surface, SurfaceAlt, Text, Muted, Border, Accent, Accent2, Shadow, Backdrop, Animations, Style;
        public int Glass;
        // The tile every app icon sits on: shape and material differ per theme.
        public string Shape = "Squircle", Fill = "Deep", Mark = "White";
        public bool Pop => Style == "PopGlass";
        public bool Mono => Name == "BAKA Carbon" || Name == "BAKA Minimal";
    }

    static class Theme
    {
        public static List<ThemeInfo> All = new List<ThemeInfo>();
        public static ThemeInfo Current;
        public static string AccentHex;
        public static event Action Changed;
        public static Brush Canvas, Surface, SurfaceAlt, Text, Muted, Border, Accent, Accent2, Glass, Hover, Pressed, Rim;

        static readonly Dictionary<string, (string shape, string fill, string mark)> Packs = new Dictionary<string, (string, string, string)>
        {
            ["BAKA Carbon"] = ("Squircle", "Metal", "Silver"), ["BAKA Carbon Red"] = ("Hexagon", "Neon", "Glow"), ["BAKA Liquid Glass"] = ("Circle", "Glass", "White"),
            ["BAKA Pop Glass"] = ("Keycap", "Candy", "Ink"), ["BAKA Pop Sunset"] = ("Keycap", "Candy", "Ink"), ["BAKA Pop Mint"] = ("Keycap", "Candy", "Ink"), ["BAKA Pop Sakura"] = ("Keycap", "Candy", "Ink"),
            ["BAKA Obsidian"] = ("Hexagon", "Deep", "Duotone"), ["BAKA Liquid"] = ("Squircle", "Glass", "White"), ["BAKA Violet"] = ("Circle", "Deep", "Duotone"),
            ["BAKA Minimal"] = ("Circle", "Outline", "Line"), ["BAKA Gaming"] = ("Hexagon", "Neon", "Glow"),
        };

        public static void Load()
        {
            All.Clear();
            try
            {
                var doc = Json.Obj(Json.Parse(File.ReadAllText(Paths.Shipped("DesktopThemes.json"))));
                foreach (var t in Json.Arr(Json.Get(doc, "themes")).Select(Json.Obj))
                {
                    var i = new ThemeInfo
                    {
                        Name = Json.Str(t, "name"), Canvas = Json.Str(t, "canvas", "#050506"), Surface = Json.Str(t, "surface", "#161619"), SurfaceAlt = Json.Str(t, "surfaceAlt", "#27272A"),
                        Text = Json.Str(t, "text", "#FAFAFA"), Muted = Json.Str(t, "muted", "#A1A1AA"), Border = Json.Str(t, "border", "#6B6B72"), Accent = Json.Str(t, "accent", "#FAFAFA"),
                        Accent2 = Json.Str(t, "accent2", ""), Shadow = Json.Str(t, "shadow", ""), Backdrop = Json.Str(t, "backdrop", "Acrylic"), Animations = Json.Str(t, "animations", "Subtle"),
                        Style = Json.Str(t, "style", "Liquid"), Glass = Json.Int(t, "glassIntensity", 30)
                    };
                    if (string.IsNullOrEmpty(i.Accent2)) i.Accent2 = i.Accent;
                    if (string.IsNullOrEmpty(i.Shadow)) i.Shadow = i.Canvas;
                    if (Packs.TryGetValue(i.Name, out var p)) { i.Shape = p.shape; i.Fill = p.fill; i.Mark = p.mark; }
                    All.Add(i);
                }
            }
            catch (Exception e) { Log.Write("themes-unreadable error=\"" + e.Message + "\""); }
            if (All.Count == 0) All.Add(new ThemeInfo { Name = "BAKA Carbon", Canvas = "#050506", Surface = "#161619", SurfaceAlt = "#27272A", Text = "#FAFAFA", Muted = "#A1A1AA", Border = "#6B6B72", Accent = "#FAFAFA", Accent2 = "#D4D4D8", Shadow = "#050506", Backdrop = "Acrylic", Shape = "Squircle", Fill = "Metal", Mark = "Silver" });
        }

        public static void Apply(string name, string accent)
        {
            Current = All.FirstOrDefault(t => t.Name == name) ?? All[0];
            AccentHex = IsHex(accent) ? accent : Current.Accent;
            int glass = App.Settings == null ? 34 : Json.Int(App.Settings.Appearance, "glassIntensity", 34);
            bool opaque = Current.Backdrop == "Opaque" || App.GameRunning || System.Windows.SystemParameters.HighContrast;
            byte alpha = (byte)(opaque ? 250 : Math.Max(150, 240 - glass * 2));
            Canvas = B(Current.Canvas); Surface = B(Current.Surface, alpha); SurfaceAlt = B(Current.SurfaceAlt, 230); Text = B(Current.Text); Muted = B(Current.Muted);
            Border = B(Current.Border, 110); Accent = B(AccentHex); Accent2 = B(Current.Accent2); Glass = B(Current.Surface, alpha);
            Hover = B(Current.Text, 22); Pressed = B(Current.Text, 40); Rim = B("#FFFFFF", (byte)(Current.Pop ? 210 : 40));
            Icons.ClearCache();
            Changed?.Invoke();
        }

        public static bool IsHex(string s) => s != null && System.Text.RegularExpressions.Regex.IsMatch(s, "^#[0-9A-Fa-f]{6}$");
        public static Color C(string hex, byte a = 255)
        {
            if (!IsHex(hex)) hex = "#808080";
            return Color.FromArgb(a, Convert.ToByte(hex.Substring(1, 2), 16), Convert.ToByte(hex.Substring(3, 2), 16), Convert.ToByte(hex.Substring(5, 2), 16));
        }
        public static SolidColorBrush B(string hex, byte a = 255) { var b = new SolidColorBrush(C(hex, a)); b.Freeze(); return b; }
        public static Color Mix(Color a, Color b, double t) => Color.FromArgb((byte)(a.A + (b.A - a.A) * t), (byte)(a.R + (b.R - a.R) * t), (byte)(a.G + (b.G - a.G) * t), (byte)(a.B + (b.B - a.B) * t));
        // Readable text on a coloured background (dark ink on light accents, white on dark).
        public static Brush OnColor(string hex) { var c = C(hex); return (0.299 * c.R + 0.587 * c.G + 0.114 * c.B) > 150 ? B("#0B0B0E") : B("#FFFFFF"); }
        public static bool Motion => App.Settings != null && Json.Str(App.Settings.Appearance, "animationIntensity", "Full") != "Off" && !Json.Bool(App.Settings.Appearance, "reducedMotion") && !App.GameRunning && System.Windows.SystemParameters.ClientAreaAnimation;
    }
}
