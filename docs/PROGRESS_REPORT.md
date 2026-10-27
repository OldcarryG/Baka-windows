# BAKA Windows Gaming Edition — progress report

Updated: 2026-10-27

## Current result

A distinct BAKA Liquid UI-R2 candidate has been built in the user-authorized Windows 11 technician VM and passed structural ISO validation. The original ISO and the earlier 2026-10-16 candidate remain unchanged. This is **not a fully acceptance-tested release**: a new disposable VMware VM reached a genuine Windows 11 Setup screen, then stopped because the VM lacked TPM 2.0; the preserved AB candidate/source comparison still ends in a shared EFI timeout. Installation/OOBE, Windows SIM, installed desktop behavior, security and update-restoration checks, game testing, and physical performance measurements remain outstanding.

## R4 Liquid Shell source — 2026-10-27

Implemented in source (no ISO rebuilt yet):

- Answer file: passwordless local `BAKA` administrator with automatic sign-in, OOBE account/privacy/Microsoft-account screens hidden, computer name `BAKA-PC`, en-US locale. No `windowsPE` pass, so disk selection stays interactive. First-logon setup keeps auto sign-in permanent and disables sign-in after sleep. `Config/AccountSetup.json` documents the physical-access trade-off.
- Debloat: 19 exact packages, protected-pattern list extended (Xbox identity/TCUI, Security, App Installer, codecs, Store purchase). The approved list is also removed online for all users at first logon.
- `Modules/SystemTuning.psm1` + `Config/SystemTuning.json`: reversible service start types (DiagTrack, dmwappushservice, MapsBroker, RetailDemo, Fax, WpcMonSvc disabled; lfsvc, WerSvc manual), 13 telemetry/feedback scheduled tasks disabled, protected-service refusal list, and backup/restore. `Restore BAKA System Tuning` shortcut restores system and per-user values.
- `Config/PrivacySettings.json`: 21 device and 25 user values (Copilot, Recall, activity history, web search, Widgets feed, tips, suggestions, promoted apps, Spotlight, advertising ID, Delivery Optimization P2P, feedback).
- Baka Browser: silent Velopack install at first logon, Default Programs registration (`BakaBrowserHTML`), and `Config/DefaultAssociations.xml` applied through the Windows default-associations policy. It is also the first pinned dock app.
- Companion R4: Start button, open-window strip, reversible native-taskbar auto-hide, image/video/color wallpaper with video behind the desktop icons and pause-in-games, custom dock icons, settings upgrade for older files.
- Fixed a first-logon race: the per-user Active Setup step is now registered during `specialize`, and first logon starts the companion directly, so the BAKA desktop appears on the very first sign-in instead of the second.
- Tests: new `Tests/Test-SystemTuning.ps1` (in-memory apply/idempotence/restore/protected-service refusal); new configuration-upgrade and wallpaper/icon validation checks; new project preflight checks for autologon, browser default, tuning restore, protected packages, and R4 staging; preview smoke stage `wallpaper-and-taskbar`.

Source verification on the Windows 10 development host (2026-10-27):

| Check | Result |
| --- | --- |
| Full project preflight (with local media, MSU, and browser installer) | Passed, 99/99 |
| Repository-safe preflight | Passed, 93 passed / 3 explicitly skipped |
| WPF preview smoke (includes new `wallpaper-and-taskbar` stage) | Passed, 18/18 stages, exit 0 |
| `Test-SystemTuning.ps1` (in-memory apply, idempotence, exact restore, protected-service refusal) | Passed, 4/4 |
| `Test-DesktopConfiguration.ps1` (adds settings upgrade and wallpaper/icon validation) | Passed, 6/6 |
| Contrast, game detection, profiles, monitoring, release guards | Passed (contrast 20/20 in a fresh STA process) |

These are source-level results. Preview mode simulates wallpaper and taskbar changes, so video wallpaper, taskbar auto-hide, autologon, online debloat, service/task tuning, and the browser default have **not** been observed on an installed Windows 11 system. No R4 ISO has been built yet.

VMware state found this session: the disposable acceptance VM now has a vTPM (partial VMware encryption) and an NVMe disk with about 30 GB written. Its log shows Windows Boot Manager booting from disk through several Setup restarts on 2026-10-27, so the R2 image appears to have installed. No desktop screenshot or OOBE result has been captured yet, so installation success is not claimed.

## Source reliability remediation — 2026-10-27

The live BAKA Liquid companion received the R3 Arena/Files redesign plus a reliability pass. Action buttons now render their supplied Windows icon glyphs; manual profiles stop automatic process detection; a not-yet-created Quick Panel is safe during profile polling; malformed settings imports are contained and reported; profile UI changes attempt rollback to the previous backend/UI state; BAKA Files reads a real workspace; and the smoke timer is initialized before cleanup handlers run. The BAKA source smoke passed 15/15 stages after these changes.

The build-host preflight diagnostic was also hardened to fall back from a missing `ProgramFiles(x86)` environment variable and to report absent WSIM paths instead of throwing a null-path error. On this host it now correctly reports Windows 10 Pro 19045 with no OSCDIMG, WinPE add-on, or WSIM, so ISO rebuilding remains blocked until the preserved Windows 11 technician VM is available.

An actual host preview sample (15 samples, two-second interval, five-second startup warm-up) averaged 0.494% CPU and 212.76 MiB working set, with maxima of 0.824% CPU and 215.38 MiB. The CPU result met the initial target in this host sample; the memory result did not meet 150 MiB. This was a Windows 10 development preview and does not establish installed Windows 11 resource use. The repeatable procedure is `Scripts/Diagnostics/Measure-CompanionPreview.ps1`.

Primary review artifact:

- `Output/BAKA-Windows-Gaming-Edition-26H2-x64-BakaLiquid-UI-R2-20261024.iso`
- Size: 11,164,844,032 bytes
- SHA-256: `55E6883CC303AE5AD8D22EDD3C8A7E9344C13498F6623A79F4D5D1D5DF877CD8`

The build ISO was mounted and structurally inspected in the Windows 11 build environment. It contains one Windows 11 Pro x64 image, build 26300.9711, a valid Microsoft Setup signature, required BAKA runtime files, BIOS/UEFI boot entries, and the pinned browser payload. Host SHA-256 recalculation on 2026-10-26 matches the R2 candidate value above. Structural checks do not prove the ISO boots, Setup succeeds, or the installed desktop works.

The original and prior candidate were rehashed after the build and remain unchanged:

- Earlier candidate SHA-256: `830A4161DBE8C5EFAFDC6DCA19B8FE20571D057A5B97C8F5617EE21DE47A672D`
- Original ISO SHA-256: `EC287E1B8FF0FCD59E7DFDF3C9A0B95BA83D133B2AE3A9EF64F8F54E44AC7BAB`
- Official source ISO SHA-256: `BD4307DF32BC8AF33B39CCECB1174AEB345386630F89A2B86C7A4E36B55EA650`

## Changes made

- Built a distinct candidate from the pinned Windows 11 Pro source and serviced it to build 26300.9711 with the approved KB5127648 update.
- Integrated the optional BAKA Liquid WPF desktop companion while retaining Explorer as the Windows shell. It provides the dock, optional system bar, Quick Panel, settings editor, and optional widgets.
- Made BAKA Liquid the default visual preset: silver-on-black surfaces, layered Acrylic-style highlights, brief panel entrances, a one-shot glass sheen, and pointer-focused dock magnification. The R2 image includes refined dock/editor glass coverage, consistent opaque fallback, event-driven liquid sheen, dock wave, running indicators, and corrected icon sizing. Kept Obsidian, Liquid, Minimal, and Gaming presets plus optional Violet.
- Kept motion and transparent surfaces reduced in Competitive Gaming and Benchmark profiles. High-contrast and remote-session fallbacks use opaque surfaces. Retained Balanced power, Windows scheduling, security protections, reversible profile logic, and update-restoration controls.
- Removed eight exact reviewed consumer packages from the provisioned image: Gaming App, Xbox Gaming Overlay, Bing News, Bing Weather, Office Hub, Solitaire Collection, personal Teams, and Clipchamp. Microsoft Store, WebView2, Defender, Firewall, recovery, Bluetooth, and printing support were retained.
- Staged the selected Baka Browser payload with the pinned SHA-256. It is unsigned and was not executed.
- Kept clean-install disk selection interactive and did not add disk-erasure or partition automation.

## Source remediation — 2026-10-26

- Fixed a settings bug where changing the System widget refresh interval was saved to disk but the running timer kept its original interval. The polling scheduler now applies the saved value when widget visibility or settings are refreshed.
- Fixed a top-bar monitor-selection bug where the display setting was only read during initial window creation. The bar now repositions from the saved monitor setting when settings are applied, including after a restart.
- Added isolated UI smoke assertions for both corrected settings paths. Added a strict-by-default project-preflight option for source-only CI checkouts: `-SkipExternalArtifactChecks` explicitly reports skipped media and installer byte/signature checks and continues validating the source manifests and PowerShell code.
- Fixed clean-checkout test setup exposed by the first GitHub Actions run: preflight and release-guard tests now create their ignored `Logs`/`Output` directories when absent, as they are in a fresh clone.
- Validated the staged source snapshot from a clean archive with no ignored media/build folders: the latest repository-safe preflight passed 79 checks with 3 explicit skips, and all isolated test scripts passed.
- Added a Windows GitHub Actions source-validation workflow, a repository `.gitignore`, and portable source-test and contribution guidance. ISO images, source media, servicing packages, the unsigned browser installer, VM files, and raw host logs are excluded from commits.
- Recalculated the current R2 candidate, earlier candidate, original ISO, and Microsoft source hashes. No ISO or VM disk was modified during this source remediation.
- The source-validation workflow passed on the pushed source commit after the clean-checkout directory fix; the initial run exposed the missing-directory assumption and remains visible in Actions history.

## Performance impact and limits

The BAKA Liquid work changes the desktop's appearance and interaction. Hiding optional BAKA widgets and animations in Gaming and Benchmark modes is intended to reduce the companion's own background work. That reduction has not been measured in the installed image. Removing optional packages narrows the installed consumer-app set, but no memory, CPU, startup, FPS, frametime, or input-latency improvement has been demonstrated. No BAKA gaming-performance gain is claimed.

The serviced Microsoft update contains an upstream fix for mouse-input stutter in some games. That is a Microsoft Windows fix and is not a measurement of BAKA's performance.

## VMware A/B comparison — new request

- Audited the current host: Windows 10 Pro build 19045, Intel Core i5-14400F (10 cores / 16 threads), RTX 5060, 31.8 GiB RAM, and about 405 GiB free system-drive space. Hyper-V is active.
- Documented a matched stock-vs-BAKA VMware protocol in `docs/VMWARE_AB_COMPARISON.md`, including same-build servicing, UEFI/Secure Boot/vTPM, VM resources, repeatable idle and game measurements, and authentic screenshot evidence.
- Added `Scripts/Diagnostics/Collect-ABGuestMetrics.ps1` to record guest CPU, memory, disk throughput, and detected BAKA/game process usage as timestamped CSV and JSON. Its syntax and output flow passed a short host-only smoke check; this is not a guest measurement and yields no performance conclusion.
- The source ISO is build 26300.9457 and the BAKA candidate is 26300.9711. The stock guest must receive the same approved update before a fair comparison.

## VMware acceptance — 2026-10-27

- Created a separate disposable 4-vCPU/12-GiB UEFI/Secure Boot VMware VM with a new 80 GiB growable disk and the R2 ISO attached. The preserved AB shells and unrelated existing user VM were not modified.
- The candidate reached real Windows 11 Setup. Genuine VMware guest evidence is `docs/evidence/screenshots/20261027-vmware-baka-boot-result.png`; the screenshot SHA-256 is `E712042C81EE0F7A486D30CF737E161F02AC3207600B5860B7DF12E5F1339A3A`.
- Setup reported the missing TPM 2.0 requirement. Workstation's supported encryption/vTPM UI flow remains pending; no unsupported VMX TPM bypass was used. No disk partitioning or installation action was performed.

## VMware lab setup — 2026-10-26

- Verified VMware Workstation Pro 26H1 build 25388281. The installer has a valid Broadcom Inc. Authenticode signature; SHA-256 is `A0EF9087607D9CAD20B08139E73E41242E044AD5BD8CEE141D3BAD314586737F`.
- Created matched `BAKA-Stock-Reference` and `BAKA-Liquid-R2` Workstation VM shells in ignored `Work/VMware-AB-20261026/`. Each has 4 vCPUs, 12 GiB RAM, a 160 GiB growable disk, UEFI firmware, Secure Boot, 3D acceleration, NAT networking, and its stock or BAKA ISO attached. The source and candidate ISOs remain unchanged.
- The preserved AB BAKA shell's VMware UEFI boot log reports `SECUREBOOT: Image APPROVED`, and the firmware lists the candidate ISO. That preserved comparison still did not open Setup and does not resolve the earlier Hyper-V boot failure.
- Workstation requires VM encryption before adding a vTPM. Broadcom's instructions use Workstation's encryption and TPM settings UI; its employee response says `vmcli` cannot create encryption or a vTPM. The Windows computer-use capture channel failed twice (`FrameArrived timed out: timed out waiting on channel`; `window capture timed out: timed out waiting on channel`), so UI automation stopped. No TPM bypass or unsupported VMX TPM flag was used. [Broadcom Windows 11 guest instructions](https://knowledge.broadcom.com/external/article/315650) · [Broadcom vmcli response](https://community.broadcom.com/vmware-cloud-foundation/discussion/vmcli-add-encryption-for-enabling-tpm)
- Captured genuine boot-manager evidence at `docs/evidence/screenshots/20261026-baka-vmware-uefi-boot-manager.png` and genuine Setup evidence at `docs/evidence/screenshots/20261027-vmware-baka-boot-result.png`. No installed Windows desktop, game, or VM performance result exists yet. Physical hardware testing remains unavailable.
- Tested the official source ISO in the matched stock guest: it also logs `SECUREBOOT: Image APPROVED` and then `Status upon boot failure: Time out` at the EFI CD-ROM handoff. Saved the actual firmware screenshot at `docs/evidence/screenshots/20261026-stock-source-vmware-efi-timeout.png`. This common result does not establish a BAKA-only boot defect. BAKA trials moving the ISO from SATA port 1 to port 0 and then IDE had the same timeout. A timed Enter-key event and the vendor-recommended `windows10-64` guest type also did not resolve it. Workstation reports `Monitor Mode: ULM` with Hyper-V detected. No Windows Setup or installed desktop has been reached.
- Further VMware installation testing depends on completing Workstation encryption and adding a vTPM device to the disposable VM. The A/B plan, preserved shells, and metrics collector are ready; no BAKA performance gain is claimed.

## Bugs fixed

1. **ISO creation/remoting:** The first OSCDIMG attempt wrote an unmountable image because PowerShell remoting interpreted native tool output as a terminating error. The build script now redirects stdout and stderr into separate logs, checks the process exit code, and records success only after a successful exit. The failed image was isolated in build diagnostics; it did not replace the original or earlier candidate. The corrected run produced the structurally validated candidate.
2. **Stale ISO validator expectation:** The validator expected the retired `BakaDock.ps1` payload. It now checks the integrated companion, first-logon workflow, modules, and configuration files actually staged by the project.
3. **Build pipeline stage errors:** Pipeline failure records now preserve detailed stage errors, aiding diagnosis instead of reporting only a generic failure.
4. **System widget refresh setting:** A saved polling interval no longer leaves the active timer at its startup value.
5. **Top-bar display setting:** Applying a display selection now moves the bar immediately to the selected monitor instead of waiting for a restart.
6. **Clean-checkout validation:** Source preflight and release-guard tests no longer assume ignored `Logs/` or `Output/` directories already exist.

## Checks completed

| Check | Result | Evidence / limits |
| --- | --- | --- |
| Full project parser/configuration preflight | Passed, 85/85 | Local source media, signed servicing packages, and pinned browser payload were present and checked. |
| Repository-safe project preflight | Passed, 79 passed / 3 explicitly skipped | Latest host rerun; skips are limited to external ISO bytes, servicing package bytes/signatures, and the excluded browser installer bytes/signature. |
| Clean source-only checkout | Passed | The repository-safe preflight and all seven isolated test scripts passed with no ignored media/build folders present. |
| Windows 11 build host preflight | Passed, 8/8 | Raw machine-specific build evidence is retained locally and not published. |
| Source transfer and integrity | Passed, 60 files | Transferred build inputs were hash-checked; raw host records remain local. |
| Microsoft source, Setup signature, servicing, and image integrity | Passed | Verified during the prior Windows 11 build; no rebuild occurred during source remediation. |
| Current Windows release and supported ADK version | Passed | Microsoft release history and local ADK file-version evidence were checked on 2026-10-26. |
| ISO creation and structural validation | Passed | Prior build exited successfully and the resulting candidate mounted for structural validation. |
| Preserved and new artifact hashes | Passed | All four image/source hashes were recalculated on 2026-10-26 and matched their records. |
| Theme contrast | Passed, 20/20 | Required presets and optional Violet. |
| WPF source-preview smoke | Passed, 15/15 stages | Latest rerun includes BAKA Files readability/close plus live widget refresh interval and top-bar monitor placement. It used the Windows 10 opaque fallback; this is not installed Windows 11 glass validation. |
| Desktop settings persistence/recovery | Passed, 4/4 | Isolated temporary settings. |
| Profile recovery/rollback/instance lock | Passed, 6/6 | Simulated registry; no host profile registry writes. |
| System metrics data path | Passed at source level | Returned values or explicit unavailable states; no companion overhead measurement. |
| Release-pipeline overwrite guards | Passed, 2/2 | Existing workspaces and ISO destinations remained protected. |
| CS2/TF2 detection and VALORANT exclusion | Passed at unit level | Process-name checks only; no game install or launch. |

Complete evidence inventory and acceptance status are in `docs/BUILD_STATUS.md` and `docs/ACCEPTANCE_MATRIX.md`.

## Outstanding acceptance

- Windows SIM catalog-backed answer-file validation remains outstanding. Console capture timed out and the GUI was not opened.
- The earlier Hyper-V and preserved VMware AB attempts still failed before Setup with the documented shared EFI timeout. A new disposable VMware VM reached Setup but stopped at the missing TPM 2.0 requirement. No disk partitioning or installation action occurred.
- Clean UEFI installation, interactive disk confirmation, OOBE, and both local and Microsoft account paths. The new empty 80 GiB test disk is attached; the previous system disk remains detached. No partition or erase action has been performed.
- Installed desktop testing: dock, bar, Quick Panel, widgets, persistence, profile switching/restoration, Explorer fallback, scaling, keyboard access, multi-monitor, sleep/wake, and crash recovery.
- Runtime Defender, Firewall, SmartScreen, UAC, exploit-protection, recovery, and Windows Update suppression/restoration checks.
- Baka Browser installation/launch in the isolated acceptance VM. The installer remains unexecuted despite prior user authorization.
- VMware installation and CS2/Team Fortress 2 or another free game testing. VALORANT remains excluded by user request.
- Companion idle CPU/memory/wakeups/startup and gameplay overhead measurements.
- Physical Intel/AMD game, frametime, input-latency, USB polling, DPC/ISR, and peripheral tests. Physical hardware is unavailable; these remain blocked.

The technician VM is Saved with guest state preserved after the Windows SIM console check; its heartbeat was healthy but the desktop could not be captured. The acceptance VM is Off after the latest failed boot attempt; the R2 ISO and fresh 80 GiB test disk remain attached under an automatic checkpoint, and the previous system disk remains detached. Hyper-V recorded the same EFI boot failure for the official source and the candidate. Setup was not observed, console capture remains unavailable, and no guest input or partition/erase action occurred. Raw host logs are retained locally; a sanitized source-test summary is in `docs/evidence/SOURCE_VALIDATION_20261026.md`.
