# BAKA Windows: your requests checklist

Updated: 2026-10-28 (R11 and Baka Browser 1.5.0). A Windows item is ticked only when it is done **and** verified on an installed BAKA system. Browser items are ticked when the real browser passed a scripted user run on this PC (`--ui-test`, 30 of 30 steps). "Built" means the code is written and the automated tests pass, but it has not yet been seen working in an installed VM.

Legend: ✅ done and verified · 🟡 built, waiting for VM proof · 🔄 waiting on you · ❌ not done / blocked

## Core OS

| | Request | Status / evidence |
|---|---|---|
| ✅ | Remove junk apps (debloat) | 19 exact packages removed; installed VM's Installed apps listed only Edge and Remote Desktop |
| 🟡 | Remove useless services and background tasks | Telemetry/feedback services and 13 tasks disabled and restorable; tests 4/4 |
| 🟡 | Privacy, no ads, no tracking | Copilot, Recall, ads ID, tips, suggestions, Start web search, Spotlight, Edge nags off. Windows Pro keeps "required" diagnostics (Microsoft limit) |
| ✅ | No Windows login page | Installed R5.3 and R7 VMs boot straight to the desktop with no password |
| 🟡 | Gaming tweaks for every game | Game Mode, GPU scheduling, no recording, raw mouse, foreground CPU priority, no power throttling, VRR + windowed-game optimizations, MMCSS foreground-only, no Sticky/Filter/Toggle Keys pop-ups. All backed up and restorable. **Your PC test decides the FPS result** |
| 🟡 | BAKA Gaming power plan | 26 settings on an Ultimate Performance base (R11 added: games prefer performance cores on hybrid CPUs, no E-core parking, 15 ms CPU re-evaluation, no USB hub suspend; missing settings are skipped); laptops keep battery-friendly DC values |
| 🟡 | Tweaks researched online (R11) | Safe items adopted from Chris Titus Tech's winutil (MIT): network throttling off, long paths, faster menus, full-quality JPEG wallpaper, Edge telemetry/shopping policies, device metadata off, WPBT off, Notepad AI off, maps auto-update off, speech/inking personalisation off. Left out on purpose: IPv6 off, BitLocker off, Edge removal, location deny, background-apps off (they break things) |
| 🟡 | Ad and tracker blocking in Windows (R11) | Encrypted AdGuard DNS (DoH) on every adapter at first logon, previous DNS saved; on/off in BAKA Settings > System; undone by the restore shortcut. Not run on this PC (it would change your DNS) |
| 🟡 | 4K video in Windows (R11) | Free AV1, VP9, HEIF and HEVC (Device Manufacturer) codecs installed from Microsoft Store in the background at first logon |
| ❌ | Proven FPS / latency improvement | You are testing on your PC (not tested here, by your request) |

## Baka Browser

| | Request | Status / evidence |
|---|---|---|
| ✅ | Chrome Web Store support | **Add to Baka** button on store pages: downloads the package from Google, verifies the CRX3 signature against the extension ID, shows permissions, installs. Live run: Dark Reader and uBlock Origin Lite installed with their store IDs; Dark Reader themed a light page; its popup and options page opened; on/off and remove worked |
| ✅ | Browser UI matches the custom Windows | BAKA theme is now flat graphite (no Mica), pill address bar, 40 px toolbar, slimmer tab and bookmark rails. Old default (Dark + blue) moves to BAKA once on update |
| ✅ | Icons where they were missing | Main menu (every item), extensions menu, real shield icon, home button, chevron toggles, bookmark site icons, new-tab card icons and quick-link tiles, settings rail and buttons, dialogs |
| ✅ | Better settings page | Section rail with icons (Privacy, Appearance, Search, Extensions, Tabs & bookmarks, Performance, Compatibility, Advanced, About), rounded cards, switches, installed-extensions list, About page with update check, themed dialogs |
| ✅ | Popular ad blocker in the browser (1.5.0) | uBlock Origin Lite (free, open source) is added from the Chrome Web Store on first start; live UI run: installed in a fresh profile. Removal is respected; switch in Settings > Extensions |
| 🔄 | Photo and video upload | UI run uploads a 3 MB photo and a 40 MB video through a page's file input by form, fetch/FormData and 8 MB XHR chunks: all bytes arrive. Your failure is not reproduced here: tell me the site (and whether you used drag-and-drop or the file picker) |
| ✅ | 4K video in the browser | UI run: VP9, AV1 and H.264 at 3840×2160 60 fps report supported, smooth and hardware-decoded. HEVC needs Microsoft's HEVC codec (BAKA Windows installs it) |
| 🟡 | Browser performance (1.5.0) | Background tabs run with WebView2 memory target Low; idle tabs still sleep after 2 minutes. Memory saving not measured in numbers |
| ✅ | Release on GitHub | [v1.5.0](https://github.com/OldcarryG/Baka-browser/releases/tag/v1.5.0) and earlier [v1.4.0](https://github.com/OldcarryG/Baka-browser/releases/tag/v1.4.0) published by the release workflow: `BakaBrowser-win-Setup.exe` 59,278,796 bytes, SHA-256 `B708A19554FBDE8E932C60FA807E127ADEDC85AD4FB6E736C327D0D1A6C4D056`. Your installed copy updates itself |
| 🟡 | Baka Browser preinstalled | 1.4.0 (the exact GitHub installer, hash pinned) ships in R10 and installs before the desktop appears |
| 🟡 | Baka Browser is the default browser | Default-associations policy + registration |

## Desktop and UI

| | Request | Status / evidence |
|---|---|---|
| ✅ | Design you approved: Carbon layout + Stealth Mono colors | Seen in the installed R7 VM: left dock, menu bar, mono wallpaper, Arena |
| 🟡 | Compact, small, clean UI like the mock (R10) | Arena rebuilt at its real size (720 × 470, was 1120 × 790 scaled down): profile tiles, four live numbers, quick actions, gaming changes, no filler text. BAKA Files layout fixed (sidebar was floating mid-window, white column header, clipped buttons). Smaller dock, menu bar, tiles |
| 🟡 | Optimized UI, less RAM, no lag | No blur shadows or pointer light, opaque Launchpad, Arena built only when opened, one reused metrics worker, memory trimmed when idle. Measured on this PC (preview): everyday desktop **75–105 MiB, 0.6–0.8% CPU**; with Arena open about 250 MiB |
| 🟡 | Completely replace the Windows taskbar (full shell) | BakaShell.exe is the shell, restarts BAKA, and falls back to Explorer after 3 failures |
| 🟡 | Windows key works in the BAKA UI | Lone Win tap opens the BAKA launcher; Win+key shortcuts and Ctrl+Esc still work; off during games |
| 🟡 | Custom app icon styles that follow the theme, plus transparent and wallpaper (R11) | BAKA Settings > Appearance > App icons and Control Center > Look: Themed (default, rounded tiles in theme colours), Tinted (accent colour), Clear (see-through glass), Wallpaper (tiles cut from the current wallpaper), Original. Redrawn on theme, accent or wallpaper change. Captures of each style are in the README |
| 🟡 | Faster, lighter Windows UI (R11) | Native C# system-numbers reader replaces PowerShell/WMI queries; themed Settings tabs (the stock ones had an unreadable hover). Measured (preview): everyday desktop **97 MiB, 0.5% CPU** (R10: 103 MiB, 0.8%); Arena open **224 MiB** (R10: about 250) |
| 🟡 | Close buttons everywhere | Red close / amber hide lights on Arena, Files, Settings, Control Center; Esc; Launchpad ✕ |
| 🟡 | Custom wallpaper, full customisation | 5 BAKA wallpapers + any image/video/color; themes, accent, glass, motion, dock, pinned apps, widgets, menu bar |
| 🟡 | Useful things in the UI, no PowerShell commands | Launchpad, Control Center, Files, Arena, launcher; tools in BAKA Settings > System |
| ❌ | Tray icons (Discord, Steam) in full shell mode | Not done: needs a native tray host |
| ❌ | Fully native C# desktop | Not done: the launcher is native, the desktop UI is PowerShell + WPF |
| ❌ | Windows Settings / Store / Xbox in full shell mode | Not yet tested in the VM |

## Shipping

| | Request | Status / evidence |
|---|---|---|
| ✅ | Source, tests, README and About pages on GitHub | Both repos pushed; READMEs rewritten; repo descriptions updated. All 9 Windows test suites pass (UI smoke 25/25); browser self-check and 30/30 UI run pass |
| ✅ | Clean R11 ISO (icon styles, ad blocking, codecs, power plan, Baka Browser 1.5.0) | `Output/BAKA-Windows-Gaming-Edition-26H2-x64-CarbonShell-R11-20261028.iso`, 11,174,158,336 bytes, SHA-256 `5AF4F3F71A7761ED1B8810A64FF17CB73FB9CE93EA28C9C9F9CBFFDE4347B286`. Structural validation passed (Setup signature valid, Windows 11 Pro 26300.9711, Baka Browser 1.5.0 hash, new scripts staged) |
| 🔄 | Windows ISO as a GitHub download | The ISO is 11 GB of Microsoft Windows media: GitHub allows 2 GB per file, and Windows media is Microsoft's to distribute. The BAKA Windows release has the payload, checksums and build steps; uploading the ISO in parts needs your decision |
| 🔄 | Bootable USB | Writing a USB erases it, so it waits for you to confirm the exact drive |
| ❌ | Test R10/R11 in VMware | Blocked: the VMware encryption password for the test VM is no longer saved in Windows Credential Manager |
| ➖ | Games tested | Skipped here by your request; you test on your PC |
| ❌ | 100% complete | Not yet: VM proof for the 🟡 items, tray icons, native desktop |

## Score

12 of 41 verified (✅), 19 built and waiting for VM or PC proof (🟡), 3 waiting on you (🔄), 6 not done, blocked, or waiting on your PC test (❌), 1 skipped by request (➖).
