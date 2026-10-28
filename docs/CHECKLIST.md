# BAKA Windows: your requests checklist

Updated: 2026-10-28 (R9: compact UI, Windows key, themed icons, RAM fixes). A box is ticked only when it is done **and** verified on an installed BAKA system. "Built" means the code is written and the automated tests pass, but it has not yet been seen working in an installed VM.

Legend: ✅ done and verified · 🟡 built, waiting for VM proof · 🔄 in progress · ❌ not done / blocked

## Core OS

| | Request | Status / evidence |
|---|---|---|
| ✅ | Remove junk apps (debloat) | 19 exact packages removed; installed VM's Installed apps listed only Edge and Remote Desktop |
| 🟡 | Remove useless services and background tasks | Telemetry/feedback services and 13 tasks disabled and restorable; tests 4/4 |
| 🟡 | Privacy, no ads, no tracking | Copilot, Recall, ads ID, tips, suggestions, Start web search, Spotlight, Edge nags off. Windows Pro keeps "required" diagnostics (Microsoft limit) |
| ✅ | No Windows login page | Installed R5.3 and R7 VMs boot straight to the desktop with no password |
| 🟡 | Gaming tweaks for every game (improved in R8) | Game Mode, GPU scheduling, no recording, raw mouse, foreground CPU priority (Win32PrioritySeparation 38), no power throttling, VRR + windowed-game optimizations, MMCSS foreground-only, no Sticky/Filter/Toggle Keys pop-ups. All backed up and restorable. **Your PC test decides the FPS result** |
| 🟡 | BAKA Gaming power plan (improved in R8) | 22 settings on an Ultimate Performance base: 100% min CPU, EPP 0, boost aggressive/100%, no core parking, no throttle states, active cooling, faster ramp-up, USB/PCIe/AHCI/NVMe power saving off, no sleep or wake timers on AC; hibernation off on desktops. Laptops keep battery-friendly DC values |
| ❌ | Proven FPS / latency improvement | You are testing on your PC after the build (not tested here, by your request) |

## Browser

| | Request | Status / evidence |
|---|---|---|
| 🟡 | Baka Browser preinstalled | Baka Browser 1.3.0 ships inside the ISO and installs before the desktop appears, plus self-repair |
| 🟡 | Baka Browser is the default browser | Default-associations policy + registration |
| ✅ | Baka Browser matches the BAKA theme | New **Baka** theme (graphite surfaces, white text and accent), default on new installs. Built from source; 26/26 self-checks pass, including contrast. Pushed to OldcarryG/Baka-browser `4e47a7a` (v1.3.0) |
| 🔄 | Try Baka Browser 1.3.0 on your PC, release it on GitHub if you like it | Preview copy running on your PC with a separate test profile (your real profile is untouched). **GitHub release waits for your OK** |

## Desktop and UI

| | Request | Status / evidence |
|---|---|---|
| ✅ | Design you approved: Carbon layout + Stealth Mono colors | Seen in the installed R7 VM: left dock, menu bar, mono wallpaper, Arena |
| 🟡 | Liquid glass look with animation | Frosted glass, glint sweep, dock bounce, window pop |
| 🟡 | Completely replace the Windows taskbar (full shell) | **R7 VM bug found:** using powershell.exe as the shell opened a visible Windows Terminal, and nothing restarted BAKA when it stopped. **Fixed in R8:** a windowless native launcher (BakaShell.exe) is the shell, restarts BAKA, and falls back to Explorer after 3 failures |
| 🟡 | Close buttons everywhere | Red close / amber hide lights on Arena, Files, Settings, Control Center; Esc; Launchpad ✕ |
| 🟡 | Custom wallpaper (image, video, color, gallery) | 5 BAKA wallpapers (Stealth default) + any image/video/color |
| 🟡 | Full customisation freedom | Themes, accent, glass, motion, dock side/size, pinned apps, icons, widgets, menu bar |
| 🟡 | Useful things in the UI | Launchpad, Control Center (volume, power plan, profiles, power actions), Files, Arena, Windows-key launcher |
| 🟡 | No PowerShell commands to run things | Tools in BAKA Settings > System and a Start-menu folder, no console windows; the shell itself no longer runs in a console (R8) |
| 🟡 | Optimized UI, less RAM, no lag (improved after R8) | Blur shadows and the pointer light removed, opaque Launchpad, Arena built only when opened, one reused metrics worker instead of a new PowerShell runspace every 3 s, memory trimmed after startup/idle/game start, below-normal priority during games. Measured on this PC (preview, not the installed image): everyday desktop (dock + menu bar) **74.5 MiB, 0.63% CPU**; with Arena open 262 MiB, 0.84% CPU |
| 🟡 | Smaller UI matching the approved mock | Dock icons 52 → 40 px, menu bar 34 → 28 px, Arena/Files drawn at 80%, Settings/Control Center at 85%, smaller Launchpad and Control Center tiles, cleaner Look section |
| 🟡 | Windows key works in the BAKA UI | Low-level key hook: a lone Win tap opens the BAKA launcher instead of Start, Win+key shortcuts keep working, Ctrl+Esc still opens Windows Start. Works in shell and Explorer mode; off during games |
| 🟡 | App icons match the theme automatically | Dock, Launchpad, and running-app icons are re-tinted to the theme's text color (mono for Carbon), and rebuild when you change theme. Can be turned off with the themed-icons setting |
| ❌ | Tray icons (Discord, Steam) in full shell mode | Not done: needs a native tray host |
| ❌ | Fully native C# desktop | Not done: the launcher is native now, the desktop UI is still PowerShell + WPF |
| ❌ | Windows Settings / Store / Xbox in full shell mode | Not yet tested in the VM |

## Shipping

| | Request | Status / evidence |
|---|---|---|
| ✅ | Source and tests on GitHub | `d6f5114` on OldcarryG/Baka-windows; all 9 test suites pass |
| ✅ | Clean R8 ISO | `Output/BAKA-Windows-Gaming-Edition-26H2-x64-CarbonShell-R8-20261028.iso`, 11,174,055,936 bytes, SHA-256 `187EE1E10BF0A204C7F436C68648C0F458BE73298A7124B0C4CBB5B12D5AA488`. Structural validation passed: valid Microsoft Setup signature, Windows 11 Pro 26300.9711, Baka Browser 1.3.0 hash matches, BakaShell.exe present |
| ✅ | Clean R9 ISO (compact UI, Windows key, themed icons, RAM fixes) | `Output/BAKA-Windows-Gaming-Edition-26H2-x64-CarbonShell-R9-20261028.iso`, 11,174,060,032 bytes, SHA-256 `40E4EC950571458ACD9AED8CF2E7D39A7895B04A7060B4CE75A31C11993705DC`. Structural validation passed (valid Setup signature, Windows 11 Pro 26300.9711, Baka Browser 1.3.0 hash matches) |
| ❌ | Test R8/R9 in VMware | Blocked: the VMware encryption password for the test VM is no longer saved in Windows Credential Manager, so the VM cannot be reinstalled automatically |
| ➖ | Games tested | Skipped here by your request; you test on your PC |
| ❌ | 100% complete | Not yet: VM proof for the 🟡 items, tray icons, native desktop |

## Score

7 of 32 verified (✅), 17 built and waiting for VM or PC proof (🟡), 1 waiting on your decision (🔄), 6 not done, blocked, or waiting on your PC test (❌), 1 skipped by request (➖).

The R9 ISO includes the compact UI, Windows-key, themed-icon, and RAM fixes. R8 does not.
