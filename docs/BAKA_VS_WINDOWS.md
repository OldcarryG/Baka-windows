# BAKA Windows vs normal Windows 11

Both are Windows 11 Pro 26H2 (build 26300) from Microsoft's own installation media. BAKA keeps Windows itself intact (Windows Update can be turned back on, Windows Security, Store, drivers and every app work as usual) and changes what is around it. Everything BAKA changes can be undone with **Restore BAKA System Tuning** or **BAKA Settings > Windows > Leave BAKA**.

## Desktop

| | Normal Windows 11 | BAKA |
|---|---|---|
| Taskbar | Windows taskbar at the bottom | **BAKA menu bar** at the top (BAKA menu, Apps, Files, Arena, Settings, the app in front, tray, network, volume, battery, clock, notifications, Control Center) and the **BAKA dock** on the left (or bottom/right). The Windows taskbar is hidden and comes back by itself if BAKA ever stops. |
| Start menu | Start with recommendations and web search | **Launchpad** (Windows key): every installed app, and one search for apps, Windows settings pages and files. Typo-tolerant ("setings", "discrod"), matches program names ("cmd", "regedit") and initials ("vsc"). Ctrl+Esc still opens Start. |
| Maximized windows | Stop at the taskbar | Stop below the menu bar and next to the dock, so close/minimize/maximize buttons are never covered. Fullscreen video and games cover the bars, as they cover the taskbar. |
| File manager | File Explorer | **BAKA Files**: sidebar with places and drives (with free space), sortable list, search in folder and subfolders, copy/cut/paste with the Windows clipboard, drag and drop, delete to Recycle Bin, rename, new folder/text file, ZIP compress/extract, open with, properties, open Terminal here. Win+E and folders opened from any app open here. File Explorer still runs in the background because Windows needs it for tray icons, notifications and file dialogs. |
| Window buttons | Windows' minimize, maximize and close | **BAKA's amber, green and red buttons on every app window** (Notepad, Store apps such as Calculator and Media Player, most desktop apps), in Windows order. Nothing is loaded into the apps, so anti-cheat is not affected. Apps running as administrator, dialogs and fullscreen windows keep their own buttons. Hidden while a game runs. Can be turned off in Settings > Windows. |
| Wallpaper | Picture, slideshow, Spotlight | Picture, solid colour, or **4K video** (H.264, HEVC, VP9, AV1 in MP4/MOV/MKV/WebM/WMV/AVI) decoded on the graphics card by Windows' Media Foundation. Pauses when a maximized or fullscreen window covers the desktop, on battery and when locked; closed during games. |
| Moving windows | Smooth | BAKA's own windows use the same Mica backdrop as Windows 11 apps, so they move as smoothly. |
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
| Input path while gaming | Any app's hooks stay | BAKA removes its own keyboard hook while a game runs, so key presses go straight to the game (VM: median 0.221 ms vs stock 0.225 ms). |
| Tuning for your hardware | – | [AI tuning prompt](OPTIMIZE_WITH_AI.md) for any AI coding agent: inventory, benchmark, plan, measured changes only, undo script. |
| Other tuning | Default | Hardware GPU scheduling, optimizations for windowed games, foreground priority, no network throttling for games, full-quality wallpapers. |

## Privacy and ads

| | Normal Windows 11 | BAKA |
|---|---|---|
| Ads in every app | No blocking | Encrypted **AdGuard DNS** for every app, plus a BAKA block list in the Windows hosts file for ad, analytics and error-tracking hosts that DNS lists miss. |
| Browser | Microsoft Edge | **Baka Browser** (default), with uBlock Origin Lite, strict tracking prevention and no SmartScreen URL reporting. BAKA uninstalls Edge and blocks its reinstall by policy. Edge was absent in all R13 VM installs; in R12 Windows put it back once, so this is not guaranteed. The WebView2 runtime that apps need is kept. |
| Telemetry | Full diagnostic upload service | DiagTrack and push-routing services off; Inventory and Compatibility Appraisal, Windows Health and Optimized Experiences, Windows AI Components Host and Distributed Link Tracking services off; 16 telemetry tasks off; app inventory and application telemetry policies off; diagnostic data at the lowest level Windows Pro allows. Windows Pro still keeps "required" diagnostic data; BAKA does not claim zero telemetry. |
| Copilot, Recall, ads ID, tips, Start web search, Spotlight | On | Off |

## Apps

| | Normal Windows 11 | BAKA |
|---|---|---|
| Removed | — | Internet Explorer, the legacy Windows Media Player, Movies & TV, Clipchamp, WordPad, Steps Recorder, Math Input Panel, Fax and Scan, PowerShell ISE, Xbox app, Game Bar, News, Weather, Office hub, Solitaire, Teams (personal), Bing Search, Outlook (new), To Do, Power Automate, Get Help, Feedback Hub, Dev Home, Phone Link, Cross Device, Quick Assist, Copilot, Maps, People, Family |
| Store apps | Install and run | Install and run (tested in the VM: WhatsApp, Microsoft To Do and Spotify installed with winget from the Store and started). **Exception:** apps that need Edge as a component, such as Netflix, do not install, because Edge is removed (error 0x80073D31, "depends on a framework that could not be found: Microsoft.MicrosoftEdge.Stable"). |
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
| 1.6.2 (in R13) | Fixed: a video picked as the new-tab background did not play. The browser now serves the file itself with seeking support; the UI test checks a .webm and an .mp4 clip. |
| 1.6.1 (in R12) | Fixed: Settings > Appearance > "Choose image or video…" (new-tab background) failed on a new profile with "Could not find a part of the path …\baka-browser\home-assets\…"; the folder is now created first. |
| 1.6.0 | Tab right-click menu (new tab, reload, duplicate, mute site, copy address, move to new window, close, close others, close tabs below/right, reopen closed tab). Drag tabs to reorder, or drag one off the strip into its own window. Speaker icon on tabs that play sound, click to mute. Ctrl+Shift+T reopens closed tabs (last 25), Ctrl+1 to Ctrl+8 select a tab, Ctrl+9 the last. Fixed: closing a background tab changed the selected tab; Ctrl+W inside a page; zoom changes now apply to open tabs. A second window no longer overwrites the main window's session, settings or history. |
| 1.5.0 (in R11) | uBlock Origin Lite added from the Chrome Web Store on first start (removal is respected). Background tabs use less memory. Upload (photo, 40 MB video) and 4K decoding self-tests. |
| 1.4.0 (in R10) | Chrome Web Store: an "Add to Baka" button downloads the extension from Google, checks its CRX3 signature against the extension ID, shows its permissions and installs it. Extensions menu, popups and options pages. New main menu, zoom, print, home button. Redesigned settings with a section rail. Flat graphite BAKA theme. |
| 1.3.0 (not published, shipped in 1.4.0) | BAKA theme in the BAKA Windows colours, soft-white default accent. |

## Measured in virtual machines

Both systems were installed from their ISOs into identical Hyper-V VMs (Generation 2, Secure Boot, virtual TPM 2.0, 4 vCPU, 6 GB fixed memory, 64 GB disk) on the same host and measured one at a time with the same script (`Guest-Bench`) over PowerShell Direct. Stock is the official Windows 11 Pro 26H2 ISO with no changes.

R13 measures three states: stock Windows, **BAKA in Desktop mode** (normal use), and **BAKA in Gaming mode** (the same VM a minute after `BakaDesktop.exe --profile gaming`, which is what Arena's Gaming card and a detected game do: menu bar, dock, widgets and BAKA window buttons hidden, BAKA's memory trimmed). Each VM was restarted, signed in, and left alone for 10 minutes before measuring, so first-boot work (indexing, Store and Defender updates) does not count. Measured 2026-10-29 on the R13 candidate whose BAKA Desktop differs from the final R13 only in which windows get BAKA buttons.

| Measurement | Stock | BAKA Desktop mode | BAKA Gaming mode |
|---|---:|---:|---:|
| Boot time (Windows boot event, s) | 29.3 | **26.5** | (same boot) |
| Main boot path (s) | **6.9** | 8.8 | (same boot) |
| Memory in use at idle (MB) | 2295 | 2354 | **2242** |
| Memory committed (MB) | 1971 | 1975 | **1906** |
| Processes | 138 | 135 | **130** |
| Threads | **1421** | 1630 | 1594 |
| Running services | 99 | 98 | **97** |
| Idle CPU, 60 s average (%) | **3.6** | 13.5 | 5.0 |
| BAKA Desktop's own CPU (%) | – | 0.03 | 0.03 |
| BAKA Desktop's own memory (MB) | – | 43 | 39 |
| Disk used on C: (GB) | **21.7** | 23.0 | 22.9 |
| CPU: SHA-256 on one core (MB/s) | 1850 | 1855 | 1874 |
| Memory copy, 256 MB (MB/s) | 14512 | **17498** | 17081 |
| Disk write, 1 GB write-through (MB/s) | 1140 | 1431 | **1442** |
| Installed Store apps (non-framework) | 50 | 30 | 30 |

**Performance and footprint score: 91.8 in Desktop mode, 101.9 in Gaming mode** (100 = the same as stock; geometric mean of BAKA-vs-stock ratios over boot time, memory in use, memory committed, processes, running services, idle CPU, disk used, CPU, memory copy and disk write; Gaming mode uses the same metrics without boot time).

What this means:
- **BAKA adds almost nothing while gaming.** In Gaming mode BAKA uses less memory (−53 MB), fewer processes (−8) and fewer services than stock, and BAKA Desktop itself used 0.03% CPU and 39 MB. Its window scan, BAKA buttons and widgets are off while a game runs.
- **Idle CPU is still higher than stock** (13.5% in Desktop mode, 5.0% in Gaming mode, stock 3.6%). The time is not spent in BAKA Desktop (0.03%). In the Desktop-mode sample Microsoft Defender (1.7% of all cores) and the kernel (1.0%) were the largest users, and most of the rest was not attributed to any process (interrupt and DPC time). In the fresh-install round before the 10-minute settle the numbers were 12.6% (Desktop) and 8.0% (Gaming) against stock 4.2%, with one svchost at 5.8%. This was not traced to a cause, so BAKA does not claim lower idle CPU.
- Boot to the desktop event was 2.8 s faster on BAKA in this round (26.5 vs 29.3 s), but the main boot path was 1.9 s slower; boot time varied by several seconds between rounds on both systems.
- CPU speed is the same. Memory copy and disk writes were 18 to 26% faster on BAKA in this round; in R12 they were within 1 to 11%, so treat part of this as VM variance.
- BAKA uses 1.2 GB more disk (Baka Browser, codecs, wallpapers) and has more threads.

Not measurable here: game FPS, frame times and input latency (the VMs have no GPU), and WinSAT (Microsoft's benchmark refuses to run in a VM: "Unable to run inside of a Virtual Machine").

R12 for comparison (fresh install, 3 minutes idle, final R12 build): score 80.6, memory in use 2451 vs 2005 MB, idle CPU 14.2 vs 3.4%; Windows was re-installing Edge during that measurement.

**Ad and tracker blocking** (every domain of the public [d3ward ad-block test](https://d3ward.github.io/toolz/adblock), resolved through Windows the way any app does), same in both rounds:

| | Stock | BAKA |
|---|---:|---:|
| Domains blocked | 2 of 131 (1.5%) | **131 of 131 (100%)** |

AdGuard DNS alone blocked 107 of 131 (81.7%) on the development PC; the BAKA hosts list covers the rest. The hosts list was built with the d3ward list in mind, so 100% on that list is expected; other test sites use other domains. Online tests that need a person in a browser (EFF Cover Your Tracks) were not run.

**Privacy settings** (12 checks: DiagTrack and push service disabled, telemetry policy, advertising ID, Copilot, Recall, Start web search, activity history, consumer features, 16 named telemetry tasks disabled, app inventory off, no telemetry service running among DiagTrack, dmwappushservice, InventorySvc, whesvc, WSAIFabricSvc and TrkWks):

| | Stock | BAKA |
|---|---:|---:|
| Privacy checks passed | 0 of 12 | **12 of 12** |
| Telemetry tasks enabled (of 16) | 14 | 0 |
| Telemetry services running | 5 | 0 |

R12 scored 8 of 10 on the older list. The task check changed in R13: it now counts the 16 named telemetry tasks, where R12 counted every task in two folders, including two app-compatibility database tasks that send nothing and stay on.

**Apps:**
- **Microsoft Edge:** BAKA removes the Edge app package, runs Edge's own uninstaller and sets the Edge Update policy that forbids installing Edge. In the R13 VM installs Edge was absent at every check. In R12 Windows installed Edge 156 again once, despite the policy, so removal is not guaranteed on this Windows build.
- **Store apps:** WhatsApp, Microsoft To Do and Spotify installed from the Store (winget, msstore source) and started, in two R13 installs. Netflix did not install: it needs Edge as a component (0x80073D31). Any Store app built on Edge has the same problem while Edge is removed.
- WebView2 kept (both), Microsoft Store kept (both), Media Player kept (both), legacy Windows Media Player removed (stock: installed), Baka Browser installed and default, power plan "BAKA Gaming" (stock: Balanced).

**Desktop state in the installed VM** (`BakaDesktop.exe --status`, run in the signed-in user's session, R13): Windows taskbar hidden, BAKA menu bar and dock present, dock 58 px wide, work area starts 30 px from the top (below the menu bar) and 72 px from the left (next to the dock), folders open in BAKA Files, no shell override, ad-block DNS on, Edge not installed, WebView2 installed, Baka Browser installed. Setup reached the desktop with no account page and signed in automatically in every install.

**Feature test in the installed VM:** BAKA Desktop's self-test (Launchpad and search, Control Center, every Settings page, BAKA Files including creating and deleting a folder, Arena, BAKA buttons on Notepad and Calculator, all widgets, gaming profile switching, dock positions and width, all 12 themes, icons) passed every check in the signed-in BAKA session.

**Using it like a person (simulated mouse and keyboard in the VM, R13):** BAKA buttons appear on Notepad, Calculator and Media Player, follow the window when it is dragged, and minimize, maximize and close it. Dragging Notepad, Calculator, Media Player, System Information and BAKA Files by the title bar moves them by exactly the distance dragged. The tray button in Control Center shows the Windows tray icons and hides them again. Media keys could not be tested: the VM has no sound device, so Media Player never starts a playback session.
