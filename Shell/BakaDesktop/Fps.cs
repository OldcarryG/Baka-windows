using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Threading;

namespace Baka.Desktop
{
    // Frames per second of the app in front, from Windows' own graphics event log (ETW). This is how
    // PresentMon, CapFrameX and Xbox Game Bar measure it: every frame an app hands to Windows (a DXGI or
    // Direct3D 9 Present, or the kernel's present for Vulkan / OpenGL) is logged with the app's process id
    // and a time stamp. Nothing is injected into the game, so anti-cheat software has nothing to object to.
    //
    // Windows lets administrators and members of "Performance Log Users" read this log. BAKA runs as a
    // normal user, so FpsAccess adds the account to that group once, with the user's approval; Windows
    // applies group changes at the next sign-in.
    static class Fps
    {
        public enum Status { Off, Starting, Running, NoAccess, Failed }
        public static volatile Status State = Status.Off;
        public static string Error = "";
        static string SessionName => "BAKA-FPS-" + Process.GetCurrentProcess().SessionId;

        // Microsoft-Windows-DXGI, Microsoft-Windows-D3D9 and Microsoft-Windows-DxgKrnl (ids from PresentMon)
        static readonly Guid DxgiGuid = new Guid("CA11C036-0102-4A2D-A6AD-F03CFED5D3C9"), D3d9Guid = new Guid("783ACA0A-790E-4D7F-8451-AA850511C6B9"), KernelGuid = new Guid("802EC45A-1E99-4B83-9920-87C98277BA9D");
        static readonly long Dxgi0 = Half(DxgiGuid, 0), Dxgi1 = Half(DxgiGuid, 8), D3d90 = Half(D3d9Guid, 0), D3d91 = Half(D3d9Guid, 8), Kern0 = Half(KernelGuid, 0), Kern1 = Half(KernelGuid, 8);
        static long Half(Guid g, int at) => BitConverter.ToInt64(g.ToByteArray(), at);
        const int DxgiPresentStart = 42, DxgiMultiplaneStart = 55, D3d9PresentStart = 1, KernelPresentInfo = 184;

        // ---- frames, per process and swap chain ----
        sealed class Chain
        {
            public const int Size = 4096, Mask = Size - 1;
            public readonly long[] T = new long[Size];
            public int Count, Head; public long Last; public bool Kernel;
            public void Add(long ts) { T[Head] = ts; Head = (Head + 1) & Mask; if (Count < Size) Count++; Last = ts; }
            public long At(int back) => T[(Head - 1 - back) & Mask]; // 0 = newest
        }
        static readonly Dictionary<uint, Dictionary<ulong, Chain>> procs = new Dictionary<uint, Dictionary<ulong, Chain>>();
        static readonly object gate = new object();
        static long events;

        public struct Reading { public bool Has; public double Fps, Low1, FrameMs; }

        // The app's frame rate: its busiest swap chain (a game with a second one for its launcher UI counts
        // the game's). The kernel's count is only used for apps that hand Windows no DXGI / D3D9 frames.
        public static Reading Sample(uint pid)
        {
            long now = Stopwatch.GetTimestamp(), f = Stopwatch.Frequency;
            lock (gate)
            {
                if (!procs.TryGetValue(pid, out var chains) || chains.Count == 0) return default;
                bool api = chains.Values.Any(c => !c.Kernel && c.Last > now - 3 * f);
                Chain best = null; int bestN = -1;
                foreach (var c in chains.Values)
                {
                    if (api && c.Kernel) continue;
                    int n = 0; for (; n < c.Count && c.At(n) > c.Last - f; n++) { }
                    if (n > bestN) { bestN = n; best = c; }
                }
                if (best == null) return default;
                var r = new Reading { Has = true };
                if (best.Last < now - (long)(2.5 * f) || best.Count < 2) return r; // drew nothing lately: 0 fps
                // average over the last second (at least the last two frames)
                int k = Math.Max(2, Math.Min(bestN, best.Count));
                double span = best.At(0) - best.At(k - 1);
                if (span > 0) { r.Fps = (k - 1) * (double)f / span; r.FrameMs = span * 1000.0 / f / (k - 1); }
                // 1% low: the frame rate of the slowest 1% of frames over the last 5 seconds
                var gaps = new List<long>();
                for (int i = 0; i + 1 < best.Count && best.At(i + 1) > best.Last - 5 * f; i++) gaps.Add(best.At(i) - best.At(i + 1));
                if (gaps.Count >= 10)
                {
                    gaps.Sort();
                    long slow = gaps[Math.Min(gaps.Count - 1, (int)Math.Floor(gaps.Count * 0.99))];
                    // never above the current rate: right after a slowdown the 5 s window still holds the faster frames
                    if (slow > 0) r.Low1 = Math.Min((double)f / slow, r.Fps > 0 ? r.Fps : double.MaxValue);
                }
                return r;
            }
        }
        // Processes that drew in the last few seconds (for the probe and for apps that draw in a helper process).
        public static List<uint> ActiveProcesses()
        {
            long now = Stopwatch.GetTimestamp(), f = Stopwatch.Frequency;
            lock (gate) return procs.Where(p => p.Value.Values.Any(c => c.Last > now - 3 * f)).Select(p => p.Key).ToList();
        }
        static void Forget()
        {
            long old = Stopwatch.GetTimestamp() - 30 * Stopwatch.Frequency;
            lock (gate) foreach (var pid in procs.Where(p => p.Value.Values.All(c => c.Last < old)).Select(p => p.Key).ToList()) procs.Remove(pid);
        }

        // ---- the event callback (ETW's thread; must be quick and must never throw) ----
        delegate void EventRecordCallback(IntPtr record);
        static readonly EventRecordCallback callback = OnEvent; // kept alive: Windows calls into it
        static Dictionary<(int, int, uint), int> probe;          // --fps-probe: every event, counted
        static bool probeFiltered;                                // --fps-probe ... filtered: with the normal filters
        static void OnEvent(IntPtr r)
        {
            try
            {
                Interlocked.Increment(ref events);
                long g0 = Marshal.ReadInt64(r, 24), g1 = Marshal.ReadInt64(r, 32);
                int id = (ushort)Marshal.ReadInt16(r, 40);
                uint pid = (uint)Marshal.ReadInt32(r, 12);
                int provider = g0 == Dxgi0 && g1 == Dxgi1 ? 1 : g0 == D3d90 && g1 == D3d91 ? 2 : g0 == Kern0 && g1 == Kern1 ? 3 : 0;
                var counts = probe;
                if (counts != null) lock (counts) { var key = (provider, id, pid); counts.TryGetValue(key, out int n); counts[key] = n + 1; }
                bool kernel = provider == 3;
                if (!(provider == 1 && (id == DxgiPresentStart || id == DxgiMultiplaneStart)) && !(provider == 2 && id == D3d9PresentStart) && !(kernel && id == KernelPresentInfo)) return;
                long ts = Marshal.ReadInt64(r, 16);
                ulong chain = 1UL << 63;
                if (!kernel)
                {
                    // the first field is the swap chain (a 4-byte pointer when the app is 32-bit)
                    int len = (ushort)Marshal.ReadInt16(r, 86); IntPtr data = Marshal.ReadIntPtr(r, 96);
                    bool p32 = (Marshal.ReadInt16(r, 4) & 0x0020) != 0; int ps = p32 ? 4 : 8;
                    if (data != IntPtr.Zero && len >= ps)
                    {
                        chain = p32 ? (uint)Marshal.ReadInt32(data) : (ulong)Marshal.ReadInt64(data);
                        // DXGI_PRESENT_TEST asks whether a frame could be shown; nothing is shown
                        if (provider == 1 && len >= ps + 4 && (Marshal.ReadInt32(data, ps) & 1) != 0) return;
                    }
                }
                lock (gate)
                {
                    if (!procs.TryGetValue(pid, out var chains)) procs[pid] = chains = new Dictionary<ulong, Chain>();
                    if (!chains.TryGetValue(chain, out var c)) { if (chains.Count > 16) return; chains[chain] = c = new Chain { Kernel = kernel }; }
                    c.Add(ts);
                }
            }
            catch { }
        }

        // ---- the trace session ----
        [DllImport("advapi32.dll", CharSet = CharSet.Unicode)] static extern int StartTrace(out ulong handle, string name, IntPtr properties);
        [DllImport("advapi32.dll", CharSet = CharSet.Unicode)] static extern int ControlTrace(ulong handle, string name, IntPtr properties, uint code);
        [DllImport("advapi32.dll")] static extern int EnableTraceEx2(ulong handle, ref Guid provider, uint code, byte level, ulong anyKeyword, ulong allKeyword, uint timeout, IntPtr parameters);
        [DllImport("advapi32.dll", EntryPoint = "OpenTraceW", SetLastError = true)] static extern ulong OpenTrace(IntPtr logfile);
        [DllImport("advapi32.dll")] static extern int ProcessTrace(ulong[] handles, uint count, IntPtr start, IntPtr end);
        [DllImport("advapi32.dll")] static extern int CloseTrace(ulong handle);
        const uint StopCode = 1;

        // EVENT_TRACE_PROPERTIES (120 bytes on x64) with room for the session name behind it.
        const int PropsSize = 120, NameRoom = 1024;
        static IntPtr Properties(bool msFlush)
        {
            IntPtr p = Marshal.AllocHGlobal(PropsSize + NameRoom);
            for (int i = 0; i < PropsSize + NameRoom; i += 4) Marshal.WriteInt32(p, i, 0);
            Marshal.WriteInt32(p, 0, PropsSize + NameRoom);   // Wnode.BufferSize
            Marshal.WriteInt32(p, 40, 1);                      // Wnode.ClientContext: QueryPerformanceCounter time stamps
            Marshal.WriteInt32(p, 44, 0x00020000);             // Wnode.Flags: WNODE_FLAG_TRACED_GUID
            Marshal.WriteInt32(p, 48, 64);                     // BufferSize (KB)
            Marshal.WriteInt32(p, 52, 4);                      // MinimumBuffers
            Marshal.WriteInt32(p, 56, 32);                     // MaximumBuffers
            // real time, and (Windows 8+) the flush timer in milliseconds: frames arrive within a quarter second
            Marshal.WriteInt32(p, 64, 0x00000100 | (msFlush ? 0x00000010 : 0));
            Marshal.WriteInt32(p, 68, msFlush ? 250 : 1);      // FlushTimer
            Marshal.WriteInt32(p, 116, PropsSize);             // LoggerNameOffset
            return p;
        }
        // EnableTraceEx2 with an event id filter (ENABLE_TRACE_PARAMETERS v2 -> EVENT_FILTER_DESCRIPTOR of type
        // EVENT_FILTER_TYPE_EVENT_ID -> EVENT_FILTER_EVENT_ID). If Windows refuses the filter, a provider whose
        // unfiltered volume is small is enabled without it; the kernel provider is then left off.
        static int Enable(ulong session, Guid provider, byte level, ulong anyKeyword, ushort[] ids, bool unfilteredOk)
        {
            if (ids == null) return EnableTraceEx2(session, ref provider, 1, level, anyKeyword, 0, 0, IntPtr.Zero);
            int size = 4 + 2 * ids.Length;
            IntPtr filter = Marshal.AllocHGlobal(size), desc = Marshal.AllocHGlobal(16), param = Marshal.AllocHGlobal(48);
            try
            {
                Marshal.WriteByte(filter, 0, 1); Marshal.WriteByte(filter, 1, 0); Marshal.WriteInt16(filter, 2, (short)ids.Length); // FilterIn, Reserved, Count
                for (int i = 0; i < ids.Length; i++) Marshal.WriteInt16(filter, 4 + 2 * i, (short)ids[i]);
                Marshal.WriteInt64(desc, 0, filter.ToInt64()); Marshal.WriteInt32(desc, 8, size); Marshal.WriteInt32(desc, 12, unchecked((int)0x80000200)); // EVENT_FILTER_TYPE_EVENT_ID
                for (int i = 0; i < 48; i += 8) Marshal.WriteInt64(param, i, 0);
                Marshal.WriteInt32(param, 0, 2);          // ENABLE_TRACE_PARAMETERS_VERSION_2
                Marshal.WriteIntPtr(param, 32, desc);     // EnableFilterDesc
                Marshal.WriteInt32(param, 40, 1);         // FilterDescCount
                int rc = EnableTraceEx2(session, ref provider, 1, level, anyKeyword, 0, 0, param);
                if (rc != 0) { Log.Write("fps-filter-refused provider=" + provider + " code=" + rc); if (unfilteredOk) rc = EnableTraceEx2(session, ref provider, 1, level, anyKeyword, 0, 0, IntPtr.Zero); }
                return rc;
            }
            finally { Marshal.FreeHGlobal(filter); Marshal.FreeHGlobal(desc); Marshal.FreeHGlobal(param); }
        }
        static void StopSession(string name)
        {
            IntPtr p = Properties(false);
            try { ControlTrace(0, name, p, StopCode); } finally { Marshal.FreeHGlobal(p); }
        }

        static Thread thread;
        static volatile bool stopping;
        public static bool Running => thread != null && thread.IsAlive;

        // Starts reading frames (the overlay is showing). Does nothing when it already runs, or when Windows
        // said no and nothing has changed since (Retry is for after the user allowed it).
        public static void Start(bool withProbe = false)
        {
            if (Running)
            {
                if (!stopping) return;
                try { thread.Join(1500); } catch { } // the previous session is still ending
            }
            if (State == Status.NoAccess) return;
            if (withProbe) probe = new Dictionary<(int, int, uint), int>();
            stopping = false; State = Status.Starting;
            thread = new Thread(Run) { IsBackground = true, Name = "BAKA FPS", Priority = ThreadPriority.AboveNormal };
            thread.Start();
        }
        public static void Retry() { if (State == Status.NoAccess || State == Status.Failed) State = Status.Off; }
        // Stops the session; the reading thread ends by itself once Windows has stopped it (no waiting here,
        // this runs on the UI thread).
        public static void Stop()
        {
            if (!Running) return;
            stopping = true;
            try { StopSession(SessionName); } catch { }
            lock (gate) procs.Clear();
        }
        // A session left behind by a BAKA that was ended without stopping it: it would keep the graphics
        // providers logging for nobody. Stopped at start and by the supervisor after a crash.
        public static void StopLeftover() { if (!Running) try { StopSession(SessionName); } catch { } }

        static void Run()
        {
            string name = SessionName;
            IntPtr props = IntPtr.Zero, logfile = IntPtr.Zero, namePtr = IntPtr.Zero;
            try
            {
                bool ms = true;
                props = Properties(ms);
                int err = StartTrace(out ulong session, name, props);
                if (err == 183 /*ALREADY_EXISTS*/) { StopSession(name); Marshal.FreeHGlobal(props); props = Properties(ms); err = StartTrace(out session, name, props); }
                if (err == 87 /*INVALID_PARAMETER: no millisecond flush timer*/) { ms = false; Marshal.FreeHGlobal(props); props = Properties(ms); err = StartTrace(out session, name, props); }
                if (err == 5 /*ACCESS_DENIED*/) { State = Status.NoAccess; Log.Write("fps-counter-no-access (Performance Log Users needed)"); return; }
                if (err != 0) { State = Status.Failed; Error = "StartTrace " + err; Log.Write("fps-counter-failed error=\"StartTrace " + err + "\""); return; }
                // Windows filters the events to the present ones before they are logged: the kernel provider's
                // Present keyword alone was about 4,000 events a second on the desktop (measured), the one
                // "present" event is one per frame. The unfiltered probe sees everything.
                bool all = probe != null && !probeFiltered;
                int e1 = Enable(session, DxgiGuid, 4, 0x8000000000000002UL, all ? null : new ushort[] { DxgiPresentStart, DxgiMultiplaneStart }, true); // Events | Analytic
                int e2 = Enable(session, D3d9Guid, 5, ulong.MaxValue, all ? null : new ushort[] { D3d9PresentStart }, true);
                int e3 = Enable(session, KernelGuid, 4, 0x8000000UL, all ? null : new ushort[] { KernelPresentInfo }, false);                   // Present (Windows 11)
                // EVENT_TRACE_LOGFILEW (448 bytes on x64): LoggerName at 8, ProcessTraceMode at 28, EventRecordCallback at 424
                logfile = Marshal.AllocHGlobal(448);
                for (int i = 0; i < 448; i += 8) Marshal.WriteInt64(logfile, i, 0);
                namePtr = Marshal.StringToHGlobalUni(name);
                Marshal.WriteIntPtr(logfile, 8, namePtr);
                Marshal.WriteInt32(logfile, 28, 0x00000100 | 0x00001000 | 0x10000000); // REAL_TIME | RAW_TIMESTAMP | EVENT_RECORD
                Marshal.WriteIntPtr(logfile, 424, Marshal.GetFunctionPointerForDelegate(callback));
                ulong trace = OpenTrace(logfile);
                if (trace == ulong.MaxValue) { int le = Marshal.GetLastWin32Error(); State = Status.Failed; Error = "OpenTrace " + le; Log.Write("fps-counter-failed error=\"OpenTrace " + le + "\""); return; }
                State = Status.Running;
                Log.Write("fps-counter-on enable=" + e1 + "/" + e2 + "/" + e3 + " msFlush=" + ms);
                var cleanup = new Timer(_ => Forget(), null, 10000, 10000);
                int pr = ProcessTrace(new[] { trace }, 1, IntPtr.Zero, IntPtr.Zero); // runs until the session stops
                cleanup.Dispose();
                CloseTrace(trace);
                Log.Write("fps-counter-off result=" + pr + " events=" + Interlocked.Read(ref events));
            }
            catch (Exception e) { State = Status.Failed; Error = e.Message; Log.Write("fps-counter-failed error=\"" + e.Message + "\""); }
            finally
            {
                try { if (!stopping) StopSession(name); } catch { }
                if (props != IntPtr.Zero) Marshal.FreeHGlobal(props);
                if (logfile != IntPtr.Zero) Marshal.FreeHGlobal(logfile);
                if (namePtr != IntPtr.Zero) Marshal.FreeHGlobal(namePtr);
                if (State == Status.Running || State == Status.Starting) State = Status.Off;
            }
        }

        // ---- --fps-probe <seconds> <result.json>: what the graphics log reports on this PC ----
        // Runs the counter with every event counted, while a BAKA test window animates (WPF draws through
        // Direct3D 9, so its own frames are a known source at the screen's refresh rate). Needs an elevated
        // run or Performance Log Users. Writes per-process frame rates and raw event counts.
        public static int Probe(int seconds, string path, bool filtered = false)
        {
            Paths.Init(true);
            probeFiltered = filtered;
            var result = new Dictionary<string, object> { ["startedAt"] = DateTime.Now.ToString("o"), ["seconds"] = seconds, ["filtered"] = filtered, ["elevated"] = Native.IsElevated((uint)Process.GetCurrentProcess().Id), ["ownPid"] = Process.GetCurrentProcess().Id };
            var app = new System.Windows.Application { ShutdownMode = System.Windows.ShutdownMode.OnExplicitShutdown };
            var w = new System.Windows.Window { Title = "BAKA FPS test", Width = 260, Height = 120, Left = 40, Top = 40, Topmost = true, ShowActivated = false, WindowStyle = System.Windows.WindowStyle.ToolWindow };
            var bar = new System.Windows.Controls.Border { Width = 40, Height = 40, Background = System.Windows.Media.Brushes.DeepSkyBlue, HorizontalAlignment = System.Windows.HorizontalAlignment.Left };
            w.Content = bar;
            var started = Stopwatch.StartNew();
            System.Windows.Media.CompositionTarget.Rendering += (o, e) => bar.Margin = new System.Windows.Thickness(100 + 80 * Math.Sin(started.Elapsed.TotalSeconds * 3), 0, 0, 0);
            app.Startup += (o, e) => { };
            app.Dispatcher.BeginInvoke(new Action(() =>
            {
                w.Show();
                Start(true);
                var done = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(seconds) };
                done.Tick += (o2, e2) =>
                {
                    done.Stop();
                    try
                    {
                        result["state"] = State.ToString(); result["error"] = Error; result["eventsTotal"] = Interlocked.Read(ref events);
                        var names = new Dictionary<uint, string>();
                        string Name(uint pid) { if (!names.TryGetValue(pid, out var n)) { try { n = Path.GetFileName(Native.ProcessPath(pid) ?? ("pid " + pid)); } catch { n = "pid " + pid; } names[pid] = n; } return n; }
                        var fps = new List<object>();
                        foreach (var pid in ActiveProcesses())
                        {
                            var r = Sample(pid);
                            fps.Add(new Dictionary<string, object> { ["pid"] = (long)pid, ["process"] = Name(pid), ["fps"] = Math.Round(r.Fps, 1), ["low1"] = Math.Round(r.Low1, 1), ["frameMs"] = Math.Round(r.FrameMs, 2) });
                        }
                        result["fps"] = fps;
                        var rows = new List<object>();
                        if (probe != null) lock (probe)
                            foreach (var kv in probe.OrderByDescending(k => k.Value).Take(80))
                                rows.Add(new Dictionary<string, object> { ["provider"] = kv.Key.Item1 == 1 ? "DXGI" : kv.Key.Item1 == 2 ? "D3D9" : kv.Key.Item1 == 3 ? "DxgKrnl" : "other", ["id"] = kv.Key.Item2, ["pid"] = (long)kv.Key.Item3, ["process"] = Name(kv.Key.Item3), ["count"] = kv.Value, ["perSecond"] = Math.Round(kv.Value / (double)seconds, 1) });
                        result["eventCounts"] = rows;
                    }
                    catch (Exception ex) { result["exception"] = ex.ToString(); }
                    Stop();
                    try { thread?.Join(2000); } catch { }
                    try { File.WriteAllText(path, Json.Write(result)); } catch { }
                    app.Shutdown(0);
                };
                done.Start();
            }));
            app.Run();
            return State == Status.Failed ? 1 : 0;
        }
    }

    // Membership of Windows' "Performance Log Users" group (S-1-5-32-559), which lets a normal user read
    // the graphics event log. Asked for once from Settings; it runs elevated as
    // "BakaDesktop.exe --fps-access on|off --user <SID>". The group can record performance counters and
    // event traces; it cannot change settings or install anything.
    static class FpsAccess
    {
        const string GroupSid = "S-1-5-32-559";
        public static string MarkerPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "BAKA", "FpsCounterAccess.json");
        public static string UserSid { get { try { return WindowsIdentity.GetCurrent().User.Value; } catch { return ""; } } }
        // in this sign-in's token already (or BAKA runs elevated): FPS works now
        public static bool InToken
        {
            get
            {
                try { var p = new WindowsPrincipal(WindowsIdentity.GetCurrent()); return p.IsInRole(new SecurityIdentifier(GroupSid)) || p.IsInRole(WindowsBuiltInRole.Administrator); }
                catch { return false; }
            }
        }
        // allowed for this account (BAKA's record of it); takes effect at the next sign-in
        public static bool Granted
        {
            get
            {
                try { return File.Exists(MarkerPath) && Json.Str(Json.Obj(Json.Parse(File.ReadAllText(MarkerPath))), "sid") == UserSid; }
                catch { return false; }
            }
        }

        public static void RequestElevated(bool on)
        {
            try { Process.Start(new ProcessStartInfo(App.Exe, "--fps-access " + (on ? "on" : "off") + " --user " + UserSid) { UseShellExecute = true, Verb = "runas", WindowStyle = ProcessWindowStyle.Hidden }); }
            catch (Exception e) { Log.Write("fps-access-elevation-declined error=\"" + e.Message + "\""); }
        }

        [DllImport("netapi32.dll", CharSet = CharSet.Unicode)] static extern int NetLocalGroupAddMembers(string server, string group, int level, IntPtr[] members, int count);
        [DllImport("netapi32.dll", CharSet = CharSet.Unicode)] static extern int NetLocalGroupDelMembers(string server, string group, int level, IntPtr[] members, int count);

        public static int Run(string mode, string sid)
        {
            Paths.Init(false);
            bool on = !string.Equals(mode, "off", StringComparison.OrdinalIgnoreCase);
            try
            {
                // only a local or Microsoft account of this PC (S-1-5-21-...), never a group or a service
                if (string.IsNullOrEmpty(sid) || !System.Text.RegularExpressions.Regex.IsMatch(sid, @"^S-1-5-21(-\d+){4}$")) { Log.Write("fps-access-failed error=\"not an account SID\""); return 2; }
                var user = new SecurityIdentifier(sid);
                string group = ((NTAccount)new SecurityIdentifier(GroupSid).Translate(typeof(NTAccount))).Value; // localized name
                group = group.Substring(group.IndexOf('\\') + 1);
                var bytes = new byte[user.BinaryLength]; user.GetBinaryForm(bytes, 0);
                var pin = GCHandle.Alloc(bytes, GCHandleType.Pinned);
                int rc;
                try { var members = new[] { pin.AddrOfPinnedObject() }; rc = on ? NetLocalGroupAddMembers(null, group, 0, members, 1) : NetLocalGroupDelMembers(null, group, 0, members, 1); }
                finally { pin.Free(); }
                bool ok = rc == 0 || (on && rc == 1378 /*already a member*/) || (!on && rc == 1377 /*not a member*/);
                if (!ok) { Log.Write("fps-access-failed on=" + on + " code=" + rc); return 1; }
                if (on) { Directory.CreateDirectory(Path.GetDirectoryName(MarkerPath)); File.WriteAllText(MarkerPath, Json.Write(new Dictionary<string, object> { ["sid"] = sid, ["group"] = GroupSid, ["at"] = DateTime.Now.ToString("o") })); }
                else if (File.Exists(MarkerPath)) File.Delete(MarkerPath);
                Log.Write("fps-access " + (on ? "granted" : "removed") + " code=" + rc);
                return 0;
            }
            catch (Exception e) { Log.Write("fps-access-failed on=" + on + " error=\"" + e.Message + "\""); return 1; }
        }
    }
}
