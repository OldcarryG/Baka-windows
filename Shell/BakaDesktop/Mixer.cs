using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;

namespace Baka.Desktop
{
    // One app's sound on the default output device: Windows keeps an audio session per stream, so an app
    // with several (a browser) is one row here and its slider sets them all, like Windows' volume mixer.
    sealed class AudioApp : IDisposable
    {
        public string Key = "", Name = "", Exe = "", AppId = "";
        public bool System, Active;
        public int Sessions => volumes.Count;
        internal readonly List<AppVolume.ISimpleAudioVolume> volumes = new List<AppVolume.ISimpleAudioVolume>();
        internal readonly List<AppVolume.IAudioMeterInformation> meters = new List<AppVolume.IAudioMeterInformation>();
        internal readonly List<object> com = new List<object>();
        static Guid none = Guid.Empty;

        public float Level { get { try { return volumes.Count > 0 && volumes[0].GetMasterVolume(out float v) == 0 ? v : 0; } catch { return 0; } } }
        public bool Muted { get { try { return volumes.Count > 0 && volumes[0].GetMute(out bool m) == 0 && m; } catch { return false; } } }
        public float Peak
        {
            get
            {
                float max = 0;
                foreach (var m in meters) { try { if (m.GetPeakValue(out float p) == 0 && p > max) max = p; } catch { } }
                return max;
            }
        }
        public void SetLevel(float level)
        {
            level = Math.Max(0, Math.Min(1, level));
            foreach (var v in volumes) { try { v.SetMasterVolume(level, ref none); if (level > 0) v.SetMute(false, ref none); } catch { } }
        }
        public void SetMuted(bool mute) { foreach (var v in volumes) { try { v.SetMute(mute, ref none); } catch { } } }
        // No Marshal.ReleaseComObject: .NET hands out one wrapper per COM object, so a session listed again
        // (every 1.5 s) is the same wrapper the visible row still uses; releasing it broke that row. The
        // garbage collector releases them once nothing uses them.
        public void Dispose() { com.Clear(); volumes.Clear(); meters.Clear(); }
    }

    // Per-app volume (Core Audio sessions), read and set the documented way.
    static class AppVolume
    {
        // Created by CLSID, not through a [ComImport] class: the Audio class (master volume) has its own, and .NET
        // gives back the wrapper it already has for the device enumerator, typed as that other class ("Unable
        // to cast MMDeviceEnumerator to MMDeviceEnumerator", seen live). The interface cast works on either.
        static readonly Type EnumeratorType = Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"));
        [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IMMDeviceEnumerator { int NotImpl1(); [PreserveSig] int GetDefaultAudioEndpoint(int flow, int role, out IMMDevice device); }
        [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IMMDevice { [PreserveSig] int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); }
        [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IAudioSessionManager2
        {
            [PreserveSig] int GetAudioSessionControl(IntPtr groupingParam, int flags, out IntPtr control);
            [PreserveSig] int GetSimpleAudioVolume(IntPtr groupingParam, int flags, out IntPtr volume);
            [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator sessions);
        }
        [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IAudioSessionEnumerator { [PreserveSig] int GetCount(out int count); [PreserveSig] int GetSession(int index, out IAudioSessionControl2 session); }
        [ComImport, Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        internal interface IAudioSessionControl2
        {
            // IAudioSessionControl
            [PreserveSig] int GetState(out int state);
            [PreserveSig] int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string name);
            [PreserveSig] int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string name, ref Guid context);
            [PreserveSig] int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string path);
            [PreserveSig] int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string path, ref Guid context);
            [PreserveSig] int GetGroupingParam(out Guid param);
            [PreserveSig] int SetGroupingParam(ref Guid param, ref Guid context);
            [PreserveSig] int RegisterAudioSessionNotification(IntPtr client);
            [PreserveSig] int UnregisterAudioSessionNotification(IntPtr client);
            // IAudioSessionControl2
            [PreserveSig] int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
            [PreserveSig] int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
            [PreserveSig] int GetProcessId(out uint pid);
            [PreserveSig] int IsSystemSoundsSession();
            [PreserveSig] int SetDuckingPreference([MarshalAs(UnmanagedType.Bool)] bool optOut);
        }
        [ComImport, Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        internal interface ISimpleAudioVolume
        {
            [PreserveSig] int SetMasterVolume(float level, ref Guid context);
            [PreserveSig] int GetMasterVolume(out float level);
            [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid context);
            [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
        }
        [ComImport, Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        internal interface IAudioMeterInformation { [PreserveSig] int GetPeakValue(out float peak); }

        // Helper processes that play sound for the app that started them (WebView2 apps such as Baka Browser).
        static readonly HashSet<string> Helpers = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "msedgewebview2.exe" };
        static readonly Dictionary<string, (string name, string appId)> names = new Dictionary<string, (string, string)>(StringComparer.OrdinalIgnoreCase);
        static bool loggedFailure; // the panel lists every 1.5 s: one log line, not forty

        // Apps with sound on the default output (expired sessions left out): playing ones first, then by name,
        // Windows' system sounds last.
        public static List<AudioApp> List()
        {
            var apps = new Dictionary<string, AudioApp>(StringComparer.OrdinalIgnoreCase);
            Dictionary<uint, (uint parent, string exe)> tree = null;
            try
            {
                var en = (IMMDeviceEnumerator)Activator.CreateInstance(EnumeratorType);
                if (en.GetDefaultAudioEndpoint(0 /*render*/, 1 /*multimedia*/, out IMMDevice dev) != 0 || dev == null) return new List<AudioApp>();
                var iid = typeof(IAudioSessionManager2).GUID;
                if (dev.Activate(ref iid, 23 /*CLSCTX_ALL*/, IntPtr.Zero, out object o) != 0 || !(o is IAudioSessionManager2 mgr)) return new List<AudioApp>();
                if (mgr.GetSessionEnumerator(out var list) != 0 || list == null) return new List<AudioApp>();
                list.GetCount(out int count);
                for (int i = 0; i < count; i++)
                {
                    IAudioSessionControl2 s = null;
                    try
                    {
                        if (list.GetSession(i, out s) != 0 || s == null) continue;
                        if (s.GetState(out int state) != 0 || state == 2 /*expired*/) continue;
                        bool system = s.IsSystemSoundsSession() == 0;
                        s.GetProcessId(out uint pid);
                        if (!system && pid == 0) continue;
                        string exe = system ? "" : Native.ProcessPath(pid) ?? "";
                        if (!system && exe.Length == 0) continue; // the app is gone
                        uint owner = pid;
                        if (!system && Helpers.Contains(Path.GetFileName(exe)))
                        {
                            if (tree == null) tree = Native.Processes();
                            for (int up = 0; up < 6 && tree.TryGetValue(owner, out var e) && e.parent != 0 && Helpers.Contains(e.exe); up++) owner = e.parent;
                            string host = Native.ProcessPath(owner);
                            if (!string.IsNullOrEmpty(host) && !Helpers.Contains(Path.GetFileName(host))) exe = host; else owner = pid;
                        }
                        string key = system ? "system" : exe;
                        if (!apps.TryGetValue(key, out var app))
                        {
                            app = new AudioApp { Key = key, Exe = exe, System = system };
                            if (system) app.Name = "System sounds";
                            else { var n = NameOf(exe, owner, s); app.Name = n.name; app.AppId = n.appId; }
                            apps[key] = app;
                        }
                        if (!(s is ISimpleAudioVolume v)) continue;
                        if (state == 1) app.Active = true;
                        app.volumes.Add(v); app.com.Add(s);
                        if (s is IAudioMeterInformation m) app.meters.Add(m);
                    }
                    catch { }
                }
            }
            catch (Exception e) { if (!loggedFailure) { loggedFailure = true; Log.Write("mixer-list-failed error=\"" + e.Message + "\""); } }
            return apps.Values.Where(a => a.Sessions > 0).OrderBy(a => a.System).ThenByDescending(a => a.Active).ThenBy(a => a.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
        }

        // The name the dock and Launchpad use for the program: its Start-menu entry, else its description.
        static (string name, string appId) NameOf(string exe, uint pid, IAudioSessionControl2 s)
        {
            if (names.TryGetValue(exe, out var known)) return known;
            string appId = Native.ProcessAppId(pid) ?? "", name = null;
            try
            {
                var file = Path.GetFileName(exe);
                if (file.Equals("BakaDesktop.exe", StringComparison.OrdinalIgnoreCase)) return names[exe] = ("BAKA video wallpaper", "");
                var hit = appId.Length > 0 ? AppCatalog.Apps.FirstOrDefault(a => string.Equals(a.AppId, appId, StringComparison.OrdinalIgnoreCase)) : null;
                name = hit?.Name;
                if (string.IsNullOrEmpty(name)) ByProgram().TryGetValue(file, out name);
                if (string.IsNullOrEmpty(name)) { try { name = System.Diagnostics.FileVersionInfo.GetVersionInfo(exe).FileDescription?.Trim(); } catch { } }
                if (string.IsNullOrEmpty(name) && s.GetDisplayName(out string dn) == 0 && !string.IsNullOrWhiteSpace(dn) && !dn.StartsWith("@")) name = dn;
                if (string.IsNullOrEmpty(name)) name = Path.GetFileNameWithoutExtension(exe);
            }
            catch { name = Path.GetFileNameWithoutExtension(exe); }
            return names[exe] = (name, appId);
        }
        // Start-menu names by the program file they start ("baka.exe" -> "Baka Browser"). Shortcuts are read
        // once per app list load, so the panel is not slowed by it afterwards.
        static Dictionary<string, string> byProgram; static DateTime byProgramFor;
        static Dictionary<string, string> ByProgram()
        {
            if (byProgram != null && byProgramFor == AppCatalog.Loaded) return byProgram;
            var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var a in AppCatalog.Apps)
            {
                try
                {
                    string path = !string.IsNullOrEmpty(a.Exe) ? a.Exe : a.Target ?? "";
                    if (path.EndsWith(".lnk", StringComparison.OrdinalIgnoreCase)) path = AppCatalog.ShortcutTarget(path) ?? "";
                    if (!path.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) continue;
                    string f = Path.GetFileName(path);
                    if (!map.ContainsKey(f)) map[f] = a.Name;
                }
                catch { }
            }
            byProgramFor = AppCatalog.Loaded;
            return byProgram = map;
        }
    }

    // The "Apps" part of Control Center's Sound section: one row per app with its icon, name, a volume slider,
    // a mute button and a thin level meter under the slider that moves with what the app plays.
    sealed class MixerPanel : IDisposable
    {
        public readonly StackPanel Root = new StackPanel();
        readonly StackPanel rows = new StackPanel();
        readonly DispatcherTimer timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(100) };
        List<AudioApp> apps = new List<AudioApp>();
        readonly List<(AudioApp app, Slider slider, ScaleTransform meter, Button mute)> shown = new List<(AudioApp, Slider, ScaleTransform, Button)>();
        string signature = "";
        int ticks;
        bool disposed;
        const int MaxRows = 6;

        public MixerPanel()
        {
            Root.Children.Add(rows);
            Refresh(true);
            timer.Tick += (o, e) => Tick();
            timer.Start();
        }
        void Tick()
        {
            if (disposed) return;
            foreach (var r in shown) { float p = r.app.Peak; double to = Math.Max(0, Math.Min(1, Math.Sqrt(p))); r.meter.ScaleX = r.meter.ScaleX * 0.45 + to * 0.55; }
            if (++ticks % 15 == 0) Refresh(false); // apps that started or stopped playing sound, every 1.5 s
        }
        void Refresh(bool force)
        {
            var fresh = AppVolume.List();
            string sig = string.Join("|", fresh.Take(MaxRows).Select(a => a.Key + ":" + a.Sessions));
            if (!force && sig == signature)
            {
                // the same apps: show volume changes made elsewhere (Windows' mixer, the app itself)
                foreach (var a in fresh) a.Dispose();
                foreach (var r in shown)
                {
                    if (r.slider.IsMouseCaptureWithin) continue;
                    double v = Math.Round(r.app.Level * 100);
                    if (Math.Abs(r.slider.Value - v) >= 1) { r.slider.Tag = "sync"; r.slider.Value = v; r.slider.Tag = null; }
                    SetMuteGlyph(r.mute, r.app.Muted || v == 0);
                }
                return;
            }
            signature = sig;
            foreach (var a in apps) a.Dispose();
            apps = fresh;
            rows.Children.Clear(); shown.Clear();
            Root.Visibility = apps.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
            foreach (var a in apps.Take(MaxRows)) rows.Children.Add(Row(a));
            if (apps.Count > MaxRows) { var more = Ui.Muted("+" + (apps.Count - MaxRows) + " more in Windows' volume mixer", 10.5); more.Margin = new Thickness(30, 2, 0, 0); rows.Children.Add(more); }
        }
        FrameworkElement Row(AudioApp a)
        {
            var g = new Grid { Margin = new Thickness(0, 1, 0, 1), ToolTip = a.Name };
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(26) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(96) });
            g.ColumnDefinitions.Add(new ColumnDefinition());
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            FrameworkElement icon;
            if (a.System) icon = Ui.Glyph(0xE7F5, 14, Theme.Muted);
            else
            {
                ImageSource src = null;
                try { src = Icons.For(new AppRef { Name = a.Name, Exe = a.Exe, AppId = a.AppId ?? "" }, 48, true); } catch { }
                icon = src == null ? (FrameworkElement)Ui.Glyph(0xE8D6, 13, Theme.Muted) : new Image { Source = src, Width = 18, Height = 18 };
                if (icon is Image img) RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality);
            }
            icon.HorizontalAlignment = HorizontalAlignment.Left; icon.VerticalAlignment = VerticalAlignment.Center; icon.Margin = new Thickness(4, 0, 0, 0);
            g.Children.Add(icon);
            var name = Ui.Text(a.Name, 12, null, a.Active ? Theme.Text : Theme.Muted); name.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(name, 1); g.Children.Add(name);
            var cell = new Grid { Margin = new Thickness(6, 0, 4, 0) };
            var slider = new Slider { Minimum = 0, Maximum = 100, Value = Math.Round(a.Level * 100), VerticalAlignment = VerticalAlignment.Center };
            System.Windows.Automation.AutomationProperties.SetName(slider, a.Name + " volume");
            var meterScale = new ScaleTransform(0, 1);
            var meter = new Border { Height = 2, CornerRadius = new CornerRadius(1), Background = Theme.Data, Opacity = 0.75, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(8, 0, 8, 0), RenderTransform = meterScale, RenderTransformOrigin = new Point(0, 0.5), IsHitTestVisible = false };
            cell.Children.Add(slider); cell.Children.Add(meter);
            Grid.SetColumn(cell, 2); g.Children.Add(cell);
            Button mute = null;
            mute = Ui.Icon(0xE995, "Mute " + a.Name, () => { a.SetMuted(!a.Muted); SetMuteGlyph(mute, a.Muted || slider.Value == 0); }, 26, 11);
            SetMuteGlyph(mute, a.Muted || slider.Value == 0);
            Grid.SetColumn(mute, 3); g.Children.Add(mute);
            slider.ValueChanged += (o, e) => { if (slider.Tag as string == "sync") return; a.SetLevel((float)(slider.Value / 100)); SetMuteGlyph(mute, a.Muted || slider.Value == 0); };
            shown.Add((a, slider, meterScale, mute));
            return g;
        }
        static void SetMuteGlyph(Button b, bool muted) { if (b?.Content is TextBlock t) t.Text = char.ConvertFromUtf32(muted ? 0xE74F : 0xE995); }
        public void Dispose()
        {
            if (disposed) return;
            disposed = true; timer.Stop();
            foreach (var a in apps) a.Dispose();
            apps.Clear(); shown.Clear();
        }
    }
}
