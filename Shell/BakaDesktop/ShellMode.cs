using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace Baka.Desktop
{
    // BAKA as the Windows shell (instead of Explorer), for this account only. Explorer did several jobs
    // besides the taskbar; while BAKA is the shell it does them itself:
    //  - starts the apps set to run at sign-in (Run keys and Startup folders, honouring Task Manager's
    //    enabled / disabled switches)
    //  - keeps the screen edges of the menu bar and dock free (the work area; Explorer's app-bar manager is gone)
    //  - keeps minimized windows out of sight (without a shell Windows parks them as title bars bottom-left)
    // Everything here is inactive while Explorer is running, so nothing is done twice.
    static class ShellMode
    {
        const string WinlogonKey = @"Software\Microsoft\Windows NT\CurrentVersion\Winlogon";

        // The choice recorded in the registry: Windows starts BAKA instead of Explorer at sign-in.
        public static bool Chosen
        {
            get
            {
                try { using (var k = Registry.CurrentUser.OpenSubKey(WinlogonKey)) return (k?.GetValue("Shell") as string ?? "").IndexOf("BakaDesktop", StringComparison.OrdinalIgnoreCase) >= 0; }
                catch { return false; }
            }
        }
        // BAKA is doing the shell's jobs right now (chosen, and Explorer is not running in this session).
        // Remembered for 2 s: it reads the registry and lists every process, and the volume keys asked it on
        // every key repeat (about 30 times a second while a key was held).
        static bool activeCache; static DateTime activeAt = DateTime.MinValue;
        public static bool Active
        {
            get
            {
                if (Paths.Preview) return false;
                if ((DateTime.Now - activeAt).TotalSeconds < 2) return activeCache;
                activeCache = Chosen && !ExplorerIntegration.ExplorerRunning(); activeAt = DateTime.Now;
                return activeCache;
            }
        }
        public static void ForgetActive() { activeAt = DateTime.MinValue; }

        public static void Choose(bool baka)
        {
            if (Paths.Preview) return;
            try
            {
                using (var k = Registry.CurrentUser.CreateSubKey(WinlogonKey))
                {
                    if (baka) k.SetValue("Shell", "\"" + App.Exe + "\"", RegistryValueKind.String);
                    else k.DeleteValue("Shell", false);
                }
                App.Settings.Integration["shell"] = baka ? "BAKA" : "Explorer"; App.Settings.Save();
                Log.Write("shell-chosen " + (baka ? "BAKA" : "Explorer"));
                WindowsBanners.Update(); // BAKA's pop-ups only with BAKA as the shell; otherwise Windows' banners come back
            }
            catch (Exception e) { Log.Write("shell-choose-failed error=\"" + e.Message + "\""); }
        }

        // ---- the Windows apps helper: one hidden Explorer for this sign-in ----
        // Store apps and Windows Settings cannot start without Explorer: their window frame is built by
        // Explorer's "immersive shell", which only exists while an explorer.exe runs (activation fails with
        // 0x80040900 / "Class not registered" otherwise). No other shell reimplements it; Cairo, Starling and
        // Microsoft's own CustomShellHost all keep an Explorer. So BAKA starts one Explorer in the background,
        // hides its taskbar and desktop icons, and stays the shell the user sees. With it Windows also handles
        // Alt+Tab, the Win+ shortcuts, the volume overlay, minimized windows and notification banners natively.
        // It stays for the whole sign-in: starting and killing Explorer per launch breaks app frames.
        // Settings > Windows > Windows Explorer in the background:
        //   "Off" (default): no Explorer at all. Opening a Store app or Windows Settings asks once whether to
        //        start Explorer hidden until sign-out (they cannot open without it).
        //   "OnDemand": Explorer starts by itself, hidden, the first time a Store app or Settings is opened.
        //   "Always": Explorer starts hidden at sign-in (Store apps, notification banners, Salad and every
        //        Windows shortcut work from the start).
        // Two choices now: On (default) keeps one Explorer hidden in the background the whole session, so the
        // Store, Settings, notification banners and Salad's WSL check all work and open instantly; Off runs no
        // Explorer at all (those few things then fall back to BAKA's own panels or do not work). On-demand was
        // removed: cold-starting Explorer each time made the Store and Settings slow, and Salad's check ran
        // before Explorer was up. "Always" / "OnDemand" from older settings both read as On.
        public static string HelperMode
        {
            get
            {
                if (App.Settings == null) return "Always";
                return Json.Str(App.Settings.Integration, "explorerMode", "") == "Off" ? "Off" : "Always";
            }
        }
        public static bool Helper => HelperMode == "Always";
        static int helperStarts;
        static DateTime helperLastStart = DateTime.MinValue, helperNeededAt = DateTime.Now;
        static bool startedByUs;   // BAKA started this Explorer (so BAKA may close it again on demand)
        static readonly List<DateTime> recentStarts = new List<DateTime>();
        public static bool StartedThisSession => helperStarts > 0;
        public static void StartHelper(string reason, bool force = false)
        {
            if (Paths.Preview || !Chosen || ExplorerIntegration.ExplorerRunning()) return;
            if (!force && HelperMode != "Always") return;
            // Rate limit so Explorer never flaps: at most 5 starts in 10 minutes, at least 15 s apart. The cap
            // used to count the whole sign-in, so after Explorer had crashed 5 times nothing (not even opening
            // the Store, which asks with force) could start it again until sign-out, and nobody was told.
            recentStarts.RemoveAll(t => (DateTime.Now - t).TotalMinutes > 10);
            if ((DateTime.Now - helperLastStart).TotalSeconds < 15) return;
            if (recentStarts.Count >= 5)
            {
                if (force) Osd.Show(0xE7BA, "Windows Explorer keeps closing · try again in a few minutes");
                Log.Write("explorer-helper-rate-limited reason=" + reason);
                return;
            }
            recentStarts.Add(DateTime.Now);
            helperStarts++; helperLastStart = DateTime.Now; helperNeededAt = DateTime.Now; startedByUs = true;
            // Explorer registers the Win+ shortcuts when it starts: a key BAKA still holds then is lost to it
            // for the whole sign-in, so BAKA lets go of them first.
            ShellKeys.ReleaseAll();
            try
            {
                Process.Start(new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe")) { UseShellExecute = false })?.Dispose();
                ForgetActive();
                Log.Write("explorer-helper-started reason=" + reason + " count=" + helperStarts);
            }
            catch (Exception e) { Log.Write("explorer-helper-failed error=\"" + e.Message + "\""); }
        }

        // On-demand: is a running Explorer still doing something only it can do? A Store / Settings / other UWP
        // window is on screen, or (optionally) Salad is running and borrowing Explorer's token for WSL. When
        // none of these hold for a while, BAKA closes Explorer again.
        public static bool HelperNeeded()
        {
            try
            {
                bool uwp = false;
                Native.EnumWindows((h, l) =>
                {
                    if (!Native.IsWindowVisible(h) || Native.IsIconic(h) || Native.IsCloaked(h)) return true;
                    string cls = Native.ClassName(h);
                    // a framed Store/Settings app window (ApplicationFrameHost) or a bare UWP CoreWindow
                    if (cls == "ApplicationFrameWindow" || cls == "Windows.UI.Core.CoreWindow") { uwp = true; return false; }
                    return true;
                }, IntPtr.Zero);
                if (uwp) return true;
                if (App.Settings != null && Json.Bool(App.Settings.Integration, "keepExplorerForSalad", true))
                    foreach (var p in Process.GetProcessesByName("Salad")) { p.Dispose(); return true; }
            }
            catch { }
            return false;
        }

        // Called every few seconds (App guard). OnDemand only: closes the Explorer BAKA started once it has
        // been idle (nothing needs it) for a grace period, so Explorer is gone when you are not using a Store
        // app, Settings or Salad.
        public static void MaybeCloseIdleHelper()
        {
            if (HelperMode != "OnDemand" || !startedByUs || !ExplorerIntegration.ExplorerRunning()) return;
            if (HelperNeeded()) { helperNeededAt = DateTime.Now; return; }
            if ((DateTime.Now - helperNeededAt).TotalSeconds < 90) return;   // let a just-closed app settle
            CloseHelper("idle");
        }
        // Closes the background Explorer: only the process that owns the (hidden) taskbar, never a File
        // Explorer window the user opened (those can run as separate explorer.exe processes, and killing them
        // used to stop any copy in progress). After a BAKA restart it was not "started by us" any more, so
        // the Off switch did nothing while it said Off; the taskbar's owner is closed in that case too.
        public static void CloseHelper(string reason)
        {
            if (!Chosen) return;
            startedByUs = false;
            IntPtr bar = ExplorerIntegration.ExplorerTaskbar();
            if (bar == IntPtr.Zero) return;
            Native.GetWindowThreadProcessId(bar, out uint pid);
            try { using (var p = Process.GetProcessById((int)pid)) if (p.ProcessName.Equals("explorer", StringComparison.OrdinalIgnoreCase)) p.Kill(); }
            catch (Exception e) { Log.Write("explorer-helper-close-failed error=\"" + e.Message + "\""); return; }
            Log.Write("explorer-helper-closed reason=" + reason + " pid=" + pid);
        }

        // A Store app / Settings could not start because Explorer is not running (0x80040900, "Class not
        // registered"). On demand: start Explorer and try again. Off: ask once per sign-in.
        public static bool IsMissingExplorer(Exception e)
        {
            if (e == null) return false;
            int hr = e is System.ComponentModel.Win32Exception w ? w.NativeErrorCode : e.HResult;
            string m = e.Message ?? "";
            return hr == unchecked((int)0x80040900) || hr == unchecked((int)0x80040154) || m.Contains("0x80040900") || m.Contains("Class not registered");
        }
        public static void NeedExplorer(string what, Action retry)
        {
            if (Paths.Preview || !Chosen) return;
            if (ExplorerIntegration.ExplorerRunning()) return;
            if (HelperMode == "Off")
            {
                // Explorer stays off: a Settings page opens its classic Windows panel directly, everything else
                // gets BAKA's Windows settings panel (with "start Explorer" only as an explicit last resort)
                Log.Write("explorer-needed what=\"" + what + "\" -> BAKA panel");
                WindowsSettingsPanel.Show(what, retry);
                return;
            }
            StartHelper("needed-by " + what, true);
            // Store apps start once Explorer has finished starting its app frame machinery (about 3 s)
            new System.Threading.Thread(() =>
            {
                for (int i = 0; i < 40 && !ExplorerIntegration.ExplorerRunning(); i++) System.Threading.Thread.Sleep(250);
                System.Threading.Thread.Sleep(3500);
                try { retry?.Invoke(); } catch (Exception e) { Log.Write("explorer-needed-retry-failed error=\"" + e.Message + "\""); }
            }) { IsBackground = true }.Start();
        }

        // Called once the desktop is up.
        public static void Start()
        {
            if (!Active) return;
            Log.Write("shell-mode active helper=" + Helper);
            HideMinimizedWindows();
            AppBars.UseWorkArea = true; AppBars.ApplyWorkArea();
            BakaTray.Start();
            if (Helper)
            {
                // Explorer runs the sign-in apps itself (once per sign-in, honouring Task Manager's switches),
                // so BAKA does not start them a second time.
                StartHelper("sign-in");
                // safety net: 30 s later, any sign-in app that is still not running is started by BAKA
                new System.Threading.Thread(() => { System.Threading.Thread.Sleep(30000); RunStartupApps(true); }) { IsBackground = true, Name = "BAKA startup check" }.Start();
                return;
            }
            var t = new System.Threading.Thread(RunStartupApps) { IsBackground = true, Name = "BAKA startup apps" };
            t.Start();
        }

        // ---- minimized windows: hidden (the dock shows and restores them), not parked bottom-left ----
        [StructLayout(LayoutKind.Sequential)] struct MINIMIZEDMETRICS { public int cbSize, iWidth, iHorzGap, iVertGap, iArrange; }
        [DllImport("user32.dll")] static extern bool SystemParametersInfo(uint action, uint param, ref MINIMIZEDMETRICS data, uint winIni);
        static void HideMinimizedWindows()
        {
            try
            {
                var m = new MINIMIZEDMETRICS { cbSize = Marshal.SizeOf(typeof(MINIMIZEDMETRICS)) };
                SystemParametersInfo(0x002B /*SPI_GETMINIMIZEDMETRICS*/, (uint)m.cbSize, ref m, 0);
                m.iArrange |= 0x0008; // ARW_HIDE: park minimized windows off-screen, not as a bar bottom-left
                m.iWidth = 0; m.iHorzGap = 0; m.iVertGap = 0;
                // SPIF_SENDCHANGE (0x02) broadcasts WM_SETTINGCHANGE so the new metric takes effect now;
                // without it the value was set but never applied, so windows still parked as a black bar.
                SystemParametersInfo(0x002C /*SPI_SETMINIMIZEDMETRICS*/, (uint)m.cbSize, ref m, 0x02);
            }
            catch (Exception e) { Log.Write("minimized-metrics-failed error=\"" + e.Message + "\""); }
        }

        // ---- apps that start at sign-in ----
        static void RunStartupApps() => RunStartupApps(false);
        // onlyMissing: Explorer (the helper) already started the sign-in apps; start only the ones whose program
        // is not running, so nothing is started twice.
        static void RunStartupApps(bool onlyMissing)
        {
            try
            {
                if (onlyMissing)
                {
                    var running = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                    foreach (var p in Process.GetProcesses()) { try { running.Add(p.ProcessName); } catch { } finally { p.Dispose(); } }
                    int started = 0, already = 0;
                    foreach (var (name, command) in Entries())
                    {
                        if (command.IndexOf("BakaDesktop", StringComparison.OrdinalIgnoreCase) >= 0) continue;
                        string exe = ProgramOf(command);
                        if (exe.Length > 0 && running.Contains(exe)) { already++; continue; }
                        if (exe.Length == 0) continue; // a shortcut or script: can't tell, so leave it to Explorer
                        if (Launch(command)) { started++; Log.Write("startup-app-missing-started name=\"" + name + "\""); }
                        System.Threading.Thread.Sleep(250);
                    }
                    Log.Write("startup-apps-checked running=" + already + " started=" + started);
                    return;
                }
                // once per sign-in: a desktop restart after a crash must not start them all again
                string marker = Path.Combine(Paths.State, "startup-apps.txt");
                // the supervisor is started once per sign-in (by Windows, as the shell) and tells its desktop when
                string session = Process.GetCurrentProcess().SessionId + "|" + (Environment.GetEnvironmentVariable("BAKA_LOGON") ?? LogonTime());
                try { if (File.Exists(marker) && File.ReadAllText(marker).Trim() == session) { Log.Write("startup-apps-already-run"); return; } } catch { }
                try { File.WriteAllText(marker, session); } catch { }
                System.Threading.Thread.Sleep(2500); // let the desktop settle first, like Explorer does
                int n = 0;
                foreach (var (name, command) in Entries())
                {
                    if (command.IndexOf("BakaDesktop", StringComparison.OrdinalIgnoreCase) >= 0) continue;
                    if (Launch(command)) { n++; Log.Write("startup-app name=\"" + name + "\""); } else Log.Write("startup-app-failed name=\"" + name + "\" command=\"" + command + "\"");
                    System.Threading.Thread.Sleep(250);
                }
                Log.Write("startup-apps-started count=" + n);
            }
            catch (Exception e) { Log.Write("startup-apps-failed error=\"" + e.Message + "\""); }
        }
        static string LogonTime() { try { return Process.GetCurrentProcess().StartTime.ToString("yyyyMMddHHmmss"); } catch { return ""; } }

        // The same list Task Manager's "Startup apps" shows, minus the ones switched off there.
        public static IEnumerable<(string name, string command)> Entries()
        {
            var list = new List<(string, string)>();
            void FromKey(RegistryKey root, string path, string approvedPath, RegistryView view)
            {
                try
                {
                    using (var b = RegistryKey.OpenBaseKey(root == Registry.LocalMachine ? RegistryHive.LocalMachine : RegistryHive.CurrentUser, view))
                    using (var k = b.OpenSubKey(path))
                    {
                        if (k == null) return;
                        foreach (var n in k.GetValueNames())
                        {
                            if (string.IsNullOrEmpty(n)) continue;
                            string cmd = k.GetValue(n) as string;
                            if (string.IsNullOrWhiteSpace(cmd) || Disabled(root, approvedPath, n)) continue;
                            list.Add((n, cmd));
                        }
                    }
                }
                catch { }
            }
            const string run = @"Software\Microsoft\Windows\CurrentVersion\Run";
            const string approved = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\";
            FromKey(Registry.CurrentUser, run, approved + "Run", RegistryView.Default);
            FromKey(Registry.LocalMachine, run, approved + "Run", RegistryView.Registry64);
            FromKey(Registry.LocalMachine, run, approved + "Run32", RegistryView.Registry32);
            foreach (var dir in new[] { Environment.GetFolderPath(Environment.SpecialFolder.Startup), Environment.GetFolderPath(Environment.SpecialFolder.CommonStartup) })
            {
                try
                {
                    if (!Directory.Exists(dir)) continue;
                    bool common = dir == Environment.GetFolderPath(Environment.SpecialFolder.CommonStartup);
                    foreach (var f in Directory.GetFiles(dir))
                    {
                        string fn = Path.GetFileName(f);
                        if (fn.Equals("desktop.ini", StringComparison.OrdinalIgnoreCase)) continue;
                        if (Disabled(common ? Registry.LocalMachine : Registry.CurrentUser, approved + "StartupFolder", fn)) continue;
                        list.Add((Path.GetFileNameWithoutExtension(f), "\"" + f + "\""));
                    }
                }
                catch { }
            }
            return list;
        }
        // Task Manager writes 12 bytes per entry; an odd first byte means "disabled".
        static bool Disabled(RegistryKey root, string path, string name)
        {
            try
            {
                using (var k = root.OpenSubKey(path))
                    if (k?.GetValue(name) is byte[] b && b.Length > 0) return (b[0] & 1) == 1;
            }
            catch { }
            return false;
        }
        // The program name (no extension) a Run-key command starts, or "" when it is not an .exe.
        static string ProgramOf(string command)
        {
            try
            {
                string cmd = Environment.ExpandEnvironmentVariables(command.Trim()), file;
                if (cmd.StartsWith("\"")) { int end = cmd.IndexOf('"', 1); if (end < 0) return ""; file = cmd.Substring(1, end - 1); }
                else { int exe = cmd.IndexOf(".exe", StringComparison.OrdinalIgnoreCase); file = exe > 0 ? cmd.Substring(0, exe + 4) : cmd; }
                return file.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? Path.GetFileNameWithoutExtension(file) : "";
            }
            catch { return ""; }
        }
        static bool Launch(string command)
        {
            try
            {
                string cmd = Environment.ExpandEnvironmentVariables(command.Trim()), file, args = "";
                if (cmd.StartsWith("\"")) { int end = cmd.IndexOf('"', 1); if (end < 0) return false; file = cmd.Substring(1, end - 1); args = cmd.Substring(end + 1).Trim(); }
                else
                {
                    int exe = cmd.IndexOf(".exe", StringComparison.OrdinalIgnoreCase);
                    if (exe > 0) { file = cmd.Substring(0, exe + 4); args = cmd.Substring(exe + 4).Trim(); }
                    else { int sp = cmd.IndexOf(' '); file = sp > 0 ? cmd.Substring(0, sp) : cmd; args = sp > 0 ? cmd.Substring(sp + 1) : ""; }
                }
                var psi = new ProcessStartInfo(file, args) { UseShellExecute = true };
                try { string d = Path.GetDirectoryName(file); if (!string.IsNullOrEmpty(d) && Directory.Exists(d)) psi.WorkingDirectory = d; } catch { }
                Process.Start(psi)?.Dispose();
                return true;
            }
            catch { return false; }
        }
    }
}
