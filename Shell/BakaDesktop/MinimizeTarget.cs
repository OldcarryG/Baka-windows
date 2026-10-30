using System;
using System.Runtime.InteropServices;

namespace Baka.Desktop
{
    // Minimize animation toward the dock. When a window minimizes, Windows asks the shell where its taskbar
    // button is (HSHELL_GETMINRECT, sent to every window registered with RegisterShellHookWindow) and animates
    // the window into that rectangle. The Windows taskbar is hidden behind BAKA, so without an answer the
    // window shrinks toward the bottom of the screen. BAKA answers with the rectangle of the app's dock icon
    // (or the dock itself), so minimizing flies into the dock and restoring grows out of it.
    static class MinimizeTarget
    {
        [DllImport("user32.dll")] static extern bool RegisterShellHookWindow(IntPtr h);
        [DllImport("user32.dll")] static extern bool DeregisterShellHookWindow(IntPtr h);
        [StructLayout(LayoutKind.Sequential)] struct MBI { public IntPtr BaseAddress, AllocationBase; public uint AllocationProtect; public IntPtr RegionSize; public uint State, Protect, Type; }
        [DllImport("kernel32.dll")] static extern IntPtr VirtualQuery(IntPtr address, out MBI info, IntPtr length);

        public static uint Message;
        static int served;
        public static bool Enabled => App.Settings == null || Json.Bool(App.Settings.Dock, "minimizeToDock", true);

        // Registered once at start and again after Explorer (the helper) starts, so BAKA's answer comes last.
        public static void Register(IntPtr h, bool again)
        {
            if (h == IntPtr.Zero || Paths.Preview) return;
            try
            {
                if (Message == 0) Message = Native.RegisterWindowMessage("SHELLHOOK");
                if (again) DeregisterShellHookWindow(h);
                bool ok = RegisterShellHookWindow(h);
                Log.Write("minimize-target registered=" + ok + (again ? " again" : ""));
            }
            catch (Exception e) { Log.Write("minimize-target-failed error=\"" + e.Message + "\""); }
        }

        // lParam points to SHELLHOOKINFO { HWND hwnd; RECT rc; }. The pointer is checked before use: reading
        // a bad pointer would end BAKA (an access violation cannot be caught in .NET Framework).
        public static IntPtr Handle(IntPtr w, IntPtr l)
        {
            try
            {
                if ((w.ToInt64() & 0x7FFF) != 5 /*HSHELL_GETMINRECT*/ || l == IntPtr.Zero) return IntPtr.Zero;
                if (!Enabled || App.GameRunning || App.Dock == null || !Writable(l, IntPtr.Size + 16)) return IntPtr.Zero;
                IntPtr hwnd = Marshal.ReadIntPtr(l);
                if (!App.Dock.TargetFor(hwnd, out var r)) return IntPtr.Zero;
                int o = IntPtr.Size;
                Marshal.WriteInt32(l, o, r.Left); Marshal.WriteInt32(l, o + 4, r.Top); Marshal.WriteInt32(l, o + 8, r.Right); Marshal.WriteInt32(l, o + 12, r.Bottom);
                if (served++ < 5) Log.Write("minimize-target served rect=" + r.Left + "," + r.Top + "-" + r.Right + "," + r.Bottom);
                return (IntPtr)1;
            }
            catch (Exception e) { Log.Write("minimize-target-error error=\"" + e.Message + "\""); return IntPtr.Zero; }
        }
        static bool Writable(IntPtr p, int size)
        {
            if (VirtualQuery(p, out var m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero) return false;
            const uint MEM_COMMIT = 0x1000, RW = 0x04 | 0x08 | 0x40 | 0x80; // READWRITE, WRITECOPY, EXECUTE_READWRITE, EXECUTE_WRITECOPY
            if (m.State != MEM_COMMIT || (m.Protect & RW) == 0 || (m.Protect & 0x100 /*GUARD*/) != 0) return false;
            long end = m.BaseAddress.ToInt64() + m.RegionSize.ToInt64();
            return p.ToInt64() + size <= end;
        }
    }
}
