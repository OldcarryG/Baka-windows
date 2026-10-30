using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows.Interop;
using System.Windows.Media.Imaging;

namespace Baka.Desktop
{
    // One icon an app put in the tray.
    class TrayItem
    {
        public IntPtr Owner; public uint Id; public IntPtr HIcon; public string Tip = "";
        public uint Callback;
        public BitmapSource Image;
        public string Key => Owner.ToInt64().ToString("X") + ":" + Id;
    }

    // BAKA's own system tray. When BAKA is the shell there is no Explorer "Shell_TrayWnd", so apps that call
    // Shell_NotifyIcon (Discord, Steam, NVIDIA, driver tools...) have nowhere to put their icon. BAKA creates
    // a window of class "Shell_TrayWnd" with a "TrayNotifyWnd" child and speaks the tray protocol itself:
    // it receives add / change / remove over WM_COPYDATA, shows the icons in the status island, and sends
    // clicks back to each app so its own left-click action and right-click menu work.
    //
    // Runs when BAKA is chosen as the shell, also next to the hidden helper Explorer (see Claim: BAKA's tray
    // window stays first so apps keep sending their icons here). While Explorer is the real shell (BAKA not
    // chosen) this never runs, so Explorer owns the tray.
    static class BakaTray
    {
        public static event Action Changed;
        public static readonly List<TrayItem> Items = new List<TrayItem>();
        public static bool Running { get; private set; }

        const int WM_COPYDATA = 0x004A, WM_USER = 0x0400;
        static IntPtr host, notifyChild;
        static WndProc hostProc, notifyProc;        // kept alive
        static bool classesRegistered;
        static uint taskbarCreated;

        [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate IntPtr WndProc(IntPtr h, uint msg, IntPtr w, IntPtr l);
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct WNDCLASSEX { public int cbSize; public uint style; public WndProc wndProc; public int clsExtra, wndExtra; public IntPtr inst, icon, cursor, bg; public string menu, cls; public IntPtr iconSm; }
        [StructLayout(LayoutKind.Sequential)] struct COPYDATA { public IntPtr dwData; public int cbData; public IntPtr lpData; }
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern ushort RegisterClassEx(ref WNDCLASSEX c);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr CreateWindowEx(uint ex, string cls, string name, uint style, int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr inst, IntPtr p);
        [DllImport("user32.dll")] static extern IntPtr DefWindowProc(IntPtr h, uint msg, IntPtr w, IntPtr l);
        [DllImport("user32.dll")] static extern bool DestroyWindow(IntPtr h);
        [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
        [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
        [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string n);
        [DllImport("user32.dll")] static extern int RegisterWindowMessage(string s);
        [DllImport("user32.dll")] static extern bool SendNotifyMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);

        public static IntPtr HostHandle => host;

        // Create the tray host (idempotent). Call when BAKA becomes the shell.
        public static void Start() => Start(false);
        public static void Start(bool force)
        {
            if (Running || (Paths.Preview && !force)) return;
            try
            {
                IntPtr inst = GetModuleHandle(null);
                // The window classes are registered once per process, with delegates kept for good. A second
                // Start (after Stop) used to make new delegates while the class still pointed at the old ones,
                // which could then be collected: the next tray message would crash BAKA.
                if (!classesRegistered)
                {
                    hostProc = HostWndProc; notifyProc = NotifyWndProc;
                    // "Shell_TrayWnd" is the window apps look for with FindWindow before sending their icon.
                    var wc = new WNDCLASSEX { cbSize = Marshal.SizeOf(typeof(WNDCLASSEX)), wndProc = hostProc, inst = inst, cls = "Shell_TrayWnd" };
                    var nc = new WNDCLASSEX { cbSize = Marshal.SizeOf(typeof(WNDCLASSEX)), wndProc = notifyProc, inst = inst, cls = "TrayNotifyWnd" };
                    classesRegistered = RegisterClassEx(ref wc) != 0 && RegisterClassEx(ref nc) != 0;
                    if (!classesRegistered) Log.Write("baka-tray-class-failed err=" + Marshal.GetLastWin32Error());
                }
                host = CreateWindowEx(0x00000080 /*WS_EX_TOOLWINDOW*/, "Shell_TrayWnd", "", 0x80000000 /*WS_POPUP*/, 0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, inst, IntPtr.Zero);
                if (host == IntPtr.Zero) { Log.Write("baka-tray-create-failed err=" + Marshal.GetLastWin32Error()); return; }
                notifyChild = CreateWindowEx(0, "TrayNotifyWnd", "", 0x40000000 /*WS_CHILD*/, 0, 0, 0, 0, host, IntPtr.Zero, inst, IntPtr.Zero);
                taskbarCreated = (uint)RegisterWindowMessage("TaskbarCreated");
                Running = true;
                Log.Write("baka-tray-started host=" + host.ToInt64().ToString("X"));
                Claim(true);
            }
            catch (Exception e) { Log.Write("baka-tray-start-failed error=\"" + e.Message + "\""); }
        }

        // Apps find the tray with FindWindow("Shell_TrayWnd"), which returns the first such window in z-order.
        // While the hidden helper Explorer runs it has its own (topmost) Shell_TrayWnd, so BAKA keeps its tray
        // window at the top of the topmost band; whenever Explorer's had got in front, BAKA moves back above it
        // and asks every app to re-add its icon ("TaskbarCreated", what Explorer itself broadcasts), so the
        // icons come to BAKA's island and not to the hidden taskbar. Cheap: one FindWindow every few seconds.
        static DateTime lastBroadcast = DateTime.MinValue;
        static int claims; static bool lastClaimOk = true;
        public static bool JustBroadcast => (DateTime.Now - lastBroadcast).TotalSeconds < 3;
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindow(string cls, string title);
        [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
        public static void Claim(bool announce = false)
        {
            if (!Running || host == IntPtr.Zero) return;
            try
            {
                bool first = FindWindow("Shell_TrayWnd", null) == host;
                if (!first)
                {
                    SetWindowPos(host, (IntPtr)(-1) /*HWND_TOPMOST*/, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010 /*NOSIZE|NOMOVE|NOACTIVATE*/);
                    first = FindWindow("Shell_TrayWnd", null) == host;
                    if (claims++ < 20 || first != lastClaimOk) Log.Write("baka-tray-claimed first=" + first);
                    lastClaimOk = first;
                    announce = true;
                }
                // Asking every app to re-add its icon is done at most once every 30 s: Explorer raised its
                // tray every few seconds (measured), and a broadcast each time made every app rebuild its icon.
                if (announce && first && (DateTime.Now - lastBroadcast).TotalSeconds >= 30)
                {
                    lastBroadcast = DateTime.Now;
                    SendNotifyMessage((IntPtr)0xFFFF /*HWND_BROADCAST*/, taskbarCreated, IntPtr.Zero, IntPtr.Zero);
                }
            }
            catch (Exception e) { Log.Write("baka-tray-claim-failed error=\"" + e.Message + "\""); }
        }

        public static void Stop()
        {
            if (!Running) return;
            Running = false;
            try { if (host != IntPtr.Zero) DestroyWindow(host); } catch { }
            host = notifyChild = IntPtr.Zero;
            Items.Clear();
            Raise();
            AnnounceToExplorer();
        }
        // Apps only re-add their tray icons when "TaskbarCreated" is broadcast. After BAKA's tray host closes
        // (Leave BAKA, Quit, the supervisor giving up) the icons BAKA held must go to Explorer's tray, so they
        // are asked to re-add them there. Nothing happens if there is no Explorer taskbar to receive them.
        public static void AnnounceToExplorer()
        {
            try
            {
                if (ExplorerIntegration.ExplorerTaskbar() == IntPtr.Zero) return;
                uint msg = taskbarCreated != 0 ? taskbarCreated : (uint)RegisterWindowMessage("TaskbarCreated");
                SendNotifyMessage((IntPtr)0xFFFF /*HWND_BROADCAST*/, msg, IntPtr.Zero, IntPtr.Zero);
                Log.Write("tray-icons-returned-to-explorer");
            }
            catch { }
        }

        static IntPtr HostWndProc(IntPtr h, uint msg, IntPtr w, IntPtr l)
        {
            try
            {
                if (msg == WM_COPYDATA)
                {
                    if (OnCopyData(l)) return (IntPtr)1;
                    // Not a tray icon: app-bar registrations (SHAppBarMessage, dwData 0), icon-rectangle queries
                    // and the like. They come here because apps find "the taskbar" with FindWindow and BAKA's
                    // tray window is first. With the helper Explorer running they belong to it: BAKA passes them
                    // on unchanged and returns its answer. (They used to be dropped, so Explorer never heard of
                    // the dock and maximized apps slid under it: logged "appbar-new edge=0 ok=0".)
                    var explorer = ExplorerTray();
                    if (explorer != IntPtr.Zero && SendMessageTimeout(explorer, WM_COPYDATA, w, l, 0x0002 /*ABORTIFHUNG*/, 2000, out IntPtr r) != IntPtr.Zero) return r;
                }
            }
            catch (Exception e) { Log.Write("baka-tray-copydata-failed error=\"" + e.Message + "\""); }
            return DefWindowProc(h, msg, w, l);
        }
        [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        static readonly uint myPid = (uint)System.Diagnostics.Process.GetCurrentProcess().Id;
        static IntPtr ExplorerTray()
        {
            for (IntPtr t = FindWindowEx(IntPtr.Zero, IntPtr.Zero, "Shell_TrayWnd", null); t != IntPtr.Zero; t = FindWindowEx(IntPtr.Zero, t, "Shell_TrayWnd", null))
            { GetWindowThreadProcessId(t, out uint pid); if (pid != myPid) return t; }
            return IntPtr.Zero;
        }
        static IntPtr NotifyWndProc(IntPtr h, uint msg, IntPtr w, IntPtr l) => DefWindowProc(h, msg, w, l);

        // WM_COPYDATA with dwData==1 carries a tray change: { DWORD magic; DWORD message; NOTIFYICONDATA nid }.
        static bool OnCopyData(IntPtr lParam)
        {
            var cds = (COPYDATA)Marshal.PtrToStructure(lParam, typeof(COPYDATA));
            // at least the 8-byte header plus the icon struct up to its icon handle (offset 40 in the 64-bit
            // layout): a shorter message from any app made BAKA read past it, which .NET cannot catch
            if (cds.dwData.ToInt64() != 1 || cds.lpData == IntPtr.Zero || cds.cbData < 8 + 40) return false;
            IntPtr p = cds.lpData;
            int message = Marshal.ReadInt32(p, 4); // NIM_ADD=0 MODIFY=1 DELETE=2 SETFOCUS=3 SETVERSION=4
            int nidBytes = cds.cbData - 8;
            IntPtr nid = p + 8;
            // The icon struct is laid out for the sending app's bitness. Pick the layout whose hWnd is a real
            // window; a 64-bit app has 4 bytes of padding after cbSize that a 32-bit app does not.
            bool x64 = true;
            IntPtr owner64 = Marshal.ReadIntPtr(nid, 8);
            IntPtr owner32 = (IntPtr)Marshal.ReadInt32(nid, 4);
            if (!IsWindow(owner64) && IsWindow(owner32)) x64 = false;
            IntPtr owner = x64 ? owner64 : owner32;
            int o = x64 ? 16 : 8;                              // uID
            uint id = (uint)Marshal.ReadInt32(nid, o);
            uint flags = (uint)Marshal.ReadInt32(nid, o + 4);
            uint callback = (uint)Marshal.ReadInt32(nid, o + 8);
            IntPtr hIcon = x64 ? Marshal.ReadIntPtr(nid, 32) : (IntPtr)Marshal.ReadInt32(nid, o + 12);
            int tipOff = x64 ? 40 : 24;                        // szTip[128]
            string tip = ReadTip(nid, tipOff, nidBytes);

            // The icon is turned into a picture now, while the app waits for this message to be answered:
            // many apps destroy the icon right after Shell_NotifyIcon returns (Explorer copies it at once), so
            // converting it later found a dead or reused handle (the icon vanished or showed another app's).
            // This window procedure already runs on the UI thread, so the list is updated here too.
            BitmapSource image = (flags & 2 /*NIF_ICON*/) != 0 && hIcon != IntPtr.Zero ? FromHIcon(hIcon) : null;
            Apply(owner, id, message, flags, callback, hIcon, tip, image);
            return true;
        }
        static void Apply(IntPtr owner, uint id, int message, uint flags, uint callback, IntPtr hIcon, string tip, BitmapSource image)
        {
            const uint NIF_MESSAGE = 1, NIF_ICON = 2, NIF_TIP = 4;
            try
            {
                var hit = Items.FirstOrDefault(x => x.Owner == owner && x.Id == id);
                if (message == 2) { if (hit != null) { Items.Remove(hit); Raise(); } return; }
                if (hit == null)
                {
                    if (message != 0 && message != 1) return; // only add/modify create
                    hit = new TrayItem { Owner = owner, Id = id }; Items.Add(hit);
                }
                if ((flags & NIF_MESSAGE) != 0) hit.Callback = callback;
                if ((flags & NIF_TIP) != 0) hit.Tip = tip;
                if ((flags & NIF_ICON) != 0 && hIcon != IntPtr.Zero && image != null) { hit.HIcon = hIcon; hit.Image = image; }
                Raise();
            }
            catch (Exception e) { Log.Write("baka-tray-apply-failed error=\"" + e.Message + "\""); }
        }

        // Test only (--shellcheck): build a real NOTIFYICONDATA (64-bit layout) and run it through the exact
        // receive path, so the byte-offset parsing and the icon conversion are exercised for real.
        [DllImport("user32.dll")] static extern IntPtr LoadIcon(IntPtr inst, IntPtr name);
        public static bool ReceiveForTest()
        {
            if (host == IntPtr.Zero) return false;
            IntPtr icon = LoadIcon(IntPtr.Zero, (IntPtr)32512 /*IDI_APPLICATION*/);
            int nidSize = 1000;
            IntPtr buf = Marshal.AllocHGlobal(8 + nidSize);
            try
            {
                for (int i = 0; i < 8 + nidSize; i++) Marshal.WriteByte(buf, i, 0);
                Marshal.WriteInt32(buf, 0, 0x34753423);           // magic
                Marshal.WriteInt32(buf, 4, 0);                     // NIM_ADD
                IntPtr nid = buf + 8;
                Marshal.WriteInt32(nid, 0, nidSize);              // cbSize
                Marshal.WriteIntPtr(nid, 8, host);                // hWnd (64-bit layout: offset 8)
                Marshal.WriteInt32(nid, 16, 7);                   // uID
                Marshal.WriteInt32(nid, 20, 1 | 2 | 4);           // uFlags = MESSAGE|ICON|TIP
                Marshal.WriteInt32(nid, 24, 0x8000);              // uCallbackMessage
                Marshal.WriteIntPtr(nid, 32, icon);               // hIcon
                byte[] tip = System.Text.Encoding.Unicode.GetBytes("BAKA tray test\0");
                for (int i = 0; i < tip.Length; i++) Marshal.WriteByte(nid, 40 + i, tip[i]);
                var cds = new COPYDATA { dwData = (IntPtr)1, cbData = 8 + nidSize, lpData = buf };
                IntPtr cdsPtr = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(COPYDATA)));
                try { Marshal.StructureToPtr(cds, cdsPtr, false); OnCopyData(cdsPtr); }
                finally { Marshal.FreeHGlobal(cdsPtr); }
                var it = Items.FirstOrDefault(x => x.Id == 7);
                return it != null && it.Image != null && it.Tip == "BAKA tray test";
            }
            finally { Marshal.FreeHGlobal(buf); }
        }

        static string ReadTip(IntPtr nid, int off, int max)
        {
            // never past the end of what the app sent (a short struct used to be read 256 bytes regardless)
            try { if (off + 2 > max) return ""; int chars = Math.Min(128, (max - off) / 2); string s = Marshal.PtrToStringUni(nid + off, chars); int z = s.IndexOf('\0'); return (z >= 0 ? s.Substring(0, z) : s).Trim(); }
            catch { return ""; }
        }
        static BitmapSource FromHIcon(IntPtr hIcon)
        {
            try { var src = Imaging.CreateBitmapSourceFromHIcon(hIcon, System.Windows.Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions()); src.Freeze(); return src; }
            catch { return null; }
        }

        static void Raise() { Items.RemoveAll(i => !IsWindow(i.Owner)); try { Changed?.Invoke(); } catch { } }

        // A click on an icon: send the app the callback message it registered, as the tray protocol says.
        // lParam low word = the mouse message, high word = the icon id (for modern version-4 icons).
        public static void Click(TrayItem it, bool right)
        {
            if (it == null || it.Callback == 0 || !IsWindow(it.Owner)) return;
            uint mouse = right ? 0x0205u /*WM_RBUTTONUP*/ : 0x0202u /*WM_LBUTTONUP*/;
            try
            {
                // many apps need a button-down then up, and a foreground change so their menu can show
                SetForegroundWindow(it.Owner);
                PostMessage(it.Owner, it.Callback, (IntPtr)it.Id, (IntPtr)(right ? 0x0204 : 0x0201)); // down
                PostMessage(it.Owner, it.Callback, (IntPtr)it.Id, (IntPtr)mouse);                      // up
                if (right) PostMessage(it.Owner, it.Callback, (IntPtr)it.Id, (IntPtr)0x007B /*WM_CONTEXTMENU*/);
                Log.Write("baka-tray-click id=" + it.Id + " right=" + right);
            }
            catch { }
        }
        [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    }
}
