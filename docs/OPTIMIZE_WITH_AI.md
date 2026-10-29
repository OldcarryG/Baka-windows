# Tune BAKA Windows for your PC with an AI coding tool

BAKA ships settings that are safe on every PC. The fastest settings depend on your exact CPU, graphics card, RAM, storage, monitor and network, so BAKA cannot pick them for you. An AI coding agent that can run commands on your PC can: Claude Code, Codex CLI, Gemini CLI, Cursor, Windsurf, Kiro, GitHub Copilot agent mode or similar.

## How to use it

1. Install the AI tool on the BAKA PC and open it in an **administrator** terminal (or with permission to run elevated commands).
2. Copy everything inside the box below and paste it as your first message.
3. Let it run its checks. It will show you a plan **before** changing anything. Answer its questions.
4. Approve the changes you want. Restart when it asks.
5. If anything feels worse, tell it "undo everything" or run the restore script it writes to `C:\ProgramData\BAKA\Tuning\Undo-Tuning.ps1`.

Keep the PC plugged in during the process. It takes about 15 to 40 minutes, most of it benchmarks.

## The prompt

```text
You are tuning a gaming PC that runs "BAKA Windows", a customized Windows 11 Pro 26H2 (build 26300).
Your goal: the best possible game performance and the lowest input and frame latency FOR THIS EXACT
HARDWARE, without breaking anything, without lowering security, and with every change reversible.

== What BAKA already does (do not redo or fight it) ==
- Power plan "BAKA Gaming" (based on Ultimate Performance): no core parking, no USB selective suspend.
- Game Mode on, hardware-accelerated GPU scheduling on, Game DVR / Game Bar off, raw mouse input
  (no pointer acceleration), Sticky/Filter/Toggle Keys prompts off, windowed-game optimizations on,
  SystemResponsiveness and network throttling tuned for games.
- Telemetry services and tasks off, ads/suggestions/Copilot/Recall off, AdGuard DNS (DoH) ad blocking.
- BAKA Desktop (C:\ProgramData\BAKA\Desktop\BakaDesktop.exe) replaces the taskbar. When a game runs it
  switches to the "Competitive Gaming" profile: hides its UI, removes its keyboard hook, closes the
  video wallpaper and trims its memory. Config: C:\ProgramData\BAKA\PerformanceProfiles.json,
  SystemTuning.json, GamePerformance.json. User settings: %LOCALAPPDATA%\BAKA\Settings\desktop-settings.json
  (edit only while BakaDesktop is closed, or use BAKA Settings).
- "Restore BAKA System Tuning" undoes BAKA's own tuning (backup: C:\ProgramData\BAKA\SystemTuningBackup.json).

== Hard rules ==
1. NEVER disable or weaken: Windows Defender, the firewall, SmartScreen, Windows Update (you may
   schedule it), Secure Boot, TPM, BitLocker, VBS/HVCI/Memory Integrity, core isolation, UAC,
   Spectre/Meltdown mitigations, or DEP. Many anti-cheat systems (Vanguard, FACEIT, EA AC,
   BattlEye, EAC) need some of these, and they protect the user.
2. NEVER install drivers, BIOS updates, overclocking tools or "optimizer" apps without asking first,
   and only from the hardware maker's official site. NEVER overclock or undervolt without explicit
   permission, and never raise voltages.
3. NEVER delete system files, remove Windows components, or edit anything under C:\Windows by hand.
4. BEFORE changing anything: create a System Restore point ("Before AI tuning") and write every
   current value you will change to C:\ProgramData\BAKA\Tuning\before.json. Write
   C:\ProgramData\BAKA\Tuning\Undo-Tuning.ps1 that restores exactly those values, and test that it
   parses. Every change must be a registry value, a service start type, a power setting (powercfg),
   a scheduled task state, a driver control-panel setting, or a per-app setting that the undo script
   can put back.
5. No placebo. Do not apply a tweak because a forum says so. Only apply a change if (a) Microsoft or the
   hardware vendor documents it, or (b) you measured a real improvement on THIS PC. Known placebo or
   harmful on Windows 11 24H2+ (do not apply): disabling HPET in BIOS/bcdedit "useplatformclock",
   "disabledynamictick", "tscsyncpolicy", Win32PrioritySeparation hacks, removing the pagefile,
   disabling Superfetch/SysMain on SSD-only systems as a "fix", random "network throttling" registry
   packs, "timer resolution" services that force 0.5 ms all the time, disabling all services.
6. Show me a plan as a table (change, why, expected effect, risk, how to undo) and WAIT for my
   approval before applying. Apply in small groups and measure after each group.
7. Keep a log of every command you run in C:\ProgramData\BAKA\Tuning\log.txt.

== Step 1: inventory (read-only) ==
Collect and show me a short summary:
- CPU model, cores/threads, hybrid (P/E cores) or not, base/boost clocks, current power plan and its
  processor settings (powercfg /q), thermal state under load if you can read it.
- GPU(s): model, driver version and date, VRAM, which GPU each monitor uses, ReBAR/SAM status if
  readable, HAGS state.
- RAM: total, speed it RUNS at vs. its rated speed (Win32_PhysicalMemory ConfiguredClockSpeed vs
  Speed) - if it runs below rating, tell me XMP/EXPO is probably off in BIOS (I change BIOS myself).
- Storage: each disk, NVMe/SATA/HDD, free space, TRIM on, where games are installed.
- Monitors: resolution and refresh rate CURRENTLY SET vs. maximum supported (a 144/165/240 Hz monitor
  left at 60 Hz is the most common big loss). G-Sync/FreeSync/VRR availability.
- Network: adapter, link speed, Wi-Fi or Ethernet, driver date, interrupt moderation, power saving.
- Mouse/keyboard polling rate if the vendor tool reports it.
- Startup apps and background processes using CPU/RAM at idle (Get-Process sorted by CPU over 60 s).
- Installed games (Steam: steamapps\libraryfolders.vdf; Epic: ProgramData\Epic\EpicGamesLauncher\
  Data\Manifests; others by folder) and their anti-cheat.
- BAKA's own state: BakaDesktop.exe --status "%TEMP%\baka-status.json" and its CPU/RAM.

== Step 2: baseline benchmark (before any change) ==
Measure and save to C:\ProgramData\BAKA\Tuning\baseline.json:
- Idle: 60 s average CPU %, RAM in use, process count, DPC/ISR load if you can (e.g. via
  "typeperf \Processor(_Total)\% DPC Time" and "% Interrupt Time").
- Input latency: time from SendInput key/mouse until a test window receives it (median, p99).
- Timer: real duration of Sleep(1) with default and 1 ms timer resolution.
- If a game with a built-in benchmark is installed (e.g. CS2 workshop benchmark, Cyberpunk 2077,
  Shadow of the Tomb Raider, F1, Forza Horizon), ask me to run it once and tell you average FPS and
  1% low, or capture frame times yourself with PresentMon (Intel, open source,
  https://github.com/GameTechDev/PresentMon) if I allow you to download it.
- Run each measurement 3 times and use the median; report the spread.

== Step 3: hardware-specific improvements to consider ==
Only those that apply to this hardware, each one measured:
- Monitor at its maximum refresh rate; VRR/G-Sync/FreeSync on; for NVIDIA: Low Latency Mode "On"
  (or Reflex in games that have it), Power management "Prefer maximum performance" only for games
  (per-app, not global). For AMD: Anti-Lag per game. For Intel Arc: latest driver, ReBAR required.
- GPU driver: if older than ~3 months, suggest the official update (ask first; use a clean install).
- Per-game GPU preference "High performance" on laptops/hybrid graphics (Settings > Display >
  Graphics, registry HKCU\Software\Microsoft\DirectX\UserGpuPreferences).
- Hybrid CPUs (Intel 12th gen+, some AMD): make sure the game runs on P-cores (Game Mode and Thread
  Director normally do this; only intervene if you measured a game on E-cores). AMD X3D CPUs: make
  sure the AMD chipset driver and "3D V-Cache performance optimizer" are installed so games use the
  cache CCD.
- RAM below rated speed: tell me to enable XMP/EXPO in BIOS (do not do it yourself).
- Storage: games on the fastest SSD, enough free space (>15%), DirectStorage-capable NVMe noted.
- Network (online games): Ethernet over Wi-Fi if possible; for the adapter, disable energy saving
  ("Energy Efficient Ethernet", "Green Ethernet"), keep interrupt moderation unless you measured
  a gain; do not touch TCP auto-tuning or Nagle globally.
- Background load you found in Step 1: offer to disable startup entries of apps I don't need (vendor
  RGB/updater tools that poll constantly are common), never Windows or security components.
- USB: mouse/keyboard on the CPU's USB ports, not a hub; polling 1000 Hz if the vendor tool allows.
- BAKA itself: if the user does not use them, BAKA Settings > Wallpaper > solid colour (no video),
  Settings > Appearance > Motion "Reduced", widgets off. Report BAKA's own CPU/RAM before and after.
- MSI (message-signaled interrupts) for the GPU/NVMe/network: only report whether they are already
  in MSI mode (they usually are); change only if not and if the driver supports it, with my approval.

== Step 4: apply, measure, report ==
- Apply approved changes in small groups. After each group: re-run the Step 2 measurements, compare
  with the baseline, and REVERT that group automatically if anything got worse by more than the
  measurement spread.
- At the end give me a table: setting, before, after, measured effect. Be honest: if something made
  no measurable difference, say so and offer to revert it.
- Save the final report to C:\ProgramData\BAKA\Tuning\report.md.

== Step 5: tell me what only I can do ==
List BIOS changes (XMP/EXPO, ReBAR, PBO/curve optimizer only if I want it, fan curves) and physical
changes (Ethernet cable, monitor cable/port, cooling) that would help, with the expected gain, but
do not claim gains you did not measure.
```

## What to expect

On a PC that was already set up well, the measurable gains are usually small (a few percent in FPS, less than 1 ms of input latency). The big wins come from mistakes the inventory step finds: a high-refresh monitor running at 60 Hz, RAM running below its rated speed, an old graphics driver, a game on a hard disk, or a vendor tool polling in the background. The prompt tells the AI to measure and to revert anything that does not help, so you should not end up with placebo tweaks.
