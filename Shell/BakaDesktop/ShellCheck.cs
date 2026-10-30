using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace Baka.Desktop
{
    // In-process check of the shell-mode replacements. Safe: it does not stop Explorer, change the shell
    // registry value or touch the live desktop. It builds the tray host, runs a real tray icon through the
    // receive path, and checks the audio and language helpers. Run with: BakaDesktop.exe --shellcheck <json>.
    static class ShellCheck
    {
        public static int Run(string result)
        {
            Paths.Init(false);
            Theme.Load(); Theme.Apply("BAKA Carbon", "#FAFAFA");
            var r = new Dictionary<string, object>();
            bool ok = true;

            // Tray: create the Shell_NotifyIcon host and push a real NOTIFYICONDATA through it.
            try
            {
                BakaTray.Start(true);
                bool created = BakaTray.HostHandle != IntPtr.Zero;
                r["trayHostWindow"] = created;
                bool got = created && BakaTray.ReceiveForTest();
                r["trayReceivedAndRenderedIcon"] = got;
                r["trayIconCount"] = BakaTray.Items.Count;
                ok &= created && got;
                BakaTray.Stop();
            }
            catch (Exception e) { r["trayError"] = e.Message; ok = false; }

            // Volume: the audio endpoint must be readable (the volume keys set it in shell mode).
            try { int? v = Audio.Level; r["audioLevelReadable"] = v != null; r["audioLevel"] = v; ok &= v != null; }
            catch (Exception e) { r["audioError"] = e.Message; ok = false; }

            // Language badge helpers.
            try { r["layoutCount"] = ShellExtras.LayoutCount(); r["currentLanguage"] = ShellExtras.CurrentLanguage(); }
            catch (Exception e) { r["langError"] = e.Message; }

            // (The notification listener is verified on the live desktop via the log, not here: waiting on a
            // WinRT async from this single-threaded test process deadlocks.)

            r["result"] = ok ? "Passed" : "Failed";
            try { File.WriteAllText(result, ToJson(r)); } catch { }
            return ok ? 0 : 1;
        }

        static string ToJson(Dictionary<string, object> r)
        {
            var sb = new StringBuilder("{\n"); int i = 0;
            foreach (var kv in r)
            {
                string v = kv.Value == null ? "null" : kv.Value is string s ? "\"" + s.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"" : kv.Value is bool b ? (b ? "true" : "false") : Convert.ToString(kv.Value, System.Globalization.CultureInfo.InvariantCulture);
                sb.Append("  \"").Append(kv.Key).Append("\": ").Append(v).Append(++i < r.Count ? ",\n" : "\n");
            }
            return sb.Append("}\n").ToString();
        }
    }
}
