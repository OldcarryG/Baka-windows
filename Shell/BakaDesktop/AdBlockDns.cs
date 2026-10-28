using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace Baka.Desktop
{
    // System-wide ad and tracker blocking: Windows uses AdGuard DNS (free, no account) over encrypted DNS
    // (DoH, with plain DNS kept as a fallback so captive portals still work). Every app, game launcher and
    // browser benefits. The previous DNS of each adapter is saved and restored by "Use my normal DNS".
    // Runs elevated as "BakaDesktop.exe --adblock on|off"; the same backup file is used as earlier releases.
    static class AdBlockDns
    {
        static readonly string[] V4 = { "94.140.14.14", "94.140.15.15" }, V6 = { "2a10:50c0::ad1:ff", "2a10:50c0::ad2:ff" };
        const string Template = "https://dns.adguard-dns.com/dns-query";
        public static string BackupPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "BAKA", "AdBlockDnsBackup.json");
        public static bool On => File.Exists(BackupPath);

        public static void RequestElevated(bool on)
        {
            try { Process.Start(new ProcessStartInfo(App.Exe, "--adblock " + (on ? "on" : "off")) { UseShellExecute = true, Verb = "runas", WindowStyle = ProcessWindowStyle.Hidden }); }
            catch (Exception e) { Log.Write("adblock-elevation-declined error=\"" + e.Message + "\""); }
        }

        static IEnumerable<NetworkInterface> Adapters() => NetworkInterface.GetAllNetworkInterfaces().Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback && n.NetworkInterfaceType != NetworkInterfaceType.Tunnel && n.GetIPProperties().GatewayAddresses.Count > 0);

        public static int Run(bool on)
        {
            Paths.Init(false);
            try { if (on) Enable(); else Disable(); return 0; }
            catch (Exception e) { Log.Write("adblock-failed on=" + on + " error=\"" + e.Message + "\""); return 1; }
        }
        static void Enable()
        {
            var saved = new List<object>();
            if (File.Exists(BackupPath)) saved = Json.Arr(Json.Get(Json.Obj(Json.Parse(File.ReadAllText(BackupPath))), "Adapters"));
            foreach (var n in Adapters())
            {
                string name = n.Name;
                if (!saved.Select(Json.Obj).Any(a => Json.Str(a, "Name") == name))
                {
                    var p = n.GetIPProperties();
                    bool dhcp = IsDhcpDns(n.Id);
                    saved.Add(new Dictionary<string, object> { ["Name"] = name, ["Dhcp"] = dhcp, ["IPv4"] = p.DnsAddresses.Where(a => a.AddressFamily == AddressFamily.InterNetwork).Select(a => (object)a.ToString()).ToList(), ["IPv6"] = p.DnsAddresses.Where(a => a.AddressFamily == AddressFamily.InterNetworkV6 && !a.IsIPv6LinkLocal && !a.ToString().StartsWith("fec0")).Select(a => (object)a.ToString()).ToList() });
                }
                Netsh($"interface ipv4 set dnsservers name=\"{name}\" source=static address={V4[0]} register=primary validate=no");
                Netsh($"interface ipv4 add dnsservers name=\"{name}\" address={V4[1]} index=2 validate=no");
                Netsh($"interface ipv6 set dnsservers name=\"{name}\" source=static address={V6[0]} register=primary validate=no");
                Netsh($"interface ipv6 add dnsservers name=\"{name}\" address={V6[1]} index=2 validate=no");
            }
            foreach (var s in V4.Concat(V6)) { Netsh($"dns delete encryption server={s}"); Netsh($"dns add encryption server={s} dohtemplate={Template} autoupgrade=yes udpfallback=yes"); }
            Directory.CreateDirectory(Path.GetDirectoryName(BackupPath));
            File.WriteAllText(BackupPath, Json.Write(new Dictionary<string, object> { ["Provider"] = "AdGuard", ["SavedAt"] = DateTime.Now.ToString("o"), ["Adapters"] = saved }));
            Hosts(true);
            Netsh("interface ip delete destinationcache"); Run("ipconfig.exe", "/flushdns");
            Log.Write("adblock-dns-on adapters=" + saved.Count);
        }
        static void Disable()
        {
            if (!File.Exists(BackupPath)) return;
            var doc = Json.Obj(Json.Parse(File.ReadAllText(BackupPath)));
            var pending = new List<object>();
            var present = new HashSet<string>(NetworkInterface.GetAllNetworkInterfaces().Select(n => n.Name));
            foreach (var a in Json.Arr(Json.Get(doc, "Adapters")).Select(Json.Obj))
            {
                string name = Json.Str(a, "Name");
                if (!present.Contains(name)) { pending.Add(a); continue; } // adapter unplugged: keep its backup
                if (Json.Bool(a, "Dhcp", true)) { Netsh($"interface ipv4 set dnsservers name=\"{name}\" source=dhcp"); Netsh($"interface ipv6 set dnsservers name=\"{name}\" source=dhcp"); }
                else
                {
                    var v4 = Json.Arr(Json.Get(a, "IPv4")).Select(x => x.ToString()).ToList(); var v6 = Json.Arr(Json.Get(a, "IPv6")).Select(x => x.ToString()).ToList();
                    if (v4.Count == 0) Netsh($"interface ipv4 set dnsservers name=\"{name}\" source=dhcp");
                    for (int i = 0; i < v4.Count; i++) Netsh(i == 0 ? $"interface ipv4 set dnsservers name=\"{name}\" source=static address={v4[i]} register=primary validate=no" : $"interface ipv4 add dnsservers name=\"{name}\" address={v4[i]} index={i + 1} validate=no");
                    if (v6.Count == 0) Netsh($"interface ipv6 set dnsservers name=\"{name}\" source=dhcp");
                    for (int i = 0; i < v6.Count; i++) Netsh(i == 0 ? $"interface ipv6 set dnsservers name=\"{name}\" source=static address={v6[i]} register=primary validate=no" : $"interface ipv6 add dnsservers name=\"{name}\" address={v6[i]} index={i + 1} validate=no");
                }
            }
            foreach (var s in V4.Concat(V6)) Netsh($"dns delete encryption server={s}");
            Hosts(false);
            if (pending.Count > 0) { doc["Adapters"] = pending; File.WriteAllText(BackupPath, Json.Write(doc)); } else File.Delete(BackupPath);
            Run("ipconfig.exe", "/flushdns");
            Log.Write("adblock-dns-off pendingAdapters=" + pending.Count);
        }
        // A second layer in the Windows hosts file for ad, analytics and error-tracking hosts that DNS block
        // lists miss (BlockedDomains.txt). Only the marked BAKA section is ever written or removed.
        const string Begin = "# >>> BAKA blocked domains (managed by BAKA Settings > Privacy & ads)", End = "# <<< BAKA blocked domains";
        static void Hosts(bool on)
        {
            string hosts = Path.Combine(Environment.SystemDirectory, @"drivers\etc\hosts");
            try
            {
                var lines = File.Exists(hosts) ? File.ReadAllLines(hosts).ToList() : new List<string>();
                int b = lines.IndexOf(Begin), e = lines.IndexOf(End);
                if (b >= 0 && e > b) lines.RemoveRange(b, e - b + 1);
                if (on)
                {
                    string list = Paths.Shipped("BlockedDomains.txt");
                    var domains = list == null ? new List<string>() : File.ReadAllLines(list).Select(l => l.Trim()).Where(l => l.Length > 0 && !l.StartsWith("#") && System.Text.RegularExpressions.Regex.IsMatch(l, @"^[a-z0-9.-]+$")).Distinct().ToList();
                    lines.Add(Begin); lines.AddRange(domains.Select(d => "0.0.0.0 " + d)); lines.Add(End);
                }
                File.WriteAllLines(hosts, lines);
                Log.Write("hosts-blocklist on=" + on);
            }
            catch (Exception ex) { Log.Write("hosts-blocklist-failed error=\"" + ex.Message + "\""); }
        }
        static bool IsDhcpDns(string id)
        {
            try
            {
                using (var k = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\" + id))
                    return string.IsNullOrWhiteSpace(k?.GetValue("NameServer") as string);
            }
            catch { return true; }
        }
        static void Netsh(string args) => Run("netsh.exe", args);
        static void Run(string exe, string args)
        {
            try
            {
                var p = Process.Start(new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, exe), args) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true });
                p.StandardOutput.ReadToEnd(); p.WaitForExit(15000);
                if (p.ExitCode != 0) Log.Write("command-exit code=" + p.ExitCode + " cmd=\"" + exe + " " + args + "\"");
            }
            catch (Exception e) { Log.Write("command-failed cmd=\"" + exe + " " + args + "\" error=\"" + e.Message + "\""); }
        }
    }
}
