# BAKA Windows: your requests checklist

Updated: 2026-10-28 (R12 and Baka Browser 1.6.1). "VM" means seen or measured on the R12 image installed in a Hyper-V VM (Generation 2, Secure Boot, virtual TPM 2.0, 4 vCPU, 6 GB), two fresh installs. "PC" means an automated run on the development PC.

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
| 🟡 | Smooth window dragging | Big windows use the Windows backdrop; not dragged by hand in the VM |

## Apps

| | Request | Status / evidence |
|---|---|---|
| ❌ | Remove Microsoft Edge | Edge's uninstaller refuses (exit code 60) and Windows put Edge 156 back in the final VM test, despite the Edge Update policy. Not reliable on this Windows build |
| ✅ | Remove Internet Explorer, legacy Media Player and other useless apps | VM: legacy Windows Media Player and IE removed; 32 Store apps vs 50 on stock |
| ✅ | Keep WebView2, Microsoft Store and one media player | VM: all three present |

## Privacy, ads, gaming

| | Request | Status / evidence |
|---|---|---|
| ✅ | Ad and tracker blocking with a 100% score | VM: 131 of 131 d3ward test domains blocked (stock: 2 of 131). Online tests needing a person in a browser were not run |
| 🟡 | Privacy | VM: 8 of 10 privacy checks (stock: 0 of 10); "consumer features" policy and 3 telemetry tasks still on |
| 🟡 | Gaming tweaks and power plan | VM: BAKA Gaming plan active. FPS not measurable without a GPU |
| ❌ | Proven FPS gain | Needs a real PC with a GPU |
| ❌ | Faster than stock Windows at idle | VM score 80.6 (round 2) and 90.7 (round 1), 100 = stock. CPU/memory speed equal, BAKA uses more memory and idle CPU |

## Baka Browser

| | Request | Status / evidence |
|---|---|---|
| ✅ | Upload error "Could not find a part of the path …\baka-browser\home-assets\…" | Fixed in 1.6.1 (the folder is created first); new self-check passes. The page-upload test (photo + 40 MB video by form, fetch and chunked XHR) also passes |
| ✅ | Tab menu, drag tabs, mute, reopen closed tabs | 1.6.0; UI test passes |
| ✅ | Preinstalled and default in BAKA | VM: Baka Browser installed (1.6.1 in the final ISO) |

## Testing and release

| | Request | Status / evidence |
|---|---|---|
| ✅ | Test in a VM, benchmark against normal Windows, give a score | Hyper-V, identical VMs, 2 rounds; [BAKA_VS_WINDOWS.md](BAKA_VS_WINDOWS.md#measured-in-virtual-machines) |
| ✅ | Test every feature several times | Desktop self-test: 4 of 4 in the VM, 10 of 10 on the PC after the click fix; 8 test suites pass; browser self-check and 40-step UI test pass |
| ✅ | List of differences and browser changes | [BAKA_VS_WINDOWS.md](BAKA_VS_WINDOWS.md) |
| ✅ | Final release, GitHub pages updated, useless files removed | Release `r12-20261028`; README, docs and screenshots replaced; obsolete docs, VMware evidence, old screenshots and PowerShell desktop removed |
| 🔄 | ISO as a GitHub download | 11 GB of Microsoft media: GitHub allows 2 GB per file. Build it with the scripts, or I write it to your USB stick |
| 🔄 | Bootable USB | Disk 1 is erased and ready; writing it needs your go-ahead |
| 🔄 | Old GitHub releases (r7 to r11) | Still listed; deleting a release cannot be undone, so it needs your go-ahead |
