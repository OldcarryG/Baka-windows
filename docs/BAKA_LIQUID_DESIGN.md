# BAKA Liquid desktop design

Updated: 2026-10-27

## R3 Arena direction

R3 changes the first-run experience from a small utility overlay into a BAKA-owned gaming desktop layer. BAKA Arena is the visible home surface: a hero, profile cards, safe-tweak ledger, live telemetry, control center, and animation system are shown together. The dock exposes Arena, pinned apps, Control, and Customize. The R2 companion remains the implementation base, but R3's dashboard is the product entry point. Research and third-party license decisions are recorded in `docs/DESIGN_RESEARCH_20261027.md`.

## R5 Pop Glass (default)

Inspired by SekaiPop's "one block everywhere" rule and Apple's liquid glass. Theme `BAKA Pop Glass` (`style: PopGlass`) adds `ring`, `shadow`, and `accent2` tokens.

- **Keycap block:** rounded pill template on every button, 1.5 px cream ring, `DropShadowEffect` with blur 0 and direction 270 (hard shadow straight down). Press animates the shadow depth to 1 and sinks the key; release springs back with an elastic ease.
- **Liquid glass:** stronger top specular band in the glass brush, an inner top-lit rim border, and a pointer-following radial highlight. Opaque fallback, high contrast, and remote sessions keep the existing rules.
- **Motion:** pop-in (elastic scale from 0.62), swallow-out (shrink + fade), phone-rise for the Quick Panel, phone-rotate for Settings, and a two-hop dock launch bounce. Only event-driven animations are used; Gaming and Benchmark suppress motion and keycap effects.
- **Quick Panel phone:** 40 px device corners, notch with status dot, app-style 88×82 tiles for Windows quick actions, scrollable on short screens.
- Arena now appears once on first run and only returns after a game if it was open before.

The preview smoke asserts the default theme, keycap ring/hard shadow, press/release, liquid light and rim, launch bounce, and the pop, phone-rise, and phone-rotate entrances (23/23 stages).

## R4 Liquid Shell direction

R4 turns the dock into the everyday taskbar while Explorer stays the shell:

- **Start and open windows.** The dock gains a Start button (opens Windows Start/search) and an open-window strip that lists up to eight running apps with their real icons. Clicking one focuses, restores, or minimizes it.
- **Native taskbar auto-hide.** While BAKA runs, the Windows taskbar is set to auto-hide through the documented `SHAppBarMessage` API. The prior state is saved and restored when BAKA exits or the option is turned off. The taskbar, tray, and notifications stay reachable at the screen edge.
- **Wallpaper freedom.** Settings > Wallpaper accepts any picture (JPG/PNG/BMP/GIF/WebP), a looping video (MP4/MOV/WMV/AVI/MKV/WebM, using Windows codecs), or a solid color, with Fill/Fit/Stretch/Center/Span. Video renders in a borderless WPF `MediaElement` re-parented into the desktop's wallpaper host (`WorkerW`) so it sits behind the desktop icons. It is muted by default and pauses during Gaming and Benchmark profiles. "Default" leaves the wallpaper under Windows Settings control.
- **Custom dock icons.** Any pinned app can use a user-chosen PNG/JPG/BMP/ICO/GIF. Apps added without a glyph show their executable's own icon.
- Older saved settings upgrade automatically: missing wallpaper, taskbar, and icon fields get defaults without touching existing values.

Limits: video wallpaper covers the primary display only, and if Explorer restarts the video must be re-applied from Settings (or by restarting BAKA). If Windows exposes no wallpaper host or the codec is missing, BAKA keeps a static background and logs the reason. These behaviors still need installed Windows 11 verification.

## Architecture

BAKA Liquid is one optional Windows Presentation Foundation companion running in a single-instance, single-threaded apartment process. Explorer remains the Windows shell and the Windows taskbar, notifications, security, servicing and recovery remain under Windows control. The companion owns the floating dock, optional status bar, Quick Panel, settings editor and widgets; it does not install a replacement shell or patch protected system binaries.

The interface reads its appearance and widget defaults from `Config/DesktopSettings.default.json` and `Config/DesktopThemes.json`. User settings are validated and saved separately from gaming-profile state. Invalid settings recover from the last valid backup or reviewed defaults. The profile module captures previous registry values and types, records interrupted transitions, rolls back a failed transition and rejects duplicate companion instances.

The installer staging script places the companion, settings modules, manifests, and both wallpaper variants together under `ProgramData\BAKA`. The newly generated silver-ribbon wallpaper is the first-logon default; the procedural 4K black-glass design remains the fallback. The UI-R2 candidate built on 2026-10-24 contains the refinements below; installed Windows 11 rendering still needs acceptance validation.

## Shared design tokens

| Token | Use |
| --- | --- |
| Canvas, surface, raised surface | Near-black desktop panels and layered control surfaces |
| Text, muted text | White primary labels and silver secondary labels |
| Border | Silver outline that remains visible against dark panels |
| Accent | Monochrome silver by default; user-configurable accent, including purple |
| Glass rim and highlight | Fine silver edge, layered translucent fill, and one event-driven moving light band |
| Segoe UI Variable | Shared interface typography |
| 20 px outer / 12 px widget corners | Consistent rounded panels and compact cards |
| Opaque fallback | High contrast, remote sessions, unsupported DWM backdrop, or reduced effects |
| Reduced motion | No hover lift or backdrop shadow in Competitive Gaming, Benchmark, high contrast, or user-selected reduced-motion mode |

Theme values and contrast checks live in `Config/DesktopThemes.json` and `Tests/Test-DockContrast.ps1`.

## Presets

- **BAKA Obsidian** — pure black surfaces with silver controls and restrained translucency.
- **BAKA Liquid** — the default. Layered black-and-silver surfaces, Windows Desktop Acrylic on companion windows, a silver rim and visible one-shot light sweep, spring-soft panel entrances, pointer-focused dock-wave magnification, and running-app dots.
- **BAKA Violet** — black surfaces with a controlled purple accent.
- **BAKA Minimal** — opaque black surfaces with reduced motion.
- **BAKA Gaming** — black and silver surfaces, low-intensity Mica, and no theme animation for a restrained gaming desktop.

Desktop Acrylic is requested for companion windows through the documented Windows 11 DWM system-backdrop API; Windows identifies the transient-window value as Desktop Acrylic. If a backdrop request fails, the companion switches every existing surface and control to one consistent opaque palette. The Windows 10 development host returns `0x80070057`, so preview smoke exercises the fallback. Actual Acrylic rendering on the target Windows 11 image still requires installed-guest verification.

## Surfaces and behavior

- **Dock:** configurable pinned apps with Segoe MDL2 icons, accessible names, running-app dots, alignment, size, spacing, auto-hide and a spring-eased pointer wave. The focused icon scales to 1.26, adjacent icons to 1.13, and the next pair to 1.05. The icon-size setting changes the icon tile itself and the dock's height.
- **BAKA Files:** the default dock Files target opens the BAKA file-management workspace rather than launching an Explorer window. It has Home/Desktop/Downloads/Documents/Pictures navigation, real filesystem drives, address navigation, back/up controls, current-folder search, details listing, double-click directory navigation, and registered Windows application opening. Explorer remains alive as the recovery shell and for native Windows controls; BAKA Files owns normal BAKA file browsing.
- **Status bar:** optional BAKA identity, profile, network availability, date/time, battery when the host reports one, and Quick Panel access. The native taskbar remains available.
- **Quick Panel:** profile switching, automatic CS2/TF2 detection resume, theme selection, widget visibility and links to the corresponding Windows Settings pages. Hardware toggles open Windows controls; the panel does not pretend that a setting changed when it did not.
- **Settings editor:** Appearance, Dock, Top bar and Widgets pages; appearance previews, dock configuration, user-configurable pinned apps, widget visibility/layout, save, reset, import and export, restore-previous, and unsaved-change handling.
- **Widgets:** clock/date, calendar, system monitor and optional local notes. Clock and calendar are local. System values come from Windows performance data; unavailable sensors are reported as unavailable. Weather and media controls are deferred.
- **Motion:** panels rise, scale, tilt slightly, and settle with a spring ease. A brighter diagonal silver band sweeps across the opened surface once. Dock hover creates a magnification wave and lifts the icon tile. These effects run on interaction; no animation loop runs at idle.
- **Profiles:** Desktop uses the richer glass and motion; Competitive Gaming and Benchmark hide widgets, use opaque surfaces and suppress optional motion while leaving Windows' scheduler, Balanced power baseline and security settings unchanged. Reduced-motion disables animation while retaining supported static glass; high-contrast and remote sessions disable glass and motion.

System-monitor reads run only while the System widget is visible in Desktop mode. Hiding it or switching to another profile stops periodic reads. The initial refresh interval is 3 seconds and can be changed from 2 to 30 seconds. Competitive Gaming and Benchmark use opaque surfaces and suppress the animation and widget work.

Saving a new system-monitor interval now updates the running widget timer immediately. Saving a top-bar display selection now repositions the bar on that monitor without requiring a companion restart. The Windows preview smoke checks both settings paths; installed Windows 11 multi-monitor behavior still needs acceptance testing.

## Safe source preview

Run `Tests/Test-BakaCompanionPreview.ps1` to launch the WPF surfaces with temporary settings and a simulated registry adapter. The test exercises visibility, profile changes and restoration, all presets, widget polling, settings live preview/save, system metric retrieval, and clean shutdown. It writes a JSON test record to `Logs` and never changes the host's Windows profile registry.

To view the isolated companion without the automated smoke sequence, launch `Scripts/Runtime/BakaCompanion.ps1` with `-Preview` from Windows PowerShell 5.1 using `-STA`. Preview settings are stored in a temporary directory.

## Not in this implementation

The Quick Panel does not replace Windows' network, Bluetooth, audio, microphone, brightness, night-light, power or notification interfaces. It opens the related Settings page. There is no custom notification infrastructure, global Win32 title-bar replacement, weather provider, media integration, vendor GPU temperature reader, or lock-screen replacement. All of these require separate capability and compatibility work.

The preview smoke now asserts that the dock retains the shared glass brush on supported systems, the settings content leaves the backdrop visible, the dock and tile create animated transforms, profile transitions suppress motion, and the fallback is consistent. The Windows 10 development host uses opaque fallback; this does not prove Windows 11 Acrylic appearance. The companion still needs installed-ISO testing at multiple display scales, after sleep/wake, under games, and against the requested idle CPU and memory budgets.

## UI-R2 refinements

The first preview looked too much like an opaque panel with a dock. The root settings panel had been painting over the backdrop, and dock styling had replaced the shared translucent brush. Both surfaces now keep the supported backdrop visible. When DWM rejects Acrylic, fallback updates every open BAKA surface and its child controls to a consistent opaque palette rather than leaving some existing windows in a stale gradient state.

The Liquid preset now has three coordinated, interaction-driven effects: a short spring entrance with a narrow diagonal silver sheen, a pointer-centered dock magnification wave with a tile lift, and small running-application indicators. Motion is event-driven and does not run an idle animation loop. Gaming and Benchmark suppress these effects. Dock size changes now resize its icon tiles and control height together, preventing the old fixed-height clipping at larger sizes.

The new original silver-ribbon wallpaper is `Assets/Wallpapers/BAKA-Liquid-Ribbon.png` (1672 × 941; SHA-256 `CE3BD720F1048E496A336B84C1458866C1E1DD83A2A8BDEA108A37ABA57D663C`). The existing procedural 4K black-glass wallpaper remains available. Provenance is recorded in `Assets/ASSET_SOURCES.md`.

The updated source preview passed 15 stages with no runtime errors on the Windows 10 development host, including glass coverage, the sheen, dock wave, fallback consistency, profile motion suppression, BAKA Files workspace readability/close, and clean shutdown. Because that host does not provide the requested Windows 11 backdrop, this result validates the fallback and interaction logic only. The preserved R2 image still requires an installed Windows 11 visual check; no FPS, latency, or installed-shell performance improvement is claimed.

## Source reliability remediation — 2026-10-27

- Action buttons now display the supplied Segoe MDL2 glyph beside the accessible text label; the glyph parameter is no longer silently ignored.
- Manual Desktop, Competitive Gaming, and Benchmark selections stop the four-second automatic process-detection timer. Automatic detection resumes only when the user selects automatic mode.
- Profile presentation failures attempt to restore the previous backend profile and UI state, while the existing registry transaction continues to provide rollback for Windows values.
- Profile polling now tolerates a Quick Panel that has not been created yet. Settings import catches malformed or invalid files and reports the failure without replacing the current configuration.
- The smoke timer is initialized before shutdown handlers can inspect it, avoiding a strict-mode cleanup failure.

The latest source smoke passed 15/15 stages. The latest R3 host-only preview sample averaged 0.583% CPU (0.729% maximum) and 218.47 MiB working set (221.10 MiB maximum) over 10 two-second samples after a three-second warm-up; the CPU target was met in that sample, while the 150 MiB memory target was not. The measurement is not installed-image acceptance evidence.
