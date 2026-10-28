# BAKA Windows vs normal Windows 11

Both are Windows 11 Pro 26H2 (build 26300) from Microsoft's own installation media. BAKA keeps Windows itself intact (Windows Update can be turned back on, Windows Security, Store, drivers and every app work as usual) and changes what is around it. Everything BAKA changes can be undone with **Restore BAKA System Tuning** or **BAKA Settings > Windows > Leave BAKA**.

## Desktop

| | Normal Windows 11 | BAKA |
|---|---|---|
| Taskbar | Windows taskbar at the bottom | **BAKA menu bar** at the top (BAKA menu, Apps, Files, Arena, Settings, the app in front, tray, network, volume, battery, clock, notifications, Control Center) and the **BAKA dock** on the left (or bottom/right). The Windows taskbar is hidden and comes back by itself if BAKA ever stops. |
| Start menu | Start with recommendations and web search | **Launchpad** (Windows key): every installed app, and one search for apps, Windows settings pages and files. Typo-tolerant ("setings", "discrod"), matches program names ("cmd", "regedit") and initials ("vsc"). Ctrl+Esc still opens Start. |
| Maximized windows | Stop at the taskbar | Stop below the menu bar and next to the dock, so close/minimize/maximize buttons are never covered. Fullscreen video and games cover the bars, as they cover the taskbar. |
| File manager | File Explorer | **BAKA Files**: sidebar with places and drives (with free space), sortable list, search in folder and subfolders, copy/cut/paste with the Windows clipboard, drag and drop, delete to Recycle Bin, rename, new folder/text file, ZIP compress/extract, open with, properties, open Terminal here. Win+E and folders opened from any app open here. File Explorer still runs in the background because Windows needs it for tray icons, notifications and file dialogs. |
| Desktop icons | Shown | Hidden (the Desktop folder is in BAKA Files). |
| App icons | As shipped | **125 hand-drawn BAKA icons** (Steam, Discord, Spotify, Settings, Store, Terminal, Git, Python, NVIDIA, Riot, VALORANT, Roblox, browsers…), each drawn in the theme's style: metal squircles (Carbon), neon hexagons (Carbon Red, Gaming), glass bubbles, candy keycaps (Pop themes) and more. Apps without a BAKA icon keep their own icon on a BAKA tile. "Original" shows icons as the apps ship them. |
| Quick settings | Quick settings flyout | **Control Center**: Wi-Fi, Bluetooth, focus, night light, tray, display, volume, brightness (laptops), media keys, profile, power plan, theme and widgets. |
| Widgets | News and weather feed | Desktop widgets: clock, calendar, system monitor (CPU, GPU, memory, disk, network), notes, media controls, focus timer. No news feed, no ads. |
| Themes | Light / dark | 12 BAKA themes (Carbon, Carbon Red, Liquid Glass, four Pop themes, Obsidian, Liquid, Violet, Minimal, Gaming), accent colours, glass level, motion level. |
| Desktop technology | Explorer | BAKA Desktop, a compiled app (C#/WPF on .NET Framework 4.8, which is part of Windows). No PowerShell runs for the desktop. It restarts itself after a crash and gives back the normal Windows desktop after three crashes in two minutes. |

## Gaming

| | Normal Windows 11 | BAKA |
|---|---|---|
| Power plan | Balanced | **BAKA Gaming** plan on Ultimate Performance (no core parking, games kept on performance cores, no USB suspend). Laptops keep Balanced on battery. |
| Game detection | Game Mode only | Any game (Steam, Epic, GOG, EA, Ubisoft, Xbox, Riot, Battle.net, itch or any fullscreen app) switches BAKA to **Competitive Gaming**: menu bar, dock, widgets and video wallpaper go away, transparency and animations off, background apps paused, Game DVR off, desktop at below-normal priority. Everything comes back when the game closes. |
| Game library | Xbox app | **BAKA Arena**: all installed Steam and Epic games in one grid, profiles and live performance numbers. |
| Background recording | Game Bar / DVR on | Off. Xbox app and Game Bar removed; Xbox sign-in kept for Game Pass and PC games. |
| Input | Mouse acceleration on, Sticky Keys prompt | Raw mouse input, no Sticky/Filter/Toggle Keys pop-ups. |
| Other tuning | Default | Hardware GPU scheduling, optimizations for windowed games, foreground priority, no network throttling for games, full-quality wallpapers. |

## Privacy and ads

| | Normal Windows 11 | BAKA |
|---|---|---|
| Ads in every app | No blocking | Encrypted **AdGuard DNS** for every app, plus a BAKA block list in the Windows hosts file for ad, analytics and error-tracking hosts that DNS lists miss. |
| Browser | Microsoft Edge | **Baka Browser** (default), with uBlock Origin Lite, strict tracking prevention and no SmartScreen URL reporting. BAKA tries to uninstall Edge and blocks its reinstall by policy, but on this Windows build Windows put Edge back in one of two VM tests (see "Apps" below). The WebView2 runtime that apps need is kept. |
| Telemetry | Full diagnostic upload service | DiagTrack and push-routing services off, telemetry scheduled tasks off, diagnostic data at the lowest level Windows Pro allows. Windows Pro still keeps "required" diagnostic data; BAKA does not claim zero telemetry. |
| Copilot, Recall, ads ID, tips, Start web search, Spotlight | On | Off |

## Apps

| | Normal Windows 11 | BAKA |
|---|---|---|
| Removed | — | Internet Explorer, the legacy Windows Media Player, Movies & TV, Clipchamp, WordPad, Steps Recorder, Math Input Panel, Fax and Scan, PowerShell ISE, Xbox app, Game Bar, News, Weather, Office hub, Solitaire, Teams (personal), Bing Search, Outlook (new), To Do, Power Automate, Get Help, Feedback Hub, Dev Home, Phone Link, Cross Device, Quick Assist, Copilot, Maps, People, Family |
| Kept | — | Microsoft Store, **Media Player** (plays music and video), Photos, Camera, Paint, Notepad, Calculator, Snipping Tool, Terminal, Clock, Sound Recorder, Windows Security, App Installer (winget), WebView2, Xbox sign-in, media codecs. Removed items can be added back from the Store or Settings > Optional features. |
| Added | — | Baka Browser, BAKA Desktop (menu bar, dock, Launchpad, Files, Settings, Control Center, Arena, widgets), free AV1/VP9/HEVC/HEIF codecs from the Store |

## Setup

| | Normal Windows 11 | BAKA |
|---|---|---|
| Out-of-box setup | Account, privacy and Microsoft-account screens | Skipped; a local BAKA account signs in by itself (set a password in Windows to get the sign-in screen back). Disk choice stays interactive. |
| Windows Update | On | Paused at first (restore shortcut turns it back on). |
| Hardware requirements | TPM 2.0, Secure Boot | Same: nothing is bypassed. |

## Baka Browser compared with Edge, and what changed in it

Baka Browser uses the same engine as Edge (Chromium through the WebView2 runtime, which BAKA keeps).

| Version | Changes |
|---|---|
| 1.6.1 (in R12) | Fixed: Settings > Appearance > "Choose image or video…" (new-tab background) failed on a new profile with "Could not find a part of the path …\baka-browser\home-assets\…"; the folder is now created first. |
| 1.6.0 | Tab right-click menu (new tab, reload, duplicate, mute site, copy address, move to new window, close, close others, close tabs below/right, reopen closed tab). Drag tabs to reorder, or drag one off the strip into its own window. Speaker icon on tabs that play sound, click to mute. Ctrl+Shift+T reopens closed tabs (last 25), Ctrl+1 to Ctrl+8 select a tab, Ctrl+9 the last. Fixed: closing a background tab changed the selected tab; Ctrl+W inside a page; zoom changes now apply to open tabs. A second window no longer overwrites the main window's session, settings or history. |
| 1.5.0 (in R11) | uBlock Origin Lite added from the Chrome Web Store on first start (removal is respected). Background tabs use less memory. Upload (photo, 40 MB video) and 4K decoding self-tests. |
| 1.4.0 (in R10) | Chrome Web Store: an "Add to Baka" button downloads the extension from Google, checks its CRX3 signature against the extension ID, shows its permissions and installs it. Extensions menu, popups and options pages. New main menu, zoom, print, home button. Redesigned settings with a section rail. Flat graphite BAKA theme. |
| 1.3.0 (not published, shipped in 1.4.0) | BAKA theme in the BAKA Windows colours, soft-white default accent. |

## Measured in virtual machines

Both systems were installed from their ISOs into identical Hyper-V VMs (Generation 2, Secure Boot, virtual TPM 2.0, 4 vCPU, 6 GB fixed memory, 64 GB disk) on the same host and measured one at a time: fresh boot, signed in, 3 minutes idle, then the same script (`Guest-Bench`) over PowerShell Direct. Stock is the official Windows 11 Pro 26H2 ISO with no changes. Two rounds were run on 2026-10-28, each with a fresh BAKA install: round 1 with the first R12 build, round 2 with the final R12 build (adds the dock fix and Baka Browser 1.6.1).

| Measurement | Stock (round 2) | BAKA final (round 2) | BAKA (round 1) | Stock (round 1) |
|---|---:|---:|---:|---:|
| Boot time (Windows boot event, s) | 21.9 | 24.9 | 21.0 | 20.9 |
| Main boot path (s) | 5.9 | 7.0 | 6.6 | 5.5 |
| Memory in use at idle (MB) | 2005 | 2451 | 2212 | 2004 |
| Memory committed (MB) | 1703 | 2143 | 1879 | 1696 |
| Processes | 131 | 146 | 132 | 131 |
| Threads | 1316 | 1712 | 1443 | 1320 |
| Running services | 96 | 101 | 102 | 95 |
| Idle CPU, 60 s average (%) | 3.4 | 14.2 | 5.7 | 2.9 |
| Disk used on C: (GB) | 20.9 | 22.9 | 22.8 | 20.9 |
| CPU: SHA-256 on one core (MB/s) | 1862 | 1838 | 1877 | 1870 |
| Memory copy, 256 MB (MB/s) | 17881 | 17640 | 18273 | 18004 |
| Disk write, 1 GB write-through (MB/s) | 1301 | 1450 | 1737 | 1646 |
| Installed Store apps (non-framework) | 50 | 32 | 30 | 50 |
| BAKA Desktop's own memory | – | 43 MB | 44 MB | – |

**Performance and footprint score: 80.6 in round 2, 90.7 in round 1** (100 = the same as stock Windows; the geometric mean of BAKA-vs-stock ratios over boot time, memory in use, memory committed, processes, running services, idle CPU, disk used, CPU, memory copy and disk write).

What this means:
- CPU and memory speed are the same as stock (within 2%). Disk writes were 6 to 11% faster on BAKA in both rounds.
- At idle BAKA uses more: 200 to 450 MB more memory, more services and more idle CPU. Explorer, Start and Search still run behind BAKA Desktop (43 MB), and BAKA has 2 GB more on disk (Baka Browser, codecs, wallpapers).
- In round 2, Windows was re-installing Microsoft Edge 156 in the background during the measurement (its files are dated 3 minutes before the benchmark, see "Apps" below). That explains part of the extra processes, threads and CPU in that round; the rest was not traced.
- **BAKA does not make this VM faster at idle.** Its gains are what it removes and blocks, not idle numbers.

Not measurable here: game FPS, frame times and input latency (the VMs have no GPU), and WinSAT (Microsoft's benchmark refuses to run in a VM: "Unable to run inside of a Virtual Machine").

**Ad and tracker blocking** (every domain of the public [d3ward ad-block test](https://d3ward.github.io/toolz/adblock), resolved through Windows the way any app does), same in both rounds:

| | Stock | BAKA |
|---|---:|---:|
| Domains blocked | 2 of 131 (1.5%) | **131 of 131 (100%)** |

AdGuard DNS alone blocked 107 of 131 (81.7%) on the development PC; the BAKA hosts list covers the rest. The hosts list was built with the d3ward list in mind, so 100% on that list is expected; other test sites use other domains. Online tests that need a person in a browser (EFF Cover Your Tracks) were not run.

**Privacy settings** (10 checks: DiagTrack and push service disabled, telemetry policy, advertising ID, Copilot, Recall, Start web search, activity history, consumer features, telemetry tasks), same in both rounds:

| | Stock | BAKA |
|---|---:|---:|
| Privacy checks passed | 0 of 10 | 8 of 10 |

BAKA misses two: the machine-wide "consumer features" policy key is not set, and 3 tasks in the Application Experience and Customer Experience Improvement Program folders are still enabled (stock: 7).

**Apps:**
- **Microsoft Edge: not reliably removed.** BAKA removes the Edge app package, runs Edge's own uninstaller and sets the Edge Update policy that forbids installing Edge. Edge's uninstaller returned exit code 60 (refused) in both rounds. In round 1 Edge was gone at the time of the check; in round 2 Windows had installed Edge 156 again (new app package and files) shortly after first sign-in, despite the policy. Treat Edge removal as not working on this Windows build.
- WebView2 kept (both), Microsoft Store kept (both), Media Player kept (both), legacy Windows Media Player removed (stock: installed), Baka Browser installed and default, power plan "BAKA Gaming" (stock: Balanced).

**Desktop state in the installed VM** (`BakaDesktop.exe --status`, run in the signed-in user's session, round 2): Windows taskbar hidden, BAKA menu bar and dock present, dock 58 px wide, work area starts 30 px from the top (below the menu bar) and 72 px from the left (next to the dock), folders open in BAKA Files, no shell override, ad-block DNS on, WebView2 installed, Baka Browser installed. Setup reached the desktop with no account page and signed in automatically, in both rounds.

**Feature test in the installed VM:** BAKA Desktop's self-test (Launchpad and search, Control Center, every Settings page, BAKA Files including creating and deleting a folder, Arena, all widgets, gaming profile switching, dock positions and width, all 12 themes, icons) passed every check, twice per round, in the signed-in BAKA session.
