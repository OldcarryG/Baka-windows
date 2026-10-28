# BAKA Windows — your requests checklist

Updated: 2026-10-28. A box is ticked only when it is done **and** verified. "Source done" means the code is written and the automated tests pass, but it has not been seen working on an installed BAKA system yet.

Legend: ✅ done and verified · 🟡 source done, not yet verified on an installed system · 🔄 in progress · ❌ not done / blocked

## Core OS

| | Request | Status / evidence |
|---|---|---|
| ✅ | Remove junk apps (debloat) | 19 exact packages removed; verified in the installed R5.3 VM (Settings > Installed apps listed only Edge and Remote Desktop) |
| 🟡 | Remove useless services and background tasks | Telemetry/feedback services and 13 tasks are disabled and restorable; tests 4/4. Service state not yet inspected in an installed VM |
| 🟡 | Privacy, no ads, no tracking | Copilot, Recall, ads ID, tips, suggestions, Start web search, Spotlight, Edge first-run nags off. Windows Pro still keeps "required" diagnostics (Microsoft limit) |
| ✅ | No Windows login page | Installed R5.3 VM booted straight to the desktop with no password |
| 🟡 | Better gaming performance for all games | Game Mode, GPU scheduling, no background recording, raw mouse input, any-game detection. **No FPS gain is proven** — needs a real PC |
| 🟡 | Gaming power plan with tweaks | "BAKA Gaming" plan (Ultimate Performance base + CPU, USB, PCIe, sleep tweaks) created at first logon; switches on in Gaming mode. Tested on this PC's powercfg reads, not yet in VM |
| ❌ | Proven FPS / latency improvement | Blocked: needs physical gaming hardware, not a VM |

## Browser

| | Request | Status / evidence |
|---|---|---|
| 🟡 | Baka Browser preinstalled | Installs from the copy inside the ISO before the desktop appears, plus self-repair. **R5.3 VM showed it did not install** — fixed in R6/R7, not yet re-verified |
| 🟡 | Baka Browser is the default browser | Default-associations policy + registration. Not yet verified in an installed VM |

## Desktop and UI

| | Request | Status / evidence |
|---|---|---|
| ✅ | New design you approved: Carbon layout + Stealth Mono colors | Design capture `docs/evidence/screenshots/20261028-baka-r7-carbon-mono-design-capture.png` |
| 🟡 | Liquid glass look like Apple, with animation | Frosted glass, glint sweep, dock bounce, window pop. Real Windows 11 glass not yet seen in the VM |
| 🟡 | Completely replace the Windows taskbar (full shell, not a layer) | BAKA becomes the Windows shell at first sign-in; Explorer's taskbar/Start/desktop never load. Not yet seen in the VM |
| 🟡 | Close buttons everywhere | Red close / amber hide lights on Arena, Files, Settings, Control Center; Esc closes; Launchpad has ✕ |
| 🟡 | Custom wallpaper (image, video, color, gallery) | 5 BAKA wallpapers (Stealth default) + any image/video/color; in shell mode BAKA draws the desktop itself |
| 🟡 | Full customisation freedom | Themes, accent, glass, motion, dock side/size, pinned apps, custom icons, widgets, menu bar |
| 🟡 | Useful things in the UI | Launchpad (all apps), Control Center (volume, power plan, profiles, power actions), Files, Arena stats, Windows-key launcher |
| 🟡 | No PowerShell commands to run things | Tools moved into BAKA Settings > System and a Start-menu folder; they run without a console window |
| ❌ | Tray icons (Discord, Steam) in full shell mode | Not done: the tray needs a native tray host. Works only while Explorer runs |
| ❌ | Native C# rewrite for speed and low memory | Not done: this PC has no .NET SDK/MSBuild. The shell is still PowerShell + WPF (~200 MB RAM) |
| ❌ | Windows Settings / Store / Xbox work in full shell mode | Unknown risk on Windows Pro without Explorer; must be tested in the VM |

## Shipping

| | Request | Status / evidence |
|---|---|---|
| ✅ | Source and tests uploaded to GitHub | `670babb` pushed to github.com/OldcarryG/Baka-windows; all 9 test suites pass |
| 🔄 | Clean R7 ISO | Building now (`Output/BAKA-Windows-Gaming-Edition-26H2-x64-CarbonShell-R7-20261028.iso`) |
| 🔄 | Test the R7 changes in VMware | Disposable test VM reinstalls automatically after the ISO build (your own VM is never touched) |
| ❌ | Games tested (CS2 / TF2) | Blocked: needs your Steam login inside the VM |
| ❌ | GitHub progress page updated to final numbers | Waiting for the R7 VM results so the numbers are real |
| ❌ | 100% complete | Not honest yet: FPS proof, tray, native shell, and VM checks are still open |

## Score

4 of 26 items fully verified (✅), 13 written and waiting for VM proof (🟡), 2 in progress (🔄), 7 not done or blocked (❌).

I update this file each time an item changes, and push it to GitHub.
