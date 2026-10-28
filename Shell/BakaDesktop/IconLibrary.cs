using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace Baka.Desktop
{
    // The BAKA icon set: one hand-drawn vector icon per app, designed for this desktop (not copies of the
    // apps' logos). Each icon is a few shapes in a 100 x 100 box; the theme decides the tile and colours,
    // the icon keeps its shape and its signature colour so every app stays recognisable in every theme.
    static partial class Icons
    {
        static string N(double v) => v.ToString("0.##", CultureInfo.InvariantCulture);
        static string Ci(double cx, double cy, double r) => $"M{N(cx - r)},{N(cy)} A{N(r)},{N(r)} 0 1 1 {N(cx + r)},{N(cy)} A{N(r)},{N(r)} 0 1 1 {N(cx - r)},{N(cy)} Z";
        static string Rr(double x, double y, double w, double h, double r)
            => $"M{N(x + r)},{N(y)} H{N(x + w - r)} A{N(r)},{N(r)} 0 0 1 {N(x + w)},{N(y + r)} V{N(y + h - r)} A{N(r)},{N(r)} 0 0 1 {N(x + w - r)},{N(y + h)} H{N(x + r)} A{N(r)},{N(r)} 0 0 1 {N(x)},{N(y + h - r)} V{N(y + r)} A{N(r)},{N(r)} 0 0 1 {N(x + r)},{N(y)} Z";
        static string Ring(double cx, double cy, double r, double t) => Ci(cx, cy, r) + " " + Ci(cx, cy, r - t);
        static string Gear(double cx, double cy, double ro, double ri, int teeth, double hole)
        {
            var sb = new StringBuilder(); int steps = teeth * 4;
            for (int i = 0; i < steps; i++)
            {
                double a = Math.PI * 2 * i / steps - Math.PI / 2, r = (i % 4 == 0 || i % 4 == 1) ? ro : ri;
                sb.Append(i == 0 ? "M" : " L").Append(N(cx + r * Math.Cos(a))).Append(',').Append(N(cy + r * Math.Sin(a)));
            }
            sb.Append(" Z ").Append(Ci(cx, cy, hole));
            return sb.ToString();
        }
        static string Star(double cx, double cy, double ro, double ri, int points)
        {
            var sb = new StringBuilder();
            for (int i = 0; i < points * 2; i++) { double a = Math.PI * i / points - Math.PI / 2, r = i % 2 == 0 ? ro : ri; sb.Append(i == 0 ? "M" : " L").Append(N(cx + r * Math.Cos(a))).Append(',').Append(N(cy + r * Math.Sin(a))); }
            return sb.Append(" Z").ToString();
        }
        static string Hex(double cx, double cy, double r) { var sb = new StringBuilder(); for (int i = 0; i < 6; i++) { double a = Math.PI / 3 * i; sb.Append(i == 0 ? "M" : " L").Append(N(cx + r * Math.Cos(a))).Append(',').Append(N(cy + r * Math.Sin(a))); } return sb.Append(" Z").ToString(); }

        static IconLayer F(string path, string role = "m") => new IconLayer { Path = path, Role = role };
        static IconLayer K(string path, double w, string role = "m") => new IconLayer { Path = path, Stroke = w, Role = role };
        static IconLayer T(string text, double size, double x = 50, double y = 50, string role = "m", bool heavy = true) => new IconLayer { Text = text, TextSize = size, TextX = x, TextY = y, Role = role, Weight = heavy ? System.Windows.FontWeights.Black : System.Windows.FontWeights.SemiBold };

        // Small corner badges for app families (Git Bash vs Git GUI, PowerShell vs PowerShell x86).
        static IconLayer[] Badge(string kind)
        {
            var l = new List<IconLayer> { F(Ci(78, 78, 19), "c"), F(Ci(78, 78, 15), "a") };
            switch (kind)
            {
                case "prompt": l.Add(K("M71,72 L77,78 L71,84", 3.4, "c")); l.Add(K("M80,84 H86", 3.4, "c")); break;
                case "gear": l.Add(F(Gear(78, 78, 10, 7, 7, 3), "c")); break;
                case "plus": l.Add(K("M78,70 V86 M70,78 H86", 3.6, "c")); break;
                case "question": l.Add(T("?", 18, 78, 78, "c")); break;
                case "doc": l.Add(F(Rr(71, 69, 14, 18, 2), "c")); l.Add(K("M74,75 H82 M74,80 H80", 1.8, "a")); break;
                case "window": l.Add(F(Rr(69, 71, 18, 14, 2.5), "c")); l.Add(F(Rr(71, 75, 14, 8, 1), "a")); break;
                case "cmd": l.Add(T("C:", 11, 78, 78, "c")); break;
                case "x86": l.Add(T("32", 11, 78, 78, "c")); break;
                case "64": l.Add(T("64", 11, 78, 78, "c")); break;
                case "book": l.Add(F("M69,72 Q74,70 78,73 Q82,70 87,72 V85 Q82,83 78,86 Q74,83 69,85 Z", "c")); break;
                case "hammer": l.Add(K("M72,86 L82,74", 3.6, "c")); l.Add(F(Rr(76, 68, 12, 7, 2), "c")); break;
                case "net": l.Add(F(Ci(72, 82, 3.4), "c")); l.Add(F(Ci(84, 82, 3.4), "c")); l.Add(F(Ci(78, 72, 3.4), "c")); l.Add(K("M72,82 L78,72 L84,82 Z", 1.6, "c")); break;
            }
            return l.ToArray();
        }

        static IconDef D(string id, string hue, string name, string target, params object[] parts)
        {
            var d = new IconDef { Id = id, Hue = hue, Name = name == null ? null : new Regex(name, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant), Target = target == null ? null : new Regex(target, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant) };
            foreach (var p in parts) { if (p is IconLayer l) d.Layers.Add(l); else if (p is IEnumerable<IconLayer> ls) d.Layers.AddRange(ls); }
            return d;
        }

        // Base drawings reused by app families.
        static IconLayer[] Terminal() => new[] { F(Rr(10, 18, 80, 64, 11)), F(Rr(16, 30, 68, 46, 5), "c"), K("M27,42 L39,52 L27,62", 6, "a"), F(Rr(45, 59, 20, 5, 2.5), "a"), F(Ci(20, 24, 2.2), "c"), F(Ci(27, 24, 2.2), "c") };
        static IconLayer[] PowerShell() => new[] { F("M26,18 H90 L76,82 H10 Z"), K("M30,36 L50,50 L30,64", 7, "c"), F(Rr(52, 58, 20, 6, 3), "c") };
        static IconLayer[] GitTree() => new[] { K("M32,30 V70", 6), K("M68,42 C68,58 32,54 32,66", 6), F(Ci(32, 24, 9)), F(Ci(32, 76, 9)), F(Ci(68, 38, 9), "a") };
        static IconLayer[] Python() => new[] { F(Rr(16, 12, 44, 42, 13)), F(Ci(29, 24, 4), "c"), F(Rr(40, 46, 44, 42, 13), "a"), F(Ci(71, 76, 4), "c") };
        static IconLayer[] Monitor() => new[] { F(Rr(12, 18, 76, 50, 8)), F(Rr(18, 24, 64, 38, 3), "c"), F("M42,68 H58 L62,80 H38 Z"), F(Rr(30, 78, 40, 6, 3)) };
        static IconLayer[] Penguin() => new[] { F("M50,12 C66,12 72,28 72,44 C80,54 84,70 78,84 H22 C16,70 20,54 28,44 C28,28 34,12 50,12 Z"), F("M50,40 C62,40 68,56 66,82 H34 C32,56 38,40 50,40 Z", "c"), F(Ci(43, 28, 3.5), "c"), F(Ci(57, 28, 3.5), "c"), F("M44,36 H56 L50,44 Z", "#F5B73B"), F("M24,84 Q30,76 40,84 Z M60,84 Q70,76 76,84 Z", "#F5B73B") };
        static IconLayer[] Gpu() => new[] { F(Rr(8, 28, 84, 42, 7)), F(Ring(36, 49, 14, 5), "c"), F(Ring(66, 49, 14, 5), "c"), F(Ci(36, 49, 4), "a"), F(Ci(66, 49, 4), "a"), F(Rr(8, 70, 10, 12, 2)), F(Rr(24, 70, 40, 6, 2), "s") };
        static IconLayer[] Cylinder() => new[] { F("M18,24 A32,11 0 0 1 82,24 V76 A32,11 0 0 1 18,76 Z"), K("M18,42 A32,11 0 0 0 82,42", 4, "c"), K("M18,60 A32,11 0 0 0 82,60", 4, "c"), F("M24,24 A26,7 0 0 1 76,24 A26,7 0 0 1 24,24 Z", "a") };
        static IconLayer[] Gamepad() => new[] { F("M28,30 H72 C86,30 92,44 92,58 C92,72 84,80 76,80 C68,80 64,70 58,68 H42 C36,70 32,80 24,80 C16,80 8,72 8,58 C8,44 14,30 28,30 Z"), K("M28,46 V62 M20,54 H36", 5.5, "c"), F(Ci(68, 48, 4.5), "a"), F(Ci(76, 58, 4.5), "c"), F(Ci(60, 58, 4.5), "c") };

        public static readonly List<IconDef> Library = new List<IconDef>
        {
            // ---- BAKA ----
            D("baka-browser", "#FB5668", @"^baka( browser)?$", @"(^|\\)baka\.exe$|bakabrowser", F(Ring(50, 50, 40, 6), "s"), F(Rr(30, 20, 11, 58, 5.5)), F(Ring(55, 58, 18, 10)), F(Ci(76, 24, 7), "a")),
            D("baka-files", "#F5B73B", @"^(baka files|file explorer|files|explorer)$", @"^explorer\.exe$|Microsoft\.Windows\.Explorer", F("M12,30 Q12,22 20,22 H40 L48,30 H80 Q88,30 88,38 V40 H12 Z", "s"), F(Rr(10, 36, 80, 46, 8)), F(Rr(22, 62, 26, 6, 3), "c"), F(Rr(10, 36, 80, 8, 4), "a")),
            D("baka-settings", "#A1A1AA", @"^baka settings$", null, F(Gear(50, 50, 40, 31, 9, 14)), T("B", 22, 50, 51, "a")),
            D("baka-arena", "#FB5668", @"^baka arena$", null, F("M28,12 H72 V34 A22,22 0 0 1 28,34 Z"), K("M28,20 H16 V28 A12,12 0 0 0 28,40 M72,20 H84 V28 A12,12 0 0 1 72,40", 5), F(Rr(44, 54, 12, 16, 3)), F(Rr(30, 70, 40, 12, 5)), F(Star(50, 26, 9, 4, 5), "a")),
            // ---- Windows ----
            D("settings", "#8A8F98", @"^settings$", @"windows\.immersivecontrolpanel|SystemSettings", F(Gear(50, 50, 40, 31, 8, 15)), F(Ci(50, 50, 7), "a")),
            D("store", "#2C8CF0", @"^microsoft store$", @"WindowsStore", K("M36,36 V28 A14,14 0 0 1 64,28 V36", 7), F("M18,34 H82 L77,84 Q76,90 70,90 H30 Q24,90 23,84 Z"), F(Rr(38, 50, 10, 10, 2), "a"), F(Rr(52, 50, 10, 10, 2), "a"), F(Rr(38, 64, 10, 10, 2), "a"), F(Rr(52, 64, 10, 10, 2), "a")),
            D("taskmgr", "#2BB673", @"^task manager$", @"taskmgr", F(Rr(10, 16, 80, 68, 10)), F(Rr(16, 28, 68, 50, 4), "c"), K("M20,56 H34 L41,38 L52,70 L59,50 H80", 5.5, "a")),
            D("terminal", "#3D8BFD", @"^(windows )?terminal$", @"WindowsTerminal|wt\.exe", Terminal()),
            D("powershell-x86", "#2C6BC4", @"^windows powershell \(x86\)$", null, PowerShell(), Badge("x86")),
            D("powershell", "#2C6BC4", @"^(windows )?powershell( 7.*)?$", @"(^|\\)(powershell|pwsh)\.exe$", PowerShell()),
            D("cmd", "#5A5A5A", @"^command prompt$", @"(^|\\)cmd\.exe$", F(Rr(10, 18, 80, 64, 9)), F(Rr(16, 28, 68, 48, 3), "c"), K("M40,42 A9,9 0 1 0 40,60", 5, "a"), K("M48,43 L57,51 L48,59", 5, "a"), F(Rr(60, 57, 12, 4, 2), "a")),
            D("notepad", "#3A96DD", @"^notepad$", @"notepad", F("M24,10 H64 L82,28 V86 Q82,92 76,92 H24 Q18,92 18,86 V16 Q18,10 24,10 Z"), F("M64,10 V24 Q64,28 68,28 H82 Z", "s"), F(Rr(28, 42, 42, 5, 2.5), "c"), F(Rr(28, 54, 42, 5, 2.5), "c"), F(Rr(28, 66, 26, 5, 2.5), "a")),
            D("calculator", "#F2A33A", @"^calculator$", @"calculator|calc\.exe", F(Rr(20, 8, 60, 84, 11)), F(Rr(27, 15, 46, 17, 4), "c"),
                F(Rr(27, 38, 13, 12, 3), "c"), F(Rr(43.5, 38, 13, 12, 3), "c"), F(Rr(60, 38, 13, 12, 3), "c"), F(Rr(27, 54, 13, 12, 3), "c"), F(Rr(43.5, 54, 13, 12, 3), "c"), F(Rr(60, 54, 13, 28, 3), "a"), F(Rr(27, 70, 29.5, 12, 3), "c")),
            D("paint", "#F0A030", @"^paint( 3d)?$", @"mspaint|Paint", F("M50,12 C74,12 90,28 90,48 C90,60 80,64 71,61 C62,58 57,64 61,73 C65,82 59,88 49,88 C26,88 10,71 10,50 C10,29 27,12 50,12 Z"), F(Ci(31, 42, 7), "#FB5668"), F(Ci(47, 27, 7), "#F5B73B"), F(Ci(67, 31, 7), "#34D399"), F(Ci(30, 63, 7), "#3D8BFD")),
            D("snipping", "#E04E8A", @"^snipping tool$", @"ScreenSketch|SnippingTool", F(Ring(29, 72, 13, 6)), F(Ring(71, 72, 13, 6)), K("M36,62 L72,14", 7), K("M64,62 L28,14", 7), F(Ci(50, 38, 4.5), "a")),
            D("media-player", "#FF6A3D", @"^media player$|^windows media player$", @"ZuneMusic|wmplayer", F(Ci(50, 50, 40)), F("M41,32 L70,50 L41,68 Z", "c"), F(Ring(50, 50, 40, 5), "a")),
            D("photos", "#2F8FEA", @"^photos$", @"Windows\.Photos", F(Rr(10, 18, 80, 64, 11)), F(Rr(17, 25, 66, 50, 5), "c"), F("M17,70 L40,44 L54,58 L64,48 L83,68 V75 H17 Z", "a"), F(Ci(66, 38, 6.5))),
            D("camera", "#5A5A5A", @"^camera$", @"WindowsCamera", F(Rr(10, 30, 80, 52, 11)), F("M35,30 L42,18 H58 L65,30 Z"), F(Ring(50, 56, 18, 6.5), "c"), F(Ci(50, 56, 8), "a")),
            D("clock", "#6264A7", @"^(clock|alarms & clock)$", @"WindowsAlarms", F(Ring(50, 50, 40, 7)), K("M50,26 V50 L65,60", 6, "a"), F(Ci(50, 50, 4.5))),
            D("recorder", "#E5484D", @"^(sound )?recorder$", @"SoundRecorder", F(Ring(50, 50, 40, 7)), F(Ci(50, 50, 20), "a")),
            D("sticky", "#F5D547", @"^sticky notes$", @"StickyNotes", F("M14,14 H86 V64 L64,86 H14 Z"), F("M64,86 V68 Q64,64 68,64 H86 Z", "s"), F(Rr(24, 30, 44, 5, 2.5), "c"), F(Rr(24, 42, 34, 5, 2.5), "c")),
            D("this-pc", "#3D8BFD", @"^this pc$|^my computer$", null, Monitor(), F(Rr(24, 30, 22, 6, 3), "a")),
            D("control-panel", "#5B8DEF", @"^control panel$", @"control\.exe", F(Rr(10, 14, 80, 72, 12)), F(Rr(22, 30, 56, 5, 2.5), "c"), F(Rr(22, 48, 56, 5, 2.5), "c"), F(Rr(22, 66, 56, 5, 2.5), "c"), F(Ci(36, 32.5, 7), "a"), F(Ci(62, 50.5, 7), "a"), F(Ci(46, 68.5, 7), "a")),
            D("services", "#8A8F98", @"^services$", @"services\.msc", F(Gear(38, 60, 26, 19, 8, 8)), F(Gear(70, 30, 18, 13, 7, 5.5), "a")),
            D("regedit", "#2B78C2", @"^registry editor$", @"regedit", F(Rr(12, 46, 34, 34, 6)), F(Rr(52, 46, 34, 34, 6), "s"), F(Rr(32, 10, 34, 34, 6), "a")),
            D("event-viewer", "#C93C3C", @"^event viewer$", @"eventvwr", F(Rr(14, 10, 56, 74, 8)), F(Rr(22, 24, 38, 5, 2.5), "c"), F(Rr(22, 36, 38, 5, 2.5), "c"), F(Rr(22, 48, 24, 5, 2.5), "c"), F("M64,48 L90,90 H38 Z", "a"), F(Rr(61.5, 62, 5, 14, 2.5), "c"), F(Ci(64, 82, 3), "c")),
            D("disk-cleanup", "#3FB8AF", @"^disk cleanup$", @"cleanmgr", K("M72,10 L48,50", 7), F("M28,48 H64 L72,90 H20 Z"), K("M34,60 L31,86 M44,60 L43,86 M54,60 L55,86", 3, "c"), F(Star(82, 68, 9, 3.5, 4), "a"), F(Star(16, 28, 7, 2.6, 4), "a")),
            D("defrag", "#3D8BFD", @"^defragment and optimi[sz]e drives$", @"dfrgui", F(Ci(50, 50, 40)), F(Rr(27, 52, 11, 22, 3), "c"), F(Rr(44.5, 40, 11, 34, 3), "c"), F(Rr(62, 28, 11, 46, 3), "a")),
            D("run", "#8A8F98", @"^run$", null, K("M44,22 H22 V78 H78 V56", 8), K("M50,50 L80,20 M60,20 H80 V40", 8, "a")),
            D("magnifier", "#3D8BFD", @"^magnifier$", @"magnify", F(Ring(42, 42, 28, 9)), K("M62,62 L84,84", 13), K("M28,38 A14,14 0 0 1 38,28", 4.5, "a")),
            D("narrator", "#7A5AF8", @"^narrator$", @"narrator", F("M12,28 Q12,20 20,20 H62 Q70,20 70,28 V58 Q70,66 62,66 H38 L24,80 V66 H20 Q12,66 12,58 Z"), K("M80,32 A18,18 0 0 1 80,56", 5, "a"), K("M90,24 A28,28 0 0 1 90,64", 4, "s")),
            D("osk", "#8A8F98", @"^on-screen keyboard$", @"osk\.exe", F(Rr(8, 26, 84, 50, 9)),
                F(Rr(16, 34, 10, 9, 2), "c"), F(Rr(30, 34, 10, 9, 2), "c"), F(Rr(44, 34, 10, 9, 2), "c"), F(Rr(58, 34, 10, 9, 2), "c"), F(Rr(72, 34, 12, 9, 2), "c"),
                F(Rr(20, 47, 10, 9, 2), "c"), F(Rr(34, 47, 10, 9, 2), "c"), F(Rr(48, 47, 10, 9, 2), "c"), F(Rr(62, 47, 10, 9, 2), "c"), F(Rr(28, 61, 44, 8, 3), "a")),
            D("charmap", "#8A8F98", @"^character map$", @"charmap", F(Rr(10, 10, 80, 80, 12)), T("Ω", 44, 37, 52, "c"), T("a", 30, 70, 60, "a")),
            D("security", "#2BB673", @"^windows security$", @"SecHealthUI", F("M50,8 L86,22 V48 C86,72 68,86 50,92 C32,86 14,72 14,48 V22 Z"), K("M33,50 L45,62 L68,38", 8, "c")),
            D("firewall", "#E5484D", @"firewall", null, F(Rr(10, 22, 36, 16, 3)), F(Rr(50, 22, 40, 16, 3)), F(Rr(10, 42, 18, 16, 3)), F(Rr(32, 42, 36, 16, 3)), F(Rr(72, 42, 18, 16, 3)), F(Rr(10, 62, 36, 16, 3)), F(Rr(50, 62, 40, 16, 3)), F("M58,14 C66,26 76,22 74,6 C86,16 88,32 80,40 H54 C48,32 52,22 58,14 Z", "a")),
            D("msinfo", "#3D8BFD", @"^system information$", @"msinfo32", F(Ci(50, 50, 40)), F(Ci(50, 29, 6.5), "c"), F(Rr(44.5, 41, 11, 33, 5.5), "c")),
            D("msconfig", "#5B8DEF", @"^system configuration$", @"msconfig", F(Rr(14, 10, 72, 80, 10)), K("M26,32 L32,38 L42,28", 5, "a"), F(Rr(50, 30, 26, 5, 2.5), "c"), K("M26,52 L32,58 L42,48", 5, "a"), F(Rr(50, 50, 26, 5, 2.5), "c"), K("M26,72 L32,78 L42,68", 5, "a"), F(Rr(50, 70, 26, 5, 2.5), "c")),
            D("perfmon", "#2BB673", @"^performance monitor$", @"perfmon", F(Rr(10, 14, 80, 72, 10)), F(Rr(18, 22, 64, 56, 4), "c"), F(Rr(24, 56, 9, 16, 2), "a"), F(Rr(38, 44, 9, 28, 2), "a"), F(Rr(52, 50, 9, 22, 2), "a"), F(Rr(66, 32, 9, 40, 2), "a")),
            D("resmon", "#2BB673", @"^resource monitor$", @"resmon", F(Ci(50, 50, 40)), F("M50,50 L50,14 A36,36 0 0 1 85,58 Z", "a"), F(Ci(50, 50, 10), "c")),
            D("taskschd", "#5B8DEF", @"^task scheduler$", @"taskschd", F(Rr(10, 14, 64, 64, 9)), F(Rr(10, 14, 64, 16, 8), "a"), F(Rr(18, 38, 10, 8, 2), "c"), F(Rr(33, 38, 10, 8, 2), "c"), F(Rr(48, 38, 10, 8, 2), "c"), F(Rr(18, 52, 10, 8, 2), "c"), F(Ci(70, 72, 20), "c"), F(Ring(70, 72, 16, 5)), K("M70,63 V72 L77,76", 3.5, "a")),
            D("compmgmt", "#5B8DEF", @"^computer management$", @"compmgmt", Monitor(), Badge("gear")),
            D("windows-tools", "#8A8F98", @"^(windows tools|windows administrative tools|administrative tools)$", null, F(Rr(8, 36, 84, 50, 9)), K("M36,36 V28 Q36,22 42,22 H58 Q64,22 64,28 V36", 6), F(Rr(8, 52, 84, 6, 0), "c"), F(Rr(42, 48, 16, 14, 3), "a")),
            D("secpol", "#E5A13A", @"^local security policy$", @"secpol", K("M34,46 V32 A16,16 0 0 1 66,32 V46", 8), F(Rr(22, 44, 56, 44, 9)), F(Ci(50, 62, 6), "c"), F(Rr(47, 62, 6, 14, 3), "c")),
            D("recovery-drive", "#E5A13A", @"^recovery drive$", @"RecoveryDrive", F(Rr(28, 30, 44, 60, 9)), F(Rr(36, 10, 28, 22, 4), "s"), F(Rr(42, 16, 6, 6, 1), "c"), F(Rr(52, 16, 6, 6, 1), "c"), K("M40,62 A10,10 0 1 0 50,52 M50,46 V58 H40", 4.5, "a")),
            D("backup", "#3D8BFD", @"^windows backup$|^backup$", null, F("M28,76 H72 A18,18 0 0 0 70,40 A22,22 0 0 0 28,44 A16,16 0 0 0 28,76 Z"), K("M50,70 V46 M40,56 L50,46 L60,56", 6, "c")),
            D("memdiag", "#2BB673", @"^windows memory diagnostic$", @"MdSched", F(Rr(6, 32, 88, 30, 4)), F(Rr(14, 38, 14, 18, 2), "c"), F(Rr(32, 38, 14, 18, 2), "c"), F(Rr(54, 38, 14, 18, 2), "c"), F(Rr(72, 38, 14, 18, 2), "c"), K("M14,68 V74 M24,68 V74 M34,68 V74 M44,68 V74 M56,68 V74 M66,68 V74 M76,68 V74 M86,68 V74", 3.5, "a")),
            D("speech", "#7A5AF8", @"^windows speech recognition$|voice access", null, F(Rr(37, 10, 26, 48, 13)), K("M26,46 A24,24 0 0 0 74,46", 6), F(Rr(47, 70, 6, 12, 3)), F(Rr(34, 80, 32, 7, 3.5), "a")),
            D("odbc-32", "#5B8DEF", @"^odbc data sources \(32-bit\)$", null, Cylinder(), Badge("x86")),
            D("odbc-64", "#5B8DEF", @"^odbc data sources( \(64-bit\))?$", @"odbcad32", Cylinder(), Badge("64")),
            D("iscsi", "#5B8DEF", @"^iscsi initiator$", @"iscsicpl", Cylinder(), Badge("net")),
            D("component-services", "#8A8F98", @"^component services$", @"comexp", F("M14,30 H34 A8,8 0 1 1 50,30 H66 V46 A8,8 0 1 1 66,62 V78 H50 A8,8 0 1 0 34,78 H14 Z"), F(Rr(70, 14, 20, 20, 5), "a")),
            D("hyperv-create", "#5B8DEF", @"^hyper-v quick create$", null, F(Rr(14, 12, 72, 22, 6)), F(Rr(14, 39, 72, 22, 6)), F(Rr(14, 66, 72, 22, 6)), F(Ci(26, 23, 4), "a"), F(Ci(26, 50, 4), "a"), F(Ci(26, 77, 4), "a"), Badge("plus")),
            D("hyperv", "#5B8DEF", @"^hyper-v manager$", @"virtmgmt", F(Rr(14, 12, 72, 22, 6)), F(Rr(14, 39, 72, 22, 6)), F(Rr(14, 66, 72, 22, 6)), F(Ci(26, 23, 4), "a"), F(Ci(26, 50, 4), "a"), F(Ci(26, 77, 4), "a"), F(Rr(56, 21, 22, 4, 2), "c"), F(Rr(56, 48, 22, 4, 2), "c"), F(Rr(56, 75, 22, 4, 2), "c")),
            D("wsl-settings", "#E5A13A", @"^wsl settings$", null, Penguin(), Badge("gear")),
            D("wsl", "#E5A13A", @"^(wsl|ubuntu.*|debian|kali linux|.*linux.*)$", @"(^|\\)wsl\.exe$", Penguin()),
            D("dism-tools", "#3D8BFD", @"^deployment and imaging tools", null, Terminal(), Badge("gear")),
            D("sim", "#3D8BFD", @"^windows system image manager$", null, F(Ring(50, 50, 40, 26)), F(Ring(50, 50, 22, 4), "a"), Badge("gear")),
            D("realtek", "#E5484D", @"realtek audio", null, F("M14,38 H30 L52,20 V80 L30,62 H14 Z"), K("M64,36 A18,18 0 0 1 64,64", 6, "a"), K("M76,26 A30,30 0 0 1 76,74", 5, "s")),
            // ---- browsers and chat ----
            D("chrome", "#4285F4", @"^google chrome$", @"chrome\.exe", F(Ci(50, 50, 40), "#E5484D"), F("M50,50 L84.6,30 A40,40 0 0 1 50,90 Z", "#F5B73B"), F("M50,50 L50,90 A40,40 0 0 1 15.4,30 Z", "#34A853"), F(Ci(50, 50, 18), "c"), F(Ci(50, 50, 13), "a")),
            D("firefox", "#FF7139", @"firefox", @"firefox\.exe", F(Ci(50, 52, 38), "a"), F("M24,30 C30,16 44,10 56,12 C48,16 46,24 50,30 C60,26 74,32 78,46 C82,66 66,84 46,82 C28,80 16,64 18,48 C22,56 30,60 38,58 C30,52 30,40 24,30 Z")),
            D("brave", "#FB542B", @"^brave", @"brave\.exe", F("M30,10 H70 L84,26 L78,62 L50,90 L22,62 L16,26 Z"), F("M50,34 L62,58 H38 Z", "c")),
            D("opera", "#FF1B2D", @"^opera", @"opera\.exe", F(Ring(50, 50, 40, 14)), F("M50,22 A12,28 0 1 1 49.9,22 Z", "a")),
            D("discord", "#5865F2", @"^discord$", @"discord", F("M20,30 Q32,20 42,20 L45,26 Q50,25 55,26 L58,20 Q68,20 80,30 Q90,48 88,72 Q78,80 66,82 L62,74 Q50,78 38,74 L34,82 Q22,80 12,72 Q10,48 20,30 Z"), F("M30,52 A7,8 0 1 1 44,52 A7,8 0 1 1 30,52 Z", "c"), F("M56,52 A7,8 0 1 1 70,52 A7,8 0 1 1 56,52 Z", "c")),
            D("telegram", "#2AABEE", @"^telegram", @"telegram", F(Ci(50, 50, 40)), F("M24,49 L74,28 L66,74 L52,64 L44,72 L44,60 L66,38 L38,57 Z", "c")),
            D("whatsapp", "#25D366", @"^whatsapp", @"whatsapp", F(Ci(52, 48, 36)), F("M26,70 L14,90 L38,80 Z"), K("M40,34 Q36,52 52,62 Q60,66 66,60", 8, "c")),
            D("slack", "#E01E5A", @"^slack$", @"slack", F(Rr(20, 40, 60, 12, 6), "#36C5F0"), F(Rr(44, 16, 12, 60, 6), "#2EB67D"), F(Rr(20, 56, 60, 12, 6), "#ECB22E"), F(Rr(28, 24, 12, 60, 6), "#E01E5A")),
            D("zoom", "#2D8CFF", @"^zoom", @"zoom\.exe", F(Rr(10, 28, 58, 44, 10)), F("M70,42 L90,30 V70 L70,58 Z", "a")),
            D("teams", "#6264A7", @"^(microsoft )?teams", @"ms-teams|Teams\.exe", F(Rr(10, 26, 56, 56, 10)), T("T", 38, 38, 54, "c"), F(Ci(78, 34, 10), "a"), F(Rr(68, 48, 24, 30, 8), "a")),
            D("chatgpt", "#10A37F", @"^chatgpt$", @"chatgpt|OpenAI", F(Ring(50, 33, 17, 6)), F(Ring(65, 41.5, 17, 6)), F(Ring(65, 58.5, 17, 6)), F(Ring(50, 67, 17, 6)), F(Ring(35, 58.5, 17, 6)), F(Ring(35, 41.5, 17, 6))),
            D("claude", "#D97757", @"^claude$", @"claude", F(Star(50, 50, 42, 10, 12), "a"), F(Ci(50, 50, 9))),
            D("copilot", "#3D8BFD", @"copilot", null, F(Star(50, 50, 40, 16, 4)), F(Star(76, 22, 12, 4, 4), "a")),
            // ---- creative, dev and tools ----
            D("vscode", "#007ACC", @"^visual studio code", @"code\.exe", K("M34,28 L14,50 L34,72", 8), K("M66,28 L86,50 L66,72", 8), K("M57,20 L43,80", 7, "a")),
            D("visual-studio", "#865FC5", @"^visual studio( 20\d\d)?$", @"devenv", F("M70,10 L90,20 V80 L70,90 L30,58 L16,70 L10,66 V34 L16,30 L30,42 Z"), F("M70,30 L48,50 L70,70 Z", "c")),
            D("kiro", "#9046FF", @"^kiro$", @"kiro", F("M22,88 V44 A28,28 0 0 1 78,44 V88 L68,79 L59,88 L50,79 L41,88 L32,79 Z"), F("M37,46 A5,7 0 1 1 47,46 A5,7 0 1 1 37,46 Z", "c"), F("M55,46 A5,7 0 1 1 65,46 A5,7 0 1 1 55,46 Z", "c")),
            D("git-bash", "#F05133", @"^git bash$", null, GitTree(), Badge("prompt")),
            D("git-cmd", "#F05133", @"^git cmd$", null, GitTree(), Badge("cmd")),
            D("git-gui", "#F05133", @"^git gui$", null, GitTree(), Badge("window")),
            D("git-faq", "#F05133", @"^git faqs", null, GitTree(), Badge("question")),
            D("git-notes", "#F05133", @"^git release notes$", null, GitTree(), Badge("doc")),
            D("git", "#F05133", @"^git\b", @"git-bash|git\.exe", GitTree()),
            D("python-docs", "#3776AB", @"^python .*(manuals|module docs)", null, Python(), Badge("book")),
            D("idle", "#3776AB", @"^idle", null, Python(), Badge("window")),
            D("python", "#3776AB", @"^python", @"python(w)?\.exe$", Python()),
            D("notepad-plus", "#90E59A", @"^notepad\+\+$", @"notepad\+\+", F("M24,10 H64 L82,28 V86 Q82,92 76,92 H24 Q18,92 18,86 V16 Q18,10 24,10 Z"), F(Rr(28, 42, 34, 5, 2.5), "c"), F(Rr(28, 54, 28, 5, 2.5), "c"), K("M64,58 V82 M52,70 H76", 6, "a")),
            D("blender", "#F5792A", @"^blender", @"blender", F(Ring(58, 58, 30, 10)), F(Ci(58, 58, 9), "a"), K("M14,40 L44,40 M28,26 L52,44", 8)),
            D("obs", "#8A8F98", @"^obs studio", @"obs64", F(Ci(50, 50, 40)), F(Ci(50, 30, 11), "c"), F(Ci(32, 62, 11), "c"), F(Ci(68, 62, 11), "c"), F(Ci(50, 50, 6), "a")),
            D("vlc", "#FF8800", @"^vlc", @"vlc\.exe", F("M42,14 H58 L76,76 H24 Z"), F("M37,36 H63 L66,48 H34 Z", "c"), F("M31,58 H69 L72,68 H28 Z", "c"), F(Rr(14, 76, 72, 12, 5), "a")),
            D("spotify", "#1DB954", @"^spotify", @"spotify", F(Ci(50, 50, 40)), K("M26,38 Q50,27 76,41", 7.5, "c"), K("M30,53 Q50,44 72,55", 6.5, "c"), K("M34,67 Q50,60 67,69", 5.5, "c")),
            D("apple-music", "#FA2D48", @"^apple music$|^itunes$", @"AppleMusic|iTunes", F(Ci(32, 72, 12)), F(Ci(70, 64, 12)), F(Rr(38, 20, 7, 54, 3.5)), F(Rr(76, 12, 7, 54, 3.5)), F("M38,20 L83,12 V26 L38,34 Z", "a")),
            D("music-presence", "#FA2D48", @"^music presence$", null, F(Ci(36, 70, 13)), F(Rr(43, 18, 8, 54, 4)), F("M43,18 Q62,22 66,38 Q56,30 43,32 Z"), K("M70,52 A12,12 0 0 1 70,72", 5, "a"), K("M80,44 A22,22 0 0 1 80,80", 4, "s")),
            D("apple-tv", "#8A8F98", @"^apple tv$", @"AppleTV", F(Rr(8, 18, 84, 56, 9)), F(Rr(15, 25, 70, 42, 4), "c"), T("tv", 26, 50, 46, "a"), F(Rr(32, 80, 36, 6, 3))),
            D("seven-zip", "#5A5A5A", @"^7-zip", @"7zfm", F(Rr(12, 12, 76, 76, 10)), T("7z", 40, 50, 52, "c")),
            D("winrar", "#7A5AF8", @"^winrar", @"winrar", F(Rr(14, 14, 22, 72, 4), "#E5484D"), F(Rr(39, 14, 22, 72, 4), "#3D8BFD"), F(Rr(64, 14, 22, 72, 4), "#2BB673"), F(Rr(10, 42, 80, 14, 3))),
            D("vmware-network", "#607078", @"^virtual network editor$", null, F(Ci(50, 22, 12)), F(Ci(22, 74, 12)), F(Ci(78, 74, 12)), K("M50,22 L22,74 L78,74 Z", 5, "a")),
            D("vmware", "#607078", @"^vmware", @"vmware\.exe", K(Rr(12, 30, 48, 48, 8), 8), K(Rr(40, 14, 48, 48, 8), 8, "a")),
            D("salad", "#B2D530", @"^salad$", @"salad", F("M18,82 C18,40 48,14 86,14 C86,52 60,82 18,82 Z"), K("M22,78 L70,30", 4.5, "c")),
            D("honeygain", "#F5B73B", @"^honeygain", @"honeygain", F(Hex(50, 30, 16)), F(Hex(32, 61, 16), "a"), F(Hex(68, 61, 16))),
            D("kovaak", "#E5484D", @"^kovaak", @"FPSAimTrainer|kovaak", F(Ring(50, 50, 32, 6)), K("M50,8 V28 M50,72 V92 M8,50 H28 M72,50 H92", 6), F(Ci(50, 50, 6), "a")),
            D("snapkey", "#F5B73B", @"^snapkey$", @"snapkey", F(Rr(12, 16, 76, 64, 12)), F(Rr(12, 16, 76, 54, 12), "s"), F("M56,22 L36,50 H50 L44,74 L66,42 H52 Z", "a")),
            D("omnirush", "#3D8BFD", @"^omnirush$", @"omnirush", K("M18,70 C30,30 70,26 82,46", 9), F("M86,30 L88,56 L64,48 Z", "a"), F(Ci(22, 72, 7), "a")),
            D("msi-afterburner", "#E5484D", @"afterburner", @"MSIAfterburner", K("M16,70 A36,36 0 1 1 84,70", 8), F("M50,30 C60,44 66,52 60,64 C56,72 44,72 40,64 C36,54 46,46 50,30 Z", "a")),
            // ---- games and launchers ----
            D("steam-support", "#2A75BB", @"^steam support", null, F(Ring(62, 38, 20, 7)), F(Ci(62, 38, 7), "a"), K("M62,38 L32,66", 10), F(Ci(30, 68, 12)), F(Ci(30, 68, 4.5), "c"), Badge("question")),
            D("steam", "#2A75BB", @"^steam$", @"(^|\\)steam\.exe$", F(Ring(62, 38, 20, 7)), F(Ci(62, 38, 7), "a"), K("M62,38 L32,66", 10), F(Ci(30, 68, 12)), F(Ci(30, 68, 4.5), "c")),
            D("epic", "#8A8F98", @"^epic games", @"EpicGamesLauncher", F("M18,8 H82 V76 L50,92 L18,76 Z"), T("E", 46, 50, 46, "c")),
            D("ea", "#FF4747", @"^ea( app)?$|electronic arts", @"EADesktop", F(Ci(50, 50, 40)), T("EA", 34, 50, 51, "c")),
            D("ubisoft", "#3D8BFD", @"^ubisoft connect", @"upc\.exe|UbisoftConnect", F(Ring(50, 50, 40, 10)), F(Ring(54, 50, 22, 8), "a"), F(Ci(58, 50, 6))),
            D("battlenet", "#148EFF", @"^battle\.net", @"Battle\.net", F(Ring(50, 50, 38, 9), "a"), F(Rr(40, 18, 10, 60, 5)), F(Ring(56, 60, 16, 8))),
            D("gog", "#7A3CE0", @"^gog galaxy", @"GalaxyClient", F(Rr(10, 22, 80, 56, 14)), T("GOG", 26, 50, 51, "c")),
            D("riot", "#EB0029", @"^riot client$", @"RiotClient", F("M58,8 L22,56 H46 L38,92 L80,38 H55 Z")),
            D("valorant", "#FF4655", @"^valorant$", @"VALORANT", F("M10,20 L52,80 H76 L34,20 Z"), F("M90,20 L68,52 H48 L70,20 Z", "a")),
            D("roblox-studio", "#00A2FF", @"^roblox studio$", @"RobloxStudio", F("M30,12 L88,28 L72,88 L12,72 Z"), F("M45,42 L60,46 L56,61 L41,57 Z", "c"), Badge("hammer")),
            D("roblox", "#E2231A", @"^roblox", @"RobloxPlayer", F("M30,12 L88,28 L72,88 L12,72 Z"), F("M45,42 L60,46 L56,61 L41,57 Z", "c")),
            D("xbox", "#107C10", @"^xbox", @"GamingApp|XboxApp", F(Ci(50, 50, 40)), K("M26,24 C40,36 60,64 74,76 M74,24 C60,36 40,64 26,76", 8, "c")),
            D("game-generic", "#FB5668", @"demo$|game$|^grilluminati", null, Gamepad()),
            // ---- hardware vendors ----
            D("nvidia-control", "#76B900", @"^nvidia control panel$", @"nvcplui", Gpu(), Badge("gear")),
            D("nvidia", "#76B900", @"^nvidia( app)?$|geforce", @"NVIDIA app|nvcontainer", Gpu()),
            D("amd", "#ED1C24", @"^amd (software|adrenalin)", @"RadeonSoftware", F("M18,18 H82 V82 L66,66 V34 H34 Z"), F("M18,34 L34,50 V66 H50 L66,82 H18 Z", "a")),
            D("logitech", "#00B8FC", @"^logitech g hub$|^g hub$", @"lghub", K("M76,32 A30,30 0 1 0 80,56 H54", 12)),
            D("gigabyte-light", "#F5B73B", @"dynamic light|rgb fusion", null, F(Ci(50, 42, 24)), F(Rr(40, 62, 20, 18, 5)), K("M50,6 V12 M18,20 L23,25 M82,20 L77,25 M10,46 H16 M84,46 H90", 4.5, "a")),
            D("gigabyte-cc", "#E5484D", @"gigabyte control center|^gcc$", @"GigabyteControlCenter", K("M18,68 A34,34 0 1 1 82,68", 8), K("M50,64 L68,38", 6, "a"), F(Ci(50, 64, 7))),
            D("realtek-generic", "#E5484D", @"^audio console$", null, F("M14,38 H30 L52,20 V80 L30,62 H14 Z"), K("M64,36 A18,18 0 0 1 64,64", 6, "a")),
            // ---- web and Microsoft apps that may still be installed ----
            D("outlook", "#0F78D4", @"^outlook", @"OutlookForWindows|olk\.exe", F(Rr(34, 16, 56, 68, 8), "s"), F(Rr(10, 28, 48, 48, 8)), F(Ring(34, 52, 13, 6), "c")),
            D("office", "#E5484D", @"^(microsoft 365( copilot)?|office|word|excel|powerpoint)$", @"WINWORD|EXCEL|POWERPNT", F(Rr(14, 14, 72, 72, 14)), T("O", 46, 50, 52, "c")),
            D("onedrive", "#0F78D4", @"^onedrive", @"OneDrive", F("M24,74 H76 A16,16 0 0 0 74,42 A22,22 0 0 0 32,40 A17,17 0 0 0 24,74 Z")),
            D("help", "#3D8BFD", @"^(get help|tips|help)$", null, F(Ci(50, 50, 40)), T("?", 52, 50, 52, "c")),
        };
    }
}
