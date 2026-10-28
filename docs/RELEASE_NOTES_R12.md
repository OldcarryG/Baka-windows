# BAKA Windows R12 (2026-10-28)

Windows 11 Pro 26H2 x64 (build 26300.9711) with BAKA Desktop, gaming and privacy tuning, and Baka Browser 1.6.1.

ISO: `BAKA-Windows-Gaming-Edition-26H2-x64-BakaDesktop-R12-Final-20261028.iso`, 11,174,187,008 bytes, SHA-256 `AEAB969431C177F82BB5740D3942854C2C80074100DCCB30A1D11A8BE6BE58C5`. Structural validation passed (Microsoft Setup signature valid, Windows 11 Pro 26300.9711, pinned Baka Browser 1.6.1 hash, BAKA payload present).

## What changed since R11

### Desktop: no PowerShell, Explorer only in the background

- The whole desktop was rewritten as one compiled app, `BakaDesktop.exe` (C#/WPF on .NET Framework 4.8, 381 KB). The PowerShell desktop scripts and modules of R1 to R11 were deleted.
- It replaces the Windows taskbar, Start menu, desktop icons and File Explorer windows. Explorer keeps running hidden for tray icons, notifications and file dialogs. Win+E, the Windows key, Win+S and folders opened by any app go to BAKA.
- A supervisor restarts the desktop after a crash; three crashes in two minutes bring the Windows taskbar back with a message, so the PC is never left without a desktop.
- **Top bar no longer covers window buttons**: the menu bar and dock reserve their screen edge like the taskbar does, so a maximized window stops below the bar. A fullscreen video or game covers them.
- **Search**: exact, prefix, word-start, initials ("vsc"), letters in order and one-typo matches ("setings", "discrod"), program names ("cmd", "regedit"), Windows settings pages ("wifi") and files from the Windows Search index. Every installed app is listed.
- Smooth window dragging: big windows use the Windows backdrop instead of a re-rendered blur.

### Icons

- 125 new vector icons, one per app (Steam, Discord, Spotify, browsers, Office, Git tools, Python, NVIDIA, AMD, Riot, VALORANT, Roblox, Windows tools and more). App families get badges (Git Bash vs Git GUI, PowerShell vs PowerShell x86). The theme decides the tile: metal squircles, neon hexagons, glass bubbles, candy keycaps. Apps installed later show their own icon on the theme tile.

### Apps removed

- Internet Explorer, legacy Windows Media Player, Movies & TV, WordPad, Steps Recorder, Math Input Panel, Fax and Scan, PowerShell ISE, Copilot, Maps, People, Family. Microsoft Store, WebView2 and the new Media Player stay.
- Microsoft Edge: BAKA removes its app package, runs its uninstaller and sets the Edge Update policy against reinstalling it. **This does not work reliably yet**: the uninstaller refused (exit code 60) and in the final VM test Windows installed Edge 156 again after first sign-in.

### Ad blocking

- Ported to C# (`BakaDesktop.exe --adblock on|off`). Besides AdGuard DNS, a BAKA section in the hosts file blocks 188 ad, analytics and error-tracking domains (`Config/BlockedDomains.txt`). AdGuard DNS alone blocked 81.7% (107 of 131) of the public d3ward ad-block test domains on the development PC.

### Baka Browser 1.6.1

- Tab right-click menu, drag tabs to reorder or into a new window, mute button, reopen closed tabs, Ctrl+1 to Ctrl+9. Full list: [docs/BAKA_VS_WINDOWS.md](BAKA_VS_WINDOWS.md#baka-browser-compared-with-edge-and-what-changed-in-it) and the [browser release](https://github.com/OldcarryG/Baka-browser/releases/tag/v1.6.1).

## Bugs found by the R12 tests and fixed in this release

| Bug | Found by | Fix |
|---|---|---|
| Setup stopped at the "Who's going to use this device?" page, so the PC did not boot straight to the desktop. The R11 script that created the BAKA account in the specialize pass failed (exit code 1), and an administrator created by a script does not make Windows skip that page anyway. | Installing in a Hyper-V VM | The answer file creates the passwordless BAKA account itself (`oobeSystem` UserAccounts). After OOBE a startup task checks the password is empty, turns on automatic sign-in and restarts once. Verified in the VM: no account page, BAKA signed in automatically, BAKA desktop running. |
| The dock was 136 px wide with its icons floating in the middle, and reserved 150 px of the screen next to it. | Screenshot of the installed VM after a restart, then a new self-test check ("dock is only as wide as its icons") that failed at 136 px on the PC too | Windows' minimum window width (136 px) is lowered to 1 px for BAKA's small panels, and the dock asks Windows for it again once. The check now reports 58 px. |
| Baka Browser: "Choose image or video…" for the new-tab background failed with "Could not find a part of the path …\baka-browser\home-assets\…". | Your report | Baka Browser 1.6.1 creates the folder first; a self-check covers it. |
| A mouse-button release without a press could start an app: the full-screen Launchpad opened under the cursor, a stray release landed on a tile, the app started and the Launchpad closed. The self-test failed this way in 3 of 17 runs. | BAKA Desktop self-test, run repeatedly | Every clickable BAKA tile (Launchpad, search results, dock, menu bar, Control Center, Arena games and profiles) now needs the press and the release on the same element. 10 of 10 self-test runs passed afterwards. |

## Tests

| Test | Result |
|---|---|
| Install of the final ISO in a Hyper-V VM (Gen 2, Secure Boot, vTPM) | Passed twice: no account page, BAKA signs in automatically, BAKA desktop up about 8 minutes after Setup starts |
| Desktop state in the installed VM (`--status`) | Taskbar hidden, menu bar and dock present, dock 58 px, work area below the menu bar and next to the dock, folders open in BAKA Files, ad-block DNS on, WebView2 and Baka Browser installed. Edge was present again (see above) |
| BAKA Desktop self-test inside the installed VM (every surface, search, Files, Settings, Arena, widgets, profiles, themes, icons) | Passed, 4 of 4 runs over two installs |
| BAKA Desktop self-test on the development PC | 10 of 10 after the click fix; dock check 58 px |
| Source test suites (project configuration 98 checks, desktop configuration, system tuning, gaming profiles, game detection, release-pipeline guards, dock contrast, BAKA Desktop) | All 8 passed |
| Benchmark vs stock Windows (same VM size, 2 rounds) | Score 80.6 and 90.7 (100 = stock). Same CPU and memory speed, faster disk writes, more idle memory and CPU. [Details](BAKA_VS_WINDOWS.md#measured-in-virtual-machines) |
| Ad and tracker blocking (d3ward, 131 domains) | BAKA 131/131 (100%), stock 2/131 |
| Privacy checks (10) | BAKA 8/10, stock 0/10 |
| Baka Browser 1.6.1 self-check and 40-step UI test (extensions, uploads, 4K video, tabs, settings) | All passed |

## Not done or not verified

- **Microsoft Edge removal** does not hold on this Windows build (see above).
- **Game FPS, frame times, input latency**: not measurable in a VM without a GPU.
- **Faster than stock at idle**: not achieved; BAKA uses more memory and idle CPU in the VM.
- **Privacy**: 2 of 10 checks still open (consumer-features policy, 3 telemetry tasks).
- **Online ad/privacy test sites** that need a person in a browser (Cover Your Tracks) were not run; the d3ward domain list was checked through Windows instead.
- **Window dragging by hand, tray icons through the Control Center, media keys**: not tried by a person on an installed system.
- **VMware**: not used. VMware Workstation's virtual TPM needs VM encryption, which its command-line tool cannot set up, so Windows 11 cannot be installed there without bypassing its checks. Hyper-V was used instead.
