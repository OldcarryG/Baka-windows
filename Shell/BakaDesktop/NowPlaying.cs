using System;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using System.Windows.Media.Imaging;
using Windows.Media.Control;

namespace Baka.Desktop
{
    // What is playing right now (Spotify, a browser tab, Media Player...) as Windows' own media controls
    // know it: title, artist, album art and play state, plus play / pause / next / previous on that app.
    // Everything WinRT lives in Gsmtc below; if Windows can't provide it, the media widget and the clock
    // island fall back to the media keys and simply show no track.
    static class NowPlaying
    {
        public static string Title = "", Artist = "", Source = "";
        public static BitmapSource Art;
        public static bool Playing, Available;
        public static bool HasMedia => !string.IsNullOrEmpty(Title);
        public static event Action Changed;
        static bool started;
        static string lastLogged = "";

        public static void Start()
        {
            if (started) return; started = true;
            try { Init(); } catch (Exception e) { Log.Write("media-session-unavailable error=\"" + e.Message + "\""); }
        }
        [MethodImpl(MethodImplOptions.NoInlining)] static void Init() => Gsmtc.Init();

        public static void PlayPause() { if (!Command(0)) Native.SendMediaKey(0xB3); }
        public static void Next() { if (!Command(1)) Native.SendMediaKey(0xB0); }
        public static void Previous() { if (!Command(2)) Native.SendMediaKey(0xB1); }
        static bool Command(int which) { if (!Available) return false; try { return Run(which); } catch { return false; } }
        [MethodImpl(MethodImplOptions.NoInlining)] static bool Run(int which) => Gsmtc.Command(which);

        // Called from any thread; the picture is decoded and the UI told on the UI thread.
        internal static void Set(string title, string artist, string source, byte[] art, bool playing)
        {
            App.Ui?.BeginInvoke(new Action(() =>
            {
                BitmapSource bmp = null;
                if (art != null && art.Length > 0)
                {
                    try
                    {
                        var b = new BitmapImage(); b.BeginInit(); b.CacheOption = BitmapCacheOption.OnLoad; b.DecodePixelWidth = 192; b.StreamSource = new MemoryStream(art); b.EndInit(); b.Freeze();
                        bmp = b;
                    }
                    catch { }
                }
                Title = title ?? ""; Artist = artist ?? ""; Source = source ?? ""; Art = bmp; Playing = playing;
                string key = Title + "|" + Artist + "|" + Playing + "|" + (bmp != null);
                // the log says which app plays, never what (media titles are private: videos, sites)
                if (key != lastLogged) { lastLogged = key; Log.Write("now-playing source=\"" + Source + "\" playing=" + Playing + " hasTitle=" + (Title.Length > 0) + " art=" + (bmp != null)); }
                try { Changed?.Invoke(); } catch (Exception e) { Log.Write("now-playing-ui-failed error=\"" + e.Message + "\""); }
            }));
        }
    }

    // Windows.Media.Control (the "global system media transport controls" session manager).
    static class Gsmtc
    {
        static GlobalSystemMediaTransportControlsSessionManager manager;
        static GlobalSystemMediaTransportControlsSession session;
        static int version;

        public static void Init()
        {
            InitAsync().ContinueWith(t => Log.Write("media-session-failed error=\"" + t.Exception?.GetBaseException().Message + "\""), TaskContinuationOptions.OnlyOnFaulted);
        }
        static async Task InitAsync()
        {
            manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
            if (manager == null) { Log.Write("media-session-unavailable"); return; }
            NowPlaying.Available = true;
            manager.CurrentSessionChanged += OnSessionChanged;
            Attach();
            Log.Write("media-session-ready");
        }
        static void OnSessionChanged(GlobalSystemMediaTransportControlsSessionManager m, CurrentSessionChangedEventArgs a) => Attach();
        static void OnProps(GlobalSystemMediaTransportControlsSession s, MediaPropertiesChangedEventArgs a) => Refresh();
        static void OnPlayback(GlobalSystemMediaTransportControlsSession s, PlaybackInfoChangedEventArgs a) => Refresh();

        static readonly object gate = new object();
        static void Attach()
        {
            try
            {
                lock (gate)
                {
                    var s = manager?.GetCurrentSession();
                    if (!ReferenceEquals(s, session))
                    {
                        if (session != null) { try { session.MediaPropertiesChanged -= OnProps; session.PlaybackInfoChanged -= OnPlayback; } catch { } }
                        session = s;
                        if (s != null) { s.MediaPropertiesChanged += OnProps; s.PlaybackInfoChanged += OnPlayback; }
                    }
                }
            }
            catch (Exception e) { Log.Write("media-session-attach-failed error=\"" + e.Message + "\""); }
            Refresh();
        }

        static void Refresh() { RefreshAsync().ContinueWith(t => { var _ = t.Exception; }, TaskContinuationOptions.OnlyOnFaulted); }
        static async Task RefreshAsync()
        {
            int v = System.Threading.Interlocked.Increment(ref version);
            var s = session;
            if (s == null) { NowPlaying.Set("", "", "", null, false); return; }
            try
            {
                var props = await s.TryGetMediaPropertiesAsync();
                var info = s.GetPlaybackInfo();
                bool playing = info != null && info.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing;
                byte[] art = null;
                if (props?.Thumbnail != null)
                {
                    try
                    {
                        using (var ws = await props.Thumbnail.OpenReadAsync())
                        using (var st = ws.AsStreamForRead())
                        using (var ms = new MemoryStream())
                        {
                            await st.CopyToAsync(ms);
                            art = ms.ToArray();
                        }
                    }
                    catch { art = null; }
                }
                if (v != version) return; // a newer update already started
                NowPlaying.Set(props?.Title, props?.Artist, SourceName(s.SourceAppUserModelId), art, playing);
            }
            catch (Exception e) { Log.Write("now-playing-read-failed error=\"" + e.Message + "\""); }
        }

        static string SourceName(string aumid)
        {
            if (string.IsNullOrEmpty(aumid)) return "";
            var hit = AppCatalog.Apps.FirstOrDefault(a => string.Equals(a.AppId, aumid, StringComparison.OrdinalIgnoreCase));
            if (hit != null) return hit.Name;
            string n = aumid;
            if (n.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) n = n.Substring(0, n.Length - 4);
            int bang = n.IndexOf('!'); if (bang > 0) n = n.Substring(bang + 1);
            if (n.Equals("MSEdge", StringComparison.OrdinalIgnoreCase)) return "Microsoft Edge";
            // Apps built on the Edge web engine (Baka Browser, WhatsApp...) all report "msedgewebview2":
            // name the one that is running rather than showing the engine's internal name.
            if (n.Equals("msedgewebview2", StringComparison.OrdinalIgnoreCase))
            {
                try { if (System.Diagnostics.Process.GetProcessesByName("baka").Length > 0) return "Baka Browser"; } catch { }
                return "Browser";
            }
            if (n.Equals("chrome", StringComparison.OrdinalIgnoreCase)) return "Google Chrome";
            if (n.Equals("firefox", StringComparison.OrdinalIgnoreCase)) return "Firefox";
            if (n.Equals("Spotify", StringComparison.OrdinalIgnoreCase)) return "Spotify";
            return n;
        }

        public static bool Command(int which)
        {
            var s = session;
            if (s == null) return false;
            if (which == 0) { var _ = s.TryTogglePlayPauseAsync(); }
            else if (which == 1) { var _ = s.TrySkipNextAsync(); }
            else { var _ = s.TrySkipPreviousAsync(); }
            return true;
        }
    }
}
