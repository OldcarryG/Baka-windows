using System;
using System.Collections.Generic;

namespace Baka.Desktop
{
    // Focus: one switch for quiet time. No notification pop-ups (they still collect behind the bell), the
    // dock tucks away until the pointer reaches its edge, and the video wallpaper pauses. It turns itself on
    // while a game runs and off again when the game ends, unless it was turned on by hand.
    //
    // Replaces the bell panel's "Do not disturb" switch (integration.doNotDisturb is moved to focus.enabled).
    // Settings: focus.enabled (turned on by hand, kept across restarts), focus.autoInGames, focus.hideDock,
    // focus.pauseWallpaper.
    static class FocusMode
    {
        public static bool On { get; private set; }
        static bool automatic; // turned on by a game, so the game's end turns it off
        static int held;       // pop-ups held back while it was on
        public static event Action Changed;
        static Dictionary<string, object> S => App.Settings.Focus;

        // Focus that a game turned on with BAKA "Light" keeps the dock where it is: in Light the desktop stays
        // as it is during a game (a fullscreen game covers it anyway)
        public static bool HidesDock => On && App.Settings != null && Json.Bool(S, "hideDock", true) && !(automatic && App.GameRunning && App.LightGaming);
        public static bool PausesWallpaper => On && App.Settings != null && Json.Bool(S, "pauseWallpaper", true);

        public static void Init()
        {
            On = App.Settings != null && Json.Bool(S, "enabled");
            if (On) Log.Write("focus on reason=start");
        }

        public static void Toggle(string reason) => Set(!On, reason);

        public static void Set(bool on, string reason, bool auto = false)
        {
            if (on == On)
            {
                // turned on by hand while a game had it on already: the game's end must not turn it off
                if (on && !auto) { automatic = false; Save(true); }
                return;
            }
            On = on; automatic = on && auto;
            if (!auto) Save(on);
            int missed = held; if (!on) held = 0;
            Log.Write("focus " + (on ? "on" : "off") + " reason=" + reason + (on ? "" : " held=" + missed));
            try { App.Dock?.Place(); if (!on) App.EdgesChanged(); } catch (Exception e) { Log.Write("focus-dock-failed error=\"" + e.Message + "\""); }
            try { Wallpaper.Refresh(); } catch { }
            if (!auto) Osd.Show(on ? 0xE708 : 0xE7E7, on ? "Focus on  ·  no pop-ups" : missed > 0 ? "Focus off  ·  " + missed + " notification" + (missed == 1 ? "" : "s") + " came in" : "Focus off");
            else if (!on && missed > 0) Osd.Show(0xE7E7, missed + " notification" + (missed == 1 ? "" : "s") + " came in during the game");
            try { Changed?.Invoke(); } catch { }
        }
        static void Save(bool on)
        {
            if (App.Settings == null) return;
            S["enabled"] = on; App.Settings.Save();
        }

        // A notification arrived while Focus was on: no pop-up, but it is counted for the summary.
        public static void Held() { if (On) held++; }

        public static void GameStarted()
        {
            if (!On && App.Settings != null && Json.Bool(S, "autoInGames", true)) Set(true, "game", true);
        }
        public static void GameEnded()
        {
            if (On && automatic) Set(false, "game ended", true);
        }
    }
}
