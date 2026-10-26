# BAKA Windows Gaming Edition

PowerShell-driven Windows 11 Pro x64 deployment project with Explorer as the shell, reversible gaming profiles, and the BAKA Liquid WPF desktop companion.

## Release status

A separate BAKA Liquid UI-R2 candidate has been built in the authorized Windows 11 build VM and passed structural ISO validation. It is **not fully acceptance-tested**: VM boot/Setup display is unverified because console capture timed out; Windows SIM, install/OOBE, installed desktop behavior, runtime security/update restoration, and game tests remain outstanding.

- Candidate: `Output/BAKA-Windows-Gaming-Edition-26H2-x64-BakaLiquid-UI-R2-20261024.iso`
- SHA-256: `55E6883CC303AE5AD8D22EDD3C8A7E9344C13498F6623A79F4D5D1D5DF877CD8`
- Size: 11,164,844,032 bytes

The original ISO and existing candidate remain unchanged:

- Candidate: `Output/BAKA-Windows-Gaming-Edition-26H2-x64-20261016.iso` — SHA-256 `830A4161DBE8C5EFAFDC6DCA19B8FE20571D057A5B97C8F5617EE21DE47A672D`
- Original: `Output/BAKA-Windows-Gaming-Edition-26H2-x64.iso` — SHA-256 `EC287E1B8FF0FCD59E7DFDF3C9A0B95BA83D133B2AE3A9EF64F8F54E44AC7BAB`

The earlier candidate does not contain the BAKA Liquid companion. The new candidate is the current artifact for review, not an accepted final release.

## BAKA Liquid desktop

One optional WPF companion provides the floating dock, optional status bar, Quick Panel, visual settings editor, five themes, and desktop widgets. BAKA Liquid is the default, with Windows Desktop Acrylic, layered silver highlights, brief spring-soft panel entrances, a one-shot glass light sweep, and pointer-focused dock magnification. Explorer remains the shell. Competitive Gaming and Benchmark use opaque surfaces and hide optional widgets and motion while preserving Windows’ Balanced power baseline, native scheduling, security, and reversible profile backend.

Themes: BAKA Obsidian, BAKA Liquid, BAKA Minimal, and BAKA Gaming are the required presets; BAKA Violet remains an optional accent variant. Core widgets: clock/date, calendar, Windows-backed system monitor, and optional local notes. Weather and media controls are deferred. Hardware controls open native Windows Settings pages rather than simulating a toggle.

Read `docs/BAKA_LIQUID_DESIGN.md` for architecture and limitations.

## Source checks

Run the isolated source checks from the project root on Windows:

```powershell
./Tests/Test-DesktopConfiguration.ps1
./Tests/Test-DockContrast.ps1
./Tests/Test-GameDetection.ps1
./Tests/Test-GamingProfiles.ps1
./Tests/Test-SystemMonitoring.ps1
./Tests/Test-ReleasePipelineGuards.ps1
./Tests/Test-BakaCompanionPreview.ps1
./Tests/Test-ProjectConfiguration.ps1
```

The full project preflight requires the pinned source image, signed servicing packages, and the pinned Baka Browser installer to be present locally. These external inputs are excluded from GitHub. For a checkout without them, use `./Tests/Test-ProjectConfiguration.ps1 -SkipExternalArtifactChecks`; the skipped checks are reported explicitly. The isolated preview and release-guard checks do not build or modify Windows.

See `docs/GITHUB_WORKFLOW.md` for the branch, review, GitHub Actions, and release workflow.

## Build and acceptance

The build pipeline accepts explicit input and output paths and refuses to overwrite an existing workspace or ISO. The R2 build used the authorized Windows 11 technician VM and current ADK toolchain; any later rebuild must use a new output path and preserve the recorded artifacts.

The current candidate still requires a verified VM boot, Windows SIM validation, a clean UEFI installation and OOBE, installed runtime/security/update-restoration tests, and resource measurements. CS2/TF2 gameplay and physical gaming performance remain unverified. VALORANT is excluded. No BAKA FPS, frametime, or input-latency gain is claimed.

See `docs/BUILD_STATUS.md`, `docs/ACCEPTANCE_MATRIX.md`, and `docs/PROGRESS_REPORT.md` before using an ISO.

The requested VMware stock-vs-BAKA comparison is being tracked separately in `docs/VMWARE_AB_COMPARISON.md`. VMware is not installed yet; no comparison screenshots, game runs, or resource measurements have been produced.
