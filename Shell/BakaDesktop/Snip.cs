using System;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Rectangle = System.Windows.Shapes.Rectangle;
using Path = System.Windows.Shapes.Path;

namespace Baka.Desktop
{
    // Win+Shift+S without Explorer (Snipping Tool is a Store app). The screen is frozen, you drag a rectangle,
    // and the part is copied to the clipboard and saved to Pictures\Screenshots. A click without dragging
    // takes the whole screen; Esc cancels.
    class Snip : Window
    {
        static Snip current;
        public static void Start()
        {
            if (current != null || App.GameRunning) return;
            try { current = new Snip(); current.Show(); current.Activate(); }
            catch (Exception e) { current = null; Log.Write("snip-failed error=\"" + e.Message + "\""); }
        }

        readonly BitmapSource shot; readonly System.Drawing.Rectangle bounds;
        readonly Canvas canvas = new Canvas(); readonly Rectangle sel; readonly Path shade;
        Point? from; double scale = 1;

        Snip()
        {
            bounds = System.Windows.Forms.Screen.PrimaryScreen.Bounds;
            using (var bmp = new System.Drawing.Bitmap(bounds.Width, bounds.Height))
            {
                using (var g = System.Drawing.Graphics.FromImage(bmp)) g.CopyFromScreen(bounds.Left, bounds.Top, 0, 0, bmp.Size);
                var h = bmp.GetHbitmap();
                try { shot = System.Windows.Interop.Imaging.CreateBitmapSourceFromHBitmap(h, IntPtr.Zero, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions()); shot.Freeze(); }
                finally { Native.DeleteObject(h); }
            }
            WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize; Topmost = true; ShowInTaskbar = false; Cursor = Cursors.Cross;
            Left = 0; Top = 0; Width = SystemParameters.PrimaryScreenWidth; Height = SystemParameters.PrimaryScreenHeight; Title = "BAKA Snip";
            canvas.Background = new ImageBrush(shot) { Stretch = Stretch.Fill };
            shade = new Path { Fill = new SolidColorBrush(Color.FromArgb(110, 0, 0, 0)) };
            sel = new Rectangle { Stroke = Theme.Accent, StrokeThickness = 1.5, Visibility = Visibility.Collapsed };
            canvas.Children.Add(shade); canvas.Children.Add(sel);
            var hint = Ui.Text("Drag to capture  ·  click for the whole screen  ·  Esc to cancel", 13, FontWeights.SemiBold, Brushes.White);
            var pill = new Border { Child = hint, Background = new SolidColorBrush(Color.FromArgb(200, 12, 12, 16)), CornerRadius = new CornerRadius(14), Padding = new Thickness(14, 6, 14, 6) };
            Canvas.SetTop(pill, 70); canvas.Children.Add(pill);
            Content = canvas;
            Loaded += (o, e) => { scale = Ui.Scale(this); Canvas.SetLeft(pill, (ActualWidth - pill.ActualWidth) / 2); Shade(new Rect()); };
            KeyDown += (o, e) => { if (e.Key == Key.Escape) Close(); };
            MouseLeftButtonDown += (o, e) => { from = e.GetPosition(canvas); CaptureMouse(); };
            MouseMove += (o, e) => { if (from == null) return; var r = new Rect(from.Value, e.GetPosition(canvas)); Canvas.SetLeft(sel, r.X); Canvas.SetTop(sel, r.Y); sel.Width = r.Width; sel.Height = r.Height; sel.Visibility = Visibility.Visible; Shade(r); };
            MouseLeftButtonUp += (o, e) =>
            {
                if (from == null) return;
                ReleaseMouseCapture();
                var r = new Rect(from.Value, e.GetPosition(canvas)); from = null;
                if (r.Width < 4 || r.Height < 4) r = new Rect(0, 0, ActualWidth, ActualHeight);
                Save(r); Close();
            };
            Closed += (o, e) => current = null;
            if (Theme.Motion) Ui.FadeIn(canvas, 120, 1.0);
        }
        void Shade(Rect r)
        {
            var all = new RectangleGeometry(new Rect(0, 0, Math.Max(1, ActualWidth), Math.Max(1, ActualHeight)));
            shade.Data = r.Width > 0 ? (Geometry)new CombinedGeometry(GeometryCombineMode.Exclude, all, new RectangleGeometry(r)) : all;
        }
        void Save(Rect r)
        {
            try
            {
                var px = new Int32Rect((int)(r.X * scale), (int)(r.Y * scale), (int)Math.Min(shot.PixelWidth - r.X * scale, r.Width * scale), (int)Math.Min(shot.PixelHeight - r.Y * scale, r.Height * scale));
                var part = new CroppedBitmap(shot, px); part.Freeze();
                // the file first: the clipboard can be held by another app (clipboard managers, Remote
                // Desktop) and then threw before anything was saved
                string dir = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "Screenshots");
                Directory.CreateDirectory(dir);
                string file = System.IO.Path.Combine(dir, "BAKA " + DateTime.Now.ToString("yyyy-MM-dd HH.mm.ss") + ".png");
                using (var fs = File.Create(file)) { var enc = new PngBitmapEncoder(); enc.Frames.Add(BitmapFrame.Create(part)); enc.Save(fs); }
                // one attempt: WPF already retries a busy clipboard about a second, and more tries froze BAKA
                bool copied = false;
                try { Clipboard.SetImage(part); copied = true; } catch { }
                Log.Write("snip-saved size=" + px.Width + "x" + px.Height + " copied=" + copied);
                Osd.Show(0xE722, copied ? "Screenshot copied · saved to Pictures\\Screenshots" : "Screenshot saved to Pictures\\Screenshots (clipboard busy)");
            }
            catch (Exception e) { Log.Write("snip-save-failed error=\"" + e.Message + "\""); }
        }
    }
}
