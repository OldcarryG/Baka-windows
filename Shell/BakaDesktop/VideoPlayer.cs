using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Baka.Desktop
{
    // A looping video drawn by Windows' own Media Foundation player (MFPlay) straight into a native window.
    // Media Foundation decodes on the GPU (DXVA) when the driver supports the format and presents the frames
    // with the Enhanced Video Renderer, so a 4K video is never copied through WPF or the CPU. It plays every
    // format Windows can: H.264, HEVC (HEVC Video Extensions), VP9, AV1 (AV1 Video Extension), in MP4, MOV,
    // MKV, WebM, WMV and AVI. The player thread does not get multimedia (MMCSS) priority, so it never
    // competes with the app in front.
    sealed class VideoPlayer : IDisposable
    {
        [ComImport, Guid("a714590a-58af-430a-85bf-44f5ec838d85"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IMFPMediaPlayer
        {
            [PreserveSig] int Play();
            [PreserveSig] int Pause();
            [PreserveSig] int Stop();
            [PreserveSig] int FrameStep();
            [PreserveSig] int SetPosition([In] ref Guid type, [In] ref PropVariant position);
            [PreserveSig] int GetPosition([In] ref Guid type, out PropVariant position);
            [PreserveSig] int GetDuration([In] ref Guid type, out PropVariant duration);
            [PreserveSig] int SetRate(float rate);
            [PreserveSig] int GetRate(out float rate);
            [PreserveSig] int GetSupportedRates(bool forward, out float slowest, out float fastest);
            [PreserveSig] int GetState(out int state);
            [PreserveSig] int CreateMediaItemFromURL([MarshalAs(UnmanagedType.LPWStr)] string url, bool sync, IntPtr userData, out IntPtr item);
            [PreserveSig] int CreateMediaItemFromObject(IntPtr obj, bool sync, IntPtr userData, out IntPtr item);
            [PreserveSig] int SetMediaItem(IntPtr item);
            [PreserveSig] int ClearMediaItem();
            [PreserveSig] int GetMediaItem(out IntPtr item);
            [PreserveSig] int GetVolume(out float volume);
            [PreserveSig] int SetVolume(float volume);
            [PreserveSig] int GetBalance(out float balance);
            [PreserveSig] int SetBalance(float balance);
            [PreserveSig] int GetMute(out bool mute);
            [PreserveSig] int SetMute(bool mute);
            [PreserveSig] int GetNativeVideoSize(out Size video, out Size aspect);
            [PreserveSig] int GetIdealVideoSize(out Size min, out Size max);
            [PreserveSig] int SetVideoSourceRect([In] ref NormalizedRect rect);
            [PreserveSig] int GetVideoSourceRect(out NormalizedRect rect);
            [PreserveSig] int SetAspectRatioMode(int mode);
            [PreserveSig] int GetAspectRatioMode(out int mode);
            [PreserveSig] int GetVideoWindow(out IntPtr hwnd);
            [PreserveSig] int UpdateVideo();
            [PreserveSig] int SetBorderColor(int color);
            [PreserveSig] int GetBorderColor(out int color);
            [PreserveSig] int InsertEffect(IntPtr effect, bool optional);
            [PreserveSig] int RemoveEffect(IntPtr effect);
            [PreserveSig] int RemoveAllEffects();
            [PreserveSig] int Shutdown();
        }
        [ComImport, Guid("766c8ffb-5fdb-4fea-a28d-b912996f51bd"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IMFPMediaPlayerCallback { [PreserveSig] void OnMediaPlayerEvent(IntPtr header); }

        [StructLayout(LayoutKind.Explicit, Size = 24)] struct PropVariant { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public long value; }
        [StructLayout(LayoutKind.Sequential)] struct NormalizedRect { public float left, top, right, bottom; }

        [DllImport("mfplay.dll")] static extern int MFPCreateMediaPlayer([MarshalAs(UnmanagedType.LPWStr)] string url, bool startPlayback, int options, IMFPMediaPlayerCallback callback, IntPtr hwnd, out IMFPMediaPlayer player);

        [ClassInterface(ClassInterfaceType.None)]
        sealed class Callback : IMFPMediaPlayerCallback
        {
            readonly VideoPlayer owner; public Callback(VideoPlayer o) { owner = o; }
            public void OnMediaPlayerEvent(IntPtr header) { try { owner.OnEvent(Marshal.ReadInt32(header), Marshal.ReadInt32(header, 4)); } catch (Exception e) { Log.Write("video-event-failed error=\"" + e.Message + "\""); } }
        }

        // the window the video is drawn into (no border, no taskbar button, never takes focus)
        sealed class Surface : Form
        {
            public Surface() { FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; StartPosition = FormStartPosition.Manual; BackColor = Color.Black; Text = "BAKA Video Wallpaper"; }
            protected override bool ShowWithoutActivation => true;
            protected override CreateParams CreateParams { get { var cp = base.CreateParams; cp.ExStyle |= 0x08000000 /*NOACTIVATE*/ | 0x80 /*TOOLWINDOW*/ | 0x20 /*TRANSPARENT to clicks*/; return cp; } }
            protected override void OnPaintBackground(PaintEventArgs e) { if (Painted == null || !Painted()) base.OnPaintBackground(e); }
            public Func<bool> Painted;
        }

        public readonly string Path;
        public string Fit;
        public event Action<string> Failed;
        public int Loops { get; private set; }
        public bool Ready { get; private set; }
        public Size VideoSize { get; private set; }
        public string LastError { get; private set; }
        readonly Surface surface = new Surface();
        IMFPMediaPlayer player; Callback callback;
        bool muted, wantPlaying = true;
        long resumeAt;
        static Guid Time100ns = Guid.Empty; // MFP_POSITIONTYPE_100NS

        public VideoPlayer(string path, string fit, bool muted)
        {
            Path = path; Fit = fit; this.muted = muted;
            surface.Painted = () => { if (player != null && Ready) { player.UpdateVideo(); return true; } return false; };
            surface.Resize += (o, e) => { Crop(); player?.UpdateVideo(); };
        }
        public IntPtr Handle => surface.Handle;

        // Shows the surface at the given place (screen pixels, or client pixels of the parent) and opens the file.
        public void Open(IntPtr parent, Rectangle where)
        {
            var h = surface.Handle;
            if (parent != IntPtr.Zero) Native.SetParentWindow(h, parent);
            surface.Show();
            Native.SetWindowPos(h, IntPtr.Zero, where.X, where.Y, where.Width, where.Height, Native.SWP_NOACTIVATE | Native.SWP_NOZORDER | Native.SWP_SHOWWINDOW);
            Create();
        }
        public void Place(Rectangle where) => Native.SetWindowPos(surface.Handle, IntPtr.Zero, where.X, where.Y, where.Width, where.Height, Native.SWP_NOACTIVATE | Native.SWP_NOZORDER);

        void Create()
        {
            Ready = false; callback = new Callback(this);
            int hr = MFPCreateMediaPlayer(Path, false, 0x2 /*MFP_OPTION_NO_MMCSS*/, callback, surface.Handle, out player);
            if (hr < 0 || player == null) { Fail("MFPCreateMediaPlayer 0x" + hr.ToString("X8")); return; }
            player.SetMute(muted);
            player.SetBorderColor(0);
        }

        void OnEvent(int type, int hr)
        {
            if (player == null) return;
            if (hr < 0 && type != 11) { Fail(EventName(type) + " 0x" + hr.ToString("X8") + Hint(hr)); return; }
            switch (type)
            {
                case 6: // MEDIAITEM_SET: the file is open
                    if (player.GetNativeVideoSize(out var v, out _) >= 0) VideoSize = v;
                    // a file whose video Windows cannot decode still "plays" its sound track: treat it as a failure
                    if (VideoSize.Width <= 0 || VideoSize.Height <= 0) { Fail("no picture: Windows has no decoder for this video's format" + Hint(unchecked((int)0xC00D5212))); return; }
                    Ready = true; Crop();
                    if (resumeAt > 0) { var p = new PropVariant { vt = 20, value = resumeAt }; player.SetPosition(ref Time100ns, ref p); resumeAt = 0; }
                    if (wantPlaying) player.Play();
                    Log.Write("video-ready size=" + VideoSize.Width + "x" + VideoSize.Height + " path=\"" + Path + "\"");
                    break;
                case 11: // PLAYBACK_ENDED: loop
                    Loops++;
                    var zero = new PropVariant { vt = 20, value = 0 };
                    player.SetPosition(ref Time100ns, ref zero);
                    if (wantPlaying) player.Play();
                    break;
                case 10: Fail("error 0x" + hr.ToString("X8") + Hint(hr)); break;
            }
        }
        static string EventName(int t) => t == 5 ? "open" : t == 6 ? "open" : t == 0 ? "play" : "event " + t;
        static string Hint(int hr) => hr == unchecked((int)0xC00D5212) || hr == unchecked((int)0xC00D36B4) ? " (Windows has no decoder for this video: install HEVC, VP9 or AV1 Video Extensions from the Microsoft Store, or use an H.264 MP4)" : "";

        // Fill crops the video to the screen's shape (no black bars); Fit shows it whole; Stretch distorts it.
        void Crop()
        {
            if (player == null || !Ready) return;
            var full = new NormalizedRect { left = 0, top = 0, right = 1, bottom = 1 };
            if (Fit == "Fit" || Fit == "Center") { player.SetAspectRatioMode(1 /*MFVideoARMode_PreservePicture*/); player.SetVideoSourceRect(ref full); return; }
            player.SetAspectRatioMode(0);
            if (Fit == "Stretch" || VideoSize.Width <= 0 || VideoSize.Height <= 0 || surface.ClientSize.Height <= 0) { player.SetVideoSourceRect(ref full); return; }
            double screen = surface.ClientSize.Width / (double)surface.ClientSize.Height, video = VideoSize.Width / (double)VideoSize.Height;
            var r = full;
            if (video > screen) { float keep = (float)(screen / video); r.left = (1 - keep) / 2; r.right = 1 - r.left; }
            else if (video < screen) { float keep = (float)(video / screen); r.top = (1 - keep) / 2; r.bottom = 1 - r.top; }
            player.SetVideoSourceRect(ref r);
        }

        public void Play() { wantPlaying = true; if (player != null && Ready) player.Play(); else if (player == null) Create(); }
        public void Pause() { wantPlaying = false; if (player != null && Ready) player.Pause(); }
        public bool Playing { get { if (player == null) return false; player.GetState(out int s); return s == 2; } }
        public TimeSpan Position { get { if (player == null) return TimeSpan.Zero; return player.GetPosition(ref Time100ns, out var p) >= 0 ? TimeSpan.FromTicks(p.value) : TimeSpan.Zero; } }
        public TimeSpan Duration { get { if (player == null) return TimeSpan.Zero; return player.GetDuration(ref Time100ns, out var p) >= 0 ? TimeSpan.FromTicks(p.value) : TimeSpan.Zero; } }
        public void SetMuted(bool m) { muted = m; player?.SetMute(m); }

        // Frees the decoder and its video memory entirely (games); Resume reopens at the same spot.
        public void Suspend()
        {
            if (player == null) return;
            try { resumeAt = Position.Ticks; } catch { resumeAt = 0; }
            Release();
            surface.Invalidate();
        }
        public void Resume() { if (player == null) { wantPlaying = true; Create(); } }
        public bool Suspended => player == null;

        void Fail(string why)
        {
            LastError = why;
            Log.Write("video-wallpaper-failed error=\"" + why + "\" path=\"" + Path + "\"");
            Release();
            Failed?.Invoke(why);
        }
        void Release()
        {
            var p = player; player = null; Ready = false;
            if (p != null) { try { p.Shutdown(); } catch { } try { Marshal.ReleaseComObject(p); } catch { } }
        }
        public void Dispose() { Release(); try { surface.Close(); surface.Dispose(); } catch { } }
    }
}

namespace Baka.Desktop
{
    // BakaDesktop.exe --video-test <file> <result.json> [seconds]: plays a file with the wallpaper player in a
    // window the size of the primary monitor for the given time (default 20 s) and writes what happened:
    // the video size, whether it played and looped, pause/resume and suspend/resume, and the CPU this
    // process used (Media Foundation decodes in this process, so a high number means software decoding).
    static class VideoTest
    {
        public static int Run(string file, string result, int seconds)
        {
            var r = new System.Collections.Generic.Dictionary<string, object> { ["file"] = file, ["seconds"] = seconds };
            int code = 1;
            try
            {
                // a 960x540 window in the corner, so a test on a PC in use does not cover the screen
                var wa = Screen.PrimaryScreen.WorkingArea;
                var screen = new Rectangle(wa.Right - 980, wa.Bottom - 560, 960, 540);
                var host = new Form { FormBorderStyle = FormBorderStyle.None, StartPosition = FormStartPosition.Manual, Bounds = screen, BackColor = Color.Black, ShowInTaskbar = false, TopMost = false, Text = "BAKA video test" };
                var player = new VideoPlayer(file, "Fill", true);
                string failed = null; player.Failed += why => failed = why;
                var proc = System.Diagnostics.Process.GetCurrentProcess();
                var sw = System.Diagnostics.Stopwatch.StartNew();
                TimeSpan cpu0 = TimeSpan.Zero, wall0 = TimeSpan.Zero, firstPos = TimeSpan.Zero; double cpuPct = -1; int step = 0;
                var t = new Timer { Interval = 250 };
                t.Tick += (o, e) =>
                {
                    double s = sw.Elapsed.TotalSeconds;
                    if (failed != null) { r["error"] = failed; t.Stop(); host.Close(); return; }
                    if (step == 0 && player.Ready && s > 2) { proc.Refresh(); cpu0 = proc.TotalProcessorTime; wall0 = sw.Elapsed; firstPos = player.Position; step = 1; }
                    if (step == 1 && s > seconds * 0.7)
                    {
                        proc.Refresh(); var used = proc.TotalProcessorTime - cpu0; var wall = sw.Elapsed - wall0;
                        cpuPct = 100.0 * used.TotalMilliseconds / (wall.TotalMilliseconds * Environment.ProcessorCount);
                        r["cpuPercentOfAllCores"] = Math.Round(cpuPct, 2);
                        r["playedSeconds"] = Math.Round(wall.TotalSeconds, 1);
                        r["positionAdvanced"] = Math.Round((player.Position - firstPos).TotalSeconds + player.Loops * player.Duration.TotalSeconds, 1);
                        player.Pause(); step = 2;
                    }
                    if (step == 2 && s > seconds * 0.7 + 1.5) { var p = player.Position; r["pausedHolds"] = !player.Playing; r["pausedAt"] = p.TotalSeconds; player.Play(); step = 3; }
                    if (step == 3 && s > seconds * 0.7 + 3) { r["resumedPlays"] = player.Playing; player.Suspend(); r["suspendFreesPlayer"] = player.Suspended; player.Resume(); step = 4; }
                    // reopening and seeking a 4K file can take several seconds when the CPU decodes it (no GPU)
                    if (step == 4 && (player.Playing || s > seconds * 0.7 + 18)) { r["resumeAfterSuspendPlays"] = player.Playing; r["resumeSeconds"] = Math.Round(s - seconds * 0.7 - 3, 1); step = 5; }
                    if (s > seconds + 22 || (step == 5)) { t.Stop(); host.Close(); }
                };
                host.Shown += (o, e) => { player.Open(host.Handle, new Rectangle(0, 0, screen.Width, screen.Height)); t.Start(); };
                Application.Run(host);
                r["ready"] = player.Ready || r.ContainsKey("positionAdvanced");
                r["videoWidth"] = player.VideoSize.Width; r["videoHeight"] = player.VideoSize.Height;
                r["durationSeconds"] = Math.Round(player.Duration.TotalSeconds, 2);
                r["loops"] = player.Loops;
                if (player.LastError != null) r["error"] = player.LastError;
                player.Dispose();
                bool ok = !r.ContainsKey("error") && r.ContainsKey("positionAdvanced") && Convert.ToDouble(r["positionAdvanced"]) > 1 && player.VideoSize.Width > 0
                    && Equals(r.ContainsKey("resumedPlays") ? r["resumedPlays"] : false, true) && Equals(r.ContainsKey("resumeAfterSuspendPlays") ? r["resumeAfterSuspendPlays"] : false, true);
                r["result"] = ok ? "Passed" : "Failed"; code = ok ? 0 : 1;
            }
            catch (Exception e) { r["error"] = e.GetType().Name + ": " + e.Message; r["result"] = "Failed"; }
            var sb = new System.Text.StringBuilder("{\n");
            int i = 0;
            foreach (var kv in r)
            {
                string v = kv.Value is string str ? "\"" + str.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"" : kv.Value is bool b ? (b ? "true" : "false") : Convert.ToString(kv.Value, System.Globalization.CultureInfo.InvariantCulture);
                sb.Append("  \"").Append(kv.Key).Append("\": ").Append(v).Append(++i < r.Count ? ",\n" : "\n");
            }
            sb.Append("}\n");
            System.IO.File.WriteAllText(result, sb.ToString());
            return code;
        }
    }
}
