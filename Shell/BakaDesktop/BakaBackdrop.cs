using System;
using System.Runtime.InteropServices;

namespace Baka.Desktop
{
    // The window the video wallpaper is drawn into when BAKA is the shell. Normally the video is parented
    // into Explorer's desktop "WorkerW" window; without Explorer that window does not exist, so BAKA makes
    // its own full-screen window, kept at the very bottom of the z-order (behind every app), for the video
    // player to use. Picture and colour wallpapers go through the registry and never need this.
    static class BakaBackdrop
    {
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate IntPtr WndProc(IntPtr h, uint msg, IntPtr w, IntPtr l);
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct WNDCLASSEX { public int cbSize; public uint style; public WndProc wndProc; public int clsExtra, wndExtra; public IntPtr inst, icon, cursor, bg; public string menu, cls; public IntPtr iconSm; }
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern ushort RegisterClassEx(ref WNDCLASSEX c);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr CreateWindowEx(uint ex, string cls, string name, uint style, int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr inst, IntPtr p);
        [DllImport("user32.dll")] static extern IntPtr DefWindowProc(IntPtr h, uint msg, IntPtr w, IntPtr l);
        [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
        [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string n);

        static IntPtr host;
        static WndProc proc;

        // Back to the very bottom. Widgets also move themselves to the bottom when clicked; without this they
        // went below the wallpaper window and vanished (Explorer off, video wallpaper).
        public static void Sink()
        {
            if (host == IntPtr.Zero) return;
            Native.SetWindowPos(host, Native.HWND_BOTTOM, 0, 0, 0, 0, Native.SWP_NOMOVE | Native.SWP_NOSIZE | Native.SWP_NOACTIVATE);
        }

        // The host window, created once, covering every monitor and pinned to the bottom. Returns Zero if it
        // could not be created, so the caller falls back to a picture wallpaper.
        public static IntPtr EnsureHost()
        {
            if (host != IntPtr.Zero) return host;
            if (Paths.Preview) return IntPtr.Zero;
            try
            {
                proc = (h, m, w, l) => DefWindowProc(h, m, w, l);
                var wc = new WNDCLASSEX { cbSize = Marshal.SizeOf(typeof(WNDCLASSEX)), wndProc = proc, inst = GetModuleHandle(null), cls = "BAKA_Backdrop" };
                RegisterClassEx(ref wc);
                var v = System.Windows.Forms.SystemInformation.VirtualScreen;
                host = CreateWindowEx(
                    0x00000080 /*TOOLWINDOW*/ | 0x08000000 /*NOACTIVATE*/ | 0x00000020 /*TRANSPARENT*/,
                    "BAKA_Backdrop", "", 0x80000000 /*WS_POPUP*/,
                    v.Left, v.Top, v.Width, v.Height, IntPtr.Zero, IntPtr.Zero, GetModuleHandle(null), IntPtr.Zero);
                if (host == IntPtr.Zero) { Log.Write("backdrop-create-failed err=" + Marshal.GetLastWin32Error()); return IntPtr.Zero; }
                ShowWindow(host, 8 /*SW_SHOWNA*/);
                Native.SetWindowPos(host, Native.HWND_BOTTOM, v.Left, v.Top, v.Width, v.Height, Native.SWP_NOACTIVATE | Native.SWP_SHOWWINDOW);
                Log.Write("backdrop-created " + v.Width + "x" + v.Height);
                return host;
            }
            catch (Exception e) { Log.Write("backdrop-failed error=\"" + e.Message + "\""); return IntPtr.Zero; }
        }
    }
}
