# Build and release status

Updated: 2026-10-26

## Release state

The BAKA Liquid UI-R2 candidate was built in the authorized Windows 11 technician VM and passed structural ISO validation. It is a **structurally validated candidate**, not a fully acceptance-tested release: guest boot/Setup could not be observed through the VM console, and installed-desktop behavior, Windows SIM, game testing, and physical performance testing remain outstanding.

| Artifact | Size | SHA-256 | Status |
| --- | ---: | --- | --- |
| `Output/BAKA-Windows-Gaming-Edition-26H2-x64-BakaLiquid-UI-R2-20261024.iso` | 11,164,844,032 bytes | `55E6883CC303AE5AD8D22EDD3C8A7E9344C13498F6623A79F4D5D1D5DF877CD8` | Current candidate; structural validation passed |
| `Output/BAKA-Windows-Gaming-Edition-26H2-x64-20261016.iso` | 11,162,904,576 bytes | `830A4161DBE8C5EFAFDC6DCA19B8FE20571D057A5B97C8F5617EE21DE47A672D` | Preserved earlier candidate; unchanged |
| `Output/BAKA-Windows-Gaming-Edition-26H2-x64.iso` | 11,787,081,728 bytes | `EC287E1B8FF0FCD59E7DFDF3C9A0B95BA83D133B2AE3A9EF64F8F54E44AC7BAB` | Preserved original; unchanged |
| `Source/OfficialWindowsMedia/Windows11_Client_x64_en-us_26300_9457.iso` | 9,047,330,816 bytes | `BD4307DF32BC8AF33B39CCECB1174AEB345386630F89A2B86C7A4E36B55EA650` | Pinned Microsoft source; verified |

The current candidate hash was recalculated on the host on 2026-10-26. The earlier candidate, original ISO, and Microsoft source hashes were recalculated after the build and matched. The R2 ISO is the primary artifact for review; do not call it fully accepted until the remaining acceptance tests pass.

## Build inputs and servicing

- Base image: official Windows 11 Pro x64, en-US, build `10.0.26300.9457`, exported as one Pro image.
- Servicing target: October 13, 2026 security update KB5127648, build `10.0.26300.9711`. The exact installed CBS package identity was verified with DISM before committing the image.
- The older checkpoint KB5043080 was skipped because the source image already contained a superseding rollup. The package and source hashes, Microsoft signatures, and build logs are retained.
- Build technician VM: Windows 11 Pro build 26300.9711, 8 vCPU, Secure Boot, ADK DISM/Windows SIM 10.0.26100.9457, matching WinPE add-on, and OSCDIMG 2.56. It is currently Saved with guest state preserved after the uncompleted Windows SIM console check. Its data VHDX was mounted read-only to copy the validated artifact and evidence, then detached.
- The host execution-policy override was process-only inside the build session; the VM's saved policy was not changed.

On 2026-10-26, Microsoft release history still listed Windows 11 26H2 build 26300.9711 (KB5127648, October 13) as the latest 26H2 release, matching the candidate. Microsoft release health marked 26H2 generally available as of October 21. KB5127648 includes an upstream mouse-input-stutter fix in some games; this is a Windows servicing change, not a measured BAKA performance result. The builder VHDX file check confirmed WSIM and ADK DISM versions 10.0.26100.9457, matching Microsoft's September 2026 ADK 10.1.26100.9457 release, which supports 26H2 and lists a WSIM fix for CVE-2026-25166. Windows SIM answer-file validation itself remains unperformed. See [release history](https://learn.microsoft.com/en-in/windows/release-health/windows11-release-information), [release health](https://learn.microsoft.com/en-us/windows/release-health/status-windows-11-26h2), [KB5127648](https://support.microsoft.com/en-us/servicing/os/windows-11/2026/10/kb5127648-windows-11-24h2-25h2-26h2-security-update), [ADK installation guidance](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install), [ADK release notes](https://learn.microsoft.com/en-us/windows-hardware/get-started/what-s-new-in-kits-and-tools), and the local check logs.

## Image changes

- Integrated the optional BAKA Liquid WPF companion while keeping Explorer as the shell. The desktop default is BAKA Liquid: silver-on-black surfaces, layered Acrylic-style highlights, short panel entrances, one-shot glass sweeps, and pointer-focused dock magnification.
- Added the Obsidian, Liquid, Minimal, and Gaming theme presets; Violet remains optional. Competitive Gaming and Benchmark use opaque surfaces, hide optional widgets, and suppress motion. Reduced-motion keeps static glass when supported; high-contrast and remote sessions use the opaque fallback.
- Preserved Desktop, Competitive Gaming, and Benchmark profile behavior, Balanced as the default power policy, Windows' native CPU scheduler, security protections, and reversible update-restoration controls.
- Removed only the exact approved provisioned consumer packages found in the image inventory: Xbox Gaming App, Xbox Gaming Overlay, Bing News, Bing Weather, Office Hub, Solitaire Collection, personal Teams, and Clipchamp. Store, WebView2, Defender, Firewall, recovery, Bluetooth, and printing dependencies were protected.
- Staged the user-selected Baka Browser installer with its pinned SHA-256. The installer is unsigned and was **not executed**.
- Kept interactive Setup and disk selection. The answer file only registers the first-logon workflow; it does not automate partitioning or account creation.

The visual work improves the desktop's appearance and interaction. Profile behavior is designed to reduce optional BAKA UI activity during gaming and benchmarking, but idle CPU, memory, wakeups, game overhead, FPS, frame pacing, and input latency were not measured. No BAKA performance gain is claimed.

## Build issue found and fixed

The first OSCDIMG attempt created a file with the expected byte count, but PowerShell remoting treated native output as a terminating error and the ISO failed to mount. That incomplete file was preserved under isolated build diagnostics. Raw diagnostics are retained locally and are not included in the source repository.

`Scripts/06-BuildISO.ps1` now launches OSCDIMG with stdout and stderr captured to separate logs, checks the process exit code, and writes the build record only after successful completion. The retry exited with code 0, and the resulting ISO mounted and passed `Scripts/07-ValidateISO.ps1`. `Invoke-BuildPipeline.ps1` also records full error details when a stage fails.

## Verification evidence

Raw evidence is retained in the local `Logs/` directory. The sanitized test summary is published at `docs/evidence/SOURCE_VALIDATION_20261026.md`.

| Check | Result | Evidence and limits |
| --- | --- | --- |
| Full project configuration and parser preflight | **Passed, 83/83** | Includes external source, package, and browser installer hash/signature checks. |
| Repository-safe source preflight | **Passed, 77 passed / 3 explicitly skipped** | Skips only checks requiring excluded external ISO, servicing packages, and browser installer bytes. |
| Build VM preflight | **Passed, 8/8** | `BuildVM-UI-R2-20261024/BuildHost-20261024-155554.json`; Windows 11, x64, admin, and required tools. |
| Input transfer | **Passed, 60 files** | The transferred build inputs were hash-checked; the machine-specific transfer manifest is retained locally. |
| Preserved and new artifact hashes | **Passed** | R2 candidate recalculated on host on 2026-10-26; earlier candidate, original ISO, and pinned Microsoft source hashes match their recorded values. |
| Windows source verification | **Passed** | `BuildVM-UI-R2-20261024/VerifiedSource.json`; Windows 11 Pro x64 en-US and valid Microsoft Setup signature. |
| Approved servicing | **Passed** | DISM logs and `BuildVM-UI-R2-20261024/build-context.json`; target update package installed and image integrity checked. |
| Component inventory/removal | **Passed** | `BuildVM-UI-R2-20261024/provisioned-packages.json` and `BAKA-20261024.log`; eight exact reviewed consumer packages removed. |
| ISO creation | **Passed** | `BuildVM-UI-R2-20261024/ISO-Build.json` and OSCDIMG stdout/stderr logs; exit code 0, BIOS/UEFI boot entries, final size and hash recorded. |
| Structural ISO validation | **Passed** | `BuildVM-UI-R2-20261024/ISO-Validation.json`; readable mount, single Windows 11 Pro image build 26300.9711, valid Microsoft Setup signature, required BAKA files, and pinned browser hash. |
| BAKA theme contrast | **Passed, 20/20** | Required presets and optional Violet pass contrast thresholds. |
| WPF source-preview smoke | **Passed, 13/13 stages** | Includes the live widget refresh-interval and top-bar monitor-placement regression checks. The Windows 10 host used the opaque fallback; this is not installed Windows 11 Acrylic validation. |
| Desktop settings persistence/recovery | **Passed, 4/4** | Isolated temporary files. |
| Profile recovery/rollback/instance lock | **Passed, 6/6** | Simulated registry adapter; no host profile registry writes. |
| CS2/TF2 detection and VALORANT exclusion | **Passed at unit level** | Process detection only; no game was launched. |
| System metrics data path | **Passed at source level** | Returned values or explicit unavailable states; no companion overhead measurement. |
| Release-pipeline overwrite guards | **Passed, 2/2** | Existing workspaces and ISO destinations remained protected. |

## Acceptance not completed

- Windows SIM catalog-backed answer-file validation was not performed. XML/source checks are not SIM validation. The technician VM heartbeat was healthy, but its console capture timed out and Windows SIM was not opened.
- Candidate and official-source boot attempts both failed in one Hyper-V environment: Event 18603 shows EFI/BOOT/BOOTX64.EFI status 0x00010003 with extended status 0x00000013 for R2, Microsoft source, then R2 twice. Read-only comparison found zero differences across 64 EFI/boot/Windows PE boot files per image. Root cause remains unresolved; this does not establish a candidate-only defect or validate boot on other systems. Ten console screenshot captures timed out, including two in the latest retry; no guest input was sent. See `docs/evidence/SOURCE_VALIDATION_20261026.md`.
- Clean UEFI install, disk-selection confirmation, local/Microsoft account OOBE paths, and first-boot workflow were not run. A fresh empty 80 GiB test disk is attached; the prior system disk remains detached. No partition or erase action has been performed.
- The acceptance VM is Off after the latest failed boot attempt. The R2 DVD remains first, Secure Boot and TPM remain enabled, and the fresh 80 GiB test disk remains attached under an automatic Hyper-V checkpoint. Guest heartbeat reported No Contact while running. VMConnect opens, but its display capture channel times out. The prior system disk remains detached.
- Installed dock, bar, Quick Panel, widgets, profile restoration, Explorer fallback, Windows security, update suppression/restoration, sleep/wake, accessibility, scaling, and crash recovery remain untested.
- Baka Browser execution, VMware CS2/Team Fortress 2 installation or gameplay, and anti-cheat behavior were not tested. VMware/VMware Player is not available on this host. VALORANT remains excluded by user instruction.
- Physical Intel/AMD performance, FPS, 1% lows, frame pacing, input latency, USB polling, DPC/ISR, peripheral stability, and runtime resource use are unavailable without suitable physical hardware.

The candidate is structurally validated but **not fully acceptance-tested**. Do not claim measured FPS or latency improvements.
