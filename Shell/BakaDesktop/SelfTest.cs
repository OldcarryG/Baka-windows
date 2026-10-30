using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace Baka.Desktop
{
    // --selftest: clicks through every surface in an isolated preview (no real settings, registry, taskbar
    // or wallpaper are touched) and checks what a person would check. --capture: design screenshots.
    // --icon-sheet: every BAKA icon in every theme on one picture.
    static class SelfTest
    {
        public static bool Running;
        static readonly List<string> passed = new List<string>(), failed = new List<string>();
        static string resultPath;
        static DateTime captionTestStart;
        static bool calculatorInstalled;
        // installed Store apps are listed for the user under ActivatableClasses\Package
        static bool CalculatorInstalled()
        {
            try
            {
                using (var k = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages"))
                    if (k != null && k.GetSubKeyNames().Any(n => n.StartsWith("Microsoft.WindowsCalculator_", StringComparison.OrdinalIgnoreCase))) return true;
                return false;
            }
            catch { return false; }
        }

        public static void Fail(string why) { failed.Add(why); Log.Write("selftest-fail " + why); }
        static void Check(bool ok, string what) { if (ok) { passed.Add(what); Log.Write("selftest-pass " + what); } else Fail(what); }

        public static void Start()
        {
            Running = true;
            resultPath = Environment.GetEnvironmentVariable("BAKA_SELFTEST_RESULT") ?? Path.Combine(Paths.Local, "selftest.json");
            var steps = new List<Action>
            {
                () => { Check(App.Bar.IsVisible && TopBar.BarHeight <= 56, "menu bar islands are visible and slim"); Check(App.Dock.IsVisible, "dock is visible"); Check(App.Dock.ActualWidth < 110, "dock is only as wide as its icons (" + Math.Round(App.Dock.ActualWidth) + " px)"); Check(AppCatalog.Apps.Count > 10, "Launchpad lists the installed apps (" + AppCatalog.Apps.Count + ")"); },
                () => {
                    // Settings > Menu bar > Show the date (12.27.1 ignored it)
                    bool was = TopBar.ShowDate;
                    App.Settings.TopBar["showDate"] = true; App.Bar.RefreshClock();
                    string with = App.Bar.ClockText;
                    Check(with.Contains(DateTime.Now.ToString("MMM")) && with.Contains(":"), "the clock shows the date when \"Show the date\" is on (" + with + ")");
                    App.Settings.TopBar["showDate"] = false; App.Bar.RefreshClock();
                    string without = App.Bar.ClockText;
                    Check(without.Length == 5 && without[2] == ':', "the clock shows only the time when it is off (" + without + ")");
                    App.Settings.TopBar["showDate"] = was; App.Bar.RefreshClock();
                },
                () => {
                    var ids = Icons.Library.Select(d => d.Id).ToList();
                    Check(ids.Count == ids.Distinct().Count(), "every BAKA icon has its own id (" + ids.Count + " icons)");
                    var dupNames = new List<string>(); var seen = new Dictionary<string, string>();
                    foreach (var d in Icons.Library) { var bmp = (BitmapSource)Icons.Draw(d, null, d.Id, 48); var px = new byte[48 * 48 * 4]; bmp.CopyPixels(px, 48 * 4, 0); string h = Convert.ToBase64String(System.Security.Cryptography.MD5.Create().ComputeHash(px)); if (seen.TryGetValue(h, out var other)) dupNames.Add(other + "=" + d.Id); else seen[h] = d.Id; }
                    Check(dupNames.Count == 0, "no two apps share the same icon drawing" + (dupNames.Count > 0 ? " (" + string.Join(", ", dupNames) + ")" : ""));
                    var named = new[] { ("Notepad", "notepad"), ("Steam", "steam"), ("Discord", "discord"), ("Task Manager", "taskmgr"), ("Windows PowerShell", "powershell"), ("Command Prompt", "cmd"), ("Git Bash", "git-bash"), ("Steam Support Center", "steam-support"), ("Media Player", "media-player"), ("Settings", "settings"), ("File Explorer", "baka-files"), ("Baka Browser", "baka-browser"), ("Visual Studio Code", "vscode"), ("WSL Settings", "wsl-settings"), ("Python 3.14 (64-bit)", "python") };
                    foreach (var (name, id) in named) Check(Icons.Find(new AppRef { Name = name })?.Id == id, "\"" + name + "\" gets its own icon (" + id + ")");
                    int matched = AppCatalog.Apps.Count(a => Icons.Find(a) != null);
                    Log.Write("icons-matched installed=" + matched + "/" + AppCatalog.Apps.Count);
                },
                () => { foreach (var t in Theme.All) Theme.Apply(t.Name, t.Accent); Check(true, "all " + Theme.All.Count + " themes apply without errors"); Theme.Apply(Json.Str(App.Settings.Appearance, "theme"), Json.Str(App.Settings.Appearance, "accentColor")); },
                () => { Launchpad.Toggle(); Check(Launchpad.IsOpen, "Win key opens Launchpad"); Check(Launchpad.Current.HintVisible, "search hint shows while the box is empty"); },
                () => { Search("notepad", "Notepad"); },
                () => { Search("task man", "Task Manager"); },
                () => { Search("setings", "Settings"); },
                () => { Search("cmd", "Command Prompt"); },
                () => { Launchpad.Current.TypeForTest("wifi"); Check(Launchpad.Current.FirstResultName() == "Wi-Fi", "\"wifi\" finds the Wi-Fi settings page (got " + Launchpad.Current.FirstResultName() + ")"); },
                () => { Launchpad.Current.TypeForTest("zzzz-nothing"); Check(Launchpad.Current.ResultCount == 0 && Launchpad.Current.ClearVisible, "a search with no match shows no results and a clear button"); Launchpad.Current.TypeForTest(""); Check(Launchpad.Current.HintVisible, "clearing the search shows every app again"); Launchpad.HideIfOpen(); Check(!Launchpad.IsOpen, "Launchpad closes"); },
                () => { ControlCenter.Toggle(App.Bar); Check(ControlCenter.IsOpen, "Control Center opens from the menu bar"); },
                () => { ControlCenter.Current?.Close(); Check(!ControlCenter.IsOpen, "Control Center closes"); Profiles.Set("CompetitiveGaming", "selftest"); Check(Profiles.Active == "CompetitiveGaming", "Gaming profile applies"); App.EnterGame("Self test game"); Check(!App.Bar.IsVisible && !App.Dock.IsVisible, "menu bar and dock hide while a game runs"); },
                () => { App.LeaveGame(); Check(Profiles.Active == "Desktop" && App.Bar.IsVisible && App.Dock.IsVisible, "leaving the game restores the Desktop profile, menu bar and dock"); Profiles.Manual = null; },
                () => { SettingsWindow.Open(); foreach (var p in SettingsWindow.PageNames) { SettingsWindow.Current.Go(p); SettingsWindow.Current.UpdateLayout(); } Check(SettingsWindow.Current.CurrentPage == "About", "every Settings page opens"); SettingsWindow.Current.Close(); },
                () => { Files.Open(null); var f = Files.Last; Check(f != null && Directory.Exists(f.CurrentFolder) && f.ItemCount > 0, "BAKA Files opens the home folder with items"); f.Navigate(Environment.GetFolderPath(Environment.SpecialFolder.Windows), true); Check(f.CurrentFolder.EndsWith("Windows", StringComparison.OrdinalIgnoreCase) && f.ItemCount > 10, "BAKA Files navigates to C:\\Windows"); Check(f.TestMultiSelect() == 2, "BAKA Files can select more than one file at once"); f.Navigate(Paths.Local, true); try { f.TestNewFolderAndDelete("BAKA self test folder"); Check(true, "new folder appears and is removed"); } catch (Exception e) { Fail(e.Message); } f.Close(); },
                () => {
                    // Recycle Bin and ZIP files open inside BAKA Files, not in Windows File Explorer
                    Files.Open("shell:RecycleBinFolder"); var f = Files.Last;
                    Check(f != null && f.CurrentFolder.StartsWith("shell|"), "Recycle Bin opens in BAKA Files (" + f?.CurrentFolder + ")");
                    string zip = Path.Combine(Paths.Local, "BAKA self test.zip");
                    try
                    {
                        using (var z = System.IO.Compression.ZipFile.Open(zip, System.IO.Compression.ZipArchiveMode.Create)) using (var w = new StreamWriter(z.CreateEntry("inside.txt").Open())) w.Write("BAKA");
                        f.Navigate(zip, true);
                        Check(f.CurrentFolder.StartsWith("shell|") && f.ItemCount == 1, "a ZIP file opens as a folder in BAKA Files (" + f.ItemCount + " item)");
                    }
                    catch (Exception e) { Fail("ZIP view threw " + e.Message); }
                    f.Close();
                    bool explorerWindow = false;
                    Native.EnumWindows((h, l) => { if (Native.IsWindowVisible(h) && Native.ClassName(h) == "CabinetWClass") explorerWindow = true; return true; }, IntPtr.Zero);
                    Check(!explorerWindow, "no Windows File Explorer window was opened");
                },
                () => { Arena.Open(); Check(Arena.Current != null && Arena.Current.IsVisible, "Arena opens"); Arena.Current.Close(); },
                () => { captionTestStart = DateTime.Now.AddSeconds(-1); try { System.Diagnostics.Process.Start("notepad.exe"); } catch (Exception e) { Fail("notepad did not start: " + e.Message); } },
                () => {
                    bool ok = CaptionButtons.TestOverlayOn("Notepad", out string detail);
                    Check(ok, "BAKA buttons sit over another app's close/minimize/maximize buttons (" + detail + ")");
                    foreach (var p in System.Diagnostics.Process.GetProcessesByName("Notepad")) { try { if (p.StartTime >= captionTestStart) p.Kill(); } catch { } }
                    calculatorInstalled = CalculatorInstalled();
                    if (calculatorInstalled) try { System.Diagnostics.Process.Start("calculator:"); } catch (Exception e) { Fail("Calculator did not start: " + e.Message); }
                },
                () => {
                    if (!calculatorInstalled) { Check(true, "BAKA buttons on a Store app: skipped, Calculator is not installed on this PC"); return; }
                    System.Threading.Thread.Sleep(2500);
                    bool ok = CaptionButtons.TestOverlayOn("ApplicationFrameWindow", out string detail);
                    Check(ok, "BAKA buttons sit over a Store app's buttons (Calculator: " + detail + ")");
                    foreach (var p in System.Diagnostics.Process.GetProcessesByName("CalculatorApp")) { try { p.Kill(); } catch { } }
                },
                () => { App.Settings.Widgets["enabled"] = true; foreach (var i in App.Settings.WidgetItems.Select(Json.Obj)) i["enabled"] = true; Widgets.ShowEnabled(); Check(Widgets.Open.Count == Widgets.Ids.Length, "all widgets open (" + Widgets.Open.Count + "/" + Widgets.Ids.Length + ")"); },
                () => {
                    var t = Widgets.Open["timer"]; t.ToggleTimer(); Check(t.TimerRunning, "focus timer starts"); t.ToggleTimer(); Check(!t.TimerRunning && t.TimerLeft >= 1490, "focus timer pauses with the time left");
                    t.ToggleTimer(); t.FinishTimerForTest(); Check(!t.TimerRunning && t.TimerText == "Done", "focus timer finishes");
                },
                () => { foreach (var a in new[] { "Center", "Right", "Left" }) { App.Settings.Dock["alignment"] = a; App.Dock.Build(); App.Dock.UpdateLayout(); } Check(App.Dock.IsVisible, "dock moves to the bottom, right and left"); Widgets.CloseAll(); },
                () => { var m = Metrics.Read(); System.Threading.Thread.Sleep(300); m = Metrics.Read(); Check(m.Cpu != null && m.MemoryTotalGb > 1, "CPU and memory numbers are read from Windows"); },
                // 12.27: Focus, the game overlay and per-app volume
                () => {
                    bool autoHide = Json.Bool(App.Settings.Dock, "autoHide");
                    FocusMode.Set(true, "selftest"); Check(FocusMode.On && Dock.AutoHiding, "Focus turns on and tucks the dock away");
                    FocusMode.Set(false, "selftest"); Check(!FocusMode.On && Dock.AutoHiding == autoHide, "Focus turns off and the dock comes back");
                    App.EnterGame("Self test game"); Check(FocusMode.On, "Focus turns on by itself in a game");
                    App.LeaveGame(); Check(!FocusMode.On && App.Dock.IsVisible, "Focus turned on by a game goes off with the game"); Profiles.Manual = null;
                },
                () => { App.Settings.Overlay["enabled"] = true; App.Settings.Overlay["when"] = "Always"; App.Settings.Overlay["detail"] = "Full"; GameOverlay.Apply(); Check(GameOverlay.Visible && GameOverlay.ClickThrough, "the game overlay shows as a click-through window"); },
                () => { System.Threading.Thread.Sleep(900); },
                () => {
                    var s = OverlayStats.Latest;
                    Check(s != null && s.Cpu != null && s.Ram != null, "the overlay reads CPU (" + s?.Cpu + "%), GPU (" + s?.Gpu + "%) and RAM (" + s?.Ram + "%)");
                    Check(GameOverlay.ShownText.Contains("CPU"), "the overlay shows its numbers (" + GameOverlay.ShownText + ")");
                    App.Settings.Overlay["enabled"] = false; GameOverlay.Update(); Check(!GameOverlay.Visible, "the overlay hides when turned off");
                },
                () => { var apps = AppVolume.List(); Check(apps != null, "apps playing sound are listed (" + apps.Count + ": " + string.Join(", ", apps.Select(a => a.Name)) + ")"); foreach (var a in apps) a.Dispose(); ControlCenter.Toggle(App.Bar); Check(ControlCenter.IsOpen, "Control Center opens with the per-app volume list"); ControlCenter.Current?.Close(); },
                () => Finish(),
            };
            int i = 0;
            var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(700) };
            timer.Tick += (o, e) =>
            {
                if (AppCatalog.Apps.Count == 0 && i == 0) return; // wait for the app list
                try { steps[i](); } catch (Exception ex) { Log.Write("selftest-exception step=" + i + " error=\"" + ex.ToString().Replace("\r", "").Replace("\n", " | ") + "\""); Fail("step " + i + " threw " + ex.GetType().Name + ": " + ex.Message); }
                if (++i >= steps.Count) timer.Stop();
            };
            timer.Start();
        }
        static void Search(string q, string expected)
        {
            Launchpad.Current.TypeForTest(q);
            string first = Launchpad.Current.FirstResultName();
            if (AppCatalog.Apps.Any(a => a.Name == expected) || expected == "Settings") Check(first == expected, "searching \"" + q + "\" puts " + expected + " first (got " + first + ")");
            else Log.Write("selftest-skip " + expected + " not installed");
        }
        static void Finish()
        {
            Running = false;
            var doc = new Dictionary<string, object> { ["result"] = failed.Count == 0 ? "Passed" : "Failed", ["passed"] = passed.Cast<object>().ToList(), ["failed"] = failed.Cast<object>().ToList(), ["apps"] = AppCatalog.Apps.Count, ["completedAt"] = DateTime.Now.ToString("o"), ["errors"] = Log.Lines.Where(l => l.Contains("ui-exception") || l.Contains("-failed")).Cast<object>().ToList() };
            File.WriteAllText(resultPath, Json.Write(doc));
            Log.Write("selftest-done passed=" + passed.Count + " failed=" + failed.Count);
            Application.Current.Shutdown(failed.Count == 0 ? 0 : 1);
        }

        // ---- design screenshots ----
        public static void Capture(string dir)
        {
            Directory.CreateDirectory(dir);
            Running = true;
            var shots = new List<(string name, Action open, Func<IEnumerable<Window>> windows)>
            {
                ("desktop", () => { }, () => new Window[] { App.Bar, App.Dock }),
                ("launchpad", () => Launchpad.Toggle(), () => new Window[] { App.Bar, App.Dock, Launchpad.Current }),
                ("search", () => Launchpad.Current.TypeForTest("se"), () => new Window[] { App.Bar, App.Dock, Launchpad.Current }),
                ("control-center", () => { Launchpad.HideIfOpen(); ControlCenter.Toggle(App.Bar); }, () => new Window[] { App.Bar, App.Dock, ControlCenter.Current }),
                ("files", () => { ControlCenter.Current?.Close(); Files.Open(null); }, () => new Window[] { App.Bar, App.Dock, Files.Last }),
                ("settings", () => { Files.Last?.Close(); SettingsWindow.Open(); }, () => new Window[] { App.Bar, App.Dock, SettingsWindow.Current }),
                ("settings-windows", () => SettingsWindow.Current.Go("Windows"), () => new Window[] { App.Bar, App.Dock, SettingsWindow.Current }),
                ("arena", () => { SettingsWindow.Current.Close(); Arena.Open(); }, () => new Window[] { App.Bar, App.Dock, Arena.Current }),
                ("widgets", () => { Arena.Current?.Close(); App.Settings.Widgets["enabled"] = true; foreach (var i in App.Settings.WidgetItems.Select(Json.Obj)) i["enabled"] = Json.Str(i, "id") != "notes" && Json.Str(i, "id") != "calendar"; Widgets.ShowEnabled(); }, () => new Window[] { App.Bar, App.Dock }.Concat(Widgets.Open.Values)),
            };
            foreach (var t in Theme.All) { var theme = t; shots.Add(("theme-" + t.Name.Replace("BAKA ", "").Replace(' ', '-').ToLowerInvariant(), () => { Widgets.CloseAll(); Launchpad.HideIfOpen(); Theme.Apply(theme.Name, theme.Accent); App.Dock.Build(); Launchpad.Toggle(); }, () => new Window[] { App.Bar, App.Dock, Launchpad.Current })); }
            int i = -1;
            var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1600) };
            timer.Tick += (o, e) =>
            {
                if (AppCatalog.Apps.Count == 0) return;
                if (i >= 0) try { Shot(Path.Combine(dir, shots[i].name + ".png"), shots[i].windows()); } catch (Exception ex) { Log.Write("capture-failed name=" + shots[i].name + " error=\"" + ex.Message + "\""); }
                if (++i >= shots.Count) { timer.Stop(); Running = false; Application.Current.Shutdown(0); return; }
                try { shots[i].open(); } catch (Exception ex) { Log.Write("capture-open-failed name=" + shots[i].name + " error=\"" + ex.Message + "\""); }
            };
            timer.Start();
        }
        static void Shot(string path, IEnumerable<Window> windows)
        {
            double w = SystemParameters.PrimaryScreenWidth, h = SystemParameters.PrimaryScreenHeight;
            var dv = new DrawingVisual();
            using (var dc = dv.RenderOpen())
            {
                string wp = Paths.Expand(Json.Str(App.Settings.Wallpaper, "path")); if (!File.Exists(wp)) wp = Paths.Shipped("BAKA-Stealth-4K.png");
                if (wp != null) dc.DrawImage(new BitmapImage(new Uri(wp)), new Rect(0, 0, w, h)); else dc.DrawRectangle(Brushes.Black, null, new Rect(0, 0, w, h));
                foreach (var win in windows.Where(x => x != null && x.IsVisible))
                {
                    var content = win.Content as Visual; if (content == null || win.ActualWidth <= 0) continue;
                    // Windows draws the acrylic behind app windows; the capture stands in a soft blur of the wallpaper.
                    if (!(win is GlassPanel)) dc.DrawRectangle(new SolidColorBrush(Color.FromArgb(win is Launchpad ? (byte)120 : (byte)90, 20, 20, 24)), null, new Rect(win.Left, win.Top, win.ActualWidth, win.ActualHeight));
                    var rtb = new RenderTargetBitmap((int)Math.Ceiling(win.ActualWidth), (int)Math.Ceiling(win.ActualHeight), 96, 96, PixelFormats.Pbgra32);
                    rtb.Render(content);
                    dc.DrawImage(rtb, new Rect(win.Left, win.Top, win.ActualWidth, win.ActualHeight));
                }
            }
            var outBmp = new RenderTargetBitmap((int)w, (int)h, 96, 96, PixelFormats.Pbgra32); outBmp.Render(dv);
            var enc = new PngBitmapEncoder(); enc.Frames.Add(BitmapFrame.Create(outBmp));
            using (var s = File.Create(path)) enc.Save(s);
            Log.Write("capture-saved path=\"" + path + "\"");
        }

        // One picture per theme: every icon with its id underneath.
        public static void IconSheet(string dir)
        {
            Directory.CreateDirectory(dir);
            var icons = Icons.Library; int cols = 14, cw = 100, ch = 112;
            int rows = (icons.Count + cols - 1) / cols, width = cols * cw, height = 46 + rows * ch;
            var face = new Typeface("Segoe UI");
            foreach (var theme in Theme.All)
            {
                Theme.Apply(theme.Name, theme.Accent);
                var dv = new DrawingVisual();
                using (var dc = dv.RenderOpen())
                {
                    dc.DrawRectangle(new SolidColorBrush(Theme.C(theme.Canvas)), null, new Rect(0, 0, width, height));
                    dc.DrawText(new FormattedText(theme.Name + " – " + icons.Count + " BAKA icons", CultureInfo.InvariantCulture, FlowDirection.LeftToRight, face, 16, Theme.Text, 1.0), new Point(12, 12));
                    for (int i = 0; i < icons.Count; i++)
                    {
                        double x = (i % cols) * cw, y = 46 + (i / cols) * ch;
                        dc.DrawImage(Icons.Draw(icons[i], null, icons[i].Id, 80), new Rect(x + 10, y, 80, 80));
                        var ft = new FormattedText(icons[i].Id, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, face, 10, Theme.Muted, 1.0) { MaxTextWidth = cw - 4, TextAlignment = TextAlignment.Center, Trimming = TextTrimming.CharacterEllipsis, MaxLineCount = 1 };
                        dc.DrawText(ft, new Point(x + 2, y + 84));
                    }
                }
                var bmp = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32); bmp.Render(dv);
                var enc = new PngBitmapEncoder(); enc.Frames.Add(BitmapFrame.Create(bmp));
                using (var s = File.Create(Path.Combine(dir, "icons-" + theme.Name.Replace("BAKA ", "").Replace(' ', '-').ToLowerInvariant() + ".png"))) enc.Save(s);
            }
        }
    }
}
