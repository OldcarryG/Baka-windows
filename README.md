# BAKA Windows Gaming Edition

A custom Windows 11 Pro 26H2 (x64) image for gaming. It replaces the taskbar, Start menu and File Explorer windows with its own desktop, puts BAKA buttons on every app window, plays 4K video wallpapers on the graphics card, removes apps most people never use, blocks ads and trackers for every app, turns off telemetry, and ships [Baka Browser](https://github.com/OldcarryG/Baka-browser) as the default browser. When a game starts, BAKA gets out of the way: its UI, keyboard hook and video wallpaper are switched off, so it adds almost nothing while you play.

[![Source validation](https://github.com/OldcarryG/Baka-windows/actions/workflows/source-validation.yml/badge.svg?branch=main)](https://github.com/OldcarryG/Baka-windows/actions/workflows/source-validation.yml)

**Download:** the full ISO is on MEGA, linked from the [latest release](https://github.com/OldcarryG/Baka-windows/releases/latest) together with its SHA-256.

![BAKA desktop on an installed system (Hyper-V VM)](docs/screenshots/installed-desktop.png)

| Launchpad (Windows key) | Search | BAKA Files |
|---|---|---|
| ![Launchpad](docs/screenshots/launchpad.png) | ![Search](docs/screenshots/search.png) | ![BAKA Files](docs/screenshots/files.png) |
| **Control Center** | **BAKA Settings** | **BAKA Arena** |
| ![Control Center](docs/screenshots/control-center.png) | ![BAKA Settings](docs/screenshots/settings.png) | ![BAKA Arena](docs/screenshots/arena.png) |

BAKA buttons on other apps (Notepad, Calculator, Media Player), captured in the installed VM:

![BAKA buttons on Notepad](docs/screenshots/baka-buttons-notepad.png)
![BAKA buttons on Calculator](docs/screenshots/baka-buttons-calculator.png)
![BAKA buttons on Media Player](docs/screenshots/baka-buttons-mediaplayer.png)

![125 BAKA icons in the Carbon Red theme](docs/screenshots/icons-carbon-red.png)

## Features

### Desktop
- **BAKA Desktop**, a compiled app (C#/WPF on .NET Framework 4.8, which ships with Windows). No PowerShell runs for the desktop. It restarts itself after a crash; after three crashes in two minutes it gives back the normal Windows taskbar.
- **Menu bar** on top and **dock** on the left (or bottom or right). They reserve their screen edge like the taskbar, so maximized windows never hide their buttons under them.
- **BAKA buttons on every app window**: amber, green and red minimize, maximize and close on Notepad, Store apps and most desktop apps. Nothing is loaded into other apps, so anti-cheat is not affected. Apps running as administrator, dialogs and fullscreen windows keep Windows' buttons.
- **4K video wallpaper**: MP4, MOV, MKV, WebM, WMV and AVI with H.264, HEVC, VP9 or AV1, up to 4K (higher if your graphics card decodes it). Windows' own Media Foundation player decodes it on the graphics card and draws it straight to the screen, so a 4K video costs well under 1% CPU on a PC with a GPU. It pauses when a maximized or fullscreen window covers the desktop, on battery and while the PC is locked, and it is closed completely (decoder and video memory freed) while a game runs. A video Windows cannot play falls back to the picture and Settings shows why.
- **Launchpad** (Windows key): every installed app, and one search for apps, Windows settings pages and files. Tolerates typos ("setings"), knows program names ("cmd") and initials ("vsc").
- **BAKA Files**: places and drives, sorting, search in subfolders, copy/cut/paste, drag and drop, Recycle Bin, rename, ZIP, Open with, Properties, Terminal here. Win+E and folders from any app open here.
- **125 hand-drawn app icons** drawn in each theme's style; **12 themes**, accent colours, glass and motion levels.
- **Control Center**, **BAKA Settings**, **BAKA Arena** (profiles, live performance numbers, every Steam and Epic game) and **widgets** (clock, calendar, system monitor, notes, media controls, focus timer).
- BAKA's own windows use the Mica backdrop, so they move as smoothly as Windows 11 apps.

### Gaming and latency
- A running game (Steam, Epic, GOG, EA, Ubisoft, Xbox, Riot, Battle.net, itch or any fullscreen app) switches BAKA to **Competitive Gaming**: menu bar, dock, widgets, BAKA buttons and video wallpaper go away, BAKA's **keyboard hook is removed** (so no key press of the game passes through BAKA), transparency and animations off, background apps paused, BAKA's memory trimmed. Everything comes back when the game closes.
- **BAKA Gaming power plan** (Ultimate Performance base, no core parking, no USB suspend), Game Mode, hardware GPU scheduling, raw mouse input (no acceleration), no Sticky/Filter/Toggle Keys pop-ups, windowed-game optimizations, no network throttling for games.
- Free AV1, VP9, HEVC and HEIF codecs installed from the Microsoft Store at first sign-in.
- **[Tune it for your hardware with an AI coding tool](docs/OPTIMIZE_WITH_AI.md)**: a ready-made prompt for Claude Code, Codex, Gemini CLI, Cursor, Kiro or similar. The AI inventories your CPU, GPU, RAM, monitor and network, benchmarks first, shows a plan, applies only measured improvements, keeps security on, and writes an undo script.

### Privacy, ads and clean-up
- Ads and trackers blocked for every app: encrypted AdGuard DNS plus a BAKA hosts block list. One switch in Settings turns both off.
- Telemetry off: DiagTrack, dmwappushservice, Inventory and Compatibility Appraisal, Windows Health and Optimized Experiences, Windows AI Components Host, Distributed Link Tracking, 16 telemetry tasks, app inventory and application telemetry. Copilot, Recall, advertising ID, tips, suggestions, Start web search, activity history and Spotlight off. Windows Pro still sends "required" diagnostic data; BAKA does not claim zero telemetry.
- Removed: Internet Explorer, legacy Windows Media Player, Movies & TV, WordPad, Steps Recorder, Math Input Panel, Fax and Scan, PowerShell ISE, Clipchamp, Copilot, Maps, People, Family and 19 more consumer apps; Microsoft Edge (WebView2 kept).
- Kept: Microsoft Store (WhatsApp, Spotify, To Do and others install and run), Media Player, Photos, Paint, Notepad, Calculator, Snipping Tool, Terminal, Windows Security, Xbox sign-in.
- Boots straight to the desktop with a passwordless local account. Everything BAKA changes is backed up; **Restore BAKA System Tuning** puts it back.

### Baka Browser 1.6.2
Preinstalled and the default browser: uBlock Origin Lite, Chrome Web Store extensions, new-tab background picture or video, tab menu, drag tabs to reorder or into a new window, mute button, 4K VP9/AV1 video.

## BAKA vs normal Windows 11

| | Normal Windows 11 Pro | BAKA Windows |
|---|---|---|
| Taskbar and Start | Taskbar, Start with recommendations and web results | Menu bar, dock, Launchpad with typo-tolerant search, no web results, no ads |
| Window buttons | Windows' buttons | BAKA amber/green/red buttons on every app |
| File manager | File Explorer | BAKA Files (Explorer still runs hidden for tray, notifications, file dialogs) |
| Wallpaper | Picture, slideshow, Spotlight | Picture, colour, or 4K video decoded on the GPU, paused when covered, closed in games |
| While gaming | Taskbar, widgets, background apps keep running | BAKA UI, keyboard hook and video wallpaper off; BAKA uses 0.03% CPU |
| Power plan | Balanced | BAKA Gaming (Ultimate Performance base) |
| Game DVR / Game Bar | On | Off |
| Mouse acceleration | On | Off (raw input) |
| Ads and trackers (d3ward list, 131 domains) | 2 blocked | **131 blocked** |
| Privacy checks (12) | 0 | **12** |
| Telemetry tasks / services running | 14 / 5 | 0 / 0 |
| Copilot, Recall, ads ID, tips, Spotlight, Start web search | On | Off |
| Microsoft Edge | Installed, default browser | Removed; Baka Browser is the default (WebView2 kept) |
| Preinstalled consumer apps | 50 Store apps | 30 |
| Setup | Account, privacy and Microsoft-account screens | Straight to the desktop; disk choice stays interactive |
| Security (Defender, firewall, Secure Boot, TPM, VBS, updates) | On | On (nothing bypassed) |
| Undo | – | Restore BAKA System Tuning, Settings > Windows > Leave BAKA |

The full comparison, with every setting, is in [docs/BAKA_VS_WINDOWS.md](docs/BAKA_VS_WINDOWS.md).

## Benchmark

Stock Windows 11 and BAKA were installed from their ISOs into identical Hyper-V VMs (Generation 2, Secure Boot, virtual TPM 2.0, 4 vCPU, 6 GB), restarted, left idle for 10 minutes and measured with the same script. BAKA was measured in Desktop mode and again in Gaming mode (what a running game switches to).

| | Stock Windows 11 | BAKA Desktop mode | BAKA Gaming mode |
|---|---:|---:|---:|
| **Score** (100 = stock) | 100 | 91.8 | **101.9** |
| Memory in use at idle | 2295 MB | 2354 MB | **2242 MB** |
| Processes / running services | 138 / 99 | 135 / 98 | **130 / 97** |
| Idle CPU | **3.6%** | 13.5% | 5.0% |
| BAKA Desktop's own CPU / memory | – | 0.03% / 43 MB | 0.03% / 39 MB |
| CPU (SHA-256, MB/s) | 1850 | 1855 | 1874 |
| Memory copy (MB/s) | 14512 | 17498 | 17081 |
| Disk write (MB/s) | 1140 | 1431 | 1442 |
| Boot to desktop (Windows boot event) | 29.3 s | 26.5 s | |

**Input latency** (time from an injected key press until the app in front receives it, 200 presses, same VMs):

| | Stock Windows 11 | BAKA Desktop mode | BAKA Gaming mode |
|---|---:|---:|---:|
| Median | 0.225 ms | 0.297 to 0.299 ms | **0.214 to 0.221 ms** |
| 99th percentile | **0.386 ms** | 0.743 to 1.075 ms | 0.618 to 0.893 ms |

BAKA was measured in two installs, stock in one. In Gaming mode BAKA removes its keyboard hook, so the median is the same as stock; the slowest 1% of key presses are 0.2 to 0.5 ms slower than stock (VM noise; one stock key press took 16.7 ms). In Desktop mode the hook (Windows key opens Launchpad) adds about 0.07 ms per key press. Mouse latency and the 1 ms timer could not be measured in Hyper-V.

**4K video wallpaper** (`--video-test`, 4K clips, 12 s each; CPU is BAKA Desktop's share of all cores):

| Format | Development PC (RTX 5060) | VM (no GPU, software decoding) |
|---|---|---|
| H.264 MP4 4K | plays and loops, **0.2% CPU** | plays and loops, 36% |
| HEVC MP4 4K | needs the HEVC extension (BAKA installs it) | plays, 50% |
| VP9 WebM 4K | plays, **2% CPU** | plays, 21% |
| AV1 WebM 4K | plays, **0% CPU** | too slow without a GPU |
| Paused when a maximized window covers the desktop | – | yes, CPU 37% → 0.05% |
| Closed while a game runs, back afterwards | – | yes, CPU 0% in Gaming mode |

![4K video wallpaper on the installed VM](docs/screenshots/video-wallpaper.png)

The score is the geometric mean of BAKA-vs-stock ratios over boot time, memory in use, memory committed, processes, services, idle CPU, disk used, CPU, memory copy and disk write. Idle CPU is still higher than stock in Desktop mode; it is not BAKA Desktop itself (0.03%) and the cause was not found. Game FPS cannot be measured in a VM without a GPU; use the [AI tuning prompt](docs/OPTIMIZE_WITH_AI.md) to benchmark and tune on your own PC.

## Install

1. Download the ISO from the MEGA link in the [latest release](https://github.com/OldcarryG/Baka-windows/releases/latest) and check its SHA-256 (`Get-FileHash <file>.iso` in PowerShell) against the one in the release.
2. Write it to a USB stick of 16 GB or more with [Rufus](https://rufus.ie) (GPT, UEFI), or mount it in a VM.
3. Boot from it. Setup asks which disk to install to (it never erases a disk on its own). TPM 2.0 and Secure Boot are required, as on stock Windows 11.
4. After about 10 minutes you are on the BAKA desktop. Baka Browser and the 4K codecs install in the background during the first minutes (internet needed).

To build the ISO yourself from Microsoft's official ISO, follow [docs/GITHUB_WORKFLOW.md](docs/GITHUB_WORKFLOW.md) and run the scripts in `Scripts/` (needs the Windows ADK Deployment Tools and the .NET SDK).

## Command line

`BakaDesktop.exe` (in `C:\ProgramData\BAKA\Desktop`):

| | |
|---|---|
| `--wallpaper <picture or video>` | set the desktop background |
| `--profile gaming` / `--profile desktop` | switch the profile (what Arena does) |
| `--video-test <file> <result.json> [s]` | check that this PC plays a video with the wallpaper player (writes CPU use, size, pause/resume) |
| `--status <file>` | what the desktop looks like, as JSON |
| `--tray` | show the Windows tray icons for a few seconds |
| `--preview`, `--selftest` | run the desktop in a throwaway profile / click through every surface (50 checks) |
| `--restore-windows` | put the normal Windows desktop back |

## Source checks

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

## Project layout

- `Shell/BakaDesktop/` the desktop (C#): menu bar, dock, Launchpad, Files, Settings, Control Center, Arena, widgets, icons, BAKA window buttons, video wallpaper player, Explorer integration, ad blocking
- `Scripts/` build pipeline and first sign-in setup
- `Modules/` power plan, system tuning, update control, gaming profile rules
- `Config/` answer file, debloat, privacy, block list, performance profiles, themes, applications (pinned Baka Browser installer)
- `Tests/` the checks above
- `docs/` comparison with stock Windows, release notes, AI tuning prompt, checklist, decisions, screenshots
