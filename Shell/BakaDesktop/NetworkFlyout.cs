using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.NetworkInformation;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using global::Windows.Devices.Radios;
using global::Windows.Devices.WiFi;
using global::Windows.Security.Credentials;

namespace Baka.Desktop
{
    // BAKA's network panel, under the Wi-Fi icon in the menu bar (instead of the Windows flyout): the wired
    // connection, the Wi-Fi switch, the networks in range with their signal, and connecting with a password.
    // Uses Windows' own Wi-Fi and radio APIs. Windows only lists nearby networks to apps when Location is on
    // (Windows 11 24H2 rule); if it is off, the panel says so and opens that setting.
    class NetworkFlyout : GlassPanel
    {
        static NetworkFlyout current;
        public static bool IsOpen => current != null && current.IsVisible;
        public static void Toggle(Window anchor)
        {
            if (IsOpen) { current.Close(); return; }
            current = new NetworkFlyout();
            current.Left = SystemParameters.PrimaryScreenWidth - current.Width - 10; current.Top = TopBar.BarHeight + 4;
            current.Show(); current.Activate();
        }

        readonly StackPanel body = new StackPanel { Margin = new Thickness(14) };
        WiFiAdapter adapter; Radio radio;
        string expanded; bool closing;

        NetworkFlyout() : base(18)
        {
            Title = "BAKA Network"; Width = 340; SizeToContent = SizeToContent.Height; Topmost = true;
            Deactivated += (o, e) => { if (!closing && !SelfTest.Running) { closing = true; try { Close(); } catch { } } };
            Closing += (o, e) => closing = true;
            Closed += (o, e) => { if (current == this) current = null; };
            KeyDown += (o, e) => { if (e.Key == Key.Escape) Close(); };
            Content = Ui.Scroll(body); MaxHeight = SystemParameters.PrimaryScreenHeight * 0.75;
            Draw(null, "Looking for networks…");
            Ui.FadeIn(Frame, 170, 0.96, -12);
            Load();
        }

        async void Load()
        {
            string note = null;
            List<WiFiAvailableNetwork> nets = null;
            try
            {
                var radios = await Radio.GetRadiosAsync();
                radio = radios.FirstOrDefault(r => r.Kind == RadioKind.WiFi);
                var access = await WiFiAdapter.RequestAccessAsync();
                if (access != WiFiAccessStatus.Allowed) note = "Windows did not let BAKA see Wi-Fi networks (" + access + ").";
                else
                {
                    adapter = (await WiFiAdapter.FindAllAdaptersAsync()).FirstOrDefault();
                    if (adapter == null) note = radio == null ? "This PC has no Wi-Fi." : null;
                    else if (radio == null || radio.State == RadioState.On)
                    {
                        try { await adapter.ScanAsync(); } catch { }
                        nets = adapter.NetworkReport.AvailableNetworks.Where(n => !string.IsNullOrEmpty(n.Ssid))
                            .GroupBy(n => n.Ssid).Select(g => g.OrderByDescending(n => n.NetworkRssiInDecibelMilliwatts).First())
                            .OrderByDescending(n => n.SignalBars).ToList();
                        if (nets.Count == 0) note = "No networks found. Windows lists nearby networks only when Location is on.";
                    }
                }
            }
            catch (Exception e) { note = "Wi-Fi is not available: " + e.Message; Log.Write("network-flyout-failed error=\"" + e.Message + "\""); }
            if (!IsLoaded || closing) return;
            Draw(nets, note);
        }

        void Draw(List<WiFiAvailableNetwork> nets, string note)
        {
            body.Children.Clear();
            var head = new Grid();
            head.Children.Add(Ui.Text("Network", 15, FontWeights.SemiBold));
            var more = Ui.Button("Settings", () => { Close(); Launcher.Run("ms-settings:network", () => System.Diagnostics.Process.Start("ms-settings:network")); }, false, 9, new Thickness(10, 4, 10, 4));
            more.HorizontalAlignment = HorizontalAlignment.Right; head.Children.Add(more);
            body.Children.Add(head);

            // wired
            foreach (var ni in NetworkInterface.GetAllNetworkInterfaces().Where(n => n.NetworkInterfaceType == NetworkInterfaceType.Ethernet && n.OperationalStatus == OperationalStatus.Up && !n.Description.Contains("Hyper-V") && !n.Description.Contains("Virtual")))
            {
                string ip = ni.GetIPProperties().UnicastAddresses.FirstOrDefault(a => a.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)?.Address.ToString() ?? "";
                body.Children.Add(Line(0xE839, "Ethernet", "Connected · " + Speed(ni.Speed) + (ip.Length > 0 ? " · " + ip : ""), null));
            }

            // Wi-Fi switch
            if (radio != null)
            {
                bool on = radio.State == RadioState.On;
                var t = Ui.Toggle(on, v => SetWifi(v));
                body.Children.Add(Line(0xE701, "Wi-Fi", on ? "On" : "Off", t));
            }

            if (note != null) { var m = Ui.Muted(note, 11.5); m.Margin = new Thickness(2, 8, 0, 4); m.TextWrapping = TextWrapping.Wrap; body.Children.Add(m); }
            if (note != null && note.Contains("Location"))
                body.Children.Add(Ui.Labeled(0xE81D, "Turn on Location", () => { Close(); Launcher.Run("ms-settings:privacy-location", () => System.Diagnostics.Process.Start("ms-settings:privacy-location")); }));

            if (nets == null) return;
            var cap = Ui.Text("NETWORKS", 10.5, FontWeights.Bold, Theme.Muted); cap.Margin = new Thickness(2, 12, 0, 6); body.Children.Add(cap);
            DrawNetworks(nets);
        }

        async void DrawNetworks(List<WiFiAvailableNetwork> nets)
        {
            string current = null;
            try { var prof = await adapter.NetworkAdapter.GetConnectedProfileAsync(); current = prof?.WlanConnectionProfileDetails?.GetConnectedSsid(); } catch { }
            if (closing) return;
            foreach (var n in nets.OrderByDescending(n => n.Ssid == current))
            {
                var net = n; bool isCurrent = n.Ssid == current;
                bool secured = n.SecuritySettings.NetworkAuthenticationType != global::Windows.Networking.Connectivity.NetworkAuthenticationType.Open80211;
                var card = new StackPanel();
                var row = Line(Bars(n.SignalBars), n.Ssid, (isCurrent ? "Connected" : secured ? "Secured" : "Open") + " · " + n.SignalBars + "/4", null);
                card.Children.Add(row);
                if (isCurrent)
                {
                    var b = Ui.Button("Disconnect", () => { try { adapter.Disconnect(); } catch { } Load(); }, false, 9, new Thickness(12, 4, 12, 4));
                    b.HorizontalAlignment = HorizontalAlignment.Right; b.Margin = new Thickness(0, 0, 0, 6); card.Children.Add(b);
                }
                else if (expanded == n.Ssid)
                {
                    var pw = new PasswordBox { Margin = new Thickness(0, 4, 0, 6), Height = 30, Visibility = secured ? Visibility.Visible : Visibility.Collapsed };
                    var status = Ui.Muted("", 11);
                    var go = Ui.Button("Connect", async () =>
                    {
                        status.Text = "Connecting…";
                        var r = await Connect(net, secured && pw.Password.Length > 0 ? pw.Password : null);
                        if (r == WiFiConnectionStatus.Success) { Log.Write("wifi-connected ssid=\"" + net.Ssid + "\""); Load(); }
                        else { status.Text = r == WiFiConnectionStatus.InvalidCredential ? "Wrong password." : "Could not connect (" + r + ")" + (secured && pw.Password.Length == 0 ? ": type the password." : "."); pw.Visibility = secured ? Visibility.Visible : pw.Visibility; }
                    }, true, 9, new Thickness(12, 4, 12, 4));
                    card.Children.Add(pw); card.Children.Add(go); card.Children.Add(status);
                    pw.KeyDown += (o, e) => { if (e.Key == Key.Enter) go.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent)); };
                }
                if (!isCurrent) { row.Cursor = Cursors.Hand; Ui.OnClick(row, () => { expanded = expanded == net.Ssid ? null : net.Ssid; Draw(nets, null); }); }
                body.Children.Add(card);
            }
        }

        async Task<WiFiConnectionStatus> Connect(WiFiAvailableNetwork n, string password)
        {
            try
            {
                var r = password == null
                    ? await adapter.ConnectAsync(n, WiFiReconnectionKind.Automatic)
                    : await adapter.ConnectAsync(n, WiFiReconnectionKind.Automatic, new PasswordCredential { Password = password });
                return r.ConnectionStatus;
            }
            catch (Exception e) { Log.Write("wifi-connect-failed error=\"" + e.Message + "\""); return WiFiConnectionStatus.UnspecifiedFailure; }
        }

        async void SetWifi(bool on)
        {
            try { var r = await radio.SetStateAsync(on ? RadioState.On : RadioState.Off); Log.Write("wifi-radio on=" + on + " result=" + r); await Task.Delay(on ? 2500 : 300); }
            catch (Exception e) { Log.Write("wifi-radio-failed error=\"" + e.Message + "\""); }
            if (!closing) Load();
        }

        FrameworkElement Line(int glyph, string title, string detail, FrameworkElement right)
        {
            var g = new Grid { Margin = new Thickness(0, 2, 0, 2) };
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(30) }); g.ColumnDefinitions.Add(new ColumnDefinition()); g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var ic = Ui.Glyph(glyph, 15); ic.VerticalAlignment = VerticalAlignment.Center; g.Children.Add(ic);
            var sp = new StackPanel { VerticalAlignment = VerticalAlignment.Center }; Grid.SetColumn(sp, 1);
            sp.Children.Add(Ui.Text(title, 13, FontWeights.SemiBold)); sp.Children.Add(Ui.Muted(detail, 11));
            g.Children.Add(sp);
            if (right != null) { Grid.SetColumn(right, 2); right.VerticalAlignment = VerticalAlignment.Center; g.Children.Add(right); }
            var b = new Border { Child = g, Padding = new Thickness(8, 6, 8, 6), CornerRadius = new CornerRadius(10), Background = System.Windows.Media.Brushes.Transparent };
            b.MouseEnter += (o, e) => b.Background = Theme.Hover; b.MouseLeave += (o, e) => b.Background = System.Windows.Media.Brushes.Transparent;
            return b;
        }
        static int Bars(byte bars) => bars >= 4 ? 0xE701 : bars == 3 ? 0xE874 : bars == 2 ? 0xE873 : 0xE872;
        static string Speed(long bps) => bps >= 1_000_000_000 ? (bps / 1_000_000_000.0).ToString("0.#") + " Gb/s" : (bps / 1_000_000) + " Mb/s";
    }
}
