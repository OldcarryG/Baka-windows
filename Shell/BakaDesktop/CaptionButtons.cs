using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Baka.Desktop
{
    // BAKA-style close / minimize / maximize buttons on every other app's window.
    //
    // No code is injected into other apps (that is what anti-cheat and antivirus software object to).
    // Instead a small BAKA window sits exactly over each window's own caption buttons: it is "owned" by
    // that window, so Windows keeps it on top of it and minimizes it with it, and a click sends the
    // window the same command its own button would (WM_SYSCOMMAND). The position comes from Windows
    // itself (DWMWA_CAPTION_BUTTON_BOUNDS) and is only used when the window's own hit test agrees that
    // its close button is there. Windows that draw their own title bar some other way, elevated
    // windows (Windows does not let a normal app send them commands), tool windows and fullscreen
    // windows keep their own buttons.
    static class CaptionButtons
    {
        static readonly Dictionary<IntPtr, CaptionOverlay> overlays = new Dictionary<IntPtr, CaptionOverlay>();
        static IntPtr hookShow, hookMove, hookForeground;
        // location changes are hooked only for the processes that have tracked windows, so BAKA is not
        // woken for every caret, cursor and window move in the system
        static readonly Dictionary<uint, IntPtr> locationHooks = new Dictionary<uint, IntPtr>();
        static readonly Dictionary<uint, bool> elevated = new Dictionary<uint, bool>();
        static Native.WinEventProc proc; // kept alive: the hook calls into it
        static readonly System.Windows.Threading.DispatcherTimer sweep = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        static readonly System.Windows.Threading.DispatcherTimer recolor = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(180) };
        public static bool Enabled { get; private set; }
        public static int Count => overlays.Count;

        public static void Apply(bool on)
        {
            if (on == Enabled) return;
            Enabled = on;
            if (on)
            {
                proc = OnEvent;
                hookShow = Native.SetWinEventHook(Native.EVENT_OBJECT_DESTROY, Native.EVENT_OBJECT_HIDE, IntPtr.Zero, proc, 0, 0, Native.WINEVENT_OUTOFCONTEXT | Native.WINEVENT_SKIPOWNPROCESS);
                hookMove = Native.SetWinEventHook(Native.EVENT_SYSTEM_MOVESIZESTART, Native.EVENT_SYSTEM_MINIMIZEEND, IntPtr.Zero, proc, 0, 0, Native.WINEVENT_OUTOFCONTEXT | Native.WINEVENT_SKIPOWNPROCESS);
                hookForeground = Native.SetWinEventHook(3 /*EVENT_SYSTEM_FOREGROUND*/, 3, IntPtr.Zero, proc, 0, 0, Native.WINEVENT_OUTOFCONTEXT | Native.WINEVENT_SKIPOWNPROCESS);
                sweep.Tick -= Sweep; sweep.Tick += Sweep;
                recolor.Tick -= Recolor; recolor.Tick += Recolor;
                if (!App.GameRunning) { sweep.Start(); Sweep(null, null); }
                Log.Write("caption-buttons on");
            }
            else
            {
                sweep.Stop(); recolor.Stop();
                foreach (var h in new[] { hookShow, hookMove, hookForeground }) if (h != IntPtr.Zero) Native.UnhookWinEvent(h);
                hookShow = hookMove = hookForeground = IntPtr.Zero;
                foreach (var h in locationHooks.Values) Native.UnhookWinEvent(h);
                locationHooks.Clear();
                foreach (var o in new List<CaptionOverlay>(overlays.Values)) o.Close();
                overlays.Clear();
                Log.Write("caption-buttons off");
            }
        }
        // While a game runs nothing here runs at all: no sweep, and the overlays are hidden.
        public static void HideAll(bool hide)
        {
            foreach (var o in overlays.Values) o.Suspended = hide;
            if (!Enabled) return;
            if (hide) { sweep.Stop(); recolor.Stop(); } else { sweep.Start(); Sweep(null, null); }
        }

        // A sweep every 2 s picks up new windows and drops closed ones. Windows already tracked are kept
        // in place by events, so the sweep does not touch them (only retries ones that are still hidden).
        static void Sweep(object s, EventArgs e)
        {
            if (!Enabled || App.GameRunning) return;
            var seen = new HashSet<IntPtr>();
            Native.EnumWindows((h, l) =>
            {
                if (overlays.TryGetValue(h, out var o)) { if (Native.IsWindowVisible(h)) { seen.Add(h); if (!o.Visible) o.Place(); } }
                else if (Eligible(h)) { seen.Add(h); Track(h); }
                return true;
            }, IntPtr.Zero);
            foreach (var h in new List<IntPtr>(overlays.Keys)) if (!seen.Contains(h)) Drop(h);
            if (elevated.Count > 400) elevated.Clear();
        }
        static void Track(IntPtr h)
        {
            if (!overlays.TryGetValue(h, out var o)) { o = new CaptionOverlay(h); overlays[h] = o; HookProcess(o.Pid); }
            o.Place();
        }
        static void Drop(IntPtr h)
        {
            if (!overlays.TryGetValue(h, out var o)) return;
            overlays.Remove(h);
            try { o.Close(); } catch { }
            bool more = false; foreach (var x in overlays.Values) if (x.Pid == o.Pid) { more = true; break; }
            if (!more && locationHooks.TryGetValue(o.Pid, out var hook)) { Native.UnhookWinEvent(hook); locationHooks.Remove(o.Pid); }
        }
        static void HookProcess(uint pid)
        {
            if (pid == 0 || locationHooks.ContainsKey(pid)) return;
            var hook = Native.SetWinEventHook(Native.EVENT_OBJECT_LOCATIONCHANGE, Native.EVENT_OBJECT_LOCATIONCHANGE, IntPtr.Zero, proc, pid, 0, Native.WINEVENT_OUTOFCONTEXT);
            if (hook != IntPtr.Zero) locationHooks[pid] = hook;
        }
        // Self-test: is there a visible overlay on a window of this class, right over its caption buttons?
        public static bool TestOverlayOn(string className, out string detail)
        {
            bool was = Enabled; if (!was) Apply(true);
            try
            {
                for (int i = 0; i < 40; i++)
                {
                    Sweep(null, null);
                    foreach (var kv in overlays)
                        if (Native.ClassName(kv.Key) == className && Native.WindowText(kv.Key).Length > 0 && kv.Value.Visible && Native.GetWindowRect(kv.Value.Handle, out var o) && Native.GetWindowRect(kv.Key, out var w))
                        { detail = $"overlay {o.Left},{o.Top}-{o.Right},{o.Bottom} on window {w.Left},{w.Top}-{w.Right},{w.Bottom}"; return o.Right <= w.Right && o.Right >= w.Right - 40 && o.Top >= w.Top && o.Top <= w.Top + 20; }
                    System.Threading.Thread.Sleep(250);
                }
                var sb = new System.Text.StringBuilder("no overlay;");
                Native.EnumWindows((h, l) => { if (Native.IsWindowVisible(h) && Native.ClassName(h) == className && Native.WindowText(h).Length > 0) sb.Append(" " + Diagnose(h)); return true; }, IntPtr.Zero);
                detail = sb.ToString(); return false;
            }
            finally { if (!was) Apply(false); }
        }
        static string Diagnose(IntPtr h)
        {
            var o = new CaptionOverlay(h);
            try { return $"[{Native.ClassName(h)} eligible={Eligible(h)} owner={Native.GetWindow(h, 4)} {o.DiagnoseBounds()}]"; }
            finally { o.Dispose(); }
        }

        // the title bar colour changes when a window becomes active or inactive; sample it again shortly after
        static void Recolor(object s, EventArgs e) { recolor.Stop(); foreach (var o in overlays.Values) o.Place(true); }

        static void OnEvent(IntPtr hook, uint ev, IntPtr h, int idObject, int idChild, uint thread, uint time)
        {
            if (ev == 3) { if (overlays.Count > 0 && !App.GameRunning) { recolor.Stop(); recolor.Start(); } return; }
            if (idObject != 0 || idChild != 0 || h == IntPtr.Zero) return; // OBJID_WINDOW only
            if (!overlays.TryGetValue(h, out var o)) { if (ev == Native.EVENT_OBJECT_SHOW && !App.GameRunning && Eligible(h)) Track(h); return; }
            switch (ev)
            {
                case Native.EVENT_OBJECT_DESTROY: case Native.EVENT_OBJECT_HIDE: Drop(h); break;
                case Native.EVENT_SYSTEM_MOVESIZESTART: case Native.EVENT_SYSTEM_MINIMIZESTART: o.Moving = true; break;
                case Native.EVENT_SYSTEM_MOVESIZEEND: case Native.EVENT_SYSTEM_MINIMIZEEND: o.Moving = false; o.Place(); break;
                default: o.Place(); break;
            }
        }

        static readonly HashSet<string> SkipClasses = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "Windows.UI.Core.CoreWindow", "XamlExplorerHostIslandWindow", "#32770" };
        static readonly int me = Process.GetCurrentProcess().Id;
        static readonly bool selfElevated = Native.IsElevated((uint)Process.GetCurrentProcess().Id);
        static bool Eligible(IntPtr h)
        {
            if (!Native.IsWindowVisible(h) || Native.IsCloaked(h) || Native.GetWindow(h, 4 /*GW_OWNER*/) != IntPtr.Zero) return false;
            long style = Native.GetWindowLongPtr(h, Native.GWL_STYLE).ToInt64(), ex = Native.ExStyle(h);
            if ((style & 0x00C00000) != 0x00C00000 /*WS_CAPTION*/ || (ex & Native.WS_EX_TOOLWINDOW) != 0) return false;
            Native.GetWindowThreadProcessId(h, out uint pid);
            // dialog-class windows (#32770) keep their own buttons: System Information is one, and its buttons
            // did not respond to BAKA's in the R13 VM test (it has a second top-level window at the same place)
            if (pid == me || SkipClasses.Contains(Native.ClassName(h))) return false;
            // Windows blocks messages from a normal app to an elevated one; when BAKA itself is elevated it can reach them
            if (selfElevated) return true;
            if (!elevated.TryGetValue(pid, out bool high)) elevated[pid] = high = Native.IsElevated(pid);
            return !high;
        }
    }

    sealed class CaptionOverlay : Form
    {
        readonly IntPtr target;
        Native.RECT bounds; // caption buttons, screen pixels
        int hover = -1;
        Color back = Color.Black;
        bool moving, suspended;
        static readonly Color[] Colors = { Color.FromArgb(0xFE, 0xBC, 0x2E), Color.FromArgb(0x28, 0xC8, 0x40), Color.FromArgb(0xFF, 0x5F, 0x57) }; // minimize, maximize, close (Windows order)

        public readonly uint Pid;
        public CaptionOverlay(IntPtr target)
        {
            this.target = target;
            Native.GetWindowThreadProcessId(target, out Pid);
            FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; StartPosition = FormStartPosition.Manual;
            DoubleBuffered = true; Text = "BAKA Caption Buttons";
            MouseMove += (o, e) => { int i = Index(e.X); if (i != hover) { hover = i; Invalidate(); } };
            MouseLeave += (o, e) => { hover = -1; Invalidate(); };
            MouseClick += (o, e) => { if (e.Button == MouseButtons.Left) Press(Index(e.X)); };
        }
        protected override CreateParams CreateParams
        {
            get
            {
                var cp = base.CreateParams;
                cp.ExStyle |= 0x08000000 /*NOACTIVATE*/ | 0x80 /*TOOLWINDOW*/;
                cp.Parent = target; // owner: stays right above the window, minimizes with it
                return cp;
            }
        }
        protected override bool ShowWithoutActivation => true;
        public bool Moving { get => moving; set { moving = value; if (value && Visible) Hide(); } }
        public bool Suspended { get => suspended; set { suspended = value; if (value) { if (Visible) Hide(); } else Place(); } }

        public void Place(bool resample = false)
        {
            if (moving || suspended || App.GameRunning || !Native.IsWindow(target) || Native.IsIconic(target)) { if (Visible) Hide(); return; }
            if (!ButtonBounds(out var b)) { if (Visible) Hide(); return; }
            bool same = Visible && b.Left == bounds.Left && b.Top == bounds.Top && b.Right == bounds.Right && b.Bottom == bounds.Bottom;
            if (same && !resample) return; // nothing moved: no repaint, no screen read
            bounds = b;
            // the title bar colour just left of the buttons (outside this window), so the patch blends in
            var c = Native.ScreenPixel(b.Left - 6, b.Top + Math.Max(4, (b.Bottom - b.Top) / 3)) ?? back;
            if (same && c == back) return;
            back = c;
            if (!same) Native.SetWindowPos(Handle, IntPtr.Zero, b.Left, b.Top, b.Right - b.Left, b.Bottom - b.Top, Native.SWP_NOACTIVATE | Native.SWP_NOZORDER | Native.SWP_SHOWWINDOW);
            if (!Visible) Show();
            Invalidate();
        }

        bool ButtonBounds(out Native.RECT screen)
        {
            screen = default;
            if (!Native.GetWindowRect(target, out var w)) return false;
            if (Native.DwmGetWindowAttribute(target, 5 /*DWMWA_CAPTION_BUTTON_BOUNDS*/, out Native.RECT rel, Marshal.SizeOf(typeof(Native.RECT))) != 0) return false;
            if (rel.Bottom - rel.Top < 16) return false;
            if (rel.Right - rel.Left < 60) return DrawnButtons(w, rel, out screen);
            // DWMWA_CAPTION_BUTTON_BOUNDS is relative to GetWindowRect (which includes the invisible resize borders).
            // Measured on Notepad: window 104..1544, buttons 1287..1433 -> right edge 1537 = the visible frame's right edge.
            screen = new Native.RECT { Left = w.Left + rel.Left, Top = w.Top + rel.Top, Right = w.Left + rel.Right, Bottom = w.Top + rel.Bottom };
            // the window itself must say its close button is there; windows with home-made title bars may not
            int x = screen.Right - 8, y = screen.Top + (screen.Bottom - screen.Top) / 2;
            var hit = Native.HitTest(target, x, y);
            if (Native.IsZoomed(target) && hit == 0) return true;
            return hit == 20 /*HTCLOSE*/;
        }

        // Store and WinUI apps (Calculator, Media Player, Settings...) draw their own caption buttons, and
        // Windows reports a zero-wide button area for them (measured: 329,0-329,30 on Calculator). Their buttons
        // are the standard 46 x 32 px (at 100%) at the right edge; that layout is used only when the window's
        // own hit test reports close, maximize and minimize at exactly those three spots.
        bool DrawnButtons(Native.RECT w, Native.RECT rel, out Native.RECT screen)
        {
            float s = DeviceDpi / 96f;
            int bw = (int)Math.Round(46 * s), h = rel.Bottom - rel.Top;
            int right = w.Left + rel.Right, top = w.Top + rel.Top, y = top + h / 2;
            screen = new Native.RECT { Left = right - 3 * bw, Top = top, Right = right, Bottom = top + h };
            int close = Native.HitTest(target, right - bw / 2, y), max = Native.HitTest(target, right - bw - bw / 2, y), min = Native.HitTest(target, right - 2 * bw - bw / 2, y);
            if (close != 20) return false;
            if (min == 8 /*HTMINBUTTON*/ && (max == 9 /*HTMAXBUTTON*/ || max == 8)) return true;
            return false;
        }
        public string DiagnoseBounds()
        {
            bool ok = ButtonBounds(out var b);
            int y = b.Top + (b.Bottom - b.Top) / 2, third = Math.Max(1, (b.Right - b.Left) / 3);
            string hit = Native.HitTest(target, b.Right - 8, y) + "/" + Native.HitTest(target, b.Right - third - third / 2, y) + "/" + Native.HitTest(target, b.Left + third / 2, y);
            return $"bounds ok={ok} {b.Left},{b.Top}-{b.Right},{b.Bottom} hit={hit} zoomed={Native.IsZoomed(target)}";
        }
        int Index(int x) { int w = Math.Max(1, Width / 3); return Math.Max(0, Math.Min(2, x / w)); }
        void Press(int i)
        {
            const int SC_MINIMIZE = 0xF020, SC_MAXIMIZE = 0xF030, SC_RESTORE = 0xF120, SC_CLOSE = 0xF060;
            int cmd = i == 0 ? SC_MINIMIZE : i == 1 ? (Native.IsZoomed(target) ? SC_RESTORE : SC_MAXIMIZE) : SC_CLOSE;
            Native.PostMessage(target, 0x0112 /*WM_SYSCOMMAND*/, new IntPtr(cmd), IntPtr.Zero);
            Log.Write("caption-button cmd=" + cmd.ToString("X"));
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(back);
            float scale = DeviceDpi / 96f, d = 13 * scale, gap = Width / 3f;
            for (int i = 0; i < 3; i++)
            {
                float cx = gap * i + gap / 2, cy = Height / 2f;
                using (var brush = new SolidBrush(Colors[i])) g.FillEllipse(brush, cx - d / 2, cy - d / 2, d, d);
                if (hover >= 0)
                {
                    using (var pen = new Pen(Color.FromArgb(200, 0x3A, 0x14, 0x10), 1.4f * scale))
                    {
                        float k = d * 0.22f;
                        if (i == 2) { g.DrawLine(pen, cx - k, cy - k, cx + k, cy + k); g.DrawLine(pen, cx - k, cy + k, cx + k, cy - k); }
                        else if (i == 0) g.DrawLine(pen, cx - k, cy, cx + k, cy);
                        else { g.DrawLine(pen, cx - k, cy, cx + k, cy); g.DrawLine(pen, cx, cy - k, cx, cy + k); }
                    }
                }
            }
        }
    }
}
