using System;
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;

namespace Baka.Desktop
{
    // Live numbers for the system widget and Arena, read straight from Windows (no WMI, no vendor tools).
    // Values that Windows does not expose on this PC are reported as unavailable, never guessed.
    class Metrics
    {
        public int? Cpu, Gpu, MemoryPercent; public double MemoryUsedGb, MemoryTotalGb, DiskFreeGb, DiskTotalGb, DownKBs, UpKBs; public int? Battery; public bool Charging;

        static long lastIdle, lastKernel, lastUser, lastRx, lastTx; static DateTime lastNet;
        static IntPtr gpuQuery, gpuCounter; static bool gpuFailed;

        public static Metrics Read()
        {
            var m = new Metrics();
            if (Native.GetSystemTimes(out long idle, out long kernel, out long user))
            {
                long di = idle - lastIdle, dt = (kernel - lastKernel) + (user - lastUser);
                if (lastKernel != 0 && dt > 0) m.Cpu = (int)Math.Round(100.0 * (dt - di) / dt);
                lastIdle = idle; lastKernel = kernel; lastUser = user;
            }
            var mem = new Native.MEMORYSTATUSEX { dwLength = (uint)Marshal.SizeOf(typeof(Native.MEMORYSTATUSEX)) };
            if (Native.GlobalMemoryStatusEx(ref mem)) { m.MemoryPercent = (int)mem.dwMemoryLoad; m.MemoryTotalGb = mem.ullTotalPhys / 1073741824.0; m.MemoryUsedGb = (mem.ullTotalPhys - mem.ullAvailPhys) / 1073741824.0; }
            try { var d = new DriveInfo(Path.GetPathRoot(Environment.SystemDirectory)); m.DiskFreeGb = d.AvailableFreeSpace / 1073741824.0; m.DiskTotalGb = d.TotalSize / 1073741824.0; } catch { }
            try
            {
                long rx = 0, tx = 0;
                foreach (var n in NetworkInterface.GetAllNetworkInterfaces().Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback))
                { var s = n.GetIPStatistics(); rx += s.BytesReceived; tx += s.BytesSent; }
                var now = DateTime.UtcNow; double sec = (now - lastNet).TotalSeconds;
                if (lastNet != DateTime.MinValue && sec > 0) { m.DownKBs = Math.Max(0, (rx - lastRx) / 1024.0 / sec); m.UpKBs = Math.Max(0, (tx - lastTx) / 1024.0 / sec); }
                lastRx = rx; lastTx = tx; lastNet = now;
            }
            catch { }
            m.Gpu = GpuPercent();
            if (Native.GetSystemPowerStatus(out var p) && p.BatteryFlag != 128 && p.BatteryLifePercent <= 100) { m.Battery = p.BatteryLifePercent; m.Charging = p.ACLineStatus == 1; }
            return m;
        }

        // Busiest GPU engine, the number Task Manager shows.
        [DllImport("pdh.dll", CharSet = CharSet.Unicode)] static extern int PdhOpenQuery(string src, IntPtr user, out IntPtr query);
        [DllImport("pdh.dll", CharSet = CharSet.Unicode)] static extern int PdhAddEnglishCounter(IntPtr query, string path, IntPtr user, out IntPtr counter);
        [DllImport("pdh.dll")] static extern int PdhCollectQueryData(IntPtr query);
        [DllImport("pdh.dll", CharSet = CharSet.Unicode)] static extern int PdhGetFormattedCounterArray(IntPtr counter, uint format, ref int bufferSize, out int count, IntPtr buffer);
        static int? GpuPercent()
        {
            if (gpuFailed) return null;
            try
            {
                if (gpuQuery == IntPtr.Zero)
                {
                    if (PdhOpenQuery(null, IntPtr.Zero, out gpuQuery) != 0 || PdhAddEnglishCounter(gpuQuery, @"\GPU Engine(*)\Utilization Percentage", IntPtr.Zero, out gpuCounter) != 0) { gpuFailed = true; return null; }
                    PdhCollectQueryData(gpuQuery); return null;
                }
                if (PdhCollectQueryData(gpuQuery) != 0) return null;
                int size = 0;
                PdhGetFormattedCounterArray(gpuCounter, 0x200, ref size, out int count, IntPtr.Zero); // PDH_FMT_DOUBLE
                if (size <= 0) return null;
                IntPtr buf = Marshal.AllocHGlobal(size);
                try
                {
                    if (PdhGetFormattedCounterArray(gpuCounter, 0x200, ref size, out count, buf) != 0) return null;
                    // PDH_FMT_COUNTERVALUE_ITEM_W: name pointer, then { status, padding, double }
                    int itemSize = IntPtr.Size + 16; double max = 0;
                    var sums = new System.Collections.Generic.Dictionary<string, double>();
                    for (int i = 0; i < count; i++)
                    {
                        IntPtr item = buf + i * itemSize;
                        string name = Marshal.PtrToStringUni(Marshal.ReadIntPtr(item)) ?? "";
                        double v = BitConverter.Int64BitsToDouble(Marshal.ReadInt64(item, IntPtr.Size + 8));
                        int at = name.IndexOf("engtype_", StringComparison.OrdinalIgnoreCase);
                        string type = at >= 0 ? name.Substring(at) : name;
                        sums[type] = (sums.TryGetValue(type, out double s) ? s : 0) + v;
                    }
                    foreach (var s in sums.Values) max = Math.Max(max, s);
                    return (int)Math.Round(Math.Min(100, max));
                }
                finally { Marshal.FreeHGlobal(buf); }
            }
            catch { gpuFailed = true; return null; }
        }
    }
}
