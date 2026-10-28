// BAKA shell launcher. Windows starts this as the user's shell (HKCU Winlogon\Shell).
// It is a windowless program, so no console or Windows Terminal window ever appears, and it supervises
// the BAKA desktop for the whole session:
//   exit code 0  BAKA handed the session to Explorer on purpose -> launcher ends.
//   exit code 3  another BAKA desktop already runs              -> wait and watch.
//   other codes  BAKA stopped unexpectedly                      -> start it again.
//   3 unexpected stops within 2 minutes                         -> Explorer becomes the shell (safe fallback).
// Build: csc /target:winexe /out:BakaShell.exe BakaShell.cs   (the Windows built-in C# compiler is enough)
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using Microsoft.Win32;

static class BakaShell
{
    static string Log = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"BAKA\Logs\ShellHost.log");

    static void Write(string message)
    {
        try { Directory.CreateDirectory(Path.GetDirectoryName(Log)); File.AppendAllText(Log, DateTime.Now.ToString("o") + " " + message + Environment.NewLine); } catch { }
    }

    static bool ExplorerRunning()
    {
        int session = Process.GetCurrentProcess().SessionId;
        foreach (var p in Process.GetProcessesByName("explorer")) { try { if (p.SessionId == session) return true; } catch { } }
        return false;
    }

    static void StartExplorer(string reason)
    {
        // Explorer only becomes the shell when it is the configured one, so the BAKA override goes first.
        try { using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows NT\CurrentVersion\Winlogon", true)) { if (key != null) key.DeleteValue("Shell", false); } } catch { }
        if (!ExplorerRunning()) { try { Process.Start(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe")); } catch { } }
        Write("explorer-fallback reason=" + reason);
    }

    // Another BAKA desktop (started at first sign-in, before BAKA was the shell) holds the single-instance
    // lock. Block on that same lock instead of polling, then take over supervision when it is released.
    static void WaitForOtherDesktop()
    {
        string sid = System.Security.Principal.WindowsIdentity.GetCurrent().User.Value;
        string name = @"Local\BAKA.DesktopCompanion." + System.Text.RegularExpressions.Regex.Replace(sid, "[^A-Za-z0-9_.-]", "_");
        try
        {
            using (var mutex = System.Threading.Mutex.OpenExisting(name))
            {
                Write("waiting-for-running-desktop");
                try { mutex.WaitOne(); } catch (System.Threading.AbandonedMutexException) { }
                try { mutex.ReleaseMutex(); } catch { }
            }
        }
        catch { System.Threading.Thread.Sleep(3000); }
    }

    [STAThread]
    static int Main()
    {
        string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "BAKA");
        string companion = Path.Combine(root, @"Scripts\BakaCompanion.ps1");
        string powershell = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
        Write("shell-host-start");
        if (!File.Exists(companion)) { StartExplorer("companion-missing"); return 0; }
        var failures = new List<DateTime>();
        while (true)
        {
            var info = new ProcessStartInfo(powershell, "-NoProfile -STA -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + companion + "\"")
            {
                UseShellExecute = false,   // CreateProcess with no console: Windows Terminal is never involved
                CreateNoWindow = true,
                WorkingDirectory = Path.GetDirectoryName(companion)
            };
            DateTime started = DateTime.Now;
            int code;
            try { using (var p = Process.Start(info)) { p.WaitForExit(); code = p.ExitCode; } }
            catch (Exception e) { Write("start-failed " + e.Message); code = -1; }
            Write(string.Format("companion-exit code={0} ranSeconds={1:N0}", code, (DateTime.Now - started).TotalSeconds));
            if (ExplorerRunning()) { Write("explorer-is-shell; host stopping"); return 0; }
            if (code == 0) { StartExplorer("companion-exited"); return 0; }
            if (code == 3) { WaitForOtherDesktop(); if (ExplorerRunning()) { Write("explorer-is-shell after wait; host stopping"); return 0; } continue; }
            failures.Add(DateTime.Now);
            failures.RemoveAll(t => t < DateTime.Now.AddMinutes(-2));
            if (failures.Count >= 3) { StartExplorer("repeated-failures"); return 0; }
            System.Threading.Thread.Sleep(2000);
        }
    }
}
