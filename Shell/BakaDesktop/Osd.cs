using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;

namespace Baka.Desktop
{
    // A short message bottom-centre that fades after 2 s (screenshot saved, window snapped...).
    static class Osd
    {
        public static void Show(int glyph, string text)
        {
            try
            {
                var w = new GlassPanel(16) { Title = "BAKA Message", ShowActivated = false, Topmost = true, SizeToContent = SizeToContent.WidthAndHeight };
                var sp = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(16, 12, 18, 12) };
                var g = Ui.Glyph(glyph, 16); g.VerticalAlignment = VerticalAlignment.Center; g.Margin = new Thickness(0, 0, 10, 0); sp.Children.Add(g);
                var t = Ui.Text(text, 13, FontWeights.SemiBold); t.VerticalAlignment = VerticalAlignment.Center; sp.Children.Add(t);
                w.Content = sp;
                w.Loaded += (o, e) => { w.Left = (SystemParameters.PrimaryScreenWidth - w.ActualWidth) / 2; w.Top = SystemParameters.PrimaryScreenHeight - 140; };
                w.Show(); Ui.FadeIn(w.Frame, 180, 0.94, 12);
                var life = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(2200) };
                life.Tick += (o, e) => { life.Stop(); try { w.Close(); } catch { } };
                life.Start();
            }
            catch (Exception e) { Log.Write("osd-failed error=\"" + e.Message + "\""); }
        }
    }

    // The on-screen volume bar. Without Explorer, pressing the volume keys changes nothing and shows no
    // indicator (measured). When BAKA is the shell it changes the volume itself and shows this small bar,
    // bottom-centre, that fades after a moment. Only used in shell mode.
    static class VolumeOsd
    {
        static OsdWindow win;
        public static void Key(string what)
        {
            try
            {
                int v = Audio.Level ?? 0; bool muted = Audio.Muted;
                if (what == "volmute") { muted = !muted; Audio.SetMuted(muted); }
                else { v = Math.Max(0, Math.Min(100, v + (what == "volup" ? 2 : -2))); Audio.SetLevel(v); muted = false; }
                if (win == null) { win = new OsdWindow(); win.Closed += (o, e) => win = null; }
                win.Show(v, muted);
            }
            catch (Exception e) { Log.Write("volume-osd-failed error=\"" + e.Message + "\""); }
        }

        class OsdWindow : GlassPanel
        {
            readonly TextBlock glyph, pct; readonly Border fill; readonly DispatcherTimer life;
            public OsdWindow() : base(16)
            {
                Title = "BAKA Volume"; Width = 320; Height = 64; ShowActivated = false; Topmost = true;
                var g = new Grid { Margin = new Thickness(16, 0, 16, 0) };
                g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                g.ColumnDefinitions.Add(new ColumnDefinition());
                g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(42) });
                glyph = Ui.Glyph(0xE995, 20); glyph.VerticalAlignment = VerticalAlignment.Center; g.Children.Add(glyph);
                var track = new Border { Height = 6, CornerRadius = new CornerRadius(3), Background = Theme.B(Theme.Current.SurfaceAlt, 160), Margin = new Thickness(12, 0, 12, 0), VerticalAlignment = VerticalAlignment.Center };
                fill = new Border { Height = 6, CornerRadius = new CornerRadius(3), Background = Theme.Accent, HorizontalAlignment = HorizontalAlignment.Left, Width = 0 };
                track.Child = fill; Grid.SetColumn(track, 1); g.Children.Add(track);
                pct = Ui.Text("", 14, FontWeights.SemiBold); pct.HorizontalAlignment = HorizontalAlignment.Right; pct.VerticalAlignment = VerticalAlignment.Center; Grid.SetColumn(pct, 2); g.Children.Add(pct);
                Content = g;
                Left = (SystemParameters.PrimaryScreenWidth - Width) / 2;
                Top = SystemParameters.PrimaryScreenHeight - 140;
                life = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1300) };
                life.Tick += (o, e) => { life.Stop(); try { Hide(); } catch { } };
            }
            public void Show(int v, bool muted)
            {
                glyph.Text = char.ConvertFromUtf32(muted || v == 0 ? 0xE74F : v < 34 ? 0xE993 : v < 67 ? 0xE994 : 0xE995);
                pct.Text = muted ? "Muted" : v + "%";
                double w = Math.Max(0, Width - 16 - 16 - 42 - 12 - 12);
                fill.Width = muted ? 0 : w * v / 100.0;
                if (!IsVisible) base.Show();
                life.Stop(); life.Start();
            }
        }
    }
}
