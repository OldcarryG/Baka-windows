# Sanitized source validation evidence

**Run date:** 2026-10-26

**Scope:** source, configuration, and isolated desktop preview only. The installed Windows image was not tested in this run.

## Changes checked

- System-widget refresh interval changes now update the active polling timer after settings are applied.
- Top-bar monitor changes now reposition the bar after settings are applied.
- The WPF preview smoke now asserts both behaviors in its isolated temporary profile.
- The project preflight supports a source-only CI mode that marks unavailable external artifact checks as skipped. Default local preflight remains strict.

## Results

| Check | Result | Limits |
| --- | --- | --- |
| Full local project preflight | **Passed, 83/83** | Local pinned Windows media, servicing packages, and browser installer were present and checked. The unsigned browser installer was not executed. |
| Repository-safe project preflight | **Passed, 77 passed / 3 explicitly skipped** | Skips are limited to external Windows ISO bytes, servicing package bytes/signatures, and the excluded Baka Browser installer bytes/signature. Manifest and source checks still ran. |
| Clean source-only checkout | **Passed** | The repository-safe preflight and all seven isolated test scripts passed from an archive containing only staged Git files, with no `Source`, `Downloads`, `Output`, `Work`, or `Logs` directory at checkout. |
| BAKA Liquid WPF preview smoke | **Passed, 13 stages** | Runs on the development host using Windows' opaque backdrop fallback. Not installed Windows 11 Acrylic validation. |
| Theme contrast | **Passed, 20/20** | Required monochrome presets and optional Violet preset. |
| Desktop settings persistence and recovery | **Passed, 4/4** | Isolated temporary files. |
| Gaming-profile rollback and duplicate-instance guard | **Passed, 6/6** | Registry behavior simulated; no host profile registry changes. |
| CS2/TF2 process detection | **Passed** | Unit-level name matching only; no game was installed or launched. VALORANT remains excluded. |
| System monitoring data path | **Passed** | Values or explicit unavailable states were returned. This did not measure BAKA companion resource use. |
| Release output overwrite guards | **Passed, 2/2** | Existing workspaces and ISO destinations were rejected. |

Raw logs are retained in the local project `Logs/` directory. They are excluded from this repository because they contain host paths and machine-specific build details.

## Preserved artifact hashes

All hashes below were recalculated on 2026-10-26. No ISO was modified during this source remediation.

| Artifact | SHA-256 |
| --- | --- |
| Current BAKA Liquid UI-R2 candidate | `55E6883CC303AE5AD8D22EDD3C8A7E9344C13498F6623A79F4D5D1D5DF877CD8` |
| Earlier candidate | `830A4161DBE8C5EFAFDC6DCA19B8FE20571D057A5B97C8F5617EE21DE47A672D` |
| Original ISO | `EC287E1B8FF0FCD59E7DFDF3C9A0B95BA83D133B2AE3A9EF64F8F54E44AC7BAB` |
| Official Microsoft source ISO | `BD4307DF32BC8AF33B39CCECB1174AEB345386630F89A2B86C7A4E36B55EA650` |

## Not validated

- No BAKA CPU, memory, wakeup, startup, game-overhead, FPS, frametime, or input-latency improvement was measured.
- Windows SIM validation, candidate boot/Setup, clean installation, OOBE, installed desktop behavior, and security/update-restoration checks remain outstanding.
- Candidate and official-source boot attempts reported the same EFI error in one Hyper-V environment; the root cause remains unresolved. This comparison does not prove that either image works or that the candidate alone is defective.
- Baka Browser execution, VMware game testing, and physical Intel/AMD testing were not performed. Physical hardware acceptance remains blocked.
- GitHub Actions execution status is tracked on the repository's Actions page; local test results above do not stand in for a remote workflow result.

The candidate remains structurally validated but **not fully acceptance-tested**.
