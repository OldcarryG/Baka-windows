# BAKA Windows: your requests checklist

Updated: 2026-10-29 (R14 and Baka Browser 1.6.2). "VM" means seen or measured on the R13 image installed in a Hyper-V VM (Generation 2, Secure Boot, virtual TPM 2.0, 4 vCPU, 6 GB). "PC" means an automated run on the development PC.

Legend: ✅ done and verified · 🟡 done, not fully verified · ❌ not done or not possible here · 🔄 waiting on you

## Desktop

| | Request | Status / evidence |
|---|---|---|
| ✅ | Replace the Windows taskbar, Start and File Explorer windows | VM: Windows taskbar hidden, BAKA menu bar and dock shown, Win key opens Launchpad, folders open in BAKA Files |
| ✅ | File Explorer only in the background | VM: explorer.exe runs, its taskbar is hidden; it is still needed for tray icons, notifications and file dialogs |
| ✅ | Nothing of the desktop runs on PowerShell | BakaDesktop.exe is compiled C# (.NET Framework 4.8). Setup scripts that run once at install time are still PowerShell |
| ✅ | Top bar must not cover close/minimize/maximize | AppBar edge reservation; VM: work area starts at 30 px (below the menu bar) and 72 px from the left (next to the 58 px dock) |
| ✅ | Search bar, accurate, lists all apps | Self-test: "notepad", "task man", "setings" (typo), "cmd" (program name), "wifi" (settings page) each give the right first result; every installed app listed (61 in the VM). Passed 4 of 4 runs in the VM |
| ✅ | No crashes | Supervisor restarts the desktop; after 3 crashes in 2 minutes the Windows taskbar comes back. No crash in any VM run |
| ✅ | A fresh icon for each app | 125 vector icons, one per app, drawn per theme (icon sheet in the README). Self-test checks no two apps share a drawing |
| ✅ | Dock as wide as its icons (bug found in R12 testing) | Fixed; VM: dock 58 px |
| ✅ | Window dragging works | VM, simulated mouse: Notepad, Calculator, Media Player, System Information and BAKA Files move by exactly the distance dragged |
| 🟡 | Window-move animation "feels weird" | BAKA windows switched from Acrylic (re-blurs every frame) to Mica; glass panels show a solid card while dragged. Smoothness itself can only be judged by you on a real PC |
| ✅ | BAKA close/minimize/maximize buttons on every app | VM: on Notepad, Calculator and Media Player the buttons appear, follow the window and minimize, maximize and close it. Not on apps running as administrator, dialogs (System Information) or fullscreen windows; hidden while gaming |
| ✅ | Tray icons | VM: the tray button shows the Windows tray icons and hides them again after about 12 s |
| ❌ | Media keys | Not testable in the VM: it has no sound device, so no playback session starts |

## Apps

| | Request | Status / evidence |
|---|---|---|
| 🟡 | Remove Microsoft Edge | VM: Edge absent in every R13 install; in R12 Windows put it back once, so not guaranteed |
| 🟡 | All Store apps install and work | VM: Store opens; WhatsApp, Microsoft To Do, Spotify install and start. Netflix fails: it needs Edge as a component (0x80073D31). Keeping Edge would fix it; your decision |
| ✅ | Remove Internet Explorer, legacy Media Player and other useless apps | VM: legacy Windows Media Player and IE removed; 32 Store apps vs 50 on stock |
| ✅ | Keep WebView2, Microsoft Store and one media player | VM: all three present |

## Privacy, ads, gaming

| | Request | Status / evidence |
|---|---|---|
| ✅ | Ad and tracker blocking with a 100% score | VM: 131 of 131 d3ward test domains blocked (stock: 2 of 131). Online tests needing a person in a browser were not run |
| ✅ | Privacy and tracking | VM: 12 of 12 privacy checks (stock: 0 of 12); 0 of 16 telemetry tasks and 0 of 6 telemetry services running (stock: 14 and 5). Windows Pro still sends required diagnostic data |
| 🟡 | Gaming tweaks and power plan | VM: BAKA Gaming plan active. FPS not measurable without a GPU |
| ✅ | 4K video wallpaper without problems | PC (RTX 5060): 4K H.264, VP9 and AV1 play and loop at 0 to 2% CPU; HEVC needs the HEVC extension (BAKA installs it). VM (no GPU): H.264 and HEVC 4K play; pauses when covered, closed in games, back after. See R14 notes |
| ✅ | Low latency | Keyboard hook on its own thread (was: up to 25 to 42 ms per key when BAKA was busy, now 0.75 ms, same as no hook); removed completely while gaming |
| ✅ | Delete old ISOs and useless files | Old ISOs R10 to R13, old build folders, orphaned VM disks, old acceptance copies, old browser installers, old logs and scripts removed; about 400 GB freed |
| ✅ | AI prompt to tune BAKA for your hardware | [docs/OPTIMIZE_WITH_AI.md](OPTIMIZE_WITH_AI.md) |
| ❌ | Proven FPS gain | Needs a real PC with a GPU |
| ✅ | BAKA adds no useless load while gaming | VM, Gaming mode: 2242 MB in use vs stock 2295, 130 vs 138 processes; BAKA Desktop 0.03% CPU, 39 MB. Score 101.9 (100 = stock) |
| 🟡 | Less idle memory and CPU, fast boot | Desktop mode score 91.8: memory +59 MB vs stock, boot event 26.5 s vs 29.3 s, but idle CPU 13.5% vs 3.6% (not BAKA Desktop itself, cause not found) |

## Baka Browser

| | Request | Status / evidence |
|---|---|---|
| ✅ | New-tab background video does not play | Fixed in 1.6.2; UI test records a .webm and an .mp4 clip, sets each as background, checks it plays (readyState 4, time advancing) |
| ✅ | Upload error "Could not find a part of the path …\baka-browser\home-assets\…" | Fixed in 1.6.1 (the folder is created first); new self-check passes. The page-upload test (photo + 40 MB video by form, fetch and chunked XHR) also passes |
| ✅ | Tab menu, drag tabs, mute, reopen closed tabs | 1.6.0; UI test passes |
| ✅ | Preinstalled and default in BAKA | VM: Baka Browser installed (1.6.1 in the final ISO) |

## Testing and release

| | Request | Status / evidence |
|---|---|---|
| ✅ | Test in a VM, benchmark against normal Windows, give a score | Hyper-V, identical VMs, 2 rounds; [BAKA_VS_WINDOWS.md](BAKA_VS_WINDOWS.md#measured-in-virtual-machines) |
| ✅ | Test every feature several times | Desktop self-test: 4 of 4 in the VM, 10 of 10 on the PC after the click fix; 8 test suites pass; browser self-check and 40-step UI test pass |
| ✅ | List of differences and browser changes | [BAKA_VS_WINDOWS.md](BAKA_VS_WINDOWS.md) |
| ✅ | R13 release | Release `r13-20261029`, Baka Browser `v1.6.2` |
| ✅ | Final release, GitHub pages updated, useless files removed | Release `r12-20261028`; README, docs and screenshots replaced; obsolete docs, VMware evidence, old screenshots and PowerShell desktop removed |
| 🔄 | ISO as a GitHub download | 11 GB of Microsoft media: GitHub allows 2 GB per file. Build it with the scripts, or I write it to your USB stick |
| 🔄 | Bootable USB | Disk 1 is erased and ready; writing it needs your go-ahead |
| 🔄 | Old GitHub releases (r7 to r11) | Still listed; deleting a release cannot be undone, so it needs your go-ahead |
