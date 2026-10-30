using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Baka.Desktop
{
    // BAKA Arena: the gaming hub. Profiles, live performance, and every installed Steam and Epic game in
    // one grid that starts the game through its own launcher.
    class Arena : AppWindow
    {
        static Arena current;
        TextBlock cpu, gpu, ram, disk;
        public static void Open() { if (current != null) { current.Activate(); return; } current = new Arena(); current.Closed += (o, e) => current = null; current.Show(); current.Activate(); }
        public static Arena Current => current;

        Arena() : base("BAKA Arena", 1000, 660) { Rebuild(); App.Tick += OnTick; Closed += (o, e) => App.Tick -= OnTick; }

        public override void Rebuild()
        {
            var sp = new StackPanel { Margin = new Thickness(26, 4, 26, 24) };
            sp.Children.Add(Ui.Heading("Arena", "Profiles, performance and your games. A game starting switches BAKA to Gaming by itself."));
            var profiles = new WrapPanel { Margin = new Thickness(0, 0, 0, 14) };
            foreach (var (id, name, glyph, text) in new[] { ("Desktop", "Desktop", 0xE7F4, "Everything on, animations and widgets."), ("CompetitiveGaming", "Gaming", 0xE7FC, "Game Mode on, background apps paused, no transparency or animations."), ("Benchmark", "Benchmark", 0xE9D9, "Records conditions; Windows left exactly as it is.") })
            {
                bool on = Profiles.Active == id;
                var card = new Border { Width = 296, Margin = new Thickness(0, 0, 12, 12), Padding = new Thickness(16), CornerRadius = new CornerRadius(14), Cursor = Cursors.Hand, Background = on ? Theme.B(Theme.AccentHex, 48) : Theme.B(Theme.Current.SurfaceAlt, 140), BorderBrush = on ? Theme.Accent : Theme.B(Theme.Current.Border, 70), BorderThickness = new Thickness(on ? 1.6 : 1) };
                var c = new StackPanel(); var top = new StackPanel { Orientation = Orientation.Horizontal };
                top.Children.Add(Ui.Glyph(glyph, 18, on ? Theme.Accent : Theme.Text)); var n = Ui.Text(name, 15, FontWeights.SemiBold); n.Margin = new Thickness(10, 0, 0, 0); top.Children.Add(n);
                c.Children.Add(top); var d = Ui.Muted(text, 11.5); d.Margin = new Thickness(0, 6, 0, 0); c.Children.Add(d);
                card.Child = c;
                string pid = id;
                Ui.OnClick(card, () => { Profiles.Manual = pid == "Desktop" ? null : pid; Profiles.Set(pid, "arena"); Rebuild(); });
                profiles.Children.Add(card);
            }
            sp.Children.Add(profiles);
            var stats = new System.Windows.Controls.Primitives.UniformGrid { Columns = 4, Margin = new Thickness(0, 0, 0, 18) };
            stats.Children.Add(Stat("CPU", out cpu)); stats.Children.Add(Stat("GPU", out gpu)); stats.Children.Add(Stat("Memory", out ram)); stats.Children.Add(Stat("System drive", out disk));
            sp.Children.Add(stats);
            var games = Library();
            sp.Children.Add(Ui.Text("Your games (" + games.Count + ")", 15, FontWeights.SemiBold));
            if (games.Count == 0) { var none = Ui.Muted("No Steam, Epic or Riot games found yet. Install a game and it appears here.", 12); none.Margin = new Thickness(0, 6, 0, 0); sp.Children.Add(none); }
            var grid = new WrapPanel { Margin = new Thickness(0, 10, 0, 0) };
            foreach (var g in games) grid.Children.Add(GameCard(g));
            sp.Children.Add(grid);
            var tools = new WrapPanel { Margin = new Thickness(0, 14, 0, 0) };
            foreach (var (label, glyph, uri) in new[] { ("Game Mode", 0xE7FC, "ms-settings:gaming-gamemode"), ("Graphics", 0xE7F4, "ms-settings:display-advancedgraphics"), ("Display", 0xE7F8, "ms-settings:display"), ("Sound", 0xE995, "ms-settings:sound") })
            { var u = uri; var b = Ui.Labeled(glyph, label, () => Launcher.Run(u, () => Process.Start(u))); b.Margin = new Thickness(0, 0, 8, 8); tools.Children.Add(b); }
            sp.Children.Add(tools);
            Body.Content = Ui.Scroll(sp);
            OnTick();
        }
        FrameworkElement Stat(string label, out TextBlock value)
        {
            var sp = new StackPanel(); sp.Children.Add(Ui.Text(label.ToUpperInvariant(), 10.5, FontWeights.Bold, Theme.Muted));
            value = Ui.Text("—", 22, FontWeights.SemiBold); sp.Children.Add(value);
            return new Border { Child = sp, Padding = new Thickness(14, 10, 14, 10), Margin = new Thickness(0, 0, 10, 0), CornerRadius = new CornerRadius(12), Background = Theme.B(Theme.Current.SurfaceAlt, 120) };
        }
        int ticks;
        void OnTick()
        {
            if (!IsVisible || cpu == null || ticks++ % 2 != 0) return;
            var m = Metrics.Read();
            cpu.Text = m.Cpu == null ? "—" : m.Cpu + "%"; gpu.Text = m.Gpu == null ? "—" : m.Gpu + "%";
            ram.Text = m.MemoryUsedGb.ToString("0.0") + " GB"; disk.Text = m.DiskFreeGb.ToString("0") + " GB free";
        }

        class Game { public string Name, Launch, Args, Image, Source; }
        FrameworkElement GameCard(Game g)
        {
            var sp = new StackPanel();
            var art = new Border { Height = 98, CornerRadius = new CornerRadius(10), Background = Theme.B(Theme.Current.SurfaceAlt, 200), ClipToBounds = true };
            if (g.Image != null) try { var bmp = new BitmapImage(); bmp.BeginInit(); bmp.CacheOption = BitmapCacheOption.OnLoad; bmp.DecodePixelWidth = 420; bmp.UriSource = new Uri(g.Image); bmp.EndInit(); bmp.Freeze(); art.Background = new ImageBrush(bmp) { Stretch = Stretch.UniformToFill }; } catch { }
            if (g.Image == null) art.Child = Ui.Glyph(0xE7FC, 28, Theme.Muted);
            sp.Children.Add(art);
            var n = Ui.Text(g.Name, 12.5, FontWeights.SemiBold); n.Margin = new Thickness(2, 6, 0, 0); sp.Children.Add(n);
            sp.Children.Add(Ui.Text(g.Source, 10.5, null, Theme.Muted));
            var b = new Border { Width = 210, Margin = new Thickness(0, 0, 12, 14), Child = sp, Cursor = Cursors.Hand, ToolTip = "Play " + g.Name };
            b.MouseEnter += (o, e) => art.Opacity = 0.85; b.MouseLeave += (o, e) => art.Opacity = 1;
            Ui.OnClick(b, () => { try { Process.Start(new ProcessStartInfo(g.Launch, g.Args ?? "") { UseShellExecute = true }); Log.Write("arena-play name=\"" + g.Name + "\""); } catch (Exception ex) { Log.Write("arena-play-failed error=\"" + ex.Message + "\""); } });
            return b;
        }

        static List<Game> Library()
        {
            var games = new List<Game>();
            try
            {
                string steam = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam")?.GetValue("SteamPath") as string ?? Paths.Expand(@"%ProgramFiles(x86)%\Steam");
                steam = steam.Replace('/', '\\');
                var libs = new List<string> { steam };
                string vdf = Path.Combine(steam, @"steamapps\libraryfolders.vdf");
                if (File.Exists(vdf)) foreach (Match m in Regex.Matches(File.ReadAllText(vdf), "\"path\"\\s+\"([^\"]+)\"")) libs.Add(m.Groups[1].Value.Replace(@"\\", @"\"));
                foreach (var lib in libs.Distinct(StringComparer.OrdinalIgnoreCase))
                {
                    string apps = Path.Combine(lib, "steamapps"); if (!Directory.Exists(apps)) continue;
                    foreach (var acf in Directory.GetFiles(apps, "appmanifest_*.acf"))
                    {
                        string text = File.ReadAllText(acf);
                        string id = Regex.Match(text, "\"appid\"\\s+\"(\\d+)\"").Groups[1].Value, name = Regex.Match(text, "\"name\"\\s+\"([^\"]+)\"").Groups[1].Value;
                        if (id.Length == 0 || name.Length == 0 || Regex.IsMatch(name, "(?i)redistributable|steamworks|proton|runtime|sdk")) continue;
                        string cache = Path.Combine(steam, @"appcache\librarycache");
                        string img = new[] { Path.Combine(cache, id, "header.jpg"), Path.Combine(cache, id + "_header.jpg"), Path.Combine(cache, id, "library_header.jpg") }.FirstOrDefault(File.Exists);
                        if (img == null && Directory.Exists(Path.Combine(cache, id))) img = Directory.GetFiles(Path.Combine(cache, id), "*.jpg", SearchOption.AllDirectories).OrderByDescending(f => new FileInfo(f).Length).FirstOrDefault();
                        games.Add(new Game { Name = name, Launch = "steam://rungameid/" + id, Image = img, Source = "Steam" });
                    }
                }
            }
            catch (Exception e) { Log.Write("arena-steam-scan-failed error=\"" + e.Message + "\""); }
            try
            {
                string manifests = Paths.Expand(@"%ProgramData%\Epic\EpicGamesLauncher\Data\Manifests");
                if (Directory.Exists(manifests))
                    foreach (var item in Directory.GetFiles(manifests, "*.item"))
                    {
                        var j = Json.Obj(Json.Parse(File.ReadAllText(item)));
                        string name = Json.Str(j, "DisplayName"), app = Json.Str(j, "AppName");
                        if (name.Length == 0 || app.Length == 0) continue;
                        games.Add(new Game { Name = name, Launch = "com.epicgames.launcher://apps/" + app + "?action=launch&silent=true", Source = "Epic Games" });
                    }
            }
            catch (Exception e) { Log.Write("arena-epic-scan-failed error=\"" + e.Message + "\""); }
            // Riot games start through the Riot Client (it signs in and updates them first).
            try
            {
                string installs = Paths.Expand(@"%ProgramData%\Riot Games\RiotClientInstalls.json"), client = null;
                if (File.Exists(installs)) client = Json.Str(Json.Obj(Json.Parse(File.ReadAllText(installs))), "rc_default").Replace('/', '\\');
                if (string.IsNullOrEmpty(client) || !File.Exists(client)) client = new[] { @"C:\Riot Games\Riot Client\RiotClientServices.exe", @"D:\Riot Games\Riot Client\RiotClientServices.exe" }.FirstOrDefault(File.Exists);
                if (client != null)
                {
                    string root = Path.GetDirectoryName(Path.GetDirectoryName(client));
                    foreach (var (name, product, folder) in new[] { ("VALORANT", "valorant", @"VALORANT\live"), ("League of Legends", "league_of_legends", "League of Legends") })
                        if (Directory.Exists(Path.Combine(root, folder)))
                            games.Add(new Game { Name = name, Launch = client, Args = "--launch-product=" + product + " --launch-patchline=live", Source = "Riot Games" });
                }
            }
            catch (Exception e) { Log.Write("arena-riot-scan-failed error=\"" + e.Message + "\""); }
            return games.OrderBy(g => g.Name).ToList();
        }
    }
}
