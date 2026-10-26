# BAKA release acceptance matrix

Updated: 2026-10-26. A result is marked **Passed** only when the named evidence supports it. Source previews and configuration checks do not count as installed-image acceptance.

## Release artifacts

| Artifact | Size | SHA-256 | Status |
| --- | ---: | --- | --- |
| `Output/BAKA-Windows-Gaming-Edition-26H2-x64-BakaLiquid-UI-R2-20261024.iso` | 11,164,844,032 bytes | `55E6883CC303AE5AD8D22EDD3C8A7E9344C13498F6623A79F4D5D1D5DF877CD8` | Current candidate; structural validation passed, acceptance incomplete |
| `Output/BAKA-Windows-Gaming-Edition-26H2-x64-20261016.iso` | 11,162,904,576 bytes | `830A4161DBE8C5EFAFDC6DCA19B8FE20571D057A5B97C8F5617EE21DE47A672D` | Preserved, unchanged |
| `Output/BAKA-Windows-Gaming-Edition-26H2-x64.iso` | 11,787,081,728 bytes | `EC287E1B8FF0FCD59E7DFDF3C9A0B95BA83D133B2AE3A9EF64F8F54E44AC7BAB` | Preserved original, unchanged |
| `Source/OfficialWindowsMedia/Windows11_Client_x64_en-us_26300_9457.iso` | 9,047,330,816 bytes | `BD4307DF32BC8AF33B39CCECB1174AEB345386630F89A2B86C7A4E36B55EA650` | Pinned Microsoft source, verified |

All four hashes were recalculated on 2026-10-26 and match the recorded values. Raw build and VM logs remain local and are excluded from the source repository because they contain machine-specific paths and details. The sanitized source and acceptance summary is in `docs/evidence/SOURCE_VALIDATION_20261026.md`.

## Test environment
- The authorized Windows 11 technician VM completed the build and is currently Saved with its guest state preserved after the Windows SIM console attempt.
- The disposable Generation 2 acceptance VM is Off after a repeat boot-failure check. It is configured with 6 vCPUs and 8 GiB RAM; the R2 ISO and fresh 80 GiB test disk remain attached, and the earlier system disk remains detached and preserved. Hyper-V created an automatic checkpoint.
- Host configuration reports Secure Boot On with the Microsoft Windows template and TPM enabled. The DVD is first in the UEFI boot order. Guest integration services report No Contact.
- After UAC approval, the acceptance VM was restarted and connected by name. Hyper-V recorded Event 18603 boot failures for R2 at 18:05:32, the official source at 18:23:41, R2 at 18:25:02, and R2 again at 19:37:08. Each attempt reported the same EFI loader result (0x00010003, extended status 0x00000013) at `EFI/BOOT/BOOTX64.EFI`. The DVD remained first in the UEFI boot order and Secure Boot remained enabled. Ten console screenshot captures have timed out in total, including two in this retry. No Setup/OOBE text was captured, no guest input or partition/erase action occurred, and the acceptance VM is now Off. Raw host logs are retained locally and excluded from the source repository; the sanitized project summary is in `docs/evidence/SOURCE_VALIDATION_20261026.md`.
- Suitable physical Intel/AMD gaming hardware is unavailable. Physical gameplay, latency, USB, DPC/ISR, and stability tests cannot be substituted with source checks or VM observations.

## Boot attempt diagnosis

| Requirement | Status | Evidence / limits |
| --- | --- | --- |
| Project configuration and PowerShell parser | **Passed** | Full local preflight passed 83/83. Repository-safe mode passed 77 checks and explicitly skipped 3 external-artifact checks. See `docs/evidence/SOURCE_VALIDATION_20261026.md`. |
| Clean source-only checkout | **Passed** | Repository-safe preflight and all seven isolated test scripts passed without ignored media or build folders present. |
| Official source and Windows build identity | **Passed** | Guest source verification and final ISO validation; Windows 11 Pro x64 en-US, build 26300.9711; valid Microsoft Setup signature. |
| Approved image servicing and integrity | **Passed** | DISM servicing logs and `BuildContext-20261024.json`; KB5127648 package identity verified, image integrity/commit completed. |
| Current Windows release and supported ADK version | **Passed** | 2026-10-26 release-history and offline ADK version checks are recorded in the local project. Windows SIM answer-file validation remains unperformed. |
| Exact approved consumer package removals | **Passed** | Eight package identities confirmed in image inventory/log; Store, WebView2, Defender, Firewall, recovery, Bluetooth, and printing retained. |
| New ISO creation and boot-media structure | **Passed** | `ISO-Build.json`; OSCDIMG exit 0, BIOS and UEFI boot entries recorded. |
| Structural ISO validation | **Passed** | R2 `ISO-Validation.json` in the build evidence folder; mountable, one Windows 11 Pro image, valid Setup signature, BAKA runtime payload present, pinned browser hash matches. This does not prove boot or installation. |
| Candidate, original, and source preservation | **Passed** | Host SHA-256 recalculation matches all pinned values; prior candidate and original remain unchanged. |
| BAKA theme contrast | **Passed, 20/20** | Required presets and optional Violet pass contrast thresholds. Sanitized summary in `docs/evidence/SOURCE_VALIDATION_20261026.md`. |
| WPF companion source preview | **Passed with limits** | 13/13 stages on the Windows 10 development host's opaque fallback. Includes widget refresh interval and top-bar monitor-placement regression checks. This does not verify installed Windows 11 Acrylic rendering. |
| Settings persistence/recovery | **Passed, 4/4 source checks** | Isolated temporary files only. |
| Profile rollback/restoration and duplicate-instance guard | **Passed, 6/6 source checks** | Simulated registry; no host profile registry writes. Does not establish installed guest behavior. |
| CS2/TF2 process detection and VALORANT exclusion | **Passed at unit level** | Process-name checks only. No game installation, launch, gameplay, or anti-cheat test. |
| System metrics data path | **Passed at source level** | Returned values or explicit unavailable states. Sensor accuracy and companion overhead were not measured. |
| Release output overwrite guards | **Passed, 2/2** | Existing workspaces and ISO destinations remained protected. |
| OSCDIMG remoting failure handling | **Bug fixed and regression checked** | Output is redirected to separate logs, exit status is checked, and build record is only written on success. Regression included in the 83/83 project preflight. |

## Not run or blocked

| Requirement | Status | Evidence / limitation |
| --- | --- | --- |
| Windows SIM catalog-backed answer-file validation | **Not run** | Console capture timed out; Windows SIM was not opened and no catalog-backed validation is claimed. |
| Candidate ISO boot in a VM | **Failed in one Hyper-V environment; root cause unresolved** | Event 18603 reports the same EFI boot-image error for R2 and the official Microsoft source. The compared 64-file boot-path sets match; this does not establish full ISO validity. See `docs/evidence/SOURCE_VALIDATION_20261026.md`. |
| Clean UEFI install, interactive disk selection, confirmation, OOBE | **Not run** | Setup could not be inspected or operated. The new blank test disk is attached and the earlier disk is detached. No partition or erase action was sent. |
| Local and Microsoft account setup paths | **Not run** | Requires interactive OOBE on the candidate. |
| Installed BAKA Liquid desktop, dock, bar, Quick Panel, widgets, editor | **Not run** | Source preview is not installed-image runtime evidence. |
| Profile switching, restoration, Explorer fallback, crash recovery | **Not run in installed guest** | Reversible logic has isolated source tests; actual installed behavior remains unverified. |
| Defender, Firewall, SmartScreen, UAC, exploit protection, recovery | **Not run in installed guest** | Build config retained these components; runtime state has not been inspected. |
| Windows Update suppression and administrator restoration | **Not run in installed guest** | Static implementation is present; policy and restore flow still need runtime proof. |
| UI scaling, keyboard/focus accessibility, multiple monitors, sleep/wake, long-run stability | **Not run** | Requires installed runtime and appropriate VM/display coverage. |
| Companion CPU, memory, wakeups, startup time, game overhead | **Not measured** | No installed process measurements. No resource budget or FPS benefit is claimed. |
| Baka Browser install and launch | **Not run** | The unsigned installer was staged and hash-matched but not executed. The acceptance VM has not reached a verified installed desktop. Earlier authorization is limited to that isolated VM. |
| VMware CS2, Team Fortress 2, or another free game | **Not run** | VMware/VMware Player is not available on this host, and no game installation or gameplay result exists. Anti-cheat compatibility is unclaimed. VALORANT is excluded per user request. |
| Physical Intel/AMD FPS, 1% lows, frame pacing, input latency, USB polling, DPC/ISR, peripheral stability | **Blocked** | Suitable physical test hardware is unavailable. No physical results are claimed. |
| Release acceptance | **Incomplete** | The candidate is structurally validated, not fully acceptance-tested. |

## Build issue fixed

The first OSCDIMG run generated an unmountable ISO because native process output was treated as a terminating remoting error. That failed artifact was kept in isolated build diagnostics and recorded. `Scripts/06-BuildISO.ps1` now captures stdout/stderr separately, checks the exit code, and records success only after completion; the retry produced the candidate above and passed structural validation. `Scripts/Invoke-BuildPipeline.ps1` retains stage error details. See `ISO-CreateFailure-20261024.json`, `BuildVM-OSCDIMG-Fix-20261024.json`, and `ISO-Build.json` in the build evidence folder.

No BAKA FPS or latency gain is established. The interface and package choices should be described as design and installed-app-surface changes, while game and system performance remain unmeasured.
