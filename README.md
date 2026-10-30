# BAKA Windows Gaming Edition

A custom Windows 11 Pro 26H2 (x64) image for gaming. It replaces the taskbar, Start menu and File Explorer windows with its own desktop, adds a game overlay with an FPS counter, plays 4K video wallpapers on the graphics card, removes apps most people never use, blocks ads and trackers for every app, turns off telemetry, and ships [Baka Browser](https://github.com/OldcarryG/Baka-browser) as the default browser. When a game starts, BAKA gets out of the way: its UI, keyboard listener and video wallpaper are switched off, so it adds almost nothing while you play.

Windows itself is not modified: it is Microsoft's own Windows 11 Pro 26H2 (build 26300) with Windows Security, Secure Boot, TPM, the Store, drivers and Windows Update all working. Everything BAKA changes can be undone.

[![Source validation](https://github.com/OldcarryG/Baka-windows/actions/workflows/source-validation.yml/badge.svg?branch=main)](https://github.com/OldcarryG/Baka-windows/actions/workflows/source-validation.yml)

**Download:** the full ISO (11.2 GB) is on MEGA, linked from the [R15 release](https://github.com/OldcarryG/Baka-windows/releases/tag/r15-20261029) together with its SHA-256. The newest BAKA Desktop update is in the [latest release](https://github.com/OldcarryG/Baka-windows/releases/latest).

> **No more new ISOs.** R15 is the last ISO for now. From here on BAKA Windows is updated through BAKA Desktop releases: download the zip, run the installer, done ([Update BAKA Desktop](#update-baka-desktop), [what changed since R15](#changes-since-r15)). A new ISO is only made if Microsoft releases a Windows update that is worth building into the image.

- [Screenshots](#screenshots)
- [Features](#features)
- [BAKA vs normal Windows 11](#baka-vs-normal-windows-11)
- [Benchmark](#benchmark)
- [Input latency](#input-latency)
- [4K video wallpaper](#4k-video-wallpaper)
- [System requirements](#system-requirements)
- [Install](#install)
- [Update BAKA Desktop](#update-baka-desktop)
- [First start](#first-start)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Undo BAKA](#undo-baka)
- [Known limits](#known-limits)
- [FAQ](#faq)
- [Releases](#releases)
- [Changes since R15](#changes-since-r15)
- [Command line](#command-line)
- [Build and source checks](#build-and-source-checks)

## Screenshots

![BAKA desktop on an installed system (Hyper-V VM)](docs/screenshots/installed-desktop.png)

| Launchpad (Windows key) | Search | BAKA Files |
|---|---|---|
| ![Launchpad](docs/screenshots/launchpad.png) | ![Search](docs/screenshots/search.png) | ![BAKA Files](docs/screenshots/files.png) |
| **Control Center** | **BAKA Settings** | **BAKA Arena** |
| ![Control Center](docs/screenshots/control-center.png) | ![BAKA Settings](docs/screenshots/settings.png) | ![BAKA Arena](docs/screenshots/arena.png) |

The screenshots are from R13 to R15; BAKA Desktop 12.27 has a redesigned menu bar (three islands) and dock. BAKA buttons on other apps (Notepad, Calculator, Media Player), captured in the installed VM in R13 (they are optional and off by default now):

![BAKA buttons on Notepad](docs/screenshots/baka-buttons-notepad.png)
![BAKA buttons on Calculator](docs/screenshots/baka-buttons-calculator.png)
![BAKA buttons on Media Player](docs/screenshots/baka-buttons-mediaplayer.png)

![125 BAKA icons in the Carbon Red theme](docs/screenshots/icons-carbon-red.png)

## Features

### Desktop
- **BAKA Desktop** is a compiled app (C#/WPF on .NET Framework 4.8, which ships with Windows). No PowerShell runs for the desktop. It restarts itself after a crash; after three crashes in two minutes it gives back the normal Windows taskbar, so you are never left without a desktop.
- **Menu bar** on top as three floating glass islands: BAKA menu, Apps, Files, Arena, Settings and the name of the app in front on the left; the clock (with what is playing, and the date on hover) in the middle; tray icons, network, volume, battery, notifications and Control Center on the right. Clicks between the islands go through to the desktop. It can hide until the pointer reaches the top.
- **BAKA as the Windows shell** (optional, Settings > Windows): Windows starts BAKA instead of Explorer. BAKA then starts the sign-in apps, hosts the tray icons, keeps the screen edges free and handles the Win shortcuts itself. A hidden Explorer stays in the background by default so the Store and the Settings app work.
- **Snip** (Win+Shift+S), a **Wi-Fi panel** under the network icon, minimizing into the dock, and with Explorer off a **Win+Tab / Alt+Tab switcher** with live previews.
- **Dock** on the left, bottom or right, with pinned and running apps. Menu bar and dock reserve their screen edge like the taskbar, so maximized windows never hide their buttons under them. Fullscreen games and video cover them as they would cover the taskbar.
- **BAKA buttons on app windows** (optional and off by default; Settings > Windows): BAKA's own minimize, maximize and close, as rounded Chips or coloured Lights, on Notepad and other apps whose buttons Windows draws. They follow the window when you drag it. Apps that draw their own title bar (Chrome, Discord, Store apps) keep theirs unless you turn on "Cover other apps' own buttons". Nothing is loaded into other apps, so anti-cheat is not affected. Apps running as administrator, dialogs and fullscreen windows keep Windows' buttons.
- **4K video wallpaper**: MP4, MOV, MKV, WebM, WMV and AVI with H.264, HEVC, VP9 or AV1, up to 4K (higher if your graphics card decodes it). Details [below](#4k-video-wallpaper).
- **Launchpad** (Windows key): every installed app in a grid, and one search box for apps, Windows settings pages and files. It tolerates typos ("setings", "discrod"), knows program names ("cmd", "regedit") and initials ("vsc" for Visual Studio Code). Ctrl+Esc still opens the Windows Start menu.
- **BAKA Files**: sidebar with places and drives (with free space), sortable list, search in the folder and subfolders, rubber-band selection, copy/cut/paste with the Windows clipboard, drag and drop, delete to the Recycle Bin, rename, new folder or text file, ZIP compress and extract, Open with, Properties, Open Terminal here. The Recycle Bin (restore, empty), Network, the inside of ZIP files and libraries open in BAKA Files too. Win+E and folders opened from any app open here.
- **Control Center**: Focus and Game overlay switches, Wi-Fi, Bluetooth, Arena, night light, tray icons, display, ad block, volume with **per-app volume** (one slider, mute button and level meter for each app with sound open), brightness (laptops), media controls, profile, power plan, theme and widgets.
- **Notifications**: BAKA reads Windows' own notification list and shows it in the bell panel (Win+N). With BAKA as the shell, each notification also pops up as a BAKA pop-up, and Windows' duplicate banners are switched off (put back when you leave BAKA).
- **Keyboard shortcut cheat sheet**: hold the Windows key for about 0.7 s (Win+/ keeps it open).
- **BAKA Settings** pages: Appearance (theme, accent, glass, motion, icons), Wallpaper (BAKA wallpapers, any picture, a looping video or a colour, plus the pause options), Dock, Menu bar, Widgets, Windows (BAKA buttons, Windows key, BAKA as the shell, Explorer in the background, Leave BAKA), Privacy & ads, Focus & games (Focus, game overlay, FPS counter permission, Windows banners), Power (power plan, Desktop/Gaming/Benchmark profile) and About.
- **BAKA Arena**: all installed Steam, Epic and Riot games in one grid, Desktop and Gaming profiles, live CPU, GPU, memory and network numbers.
- **Backgrounds** for the dock, the menu bar islands and each widget: the theme's glass, a colour, a picture or a looping muted video (Settings > Appearance > Backgrounds).
- **Widgets**: clock, calendar, system monitor (CPU, GPU, memory, disk, network), GPU, network, storage, quick toggles, search, notes, media controls, focus timer. No news feed and no ads.
- **125 hand-drawn app icons** (Steam, Discord, Spotify, Settings, Store, Terminal, Git, Python, NVIDIA, Riot, VALORANT, Roblox, browsers and more), each drawn in the style of the theme. Apps without a BAKA icon keep their own icon on a BAKA tile.
- **12 themes**: Carbon, Carbon Red, Liquid Glass, four Pop themes, Obsidian, Liquid, Violet, Minimal and Gaming, with accent colours and glass and motion levels.
- BAKA's own windows use the Mica backdrop, so they move as smoothly as Windows 11 apps.

### Gaming and latency
- **Automatic game detection.** A running game (Steam, Epic, GOG, EA, Ubisoft, Xbox, Riot, Battle.net, itch, or any fullscreen app) switches BAKA to **Competitive Gaming**:
  - menu bar, dock, widgets and BAKA window buttons are hidden;
  - the video wallpaper is closed and its decoder and video memory freed;
  - BAKA's **keyboard listener is removed**, so BAKA sees none of the game's key presses;
  - the window-event hooks for the BAKA buttons are removed;
  - transparency and animations are switched off, background apps paused, and BAKA's memory trimmed;
  - BAKA Desktop runs at below-normal priority;
  - Focus turns on (no pop-ups), and the game overlay shows if you turned it on.

  Everything comes back when the game closes. Arena's Gaming card does the same by hand.
- **Game overlay** (Ctrl+Alt+F): FPS, 1% low, frame time, CPU, GPU load, GPU temperature, video memory, GPU power and RAM in a small see-through strip that clicks pass through. FPS comes from Windows' own graphics event log (ETW, like Xbox Game Bar and PresentMon); nothing is injected into games. FPS needs a one-time permission in Settings > Focus & games (it adds your account to Windows' Performance Log Users group). Temperature, power and video memory need an NVIDIA GPU.
- **Focus** (Ctrl+Alt+D): no notification pop-ups, the dock tucks away and the video wallpaper pauses. It turns on by itself while a game runs.
- **BAKA Gaming power plan**: based on Ultimate Performance, no core parking, games kept on performance cores, no USB selective suspend. Laptops keep Balanced on battery.
- Game Mode on, hardware-accelerated GPU scheduling on, optimizations for windowed games, foreground priority, no network throttling for games.
- Raw mouse input (no acceleration), no Sticky Keys, Filter Keys or Toggle Keys pop-ups.
- Game DVR and Game Bar off. Xbox sign-in is kept for Game Pass and PC games.
- Free AV1, VP9, HEVC and HEIF codecs installed from the Microsoft Store at first sign-in.
- **[Tune it for your hardware with an AI coding tool](docs/OPTIMIZE_WITH_AI.md)**: a ready-made prompt for Claude Code, Codex, Gemini CLI, Cursor, Kiro or similar. The AI inventories your CPU, GPU, RAM, monitor and network, benchmarks first, shows a plan, applies only changes it measured to help, keeps security and anti-cheat requirements on, and writes an undo script.

### Privacy and ads
- **Ads and trackers blocked for every app**, not just the browser: encrypted AdGuard DNS (DNS over HTTPS) plus a BAKA block list in the Windows hosts file for ad, analytics and error-tracking hosts that DNS lists miss. One switch in Settings turns both off.
- **Telemetry off**: DiagTrack, dmwappushservice, Inventory and Compatibility Appraisal, Windows Health and Optimized Experiences, Windows AI Components Host and Distributed Link Tracking services; 16 telemetry tasks; app inventory and application telemetry policies; diagnostic data at the lowest level Windows Pro allows. Windows Pro still sends "required" diagnostic data; BAKA does not claim zero telemetry.
- **Off**: Copilot, Recall, advertising ID, tips and suggestions, Start menu web search, activity history, Spotlight, consumer app installs.

### Apps
- **Removed**: Internet Explorer, legacy Windows Media Player, Movies & TV, WordPad, Steps Recorder, Math Input Panel, Fax and Scan, PowerShell ISE, Clipchamp, Copilot, Xbox app, Game Bar, News, Weather, Office hub, Solitaire, Teams (personal), Bing Search, Outlook (new), To Do, Power Automate, Get Help, Feedback Hub, Dev Home, Phone Link, Cross Device, Quick Assist, Maps, People, Family; Microsoft Edge (the WebView2 runtime that apps need is kept). Removed apps can be installed again from the Store.
- **Kept**: Microsoft Store (WhatsApp, Spotify, To Do and others install and run), Media Player, Photos, Camera, Paint, Notepad, Calculator, Snipping Tool, Terminal, Clock, Sound Recorder, Windows Security, App Installer (winget), Xbox sign-in.
- **Added**: Baka Browser, BAKA Desktop, free AV1/VP9/HEVC/HEIF codecs.

### Baka Browser 1.6.2
Preinstalled and set as the default browser. Chromium engine (WebView2), uBlock Origin Lite added on first start, Chrome Web Store extensions with signature checks, tab menu, drag tabs to reorder or into a new window, mute button, private windows, new-tab dashboard with picture or video background, 4K VP9/AV1/H.264 video, quiet automatic updates. See the [Baka Browser README](https://github.com/OldcarryG/Baka-browser#readme).

## BAKA vs normal Windows 11

| | Normal Windows 11 Pro | BAKA Windows |
|---|---|---|
| Taskbar and Start | Taskbar, Start with recommendations and web results | Menu bar, dock, Launchpad with typo-tolerant search, no web results, no ads |
| Window buttons | Windows' buttons | Windows' buttons by default; optional BAKA buttons (Settings > Windows) |
| File manager | File Explorer | BAKA Files (Explorer still runs hidden for tray, notifications, file dialogs) |
| Wallpaper | Picture, slideshow, Spotlight | Picture, colour, or 4K video decoded on the GPU, paused when covered, closed in games |
| While gaming | Taskbar, widgets, background apps keep running | BAKA UI, keyboard listener and video wallpaper off; BAKA Desktop uses 0.01% CPU and 34 MB |
| Key press latency, median (VM) | 0.27 to 0.28 ms | 0.26 to 0.27 ms gaming, 0.29 to 0.33 ms desktop |
| Windows key → start surface | 30 to 46 ms (Start) | 16 to 19 ms (Launchpad) |
| Fast Startup | On | On (since R15) |
| Power plan | Balanced | BAKA Gaming (Ultimate Performance base) |
| Game DVR / Game Bar | On | Off |
| Mouse acceleration | On | Off (raw input) |
| Ads and trackers (d3ward list, 131 domains) | 2 blocked | **131 blocked** |
| Privacy checks (12) | 0 | **12** |
| Telemetry tasks / services running | 14 / 5 | 0 / 0 |
| Copilot, Recall, ads ID, tips, Spotlight, Start web search | On | Off |
| Microsoft Edge | Installed, default browser | Removed; Baka Browser is the default (WebView2 kept) |
| Installed app packages | 51 | 35 |
| Setup | Account, privacy and Microsoft-account screens | Straight to the desktop; disk choice stays interactive |
| Security (Defender, firewall, Secure Boot, TPM, VBS, updates) | On | On (nothing bypassed) |
| Undo | – | Restore BAKA System Tuning, Settings > Windows > Leave BAKA |

The full comparison, with every setting, is in [docs/BAKA_VS_WINDOWS.md](docs/BAKA_VS_WINDOWS.md).

## Benchmark

Final R14 ISO, measured 2026-10-29. Stock Windows 11 (the official Microsoft ISO, unchanged) and BAKA were installed into identical Hyper-V VMs (Generation 2, Secure Boot, virtual TPM 2.0, 4 vCPU, 6 GB, 64 GB disk). Each VM ran alone, was restarted, signed in, left idle for 10 minutes and measured with the same script. BAKA was measured in Desktop mode and again in Gaming mode (what a running game switches to).

| | Stock Windows 11 | BAKA Desktop mode | BAKA Gaming mode |
|---|---:|---:|---:|
| **Score** (100 = stock) | 100 | 99.4 | **101.7** |
| Score without idle CPU | 100 | 91.4 | 94.0 |
| Idle CPU, 60 s average | 5.5% | **2.6%** | 2.9% |
| Memory in use at idle | **2066 MB** | 2539 MB | 2579 MB |
| Memory committed | **1779 MB** | 2340 MB | 2324 MB |
| Processes / threads | 137 / 1562 | 136 / 1652 | 136 / **1511** |
| Running services | 97 | 90 | **89** |
| Ready scheduled tasks | 211 | **194** | **194** |
| BAKA Desktop's own CPU / memory | – | 0.1% / 57 MB | 0.01% / 34 MB |
| CPU (SHA-256, one core) | 1871 MB/s | 1871 MB/s | 1870 MB/s |
| Memory copy (256 MB) | 18,088 MB/s | 17,517 MB/s | 17,803 MB/s |
| Disk write (1 GB, write-through) | 1620 MB/s | 1509 MB/s | 1619 MB/s |
| Boot time (Windows boot event) | **22.0 s** | 27.8 s | |
| Disk used on C: | **22.0 GB** | 23.8 GB | 23.8 GB |
| Ads blocked (d3ward test, 131 hosts) | 2 | **131** | **131** |
| Privacy checks passed | 0 / 12 | **12 / 12** | **12 / 12** |

What this means:
- **Same speed as stock.** CPU is identical; memory copy and disk write are within 7%, the normal run-to-run range of this VM.
- **BAKA's own cost is small**: 0.1% CPU and 57 MB on the desktop, 0.01% and 34 MB while gaming.
- **Idle CPU** was lower on BAKA this round, mostly because Microsoft Defender was scanning on stock (2.9%). In R13 it was the other way round (BAKA 13.5%, stock 3.6%), so idle CPU is noisy. It also carries the score: without it the score is 91.4 (Desktop) and 94.0 (Gaming).
- **Memory** was about 0.5 GB higher on BAKA. The BAKA VM still had WhatsApp, Spotify and To Do installed and running from the Store test (WhatsApp alone 200 MB); stock had none of them.
- **Boot** was 5.8 s slower on BAKA this round; in R13 it was 2.8 s faster. Boot time varies by several seconds between runs.

The score is the geometric mean of BAKA-vs-stock ratios over boot time, memory in use, memory committed, processes, services, idle CPU, disk used, CPU, memory copy and disk write (Gaming mode without boot time). **Full method, every ratio, the top CPU and memory users of each system, earlier rounds and the scripts to run it yourself: [docs/BENCHMARK.md](docs/BENCHMARK.md).**

Game FPS cannot be measured in a VM without a GPU; use the [AI tuning prompt](docs/OPTIMIZE_WITH_AI.md) to benchmark and tune on your own PC.

## Input latency

Time from an injected key press until the window in front receives it, 200 presses per run, 3 runs, in the same VMs on the same day (R15):

| | Median |
|---|---:|
| Stock Windows 11 | 0.27 to 0.28 ms |
| BAKA Gaming mode | **0.26 to 0.27 ms** |
| BAKA Desktop mode, R15 | 0.29 to 0.33 ms |
| BAKA Desktop mode, R14 | 0.33 to 0.37 ms |
| BAKA Desktop mode, "Windows key opens Launchpad" off | 0.26 to 0.27 ms |

- **While gaming, BAKA is not in the input path at all**: the same as stock.
- **On the desktop BAKA adds 0.02 to 0.06 ms** per key, the cost of listening for the Windows key. Since R15 BAKA only listens (raw input) instead of hooking the keyboard, so Windows never waits for BAKA on a key press. Turning off "Windows key opens Launchpad" brings it to stock.

| Start surface | Stock Windows 11 | BAKA R15 |
|---|---:|---:|
| Windows key → Start / Launchpad in front | 30 to 46 ms | **16 to 19 ms** |
| Win+E → File Explorer / BAKA Files | 175 to 258 ms | **16 to 64 ms** |

**Boot** (restart, same VMs): the Windows boot event is the same as stock within the VM's spread (BAKA 27.0 to 28.8 s, stock 23.0 to 28.5 s). The BAKA desktop is ready 8.8 to 9.6 s after boot start (R14: 10.9 to 11.3 s); Explorer starts at about 7 s on both. R15 also keeps Windows' Fast Startup on, which R14 had turned off, so power-on after a shutdown is no longer a full cold boot. Details: [docs/BENCHMARK.md#r15-boot-shutdown-and-key-latency](docs/BENCHMARK.md#r15-boot-shutdown-and-key-latency).

**The earlier latency fix in R14** (before R15 removed the hook altogether). Windows holds every key press until each low-level keyboard hook answers. Until R13, BAKA's hook ran on BAKA's UI thread, so a key press had to wait whenever BAKA was busy drawing. On the development PC, with BAKA's main thread kept busy like a frame being drawn:

| Design | Median key latency |
|---|---:|
| No hook at all | 0.66 to 0.71 ms |
| R13: hook on the UI thread | **25 to 42 ms** (most presses held more than 50 ms) |
| R14: hook on its own time-critical thread | **0.75 ms** |

Mouse latency and the 1 ms timer could not be measured in Hyper-V. Details: [docs/BENCHMARK.md#input-latency](docs/BENCHMARK.md#input-latency).

## 4K video wallpaper

Settings > Wallpaper > choose a video, or `BakaDesktop.exe --wallpaper <file>`. Windows' own Media Foundation player decodes the video on the graphics card (DXVA) and draws it straight to the screen, without copying frames through the CPU.

| Format | Development PC (RTX 5060) | VM (no GPU, software decoding) |
|---|---|---|
| H.264 MP4 4K | plays and loops, **0.2% CPU** | plays and loops, 36% |
| HEVC MP4 4K | needs the HEVC extension (BAKA installs it) | plays, 50% |
| VP9 WebM 4K | plays, **2% CPU** | plays, 21% |
| AV1 WebM 4K | plays, **0% CPU** | too slow without a GPU |
| A maximized window covers the desktop | – | paused, CPU 37% → 0.05% |
| A game starts | – | closed, CPU 0%; plays again afterwards |

- It plays only while you can see it: it **pauses** when a maximized or fullscreen window covers the desktop, **on battery**, and while the PC is **locked**. Each can be switched off in Settings > Wallpaper.
- While a game runs the player is **closed** (decoder and video memory freed) and it continues afterwards.
- **Fill** crops the video to the screen without black bars; **Fit** shows it whole.
- A video Windows cannot decode falls back to the picture, and Settings > Wallpaper says why.
- AV1 needs a GPU that decodes it (NVIDIA RTX 30 or newer, AMD RX 6000 or newer, Intel Arc or 11th-gen Core graphics or newer). On older GPUs use H.264, HEVC or VP9 for 4K.

![4K video wallpaper on the installed VM](docs/screenshots/video-wallpaper.png)

## System requirements

The same as Windows 11 Pro; nothing is bypassed:
- 64-bit CPU supported by Windows 11, UEFI with **Secure Boot**, **TPM 2.0**
- 4 GB RAM minimum, 8 GB or more recommended for gaming
- 64 GB disk minimum
- A USB stick of 16 GB or more for installing
- Internet at first sign-in for Baka Browser, codecs and Store apps
- For 4K video wallpapers with almost no CPU use: a GPU with hardware video decoding

## Install

1. Download the ISO from the MEGA link in the [R15 release](https://github.com/OldcarryG/Baka-windows/releases/tag/r15-20261029).
2. Check it: `Get-FileHash .\BAKA-Windows-Gaming-Edition-26H2-x64-BakaDesktop-R15-20261029.iso` in PowerShell must print `D33C2E3900710A96347F47ABE905911E372B5D19C034AC49260B9217E1E18107`, the SHA-256 shown in the release.
3. Write it to a USB stick with [Rufus](https://rufus.ie) (partition scheme GPT, target UEFI), or mount it in a VM (Hyper-V Generation 2 with Secure Boot and a virtual TPM, or VMware with UEFI and a vTPM).
4. Boot from it. Setup asks which disk to install to; it never erases a disk on its own. **Back up your data first** if you install over an existing system.
5. After about 10 minutes you are on the BAKA desktop.
6. Install the newest BAKA Desktop update (next section).

To build the ISO yourself from Microsoft's official ISO, follow [docs/GITHUB_WORKFLOW.md](docs/GITHUB_WORKFLOW.md) and run the scripts in `Scripts/` (needs the Windows ADK Deployment Tools and the .NET SDK).

## Update BAKA Desktop

BAKA Desktop (the menu bar, dock, Launchpad, Files, Control Center, Settings and widgets) is updated on its own, without reinstalling Windows. Settings, wallpapers and pinned apps are kept.

1. Open the [latest release](https://github.com/OldcarryG/Baka-windows/releases/latest) and download **BakaDesktop-&lt;version&gt;.zip**.
2. Right-click the zip > **Extract All**.
3. In the extracted folder, double-click **Install-BakaDesktop.cmd** and approve the administrator prompt. If Windows SmartScreen says "Windows protected your PC", click **More info** > **Run anyway** (the files are not code-signed).
4. BAKA Desktop closes for a few seconds and starts again. BAKA Settings > About shows the new version.

The installer only replaces `C:\ProgramData\BAKA\Desktop\BakaDesktop.exe`. It checks that the PC has BAKA Windows, checks the new file against `SHA256.txt` from the zip, keeps the current one as `BakaDesktop.exe.previous` and pre-compiles the new one (NGen). To go back to the previous version, run `Install-BakaDesktop.cmd rollback` from the same folder. What changed in each version: [docs/CHANGELOG_DESKTOP.md](docs/CHANGELOG_DESKTOP.md).

## First start

- Setup skips the account, privacy and Microsoft-account screens. A local account named **BAKA** signs in by itself without a password. Set a password in Windows Settings > Accounts to get the sign-in screen back.
- In the first minutes, with internet, BAKA installs Baka Browser and the AV1, VP9, HEVC and HEIF codecs in the background.
- Windows Update is **paused** at first so it does not download for an hour on a fresh install. Resume it with the **Restore Windows Update** shortcut in the Start menu's BAKA folder.
- Install your GPU driver (NVIDIA, AMD or Intel) as on any Windows PC.
- Optional: run the [AI tuning prompt](docs/OPTIMIZE_WITH_AI.md) to tune for your hardware.

## Keyboard shortcuts

| Keys | Action |
|---|---|
| Windows key | Launchpad (apps and search) |
| Hold the Windows key (about 0.7 s) | Keyboard shortcut cheat sheet; Win+/ keeps it open |
| Win+S | Search |
| Win+E | BAKA Files |
| Win+N | Notifications (bell panel) |
| Ctrl+Alt+D | Focus on or off |
| Ctrl+Alt+F | Game overlay (FPS, CPU, GPU) on or off, also inside games |
| Ctrl+Alt+G | Leave a game mode you started by hand |
| Win+Shift+S | Snip: drag an area, or click for the whole screen (copied and saved to Pictures\Screenshots) |
| Ctrl+Esc | Windows Start menu |
| Win+D, Alt+Tab, Win+Tab, Win+L and other Windows shortcuts | Work as usual |

With BAKA as the shell and the background Explorer off, BAKA handles the shortcuts Explorer would: Win+Tab and Alt+Tab (BAKA's switcher with live previews), Win+Left/Right/Up/Down (snap, maximize, restore), Win+A and Win+X (Control Center), Win+I (BAKA's Windows settings panel), Win+D, Win+M, Win+1 to 9 (dock apps), Win+N, Win+R, Win+F1 (cheat sheet), PrintScreen (snip) and the volume keys (with an on-screen volume bar).

## Undo BAKA

- **BAKA Settings > Windows > Leave BAKA** gives back the Windows taskbar, Start menu and File Explorer.
- **Restore BAKA System Tuning** (Start menu, BAKA folder) undoes BAKA's service, scheduled-task, privacy, power plan and default-browser policy changes from the backup BAKA made at first sign-in. It asks for administrator approval.
- **Restore Windows Update** (same folder) turns Windows Update back on.
- The ad-block DNS and hosts list are turned off with one switch in BAKA Settings > Privacy & ads.
- `BakaDesktop.exe --restore-windows` does the same as Leave BAKA from a command line.
- Removed apps can be installed again from the Microsoft Store or Windows Settings > Optional features.

## Known limits

- **Microsoft Edge** is removed and its reinstall blocked by policy, but in one R12 install Windows put Edge back, so removal is not guaranteed on this Windows build.
- **Store apps that need Edge**, such as Netflix, do not install while Edge is removed (error 0x80073D31).
- **AV1 4K wallpapers** need hardware AV1 decoding (see above).
- **Game FPS, frame times, mouse latency and media keys** were not benchmarked; the test VMs have no GPU and no sound device. The game overlay's FPS counter was checked on a real PC at 60 FPS (a Direct3D 9 window and a DXGI app on a 60 Hz screen), but not yet inside a real game, and not with Vulkan or OpenGL games.
- **Game overlay** shows over borderless and windowed games; a game in exclusive fullscreen draws above it. GPU temperature, power and video memory are read only on NVIDIA GPUs.
- **BAKA Desktop 12.27.1** has a few known issues (WebP wallpapers, the "Show the date" switch, Win+F1): see [Known issues in 12.27.1](#known-issues-in-12271).
- **Windows Pro telemetry**: "required" diagnostic data is still sent; BAKA does not claim zero telemetry.
- **Apps running as administrator** and dialogs keep Windows' own window buttons.
- The ISO is not signed by Microsoft. Check its SHA-256 against the release.

## FAQ

**Does BAKA affect anti-cheat?** BAKA does not load anything into other processes. The BAKA buttons are separate windows that follow the app. With Explorer running in the background (the default) BAKA only listens to the keyboard with raw input; only when you turn Explorer off completely does it use a keyboard hook, on its own thread. Either way it stops listening while a game runs. The game overlay reads FPS from Windows' graphics event log instead of hooking into the game. Secure Boot, TPM, VBS and Defender stay on.

**Is it activated?** BAKA includes no licence key. Activate it with your own Windows 11 Pro licence, as with Microsoft's ISO.

**Can I update Windows?** Yes. Windows Update works normally once you resume it with Restore Windows Update.

**Can I install Chrome, Firefox or Edge?** Chrome, Firefox and other browsers install as usual. Edge is blocked by the Edge Update policy value `Install{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}` = 0 in `HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate`; delete that value (and `DoNotUpdateToEdgeWithChromium` in `HKLM\SOFTWARE\Microsoft\EdgeUpdate`) to install Edge again.

**Does the video wallpaper slow games down?** No. It is closed completely while a game runs, and paused whenever a maximized window covers the desktop.

**How do I get the normal Windows desktop back?** BAKA Settings > Windows > Leave BAKA.

## Releases

| Release | Main changes |
|---|---|
| **BAKA Desktop 12.27.1** (2026-10-30, no new ISO) | Update for R15 PCs: game overlay with FPS, Focus, per-app volume, BAKA notification pop-ups without Windows' duplicate banners, shortcut cheat sheet, optional BAKA-as-shell mode with its own tray and switcher, and many bug fixes. [Every change and fix](#changes-since-r15), [how to install](#update-baka-desktop) |
| **R15** (2026-10-29, last ISO) | Fast Startup back on; BAKA Desktop starts with Explorer (desktop ready about 1.7 s sooner); no false crash at every shutdown; Windows key only listened to, not hooked; Launchpad opens in under 20 ms; native image for BAKA Desktop |
| R14 (2026-10-29) | 4K video wallpaper decoded on the GPU; keyboard hook on its own time-critical thread (25–42 ms → 0.75 ms with BAKA busy) and removed in games; AI tuning prompt; ISO on MEGA |
| R13 (2026-10-29) | BAKA buttons on every app window, Mica backdrop for BAKA windows, more privacy checks, Store apps tested, Gaming-mode benchmark, Baka Browser 1.6.2 |
| R12 (2026-10-28) | Baka Browser 1.6.1 |

All releases: [github.com/OldcarryG/Baka-windows/releases](https://github.com/OldcarryG/Baka-windows/releases).

## Changes since R15

Everything here came after the R15 ISO, which shipped BAKA Desktop 12.0, and is in **BAKA Desktop 12.27.1** ([install it](#update-baka-desktop)). Windows itself, Baka Browser 1.6.2, the system tuning and the ISO build scripts are unchanged. The list comes from the code changes between R15 and 12.27.1 (48 files). Notes for each version: [docs/CHANGELOG_DESKTOP.md](docs/CHANGELOG_DESKTOP.md).

### New features

**Game overlay and FPS counter** (Ctrl+Alt+F, also inside games)
- A see-through strip in a corner of the screen: FPS, CPU, GPU load and GPU temperature. The Full view adds the 1% low, frame time, video memory, GPU power and RAM. Clicks go through it and it never takes the keyboard.
- FPS comes from Windows' graphics event log (DXGI, Direct3D 9, and the kernel's present events for Vulkan and OpenGL games), the way Xbox Game Bar and PresentMon measure it. Nothing is injected into games.
- FPS needs a one-time permission: Settings > Focus & games > **Allow the FPS counter** adds your account to Windows' Performance Log Users group, then sign out and in. **Remove the permission** undoes it. CPU, GPU and temperature work without it.
- GPU temperature, power and video memory come from the NVIDIA driver (nvml.dll). Other GPUs show the load only.
- It follows the game BAKA detected and sits in the chosen corner of that game's screen. Browsers and Electron apps are measured through the GPU process they draw in.
- It puts itself back above borderless games that are set to stay on top. A game in exclusive fullscreen still draws over it.
- Settings: on or off (off by default), when (in games or always), corner, and detail (FPS only, Standard or Full).

**Focus** (Ctrl+Alt+D, also inside games)
- No notification pop-ups (they still collect behind the bell), the dock tucks away and gives its screen edge back, and the video wallpaper pauses. A moon in the menu bar shows it is on; click it to turn Focus off.
- It turns on by itself while a game runs and off when the game closes, then tells you how many notifications came in, if any did.
- Each part can be switched off in Settings > Focus & games. It replaces the bell's "Do not disturb" switch, and that setting is carried over.
- Switch it from Control Center, the bell panel, Settings, `--focus`, or Ctrl+Alt+D.

**Notifications**
- BAKA reads Windows' own notification list (read-only, through the SQLite library that ships with Windows) and lists the notifications in the bell panel (Win+N).
- With BAKA as the shell, each new notification also pops up at the top right as a BAKA pop-up, within about 2 seconds. Pop-ups stack up to four, fade after 6 seconds and never take the keyboard; a click opens the app. With Explorer as the shell, Windows shows its own banners as before.
- Clear in the bell panel hides notifications in BAKA only, and stays cleared after a restart.
- Starting BAKA does not replay old notifications: only ones less than 2 minutes old pop up.
- Windows' own banner is switched off for each app while BAKA shows the pop-ups, so each notification comes once (12.27.1). Alarms, timers and calls keep Windows' banner. Leaving BAKA puts every app's setting back.

**Per-app volume** (Control Center)
- One row for each app with sound open: icon, volume slider, mute button and level meter. Apps playing now come first, then idle ones, then System sounds, up to six rows.
- An app with several sound streams (a browser) is one row. Baka Browser and other WebView2 apps show their own name, and BAKA's video wallpaper is listed as "BAKA video wallpaper".
- Changes made in Windows' volume mixer or in the app show up within 1.5 seconds.

**Keyboard shortcut cheat sheet**
- Hold the Windows key for about 0.7 seconds and every BAKA shortcut appears; let go and it goes away. Win+/ keeps it open; Esc or a click closes it.
- It never takes the keyboard and does not open during games. It can be switched off in Settings > Windows.

**BAKA as the Windows shell** (optional, Settings > Windows, off by default)
- Windows starts BAKA instead of Explorer at sign-in, and BAKA does Explorer's other jobs:
  - starts the sign-in apps from the same list as Task Manager's Startup apps, honouring its on/off switches, once per sign-in;
  - its own tray in the menu bar (Discord, Steam, NVIDIA and driver icons, with their clicks and menus), with a button that hides or shows the icons;
  - keeps the menu bar and dock edges free, and hides minimized windows instead of parking them at the bottom left;
  - the Win shortcuts listed under [Keyboard shortcuts](#keyboard-shortcuts), the volume keys with an on-screen volume bar, and a notice when a USB drive is plugged in;
  - the video wallpaper without Explorer (BAKA draws its own desktop behind every window);
  - a Windows settings panel when Explorer is off: the classic panels that work without it (Sound, Mouse, Date and time, Region, System, Device Manager, Services and others), a display panel (resolution and refresh rate, with a 12-second "keep?"), and BAKA's Wi-Fi panel.
- **Windows Explorer in the background** (on by default with the shell): one hidden Explorer for the whole sign-in, so the Microsoft Store, the Settings app and apps that check for Explorer (Salad's WSL check, for example) work and open quickly. It uses about 300 MB. Off runs no Explorer at all.
- If BAKA stops three times in two minutes, Explorer starts for that sign-in. The switch in Settings, or Task Manager > Run new task > explorer.exe, always brings Explorer back.

**Menu bar**
- Three floating glass islands instead of one bar: menu on the left, clock in the middle, status on the right. Clicks in the gaps go through to the desktop and apps.
- The clock island shows what is playing (album art, title and artist, from Spotify, a browser tab, Media Player and others), with play controls and the full date when the pointer is over it.
- It can hide until the pointer reaches the top: Settings > Menu bar (off by default).
- Wi-Fi panel under the network icon: networks in range with signal, connect with a password, Wi-Fi on/off, disconnect, the wired connection's speed and address, and an explanation when Windows needs Location on to list networks.
- A keyboard-language badge when more than one keyboard layout is installed.

**Dock**
- Minimizing a window flies into its dock icon, and restoring grows out of it.
- With too many open apps the whole dock shrinks to fit instead of running off the screen.
- New look: one row of flat icons with a hover highlight, thin separators and rounded ends. Newly opened apps fade in.
- The BAKA Files icon shows when a Files window is open, and a click brings it back or minimizes it.
- "Keep in dock" also works for Store apps.

**Windows and switching**
- BAKA's window switcher, with Explorer off (BAKA as the shell, background Explorer off): Win+Tab shows every open window as a card with a live preview. Use the arrows or Tab and Enter, or Delete or a middle-click to close a window; Win+Tab then Enter flips back to the previous window. Alt+Tab and Alt+Shift+Tab use the same switcher.
- Also with Explorer off: Win+Left/Right snap a window to half the screen, Win+Up maximizes and Win+Down restores or minimizes. With Explorer running, Windows handles these keys as usual.
- BAKA window buttons (off by default) come in two styles, Chips and Lights. On windows whose buttons Windows draws, BAKA switches those off and draws its own on the real title bar. Apps that draw their own title bar keep their buttons unless "Cover other apps' own buttons" is on. If BAKA closes or crashes, apps get their own buttons back.

**Desktop, wallpaper and backgrounds**
- BAKA's own right-click menu on the empty desktop (while desktop icons are hidden): wallpaper, widgets, appearance, BAKA Files, the Desktop folder, Terminal, display settings and BAKA Settings.
- Backgrounds for the dock, the menu bar islands and the widgets, and for each widget on its own: the theme's glass, a colour, a picture or a looping muted video, with a slider for how dark the veil over it is. Videos are decoded on the graphics card at 640×360 and up to 20 frames a second, share one player per file, and stop during games.
- Snip: Win+Shift+S (and PrintScreen when Explorer is off) freezes the screen. Drag an area or click for the whole screen; the picture is copied and saved to Pictures\Screenshots.
- Short on-screen messages: screenshot saved, Focus on or off, game mode on or off, game overlay on or off.

**Widgets**
- New widgets: GPU, Network, Storage, Quick toggles (mute, game mode, volume, Control Center, Settings) and Search.
- The System widget is four bars (CPU, GPU, RAM, network). The Media widget shows the album art, title, artist and the app playing.
- Widgets are sized to what they show (Notes stays resizable). Right-click a widget's title to hide it.

**BAKA Files**
- The Recycle Bin (restore, delete for good, restore all, empty), Network, the inside of ZIP files (open a file, extract selected items), libraries and `shell:` places open in BAKA Files instead of File Explorer.
- Rubber-band selection: drag on empty space to select the rows the box touches.
- A shortcut to a folder opens that folder in the same window.

**Control Center, Settings, Launchpad and Arena**
- Control Center: Focus and Game overlay switches at the top, an Arena tile, and the Wi-Fi tile opens BAKA's Wi-Fi panel.
- Settings: new **Focus & games** page, a **Backgrounds** section in Appearance, and the glass slider goes much more see-through (0 to 90 instead of 0 to 45).
- The Launchpad and search follow apps being installed and removed while BAKA runs.
- Arena lists Riot games (VALORANT, League of Legends) and starts them through the Riot Client.

**Command line**
- `--focus on|off|toggle`, `--overlay on|off|toggle`, `--overlay-test <result.json>`, `--fps-probe <seconds> <result.json>`, `--shellcheck <result.json>`, and `--fps-access on|off --user <SID>` (used by Settings). `--restore-windows` also brings back Windows' notification banners.

### Changed

- **Keyboard:** while Explorer runs, BAKA only listens with raw input. A keyboard hook, on its own time-critical thread, is used only when Explorer is off. Nothing listens while a game runs. Turning off "Windows key opens Launchpad" now only changes what a tap of Win does.
- **Window events:** the dock and menu bar follow windows as Windows reports them (within about 0.1 s) instead of checking every 1.5 s. While a game runs BAKA receives no window events at all.
- **Game start** also closes Control Center and the cheat sheet, pauses the notification check and background videos, and turns on Focus. The prepared Launchpad is kept, so the desktop is not slow right after a game.
- **Animations** are off in the Gaming and Benchmark profiles, also when you choose them by hand.
- **Restart, Shut down and Sign out** use the Windows API and force-close only apps that are not responding, so the others can still save. shutdown.exe is the fallback.
- **BAKA window buttons** are off by default, and were switched off once for existing installs. Windows' own buttons are back on every app.
- **Widgets** were switched on once with a starter set (Clock, System, Media) placed clear of the dock.
- **Menu bar:** its reserved strip is 50 px instead of 30 px. The clock shows the time; the date appears on hover.
- **Glass:** the dock, menu bar and widgets no longer use Windows' blur behind them, because it drew square corners on Windows 11. The glass is now a plain see-through tint.
- **Widgets content:** the Media widget lost its volume buttons (use Control Center). The System widget no longer shows battery, disk space or upload speed; the battery is in the menu bar, disk space in Storage and upload in Network.
- **Store apps** start by their app id, which also works with Explorer off.
- **Background Explorer** is simply on or off. An earlier "on demand" mode was removed because starting Explorer each time made the Store and Settings slow.

### Bug fixes

**Crashes and stability**
- BAKA crashed when an installer window closed while BAKA was placing its buttons on it.
- An error in the BAKA window buttons, a window event, the keyboard listener, the tray or a background task could end BAKA or show an error box. These errors are now caught and logged.
- Restarting the keyboard hook or BAKA's tray could crash BAKA on the next key or tray message.
- Minimizing into the dock checks the memory Windows passes before writing to it, so a bad pointer cannot end BAKA.
- Picking a Control Center quick action or a calendar link while the panel was closing raised an error.
- A crash in the Gaming profile left transparency, animations and background apps off for the rest of the session.
- After a crash, tray icons now go back to Explorer's tray, apps get their own window buttons back and the frame counter stops. After three crashes, Windows' notification banners come back too.
- Sign-in apps started again each time BAKA restarted after a crash; now they start once per sign-in.

**Keyboard**
- Keys held when you locked the PC (Win+L), pressed Ctrl+Alt+Del or got an administrator prompt stayed "held": after unlocking, typing E, S or Q opened Files or search, and every Tab opened the switcher.
- Two keyboard listeners could run at once. One kept listening during games, and a single Win press opened and closed the Launchpad.
- Turning off "Windows key opens Launchpad" also turned off Alt+Tab, Win+Tab, Win+arrows, the snip and the cheat sheet.
- Letting go of a held Win key opened Start, Search or the Launchpad.
- Holding Win+E opened one Files window per key repeat, and Win+Tab and Win+/ flickered.
- After Alt+Tab with BAKA's switcher, the app you switched to opened its menu bar or Office's key tips.
- Win+I, Win+D, Win+A, Win+Shift+S and Win+N could stop working for the whole sign-in when the background Explorer started.

**Dock**
- Open-app icons blinked in and out every 1.5 seconds.
- Magnified icons were cut off at the dock's edge.
- Auto-hide only made the dock transparent; it still took its space. Now it slides off the edge and gives the space back.
- Store apps were pinned as "ApplicationFrameHost".
- A pinned app got a second "open" icon next to its pin when it started (Steam, Discord, Kiro, WhatsApp, Windows Settings and others).
- Clicking an icon several times before the app's window appeared opened several copies.
- A window closed from the dock menu stayed in the dock for up to 4 seconds.
- A left or right dock overlapped the menu bar's strip in the corner, and after Explorer restarted the screen edges were not reserved again, so maximized windows slid under the dock.
- The launch bounce broke the icon magnification.

**Menu bar, power and windows**
- Maximized windows jumped whenever an app opened or closed.
- Shut down from the BAKA menu failed silently on PCs that do not support Windows' `/hybrid` shutdown.
- The "Restart now?", "Shut down now?" and "Sign out now?" questions could open behind the app in front, so the button looked dead.
- The menu bar could stay behind a maximized or just-focused app when it slid back into view.
- In shell mode the tray button opened the Launchpad search instead of the tray icons.
- Leaving BAKA did not bring back the Windows taskbar: BAKA found its own tray window, which has the same name, instead of Explorer's.
- The Windows taskbar flashed into view when the background Explorer started.
- BAKA window buttons: doubled or misplaced buttons on windows with a help button or only a close button; buttons covered by their window as soon as it was clicked (Baka Browser's vanished a few seconds after it opened); buttons partly under the menu bar on maximized windows; a frozen app could stall the desktop through its buttons; the cover colour could come from one stray pixel.
- Snapping with Win+arrows at 150% scaling gave the window 2/3 of the right size, and moved a window on a second monitor to the first.

**Desktop and wallpaper**
- The desktop turned black when the wallpaper file was missing or a leftover video path. When a video wallpaper fails, a real picture is shown now.
- If the display driver resets twice within 45 seconds while a video wallpaper plays (a reset can go with a freeze), BAKA stops the video and shows a picture. Settings > Wallpaper says why.
- With BAKA as the shell and a video wallpaper, clicking a widget dropped it behind the wallpaper.
- With BAKA as the shell, minimized windows sat as a black bar at the bottom left.
- A screenshot was lost when another app held the clipboard, and copying it could freeze BAKA. The file is saved first now.

**BAKA Files**
- Pressing Win+E or a folder link several times opened a pile of identical windows.
- Copy, move, paste and delete sometimes failed without a message.
- Cut, Copy, Paste and Copy path failed when another app (a clipboard manager, Remote Desktop) held the clipboard.
- Opening a file could freeze BAKA for seconds.
- Items without a date showed the year 0001.

**Widgets, Settings, Control Center and Launchpad**
- CPU and network numbers were wrong with more than one system widget open.
- Changing a setting far down a Settings page jumped back to the top.
- Picking a wallpaper froze Settings for most of a second (every thumbnail was decoded again).
- Opening Settings while it was minimized did not bring it back.
- Dragging a slider rebuilt the desktop and saved the settings for every step.
- With the Launchpad open, Win+S closed it instead of going to its search box.
- An app whose icon could not be read yet (still installing) kept a placeholder for the whole session.
- Apps that Windows lists by app id (Discord, Kiro, NVIDIA App) appeared twice in the dock.
- Opening the Microsoft Store froze the whole desktop. No app, Store app or Windows Settings page can freeze BAKA any more.

**Game detection**
- Launchers and stores were taken for games and hid the dock and menu bar: Riot Client, Steam, Epic Games Launcher, GOG Galaxy, EA app, Ubisoft Connect, Battle.net, the Xbox app, Playnite, itch, Amazon Games and HoYoPlay.
- Everyday apps such as WhatsApp, Spotify, Telegram, Slack, Zoom, Notepad, Photos, Paint and Calculator could count as games when fullscreen.
- A maximized window with a title bar was taken for a fullscreen game.
- VALORANT did not get Gaming mode on a real PC (it had been excluded for the virtual machine tests).

**Shell mode and tray**
- Tray icons vanished or showed another app's picture.
- Apps were asked to send their tray icons again every few seconds, and each time every app rebuilt its icon.
- Turning "Windows Explorer in the background" off did nothing after BAKA had restarted, and it could close a File Explorer window with a copy in progress. Now it closes only the hidden Explorer.
- After the background Explorer crashed five times, nothing could start it again until sign-out. The limit is now 5 starts in 10 minutes, with a message.
- Choosing BAKA as the shell was undone at the next start.

**Security and privacy**
- BAKA's log names a window's program and kind, never its title. For media it records which app plays, never what; for notifications only the app's name.
- Messages from other apps to BAKA's desktop and tray are size-checked, so a malformed message cannot make BAKA read past it.
- nvml.dll is loaded only from Windows' system folder or NVIDIA's own folder.

**Found and fixed while testing the 12.x builds** (in features that are new since R15)
- Notification pop-ups came up to 20 seconds late, did not show at all while the background Explorer ran, and every notification came twice (Windows' banner and BAKA's) until 12.27.1.
- The cheat sheet showed on only 5 of 10 holds, and could stay on screen after Win+L.
- Cleared notifications could come back, the open bell panel jumped to the top or went empty for a moment, and clicking the bell to close the panel opened it again.
- The per-app volume list failed with a cast error, and its rows stopped working after a refresh.

### Performance

- The dock's and menu bar's auto-hide checks stop when auto-hide is off. They ran 8 and 7 times a second, part of the idle CPU the benchmark showed.
- Clicks, scrolling and menus in other apps no longer make BAKA read every window again.
- BAKA pages its memory out only when Windows' memory use is 80% or more. Doing it every time made the dock, Launchpad and menus stutter afterwards.
- Notifications are checked with one small query every 2 seconds (0.8 ms), paused during games.
- The power plan list is cached for 20 seconds, the brightness check runs once on desktop PCs, the sound device is looked up every 5 seconds instead of for every slider step, and each window's program is read once.
- The overlay reads its numbers once a second off the UI thread. The frame counter runs only while the overlay is shown, and Windows filters its events down to about one per frame.

### Known issues in 12.27.1

- A WebP picture chosen as the wallpaper is replaced with the BAKA BlackGlass picture. Use JPG or PNG for now.
- Settings > Menu bar > "Show the date" has no effect since the menu bar redesign; the date shows when the pointer is over the clock.
- Win+F1 opens the cheat sheet only when Explorer is off (otherwise it is Windows Help). Win+/ always works.
- With the background Explorer running, Explorer can refuse a left or right dock's screen reservation on some Windows builds. BAKA then stops trying, so maximized windows may reach under the dock; the menu bar stays reserved.
- Per-app volume lists the default output device only.
- Without BAKA as the shell, the menu bar's tray button shows the Windows taskbar for 12 seconds, as in R15.

## Command line

`BakaDesktop.exe` (in `C:\ProgramData\BAKA\Desktop`):

| | |
|---|---|
| `--wallpaper <picture or video>` | set the desktop background |
| `--profile gaming` / `--profile desktop` | switch the profile (what Arena does) |
| `--video-test <file> <result.json> [s]` | check that this PC plays a video with the wallpaper player (writes CPU use, size, pause/resume) |
| `--status <file>` | what the desktop looks like, as JSON |
| `--tray` | show the Windows tray icons for a few seconds |
| `--preview`, `--selftest` | run the desktop in a throwaway profile / click through every surface and check it |
| `--focus on\|off\|toggle` | Focus on the running desktop (what Ctrl+Alt+D does) |
| `--overlay on\|off\|toggle` | the game overlay on the running desktop (what Ctrl+Alt+F does) |
| `--overlay-test <result.json>` | check the overlay, the NVIDIA sensors and the per-app volume list on this PC |
| `--fps-probe <seconds> <result.json>` | what Windows' graphics event log reports for each running app (run as administrator) |
| `--restore-windows` | put the normal Windows desktop back |

## Build and source checks

```powershell
./Tests/Test-ProjectConfiguration.ps1 -SkipExternalArtifactChecks
./Tests/Test-DesktopConfiguration.ps1
./Tests/Test-SystemTuning.ps1
./Tests/Test-GamingProfiles.ps1
./Tests/Test-GameDetection.ps1
./Tests/Test-ReleasePipelineGuards.ps1
./Tests/Test-DockContrast.ps1
./Tests/Test-BakaDesktop.ps1
```

Benchmark scripts: [`Tests/Benchmark/`](Tests/Benchmark) (see [docs/BENCHMARK.md](docs/BENCHMARK.md#run-it-yourself)).

Project layout:

- `Shell/BakaDesktop/` the desktop (C#): menu bar, dock, Launchpad, Files, Settings, Control Center, Arena, widgets, icons, BAKA window buttons, video wallpaper player, Explorer integration, ad blocking
- `Scripts/` build pipeline and first sign-in setup
- `Modules/` power plan, system tuning, update control, gaming profile rules
- `Config/` answer file, debloat, privacy, block list, performance profiles, themes, applications (pinned Baka Browser installer)
- `Tests/` the checks above and the benchmark scripts
- `Tools/` the BAKA Desktop updater that goes into each release zip (`Install-BakaDesktop.cmd`, `Update-BakaDesktop.ps1`) and the wallpaper generator
- `docs/` comparison with stock Windows, benchmark, release notes, AI tuning prompt, checklist, decisions, screenshots
