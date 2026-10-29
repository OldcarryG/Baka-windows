# BAKA Windows R13 (2026-10-29)

Windows 11 Pro 26H2 x64 (build 26300.9711) with BAKA Desktop, gaming and privacy tuning, and Baka Browser 1.6.2.

ISO: `BAKA-Windows-Gaming-Edition-26H2-x64-BakaDesktop-R13-20261029.iso`, 11,174,205,440 bytes, SHA-256 `86FAA93AE886C906C4B6132B6D425F9ED92FA5398546650A9AC000E06E87F262`. Structural validation passed (Microsoft Setup signature valid, Windows 11 Pro 26300.9711, pinned Baka Browser 1.6.2 hash, BAKA payload present).

## What changed since R12

### BAKA buttons on every app window

- Other apps' minimize, maximize and close buttons are covered by BAKA's amber, green and red buttons (Windows order: minimize, maximize, close). Hovering shows the symbols; a click does what the app's own button does.
- Nothing is loaded into other apps, so games with anti-cheat are not affected. BAKA places a small window of its own over the buttons, at the position Windows reports, and only where the app itself confirms its close button is there.
- Works on classic apps (Notepad) and on Store apps that draw their own title bar (Calculator, Media Player). Windows of apps running as administrator keep their own buttons, because Windows does not let a normal app send them clicks. Dialogs (including System Information, which is built as a dialog), tool windows and fullscreen windows keep theirs too.
- While a game runs the BAKA buttons are hidden and the window scan stops, so nothing of this runs during a game. Settings > Windows > "BAKA buttons on every window" turns it off.

### Moving windows

- BAKA Files, Settings and Arena use the Mica backdrop instead of Acrylic. Acrylic blurs whatever is behind the window again on every frame of a drag, which made moving these windows look smeared and stutter. They now move like any Windows 11 app.
- BAKA's glass panels (widgets, Control Center) show a solid card while dragged instead of flickering to transparent.

### Privacy

- Disabled: Inventory and Compatibility Appraisal service, Windows Health and Optimized Experiences, Windows AI Components Host, Distributed Link Tracking; the MareBackup, feature-usage reporting (4 tasks) and SQM tasks.
- Policies: app inventory collection off, application telemetry off, "consumer features" (suggested apps) off, Edge startup boost and background mode off.
- Every change is backed up and undone by "Restore BAKA System Tuning". Windows Pro still sends required diagnostic data.

### Benchmark

- Each run measures stock Windows, BAKA in Desktop mode, and BAKA in Gaming mode (`BakaDesktop.exe --profile gaming`, the same as Arena's Gaming card). It also records which processes used the CPU and how much CPU and memory BAKA Desktop itself uses.

### Baka Browser 1.6.2

- A video picked as the new-tab background (Settings > Appearance > "Choose image or video…") now plays. WebView2's folder mapping did not serve video requests; the browser now serves the file itself, with seeking support. Its UI test records a .webm and an .mp4 clip, sets each as the background and checks that it plays ([release](https://github.com/OldcarryG/Baka-browser/releases/tag/v1.6.2)).

### Tools

- `BakaDesktop.exe --profile gaming|desktop` switches the profile from the command line, and `--tray` shows the Windows tray icons for a few seconds.

## Bugs found by the R13 tests and fixed in this release

| Bug | Found by | Fix |
|---|---|---|
| BAKA buttons never appeared on other apps. Their position was computed from the visible window frame, but Windows reports the button area relative to the full window rectangle, so BAKA asked the app about a point 7 px to the right of its close button, got "right border" and gave up. | VM interaction test (no BAKA window on Notepad), then a probe on the PC (hit test 11 = right border instead of 20 = close) | Position taken from the window rectangle. A self-test check now opens Notepad and fails if no BAKA buttons sit over its buttons. |
| No BAKA buttons on Store apps (Calculator, Media Player). Windows reports a zero-wide button area for apps that draw their own title bar. | VM interaction test | For those apps BAKA uses the standard Windows button layout, and only if the app's own hit test reports minimize, maximize and close at those three spots. Self-test check with Calculator added. |
| On System Information the BAKA minimize and close buttons did nothing. | VM interaction test | Dialog-class windows keep their own buttons. |
| A service or task that Windows refuses to change stopped the rest of the system tuning. | Code review while adding the R13 services | Refused changes are skipped and logged; everything else is still applied and backed up. |
| The benchmark's own test helper failed silently (a PowerShell name clash), so the first interaction run reported no results. | VM interaction test | Fixed in the test scripts. |

## Tests

| Test | Result |
|---|---|
| Install of the final ISO in a Hyper-V VM (Gen 2, Secure Boot, vTPM) | Passed: no account page, BAKA signs in automatically, BAKA desktop up about 9 minutes after Setup starts. Earlier R13 candidates installed the same way 3 times |
| Desktop state in the installed VM (`--status`) | Taskbar hidden, menu bar and dock present, dock 58 px, work area below the menu bar and next to the dock, folders open in BAKA Files, ad-block DNS on, **Edge not installed**, WebView2 and Baka Browser installed |
| BAKA Desktop self-test in the installed VM | 50 of 50, including BAKA buttons over Notepad and over Calculator |
| BAKA Desktop self-test on the development PC | 50 of 50, twice (Calculator check skipped there: Calculator is not installed on that PC) |
| Source test suites (project configuration 96 checks, desktop configuration, system tuning, gaming profiles, game detection, release-pipeline guards, dock contrast, BAKA Desktop) | All passed |
| Interaction test (simulated mouse and keyboard in the user's session) | Notepad, Calculator and Media Player: BAKA buttons present, follow a drag, minimize, maximize and close work. Dragging Notepad, Calculator, Media Player, System Information and BAKA Files moves each by exactly 240×140 or −180×90 px. Tray button shows the tray icons, then hides them. System Information keeps its own buttons (by design). Media keys: not testable, no sound device in the VM |
| Store apps (winget, msstore source, in the user's session) | Microsoft Store opens. WhatsApp, Microsoft To Do and Spotify install and start. Netflix does not install: it needs Edge as a component (0x80073D31) |
| Benchmark vs stock Windows (10 minutes settled) | Score 91.8 in Desktop mode, 101.9 in Gaming mode (100 = stock). [Details](BAKA_VS_WINDOWS.md#measured-in-virtual-machines) |
| Ad and tracker blocking (d3ward, 131 domains) | BAKA 131/131 (100%), stock 2/131 |
| Privacy checks (12) | BAKA 12/12, stock 0/12 |
| Baka Browser 1.6.2 self-check and UI test (extensions, uploads, 4K video, background video .webm and .mp4, tabs, settings) | All passed |

## Not done or not verified

- **Idle CPU** is higher than stock (13.5% in Desktop mode, 5.0% in Gaming mode, stock 3.6%). BAKA Desktop itself uses 0.03%; the cause was not found.
- **Media keys**: not testable in the VM, which has no sound device.
- **Netflix and other Store apps built on Edge** do not install while Edge is removed. Keeping Edge would fix them; that is your call.
- **Edge removal**: held in every R13 install, but Windows put Edge back once in R12, so it is not guaranteed.
- **Game FPS, frame times, input latency**: not measurable in a VM without a GPU.
- **BAKA buttons on apps running as administrator** are not possible without BAKA itself running as administrator; those windows keep Windows' buttons.
