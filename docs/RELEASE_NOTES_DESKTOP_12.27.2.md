# BAKA Desktop 12.27.2 (2026-10-30)

An update of BAKA Desktop for PCs installed from the **BAKA Windows R15** ISO. It fixes two bugs in 12.27.1 and contains everything from 12.27.0 and 12.27.1, so it installs straight over R15 or over 12.27.1. No new ISO: Windows, Baka Browser and the system tuning are unchanged; only `BakaDesktop.exe` is replaced. Your settings, wallpaper and pinned apps are kept.

> **No new ISO is coming.** R15 is the last BAKA Windows ISO for now. BAKA Windows is updated through BAKA Desktop releases like this one: a zip with the new BakaDesktop.exe and an installer. A new ISO is only made if Microsoft releases a Windows update that is worth building into the image. For a fresh install, use the [R15 ISO](https://github.com/OldcarryG/Baka-windows/releases/tag/r15-20261029), then install the newest BAKA Desktop zip.

## Install

1. Download **BakaDesktop-12.27.2.zip** below.
2. Right-click it > **Extract All**.
3. Open the extracted folder and double-click **Install-BakaDesktop.cmd**. Approve the administrator prompt. If Windows SmartScreen says "Windows protected your PC", click **More info** > **Run anyway** (the files are not code-signed).
4. BAKA Desktop closes for a few seconds and starts again. BAKA Settings > About shows **BAKA Desktop 12.27.2**.
5. Optional, for the FPS counter: BAKA Settings > Focus & games > **Allow the FPS counter**, then sign out and back in.

The installer only replaces `C:\ProgramData\BAKA\Desktop\BakaDesktop.exe`. It checks that the PC has BAKA Windows, checks `BakaDesktop.exe` against `SHA256.txt`, keeps the current version as `BakaDesktop.exe.previous`, and pre-compiles the new one (NGen). To go back: run `Install-BakaDesktop.cmd rollback` from the same folder. The installer writes a log to `C:\ProgramData\BAKA\Logs\Update-BakaDesktop.log`.

`BakaDesktop.exe` is not code-signed. Its SHA-256 is in `SHA256.txt` inside the zip and in `BakaDesktop-12.27.2-SHA256.txt` below.

## Fixed in 12.27.2

- **WebP wallpapers.** A WebP picture chosen in Settings > Wallpaper (or with `BakaDesktop.exe --wallpaper`) was replaced with the BAKA BlackGlass picture, and that replacement was saved over your choice. BAKA now converts the picture once to PNG with Windows' own WebP decoder and shows that. Your file stays the setting, and the converted copy is kept in `%LOCALAPPDATA%\BAKA\State\Wallpaper`. If you chose a WebP picture with 12.27.1, choose it again.
- **Settings > Menu bar > "Show the date"** did nothing after the menu bar redesign. Now, when it is on, the clock island shows the date next to the time (for example "Fri 30 Oct   20:15"). When it is off, only the time shows, and the full date appears when the pointer is over the clock. The update turns the switch off once, so the menu bar looks the same as before until you turn it on.
- The BAKA Desktop self-test now checks the date switch both ways.

## Everything since R15

The full list of new features, changes and bug fixes since the R15 ISO, grouped by area, is in the README: [Changes since R15](https://github.com/OldcarryG/Baka-windows#changes-since-r15). Notes for each version: [docs/CHANGELOG_DESKTOP.md](https://github.com/OldcarryG/Baka-windows/blob/main/docs/CHANGELOG_DESKTOP.md). The main additions:

- **Game overlay** (Ctrl+Alt+F): FPS, 1% low, CPU, GPU, GPU temperature, video memory and GPU power. FPS comes from Windows' graphics event log, nothing is injected into games.
- **Focus** (Ctrl+Alt+D): no pop-ups, the dock tucks away, the video wallpaper pauses; on by itself during games.
- **Per-app volume** in Control Center.
- **Notifications** in the bell panel; with BAKA as the shell also as BAKA pop-ups, without Windows' duplicate banners.
- **Keyboard shortcut cheat sheet**: hold the Windows key.
- **BAKA as the Windows shell** (optional): its own tray, sign-in apps, Win shortcuts, a window switcher with live previews, snip, Wi-Fi panel and volume bar.
- Menu bar islands, minimize into the dock, backgrounds for the dock, menu bar and widgets, new widgets, and BAKA Files opening ZIP, Recycle Bin and Network itself.
- Many bug fixes (70 in the README list), including crashes, keys stuck after locking the PC, launchers taken for games, dock icons blinking or doubled, maximized windows jumping, a black desktop when the wallpaper file was missing, Shut down failing silently, and BAKA freezing while opening the Store.

## Tested

On a real PC (Intel i5-14400F, RTX 5060, Windows 11 Pro 26H2 build 26300.9711):

- Installed over 12.27.1 from this zip with Install-BakaDesktop.cmd (extracted into a folder with a space in its name). It checked the SHA-256, kept 12.27.1 as `BakaDesktop.exe.previous`, pre-compiled the new one and restarted BAKA Desktop as 12.27.2. No errors in BAKA's log afterwards.
- WebP: a WebP picture set with `--wallpaper` was converted by "Microsoft Webp Decoder" in about 60 ms (a 550×368 picture) and became the desktop picture through its PNG. The setting kept the WebP file. The previous video wallpaper was then put back and played again.
- Date switch: the update set it to off once (settings revision 18), and the clock island read "20:15", the time only, as before.
- Source checks (project configuration, desktop configuration, dock contrast, game detection, gaming profiles, system tuning, release-pipeline guards) pass, and GitHub Actions runs the BAKA Desktop self-test, including the new date check, for this commit.

## Known issues

- Win+F1 opens the cheat sheet only when Explorer is off (otherwise it is Windows Help). Win+/ always works.
- With the background Explorer running, Explorer can refuse a left or right dock's screen reservation on some Windows builds, so maximized windows may reach under the dock. The menu bar stays reserved.
- Per-app volume lists the default output device only.
- Without BAKA as the shell, the menu bar's tray button shows the Windows taskbar for 12 seconds, as in R15.
- FPS has not been measured inside a real game yet.
