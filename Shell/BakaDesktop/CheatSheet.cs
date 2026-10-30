using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;

namespace Baka.Desktop
{
    // The keyboard shortcut cheat sheet. Hold the Windows key for about a second (without pressing another
    // key) and it appears in the middle of the screen; it goes away when you let go. Win+/ and Win+F1 open
    // it too and keep it open until Esc, a click, or the same keys again. It never takes the keyboard focus,
    // so the app in front keeps getting what you type.
    class CheatSheet : GlassPanel
    {
        static CheatSheet current;
        public static bool IsOpen => current != null && current.IsVisible;
        bool pinned;

        // The hold is timed on the keyboard thread, not here. A UI timer was starved by the auto-repeat
        // itself: a held key sends a key-down about every 33 ms, and under that the 700 ms DispatcherTimer
        // fired late or not at all (the cheat sheet showed on only 5 of 10 held presses in a stress test).
        // The keyboard hook sees every repeat and raises "cheat-sheet-hold" once Win has been held ~700 ms;
        // these just run the open/close on the UI thread.
        public static void HoldFired() { Open(false); }
        // The Windows key came up. Returns true when the cheat sheet was showing because of the hold, so the
        // key-up does not also open the Launchpad.
        public static bool WinUp()
        {
            if (current != null && !current.pinned) { current.Close(); return true; }
            return false;
        }
        public static void Toggle()
        {
            if (IsOpen) { current.Close(); return; }
            Open(true);
        }
        static void Open(bool pin)
        {
            if (App.GameRunning) return;
            try
            {
                if (current == null) { current = new CheatSheet(); current.Closed += (o, e) => { current = null; KeyHook.CheatSheetOpen = false; }; }
                // Opened by holding Win: Windows only remembers that Win was "used" (BAKA's mask key on the
                // press) for about a second, then treats the release of a long press as a lone Win and opens its
                // Search (measured: SearchHost came to the front). BAKA marks the press as used again now,
                // while Win is still down, so the release opens nothing.
                if (!pin) KeyHook.MaskNow();
                current.pinned = pin;
                if (!current.IsVisible) { current.Show(); Ui.FadeIn(current.Frame, 140, 0.97); }
                KeyHook.CheatSheetOpen = true;
                Log.Write("cheat-sheet open pinned=" + pin);
            }
            catch (Exception e) { current = null; Log.Write("cheat-sheet-failed error=\"" + e.Message + "\""); }
        }

        CheatSheet() : base(20)
        {
            Title = "BAKA Shortcuts"; ShowActivated = false; Topmost = true; SizeToContent = SizeToContent.WidthAndHeight;
            bool explorer = ExplorerIntegration.ExplorerRunning();
            var root = new StackPanel { Margin = new Thickness(26, 20, 26, 20) };
            var head = new Grid(); head.ColumnDefinitions.Add(new ColumnDefinition()); head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var titles = new StackPanel();
            titles.Children.Add(Ui.Text("Keyboard shortcuts", 20, FontWeights.SemiBold));
            titles.Children.Add(Ui.Muted("Hold the Windows key to see this.  Win+/ keeps it open.", 11.5));
            head.Children.Add(titles);
            var close = Ui.Icon(0xE711, "Close", () => Close(), 28, 11); close.VerticalAlignment = VerticalAlignment.Top; Grid.SetColumn(close, 1); head.Children.Add(close);
            root.Children.Add(head);

            var cols = new Grid { Margin = new Thickness(0, 16, 0, 0) };
            for (int i = 0; i < 3; i++) cols.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Auto) });
            void Column(int index, params (string group, (string keys, string what)[] rows)[] groups)
            {
                var sp = new StackPanel { Margin = new Thickness(index == 0 ? 0 : 28, 0, 0, 0), MinWidth = 250 };
                foreach (var g in groups)
                {
                    var gh = Ui.Text(g.group.ToUpperInvariant(), 10.5, FontWeights.SemiBold, Theme.Accent); gh.Margin = new Thickness(0, sp.Children.Count == 0 ? 0 : 14, 0, 6); sp.Children.Add(gh);
                    foreach (var r in g.rows) sp.Children.Add(Row(r.keys, r.what));
                }
                Grid.SetColumn(sp, index); cols.Children.Add(sp);
            }
            Column(0,
                ("Open", new[] {
                    ("Win", "Launchpad (all apps, search)"),
                    ("Win + S", "Search apps"),
                    ("Win + E", "BAKA Files"),
                    ("Win + R", "Run a command"),
                    ("Win + 1 … 9", "Open the app at that place in the dock"),
                    ("Ctrl + Shift + Esc", "Task Manager"),
                }),
                ("Screenshots", new[] {
                    ("Win + Shift + S", "Snip: drag an area, click for the whole screen"),
                    ("PrintScreen", explorer ? "Windows Snipping Tool" : "Snip the screen"),
                }));
            Column(1,
                ("Windows", new[] {
                    ("Alt + Tab", "Switch to the last window (hold Alt, tap Tab)"),
                    ("Alt + Shift + Tab", "Switch backwards"),
                    ("Win + Tab", "All windows"),
                    ("Win + ← / →", "Snap to the left / right half"),
                    ("Win + ↑ / ↓", "Maximize / restore or minimize"),
                    ("Win + D", "Show the desktop (again: back)"),
                    ("Win + M", "Minimize everything"),
                    ("Alt + F4", "Close the window in front"),
                }),
                ("Focus & games", new[] {
                    ("Ctrl + Alt + D", "Focus on / off (no pop-ups)"),
                    ("Ctrl + Alt + F", "Game overlay: FPS, CPU, GPU (also in games)"),
                    ("Ctrl + Alt + G", "Leave a game mode started by hand"),
                }));
            Column(2,
                ("Panels", new[] {
                    ("Win + A  ·  Win + X", "Control Center"),
                    ("Win + N", "Notifications"),
                    ("Win + I", "Settings"),
                    ("Win + /", "This cheat sheet"),
                }),
                ("System", new[] {
                    ("Win + L", "Lock"),
                    ("Win + V", "Clipboard history" + (explorer ? "" : " (needs Explorer on)")),
                    ("Win + .", "Emoji" + (explorer ? "" : " (needs Explorer on)")),
                    ("Volume keys", "Change the volume"),
                    ("Ctrl + Alt + Del", "Sign out, switch user, Task Manager"),
                }));
            root.Children.Add(cols);
            var foot = Ui.Muted("Shortcuts change in Settings > Windows. While a game runs BAKA steps aside and Windows' own keys apply.", 11);
            foot.Margin = new Thickness(0, 16, 0, 0); root.Children.Add(foot);
            Content = root;

            Loaded += (o, e) =>
            {
                var wa = SystemParameters.WorkArea;
                Left = wa.Left + (wa.Width - ActualWidth) / 2; Top = wa.Top + (wa.Height - ActualHeight) / 2;
            };
            // closes with Esc (BAKA hears it without taking focus) or a click on it, pinned or not (an unpinned
            // one whose Win key-up was missed, e.g. Win held then L to lock, must not be stuck on screen)
            PreviewMouseLeftButtonUp += (o, e) => { if (!(e.OriginalSource is DependencyObject d && IsInside(d, close))) Close(); };
        }
        static bool IsInside(DependencyObject d, DependencyObject parent) { for (; d != null; d = VisualTreeHelper.GetParent(d)) if (d == parent) return true; return false; }
        public static void Escape() { if (IsOpen) current.Close(); }

        static FrameworkElement Row(string keys, string what)
        {
            var g = new Grid { Margin = new Thickness(0, 3, 0, 3) };
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(150) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var chips = new WrapPanel { VerticalAlignment = VerticalAlignment.Center };
            foreach (var part in keys.Split(new[] { " + " }, StringSplitOptions.None))
            {
                if (chips.Children.Count > 0) { var plus = Ui.Text("+", 10.5, null, Theme.Muted); plus.Margin = new Thickness(3, 0, 3, 0); plus.VerticalAlignment = VerticalAlignment.Center; chips.Children.Add(plus); }
                chips.Children.Add(new Border
                {
                    Child = Ui.Text(part, 11, FontWeights.SemiBold),
                    Background = Theme.B(Theme.Current.SurfaceAlt, 190), BorderBrush = Theme.B(Theme.Current.Border, 120), BorderThickness = new Thickness(1),
                    CornerRadius = new CornerRadius(6), Padding = new Thickness(7, 2, 7, 3)
                });
            }
            g.Children.Add(chips);
            var t = Ui.Text(what, 12, null, Theme.Text); t.VerticalAlignment = VerticalAlignment.Center; t.Margin = new Thickness(10, 0, 0, 0); t.MaxWidth = 280; t.TextTrimming = TextTrimming.None; t.TextWrapping = TextWrapping.Wrap;
            Grid.SetColumn(t, 1); g.Children.Add(t);
            return g;
        }
    }
}
