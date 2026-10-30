using System;
using System.Threading;

namespace Baka.Desktop
{
    // Starting another program must NOT run on BAKA's UI thread. When BAKA is the Windows shell (Explorer not
    // running) the shell-activation calls behind UseShellExecute=true and the UWP ActivationManager can block
    // for seconds while Windows waits on the shell to broker the launch — and since BAKA *is* that shell,
    // waiting on the UI thread deadlocks the whole desktop (this is why opening the Store froze all of BAKA).
    // Running every launch on a short-lived background STA thread keeps the UI responsive and breaks the loop.
    static class Launcher
    {
        public static void Run(string what, Action launch) => Run(what, launch, false);
        static void Run(string what, Action launch, bool retried)
        {
            var t = new Thread(() =>
            {
                try { launch(); }
                catch (Exception e)
                {
                    Log.Write("launch-failed what=\"" + what + "\" error=\"" + e.Message + "\"");
                    // a Store app / Windows Settings with Explorer off: start it (on demand) or ask, then retry
                    if (ShellMode.IsMissingExplorer(e) && ShellMode.Chosen && !retried)
                        try { App.Ui.BeginInvoke(new Action(() => ShellMode.NeedExplorer(what, () => Run(what, launch, true)))); } catch { }
                }
            });
            t.IsBackground = true;
            t.SetApartmentState(ApartmentState.STA); // shell activation / COM needs an STA caller
            t.Start();
        }
    }
}
