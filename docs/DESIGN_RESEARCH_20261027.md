# BAKA R3 design and optimization research

Updated: 2026-10-27

## Research used

| Reference | What was studied | License / use decision |
| --- | --- | --- |
| [Ghost Spectre](https://ghostspectre.the-ninja.jp/20H2.X64.html) and [Ghost Toolbox guide](https://www.ghostspectre.org/blog/ghost-toolbox-tutorial-drivers-updates) | Modular toolbox, optional feature restoration, visible gaming-oriented controls, and the warning that aggressive removals affect Store, printing, updates, and compatibility. | Ghost Spectre is not an open-source code dependency in this project. No Ghost code, branding, wallpaper, installer, or binaries were copied. BAKA uses the product idea of a visible reversible control center only. |
| [AtlasOS](https://github.com/Atlas-OS/Atlas) and [performance documentation](https://www.mintlify.com/Atlas-OS/Atlas/features/performance) | Open playbook structure, documented tradeoffs, benchmark discipline, background-app policy, Game DVR policy, and the principle of avoiding placebo tweaks. | Atlas playbook is GPL-3.0. No Atlas source was copied or linked into the runtime. The concepts are independently implemented in BAKA's PowerShell modules; the project remains separately licensed and documents its own changes. |
| [Microsoft system backdrops](https://learn.microsoft.com/en-us/windows/apps/develop/ui/system-backdrops) and [DWM backdrop API](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/ne-dwmapi-dwm_systembackdrop_type) | Mica for long-lived surfaces, Acrylic for transient surfaces, transparent layers, and supported fallback behavior. | Microsoft documentation is referenced, not redistributed. BAKA calls the documented DWM attribute and falls back to opaque surfaces when Windows rejects it. |
| [Fluent System Icons](https://github.com/microsoft/fluentui-system-icons) | Consistent modern icon proportions and filled/regular visual hierarchy. | The icon repository is MIT licensed, but BAKA R3 does not redistribute its files. It uses Windows' installed Segoe MDL2 Assets so the ISO has no extra icon payload or attribution burden. |

## R3 design direction

The earlier R2 surface was a floating utility panel: it exposed useful controls, but it left the Windows desktop visually dominant and did not communicate that BAKA was the product. R3 makes the companion's first-run state a BAKA Arena dashboard with a clear visual hierarchy:

- a dark-glass canvas and custom BAKA wallpaper;
- cyan/violet/green status accents for actions, gaming state, and telemetry;
- a hero surface that explains the product and starts Competitive Gaming;
- explicit Desktop, Competitive, and Benchmark cards;
- live Windows-backed CPU, memory, GPU-engine, and system-drive telemetry;
- a visible safe-tweak ledger instead of unexplained “performance” claims;
- an Arena home action in the dock, a control-center action, and a real settings editor;
- event-driven entrance, sheen, hover lift, and dock-wave animation with reduced-motion and gaming suppression.

The dashboard is intentionally a BAKA-owned layer over Explorer. Explorer, the Windows taskbar, notifications, security, recovery, Windows Update restoration, and servicing remain native. This keeps the visual identity strong without replacing the shell or patching protected Windows binaries.

## Optimization decisions

Competitive Gaming now applies and transactionally restores four user-level values:

1. `AutoGameModeEnabled=1` — asks Windows Game Mode to recognize the gaming state.
2. `GlobalUserDisabled=1` under BackgroundAccessApplications — prevents background app execution for the user while gaming.
3. `GameDVR_Enabled=0` — removes Game DVR capture overhead for the competitive profile.
4. Existing transparency and optional animation values — removes desktop composition work while gaming.

The profile does **not** change the power plan, scheduler policy, CPU affinity, HPET, MSI mode, driver settings, Defender, SmartScreen, recovery, Windows Update servicing, or VALORANT handling. Every value is captured with its original type and existence state and restored when Desktop is selected or during startup recovery. Benchmark deliberately records conditions without changing Windows settings.

## Evidence boundary

Source evidence currently validates configuration, reversible profile transactions, game detection, UI motion, and Windows performance-counter reads. The host preview sample is not a gaming benchmark. No FPS, frame-time, input-latency, or hardware-compatibility improvement is claimed until the rebuilt R3 image is installed on a disposable vTPM-capable VMware guest and measured against the same stock guest.
