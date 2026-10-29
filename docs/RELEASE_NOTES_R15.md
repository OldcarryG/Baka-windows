# BAKA Windows R15 (2026-10-29)

Windows 11 Pro 26H2 x64 (build 26300.9711) with BAKA Desktop, gaming and privacy tuning, and Baka Browser 1.6.2. R15 fixes boot, shutdown and keyboard problems found by measuring R14 against stock Windows 11.

**Download:** MEGA_LINK

ISO: `ISO_NAME`, ISO_SIZE bytes, SHA-256 `ISO_SHA`. Check it after downloading with `Get-FileHash <file>.iso` in PowerShell.

## What was wrong in R14, and what R15 changes

Each problem below was found by measuring, and each fix was measured again in the same Hyper-V VM. Full numbers: [BENCHMARK.md](BENCHMARK.md#r15-boot-shutdown-and-key-latency).

| Problem in R14 | Cause | R15 |
|---|---|---|
| **Power-on after a shutdown was a full cold boot.** | BAKA turned hibernation off on desktops, which also turns off Fast Startup. Stock Windows keeps Fast Startup on. | Fast Startup stays on, as on stock Windows. The hibernation file is the small "reduced" type that only Fast Startup uses. Restart is a full boot either way. |
| **The BAKA desktop appeared about 4 s after Explorer.** | BAKA Desktop was started from the Run list, which Explorer only processes after its own start-up. | BAKA Desktop starts from a sign-in task, at the same time as Explorer. Desktop ready 9.5 s after boot start instead of 11.1 s. |
| **Every startup app started at once with the desktop.** | R14 set Explorer's startup delay to 0 for all apps. | Other startup apps (Steam, Discord, ...) keep Windows' own delay again, so the desktop comes up first, as on stock Windows. |
| **Every shutdown was logged as a BAKA Desktop crash**, and the next sign-in showed the Windows taskbar until BAKA hid it. | Windows ends the desktop at sign-out (exit code 0x40010004). The watchdog treated that as a crash and put the Windows taskbar back while Windows was shutting down. | BAKA Desktop exits cleanly when the session ends and changes nothing. 0 crash entries in 10 test restarts (R14: one per restart). |
| **The first Windows key press took 0.6 s** before the Launchpad appeared. | The full-screen Launchpad, with a tile for every app, was built again on every press. | It is built once in the background after sign-in and then only shown: 16 to 19 ms from key release to Launchpad in front (VM). |
| **The keyboard hook made Windows wait for BAKA on every key press.** | A low-level keyboard hook is in the path of every key of every app. | BAKA now only listens (raw input) and does not hold any key. Explorer's own Win+E, Win+S and Win+Q are switched off with Explorer's documented `DisabledHotkeys` setting so BAKA can take them without hooking. |
| BAKA Desktop compiled its code again at every sign-in. | .NET Framework compiles an app when it starts unless a native image exists. | A native image (NGen) is created once at first sign-in. |

## Measured (Hyper-V VM, same host, 4 vCPU, 6 GB)

| | Stock Windows 11 | BAKA R14 | BAKA R15 |
|---|---:|---:|---:|
| Key latency on the desktop, median | 0.27 to 0.28 ms | 0.33 to 0.37 ms | **0.29 to 0.33 ms** |
| Key latency while gaming, median | (same as desktop) | 0.27 to 0.28 ms | **0.26 to 0.27 ms** |
| Windows boot event (restart), total | 23.0 to 28.5 s | 27.0 to 29.4 s | 27.0 to 28.8 s |
| Explorer started, after boot start | 7.2 to 7.7 s | 7.0 to 7.2 s | 6.9 to 7.1 s |
| Desktop ready, after boot start | taskbar comes with Explorer (7.2 to 7.7 s) | 10.9 to 11.3 s | **8.8 to 9.6 s** |
| Shutdown (restart command to new boot) | 5.6 to 17.5 s | 6.3 to 23.4 s, crash logged | **5.7 to 7.1 s**, no crash |
| Win key to start surface in front | 30 to 46 ms (Start) | 598 ms first press, then 30 ms | **16 to 19 ms** (Launchpad) |
| Win+E to a file window | 175 to 258 ms (File Explorer) | not measured | **16 to 64 ms** (BAKA Files) |
| Fast Startup on power-on | on | **off** | on |

FRESH_INSTALL_NOTE

What these numbers mean:
- **Gaming mode equals stock** for key latency: BAKA has nothing in the keyboard path while a game runs.
- **On the desktop BAKA adds 0.02 to 0.06 ms per key** (median 0.29 to 0.33 ms vs stock 0.27 to 0.28 ms), down from about 0.08 ms in R14. This is the cost of listening for the Windows key; a human cannot feel it, but it is not zero. Turning off Settings > Windows > "Windows key opens Launchpad" removes it: 0.26 to 0.27 ms, the same as stock.
- **Boot itself is the same as stock** (the Windows boot event differs by less than the run-to-run spread of the VM). The BAKA desktop is now ready about 1.5 s after Explorer starts.
- **Fast Startup could not be tested in the VM**: Hyper-V's virtual firmware does not support hibernation, so the stock VM did full boots too. On a real PC, power-on after a shutdown now uses Fast Startup like stock Windows; Microsoft and PC makers describe this as noticeably faster than a full boot.

## Research behind the changes

- Microsoft's documentation for low-level keyboard hooks (`LowLevelKeyboardProc`) recommends raw input instead of a low-level hook when an app only needs to watch the keyboard, because Windows does not wait for raw input.
- Explorer's per-user `DisabledHotkeys` value (HKCU\...\Explorer\Advanced) switches off chosen Win+letter shortcuts.
- [valleyofdoom/PC-Tuning](https://github.com/valleyofdoom/PC-Tuning) (latency tuning guide): measure every change, keep startup programs to a minimum, and prefer Windows' per-process timer behaviour. BAKA does not change the timer resolution, idle states, HPET or BCD settings.
- Fast Startup restores the saved kernel session instead of a full boot; Restart always does a full boot ([Windows Forum](https://windowsforum.com/threads/windows-fast-startup-when-to-disable-for-stable-boots.388491/), [HP](https://www.hp.com/us-en/tech-takes/software/how-to/how-to-optimize-fast-startup-windows.html)).

## Tests

TESTS_TABLE

## Not done or not verified

- **Fast Startup timing** on real hardware was not measured (not possible in Hyper-V).
- **Game FPS, frame times and mouse latency**: not measurable in the VM.
- The **first Windows key press right after sign-in**, before the background build has finished, can still take longer.
- **Netflix** and other Store apps that need Edge do not install while Edge is removed.
