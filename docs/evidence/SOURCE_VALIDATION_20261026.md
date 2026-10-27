# Sanitized source validation evidence

**Run date:** 2026-10-27 source follow-up; prior image-validation evidence remains dated 2026-10-26

**Scope:** source, configuration, and isolated desktop preview only. The installed Windows image was not tested in this run.

## Changes checked

- System-widget refresh interval changes now update the active polling timer after settings are applied.
- Top-bar monitor changes now reposition the bar after settings are applied.
- The WPF preview smoke now asserts both behaviors in its isolated temporary profile.
- The companion reliability pass adds icon glyph rendering, manual-profile polling suspension, Quick Panel null protection, settings-import error containment, profile UI rollback attempts, and strict-mode cleanup initialization.
- The project preflight supports a source-only CI mode that marks unavailable external artifact checks as skipped. Default local preflight remains strict.

## Results

| Check | Result | Limits |
| --- | --- | --- |
| Full local project preflight | **Passed, 85/85** | Local pinned Windows media, servicing packages, and browser installer were present and checked. The unsigned browser installer was not executed. |
| Repository-safe project preflight | **Passed, 79 passed / 3 explicitly skipped** | Skips are limited to external Windows ISO bytes, servicing package bytes/signatures, and the excluded Baka Browser installer bytes/signature. Manifest and source checks still ran. |
| Clean source-only checkout | **Passed** | The repository-safe preflight and all seven isolated test scripts passed from an archive containing only staged Git files, with no `Source`, `Downloads`, `Output`, `Work`, or `Logs` directory at checkout. |
| BAKA Liquid WPF preview smoke | **Passed, 13 stages** | Runs on the development host using Windows' opaque backdrop fallback. Not installed Windows 11 Acrylic validation. |
| VMware candidate boot/Setup observation | **Passed with limitation** | A new disposable VMware VM reached genuine Windows 11 Setup; Setup stopped on missing TPM 2.0. See `docs/evidence/VMWARE_ACCEPTANCE_20261027.md`. |
| Theme contrast | **Passed, 20/20** | Required monochrome presets and optional Violet preset. |
| Desktop settings persistence and recovery | **Passed, 4/4** | Isolated temporary files. |
| Gaming-profile rollback and duplicate-instance guard | **Passed, 6/6** | Registry behavior simulated; no host profile registry changes. |
| CS2/TF2 process detection | **Passed** | Unit-level name matching only; no game was installed or launched. VALORANT remains excluded. |
| System monitoring data path | **Passed** | Values or explicit unavailable states were returned. This did not measure BAKA companion resource use. |
| Release output overwrite guards | **Passed, 2/2** | Existing workspaces and ISO destinations were rejected. |
| Companion reliability guards | **Passed** | Source guards and the WPF preview smoke cover the 2026-10-27 reliability changes. |
| Host preview CPU sample | **Passed for this sample only** | 0.494% average, 0.824% maximum across 15 two-second samples after a five-second warm-up. |
| Host preview memory sample | **Failed for this sample** | 212.76 MiB average working set, 215.38 MiB maximum; the initial 150 MiB target was exceeded. |

Raw logs are retained in the local project `Logs/` directory. They are excluded from this repository because they contain host paths and machine-specific build details.

## Preserved artifact hashes

All hashes below were recalculated on 2026-10-26 and rechecked on 2026-10-27. No ISO was modified during this source remediation.

| Artifact | SHA-256 |
| --- | --- |
| Current BAKA Liquid UI-R2 candidate | `55E6883CC303AE5AD8D22EDD3C8A7E9344C13498F6623A79F4D5D1D5DF877CD8` |
| Earlier candidate | `830A4161DBE8C5EFAFDC6DCA19B8FE20571D057A5B97C8F5617EE21DE47A672D` |
| Original ISO | `EC287E1B8FF0FCD59E7DFDF3C9A0B95BA83D133B2AE3A9EF64F8F54E44AC7BAB` |
| Official Microsoft source ISO | `BD4307DF32BC8AF33B39CCECB1174AEB345386630F89A2B86C7A4E36B55EA650` |

## Not validated

- No BAKA CPU, memory, wakeup, startup, game-overhead, FPS, frametime, or input-latency improvement was measured.
- The host preview sample is not an installed-image measurement and does not establish a release resource result.
- Windows SIM validation, clean installation, OOBE, installed desktop behavior, and security/update-restoration checks remain outstanding. Candidate Setup was observed in the new disposable VMware run but stopped at the missing TPM requirement.
- Candidate and official-source boot attempts reported the same EFI error in one Hyper-V environment; the root cause remains unresolved. This comparison does not prove that either image works or that the candidate alone is defective.
- Baka Browser execution, VMware game testing, and physical Intel/AMD testing were not performed. Physical hardware acceptance remains blocked.
- GitHub Actions [passed on commit `03ec01d`](https://github.com/OldcarryG/Baka-windows/actions/runs/40336218684): source-only preflight and isolated configuration, theme, profile, game-detection, monitoring, release-guard, and UI checks all succeeded. The [initial run](https://github.com/OldcarryG/Baka-windows/actions/runs/40334909765) failed because a clean checkout lacked ignored `Logs`/`Output` folders; the setup fix is included in the passing commits.

The candidate remains structurally validated but **not fully acceptance-tested**.
