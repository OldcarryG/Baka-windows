# BAKA Windows Gaming Edition — progress report

Updated: 2026-10-26

## Current result

A distinct BAKA Liquid UI-R2 candidate has been built in the user-authorized Windows 11 technician VM and passed structural ISO validation. The original ISO and the earlier 2026-10-16 candidate remain unchanged. This is **not a fully acceptance-tested release**: the VM guest boot/Setup screen could not be observed, and installation/OOBE, Windows SIM, installed desktop behavior, security and update-restoration checks, game testing, and physical performance measurements remain outstanding.

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
- Validated the staged source snapshot from a clean archive with no ignored media/build folders: the 77-pass/3-skip source preflight and all seven isolated test scripts passed.
- Added a Windows GitHub Actions source-validation workflow, a repository `.gitignore`, and portable source-test and contribution guidance. ISO images, source media, servicing packages, the unsigned browser installer, VM files, and raw host logs are excluded from commits.
- Recalculated the current R2 candidate, earlier candidate, original ISO, and Microsoft source hashes. No ISO or VM disk was modified during this source remediation.
- The source-validation workflow passed on the pushed source commit after the clean-checkout directory fix; the initial run exposed the missing-directory assumption and remains visible in Actions history.

## Performance impact and limits

The BAKA Liquid work changes the desktop's appearance and interaction. Hiding optional BAKA widgets and animations in Gaming and Benchmark modes is intended to reduce the companion's own background work. That reduction has not been measured in the installed image. Removing optional packages narrows the installed consumer-app set, but no memory, CPU, startup, FPS, frametime, or input-latency improvement has been demonstrated. No BAKA gaming-performance gain is claimed.

The serviced Microsoft update contains an upstream fix for mouse-input stutter in some games. That is a Microsoft Windows fix and is not a measurement of BAKA's performance.

## VMware A/B comparison — new request

- Audited the current host: Windows 10 Pro build 19045, Intel Core i5-14400F (10 cores / 16 threads), RTX 5060, 31.8 GiB RAM, and about 405 GiB free system-drive space. Hyper-V is active; VMware Workstation is not installed.
- Documented a matched stock-vs-BAKA VMware protocol in `docs/VMWARE_AB_COMPARISON.md`, including same-build servicing, UEFI/Secure Boot/vTPM, VM resources, repeatable idle and game measurements, and authentic screenshot evidence.
- Added `Scripts/Diagnostics/Collect-ABGuestMetrics.ps1` to record guest CPU, memory, disk throughput, and detected BAKA/game process usage as timestamped CSV and JSON. Its syntax and output flow passed a short host-only smoke check; this is not a guest measurement and yields no performance conclusion.
- Broadcom's official 26H1 download route requires portal sign-in. The user has said they will sign in; no installer is available locally yet. The stock guest, BAKA guest, screenshots, resource measurements, CS2/TF2 runs, and performance delta are therefore not started. No performance improvement is claimed.
- The source ISO is build 26300.9457 and the BAKA candidate is 26300.9711. The stock guest must receive the same approved update before a fair comparison.

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
| Full project parser/configuration preflight | Passed, 83/83 | Local source media, signed servicing packages, and pinned browser payload were present and checked. |
| Repository-safe project preflight | Passed, 77 passed / 3 explicitly skipped | Skips are limited to external ISO bytes, servicing package bytes/signatures, and the excluded browser installer bytes/signature. |
| Clean source-only checkout | Passed | The repository-safe preflight and all seven isolated test scripts passed with no ignored media/build folders present. |
| Windows 11 build host preflight | Passed, 8/8 | Raw machine-specific build evidence is retained locally and not published. |
| Source transfer and integrity | Passed, 60 files | Transferred build inputs were hash-checked; raw host records remain local. |
| Microsoft source, Setup signature, servicing, and image integrity | Passed | Verified during the prior Windows 11 build; no rebuild occurred during source remediation. |
| Current Windows release and supported ADK version | Passed | Microsoft release history and local ADK file-version evidence were checked on 2026-10-26. |
| ISO creation and structural validation | Passed | Prior build exited successfully and the resulting candidate mounted for structural validation. |
| Preserved and new artifact hashes | Passed | All four image/source hashes were recalculated on 2026-10-26 and matched their records. |
| Theme contrast | Passed, 20/20 | Required presets and optional Violet. |
| WPF source-preview smoke | Passed, 13/13 stages | Latest rerun includes regression checks for live widget refresh interval and top-bar monitor placement. It used the Windows 10 opaque fallback; this is not installed Windows 11 glass validation. |
| Desktop settings persistence/recovery | Passed, 4/4 | Isolated temporary settings. |
| Profile recovery/rollback/instance lock | Passed, 6/6 | Simulated registry; no host profile registry writes. |
| System metrics data path | Passed at source level | Returned values or explicit unavailable states; no companion overhead measurement. |
| Release-pipeline overwrite guards | Passed, 2/2 | Existing workspaces and ISO destinations remained protected. |
| CS2/TF2 detection and VALORANT exclusion | Passed at unit level | Process-name checks only; no game install or launch. |

Complete evidence inventory and acceptance status are in `docs/BUILD_STATUS.md` and `docs/ACCEPTANCE_MATRIX.md`.

## Outstanding acceptance

- Windows SIM catalog-backed answer-file validation remains outstanding. Console capture timed out and the GUI was not opened.
- Candidate and official-source boot attempts both failed in one acceptance Hyper-V environment: Event 18603 reports EFI/BOOT/BOOTX64.EFI status 0x00010003 / extended 0x00000013 for R2, Microsoft source, then R2 twice. A read-only comparison found no differences across 64 EFI/boot/Windows PE boot files per image. The DVD remained first in UEFI order and Secure Boot remained on. Root cause remains unresolved. Ten console captures timed out, including two on the latest retry; no guest input or partition/erase action occurred.
- Clean UEFI installation, interactive disk confirmation, OOBE, and both local and Microsoft account paths. The new empty 80 GiB test disk is attached; the previous system disk remains detached. No partition or erase action has been performed.
- Installed desktop testing: dock, bar, Quick Panel, widgets, persistence, profile switching/restoration, Explorer fallback, scaling, keyboard access, multi-monitor, sleep/wake, and crash recovery.
- Runtime Defender, Firewall, SmartScreen, UAC, exploit-protection, recovery, and Windows Update suppression/restoration checks.
- Baka Browser installation/launch in the isolated acceptance VM. The installer remains unexecuted despite prior user authorization.
- VMware installation and CS2/Team Fortress 2 or another free game testing. VALORANT remains excluded by user request.
- Companion idle CPU/memory/wakeups/startup and gameplay overhead measurements.
- Physical Intel/AMD game, frametime, input-latency, USB polling, DPC/ISR, and peripheral tests. Physical hardware is unavailable; these remain blocked.

The technician VM is Saved with guest state preserved after the Windows SIM console check; its heartbeat was healthy but the desktop could not be captured. The acceptance VM is Off after the latest failed boot attempt; the R2 ISO and fresh 80 GiB test disk remain attached under an automatic checkpoint, and the previous system disk remains detached. Hyper-V recorded the same EFI boot failure for the official source and the candidate. Setup was not observed, console capture remains unavailable, and no guest input or partition/erase action occurred. Raw host logs are retained locally; a sanitized source-test summary is in `docs/evidence/SOURCE_VALIDATION_20261026.md`.
