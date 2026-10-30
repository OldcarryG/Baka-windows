using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;

namespace Baka.Desktop
{
    // NVIDIA's own sensor library (nvml.dll, part of every NVIDIA driver): GPU load, temperature, video
    // memory, power and clock, readable by a normal user. Other GPUs give BAKA load only (PDH).
    static class Nvml
    {
        [StructLayout(LayoutKind.Sequential)] struct Utilization { public uint Gpu, Memory; }
        [StructLayout(LayoutKind.Sequential)] struct Memory { public ulong Total, Free, Used; }
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr LoadLibrary(string path);
        [DllImport("nvml.dll", EntryPoint = "nvmlInit_v2")] static extern int Init();
        [DllImport("nvml.dll", EntryPoint = "nvmlDeviceGetHandleByIndex_v2")] static extern int Handle(uint index, out IntPtr device);
        [DllImport("nvml.dll", EntryPoint = "nvmlDeviceGetName", CharSet = CharSet.Ansi)] static extern int Name(IntPtr device, StringBuilder name, uint length);
        [DllImport("nvml.dll", EntryPoint = "nvmlDeviceGetUtilizationRates")] static extern int Load(IntPtr device, out Utilization u);
        [DllImport("nvml.dll", EntryPoint = "nvmlDeviceGetTemperature")] static extern int Temperature(IntPtr device, int sensor, out uint celsius);
        [DllImport("nvml.dll", EntryPoint = "nvmlDeviceGetMemoryInfo")] static extern int Vram(IntPtr device, out Memory m);
        [DllImport("nvml.dll", EntryPoint = "nvmlDeviceGetPowerUsage")] static extern int Power(IntPtr device, out uint milliwatts);
        [DllImport("nvml.dll", EntryPoint = "nvmlDeviceGetClockInfo")] static extern int Clock(IntPtr device, int type, out uint mhz);

        static bool tried, ok; static IntPtr device;
        public static string GpuName { get; private set; } = "";
        public static bool Available { get { Start(); return ok; } }
        static readonly object gate = new object();
        static void Start()
        {
            lock (gate)
            {
                if (tried) return; tried = true;
                try
                {
                    // only from the driver's own places, never from the current folder
                    string sys = Path.Combine(Environment.SystemDirectory, "nvml.dll"), smi = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "NVIDIA Corporation", "NVSMI", "nvml.dll");
                    if ((!File.Exists(sys) || LoadLibrary(sys) == IntPtr.Zero) && (!File.Exists(smi) || LoadLibrary(smi) == IntPtr.Zero)) return;
                    if (Init() != 0 || Handle(0, out device) != 0) return;
                    var sb = new StringBuilder(96); if (Name(device, sb, 96) == 0) GpuName = sb.ToString();
                    ok = true;
                    Log.Write("nvml-ready gpu=\"" + GpuName + "\"");
                }
                catch (Exception e) { ok = false; Log.Write("nvml-unavailable error=\"" + e.Message + "\""); }
            }
        }
        public static void Read(OverlaySnapshot s)
        {
            if (!Available) return;
            try
            {
                if (Load(device, out var u) == 0) s.Gpu = (int)u.Gpu;
                if (Temperature(device, 0, out uint t) == 0) s.GpuTemp = (int)t;
                if (Vram(device, out var m) == 0 && m.Total > 0) { s.VramUsedGb = m.Used / 1073741824.0; s.VramTotalGb = m.Total / 1073741824.0; }
                if (Power(device, out uint mw) == 0) s.GpuWatts = mw / 1000.0;
                if (Clock(device, 0 /*graphics*/, out uint mhz) == 0) s.GpuMhz = (int)mhz;
            }
            catch { }
        }
    }

    sealed class OverlaySnapshot
    {
        public double? Fps, Low1, FrameMs, VramUsedGb, VramTotalGb, GpuWatts;
        public int? Cpu, Ram, Gpu, GpuTemp, GpuMhz;
        public IntPtr Window; public uint Pid;
    }

    // Reads the overlay's numbers once a second on a thread pool thread, so the UI thread (lowered in
    // priority during games) only copies them into the window.
    static class OverlayStats
    {
        static System.Threading.Timer timer;
        public static volatile OverlaySnapshot Latest;
        static long lastIdle, lastKernel, lastUser;
        static readonly GpuCounter pdh = new GpuCounter();
        static IntPtr lastTarget; static int busy;
        static readonly uint me = (uint)Process.GetCurrentProcess().Id;

        public static void Start()
        {
            if (timer != null) return;
            Native.GetSystemTimes(out lastIdle, out lastKernel, out lastUser); // the first reading has a baseline
            timer = new System.Threading.Timer(_ => Sample(), null, 500, 1000);
        }
        public static void Stop() { timer?.Dispose(); timer = null; Latest = null; }

        static void Sample()
        {
            if (Interlocked.Exchange(ref busy, 1) == 1) return;
            try
            {
                var s = new OverlaySnapshot();
                if (Native.GetSystemTimes(out long idle, out long kernel, out long user))
                {
                    long di = idle - lastIdle, dt = (kernel - lastKernel) + (user - lastUser);
                    if (dt > 0) s.Cpu = (int)Math.Round(Math.Max(0, Math.Min(100, 100.0 * (dt - di) / dt)));
                    lastIdle = idle; lastKernel = kernel; lastUser = user;
                }
                var mem = new Native.MEMORYSTATUSEX { dwLength = (uint)Marshal.SizeOf(typeof(Native.MEMORYSTATUSEX)) };
                if (Native.GlobalMemoryStatusEx(ref mem)) s.Ram = (int)mem.dwMemoryLoad;
                Nvml.Read(s);
                if (s.Gpu == null) s.Gpu = pdh.Read();
                // the game BAKA detected, else the app in front (BAKA's own windows keep the previous one)
                IntPtr w = App.GameRunning && App.GameWindow != IntPtr.Zero && Native.IsWindow(App.GameWindow) ? App.GameWindow : Native.GetForegroundWindow();
                Native.GetWindowThreadProcessId(w, out uint pid);
                if (w == IntPtr.Zero || pid == 0 || pid == me) { w = lastTarget; Native.GetWindowThreadProcessId(w, out pid); }
                if (w != IntPtr.Zero && !Native.IsWindow(w)) { w = IntPtr.Zero; pid = 0; }
                lastTarget = w; s.Window = w; s.Pid = pid;
                if (pid != 0 && Fps.State == Fps.Status.Running)
                {
                    var r = Frames(pid);
                    if (r.Has) { s.Fps = r.Fps; s.FrameMs = r.FrameMs; if (r.Low1 > 0) s.Low1 = r.Low1; }
                }
                Latest = s;
            }
            catch (Exception e) { Log.Write("overlay-sample-failed error=\"" + e.Message + "\""); }
            finally { Interlocked.Exchange(ref busy, 0); }
        }

        // The app's own frames; browsers and Electron apps (Baka Browser, Discord) draw in a child GPU process,
        // so when the app itself shows nothing, its busiest child process counts.
        static Dictionary<uint, (uint parent, string exe)> tree; static DateTime treeAt;
        static Fps.Reading Frames(uint pid)
        {
            var r = Fps.Sample(pid);
            if (r.Has && r.Fps > 0) return r;
            var active = Fps.ActiveProcesses().Where(p => p != pid).ToList();
            if (active.Count == 0) return r;
            if (tree == null || (DateTime.Now - treeAt).TotalSeconds > 3) { tree = Native.Processes(); treeAt = DateTime.Now; }
            Fps.Reading best = r;
            foreach (var p in active)
            {
                if (!Descends(p, pid)) continue;
                var c = Fps.Sample(p);
                if (c.Has && c.Fps > best.Fps) best = c;
            }
            return best;
        }
        static bool Descends(uint child, uint ancestor)
        {
            for (int i = 0; i < 6 && tree.TryGetValue(child, out var e); i++) { if (e.parent == ancestor) return true; if (e.parent == child || e.parent == 0) return false; child = e.parent; }
            return false;
        }
    }

    // The overlay: a small see-through strip in a corner of the game's screen. Clicks go through it to the
    // game, it never takes the keyboard, and it is not a window of the game (nothing is injected).
    // It shows over borderless and windowed games; a game in exclusive fullscreen is drawn above every window.
    sealed class OverlayWindow : GlassPanel
    {
        readonly StackPanel row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(10, 5, 12, 6) };
        readonly Dictionary<string, TextBlock> values = new Dictionary<string, TextBlock>();
        public OverlayWindow() : base(9)
        {
            Title = "BAKA Game Overlay"; ShowActivated = false; Topmost = true; SizeToContent = SizeToContent.WidthAndHeight; Focusable = false; IsHitTestVisible = false;
            TextOptions.SetTextFormattingMode(this, TextFormattingMode.Display);
            Content = row;
            SourceInitialized += (o, e) => Native.SetWindowLongPtr(Handle, Native.GWL_EXSTYLE, new IntPtr(Native.ExStyle(Handle) | 0x20 /*TRANSPARENT: clicks go through*/ | Native.WS_EX_NOACTIVATE | Native.WS_EX_TOOLWINDOW));
            SizeChanged += (o, e) => GameOverlay.Place();
        }
        // A fixed dark strip that reads over any game, whatever the BAKA theme.
        public override void Paint()
        {
            Frame.Background = new SolidColorBrush(Color.FromArgb(184, 8, 9, 12));
            Frame.BorderBrush = new SolidColorBrush(Color.FromArgb(38, 255, 255, 255)); Frame.BorderThickness = new Thickness(1);
        }
        public bool ClickThrough => Handle != IntPtr.Zero && (Native.ExStyle(Handle) & 0x20) != 0 && (Native.ExStyle(Handle) & Native.WS_EX_NOACTIVATE) != 0;

        static readonly Brush Label = Frozen(Color.FromRgb(0x9C, 0xA3, 0xAF)), Value = Frozen(Colors.White), FpsBrush = Frozen(Color.FromRgb(0x22, 0xD3, 0xEE));
        static Brush Frozen(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }
        string built;
        public void Build(string detail)
        {
            if (built == detail) return;
            built = detail; row.Children.Clear(); values.Clear();
            Cell("fps", "FPS", 12, true);
            if (detail == "Full") { Cell("low", "1% LOW"); Cell("ms", "MS"); }
            if (detail != "FPS") { Cell("cpu", "CPU"); Cell("gpu", "GPU"); Cell("temp", "", 6); }
            if (detail == "Full") { Cell("watts", "", 6); Cell("vram", "VRAM"); Cell("ram", "RAM"); }
        }
        // temperature and power follow the GPU load as plain values ("4% GPU 38°C 26 W"), closer to it
        void Cell(string id, string label, double gap = 12, bool big = false)
        {
            var sp = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(row.Children.Count == 0 ? 0 : gap, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
            var v = new TextBlock { Text = "—", FontFamily = Ui.Display, FontSize = big ? 17 : 13.5, FontWeight = FontWeights.SemiBold, Foreground = big ? FpsBrush : Value, VerticalAlignment = VerticalAlignment.Center, MinWidth = big ? 30 : 0, TextAlignment = TextAlignment.Right };
            sp.Children.Add(v);
            if (label.Length > 0) sp.Children.Add(new TextBlock { Text = label, FontFamily = Ui.Font, FontSize = 10, FontWeight = FontWeights.SemiBold, Foreground = Label, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(5, big ? 2 : 1, 0, 0) });
            row.Children.Add(sp); values[id] = v;
        }
        public void Set(OverlaySnapshot s)
        {
            Put("fps", s.Fps == null ? "—" : Math.Round(s.Fps.Value).ToString("0"));
            Put("low", s.Low1 == null ? "—" : Math.Round(s.Low1.Value).ToString("0"));
            Put("ms", s.FrameMs == null || s.Fps == null || s.Fps < 1 ? "—" : s.FrameMs.Value.ToString(s.FrameMs < 10 ? "0.0" : "0"));
            Put("cpu", s.Cpu == null ? "—" : s.Cpu + "%");
            Put("gpu", s.Gpu == null ? "—" : s.Gpu + "%");
            Put("temp", s.GpuTemp == null ? "—°C" : s.GpuTemp + "°C");
            Put("vram", s.VramUsedGb == null ? "—" : s.VramUsedGb.Value.ToString("0.0") + "/" + s.VramTotalGb.Value.ToString("0") + "G");
            Put("watts", s.GpuWatts == null ? "— W" : Math.Round(s.GpuWatts.Value).ToString("0") + " W");
            Put("ram", s.Ram == null ? "—" : s.Ram + "%");
        }
        void Put(string id, string text) { if (values.TryGetValue(id, out var t) && t.Text != text) t.Text = text; }
        public string Text => string.Join(" ", row.Children.OfType<StackPanel>().Select(sp => string.Join(" ", sp.Children.OfType<TextBlock>().Select(t => t.Text))));
    }

    // Settings: overlay.enabled, overlay.when ("Games" | "Always"), overlay.position (TopLeft, TopRight,
    // BottomLeft, BottomRight), overlay.detail ("FPS" | "Standard" | "Full"). Ctrl+Alt+F shows / hides it,
    // also in a game (a registered hotkey: Windows tells BAKA about that one combination only).
    static class GameOverlay
    {
        static OverlayWindow win;
        static DispatcherTimer tick;
        static Dictionary<string, object> S => App.Settings.Overlay;
        public static bool Enabled => App.Settings != null && Json.Bool(S, "enabled");
        public static string When => Json.Str(S, "when", "Games") == "Always" ? "Always" : "Games";
        public static string Position => Json.Str(S, "position", "TopLeft");
        public static string Detail { get { string d = Json.Str(S, "detail", "Standard"); return d == "FPS" || d == "Full" ? d : "Standard"; } }
        public static bool Visible => win != null && win.IsVisible;
        public static bool ClickThrough => win != null && win.ClickThrough;
        public static string ShownText => win?.Text ?? "";

        public static void Update()
        {
            try
            {
                bool want = Enabled && (When == "Always" || App.GameRunning);
                if (want) ShowNow(); else HideNow();
            }
            catch (Exception e) { Log.Write("overlay-failed error=\"" + e.Message + "\""); }
        }
        public static void SetEnabled(bool on, string reason)
        {
            if (App.Settings == null) return;
            S["enabled"] = on; App.Settings.Save();
            if (on) Fps.Retry();
            Log.Write("overlay " + (on ? "on" : "off") + " reason=" + reason);
            Update();
        }
        public static void ToggleFromKey()
        {
            SetEnabled(!Enabled, "key");
            Osd.Show(0xEC4A, !Enabled ? "Game overlay off" : !Visible ? "Game overlay on  ·  shows in games" : "Game overlay on");
        }
        // a setting changed (position, detail, when)
        public static void Apply() { if (win != null) win.Build(Detail); Update(); Place(); }

        static void ShowNow()
        {
            if (win == null) win = new OverlayWindow();
            win.Build(Detail);
            OverlayStats.Start();
            Fps.Start();
            if (!win.IsVisible) { win.Show(); Log.Write("overlay-shown detail=" + Detail + " fps=" + Fps.State); }
            if (tick == null) { tick = new DispatcherTimer(DispatcherPriority.Normal) { Interval = TimeSpan.FromSeconds(1) }; tick.Tick += (o, e) => Refresh(); }
            tick.Start();
            Refresh();
        }
        static void HideNow()
        {
            tick?.Stop();
            OverlayStats.Stop();
            Fps.Stop();
            if (win != null && win.IsVisible) { win.Hide(); Log.Write("overlay-hidden"); }
        }
        public static void Close() { HideNow(); try { win?.Close(); } catch { } win = null; }

        static void Refresh()
        {
            if (win == null || !win.IsVisible) return;
            var s = OverlayStats.Latest;
            if (s != null) win.Set(s);
            Place();
            KeepOnTop(s?.Window ?? IntPtr.Zero);
        }

        // In the chosen corner of the game's screen (the app in front's, outside games), 14 px in. Outside a
        // game the work area is used, so the menu bar and dock are not covered.
        public static void Place()
        {
            if (win == null || win.Handle == IntPtr.Zero || win.ActualWidth <= 0) return;
            IntPtr target = OverlayStats.Latest?.Window ?? IntPtr.Zero;
            Native.RECT r;
            if (target != IntPtr.Zero) r = Native.MonitorRect(target, !App.GameRunning);
            else { var wa = System.Windows.Forms.Screen.PrimaryScreen.WorkingArea; r = new Native.RECT { Left = wa.Left, Top = wa.Top, Right = wa.Right, Bottom = wa.Bottom }; }
            double s = Ui.Scale(win), m = 14;
            double left = r.Left / s, top = r.Top / s, right = r.Right / s, bottom = r.Bottom / s;
            // the menu bar is not part of the work area when it auto-hides: keep clear of it outside games
            if (!App.GameRunning && Position.StartsWith("Top") && App.Bar != null && App.Bar.IsVisible && r.Top == System.Windows.Forms.Screen.PrimaryScreen.Bounds.Top) top = Math.Max(top, TopBar.BarHeight);
            double x = Position.EndsWith("Right") ? right - win.ActualWidth - m : left + m;
            double y = Position.StartsWith("Bottom") ? bottom - win.ActualHeight - m : top + m;
            if (Math.Abs(win.Left - x) > 0.5) win.Left = x;
            if (Math.Abs(win.Top - y) > 0.5) win.Top = y;
        }
        // Topmost games (many borderless ones are) can sit above BAKA's topmost window: put the overlay back
        // on top, without taking the keyboard from the game.
        static void KeepOnTop(IntPtr target)
        {
            IntPtr h = win.Handle;
            if (h == IntPtr.Zero) return;
            Native.SetWindowPos(h, Native.HWND_TOPMOST, 0, 0, 0, 0, Native.SWP_NOMOVE | Native.SWP_NOSIZE | Native.SWP_NOACTIVATE);
            if (target == IntPtr.Zero) return;
            for (IntPtr above = Native.GetWindow(target, 3 /*GW_HWNDPREV*/); above != IntPtr.Zero; above = Native.GetWindow(above, 3)) if (above == h) return;
            IntPtr justAbove = Native.GetWindow(target, 3);
            Native.SetWindowPos(h, justAbove == IntPtr.Zero ? Native.HWND_TOPMOST : justAbove, 0, 0, 0, 0, Native.SWP_NOMOVE | Native.SWP_NOSIZE | Native.SWP_NOACTIVATE);
        }

        // --overlay-test <result.json>: shows the overlay for a few seconds with live numbers (throw-away
        // settings), lists the apps playing sound, and writes what it saw. Runs as the normal user.
        public static int Test(string path)
        {
            Paths.Init(true);
            var result = new Dictionary<string, object> { ["startedAt"] = DateTime.Now.ToString("o") };
            var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            App.Settings = Settings.Load();
            Theme.Load(); Theme.Apply(Json.Str(App.Settings.Appearance, "theme"), Json.Str(App.Settings.Appearance, "accentColor")); Styles.Install(app);
            try { AppCatalog.Refresh(true); } catch { } // app names for the sound list, as the desktop has them
            S["enabled"] = true; S["when"] = "Always"; S["detail"] = "Full"; S["position"] = "TopRight";
            app.Dispatcher.BeginInvoke(new Action(() =>
            {
                Update();
                int n = 0;
                var t = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
                t.Tick += (o, e) =>
                {
                    if (++n < 5) return;
                    t.Stop();
                    try
                    {
                        var s = OverlayStats.Latest;
                        result["visible"] = Visible; result["clickThrough"] = ClickThrough;
                        result["topmost"] = win != null && (Native.ExStyle(win.Handle) & 8) != 0;
                        if (win != null && Native.GetWindowRect(win.Handle, out var wr)) result["rect"] = wr.Left + "," + wr.Top + "-" + wr.Right + "," + wr.Bottom;
                        result["text"] = ShownText;
                        result["fpsState"] = Fps.State.ToString(); result["fpsError"] = Fps.Error;
                        result["nvml"] = Nvml.Available; result["gpuName"] = Nvml.GpuName;
                        if (s != null) { result["cpu"] = s.Cpu; result["ram"] = s.Ram; result["gpu"] = s.Gpu; result["gpuTemp"] = s.GpuTemp; result["vramGb"] = s.VramUsedGb == null ? null : (object)Math.Round(s.VramUsedGb.Value, 2); result["gpuWatts"] = s.GpuWatts == null ? null : (object)Math.Round(s.GpuWatts.Value, 1); result["gpuMhz"] = s.GpuMhz; result["targetPid"] = (long)s.Pid; }
                        result["fpsAccessInToken"] = FpsAccess.InToken; result["fpsAccessGranted"] = FpsAccess.Granted;
                        var sound = new List<object>();
                        result["masterVolume"] = Audio.Level; // the master volume's own device enumerator first, as in Control Center
                        foreach (var a in AppVolume.List())
                        {
                            sound.Add(new Dictionary<string, object> { ["name"] = a.Name, ["exe"] = Path.GetFileName(a.Exe ?? ""), ["system"] = a.System, ["active"] = a.Active, ["sessions"] = a.Sessions, ["volume"] = Math.Round(a.Level * 100), ["muted"] = a.Muted, ["peak"] = Math.Round(a.Peak, 3) });
                            a.Dispose();
                        }
                        result["audioApps"] = sound;
                    }
                    catch (Exception ex) { result["exception"] = ex.ToString(); }
                    Close();
                    try { File.WriteAllText(path, Json.Write(result)); } catch { }
                    app.Shutdown(0);
                };
                t.Start();
            }));
            app.Run();
            return 0;
        }
    }
}
