using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

namespace Baka.Desktop
{
    // Win+Tab: every open window as a card with a live preview (DWM thumbnails, drawn by Windows itself, so
    // nothing is copied), its icon and title. Click one to jump straight to it; arrows + Enter work too; the
    // middle button or the x closes a window; Esc or Win+Tab again leaves.
    class Switcher : Window
    {
        static Switcher current;
        public static bool IsOpen => current != null;
        public static void Toggle()
        {
            if (current != null) { current.Close(); return; }
            if (App.BakaHidden) return;
            current = new Switcher(false); current.Show(); current.Activate();
        }

        // Alt+Tab (driven by the keyboard hook, which holds Alt): open if needed and move the selection; the
        // window does not take focus, so holding Alt keeps working. Commit activates on Alt release.
        public static void Step(bool back)
        {
            if (App.BakaHidden) return;
            if (current == null) { current = new Switcher(true); current.Show(); }
            current.Move(back ? -1 : 1);
        }
        public static void Commit() { if (current != null && current.altTab) { var w = current.Current; current.closing = true; current.Close(); if (w != null) Native.Activate(w.Handle); } }
        public static void Cancel() { if (current != null) current.Close(); }
        OpenWindow Current => selected >= 0 && selected < cards.Count ? cards[selected].w : null;
        public void Move(int d) { if (cards.Count > 0) Select((selected + d + cards.Count) % cards.Count); }
        readonly bool altTab;

        [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
        [StructLayout(LayoutKind.Sequential)] struct THUMBPROPS { public int dwFlags; public RECT rcDestination, rcSource; public byte opacity; public int fVisible, fSourceClientAreaOnly; }
        [DllImport("dwmapi.dll")] static extern int DwmRegisterThumbnail(IntPtr dest, IntPtr src, out IntPtr thumb);
        [DllImport("dwmapi.dll")] static extern int DwmUnregisterThumbnail(IntPtr thumb);
        [DllImport("dwmapi.dll")] static extern int DwmUpdateThumbnailProperties(IntPtr thumb, ref THUMBPROPS props);
        [DllImport("dwmapi.dll")] static extern int DwmQueryThumbnailSourceSize(IntPtr thumb, out SIZE size);
        [StructLayout(LayoutKind.Sequential)] struct SIZE { public int cx, cy; }

        readonly List<(OpenWindow w, Border card, Border preview, IntPtr thumb)> cards = new List<(OpenWindow, Border, Border, IntPtr)>();
        readonly WrapPanel grid = new WrapPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(60) };
        IntPtr handle; int selected;

        Switcher(bool altTab)
        {
            this.altTab = altTab;
            ShowActivated = !altTab; // Alt+Tab: never steal focus (Alt is held); Win+Tab: focus for the keyboard
            WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize; Topmost = true; ShowInTaskbar = false; AllowsTransparency = false;
            Background = new SolidColorBrush(Color.FromArgb(255, 10, 10, 14)); Title = "BAKA Windows";
            Left = 0; Top = 0; Width = SystemParameters.PrimaryScreenWidth; Height = SystemParameters.PrimaryScreenHeight;
            var root = new Grid();
            var head = Ui.Text("Windows", 20, FontWeights.SemiBold); head.Margin = new Thickness(60, 40, 0, 0); head.HorizontalAlignment = HorizontalAlignment.Left; head.VerticalAlignment = VerticalAlignment.Top;
            root.Children.Add(head);
            root.Children.Add(new ScrollViewer { Content = grid, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Margin = new Thickness(0, 70, 0, 0) });
            Content = root;
            var list = Windows.List().Where(w => w.Handle != IntPtr.Zero && Native.IsWindow(w.Handle)).ToList();
            // the window you were in comes second, so Win+Tab, Enter goes back to the previous one
            var fg = Native.GetForegroundWindow();
            list = list.OrderBy(w => w.Handle == fg ? 0 : 1).ToList();
            if (list.Count == 0) { var none = Ui.Muted("No open windows.", 14); grid.Children.Add(none); }
            foreach (var w in list) AddCard(w);
            // Win+Tab highlights the previous window so Enter flips back; Alt+Tab starts on the current one and
            // the first Tab (hook calls Move) steps to the previous.
            selected = altTab ? 0 : (list.Count > 1 ? 1 : 0);
            SourceInitialized += (o, e) => { handle = new WindowInteropHelper(this).Handle; Native.DarkFrame(handle); };
            Loaded += (o, e) => { Register(); Select(selected); };
            LayoutUpdated += (o, e) => Place();
            KeyDown += OnKey;
            // Alt+Tab keeps the switcher up while Alt is held even though it never had focus; Win+Tab closes
            // when another window is clicked.
            Deactivated += (o, e) => { if (!closing && !altTab) Close(); };
            Closing += (o, e) => closing = true;
            Closed += (o, e) => { foreach (var c in cards) if (c.thumb != IntPtr.Zero) DwmUnregisterThumbnail(c.thumb); current = null; };
            if (Theme.Motion) Ui.FadeIn(grid, 180, 0.94);
        }
        bool closing;

        void AddCard(OpenWindow w)
        {
            const double cw = 300, ph = 170;
            var sp = new StackPanel();
            var preview = new Border { Height = ph, CornerRadius = new CornerRadius(10), Background = Theme.B(Theme.Current.SurfaceAlt, 255), Margin = new Thickness(0, 0, 0, 8) };
            sp.Children.Add(preview);
            var row = new Grid(); row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); row.ColumnDefinitions.Add(new ColumnDefinition()); row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var icon = new System.Windows.Controls.Image { Width = 20, Height = 20, Margin = new Thickness(2, 0, 8, 0), Source = Icons.For(new AppRef { Name = w.Title, Exe = w.Exe, AppId = w.AppId }) };
            row.Children.Add(icon);
            var t = Ui.Text(w.Title, 12.5, FontWeights.SemiBold); t.TextTrimming = TextTrimming.CharacterEllipsis; t.VerticalAlignment = VerticalAlignment.Center; Grid.SetColumn(t, 1); row.Children.Add(t);
            var x = Ui.Icon(0xE8BB, "Close window", () => { Windows.Close(w.Handle); Remove(w); }, 24, 9); Grid.SetColumn(x, 2); row.Children.Add(x);
            sp.Children.Add(row);
            var card = new Border { Width = cw, Padding = new Thickness(10), Margin = new Thickness(10), CornerRadius = new CornerRadius(14), Background = Theme.B(Theme.Current.Surface, 255), BorderThickness = new Thickness(2), BorderBrush = Brushes.Transparent, Child = sp, Cursor = Cursors.Hand };
            card.MouseEnter += (o, e) => Select(cards.FindIndex(c => c.card == card));
            Ui.OnClick(card, () => Go(w));
            card.MouseDown += (o, e) => { if (e.ChangedButton == MouseButton.Middle) { Windows.Close(w.Handle); Remove(w); } };
            grid.Children.Add(card);
            cards.Add((w, card, preview, IntPtr.Zero));
        }
        void Remove(OpenWindow w)
        {
            int i = cards.FindIndex(c => c.w == w); if (i < 0) return;
            if (cards[i].thumb != IntPtr.Zero) DwmUnregisterThumbnail(cards[i].thumb);
            grid.Children.Remove(cards[i].card); cards.RemoveAt(i);
            if (cards.Count == 0) Close(); else Select(Math.Min(selected, cards.Count - 1));
        }
        void Register()
        {
            for (int i = 0; i < cards.Count; i++)
            {
                var c = cards[i];
                if (DwmRegisterThumbnail(handle, c.w.Handle, out IntPtr th) == 0) cards[i] = (c.w, c.card, c.preview, th);
            }
            Place();
        }
        void Place()
        {
            if (handle == IntPtr.Zero) return;
            double s = Ui.Scale(this);
            foreach (var c in cards)
            {
                if (c.thumb == IntPtr.Zero || !c.preview.IsVisible) continue;
                try
                {
                    var p = c.preview.TransformToAncestor(this).Transform(new Point(0, 0));
                    double bw = c.preview.ActualWidth, bh = c.preview.ActualHeight;
                    DwmQueryThumbnailSourceSize(c.thumb, out SIZE src);
                    double fit = src.cx > 0 && src.cy > 0 ? Math.Min(bw / src.cx, bh / src.cy) : 1;
                    double w = src.cx > 0 ? src.cx * fit : bw, h = src.cy > 0 ? src.cy * fit : bh;
                    double x = p.X + (bw - w) / 2, y = p.Y + (bh - h) / 2;
                    var props = new THUMBPROPS { dwFlags = 0x1 | 0x4 | 0x8 | 0x10, rcDestination = new RECT { L = (int)(x * s), T = (int)(y * s), R = (int)((x + w) * s), B = (int)((y + h) * s) }, opacity = 255, fVisible = 1, fSourceClientAreaOnly = 0 };
                    DwmUpdateThumbnailProperties(c.thumb, ref props);
                }
                catch { }
            }
        }
        void Select(int i)
        {
            if (cards.Count == 0 || i < 0) return;
            selected = Math.Max(0, Math.Min(cards.Count - 1, i));
            for (int k = 0; k < cards.Count; k++) cards[k].card.BorderBrush = k == selected ? Theme.Accent : Brushes.Transparent;
        }
        // the log gets the window's kind, never its title (titles hold private things: chats, sites, documents)
        void Go(OpenWindow w) { closing = true; Close(); if (w != null) { Native.Activate(w.Handle); Log.Write("switcher-go class=" + Native.ClassName(w.Handle)); } }
        void OnKey(object s, KeyEventArgs e)
        {
            int perRow = Math.Max(1, (int)((grid.ActualWidth) / 320));
            switch (e.Key)
            {
                case Key.Escape: Close(); break;
                case Key.Enter: case Key.Space: if (selected < cards.Count) Go(cards[selected].w); break;
                case Key.Right: case Key.Tab: Select((selected + 1) % Math.Max(1, cards.Count)); break;
                case Key.Left: Select((selected - 1 + cards.Count) % Math.Max(1, cards.Count)); break;
                case Key.Down: Select(selected + perRow); break;
                case Key.Up: Select(selected - perRow); break;
                case Key.Delete: if (selected < cards.Count) { var w = cards[selected].w; Windows.Close(w.Handle); Remove(w); } break;
                default: return;
            }
            e.Handled = true;
        }
    }

    // Window keys Explorer normally provides: Win+arrows snap (left / right half, maximize, restore / minimize),
    // Win+M minimizes all.
    static class WindowKeys
    {
        static IntPtr Front()
        {
            var h = Native.GetForegroundWindow();
            if (h == IntPtr.Zero) return IntPtr.Zero;
            Native.GetWindowThreadProcessId(h, out uint pid);
            if (pid == (uint)System.Diagnostics.Process.GetCurrentProcess().Id) return IntPtr.Zero; // not BAKA's own bars
            return h;
        }
        public static void Snap(string where)
        {
            var h = Front(); if (h == IntPtr.Zero) return;
            // the work area of the window's own monitor, in pixels (no DPI guess: the menu bar's scale was
            // used, which is 1 when the menu bar is off, so at 150 % a snapped window got 2/3 of the size, and
            // windows on a second monitor were moved to the first)
            var wa = Native.MonitorRect(h, true);
            int L = wa.Left, T = wa.Top, W = wa.Right - wa.Left, H = wa.Bottom - wa.Top;
            bool zoomed = Native.IsZoomed(h);
            switch (where)
            {
                case "up": Native.ShowWindow(h, 3 /*SW_MAXIMIZE*/); break;
                case "down": if (zoomed) Native.ShowWindow(h, Native.SW_RESTORE); else Native.ShowWindow(h, Native.SW_MINIMIZE); break;
                case "left": case "right":
                    if (zoomed) Native.ShowWindow(h, Native.SW_RESTORE);
                    int x = where == "left" ? L : L + W / 2;
                    Native.SetWindowPos(h, IntPtr.Zero, x, T, W / 2, H, Native.SWP_NOZORDER | Native.SWP_NOACTIVATE);
                    break;
            }
            Log.Write("window-key " + where);
        }
        static readonly List<IntPtr> minimized = new List<IntPtr>();
        public static void MinimizeAll()
        {
            minimized.Clear();
            foreach (var w in Windows.List()) if (!Native.IsIconic(w.Handle)) { minimized.Add(w.Handle); Native.ShowWindowAsync(w.Handle, Native.SW_MINIMIZE); }
            Log.Write("window-key minimize-all count=" + minimized.Count);
        }
    }
}
