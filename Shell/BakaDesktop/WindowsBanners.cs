using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.Win32;

namespace Baka.Desktop
{
    // With the helper Explorer running, Windows shows its own notification banner next to BAKA's pop-up, so
    // every notification came twice. While BAKA shows the pop-ups, Windows' banners are switched off per app:
    // the "Show notification banners" switch of Settings > System > Notifications > (app), stored as
    // HKCU\...\Notifications\Settings\<app id>\ShowBanner = 0. The notifications still go to Windows'
    // notification list, which is where BAKA reads them from. Measured on this PC (12.27.1): the switch takes
    // effect at once, Windows showed no banner and BAKA's pop-up came as before.
    //
    // Alarms, timers and incoming calls keep Windows' banner (it stays until answered; BAKA's goes after 6 s),
    // and BAKA shows no pop-up of its own for those, so they still come once.
    // What each app had before is kept in State\windows-banners.json. Restore() puts it back: Leave BAKA,
    // --restore-windows, the setting turned off, or BAKA no longer the shell. A value the user changed since
    // is left alone. Setting: integration.hideWindowsBanners (default on).
    static class WindowsBanners
    {
        const string Root = @"Software\Microsoft\Windows\CurrentVersion\Notifications\Settings";
        static string BackupPath => Path.Combine(Paths.State, "windows-banners.json");
        static readonly string[] KeepWords = { "Alarm", "Calling", "Calls" };
        static readonly object gate = new object();

        // BAKA shows the pop-ups only when it is the chosen shell (NotificationPopup.Show)
        public static bool Wanted => !Paths.Preview && App.Settings != null && ShellMode.Chosen && Json.Bool(App.Settings.Integration, "hideWindowsBanners", true);
        public static bool Keeps(string appId) => !string.IsNullOrEmpty(appId) && KeepWords.Any(w => appId.IndexOf(w, StringComparison.OrdinalIgnoreCase) >= 0);

        // Settings changed, BAKA started, shell chosen or given up: switch the banners off or back on.
        public static void Update()
        {
            try { if (Wanted) { Apply(); Watch(true); } else { Watch(false); Restore(); } }
            catch (Exception e) { Log.Write("windows-banners-failed error=\"" + e.Message + "\""); }
        }

        public static void Apply()
        {
            lock (gate)
            {
                var apps = new List<string>();
                using (var root = Registry.CurrentUser.OpenSubKey(Root, false)) { if (root == null) return; Walk(root, "", 0, apps); }
                var backup = Load(); int changed = 0;
                foreach (var app in apps)
                {
                    if (Keeps(app)) continue;
                    try
                    {
                        using (var k = Registry.CurrentUser.OpenSubKey(Root + "\\" + app, true))
                        {
                            if (k == null) continue;
                            object v = k.GetValue("ShowBanner");
                            if (v is int i && i == 0) continue; // already off (BAKA's, or the user's own choice)
                            // BAKA switched it off before and it is on again: the user turned this app's banner
                            // back on in Windows' settings on purpose, so it stays on
                            if (backup.ContainsKey(app)) continue;
                            backup[app] = v is int n ? (object)n : null; // null: not set, Windows' default (on)
                            k.SetValue("ShowBanner", 0, RegistryValueKind.DWord);
                            changed++;
                        }
                    }
                    catch { }
                }
                if (changed > 0) { Save(backup); Log.Write("windows-banners off apps=" + changed + " kept=" + apps.Count(Keeps)); }
            }
        }

        public static void Restore()
        {
            lock (gate)
            {
                if (!File.Exists(BackupPath)) return;
                var backup = Load(); int restored = 0;
                foreach (var kv in backup)
                {
                    try
                    {
                        using (var k = Registry.CurrentUser.OpenSubKey(Root + "\\" + kv.Key, true))
                        {
                            if (k == null) continue;
                            if (!(k.GetValue("ShowBanner") is int cur && cur == 0)) continue; // changed by the user since
                            if (kv.Value == null) k.DeleteValue("ShowBanner", false); else k.SetValue("ShowBanner", Convert.ToInt32(kv.Value), RegistryValueKind.DWord);
                            restored++;
                        }
                    }
                    catch { }
                }
                try { File.Delete(BackupPath); } catch { }
                Log.Write("windows-banners restored apps=" + restored);
            }
        }

        // App ids can contain backslashes ("{GUID}\WindowsPowerShell\v1.0\powershell.exe"), so an app's key can
        // sit several levels down. A key with settings of its own, or with nothing below it, is an app.
        static void Walk(RegistryKey k, string path, int depth, List<string> apps)
        {
            string[] subs;
            try { subs = k.GetSubKeyNames(); } catch { return; }
            if (depth > 0 && (k.ValueCount > 0 || subs.Length == 0)) apps.Add(path);
            if (depth >= 6) return;
            foreach (var s in subs)
                try { using (var c = k.OpenSubKey(s, false)) if (c != null) Walk(c, path.Length == 0 ? s : path + "\\" + s, depth + 1, apps); } catch { }
        }

        static Dictionary<string, object> Load()
        {
            try { if (File.Exists(BackupPath) && Json.Parse(File.ReadAllText(BackupPath)) is Dictionary<string, object> d) return new Dictionary<string, object>(d, StringComparer.OrdinalIgnoreCase); }
            catch { }
            return new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
        }
        static void Save(Dictionary<string, object> backup)
        {
            try { Directory.CreateDirectory(Path.GetDirectoryName(BackupPath)); File.WriteAllText(BackupPath, Json.Write(backup)); }
            catch (Exception e) { Log.Write("windows-banners-save-failed error=\"" + e.Message + "\""); }
        }

        // A new app gets its key the first time it sends a notification: Windows tells BAKA (a registry change
        // notification, no polling) and its banner is switched off within moments. That first notification
        // can still show Windows' banner once.
        [DllImport("advapi32.dll")] static extern int RegNotifyChangeKeyValue(IntPtr key, bool subtree, uint filter, IntPtr ev, bool async);
        static Thread watcher;
        static ManualResetEvent stop;
        static void Watch(bool on)
        {
            if (on && watcher == null)
            {
                stop = new ManualResetEvent(false);
                watcher = new Thread(WatchLoop) { IsBackground = true, Name = "BAKA banners" };
                watcher.Start();
            }
            else if (!on && watcher != null) { stop.Set(); watcher = null; }
        }
        static void WatchLoop()
        {
            var myStop = stop;
            try
            {
                using (var root = Registry.CurrentUser.OpenSubKey(Root, false))
                using (var changed = new AutoResetEvent(false))
                {
                    if (root == null) return;
                    while (true)
                    {
                        if (RegNotifyChangeKeyValue(root.Handle.DangerousGetHandle(), true, 0x1 /*REG_NOTIFY_CHANGE_NAME: keys added*/, changed.SafeWaitHandle.DangerousGetHandle(), true) != 0) return;
                        if (WaitHandle.WaitAny(new WaitHandle[] { changed, myStop }) == 1) return;
                        Thread.Sleep(150); // the new key's first values
                        try { if (Wanted) Apply(); } catch { }
                    }
                }
            }
            catch (Exception e) { Log.Write("windows-banners-watch-failed error=\"" + e.Message + "\""); }
        }
    }
}
