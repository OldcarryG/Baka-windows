using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shell;

namespace Baka.Desktop
{
    static class Ui
    {
        public static readonly FontFamily Font = new FontFamily("Segoe UI Variable Text, Segoe UI");

        // A click is a press and a release on the same element. A bare release is ignored: a window that opens
        // under the mouse (Launchpad is full screen) must not run whatever is under the cursor when a button
        // is released.
        static UIElement pressed;
        public static void OnClick(UIElement e, Action run)
        {
            e.MouseLeftButtonDown += (o, a) => pressed = e;
            e.MouseLeftButtonUp += (o, a) => { bool mine = pressed == e; pressed = null; if (mine) run(); };
            e.MouseLeave += (o, a) => { if (pressed == e) pressed = null; };
        }
        public static readonly FontFamily Display = new FontFamily("Segoe UI Variable Display, Segoe UI");
        public static readonly FontFamily Symbols = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets");

        public static TextBlock Text(string text, double size = 13, FontWeight? weight = null, Brush brush = null)
            => new TextBlock { Text = text, FontSize = size, FontWeight = weight ?? FontWeights.Normal, Foreground = brush ?? Theme.Text, FontFamily = size >= 18 ? Display : Font, TextTrimming = TextTrimming.CharacterEllipsis };
        public static TextBlock Muted(string text, double size = 11.5) { var t = Text(text, size, null, Theme.Muted); t.TextWrapping = TextWrapping.Wrap; t.TextTrimming = TextTrimming.None; return t; }
        public static TextBlock Glyph(int code, double size = 14, Brush brush = null)
            => new TextBlock { Text = char.ConvertFromUtf32(code), FontFamily = Symbols, FontSize = size, Foreground = brush ?? Theme.Text, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };

        // A pill-shaped button whose look follows the theme; hover and press are animated lightly.
        public static Button Button(object content, Action click, bool primary = false, double radius = 10, Thickness? padding = null)
        {
            var b = new Button { Content = content, Cursor = Cursors.Hand, Padding = padding ?? new Thickness(14, 7, 14, 7), Focusable = true, FocusVisualStyle = null };
            b.Template = PillTemplate(radius);
            b.Background = primary ? Theme.Accent : Theme.SurfaceAlt;
            b.BorderBrush = primary ? Theme.Accent : Theme.Border;
            b.BorderThickness = new Thickness(Theme.Current.Pop ? 1.5 : 1);
            b.Foreground = primary ? Theme.OnColor(Theme.AccentHex) : Theme.Text;
            if (content is string s) b.Content = new TextBlock { Text = s, FontFamily = Font, FontSize = 12.5, Foreground = b.Foreground, FontWeight = primary ? FontWeights.SemiBold : FontWeights.Normal };
            var normal = b.Background;
            b.MouseEnter += (o, e) => { if (!primary) b.Background = Theme.B(Theme.Current.SurfaceAlt, 255); b.Opacity = 1; };
            b.MouseLeave += (o, e) => b.Background = normal;
            b.PreviewMouseDown += (o, e) => b.RenderTransform = new ScaleTransform(0.97, 0.97, b.ActualWidth / 2, b.ActualHeight / 2);
            b.PreviewMouseUp += (o, e) => b.RenderTransform = null;
            b.MouseLeave += (o, e) => b.RenderTransform = null;
            if (click != null) b.Click += (o, e) => { try { click(); } catch (Exception ex) { Log.Write("button-failed error=\"" + ex.Message + "\""); } };
            return b;
        }
        public static Button Labeled(int glyph, string label, Action click, bool primary = false)
        {
            var sp = new StackPanel { Orientation = Orientation.Horizontal };
            sp.Children.Add(Glyph(glyph, 13, primary ? Theme.OnColor(Theme.AccentHex) : Theme.Text));
            var t = Text(label, 12.5, primary ? FontWeights.SemiBold : FontWeights.Normal, primary ? Theme.OnColor(Theme.AccentHex) : Theme.Text); t.Margin = new Thickness(8, 0, 0, 0);
            sp.Children.Add(t);
            return Button(sp, click, primary);
        }
        public static Button Icon(int glyph, string tip, Action click, double size = 32, double glyphSize = 14)
        {
            var b = Button(Glyph(glyph, glyphSize), click, false, size / 2, new Thickness(0));
            b.Width = b.Height = size; b.ToolTip = tip; b.Background = Brushes.Transparent; b.BorderThickness = new Thickness(0);
            b.MouseEnter += (o, e) => b.Background = Theme.Hover; b.MouseLeave += (o, e) => b.Background = Brushes.Transparent;
            System.Windows.Automation.AutomationProperties.SetName(b, tip);
            return b;
        }
        static readonly Dictionary<double, ControlTemplate> templates = new Dictionary<double, ControlTemplate>();
        public static ControlTemplate PillTemplate(double radius)
        {
            if (templates.TryGetValue(radius, out var t)) return t;
            t = (ControlTemplate)System.Windows.Markup.XamlReader.Parse(
                "<ControlTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' TargetType='Button'><Border CornerRadius='" + radius + "' Background='{TemplateBinding Background}' BorderBrush='{TemplateBinding BorderBrush}' BorderThickness='{TemplateBinding BorderThickness}' Padding='{TemplateBinding Padding}' SnapsToDevicePixels='True'><ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/></Border></ControlTemplate>");
            templates[radius] = t; return t;
        }

        // On/off switch.
        public static FrameworkElement Toggle(bool on, Action<bool> changed)
        {
            var track = new Border { Width = 40, Height = 22, CornerRadius = new CornerRadius(11), Cursor = Cursors.Hand, BorderThickness = new Thickness(1) };
            var knob = new Border { Width = 16, Height = 16, CornerRadius = new CornerRadius(8), HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(2, 0, 0, 0) };
            track.Child = knob;
            bool state = on;
            void Paint(bool animate)
            {
                track.Background = state ? Theme.Accent : Theme.SurfaceAlt; track.BorderBrush = state ? Theme.Accent : Theme.Border;
                knob.Background = state ? Theme.OnColor(Theme.AccentHex) : Theme.Text;
                var to = new Thickness(state ? 21 : 2, 0, 0, 0);
                if (animate && Theme.Motion) knob.BeginAnimation(FrameworkElement.MarginProperty, new ThicknessAnimation(to, TimeSpan.FromMilliseconds(140)) { EasingFunction = new QuadraticEase() });
                else { knob.BeginAnimation(FrameworkElement.MarginProperty, null); knob.Margin = to; }
            }
            Paint(false);
            track.MouseLeftButtonUp += (o, e) => { state = !state; Paint(true); changed?.Invoke(state); };
            return track;
        }

        // A row of pills for picking one of a few options (replaces the light stock ComboBox).
        public static FrameworkElement Choice(IEnumerable<string> options, string selected, Action<string> changed)
        {
            var wrap = new WrapPanel();
            var buttons = new List<Button>();
            foreach (var opt in options)
            {
                string value = opt;
                Button b = null;
                b = Button(value, () => { foreach (var x in buttons) Paint(x, x == b); changed?.Invoke(value); }, false, 9, new Thickness(12, 5, 12, 5));
                b.Margin = new Thickness(0, 0, 6, 6); b.Tag = value; buttons.Add(b);
                wrap.Children.Add(b);
            }
            foreach (var x in buttons) Paint(x, (string)x.Tag == selected);
            return wrap;
            void Paint(Button x, bool on)
            {
                x.Background = on ? Theme.Accent : Theme.SurfaceAlt; x.BorderBrush = on ? Theme.Accent : Theme.Border;
                if (x.Content is TextBlock t) { t.Foreground = on ? Theme.OnColor(Theme.AccentHex) : Theme.Text; t.FontWeight = on ? FontWeights.SemiBold : FontWeights.Normal; }
            }
        }

        public static FrameworkElement Row(string title, string description, FrameworkElement control)
        {
            var g = new Grid { Margin = new Thickness(0, 0, 0, 10) };
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var left = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 16, 0) };
            left.Children.Add(Text(title, 13, FontWeights.SemiBold));
            if (!string.IsNullOrEmpty(description)) { var d = Muted(description); d.Margin = new Thickness(0, 2, 0, 0); left.Children.Add(d); }
            g.Children.Add(left);
            if (control != null) { Grid.SetColumn(control, 1); control.VerticalAlignment = VerticalAlignment.Center; g.Children.Add(control); }
            return Card(g, new Thickness(14, 11, 14, 11));
        }
        public static Border Card(UIElement child, Thickness? padding = null) => new Border
        {
            Child = child, Padding = padding ?? new Thickness(14), CornerRadius = new CornerRadius(12), Margin = new Thickness(0, 0, 0, 8),
            Background = Theme.B(Theme.Current.SurfaceAlt, 120), BorderBrush = Theme.B(Theme.Current.Border, 60), BorderThickness = new Thickness(1)
        };
        public static FrameworkElement Heading(string title, string subtitle = null)
        {
            var sp = new StackPanel { Margin = new Thickness(0, 0, 0, 12) };
            sp.Children.Add(Text(title, 20, FontWeights.SemiBold));
            if (subtitle != null) { var m = Muted(subtitle, 12); m.Margin = new Thickness(0, 3, 0, 0); sp.Children.Add(m); }
            return sp;
        }
        public static ScrollViewer Scroll(UIElement content) => new ScrollViewer { Content = content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, Focusable = false };

        public static MenuItem Item(string header, int glyph, Action click, string gesture = null, bool enabled = true)
        {
            var m = new MenuItem { Header = header, Icon = glyph == 0 ? null : Glyph(glyph, 13), InputGestureText = gesture ?? "", IsEnabled = enabled };
            if (click != null) m.Click += (o, e) => { try { click(); } catch (Exception ex) { Log.Write("menu-failed item=\"" + header + "\" error=\"" + ex.Message + "\""); } };
            return m;
        }
        public static void ShowMenu(UIElement target, params object[] items)
        {
            var menu = new ContextMenu { PlacementTarget = target, Placement = PlacementMode.Bottom, HasDropShadow = false };
            foreach (var i in items) menu.Items.Add(i is string s && s == "-" ? new Separator() : i);
            menu.IsOpen = true;
        }

        public static void FadeIn(UIElement e, double ms = 160, double fromScale = 0.97)
        {
            if (!Theme.Motion) { e.Opacity = 1; return; }
            e.Opacity = 0;
            e.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(ms)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
            if (e is FrameworkElement fe && fromScale < 1)
            {
                var st = new ScaleTransform(fromScale, fromScale); fe.RenderTransformOrigin = new Point(0.5, 0.5); fe.RenderTransform = st;
                var a = new DoubleAnimation(1, TimeSpan.FromMilliseconds(ms + 40)) { EasingFunction = new BackEase { Amplitude = 0.25, EasingMode = EasingMode.EaseOut } };
                st.BeginAnimation(ScaleTransform.ScaleXProperty, a); st.BeginAnimation(ScaleTransform.ScaleYProperty, a);
            }
        }
        public static double Scale(Visual v) { var s = PresentationSource.FromVisual(v); return s?.CompositionTarget?.TransformToDevice.M11 ?? 1.0; }
    }

    // Small floating BAKA surfaces (dock, menus, Control Center, widgets): per-pixel transparent with the
    // Windows flyout blur behind a rounded region.
    class GlassPanel : Window
    {
        public readonly Border Frame;
        public double Radius;
        public bool ToolWindow = true;
        public IntPtr Handle { get; private set; }

        public GlassPanel(double radius = 16)
        {
            Radius = radius;
            WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = Brushes.Transparent; ResizeMode = ResizeMode.NoResize;
            ShowInTaskbar = false; FontFamily = Ui.Font; UseLayoutRounding = true; SnapsToDevicePixels = true;
            Frame = new Border { CornerRadius = new CornerRadius(radius), BorderThickness = new Thickness(1), ClipToBounds = false };
            base.Content = Frame;
            Paint();
            SourceInitialized += (o, e) =>
            {
                Handle = new WindowInteropHelper(this).Handle;
                if (ToolWindow) Native.SetWindowLongPtr(Handle, Native.GWL_EXSTYLE, new IntPtr(Native.ExStyle(Handle) | Native.WS_EX_TOOLWINDOW));
                // Windows' minimum window width (about 136 px) must not apply to these small panels. On the
                // installed VM the dock was stretched to that width after a restart, with its icons floating in
                // the middle and 150 px of screen reserved next to it.
                // WPF reads the minimum from WM_GETMINMAXINFO and keeps it; this hook runs before WPF's own
                // handler, so WPF sees 1 x 1. A resize afterwards makes Windows ask again.
                HwndSource.FromHwnd(Handle)?.AddHook((IntPtr h, int msg, IntPtr w, IntPtr l, ref bool handled) =>
                {
                    if (msg == 0x0024) { System.Runtime.InteropServices.Marshal.WriteInt32(l, 24, 1); System.Runtime.InteropServices.Marshal.WriteInt32(l, 28, 1); }
                    return IntPtr.Zero;
                });
                UpdateBlur();
            };
            SizeChanged += (o, e) => UpdateBlur();
        }
        public new object Content { get => Frame.Child; set => Frame.Child = (UIElement)value; }
        public virtual void Paint() { Frame.Background = Theme.Glass; Frame.BorderBrush = Theme.Current.Pop ? Theme.B(Theme.Current.Border, 230) : Theme.Rim; Frame.BorderThickness = new Thickness(Theme.Current.Pop ? 1.6 : 1); }
        public void UpdateBlur()
        {
            if (Handle == IntPtr.Zero) return;
            double s = Ui.Scale(this);
            int w = (int)Math.Ceiling(ActualWidth * s), h = (int)Math.Ceiling(ActualHeight * s), r = (int)Math.Round(Radius * s);
            if (w <= 0 || h <= 0) return;
            Native.SetWindowRgn(Handle, Native.CreateRoundRectRgn(0, 0, w + 1, h + 1, r * 2, r * 2), true);
            if (Theme.Current.Backdrop != "Opaque" && !App.GameRunning) Native.SetBlur(Handle, true);
        }
        // Dragging a layered window with live blur makes it trail the cursor; the blur pauses while it moves.
        public void Drag()
        {
            // While moving, the panel is a solid card instead of see-through glass: no blur that trails the
            // cursor and no flash to fully transparent (the old behaviour switched the blur off and on).
            if (Handle != IntPtr.Zero) Native.SetBlur(Handle, false);
            var glass = Frame.Background;
            Frame.Background = Theme.B(Theme.Current.Surface, 248);
            try { DragMove(); } catch { }
            Frame.Background = glass;
            UpdateBlur();
        }
        public void Pin(bool bottom) { if (Handle != IntPtr.Zero) Native.SetWindowPos(Handle, bottom ? Native.HWND_BOTTOM : Native.HWND_TOPMOST, 0, 0, 0, 0, Native.SWP_NOMOVE | Native.SWP_NOSIZE | Native.SWP_NOACTIVATE); }
    }

    // Full BAKA app windows (Files, Settings, Arena): a real Windows frame, so moving, snapping, resizing,
    // shadows and rounded corners are done by Windows itself and stay smooth. The Windows 11 acrylic
    // backdrop shows through; the title strip is drawn by BAKA.
    class AppWindow : Window
    {
        public readonly Grid Root = new Grid();
        public readonly Grid TitleBar = new Grid { Height = 44 };
        public readonly ContentControl Body = new ContentControl();
        public IntPtr Handle { get; private set; }
        readonly TextBlock title;

        public AppWindow(string caption, double width, double height)
        {
            Title = caption; Width = width; Height = height; MinWidth = 520; MinHeight = 360; FontFamily = Ui.Font;
            WindowStartupLocation = WindowStartupLocation.CenterScreen; Background = Brushes.Transparent; UseLayoutRounding = true;
            WindowChrome.SetWindowChrome(this, new WindowChrome { CaptionHeight = 44, ResizeBorderThickness = new Thickness(6), GlassFrameThickness = new Thickness(-1), CornerRadius = new CornerRadius(0), UseAeroCaptionButtons = false });
            Root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            Root.RowDefinitions.Add(new RowDefinition());
            title = Ui.Text(caption, 12.5, FontWeights.SemiBold, Theme.Muted);
            title.HorizontalAlignment = HorizontalAlignment.Center; title.VerticalAlignment = VerticalAlignment.Center; title.IsHitTestVisible = false;
            BuildTitle();
            Root.Children.Add(TitleBar);
            Grid.SetRow(Body, 1); Root.Children.Add(Body);
            Content = Root;
            SourceInitialized += (o, e) =>
            {
                Handle = new WindowInteropHelper(this).Handle;
                var src = HwndSource.FromHwnd(Handle); if (src?.CompositionTarget != null) src.CompositionTarget.BackgroundColor = Colors.Transparent;
                Native.DarkFrame(Handle); Native.RoundCorners(Handle);
                ApplyBackdrop();
            };
            StateChanged += (o, e) => Root.Margin = WindowState == WindowState.Maximized ? new Thickness(7) : new Thickness(0);
            Theme.Changed += OnTheme;
            Closed += (o, e) => Theme.Changed -= OnTheme;
            KeyDown += (o, e) => { if (e.Key == Key.Escape && CloseOnEscape) Close(); };
        }
        public bool CloseOnEscape = true;
        void OnTheme() { ApplyBackdrop(); BuildTitle(); Rebuild(); }
        public virtual void Rebuild() { }
        void ApplyBackdrop()
        {
            if (Handle == IntPtr.Zero) return;
            // Mica, not Acrylic: Acrylic re-blurs whatever is behind the window on every frame of a drag, which
            // made moving Files/Settings/Arena look smeared and laggy. Mica samples only the wallpaper, so the
            // window moves like any Windows 11 app.
            int kind = Theme.Current.Backdrop == "Opaque" ? 1 : 2; // none, Mica
            bool ok = Native.DwmSetWindowAttribute(Handle, 38, ref kind, 4) == 0 && kind != 1;
            // Tint on top of the backdrop; fully opaque when Windows has no backdrop (older builds, transparency off).
            byte a = ok ? (byte)Math.Max(120, 215 - Json.Int(App.Settings.Appearance, "glassIntensity", 34) * 2) : (byte)255;
            Root.Background = Theme.B(Theme.Current.Canvas, a);
        }
        void BuildTitle()
        {
            TitleBar.Children.Clear();
            var lights = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(16, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
            lights.Children.Add(Light("#FF5F57", 0xE8BB, "Close", Close));
            lights.Children.Add(Light("#FEBC2E", 0xE921, "Minimize", () => WindowState = WindowState.Minimized));
            lights.Children.Add(Light("#28C840", 0xE740, "Maximize", () => WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized));
            TitleBar.Children.Add(lights);
            title.Foreground = Theme.Muted;
            TitleBar.Children.Add(title);
            if (TitleExtra != null) { TitleExtra.HorizontalAlignment = HorizontalAlignment.Right; WindowChrome.SetIsHitTestVisibleInChrome(TitleExtra, true); TitleBar.Children.Add(TitleExtra); }
        }
        public FrameworkElement TitleExtra;
        public void RefreshTitle() => BuildTitle();
        FrameworkElement Light(string color, int glyph, string tip, Action click)
        {
            var mark = Ui.Glyph(glyph, 7, Theme.B("#3A1410", 220)); mark.Opacity = 0;
            var b = new Border { Width = 13, Height = 13, CornerRadius = new CornerRadius(6.5), Background = Theme.B(color), Margin = new Thickness(0, 0, 8, 0), Child = mark, Cursor = Cursors.Hand, ToolTip = tip };
            b.MouseEnter += (o, e) => mark.Opacity = 1; b.MouseLeave += (o, e) => mark.Opacity = 0;
            b.MouseLeftButtonUp += (o, e) => click();
            WindowChrome.SetIsHitTestVisibleInChrome(b, true);
            return b;
        }
    }
}
