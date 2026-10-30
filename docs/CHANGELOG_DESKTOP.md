# BAKA Desktop changelog

BAKA Desktop is the app in `C:\ProgramData\BAKA\Desktop\BakaDesktop.exe`: the menu bar, dock, Launchpad, BAKA Files, Control Center, Settings, widgets and everything else you see on BAKA Windows. Since R15 it is updated on its own, without a new ISO. How to install an update: [Update BAKA Desktop](../README.md#update-baka-desktop).

R15 (2026-10-29) shipped BAKA Desktop 12.0. Everything below came after it. This page lists the changes version by version. The complete list of every new feature, change and bug fix since R15, grouped by area, is in the README: [Changes since R15](../README.md#changes-since-r15).

## 12.27.2 (2026-10-30)

- **WebP wallpapers work.** A WebP picture chosen in Settings > Wallpaper (or with `--wallpaper`) was replaced with the BAKA BlackGlass picture, and the replacement was saved over the choice. BAKA now converts the picture once to PNG with Windows' own WebP decoder (WIC, the WebP Image Extension), off the UI thread, and gives Windows the PNG. The user's file stays the setting; the converted copy is kept in `%LOCALAPPDATA%\BAKA\State\Wallpaper` (only the newest). If Windows cannot read the picture, an on-screen message says so and the BAKA picture is shown.
- **Settings > Menu bar > "Show the date" works.** On: the clock island shows the short date next to the time. Off: only the time, with the full date when the pointer is over the clock. Since the menu bar redesign the switch did nothing while it read "on", so the update sets it to off once (settings revision 18) and the menu bar looks the same until you turn it on.
- The self-test checks the date switch in both positions.

## 12.27.1 (2026-10-30)

- **Each notification comes once.** With the hidden Explorer running, Windows showed its own banner next to BAKA's pop-up. BAKA now switches off Windows' "Show notification banners" option for every app while BAKA shows the pop-ups. Notifications still go to Windows' notification list, which is where BAKA reads them from. Each app's previous setting is saved and put back if you turn this off (Settings > Focus & games), leave BAKA, or stop using BAKA as the shell. An app's banner that you turn back on in Windows Settings stays on. Alarms, timers and calls keep Windows' banner (it stays until answered) and get no second pop-up from BAKA. A brand-new app's very first notification can still show Windows' banner once.

## 12.27.0 (2026-10-30)

- **Game overlay** (Ctrl+Alt+F, also inside games; or Control Center > Game overlay). A small see-through strip in a corner of the screen: FPS, CPU, GPU load and GPU temperature, or in the Full view also the 1% low, frame time, video memory, GPU power and RAM. Clicks go through it and it never takes the keyboard.
  - FPS comes from Windows' own graphics event log (ETW: DXGI, Direct3D 9 and the kernel's present events), the way Xbox Game Bar and PresentMon measure it. Nothing is injected into games, so anti-cheat (Vanguard, EAC) has nothing to object to. Windows filters the events down to one per frame before they reach BAKA.
  - FPS needs a one-time permission: Settings > Focus & games > **Allow the FPS counter** adds your account to Windows' "Performance Log Users" group (the same step Xbox Game Bar asks for), then sign out and back in. CPU, GPU and temperature work without it.
  - GPU temperature, power and video memory come from the NVIDIA driver's own sensor library (nvml.dll). Other GPUs show GPU load only.
  - Shows over borderless and windowed games. A game in exclusive fullscreen draws above every window.
  - Settings: when (in games or always), corner, detail (FPS only, Standard, Full).
- **Focus** (Ctrl+Alt+D; also in Control Center and the bell panel). No notification pop-ups (they still collect behind the bell), the dock tucks away until the pointer reaches its edge, and the video wallpaper pauses. A moon in the menu bar shows it is on; a click on it turns Focus off. It turns on by itself while a game runs and off when the game closes, then tells you how many notifications came in, if any did. It replaces the bell's "Do not disturb" switch (that setting is carried over).
- **Per-app volume** in Control Center, under the main volume: one row per app with sound open (apps playing now first, then idle ones, then System sounds; up to six rows), with its icon, a volume slider, a mute button and a level meter. Apps that play sound through a helper process (Baka Browser and other WebView2 apps) are shown under their own name.
- New Settings page **Focus & games**.
- Control Center: Focus and Game overlay are on/off switches at the top; the old Focus tile (which only opened Windows' Focus page) became an Arena tile.
- The shortcut cheat sheet lists Ctrl+Alt+D, Ctrl+Alt+F and Ctrl+Alt+G.
- New command lines: `--focus on|off|toggle`, `--overlay on|off|toggle`, `--overlay-test <result.json>`, `--fps-probe <seconds> <result.json>`.
- The self-test also checks Focus, the overlay and the per-app volume list.

## 12.26.4 (2026-10-30)

- With BAKA's window buttons on, a window covered its BAKA buttons as soon as it was clicked. It showed most on Baka Browser, whose buttons disappeared a few seconds after it opened. BAKA's buttons are now kept right above their window (every app, not only Baka Browser), and sit in the middle of the title bar of a maximized window.

## 12.26.0 to 12.26.3 (2026-10-30)

- **Keyboard shortcut cheat sheet**: hold the Windows key about 0.7 s. Win+/ keeps it open (Win+F1 too, but only when Explorer is off), Esc closes it. Holding Win no longer opens Start or Search when you let go.
- **BAKA reads Windows' notifications** from Windows' own notification list (read-only, through the SQLite library that ships with Windows). The bell (Win+N) lists them with a Clear button. With BAKA as the shell, new ones also pop up at the top right within about 2 seconds. Before this, BAKA could not read notifications at all (Windows only offers its notification listener to Store apps).
- About 24 fixes from a code review, among them: keys that stayed "held" after locking the PC, the taskbar check that found BAKA's own tray window instead of Explorer's, two keyboard listeners running at once (one kept listening during games), Ctrl+Alt+G to leave a game mode started by hand, fewer window-event wake-ups, and no window titles in BAKA's log (they can contain chats or file names).

## 12.25.0 to 12.25.3 (2026-10-30)

- **Windows Explorer in the background** (Settings > Windows, for BAKA as the shell), on by default: one hidden Explorer for the whole sign-in, so the Store, Windows Settings, apps that check for Explorer (Salad's WSL check, for example) and every Windows shortcut work and open quickly. Off runs no Explorer at all.
- Screenshots: Win+Shift+S and PrintScreen work with and without Explorer.
- The Windows taskbar no longer flashes into view when the helper Explorer starts.
- Fixes for maximized windows ending under the dock: BAKA's tray window passes Explorer's screen-edge messages on to it, and the edges are reserved again after Explorer restarts. On some Windows builds Explorer still refuses a left or right dock's reservation; BAKA then stops trying, and the menu bar stays reserved.

## 12.1 to 12.24 (2026-10-29 to 10-30)

These builds were installed and tested one by one on a real PC; the list is grouped by area because the exact build of each change was not recorded.

**BAKA as the Windows shell (optional, Settings > Windows).** BAKA can be the shell for your account instead of Explorer. It then does Explorer's other jobs itself:
- starts the apps set to run at sign-in, honouring Task Manager's on/off switches;
- its own system tray in the menu bar (Discord, Steam, NVIDIA and driver icons, with their clicks and menus);
- keeps the menu bar and dock edges free and keeps minimized windows out of sight;
- Win+I, Win+D, Win+M, Win+1 to 9, Win+N, Win+R, Win+A / Win+X, Alt+Tab and Win+Tab;
- the volume keys with an on-screen volume bar;
- a notice when a USB drive is plugged in;
- a Windows Settings panel when Explorer is off: the classic panels that work without it (Sound, Mouse, Date and Time, Region, System Properties and others), a display panel (resolution and refresh rate with a 12-second "keep?"), and BAKA's Wi-Fi panel.

**New**
- Win+Tab (with Explorer off): every open window as a card with a live preview; click, arrows + Enter, middle-click or x to close. Alt+Tab and Win+arrow snapping too.
- Snip: freeze the screen, drag an area; copied to the clipboard and saved to Pictures\Screenshots.
- Wi-Fi panel under the menu bar's network icon: networks in range, signal, connect with a password.
- Minimizing a window flies into its dock icon, restoring grows out of it.
- BAKA's own right-click menu on the empty desktop (while desktop icons are hidden).
- Backgrounds for the dock, menu bar and widgets: glass, a colour, a picture or a looping muted video (decoded on the GPU).
- What is playing (Spotify, a browser tab, Media Player): album art and title in the clock island, controls on hover, and in the media widget.
- On-screen messages (screenshot saved, Focus on, game mode on).
- Widgets overhaul: a starter set (clock, system monitor, media) placed clear of the dock, plus GPU, network, storage, quick toggles and search widgets.
- BAKA Files opens the Recycle Bin, Network, ZIP files, libraries and other shell places itself instead of handing them to File Explorer, and selects with a rubber band when you drag on empty space.
- The app list (Launchpad, search) follows apps being installed and removed while BAKA runs.
- The menu bar became three floating islands (menu, clock, status) and can hide until the pointer reaches the top. The keyboard language shows in it when more than one layout is installed.
- Starting apps never freezes BAKA any more (every launch runs off BAKA's UI thread; opening the Store used to freeze the whole desktop).

**Changed**
- Windows' own window buttons are the default again (BAKA's buttons were switched off once for existing installs). With BAKA's buttons on (Settings > Windows), BAKA switches off the buttons Windows draws and draws its own on the real title bar, in the Chips or Lights style. Apps that draw their own title bar keep their buttons unless "Cover other apps' own buttons" is on.
- Without BAKA as the shell, the menu bar's tray button still shows the Windows taskbar for 12 seconds, as in R15. Moving Windows' tray into a BAKA flyout was tried and dropped, because the tray did not always go back to the taskbar.
- Keyboard: raw-input listening while Explorer runs (the default); with Explorer off, a keyboard hook on its own time-critical thread. Either way nothing listens while a game runs.

**Fixed**
- Launchers and stores (for example the Riot Client) were taken for games and hid the dock and menu bar.
- The dock's open-app icons blinked in and out every 1.5 s.
- Magnified dock icons were cut off at the dock's edge.
- An auto-hidden dock only turned transparent and still took its space.
- Store apps were pinned to the dock as "ApplicationFrameHost".
- Maximized windows jumped when an app opened or closed (the screen reservation was re-sent on every dock refresh).
- BAKA's window buttons crashed BAKA when an installer window closed while they were being placed.
- Settings > Wallpaper decoded every 4K wallpaper again each time the page was drawn.

## Not changed since R15

Windows itself, the ISO build scripts, Config files, Baka Browser (1.6.2) and the system tuning are the same as in R15. An installed R15 PC only needs the new BakaDesktop.exe.
