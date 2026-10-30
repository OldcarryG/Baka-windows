# BAKA Windows Gaming Edition: decisions

Updated: 2026-10-30 (BAKA Desktop 12.27.1)

## Releases (2026-10-30)

- **No more new ISOs.** R15 is the last ISO for now. Every change since R15 is inside BakaDesktop.exe, so BAKA Windows is updated through BAKA Desktop releases on GitHub: a zip with BakaDesktop.exe, its SHA-256 and an installer (`Tools/Install-BakaDesktop.cmd`, `Tools/Update-BakaDesktop.ps1`) that replaces only `C:\ProgramData\BAKA\Desktop\BakaDesktop.exe`, keeps the previous file for a rollback and pre-compiles the new one with NGen. A new ISO is built only when Microsoft releases a Windows update worth building into the image (a new build or a feature that BAKA should ship with). Windows' own monthly updates arrive through Windows Update as on any PC.
- BAKA Desktop releases are tagged `desktop-<version>`; ISO releases keep the `r<number>-<date>` tags. Changes are listed in `docs/CHANGELOG_DESKTOP.md`.

## Base image

- Official Windows 11 Pro x64 en-US, build 10.0.26300.9457 (SHA-256 `BD4307DF32BC8AF33B39CCECB1174AEB345386630F89A2B86C7A4E36B55EA650`), serviced with KB5127648 to 10.0.26300.9711.
- TPM 2.0 and Secure Boot are required, as on stock Windows. Nothing is bypassed.
- Disk selection in Setup stays interactive (the answer file has no `windowsPE` pass), so the image never erases a disk on its own.

## Desktop (R12)

- **BAKA Desktop is a compiled C#/WPF app on .NET Framework 4.8** (`Shell/BakaDesktop`). .NET Framework 4.8 ships with Windows, so nothing extra is installed. The PowerShell desktop of R1 to R11 was removed. The user asked that none of the desktop runs on PowerShell.
- **Explorer stays the Windows shell** and keeps running in the background, because tray icons, notifications, file dialogs and Windows Search depend on it. BAKA hides the taskbar and desktop icons, opens folders in BAKA Files (Win+E and the `Directory`/`Drive` open verb for the current user), and opens Launchpad with the Windows key. The old Winlogon shell replacement (BakaShell.exe) is undone for users who had it.
- BAKA Desktop starts from `HKLM\...\Run`. A supervisor process restarts the UI if it crashes; after three crashes in two minutes it gives back the Windows taskbar and desktop and shows a message.
- The menu bar and dock reserve their screen edge through the AppBar API, the same way the taskbar does, so maximized windows never sit under them. A fullscreen window covers them.
- Large windows (Files, Settings, Arena) use the DWM backdrop, so moving them is as smooth as any Windows window. Small panels use a blurred layered window, and the blur pauses while they are dragged.
- Icons: 125 vector icons drawn for BAKA (one per app, families get badges). The theme decides the tile shape and colours. An app without a BAKA icon shows its own icon on a theme tile. "Original" shows icons as the apps ship them.
- A click in BAKA surfaces is a press and a release on the same element (R12 fix): a bare release, for example from the click that opened the full-screen Launchpad, no longer starts the app under the cursor.
- **BAKA buttons on other apps' windows (R13)** are a small BAKA window placed over each window's own minimize, maximize and close buttons. Nothing is loaded into other apps. DLL injection (the way Windhawk-style mods restyle title bars) was rejected because anti-cheat and antivirus software treat it as tampering. The position comes from Windows (`DWMWA_CAPTION_BUTTON_BOUNDS`, relative to the window rectangle) and is used only when the window's own hit test reports its close button there. A click sends the window the same `WM_SYSCOMMAND` its own button would. Elevated windows (unless BAKA is elevated too), tool windows, dialogs and owned windows keep their own buttons. While a game runs, the overlays are hidden and the window scan stops. Settings > Windows turns it off.
- **Video wallpaper (R14)** uses MFPlay (Media Foundation) drawing into a native child window of the desktop's WorkerW, instead of WPF's MediaElement. MediaElement copies every decoded frame into WPF's composition, which costs CPU at 4K; MFPlay presents GPU-decoded frames directly through the Enhanced Video Renderer. MFPlay is documented by Microsoft as legacy (IMFMediaEngine is the successor), but it is still part of Windows 11 26H2 and needs no extra runtime; switching to IMFMediaEngine would need a D3D11 swap chain and is left for later. The player thread runs without MMCSS priority so it never competes with the app in front. The wallpaper pauses when any maximized or fullscreen window covers the primary monitor (not only the foreground one), on battery and when locked, and is shut down in games.
- **Keyboard hook (R14)** is uninstalled while a game runs and reinstalled after, because a low-level keyboard hook delays every key press of every app until BAKA's thread answers. It runs on its own time-critical thread with an empty message loop, not on the UI thread: on the UI thread a busy frame (layout, rendering) held key presses back, which showed as 0.7 to 1.1 ms at the 99th percentile in Desktop mode. With "Windows key opens Launchpad" off, no hook is installed at all. BAKA's window-event hooks (BAKA window buttons) are also removed during games.
- **Window moves (R13)**: BAKA Files, Settings and Arena use the Mica backdrop instead of Acrylic, because Acrylic re-blurs the screen behind the window on every frame of a drag. BAKA's glass panels show a solid card while they are dragged instead of turning transparent.

## Desktop (BAKA Desktop 12.27)

- **FPS counter** reads Windows' graphics event log (ETW: DXGI present events, Direct3D 9 present events, and the kernel's DxgKrnl present events as a fallback for Vulkan and OpenGL), with Windows' event-ID filter so only one event per frame reaches BAKA. Injecting into games (the way RTSS works) was rejected because of anti-cheat. Reading these events needs membership in the built-in Performance Log Users group; BAKA asks once (Settings > Focus & games, an administrator prompt) instead of running an elevated helper all the time.
- **GPU temperature, power and video memory** come from NVIDIA's NVML library that ships with the driver. Other GPUs show the load from Windows' GPU performance counters only.
- **Windows' duplicate notification banners** are turned off per app (`HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\<app>\ShowBanner=0`) while BAKA shows its own pop-ups; the previous values are saved and restored. Windows' global Do Not Disturb has no public API, and turning toasts off globally would also empty Windows' notification list, which BAKA reads.

## Apps

- Microsoft Edge: removed as an app package, uninstalled with its own setup and blocked by the Edge Update policy `Install{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}=0`, WebView2 kept. On 26300.9711 the uninstaller returns exit code 60 and Windows installed Edge 156 again in one of two VM tests, so this is not reliable and is documented as not done.
- Removed: Internet Explorer, the legacy Windows Media Player, Movies & TV, Clipchamp, WordPad, Steps Recorder, Math Input Panel, Fax and Scan, PowerShell ISE, Copilot, Maps, People, Family and the consumer apps listed in `Config/Debloat.json`.
- Kept: Microsoft Store, Media Player (the new one), Photos, Paint, Notepad, Calculator, Snipping Tool, Terminal, Windows Security, App Installer, Xbox sign-in, codecs.
- Baka Browser (pinned by SHA-256 in `Config/Applications.json`) installs per user at first sign-in and becomes the default browser.

## Account

- One local administrator, `BAKA`, with no password, signs in automatically. Anyone with physical access can use the PC. Setting a password in Windows brings the sign-in screen back; BAKA never stores a password.
- The account is created by the answer file's `oobeSystem` `UserAccounts` (empty password). Hyper-V testing of R12 showed that an administrator created earlier by a script does not make OOBE skip its "Who's going to use this device?" page, so the R11 script approach was replaced. After OOBE a startup task makes sure the password is empty and never expires, turns on automatic sign-in and restarts once.

## Privacy and ads

- Telemetry upload services and tasks off; Copilot, Recall, advertising ID, tips, suggestions, Start web search, activity history and Spotlight off. Every changed value is backed up and "Restore BAKA System Tuning" puts it back. Security, Update, Xbox sign-in, audio and network services are on a protected list.
- Ad blocking for every app: encrypted AdGuard DNS (DNS over HTTPS, plain DNS allowed as fallback so a network that blocks DoH still works) plus a BAKA section in the hosts file built from `Config/BlockedDomains.txt`. Microsoft domains are left out of the hosts list so Defender does not report it as a hijack. `BakaDesktop.exe --adblock off` (or BAKA Settings) restores the previous DNS.
- Windows Pro keeps "required" diagnostic data. BAKA does not claim zero telemetry.
- R13 adds: the Inventory and Compatibility Appraisal, Windows Health and Optimized Experiences, Windows AI Components Host and Distributed Link Tracking services disabled; the MareBackup, feature-usage reporting (4 tasks) and SQM tasks disabled; the `DisableInventory`, `AITEnable=0` and `DisableWindowsConsumerFeatures` policies set (Microsoft documents the last one for Enterprise and Education; Pro may ignore it); Edge startup boost and background mode off. `PcaPatchDbTask` and `SdbinstMergeDbTask` stay on: they update the app-compatibility database and send nothing. A service or task that Windows refuses to change is skipped and logged instead of stopping the whole setup.
- The privacy benchmark counts 12 checks. The scheduled-task check counts 16 named telemetry tasks; until R12 it counted every task in two folders, which included the two compatibility-database tasks.

## Gaming

- Desktop, Competitive Gaming and Benchmark are reversible profiles. A detected game switches to Competitive Gaming and back when it closes.
- BAKA Gaming power plan on Ultimate Performance; laptops keep Balanced on battery.
- No unverified global affinity, MSI, interrupt, storage or polling-rate changes.
- No FPS gain is claimed: games were not measured (the test VMs have no GPU).

## Testing

- VM tests use Hyper-V (Generation 2, Secure Boot, virtual TPM 2.0), not VMware: VMware Workstation's virtual TPM needs VM encryption, which its command-line tool cannot set up, and Windows 11 refuses to install without a TPM. Hyper-V also allows PowerShell Direct for automated checks.
- Test-only install media add an automatic disk wipe for the empty VM disk and a test administrator for PowerShell Direct. Published media do neither.
- The ISO contains Microsoft's Windows media and is about 11 GB, so it is not attached to GitHub releases. Releases list the SHA-256 and how to build the ISO.
