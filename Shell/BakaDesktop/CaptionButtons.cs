using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Baka.Desktop
{
    // BAKA-style close / minimize / maximize buttons on every other app's window.
    //
    // No code is injected into other apps (that is what anti-cheat and antivirus software object to).
    // Instead a small BAKA window sits exactly over each window's own caption buttons. BAKA keeps it
    // directly above that window in the z-order and hides it while the window is minimized (see
    // CaptionOverlay.KeepAbove), and a click sends the window the same command its own button would
    // (WM_SYSCOMMAND). The position comes from Windows
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
                if (!App.BakaHidden) { sweep.Start(); Sweep(null, null); }
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
        // Windows whose own buttons BAKA switched off (clean mode) but that BAKA no longer looks after: BAKA
        // closed or crashed. Their buttons are switched back on. Run at start, on exit and by the supervisor.
        public static void RestoreOrphans()
        {
            try
            {
                int n = 0;
                Native.EnumWindows((h, l) =>
                {
                    if (CaptionOverlay.GetProp(h, CaptionOverlay.Prop) == IntPtr.Zero) return true;
                    if (overlays.ContainsKey(h)) return true;
                    long style = Native.GetWindowLongPtr(h, Native.GWL_STYLE).ToInt64();
                    Native.SetWindowLongPtr(h, Native.GWL_STYLE, new IntPtr(style | 0x00080000 /*WS_SYSMENU*/));
                    Native.SetWindowPos(h, IntPtr.Zero, 0, 0, 0, 0, Native.SWP_NOMOVE | Native.SWP_NOSIZE | Native.SWP_NOZORDER | Native.SWP_NOACTIVATE | 0x0020);
                    CaptionOverlay.RemoveProp(h, CaptionOverlay.Prop); n++;
                    return true;
                }, IntPtr.Zero);
                if (n > 0) Log.Write("caption-orphans-restored count=" + n);
            }
            catch { }
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
            if (!Enabled || App.BakaHidden) return;
            try
            {
                var seen = new HashSet<IntPtr>();
                Native.EnumWindows((h, l) =>
                {
                    try
                    {
                        if (overlays.TryGetValue(h, out var o)) { if (Native.IsWindowVisible(h)) { seen.Add(h); if (!o.Visible) o.Place(); else o.KeepAbove(); } }
                        else if (Eligible(h)) { seen.Add(h); Track(h); }
                    }
                    catch { }
                    return true;
                }, IntPtr.Zero);
                foreach (var h in new List<IntPtr>(overlays.Keys)) if (!seen.Contains(h)) Drop(h);
                if (elevated.Count > 400) elevated.Clear();
                if (failed.Count > 400) failed.Clear();
            }
            catch (Exception ex) { Log.Write("caption-sweep-failed error=\"" + ex.Message + "\""); }
        }
        // Windows a button patch could not be created for (the window closed in between, or Windows refused
        // the owner): not tried again, so a failing window cannot keep BAKA busy.
        static readonly HashSet<IntPtr> failed = new HashSet<IntPtr>();
        static int tracked;
        static void Track(IntPtr h)
        {
            if (failed.Contains(h) || !Native.IsWindow(h)) return;
            try
            {
                // the window's kind and program only: window titles hold private things (chats, sites, files)
                if (!overlays.TryGetValue(h, out var o)) { o = new CaptionOverlay(h); overlays[h] = o; HookProcess(o.Pid); if (tracked++ < 40) Log.Write("caption-track class=" + Native.ClassName(h) + " app=" + ProcessName(o.Pid)); }
                o.Place();
            }
            catch (Exception e)
            {
                // R15 crashed here ("Error creating window handle") when an installer window closed while
                // BAKA was placing its buttons on it.
                failed.Add(h);
                Drop(h);
                Log.Write("caption-track-skipped error=\"" + e.Message + "\"");
            }
        }
        static void Drop(IntPtr h)
        {
            if (!overlays.TryGetValue(h, out var o)) return;
            overlays.Remove(h);
            try { o.Close(); } catch { }
            bool more = false; foreach (var x in overlays.Values) if (x.Pid == o.Pid) { more = true; break; }
            if (!more && locationHooks.TryGetValue(o.Pid, out var hook)) { Native.UnhookWinEvent(hook); locationHooks.Remove(o.Pid); }
        }
        public static string ProcessName(uint pid)
        {
            try { using (var p = System.Diagnostics.Process.GetProcessById((int)pid)) return p.ProcessName; } catch { return "?"; }
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

        // Called by Windows from outside .NET: an exception escaping here ends the whole process, so nothing may.
        static void OnEvent(IntPtr hook, uint ev, IntPtr h, int idObject, int idChild, uint thread, uint time)
        {
            try
            {
                if (!Enabled) return;
                // a window that becomes active jumps to the top, over its BAKA buttons: put them back on it at once
                if (ev == 3) { if (overlays.Count > 0 && !App.BakaHidden) { foreach (var f in overlays.Values) f.KeepAbove(); recolor.Stop(); recolor.Start(); } return; }
                if (idObject != 0 || idChild != 0 || h == IntPtr.Zero) return; // OBJID_WINDOW only
                if (!overlays.TryGetValue(h, out var o)) { if (ev == Native.EVENT_OBJECT_SHOW && !App.BakaHidden && Eligible(h)) Track(h); return; }
                switch (ev)
                {
                    case Native.EVENT_OBJECT_DESTROY: case Native.EVENT_OBJECT_HIDE: Drop(h); break;
                    case Native.EVENT_SYSTEM_MOVESIZESTART: case Native.EVENT_SYSTEM_MINIMIZESTART: o.Moving = true; break;
                    case Native.EVENT_SYSTEM_MOVESIZEEND: case Native.EVENT_SYSTEM_MINIMIZEEND: o.Moving = false; o.Place(); break;
                    default: o.Place(); break;
                }
            }
            catch (Exception e) { try { failed.Add(h); Drop(h); Log.Write("caption-event-failed error=\"" + e.Message + "\""); } catch { } }
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
        bool moving, suspended, skipLogged;
        static readonly Color[] Colors = { Color.FromArgb(0xFE, 0xBC, 0x2E), Color.FromArgb(0x28, 0xC8, 0x40), Color.FromArgb(0xFF, 0x5F, 0x57) }; // minimize, maximize, close (Windows order)

        public readonly uint Pid;
        public CaptionOverlay(IntPtr target)
        {
            this.target = target;
            Native.GetWindowThreadProcessId(target, out Pid);
            FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; StartPosition = FormStartPosition.Manual;
            DoubleBuffered = true; Text = "BAKA Caption Buttons";
            MouseMove += (o, e) => { int i = Index(e.X); if (i != hover) { hover = i; Redraw(); } };
            MouseLeave += (o, e) => { hover = -1; Redraw(); };
            MouseClick += (o, e) => { if (e.Button == MouseButtons.Left) Press(Index(e.X)); };
        }
        protected override CreateParams CreateParams
        {
            get
            {
                var cp = base.CreateParams;
                // LAYERED: drawn with per-pixel transparency (UpdateLayeredWindow), so the buttons sit on the
                // title bar as a rounded capsule instead of a square patch
                cp.ExStyle |= 0x08000000 /*NOACTIVATE*/ | 0x80 /*TOOLWINDOW*/ | 0x00080000 /*LAYERED*/;
                // No owner. "cp.Parent = target" never held: WinForms gives a form that stays out of the taskbar
                // its own hidden owner once the handle exists (measured: the overlay's owner was a hidden BAKA
                // window). And an owner in another process would attach BAKA's input queue to that app's, so a
                // hung app could stall the desktop. KeepAbove does the owner's job instead.
                return cp;
            }
        }
        protected override bool ShowWithoutActivation => true;

        // Keeps the buttons directly above their window. Without it, the window covered its BAKA buttons as soon
        // as it was clicked, and in clean mode (its own buttons switched off) it had no buttons at all: Baka
        // Browser with its tabs on the left lost its buttons a few seconds after opening (12.26.4).
        // Measured on the live desktop:
        //  - "insert after" the window just above works; HWND_TOP from BAKA (not the foreground app) is ignored
        //  - a window inserted between an app and its own windows (tooltips, menus) is pushed below the app,
        //    so the buttons go above the app's own windows too
        //  - inserted after an always-on-top window (the app is the top window), the buttons stay a normal
        //    window at the top of the normal windows, so they never float over other apps later
        static int raised;
        public void KeepAbove()
        {
            if (IsDisposed || !IsHandleCreated || !Visible || !Native.IsWindow(target)) return;
            try
            {
                bool top = (Native.ExStyle(target) & 8 /*WS_EX_TOPMOST*/) != 0;
                if (((Native.ExStyle(Handle) & 8) != 0) != top)
                    Native.SetWindowPos(Handle, top ? Native.HWND_TOPMOST : Native.HWND_NOTOPMOST, 0, 0, 0, 0, Native.SWP_NOMOVE | Native.SWP_NOSIZE | Native.SWP_NOACTIVATE);
                IntPtr above = Native.GetWindow(target, 3 /*GW_HWNDPREV*/);
                for (int n = 0; above != IntPtr.Zero && n < 200; n++)
                {
                    if (above == Handle) return; // already right above the window and its own windows
                    if (!OwnedByTarget(above)) break;
                    above = Native.GetWindow(above, 3);
                }
                // right under the first window above this app's (IntPtr.Zero = HWND_TOP when there is none)
                Native.SetWindowPos(Handle, above, 0, 0, 0, 0, Native.SWP_NOMOVE | Native.SWP_NOSIZE | Native.SWP_NOACTIVATE);
                if (raised++ < 10) Log.Write("caption-keep-above app=" + CaptionButtons.ProcessName(Pid));
            }
            catch { }
        }
        bool OwnedByTarget(IntPtr h)
        {
            for (int i = 0; i < 8 && h != IntPtr.Zero; i++) { h = Native.GetWindow(h, 4 /*GW_OWNER*/); if (h == target) return true; }
            return false;
        }
        // In clean mode the overlay follows the window while it is dragged (the window has no buttons of its own).
        public bool Moving { get => moving; set { moving = value; if (value && Visible && !clean) Hide(); } }
        public bool Suspended { get => suspended; set { suspended = value; if (value) { Restore(); if (Visible) Hide(); } else Place(); } }

        // ---- clean mode, for windows whose buttons Windows itself draws (Notepad-style title bars) ----
        // The patch approach (a small window painted over the buttons) always looked like a picture stuck on the
        // app. For these windows BAKA instead switches the window's own buttons off (its WS_SYSMENU style, the
        // same switch apps use to have no buttons) and draws its buttons straight onto the real title bar
        // with a see-through window: no patch, the title bar shows through. The style is put back when the
        // overlay goes (setting off, game, BAKA closing); a property on the window lets BAKA put it back even
        // after a crash (RestoreOrphans, at the next start and from the supervisor).
        bool clean, cleanTried, cleanZoomed;
        int offLeft, offRight, offTop, offBottom; // the buttons, measured from the window's top-right corner
        const long WS_SYSMENU = 0x00080000, WS_MINIMIZEBOX = 0x00020000, WS_MAXIMIZEBOX = 0x00010000;
        public const string Prop = "BAKA.SysMenu";
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool SetProp(IntPtr h, string name, IntPtr data);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr GetProp(IntPtr h, string name);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr RemoveProp(IntPtr h, string name);
        static bool CleanWanted => App.Settings == null || Json.Bool(App.Settings.Integration, "captionClean", true);
        static bool Cover => App.Settings != null && Json.Bool(App.Settings.Integration, "captionCover", false);

        bool TryClean()
        {
            cleanTried = true;
            if (!CleanWanted) return false;
            long style = Native.GetWindowLongPtr(target, Native.GWL_STYLE).ToInt64();
            if ((style & (WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX)) != (WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX)) return false;
            if (!Native.GetWindowRect(target, out var w)) return false;
            if (Native.DwmGetWindowAttribute(target, 5, out Native.RECT rel, Marshal.SizeOf(typeof(Native.RECT))) != 0) return false;
            if (rel.Right - rel.Left < 60 || rel.Bottom - rel.Top < 16) return false;   // Windows does not draw them: not this mode
            // Windows draws this window's buttons (and it has minimize + maximize): confirm the close button is
            // really at the right end. The exact split between the three does not matter here, because the
            // window's own buttons are switched off and BAKA's take their whole area (Baka Browser's measured
            // 20/8/2 split failed the old three-spot check and was left with a patch).
            var s = new Native.RECT { Left = w.Left + rel.Left, Top = w.Top + rel.Top, Right = w.Left + rel.Right, Bottom = w.Top + rel.Bottom };
            if (Native.HitTest(target, s.Right - 10, s.Top + (s.Bottom - s.Top) / 2) != 20 /*HTCLOSE*/) return false;
            Remember(w, s);
            SetProp(target, Prop, (IntPtr)1);
            Native.SetWindowLongPtr(target, Native.GWL_STYLE, new IntPtr(style & ~WS_SYSMENU));
            Frame(target);
            clean = true;
            Log.Write("caption-clean class=" + Native.ClassName(target));
            return true;
        }
        readonly Dictionary<bool, int[]> offsets = new Dictionary<bool, int[]>(); // per maximized / normal
        void Remember(Native.RECT w, Native.RECT s)
        {
            offLeft = w.Right - s.Left; offRight = w.Right - s.Right; offTop = s.Top - w.Top; offBottom = s.Bottom - w.Top;
            cleanZoomed = Native.IsZoomed(target);
            offsets[cleanZoomed] = new[] { offLeft, offRight, offTop, offBottom };
        }
        static void Frame(IntPtr h) => Native.SetWindowPos(h, IntPtr.Zero, 0, 0, 0, 0, Native.SWP_NOMOVE | Native.SWP_NOSIZE | Native.SWP_NOZORDER | Native.SWP_NOACTIVATE | 0x0020 /*FRAMECHANGED*/);
        // maximized and normal windows put their buttons at different offsets: measure again when it changes
        void Remeasure()
        {
            bool z = Native.IsZoomed(target);
            if (offsets.TryGetValue(z, out var known)) { offLeft = known[0]; offRight = known[1]; offTop = known[2]; offBottom = known[3]; cleanZoomed = z; return; }
            long style = Native.GetWindowLongPtr(target, Native.GWL_STYLE).ToInt64();
            Native.SetWindowLongPtr(target, Native.GWL_STYLE, new IntPtr(style | WS_SYSMENU)); Frame(target);
            if (Native.GetWindowRect(target, out var w) && Native.DwmGetWindowAttribute(target, 5, out Native.RECT rel, Marshal.SizeOf(typeof(Native.RECT))) == 0 && rel.Right - rel.Left >= 60)
                Remember(w, new Native.RECT { Left = w.Left + rel.Left, Top = w.Top + rel.Top, Right = w.Left + rel.Right, Bottom = w.Top + rel.Bottom });
            else cleanZoomed = Native.IsZoomed(target);
            Native.SetWindowLongPtr(target, Native.GWL_STYLE, new IntPtr(style & ~WS_SYSMENU)); Frame(target);
        }
        public void Restore()
        {
            if (!clean) return;
            clean = false; cleanTried = false;
            try
            {
                if (Native.IsWindow(target))
                {
                    long style = Native.GetWindowLongPtr(target, Native.GWL_STYLE).ToInt64();
                    Native.SetWindowLongPtr(target, Native.GWL_STYLE, new IntPtr(style | WS_SYSMENU)); Frame(target);
                    RemoveProp(target, Prop);
                }
            }
            catch { }
        }
        protected override void Dispose(bool disposing) { try { Restore(); } catch { } base.Dispose(disposing); }

        // Draws the buttons with real transparency (per-pixel alpha). A barely-there fill (alpha 1) keeps the
        // whole button area clickable without being visible.
        [StructLayout(LayoutKind.Sequential)] struct BLEND { public byte Op, Flags, Alpha, Format; }
        [StructLayout(LayoutKind.Sequential)] struct PT { public int X, Y; }
        [StructLayout(LayoutKind.Sequential)] struct SZ { public int W, H; }
        [DllImport("user32.dll")] static extern bool UpdateLayeredWindow(IntPtr h, IntPtr dst, ref PT pos, ref SZ size, IntPtr src, ref PT srcPos, int key, ref BLEND blend, int flags);
        [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
        [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h, IntPtr dc);
        [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
        [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
        [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc, IntPtr obj);
        [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);
        void RenderClean()
        {
            int w = Math.Max(1, bounds.Right - bounds.Left), h = Math.Max(1, bounds.Bottom - bounds.Top);
            using (var bmp = new Bitmap(w, h, System.Drawing.Imaging.PixelFormat.Format32bppArgb))
            {
                using (var g = Graphics.FromImage(bmp))
                {
                    g.Clear(Color.FromArgb(1, 0, 0, 0));
                    if (!clean)
                    {
                        // over buttons the app draws itself: a rounded capsule in the title bar's colour covers
                        // them (their symbols sit in the middle of each button, well inside the capsule)
                        g.SmoothingMode = SmoothingMode.AntiAlias;
                        float s = DeviceDpi / 96f, inset = 2 * s;
                        using (var p = Rounded(inset, inset, w - 2 * inset, h - 2 * inset, (h - 2 * inset) / 2f)) using (var b = new SolidBrush(Color.FromArgb(255, back))) g.FillPath(b, p);
                    }
                    DrawButtons(g, w, h, true);
                }
                IntPtr screen = GetDC(IntPtr.Zero), mem = CreateCompatibleDC(screen), hb = bmp.GetHbitmap(Color.FromArgb(0)), old = SelectObject(mem, hb);
                try
                {
                    var pos = new PT { X = bounds.Left, Y = bounds.Top }; var size = new SZ { W = w, H = h }; var src = new PT();
                    var blend = new BLEND { Op = 0, Flags = 0, Alpha = 255, Format = 1 /*AC_SRC_ALPHA*/ };
                    UpdateLayeredWindow(Handle, screen, ref pos, ref size, mem, ref src, 0, ref blend, 2 /*ULW_ALPHA*/);
                }
                finally { SelectObject(mem, old); DeleteObject(hb); DeleteDC(mem); ReleaseDC(IntPtr.Zero, screen); }
            }
        }
        void Redraw() { if (IsHandleCreated && bounds.Right > bounds.Left) RenderClean(); }

        public void Place(bool resample = false)
        {
            if (IsDisposed) return;
            if ((moving && !clean) || suspended || App.BakaHidden || !Native.IsWindow(target) || !Native.IsWindowVisible(target) || Native.IsIconic(target) || Native.IsCloaked(target)) { if (Visible) Hide(); return; }
            if (!clean && !cleanTried) TryClean();
            // Apps that draw their own title bar (Chromium / Electron like Discord and Kiro, and Store / WinUI
            // apps) cannot have their own buttons removed, so clean mode fails. By default BAKA leaves their
            // buttons alone instead of covering them, because an overlay reads as a patch stuck on the app.
            // "Cover other apps' buttons too" in Settings > Windows puts the overlay back for those who want it.
            if (!clean && !Cover) { if (Visible) Hide(); return; }
            if (clean && Native.IsZoomed(target) != cleanZoomed) Remeasure();
            if (!ButtonBounds(out var b))
            {
                if (Visible) Hide();
                // once per window: why it keeps its own buttons (the evidence for fixing more apps)
                if (!skipLogged) { skipLogged = true; try { Log.Write("caption-skip class=" + Native.ClassName(target) + " app=" + CaptionButtons.ProcessName(Pid) + " " + DiagnoseBounds()); } catch { } }
                return;
            }
            bool same = Visible && b.Left == bounds.Left && b.Top == bounds.Top && b.Right == bounds.Right && b.Bottom == bounds.Bottom;
            if (same && !resample) { KeepAbove(); return; } // nothing moved: no repaint, no screen read
            bounds = b;
            // the title bar colour just left of the buttons (outside this window), so the patch blends in
            // several points, the middle one by brightness: one stray pixel (a tab edge, a title letter) no
            // longer gives the patch a wrong colour that stands out from the title bar
            var samples = new List<Color>();
            int hgt = Math.Max(6, b.Bottom - b.Top);
            try
            {
                // one screen copy of the 20 px strip left of the buttons (one read, not nine)
                using (var strip = new Bitmap(20, hgt))
                {
                    using (var sg = Graphics.FromImage(strip)) sg.CopyFromScreen(b.Left - 20, b.Top, 0, 0, strip.Size);
                    foreach (int dx in new[] { 16, 10, 2 }) foreach (int dy in new[] { 3, hgt / 2, hgt - 4 }) samples.Add(strip.GetPixel(dx, Math.Max(0, Math.Min(hgt - 1, dy))));
                }
            }
            catch { var px = Native.ScreenPixel(b.Left - 6, b.Top + Math.Max(4, hgt / 3)); if (px != null) samples.Add(px.Value); }
            var c = samples.Count == 0 ? back : samples.OrderBy(x => x.R * 0.299 + x.G * 0.587 + x.B * 0.114).ElementAt(samples.Count / 2);
            if (same && c == back) { if (clean && resample) Redraw(); KeepAbove(); return; } // active / inactive: dim or brighten
            back = c;
            if (!same && !clean) Native.SetWindowPos(Handle, IntPtr.Zero, b.Left, b.Top, b.Right - b.Left, b.Bottom - b.Top, Native.SWP_NOACTIVATE | Native.SWP_NOZORDER | Native.SWP_SHOWWINDOW);
            if (!Visible) Show();
            if (clean) Native.SetWindowPos(Handle, IntPtr.Zero, b.Left, b.Top, b.Right - b.Left, b.Bottom - b.Top, Native.SWP_NOACTIVATE | Native.SWP_NOZORDER | Native.SWP_SHOWWINDOW);
            KeepAbove(); // Show() puts it at the top, over other apps that may cover this window
            Redraw();
        }

        bool ButtonBounds(out Native.RECT screen)
        {
            screen = default;
            if (!Native.GetWindowRect(target, out var w)) return false;
            if (clean)
            {
                screen = new Native.RECT { Left = w.Right - offLeft, Top = w.Top + offTop, Right = w.Right - offRight, Bottom = w.Top + offBottom };
                // Maximized, the window hangs past the work area by its invisible border (measured: window top 42,
                // visible top 50, buttons reported from 42). Start at the visible top, so the buttons sit centred in
                // the title bar instead of partly under the menu bar.
                if (cleanZoomed && Native.DwmGetWindowAttribute(target, 9 /*DWMWA_EXTENDED_FRAME_BOUNDS*/, out Native.RECT vis, Marshal.SizeOf(typeof(Native.RECT))) == 0 && vis.Top > screen.Top && vis.Top < screen.Bottom - 16)
                    screen.Top = vis.Top;
                return screen.Right - screen.Left > 20;
            }
            if (Native.DwmGetWindowAttribute(target, 5 /*DWMWA_CAPTION_BUTTON_BOUNDS*/, out Native.RECT rel, Marshal.SizeOf(typeof(Native.RECT))) != 0) return false;
            if (rel.Bottom - rel.Top < 16) return false;
            if (Measured(w, rel, out screen)) return true;
            return Scanned(w, rel, out screen);
        }

        // Apps whose buttons are not where Windows' standard layout puts them (Baka Browser, Chromium/Electron
        // apps like Kiro, apps with wider buttons): BAKA asks the window itself along its title bar
        // (WM_NCHITTEST every 3 px from the right edge) and finds close, maximize and minimize in that order.
        // The result is kept until the window changes size, so this runs once, not on every move. Apps that
        // answer "client area" everywhere (Discord handles its own buttons) still keep theirs.
        int scanW = -1, scanH = -1; bool scanZoomed, scanOk; int scanLeft, scanRight; // offsets from the window's right edge
        bool Scanned(Native.RECT w, Native.RECT rel, out Native.RECT screen)
        {
            screen = default;
            int width = w.Right - w.Left, height = w.Bottom - w.Top; bool zoomed = Native.IsZoomed(target);
            int top = w.Top + rel.Top, bottom = w.Top + rel.Bottom;
            if (width != scanW || height != scanH || zoomed != scanZoomed)
            {
                scanOk = false;
                int edge = w.Left + rel.Right - 1, y = top + (bottom - top) / 2;
                var segs = new List<(int code, int min, int max)>();
                for (int x = edge; x > edge - 320 && x > w.Left; x -= 3)
                {
                    int code = Native.HitTest(target, x, y);
                    if (code == -1) return false; // the app did not answer: try again later, cache nothing
                    if (segs.Count > 0 && segs[segs.Count - 1].code == code) segs[segs.Count - 1] = (code, x, segs[segs.Count - 1].max);
                    else segs.Add((code, x, x));
                }
                scanW = width; scanH = height; scanZoomed = zoomed;
                segs.RemoveAll(s => s.max - s.min < 6); // a pixel or two of border between buttons
                for (int i = 0; i + 2 < segs.Count; i++)
                {
                    var c = segs[i]; var m = segs[i + 1]; var n = segs[i + 2];
                    if (c.code != 20 || m.code != 9 || n.code != 8) continue;
                    bool sane = new[] { c, m, n }.All(s => s.max - s.min >= 18 && s.max - s.min <= 90);
                    if (!sane) break;
                    scanOk = true; scanRight = w.Right - (c.max + 3); scanLeft = w.Right - n.min;
                    break;
                }
            }
            if (!scanOk) return false;
            screen = new Native.RECT { Left = w.Right - scanLeft, Top = top, Right = w.Right - scanRight, Bottom = bottom };
            return screen.Right - screen.Left > 40;
        }

        bool Measured(Native.RECT w, Native.RECT rel, out Native.RECT screen)
        {
            screen = default;
            if (rel.Right - rel.Left < 60) return DrawnButtons(w, rel, out screen);
            // DWMWA_CAPTION_BUTTON_BOUNDS is relative to GetWindowRect (which includes the invisible resize borders).
            // Measured on Notepad: window 104..1544, buttons 1287..1433 -> right edge 1537 = the visible frame's right edge.
            screen = new Native.RECT { Left = w.Left + rel.Left, Top = w.Top + rel.Top, Right = w.Left + rel.Right, Bottom = w.Top + rel.Bottom };
            // Exactly three standard buttons, confirmed by the window itself at each of the three spots. Windows
            // with a help button, only a close button, or a home-made title bar keep their own buttons, so BAKA
            // never paints three circles over a different layout (R15 showed doubled and misplaced buttons).
            int width = screen.Right - screen.Left, height = screen.Bottom - screen.Top;
            if (width < height * 2.4 || width > height * 5.2) return false;
            int third = width / 3, y = screen.Top + height / 2;
            int close = Native.HitTest(target, screen.Right - third / 2, y), max = Native.HitTest(target, screen.Left + third + third / 2, y), min = Native.HitTest(target, screen.Left + third / 2, y);
            return close == 20 /*HTCLOSE*/ && max == 9 /*HTMAXBUTTON*/ && min == 8 /*HTMINBUTTON*/;
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
            return close == 20 /*HTCLOSE*/ && max == 9 /*HTMAXBUTTON*/ && min == 8 /*HTMINBUTTON*/;
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

        // Two looks (Settings > Windows > BAKA buttons style):
        //  "BAKA" (default): rounded buttons with real symbols (minimize line, maximize square / restore
        //   squares, close cross) in the title bar's own text colour, a soft rounded highlight on hover and a
        //   red one for close. Reads as part of the app instead of three coloured dots stuck on it.
        //  "Lights": the coloured circles, now with a ring and their symbols always shown.
        static string Style => App.Settings == null ? "BAKA" : Json.Str(App.Settings.Integration, "captionStyle", "BAKA");
        protected override void OnPaint(PaintEventArgs e) { } // layered: drawn by RenderClean
        protected override void OnPaintBackground(PaintEventArgs e) { }
        void DrawButtons(Graphics g, int Width, int Height, bool see)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias; g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            float scale = DeviceDpi / 96f, gap = Width / 3f, cy = Height / 2f;
            bool dark = back.R * 0.299 + back.G * 0.587 + back.B * 0.114 < 140;
            // a window in the background shows its buttons a little dimmer, like Windows does
            int a = Native.GetForegroundWindow() == target || !see ? 235 : 150;
            Color ink = dark ? Color.FromArgb(a, 240, 240, 244) : Color.FromArgb(a - 10, 24, 24, 28);
            bool zoomed = Native.IsZoomed(target);
            for (int i = 0; i < 3; i++)
            {
                float cx = gap * i + gap / 2;
                bool on = hover == i;
                if (Style == "Lights")
                {
                    float d = 14 * scale;
                    using (var brush = new SolidBrush(on ? ControlPaint.Light(Colors[i], 0.15f) : Colors[i])) g.FillEllipse(brush, cx - d / 2, cy - d / 2, d, d);
                    using (var ring = new Pen(Color.FromArgb(70, 0, 0, 0), 1f * scale)) g.DrawEllipse(ring, cx - d / 2, cy - d / 2, d, d);
                    Symbol(g, i, cx, cy, d * 0.24f, Color.FromArgb(on ? 230 : 150, 0x3A, 0x14, 0x10), 1.4f * scale, zoomed);
                }
                else
                {
                    // BAKA chips: each button is its own soft pill, always visible (Windows has bare symbols),
                    // tinted with the BAKA accent on hover; close turns red. Bolder, rounded symbols.
                    float cw = Math.Min(gap - 8 * scale, 32 * scale), ch = Math.Min(Height - 8 * scale, 22 * scale);
                    Color fill;
                    if (on) fill = i == 2 ? Color.FromArgb(245, 0xE5, 0x48, 0x4D) : Color.FromArgb(dark ? 95 : 70, Accent);
                    else fill = dark ? Color.FromArgb(28, 255, 255, 255) : Color.FromArgb(20, 0, 0, 0);
                    using (var path = Rounded(cx - cw / 2, cy - ch / 2, cw, ch, ch / 2)) using (var brush = new SolidBrush(fill)) g.FillPath(brush, path);
                    Color glyph = on && i == 2 ? Color.White : on ? (Bright(Accent) && dark ? Color.FromArgb(250, 16, 16, 20) : ink) : ink;
                    if (on && i != 2 && !dark) glyph = ink;
                    Symbol(g, i, cx, cy, 4.2f * scale, glyph, 1.7f * scale, zoomed);
                }
            }
        }
        static Color Accent
        {
            get
            {
                try { var c = (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(Theme.AccentHex); return Color.FromArgb(c.R, c.G, c.B); }
                catch { return Color.FromArgb(0x3D, 0xD6, 0xF5); }
            }
        }
        static bool Bright(Color c) => c.R * 0.299 + c.G * 0.587 + c.B * 0.114 > 170;
        static void Symbol(Graphics g, int i, float cx, float cy, float k, Color color, float width, bool zoomed)
        {
            using (var pen = new Pen(color, width) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round })
            {
                if (i == 0) g.DrawLine(pen, cx - k, cy, cx + k, cy);
                else if (i == 2) { g.DrawLine(pen, cx - k, cy - k, cx + k, cy + k); g.DrawLine(pen, cx - k, cy + k, cx + k, cy - k); }
                else if (!zoomed) using (var p = Rounded(cx - k, cy - k, 2 * k, 2 * k, k * 0.45f)) g.DrawPath(pen, p);
                else
                {
                    float s = k * 0.82f, o = k * 0.38f;
                    using (var front = Rounded(cx - k, cy - k + o, 2 * s, 2 * s, s * 0.4f)) g.DrawPath(pen, front);
                    g.DrawLine(pen, cx - k + o, cy - k, cx + k, cy - k); g.DrawLine(pen, cx + k, cy - k, cx + k, cy + k - o);
                }
            }
        }
        static GraphicsPath Rounded(float x, float y, float w, float h, float r)
        {
            var p = new GraphicsPath(); float d = Math.Min(2 * r, Math.Min(w, h));
            if (d <= 0.5f) { p.AddRectangle(new RectangleF(x, y, w, h)); return p; }
            p.AddArc(x, y, d, d, 180, 90); p.AddArc(x + w - d, y, d, d, 270, 90); p.AddArc(x + w - d, y + h - d, d, d, 0, 90); p.AddArc(x, y + h - d, d, d, 90, 90);
            p.CloseFigure(); return p;
        }
    }
}
