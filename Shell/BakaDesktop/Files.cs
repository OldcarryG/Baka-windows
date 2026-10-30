using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace Baka.Desktop
{
    // BAKA Files: the file manager. Folders opened anywhere in Windows, Win+E and the dock open here.
    // Copy, move, delete (to the Recycle Bin), rename, new folder, properties, open with, drag and drop,
    // cut/copy/paste with the Windows clipboard (so it works with every other app), search and tabs-free
    // back/forward history.
    class Files : AppWindow
    {
        static readonly List<Files> open = new List<Files>();
        readonly DateTime opened = DateTime.Now; string requested;
        string current;
        readonly Stack<string> back = new Stack<string>(), forward = new Stack<string>();
        TextBox address, filter;
        ListBox list;
        StackPanel sidebar;
        TextBlock status;
        bool showHidden;
        string sortBy = "name"; bool sortDesc;
        FileSystemWatcher watcher;
        System.Windows.Threading.DispatcherTimer reloadTimer;

        class Entry { public string Path, Name, Type; public bool Dir; public long Size; public DateTime Modified; public object Item; }

        // ---- places that are not plain folders on disk ----
        // Recycle Bin, Network, inside a .zip, libraries and shell: names are listed through the Windows shell
        // itself, inside BAKA Files. R15 handed all of them to Windows File Explorer.
        const string ShellPrefix = "shell|";
        static bool IsZip(string p) => p != null && p.EndsWith(".zip", StringComparison.OrdinalIgnoreCase) && File.Exists(p);
        static bool IsInsideZip(string p)
        {
            if (p == null) return false;
            int i = p.IndexOf(".zip\\", StringComparison.OrdinalIgnoreCase);
            return i > 0 && File.Exists(p.Substring(0, i + 4));
        }
        static bool IsShellFile(string p) => p != null && (p.EndsWith(".library-ms", StringComparison.OrdinalIgnoreCase) || p.EndsWith(".search-ms", StringComparison.OrdinalIgnoreCase));
        static bool IsShellTarget(string p) => p.StartsWith(ShellPrefix) || p.StartsWith("::") || (p.StartsWith("shell:", StringComparison.OrdinalIgnoreCase) && !Directory.Exists(p))
            || IsZip(p) || IsInsideZip(p) || IsShellFile(p) || (p.StartsWith(@"\\") && !Directory.Exists(p));
        // Control Panel and its pages are Windows' own windows; they stay with Windows.
        static bool IsControlPanel(string p) => p.IndexOf("26EE0668-A00A-44D7-9371-BEB064C98683", StringComparison.OrdinalIgnoreCase) >= 0 || p.IndexOf("21EC2020-3AEA-1069-A2DD-08002B30309D", StringComparison.OrdinalIgnoreCase) >= 0 || p.StartsWith("shell:ControlPanel", StringComparison.OrdinalIgnoreCase);
        static bool IsRecycleBin(string p) => p.IndexOf("RecycleBin", StringComparison.OrdinalIgnoreCase) >= 0 || p.IndexOf("645FF040-5081-101B-9F08-00AA002F954E", StringComparison.OrdinalIgnoreCase) >= 0;
        static dynamic shellApp;
        static dynamic ShellFolder(string target)
        {
            try
            {
                if (shellApp == null) shellApp = Activator.CreateInstance(Type.GetTypeFromProgID("Shell.Application"));
                return shellApp.NameSpace(target);
            }
            catch { return null; }
        }
        bool InShell => current != null && current.StartsWith(ShellPrefix);
        string ShellTarget => InShell ? current.Substring(ShellPrefix.Length) : null;
        string shellTitle;

        public static void Open(string path, string select = null)
        {
            if (string.IsNullOrEmpty(path)) path = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            path = Paths.Expand(path.Trim('"'));
            if (IsControlPanel(path)) { try { Process.Start(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe"), path); } catch { } return; }
            if (!IsShellTarget(path) && File.Exists(path)) { select = path; path = System.IO.Path.GetDirectoryName(path); }
            // The same folder asked for again within a moment (Win+E or a folder link pressed several times):
            // the window that just opened comes to the front instead of a pile of identical windows.
            var recent = open.LastOrDefault(x => (DateTime.Now - x.opened).TotalSeconds < 2.5 && x.requested != null && string.Equals(x.requested, path, StringComparison.OrdinalIgnoreCase));
            if (recent != null) { if (recent.WindowState == WindowState.Minimized) recent.WindowState = WindowState.Normal; recent.Activate(); return; }
            var w = new Files { requested = path }; open.Add(w); w.Closed += (o, e) => { open.Remove(w); App.Dock?.Refresh(false); };
            w.Show(); w.Activate();
            try { Native.Activate(new System.Windows.Interop.WindowInteropHelper(w).Handle); } catch { }
            w.Navigate(path, true, select);
            App.Dock?.Refresh(false);
        }
        public static void OpenItem(string path)
        {
            if (Directory.Exists(path) || IsZip(path) || IsShellFile(path)) { Open(path); return; }
            // off the UI thread: ShellExecute can block for seconds when BAKA is the shell
            Launcher.Run(path, () =>
            {
                try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true, WorkingDirectory = System.IO.Path.GetDirectoryName(path) }); Log.Write("file-opened ext=" + System.IO.Path.GetExtension(path)); }
                catch (Exception e) { if (e is System.ComponentModel.Win32Exception w && w.NativeErrorCode == 1155) Native.ShellVerb(path, "openas"); else Log.Write("file-open-failed error=\"" + e.Message + "\""); }
            });
        }
        public static Files Last => open.LastOrDefault();

        Files() : base("BAKA Files", 1140, 720)
        {
            MinWidth = 640;
            Rebuild();
            reloadTimer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(350) };
            reloadTimer.Tick += (o, e) => { reloadTimer.Stop(); Load(null); };
            Closed += (o, e) => { watcher?.Dispose(); reloadTimer.Stop(); };
            PreviewKeyDown += OnKey;
        }

        public override void Rebuild()
        {
            // toolbar in the title strip
            var tools = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 10, 0), VerticalAlignment = VerticalAlignment.Center };
            tools.Children.Add(Ui.Icon(0xE72B, "Back (Alt+Left)", () => Go(back, forward), 30, 12));
            tools.Children.Add(Ui.Icon(0xE72A, "Forward (Alt+Right)", () => Go(forward, back), 30, 12));
            tools.Children.Add(Ui.Icon(0xE74A, "Up (Alt+Up)", Up, 30, 12));
            tools.Children.Add(Ui.Icon(0xE72C, "Refresh (F5)", () => Load(null), 30, 12));
            tools.Children.Add(Ui.Icon(0xE8F4, "New folder (Ctrl+Shift+N)", NewFolder, 30, 12));
            tools.Children.Add(Ui.Icon(0xE890, "Show hidden files", () => { showHidden = !showHidden; Load(null); }, 30, 12));
            tools.Children.Add(Ui.Icon(0xE756, "Open Terminal here", () => { if (InShell || current == null) return; try { Process.Start(new ProcessStartInfo("wt.exe", "-d \"" + current + "\"") { UseShellExecute = true }); } catch { try { Process.Start(new ProcessStartInfo("powershell.exe") { WorkingDirectory = current, UseShellExecute = true }); } catch { } } }, 30, 12));
            TitleExtra = tools; RefreshTitle();

            var g = new Grid { Margin = new Thickness(0, 0, 0, 0) };
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(210) });
            g.ColumnDefinitions.Add(new ColumnDefinition());
            sidebar = new StackPanel { Margin = new Thickness(12, 4, 8, 12) };
            var side = Ui.Scroll(sidebar); g.Children.Add(side);
            BuildSidebar();

            var main = new Grid { Margin = new Thickness(4, 0, 14, 10) }; Grid.SetColumn(main, 1);
            main.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); main.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); main.RowDefinitions.Add(new RowDefinition()); main.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var bar = new Grid { Margin = new Thickness(0, 0, 0, 8) };
            bar.ColumnDefinitions.Add(new ColumnDefinition()); bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(230) });
            address = new TextBox { Text = current ?? "" }; address.KeyDown += (o, e) => { if (e.Key == Key.Enter) Navigate(address.Text, true); };
            bar.Children.Add(address);
            filter = new TextBox { Margin = new Thickness(8, 0, 0, 0) }; Grid.SetColumn(filter, 1);
            var filterHint = Ui.Text("Search this folder", 12.5, null, Theme.Muted); filterHint.IsHitTestVisible = false; filterHint.VerticalAlignment = VerticalAlignment.Center; filterHint.Margin = new Thickness(20, 0, 0, 0); Grid.SetColumn(filterHint, 1);
            filter.TextChanged += (o, e) => filterHint.Visibility = filter.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
            Panel.SetZIndex(filterHint, 1); bar.Children.Add(filterHint);
            filter.TextChanged += (o, e) => Load(null); filter.ToolTip = "Search this folder (Ctrl+F). Enter searches subfolders too.";
            filter.KeyDown += (o, e) => { if (e.Key == Key.Enter) DeepSearch(filter.Text); };
            bar.Children.Add(filter);
            main.Children.Add(bar);
            var header = Header(); Grid.SetRow(header, 1); main.Children.Add(header);
            list = new ListBox { SelectionMode = SelectionMode.Extended, AllowDrop = true, FocusVisualStyle = null };
            ScrollViewer.SetHorizontalScrollBarVisibility(list, ScrollBarVisibility.Disabled);
            VirtualizingPanel.SetIsVirtualizing(list, true); VirtualizingPanel.SetVirtualizationMode(list, VirtualizationMode.Recycling);
            list.MouseDoubleClick += (o, e) => { if (list.SelectedItem is ListBoxItem i) Activate(i.Tag as Entry); };
            list.PreviewMouseRightButtonDown += (o, e) => { var item = Ancestor<ListBoxItem>(e.OriginalSource as DependencyObject); if (item != null && !item.IsSelected) { list.SelectedItems.Clear(); item.IsSelected = true; } else if (item == null) list.SelectedItems.Clear(); };
            list.MouseRightButtonUp += (o, e) => ItemMenu();
            list.Drop += OnDrop; list.DragOver += (o, e) => { e.Effects = (e.KeyStates & DragDropKeyStates.ControlKey) != 0 ? DragDropEffects.Copy : DragDropEffects.Move; e.Handled = true; };
            list.PreviewMouseMove += StartDrag;
            list.PreviewMouseLeftButtonDown += (o, e) => BeginMarquee(e);
            list.PreviewMouseLeftButtonUp += (o, e) => EndMarquee();
            list.MouseLeave += (o, e) => { if (marqueeing && Mouse.LeftButton != MouseButtonState.Pressed) EndMarquee(); };
            var listCell = new Grid();
            listCell.Children.Add(list);
            marqueeLayer = new Canvas { IsHitTestVisible = false };
            marqueeBox = new System.Windows.Shapes.Rectangle { Visibility = Visibility.Collapsed, Fill = Theme.B(Theme.AccentHex, 40), Stroke = Theme.Accent, StrokeThickness = 1 };
            marqueeLayer.Children.Add(marqueeBox);
            listCell.Children.Add(marqueeLayer);
            Grid.SetRow(listCell, 2); main.Children.Add(listCell);
            status = Ui.Text("", 11.5, null, Theme.Muted); status.Margin = new Thickness(6, 6, 0, 0); Grid.SetRow(status, 3); main.Children.Add(status);
            g.Children.Add(main);
            Body.Content = g;
            if (current != null) Load(null);
        }

        FrameworkElement Header()
        {
            var g = Columns(); g.Margin = new Thickness(10, 0, 10, 4);
            void H(string text, string key, int col) { var t = Ui.Text(text + (sortBy == key ? (sortDesc ? "  ↓" : "  ↑") : ""), 11, FontWeights.Bold, Theme.Muted); t.Cursor = Cursors.Hand; t.MouseLeftButtonUp += (o, e) => { if (sortBy == key) sortDesc = !sortDesc; else { sortBy = key; sortDesc = key == "date" || key == "size"; } Rebuild(); }; Grid.SetColumn(t, col); g.Children.Add(t); }
            H("NAME", "name", 1); H("MODIFIED", "date", 2); H("TYPE", "type", 3); H("SIZE", "size", 4);
            return g;
        }
        static Grid Columns()
        {
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(30) }); g.ColumnDefinitions.Add(new ColumnDefinition());
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(150) }); g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(150) }); g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(90) });
            return g;
        }

        void BuildSidebar()
        {
            sidebar.Children.Clear();
            void Label(string t) { var l = Ui.Text(t, 10.5, FontWeights.Bold, Theme.Muted); l.Margin = new Thickness(8, 12, 0, 4); sidebar.Children.Add(l); }
            void Place(int glyph, string name, string path) { if (path == null) return; var b = SideItem(glyph, name); Ui.OnClick(b, () => Navigate(path, true)); b.Tag = path; sidebar.Children.Add(b); }
            string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            Label("PLACES");
            Place(0xE80F, "Home", home); Place(0xE8FC, "Desktop", Environment.GetFolderPath(Environment.SpecialFolder.Desktop));
            Place(0xE896, "Downloads", KnownDownloads()); Place(0xE8A5, "Documents", Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments));
            Place(0xEB9F, "Pictures", Environment.GetFolderPath(Environment.SpecialFolder.MyPictures)); Place(0xE8D6, "Music", Environment.GetFolderPath(Environment.SpecialFolder.MyMusic));
            Place(0xE714, "Videos", Environment.GetFolderPath(Environment.SpecialFolder.MyVideos));
            var steam = new[] { @"%ProgramFiles(x86)%\Steam\steamapps\common", @"D:\SteamLibrary\steamapps\common" }.Select(Paths.Expand).FirstOrDefault(Directory.Exists);
            if (steam != null) Place(0xE7FC, "Steam games", steam);
            Label("DRIVES");
            foreach (var d in DriveInfo.GetDrives().Where(d => d.IsReady))
            {
                string name = (string.IsNullOrEmpty(d.VolumeLabel) ? (d.DriveType == DriveType.Removable ? "USB drive" : "Local disk") : d.VolumeLabel) + " (" + d.Name.TrimEnd('\\') + ")";
                var b = SideItem(d.DriveType == DriveType.Removable ? 0xE88E : 0xEDA2, name);
                double used = 1 - (double)d.AvailableFreeSpace / Math.Max(1, d.TotalSize);
                var meter = new Border { Height = 3, CornerRadius = new CornerRadius(1.5), Background = Theme.B(Theme.Current.Border, 80), Margin = new Thickness(34, 2, 8, 2), Child = new Border { HorizontalAlignment = HorizontalAlignment.Left, Width = 140 * used, Background = used > 0.9 ? Theme.B("#E5484D") : Theme.Accent, CornerRadius = new CornerRadius(1.5) } };
                var sp = new StackPanel(); sp.Children.Add(b); sp.Children.Add(meter);
                var root = d.Name; Ui.OnClick(b, () => Navigate(root, true)); b.Tag = root;
                b.ToolTip = FormatSize(d.AvailableFreeSpace) + " free of " + FormatSize(d.TotalSize);
                sidebar.Children.Add(sp);
            }
            Label("MORE");
            foreach (var (glyph, name, target) in new[] { (0xE74D, "Recycle Bin", "shell:RecycleBinFolder"), (0xE968, "Network", "shell:NetworkPlacesFolder") })
            {
                var b = SideItem(glyph, name); string t = target;
                Ui.OnClick(b, () => Navigate(t, true)); b.Tag = ShellPrefix + t; sidebar.Children.Add(b);
            }
        }
        static string KnownDownloads() { var p = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads"); return Directory.Exists(p) ? p : null; }
        Border SideItem(int glyph, string name)
        {
            var sp = new StackPanel { Orientation = Orientation.Horizontal };
            sp.Children.Add(Ui.Glyph(glyph, 14, Theme.Accent)); var t = Ui.Text(name, 12.5); t.Margin = new Thickness(12, 0, 0, 0); t.MaxWidth = 140; sp.Children.Add(t);
            var b = new Border { Child = sp, Padding = new Thickness(10, 7, 8, 7), CornerRadius = new CornerRadius(8), Background = Brushes.Transparent, Cursor = Cursors.Hand };
            b.MouseEnter += (o, e) => { if (!Equals(b.Tag, current)) b.Background = Theme.Hover; }; b.MouseLeave += (o, e) => HighlightSidebar();
            return b;
        }
        void HighlightSidebar()
        {
            foreach (var b in sidebar.Children.OfType<FrameworkElement>().Select(e => e is StackPanel sp ? sp.Children[0] as Border : e as Border).Where(b => b != null))
                b.Background = b.Tag is string p && current != null && string.Equals(p.TrimEnd('\\'), current.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase) ? Theme.B(Theme.AccentHex, 46) : Brushes.Transparent;
        }

        // ---- navigation ----
        public void Navigate(string path, bool remember, string select = null)
        {
            path = Paths.Expand((path ?? "").Trim().Trim('"'));
            if (path.StartsWith(ShellPrefix)) path = path.Substring(ShellPrefix.Length);
            if (InShell && string.Equals(path, shellTitle, StringComparison.OrdinalIgnoreCase)) { Load(null); return; } // Enter in the address bar
            if (IsControlPanel(path)) { Open(path); return; }
            if (IsShellTarget(path)) { NavigateShell(path, remember); return; }
            if (path.Length == 2 && path[1] == ':') path += "\\";
            if (!Directory.Exists(path)) { if (File.Exists(path)) { OpenItem(path); return; } MessageBox.Show(this, "BAKA Files cannot find\n" + path, "BAKA Files", MessageBoxButton.OK, MessageBoxImage.Information); if (address != null) address.Text = current; return; }
            if (remember && current != null && !string.Equals(current, path, StringComparison.OrdinalIgnoreCase)) { back.Push(current); forward.Clear(); }
            current = path;
            if (filter != null && filter.Text.Length > 0) filter.Text = "";
            Title = (Path.GetFileName(path.TrimEnd('\\')) is string n && n.Length > 0 ? n : path) + " – BAKA Files";
            Watch();
            Load(select);
            HighlightSidebar();
        }
        void NavigateShell(string target, bool remember)
        {
            dynamic folder = ShellFolder(target);
            if (folder == null) { MessageBox.Show(this, "BAKA Files cannot open\n" + target, "BAKA Files", MessageBoxButton.OK, MessageBoxImage.Information); if (address != null) address.Text = InShell ? shellTitle : current; return; }
            // a shell name for an ordinary folder (shell:Downloads, a library's folder): the normal folder view
            try { string real = folder.Self.Path; if (!IsRecycleBin(target) && !IsZip(real) && !IsInsideZip(real) && Directory.Exists(real)) { Navigate(real, remember); return; } } catch { }
            string key = ShellPrefix + target;
            if (remember && current != null && !string.Equals(current, key, StringComparison.OrdinalIgnoreCase)) { back.Push(current); forward.Clear(); }
            current = key;
            try { shellTitle = folder.Title; } catch { shellTitle = target; }
            watcher?.Dispose(); watcher = null;
            if (filter != null && filter.Text.Length > 0) filter.Text = "";
            Title = shellTitle + " – BAKA Files";
            Load(null);
            HighlightSidebar();
        }
        void Go(Stack<string> from, Stack<string> to) { if (from.Count == 0) return; to.Push(current); var p = from.Pop(); Navigate(p, false); }
        void Up()
        {
            if (InShell)
            {
                string t = ShellTarget;
                if (IsZip(t) || IsInsideZip(t)) Navigate(Path.GetDirectoryName(t), true, IsZip(t) ? t : null);
                else Navigate(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), true);
                return;
            }
            var parent = Directory.GetParent(current.TrimEnd('\\') + (current.EndsWith(":\\") ? "\\" : "")); if (parent != null) Navigate(parent.FullName, true, current);
        }
        void Activate(Entry e)
        {
            if (e == null) return;
            if (InShell) { ActivateShell(e); return; }
            if (e.Dir) { Navigate(e.Path, true); return; }
            if (IsZip(e.Path) || IsShellFile(e.Path)) { NavigateShell(e.Path, true); return; }
            // a shortcut to a folder opens the folder here, not in a new window
            if (e.Path.EndsWith(".lnk", StringComparison.OrdinalIgnoreCase)) { var t = AppCatalog.ShortcutTarget(e.Path); if (t != null && Directory.Exists(t)) { Navigate(t, true); return; } }
            OpenItem(e.Path);
        }
        void ActivateShell(Entry e)
        {
            dynamic item = e.Item;
            try
            {
                if (IsRecycleBin(ShellTarget)) { item.InvokeVerb("properties"); return; } // like Windows: a deleted item shows where it came from
                if (e.Dir)
                {
                    string p = e.Path ?? "";
                    if (Directory.Exists(p) && !IsInsideZip(p)) Navigate(p, true); else NavigateShell(p, true);
                    return;
                }
                item.InvokeVerb(); // a file inside a .zip: Windows copies it out and opens it with its app
                Log.Write("file-opened ext=" + Path.GetExtension(e.Name) + " (shell)");
            }
            catch (Exception ex) { Log.Write("shell-item-failed error=\"" + ex.Message + "\""); }
        }

        void Watch()
        {
            watcher?.Dispose(); watcher = null;
            try
            {
                watcher = new FileSystemWatcher(current) { IncludeSubdirectories = false, NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.LastWrite | NotifyFilters.Size };
                FileSystemEventHandler h = (o, e) => Dispatcher.BeginInvoke(new Action(() => { reloadTimer.Stop(); reloadTimer.Start(); }));
                watcher.Created += h; watcher.Deleted += h; watcher.Changed += h; watcher.Renamed += (o, e) => h(o, e);
                watcher.EnableRaisingEvents = true;
            }
            catch { }
        }

        void LoadShell(HashSet<string> keep)
        {
            address.Text = shellTitle;
            var entries = new List<Entry>();
            string f = filter?.Text ?? "";
            bool bin = IsRecycleBin(ShellTarget);
            dynamic folder = ShellFolder(ShellTarget);
            if (folder == null) { status.Text = "This place is not available."; list.Items.Clear(); return; }
            try
            {
                foreach (dynamic item in folder.Items())
                {
                    try
                    {
                        string name = item.Name;
                        if (f.Length > 0 && name.IndexOf(f, StringComparison.OrdinalIgnoreCase) < 0) continue;
                        bool dir = item.IsFolder;
                        string path = item.Path;
                        long size = 0; try { size = item.Size; } catch { }
                        DateTime modified = DateTime.MinValue; try { modified = item.ModifyDate; } catch { }
                        string type = "";
                        try { type = bin ? "From " + folder.GetDetailsOf(item, 1) : (string)item.Type; } catch { }
                        if (bin) { try { DateTime.TryParse(((string)folder.GetDetailsOf(item, 2)).Replace("\u200e", "").Replace("\u200f", ""), out modified); } catch { } }
                        entries.Add(new Entry { Path = path, Name = name, Dir = dir, Size = dir ? -1 : size, Modified = modified, Type = string.IsNullOrEmpty(type) ? (dir ? "Folder" : "File") : type, Item = item });
                    }
                    catch { }
                }
            }
            catch (Exception e) { status.Text = e.Message; }
            Fill(entries.OrderByDescending(e => e.Dir).ThenBy(e => e.Name, NaturalComparer.Instance).ToList(), keep);
            status.Text = bin ? (entries.Count == 0 ? "The Recycle Bin is empty." : entries.Count + " deleted items · right-click to restore or delete for good")
                              : entries.Count(e => e.Dir) + " folders, " + entries.Count(e => !e.Dir) + " items" + (IsZip(ShellTarget) || IsInsideZip(ShellTarget) ? " in the ZIP · right-click a file to extract it" : "");
        }
        void Load(string select)
        {
            if (current == null || list == null) return;
            var keep = select != null ? new HashSet<string>(new[] { select }, StringComparer.OrdinalIgnoreCase) : new HashSet<string>(list.SelectedItems.OfType<ListBoxItem>().Select(i => ((Entry)i.Tag).Path ?? ""), StringComparer.OrdinalIgnoreCase);
            if (InShell) { LoadShell(keep); return; }
            address.Text = current;
            var entries = new List<Entry>();
            string f = filter?.Text ?? "";
            try
            {
                var dir = new DirectoryInfo(current);
                foreach (var i in dir.EnumerateFileSystemInfos())
                {
                    try
                    {
                        if (!showHidden && (i.Attributes & (FileAttributes.Hidden | FileAttributes.System)) != 0) continue;
                        if (f.Length > 0 && i.Name.IndexOf(f, StringComparison.OrdinalIgnoreCase) < 0) continue;
                        bool isDir = (i.Attributes & FileAttributes.Directory) != 0;
                        entries.Add(new Entry { Path = i.FullName, Name = i.Name, Dir = isDir, Modified = i.LastWriteTime, Size = isDir ? -1 : ((FileInfo)i).Length, Type = isDir ? "Folder" : TypeName(i.Extension) });
                    }
                    catch { }
                }
            }
            catch (UnauthorizedAccessException) { status.Text = "Windows does not allow BAKA Files to open this folder (access denied)."; list.Items.Clear(); return; }
            catch (Exception e) { status.Text = e.Message; list.Items.Clear(); return; }
            IEnumerable<Entry> sorted = entries.OrderByDescending(e => e.Dir);
            switch (sortBy)
            {
                case "date": sorted = sortDesc ? ((IOrderedEnumerable<Entry>)sorted).ThenByDescending(e => e.Modified) : ((IOrderedEnumerable<Entry>)sorted).ThenBy(e => e.Modified); break;
                case "size": sorted = sortDesc ? ((IOrderedEnumerable<Entry>)sorted).ThenByDescending(e => e.Size) : ((IOrderedEnumerable<Entry>)sorted).ThenBy(e => e.Size); break;
                case "type": sorted = sortDesc ? ((IOrderedEnumerable<Entry>)sorted).ThenByDescending(e => e.Type) : ((IOrderedEnumerable<Entry>)sorted).ThenBy(e => e.Type); break;
                default: sorted = sortDesc ? ((IOrderedEnumerable<Entry>)sorted).ThenByDescending(e => e.Name, NaturalComparer.Instance) : ((IOrderedEnumerable<Entry>)sorted).ThenBy(e => e.Name, NaturalComparer.Instance); break;
            }
            Fill(sorted.ToList(), keep);
            long total = entries.Where(e => !e.Dir).Sum(e => e.Size);
            status.Text = entries.Count(e => e.Dir) + " folders, " + entries.Count(e => !e.Dir) + " files" + (total > 0 ? " (" + FormatSize(total) + ")" : "") + (showHidden ? " · showing hidden files" : "");
        }
        void Fill(List<Entry> entries, HashSet<string> keep)
        {
            list.Items.Clear();
            foreach (var e in entries)
            {
                var g = Columns();
                var img = new Image { Source = Icons.ForFile(e.Path, 32, e.Dir), Width = 20, Height = 20, HorizontalAlignment = HorizontalAlignment.Left };
                g.Children.Add(img);
                var n = Ui.Text(e.Name, 13); Grid.SetColumn(n, 1); g.Children.Add(n);
                var d = Ui.Text(e.Modified.Year < 1990 ? "" : e.Modified.ToString("d MMM yyyy  HH:mm"), 12, null, Theme.Muted); Grid.SetColumn(d, 2); g.Children.Add(d);
                var t = Ui.Text(e.Type, 12, null, Theme.Muted); Grid.SetColumn(t, 3); g.Children.Add(t);
                var s = Ui.Text(e.Dir ? "" : FormatSize(e.Size), 12, null, Theme.Muted); s.TextAlignment = TextAlignment.Right; Grid.SetColumn(s, 4); g.Children.Add(s);
                var item = new ListBoxItem { Content = g, Tag = e, Padding = new Thickness(10, 5, 10, 5), Foreground = Theme.Text };
                list.Items.Add(item);
                if (keep.Contains(e.Path)) { item.IsSelected = true; list.ScrollIntoView(item); }
            }
        }
        void DeepSearch(string q)
        {
            if (string.IsNullOrWhiteSpace(q)) return;
            status.Text = "Searching " + current + " and its subfolders…";
            string root = current;
            Task.Run(() =>
            {
                var found = new List<Entry>();
                var stack = new Stack<string>(); stack.Push(root);
                while (stack.Count > 0 && found.Count < 500)
                {
                    var d = stack.Pop();
                    try
                    {
                        foreach (var sub in Directory.EnumerateDirectories(d)) { if (Path.GetFileName(sub).IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0) found.Add(new Entry { Path = sub, Name = sub.Substring(root.TrimEnd('\\').Length + 1), Dir = true, Size = -1, Type = "Folder", Modified = Directory.GetLastWriteTime(sub) }); if ((File.GetAttributes(sub) & FileAttributes.ReparsePoint) == 0) stack.Push(sub); }
                        foreach (var file in Directory.EnumerateFiles(d)) if (Path.GetFileName(file).IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0) { var fi = new FileInfo(file); found.Add(new Entry { Path = file, Name = file.Substring(root.TrimEnd('\\').Length + 1), Size = fi.Length, Modified = fi.LastWriteTime, Type = TypeName(fi.Extension) }); }
                    }
                    catch { }
                }
                return found;
            }).ContinueWith(t => Dispatcher.BeginInvoke(new Action(() => { if (current != root) return; Fill(t.Result, new HashSet<string>()); status.Text = t.Result.Count + " results for \"" + q + "\" in " + root + (t.Result.Count >= 500 ? " (first 500)" : ""); })));
        }

        static readonly Dictionary<string, string> typeNames = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        static string TypeName(string ext)
        {
            if (string.IsNullOrEmpty(ext)) return "File";
            if (typeNames.TryGetValue(ext, out var n)) return n;
            try
            {
                using (var k = Microsoft.Win32.Registry.ClassesRoot.OpenSubKey(ext))
                {
                    var prog = k?.GetValue("") as string;
                    if (prog != null) using (var p = Microsoft.Win32.Registry.ClassesRoot.OpenSubKey(prog)) n = p?.GetValue("") as string;
                }
            }
            catch { }
            if (string.IsNullOrWhiteSpace(n) || n.StartsWith("@")) n = ext.TrimStart('.').ToUpperInvariant() + " file";
            return typeNames[ext] = n;
        }
        public static string FormatSize(long b) => b < 1024 ? b + " B" : b < 1048576 ? (b / 1024.0).ToString("0") + " KB" : b < 1073741824 ? (b / 1048576.0).ToString("0.0") + " MB" : (b / 1073741824.0).ToString("0.0") + " GB";

        // ---- actions ----
        List<string> Selection() => list.SelectedItems.OfType<ListBoxItem>().Select(i => ((Entry)i.Tag).Path).ToList();
        List<Entry> SelectedEntries() => list.SelectedItems.OfType<ListBoxItem>().Select(i => (Entry)i.Tag).ToList();
        // Recycle Bin, ZIP and network items: the actions Windows offers for them (Restore, Delete, Extract…).
        void ShellMenu()
        {
            var sel = SelectedEntries(); var items = new List<object>();
            bool bin = IsRecycleBin(ShellTarget);
            if (sel.Count == 1 && !bin) items.Add(Ui.Item("Open", 0xE8E5, () => ActivateShell(sel[0]), "Enter"));
            if (bin && sel.Count > 0)
            {
                items.Add(Ui.Item("Restore", 0xE777, () => { foreach (var e in sel) Verb(e, "undelete"); }));
                items.Add(Ui.Item("Delete for good", 0xE74D, () => { foreach (var e in sel) Verb(e, "delete"); }));
            }
            else if (sel.Count == 1)
            {
                try
                {
                    foreach (dynamic v in ((dynamic)sel[0].Item).Verbs())
                    {
                        string n = ((string)v.Name ?? "").Replace("&", "").Trim(); dynamic verb = v;
                        if (n.Length == 0 || n.Equals("Open", StringComparison.OrdinalIgnoreCase)) continue;
                        items.Add(Ui.Item(n, 0, () => { try { verb.DoIt(); } catch { } ReloadSoon(); }));
                    }
                }
                catch { }
            }
            if (sel.Count > 0 && (IsZip(ShellTarget) || IsInsideZip(ShellTarget)))
                items.Add(Ui.Item("Extract to " + Path.GetFileName(Path.GetDirectoryName(ZipFile(ShellTarget))), 0xE8B7, () => ExtractItems(sel)));
            if (bin)
            {
                if (items.Count > 0) items.Add("-");
                items.Add(Ui.Item("Restore all", 0xE777, () => { foreach (var e in AllEntries()) Verb(e, "undelete"); }, null, list.Items.Count > 0));
                items.Add(Ui.Item("Empty Recycle Bin", 0xE74D, () => { Native.SHEmptyRecycleBin(Handle, null, 0); ReloadSoon(); }, null, list.Items.Count > 0));
            }
            if (sel.Count == 1 && !bin) { if (items.Count > 0) items.Add("-"); items.Add(Ui.Item("Properties", 0xE946, () => Verb(sel[0], "properties"))); }
            if (items.Count > 0) Ui.ShowMenu(list, items.ToArray());
        }
        List<Entry> AllEntries() => list.Items.OfType<ListBoxItem>().Select(i => (Entry)i.Tag).ToList();
        void Verb(Entry e, string verb) { try { ((dynamic)e.Item).InvokeVerb(verb); } catch (Exception x) { Log.Write("shell-verb-failed verb=" + verb + " error=\"" + x.Message + "\""); } ReloadSoon(); }
        void ReloadSoon() { reloadTimer.Stop(); reloadTimer.Interval = TimeSpan.FromMilliseconds(700); reloadTimer.Start(); }
        static string ZipFile(string p) { int i = p.IndexOf(".zip", StringComparison.OrdinalIgnoreCase); return i > 0 ? p.Substring(0, i + 4) : p; }
        // Copies items out of the ZIP into the folder that holds it (Windows does the unpacking).
        void ExtractItems(List<Entry> sel)
        {
            string target = Path.GetDirectoryName(ZipFile(ShellTarget));
            dynamic dest = ShellFolder(target);
            if (dest == null) return;
            foreach (var e in sel) { try { dest.CopyHere(e.Item, 16 /*yes to all*/); } catch (Exception x) { Log.Write("zip-extract-failed error=\"" + x.Message + "\""); } }
            status.Text = "Extracted " + sel.Count + " item" + (sel.Count == 1 ? "" : "s") + " to " + target;
        }
        void ItemMenu()
        {
            if (InShell) { ShellMenu(); return; }
            var sel = Selection();
            var items = new List<object>();
            if (sel.Count > 0)
            {
                items.Add(Ui.Item("Open", 0xE8E5, () => sel.ForEach(OpenItem), "Enter"));
                if (sel.Count == 1 && File.Exists(sel[0])) items.Add(Ui.Item("Open with…", 0xE7AC, () => Native.ShellVerb(sel[0], "openas")));
                if (sel.Count == 1 && Directory.Exists(sel[0])) items.Add(Ui.Item("Open in new window", 0xE8A7, () => Open(sel[0])));
                if (sel.Count == 1 && (sel[0].EndsWith(".exe", StringComparison.OrdinalIgnoreCase) || sel[0].EndsWith(".lnk", StringComparison.OrdinalIgnoreCase)))
                {
                    items.Add(Ui.Item("Run as administrator", 0xE7EF, () => { try { Process.Start(new ProcessStartInfo(sel[0]) { UseShellExecute = true, Verb = "runas" }); } catch { } }));
                    items.Add(Ui.Item("Keep in dock", 0xE718, () => Dock.Pin(new AppRef { Name = Path.GetFileNameWithoutExtension(sel[0]), Exe = sel[0].EndsWith(".lnk", StringComparison.OrdinalIgnoreCase) ? AppCatalog.ShortcutTarget(sel[0]) ?? sel[0] : sel[0] })));
                }
                items.Add("-");
                items.Add(Ui.Item("Cut", 0xE8C6, () => ToClipboard(sel, true), "Ctrl+X"));
                items.Add(Ui.Item("Copy", 0xE8C8, () => ToClipboard(sel, false), "Ctrl+C"));
            }
            bool canPaste; try { canPaste = Clipboard.ContainsFileDropList(); } catch { canPaste = false; }
            items.Add(Ui.Item("Paste", 0xE77F, Paste, "Ctrl+V", canPaste));
            if (sel.Count > 0)
            {
                items.Add(Ui.Item("Copy path", 0xE71B, () => { try { Clipboard.SetText(string.Join(Environment.NewLine, sel)); } catch { status.Text = "The clipboard is in use by another app. Try again."; } }));
                if (sel.Count == 1) items.Add(Ui.Item("Rename", 0xE8AC, () => Rename(sel[0]), "F2"));
                items.Add(Ui.Item("Delete", 0xE74D, () => Delete(sel, false), "Del"));
                if (sel.Count == 1 && sel[0].EndsWith(".zip", StringComparison.OrdinalIgnoreCase)) items.Add(Ui.Item("Extract here", 0xE8B7, () => Extract(sel[0])));
                items.Add(Ui.Item("Compress to ZIP", 0xF012, () => Zip(sel)));
                items.Add("-");
                items.Add(Ui.Item("Properties", 0xE946, () => Native.ShellVerb(sel[0], "properties"), "Alt+Enter"));
            }
            else
            {
                items.Add(Ui.Item("New folder", 0xE8F4, NewFolder, "Ctrl+Shift+N"));
                items.Add(Ui.Item("New text file", 0xE8A5, NewTextFile));
                items.Add(Ui.Item(showHidden ? "Hide hidden files" : "Show hidden files", 0xE890, () => { showHidden = !showHidden; Load(null); }));
                items.Add(Ui.Item("Properties", 0xE946, () => Native.ShellVerb(current, "properties")));
            }
            Ui.ShowMenu(list, items.ToArray());
        }
        void ToClipboard(List<string> paths, bool cut)
        {
            var data = new DataObject(); var col = new StringCollection(); col.AddRange(paths.ToArray()); data.SetFileDropList(col);
            data.SetData("Preferred DropEffect", new MemoryStream(BitConverter.GetBytes(cut ? 2 : 5)));
            // the clipboard can be briefly held by another app (clipboard managers, remote desktop): retry
            for (int i = 0; ; i++) { try { Clipboard.SetDataObject(data, true); break; } catch (System.Runtime.InteropServices.COMException) when (i < 5) { System.Threading.Thread.Sleep(60); } catch (Exception e) { status.Text = "The clipboard is in use by another app. Try again."; Log.Write("clipboard-failed error=\"" + e.Message + "\""); return; } }
            status.Text = (cut ? "Cut " : "Copied ") + paths.Count + " item" + (paths.Count == 1 ? "" : "s");
        }
        void Paste()
        {
            if (InShell) return;
            bool has; try { has = Clipboard.ContainsFileDropList(); } catch { return; } // another app holding the clipboard
            if (!has) return;
            var files = Clipboard.GetFileDropList().Cast<string>().ToList();
            bool cut = false;
            try { if (Clipboard.GetData("Preferred DropEffect") is MemoryStream ms) { var b = new byte[4]; ms.Read(b, 0, 4); cut = (BitConverter.ToInt32(b, 0) & 2) != 0; } } catch { }
            Transfer(files, current, cut);
            if (cut) Clipboard.Clear();
        }
        void Transfer(List<string> files, string target, bool move)
        {
            var h = Handle;
            ShellTask(() => Native.FileOperation(h, move ? Native.FO_MOVE : Native.FO_COPY, files, target, true)).ContinueWith(t => Dispatcher.BeginInvoke(new Action(() => { Load(null); Log.Write("files-" + (move ? "moved" : "copied") + " count=" + files.Count + " ok=" + t.Result); })));
        }
        void Delete(List<string> paths, bool permanent)
        {
            if (paths.Count == 0) return;
            var h = Handle;
            // Windows asks for confirmation itself (and puts the items in the Recycle Bin).
            ShellTask(() => Native.FileOperation(h, Native.FO_DELETE, paths, null, !permanent)).ContinueWith(t => Dispatcher.BeginInvoke(new Action(() => Load(null))));
        }
        // Windows' copy engine (progress, "replace or skip", Recycle Bin) expects a single-threaded apartment
        // thread; on a pool thread it sometimes fails without saying why.
        static Task<bool> ShellTask(Func<bool> op) => Task.Factory.StartNew(() => { try { return op(); } catch (Exception e) { Log.Write("file-operation-failed error=\"" + e.Message + "\""); return false; } }, System.Threading.CancellationToken.None, TaskCreationOptions.LongRunning, StaScheduler.Instance);
        void Rename(string path)
        {
            string old = Path.GetFileName(path);
            string name = Prompt.Ask(this, "Rename", "New name for " + old, old);
            if (string.IsNullOrWhiteSpace(name) || name == old) return;
            if (name.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0) { MessageBox.Show(this, "A name cannot contain \\ / : * ? \" < > |", "Rename", MessageBoxButton.OK, MessageBoxImage.Information); return; }
            string target = Path.Combine(Path.GetDirectoryName(path), name);
            try { if (Directory.Exists(path)) Directory.Move(path, target); else File.Move(path, target); Load(target); }
            catch (Exception e) { MessageBox.Show(this, e.Message, "Rename", MessageBoxButton.OK, MessageBoxImage.Warning); }
        }
        void NewFolder()
        {
            if (InShell || current == null) return;
            string name = "New folder"; int i = 2;
            while (Directory.Exists(Path.Combine(current, name)) || File.Exists(Path.Combine(current, name))) name = "New folder (" + i++ + ")";
            try { var p = Path.Combine(current, name); Directory.CreateDirectory(p); Load(p); Rename(p); }
            catch (Exception e) { MessageBox.Show(this, e.Message, "New folder", MessageBoxButton.OK, MessageBoxImage.Warning); }
        }
        void NewTextFile()
        {
            string name = "New text document.txt"; int i = 2;
            while (File.Exists(Path.Combine(current, name))) name = "New text document (" + i++ + ").txt";
            try { var p = Path.Combine(current, name); File.WriteAllText(p, ""); Load(p); Rename(p); } catch (Exception e) { MessageBox.Show(this, e.Message, "New file", MessageBoxButton.OK, MessageBoxImage.Warning); }
        }
        void Extract(string zip)
        {
            string target = Path.Combine(current, Path.GetFileNameWithoutExtension(zip));
            Task.Run(() => { try { System.IO.Compression.ZipFile.ExtractToDirectory(zip, target); return (string)null; } catch (Exception e) { return e.Message; } })
                .ContinueWith(t => Dispatcher.BeginInvoke(new Action(() => { if (t.Result != null) MessageBox.Show(this, t.Result, "Extract", MessageBoxButton.OK, MessageBoxImage.Warning); Load(target); })));
        }
        void Zip(List<string> paths)
        {
            string name = (paths.Count == 1 ? Path.GetFileNameWithoutExtension(paths[0]) : "Archive") + ".zip"; int i = 2;
            while (File.Exists(Path.Combine(current, name))) name = Path.GetFileNameWithoutExtension(name).Split('(')[0].Trim() + " (" + i++ + ").zip";
            string target = Path.Combine(current, name);
            Task.Run(() =>
            {
                try
                {
                    using (var z = System.IO.Compression.ZipFile.Open(target, System.IO.Compression.ZipArchiveMode.Create))
                        foreach (var p in paths)
                        {
                            if (File.Exists(p)) z.CreateEntryFromFile(p, Path.GetFileName(p));
                            else foreach (var f in Directory.EnumerateFiles(p, "*", SearchOption.AllDirectories)) z.CreateEntryFromFile(f, Path.Combine(Path.GetFileName(p), f.Substring(p.TrimEnd('\\').Length + 1)));
                        }
                    return (string)null;
                }
                catch (Exception e) { return e.Message; }
            }).ContinueWith(t => Dispatcher.BeginInvoke(new Action(() => { if (t.Result != null) MessageBox.Show(this, t.Result, "Compress", MessageBoxButton.OK, MessageBoxImage.Warning); Load(target); })));
        }

        void OnKey(object sender, KeyEventArgs e)
        {
            bool ctrl = (Keyboard.Modifiers & ModifierKeys.Control) != 0, alt = (Keyboard.Modifiers & ModifierKeys.Alt) != 0, shift = (Keyboard.Modifiers & ModifierKeys.Shift) != 0;
            var key = e.Key == Key.System ? e.SystemKey : e.Key;
            if (address.IsKeyboardFocused || (filter.IsKeyboardFocused && key != Key.Escape)) { if (ctrl && key == Key.F) { filter.Focus(); e.Handled = true; } return; }
            if (InShell)
            {
                // only navigation here: the shell items have no paths on disk to copy, rename or delete
                if (alt && key == Key.Left) Go(back, forward);
                else if (alt && key == Key.Right) Go(forward, back);
                else if ((alt && key == Key.Up) || key == Key.Back) Up();
                else if (key == Key.Enter && list.SelectedItem is ListBoxItem si) Activate(si.Tag as Entry);
                else if (key == Key.F5) Load(null);
                else if (ctrl && key == Key.F) filter.Focus();
                else if (ctrl && key == Key.L) { address.Focus(); address.SelectAll(); }
                else if (ctrl && key == Key.W) Close();
                else if (key == Key.Escape) { if (filter.Text.Length > 0) filter.Clear(); else Close(); }
                else return;
                e.Handled = true; return;
            }
            var sel = Selection();
            if (alt && key == Key.Left) Go(back, forward);
            else if (alt && key == Key.Right) Go(forward, back);
            else if ((alt && key == Key.Up) || key == Key.Back) Up();
            else if (alt && key == Key.Enter && sel.Count > 0) Native.ShellVerb(sel[0], "properties");
            else if (key == Key.Enter && sel.Count > 0) { if (sel.Count == 1) Activate((Entry)((ListBoxItem)list.SelectedItem).Tag); else sel.ForEach(OpenItem); }
            else if (key == Key.F5) Load(null);
            else if (key == Key.F2 && sel.Count == 1) Rename(sel[0]);
            else if (key == Key.Delete) Delete(sel, shift);
            else if (ctrl && key == Key.C) ToClipboard(sel, false);
            else if (ctrl && key == Key.X) ToClipboard(sel, true);
            else if (ctrl && key == Key.V) Paste();
            else if (ctrl && key == Key.A) list.SelectAll();
            else if (ctrl && key == Key.F) filter.Focus();
            else if (ctrl && key == Key.L) { address.Focus(); address.SelectAll(); }
            else if (ctrl && shift && key == Key.N) NewFolder();
            else if (ctrl && key == Key.W) Close();
            else if (ctrl && key == Key.N) Open(current);
            else if (key == Key.Escape) { if (filter.Text.Length > 0) filter.Clear(); else Close(); }
            else return;
            e.Handled = true;
        }

        // ---- drag and drop ----
        Point dragStart; bool dragArmed;
        Canvas marqueeLayer; System.Windows.Shapes.Rectangle marqueeBox; Point marqueeStart; bool marqueeing;
        void StartDrag(object sender, MouseEventArgs e)
        {
            if (marqueeing) { UpdateMarquee(e.GetPosition(list)); return; }
            if (e.LeftButton != MouseButtonState.Pressed || InShell) { dragArmed = false; return; }
            var pos = e.GetPosition(list);
            if (!dragArmed) { dragStart = pos; dragArmed = Ancestor<ListBoxItem>(e.OriginalSource as DependencyObject) != null; return; }
            if (Math.Abs(pos.X - dragStart.X) < 6 && Math.Abs(pos.Y - dragStart.Y) < 6) return;
            var sel = Selection(); if (sel.Count == 0) { dragArmed = false; return; }
            dragArmed = false;
            DragDrop.DoDragDrop(list, new DataObject(DataFormats.FileDrop, sel.ToArray()), DragDropEffects.Copy | DragDropEffects.Move | DragDropEffects.Link);
        }

        // Rubber-band selection, like File Explorer: dragging from empty space draws a box and selects the
        // file rows it touches. Dragging from a row still moves the selected files. Ctrl/Shift+click and
        // Ctrl+A keep working (the ListBox is in Extended mode). R15 had no marquee, so the only way to pick
        // several files was Ctrl+click, which is easy to miss.
        void BeginMarquee(MouseButtonEventArgs e)
        {
            if (marqueeLayer == null || Ancestor<ListBoxItem>(e.OriginalSource as DependencyObject) != null) return;
            marqueeing = true; marqueeStart = e.GetPosition(list);
            if ((Keyboard.Modifiers & (ModifierKeys.Control | ModifierKeys.Shift)) == 0) list.SelectedItems.Clear();
            Canvas.SetLeft(marqueeBox, marqueeStart.X); Canvas.SetTop(marqueeBox, marqueeStart.Y);
            marqueeBox.Width = 0; marqueeBox.Height = 0; marqueeBox.Visibility = Visibility.Visible;
            list.CaptureMouse();
        }
        void UpdateMarquee(Point p)
        {
            double x = Math.Min(p.X, marqueeStart.X), y = Math.Min(p.Y, marqueeStart.Y), w = Math.Abs(p.X - marqueeStart.X), h = Math.Abs(p.Y - marqueeStart.Y);
            Canvas.SetLeft(marqueeBox, x); Canvas.SetTop(marqueeBox, y); marqueeBox.Width = w; marqueeBox.Height = h;
            var box = new Rect(x, y, w, h);
            bool additive = (Keyboard.Modifiers & (ModifierKeys.Control | ModifierKeys.Shift)) != 0;
            for (int i = 0; i < list.Items.Count; i++)
            {
                if (!(list.ItemContainerGenerator.ContainerFromIndex(i) is ListBoxItem row) || !row.IsVisible) continue;
                Rect r; try { r = row.TransformToVisual(list).TransformBounds(new Rect(0, 0, row.ActualWidth, row.ActualHeight)); } catch { continue; }
                bool hit = box.IntersectsWith(r);
                if (hit) row.IsSelected = true; else if (!additive) row.IsSelected = false;
            }
        }
        void EndMarquee()
        {
            if (!marqueeing) return;
            marqueeing = false; marqueeBox.Visibility = Visibility.Collapsed;
            if (list.IsMouseCaptured) list.ReleaseMouseCapture();
        }
        // self-test: Extended multi-select works (returns 2 when the first two rows are selected)
        public int TestMultiSelect()
        {
            list.UpdateLayout();
            for (int i = 0; i < Math.Min(2, list.Items.Count); i++) if (list.ItemContainerGenerator.ContainerFromIndex(i) is ListBoxItem r) r.IsSelected = true;
            return list.SelectedItems.Count;
        }
        void OnDrop(object sender, DragEventArgs e)
        {
            if (InShell || !(e.Data.GetData(DataFormats.FileDrop) is string[] files) || files.Length == 0) return;
            string target = current;
            var onto = Ancestor<ListBoxItem>(e.OriginalSource as DependencyObject);
            if (onto?.Tag is Entry en && en.Dir) target = en.Path;
            if (files.Any(f => string.Equals(Path.GetDirectoryName(f), target, StringComparison.OrdinalIgnoreCase))) return;
            bool sameDrive = string.Equals(Path.GetPathRoot(files[0]), Path.GetPathRoot(target), StringComparison.OrdinalIgnoreCase);
            bool move = (e.KeyStates & DragDropKeyStates.ControlKey) == 0 && sameDrive;
            Transfer(files.ToList(), target, move);
        }
        static T Ancestor<T>(DependencyObject d) where T : DependencyObject { while (d != null && !(d is T)) d = d is Visual || d is System.Windows.Media.Media3D.Visual3D ? VisualTreeHelper.GetParent(d) : LogicalTreeHelper.GetParent(d); return d as T; }

        // for the self test
        public string CurrentFolder => current;
        public int ItemCount => list?.Items.Count ?? 0;
        public void TestNewFolderAndDelete(string name)
        {
            var p = Path.Combine(current, name); Directory.CreateDirectory(p); Load(p);
            if (!list.Items.OfType<ListBoxItem>().Any(i => ((Entry)i.Tag).Path == p)) throw new Exception("New folder did not appear in the list.");
            Directory.Delete(p); Load(null);
        }
    }

    // Sorts "file 2" before "file 10", like Windows File Explorer.
    class NaturalComparer : IComparer<string>
    {
        public static readonly NaturalComparer Instance = new NaturalComparer();
        [System.Runtime.InteropServices.DllImport("shlwapi.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)] static extern int StrCmpLogicalW(string a, string b);
        public int Compare(string a, string b) => StrCmpLogicalW(a, b);
    }

    // A one-line question (rename, notes title).
    static class Prompt
    {
        public static string Ask(Window owner, string title, string question, string value)
        {
            var w = new GlassPanel(16) { Owner = owner, Width = 420, SizeToContent = SizeToContent.Height, WindowStartupLocation = WindowStartupLocation.CenterOwner, ShowActivated = true, Topmost = true, ToolWindow = false };
            var sp = new StackPanel { Margin = new Thickness(18) };
            sp.Children.Add(Ui.Text(title, 16, FontWeights.SemiBold));
            var q = Ui.Muted(question, 12); q.Margin = new Thickness(0, 4, 0, 10); sp.Children.Add(q);
            var box = new TextBox { Text = value }; sp.Children.Add(box);
            string result = null;
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 14, 0, 0) };
            var cancel = Ui.Button("Cancel", () => w.Close()); cancel.Margin = new Thickness(0, 0, 8, 0);
            var ok = Ui.Button("OK", () => { result = box.Text; w.Close(); }, true);
            buttons.Children.Add(cancel); buttons.Children.Add(ok); sp.Children.Add(buttons);
            w.Content = sp;
            box.KeyDown += (o, e) => { if (e.Key == Key.Enter) { result = box.Text; w.Close(); } else if (e.Key == Key.Escape) w.Close(); };
            w.Loaded += (o, e) => { box.Focus(); int dot = value.LastIndexOf('.'); if (dot > 0 && !Directory.Exists(value)) box.Select(0, dot); else box.SelectAll(); };
            w.ShowDialog();
            return result;
        }
    }
}
