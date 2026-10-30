# BAKA Desktop 12.27.1 (2026-10-30)

> **A newer version is out:** [BAKA Desktop 12.27.2](https://github.com/OldcarryG/Baka-windows/releases/tag/desktop-12.27.2) fixes the WebP wallpaper and "Show the date" issues listed below. Install the [latest release](https://github.com/OldcarryG/Baka-windows/releases/latest) instead of this one.

An update of BAKA Desktop for PCs installed from the **BAKA Windows R15** ISO. No new ISO: Windows, Baka Browser and the system tuning are unchanged, only `BakaDesktop.exe` is replaced. Your settings, wallpaper and pinned apps are kept.

> **No more new ISOs.** From now on BAKA Windows is updated through BAKA Desktop releases like this one. A new ISO is only made if Microsoft releases a Windows update that is worth building into the image. For a fresh install, use the [R15 ISO](https://github.com/OldcarryG/Baka-windows/releases/tag/r15-20261029) and then install the newest BAKA Desktop update.

## Install

1. Download **BakaDesktop-12.27.1.zip** below.
2. Right-click it > **Extract All**.
3. Open the extracted folder and double-click **Install-BakaDesktop.cmd**. Approve the administrator prompt. If Windows SmartScreen says "Windows protected your PC", click **More info** > **Run anyway**.
4. BAKA Desktop closes for a few seconds and starts again. BAKA Settings > About shows **BAKA Desktop 12.27.1**.
5. Optional, for the FPS counter: BAKA Settings > Focus & games > **Allow the FPS counter**, then sign out and back in.

The installer checks that the PC has BAKA Windows, checks `BakaDesktop.exe` against `SHA256.txt`, keeps the current version as `BakaDesktop.exe.previous`, and pre-compiles the new one (NGen). To go back: `Install-BakaDesktop.cmd rollback` from the same folder.

`BakaDesktop.exe` is not code-signed. Its SHA-256 is in `SHA256.txt` inside the zip and in `BakaDesktop-12.27.1-SHA256.txt` below.

## What is new since R15

The main additions are below. **Every new feature, change and bug fix since R15**, grouped by area, is in the README: [Changes since R15](https://github.com/OldcarryG/Baka-windows#changes-since-r15). Notes for each version: [docs/CHANGELOG_DESKTOP.md](https://github.com/OldcarryG/Baka-windows/blob/main/docs/CHANGELOG_DESKTOP.md).

- **Game overlay** (Ctrl+Alt+F): FPS, 1% low, CPU, GPU, GPU temperature, video memory and GPU power in a see-through strip. FPS comes from Windows' graphics event log, nothing is injected into games. FPS needs a one-time permission in Settings > Focus & games.
- **Focus** (Ctrl+Alt+D): no pop-ups, the dock tucks away, the video wallpaper pauses; on by itself during games.
- **Per-app volume** in Control Center.
- **Notifications**: BAKA reads Windows' notifications and lists them in the bell panel. With BAKA as the shell they also come as BAKA pop-ups, and Windows' duplicate banners are switched off (12.27.1).
- **Keyboard shortcut cheat sheet**: hold the Windows key.
- **BAKA as the Windows shell** (optional): its own tray, sign-in apps, Win+ shortcuts, Win+Tab with live previews, snip, Wi-Fi panel, volume bar. A hidden Explorer stays in the background by default, so the Store and Windows Settings work and open quickly.
- Minimize into the dock, video and picture backgrounds for the dock and menu bar, now-playing in the clock, more widgets, BAKA Files opens ZIP, Recycle Bin and Network itself.
- Many bug fixes, among them:
  - crashes when an installer window closed, and errors in the window buttons, keyboard listener or tray that could end BAKA;
  - keys stuck "held" after locking the PC;
  - launchers and stores taken for games;
  - dock icons blinking, duplicate dock icons and triple launches;
  - maximized windows jumping;
  - a black desktop when the wallpaper file was missing;
  - Shut down failing silently;
  - BAKA freezing while opening the Store;
  - Baka Browser's window buttons vanishing.

## Known issues

- A WebP picture chosen as the wallpaper is replaced with the BAKA BlackGlass picture; use JPG or PNG for now.
- Settings > Menu bar > "Show the date" has no effect; the date shows when the pointer is over the clock.
- Win+F1 opens the cheat sheet only when Explorer is off; Win+/ always works.

## Tested

On a real PC (Intel i5-14400F, RTX 5060, Windows 11 Pro 26H2 build 26300.9711):

- Each build since 12.1 was installed and used on this PC.
- Overlay: shown and hidden, click-through, NVIDIA temperature, power and video memory read.
- FPS counter: 60 FPS (1% low about 59) measured for a Direct3D 9 test window and a DXGI app on a 60 Hz screen, with Windows' event filters on (2,562 events in 8 s instead of 34,559 unfiltered).
- Focus: turned on and off, dock tucked away and back, on and off with game mode.
- Per-app volume: Baka Browser, Discord, BAKA's video wallpaper and System sounds listed with working sliders.
- Notifications: a test notification showed BAKA's pop-up and no Windows banner.
- The installer from this zip: extracted into a folder with a space in its name and run through the administrator prompt. It checked the SHA-256, kept the previous file, pre-compiled the new one and restarted BAKA Desktop.
- Source checks: project configuration (97 passed, 3 skipped for the ISO inputs), desktop configuration, dock contrast, game detection, gaming profiles, system tuning and release-pipeline guards all pass.

Not tested yet: FPS inside a real game, and Vulkan or OpenGL games (they use the kernel's present events). The BAKA Desktop self-test runs on GitHub Actions for this commit.
