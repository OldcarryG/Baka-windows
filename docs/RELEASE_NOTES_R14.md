# BAKA Windows R14 (2026-10-29)

Windows 11 Pro 26H2 x64 (build 26300.9711) with BAKA Desktop, gaming and privacy tuning, and Baka Browser 1.6.2.

**Download:** MEGA_LINK

ISO: `BAKA-Windows-Gaming-Edition-26H2-x64-BakaDesktop-R14-20261029.iso`, 11,174,221,824 bytes, SHA-256 `80E4EB67F6F04C4449C40FDFB5158BD1B4F9C1227F83A9BFDFAA57125C53E51E`. Check it after downloading with `Get-FileHash <file>.iso` in PowerShell.

## What changed since R13

### 4K video wallpaper
- New player built on Windows' own Media Foundation (MFPlay). Video is decoded by the graphics card (DXVA) and drawn straight into a native window behind the desktop, instead of going through WPF. A 4K video now costs almost no CPU on a PC with a GPU.
- Formats: MP4, MOV, MKV, WebM, WMV, AVI with H.264, HEVC, VP9 or AV1, up to 4K and beyond if the graphics card decodes it. BAKA installs the free HEVC, VP9 and AV1 extensions at first sign-in.
- It plays only while you can see it: it pauses when any maximized or fullscreen window covers the desktop, on battery, and while the PC is locked. While a game runs it is closed completely (decoder and video memory freed) and continues where it was afterwards. Each can be switched off in Settings > Wallpaper.
- Fill crops the video to the screen without black bars; Fit shows it whole.
- A video Windows cannot decode (missing codec) falls back to the picture, and Settings > Wallpaper says why. A file that has sound but no decodable picture is treated as a failure too.
- `BakaDesktop.exe --wallpaper <file>` sets the background; `--video-test <file> <result.json>` checks whether this PC plays a file and how much CPU it costs.

### Lower input latency
- BAKA's keyboard hook (for the Windows key, Win+E, Win+S) is now **removed** while a game runs, not just switched off. A low-level hook sits in the path of every key press of every app, so with it gone no key press of the game passes through BAKA. It is installed again when the game closes.
- On the desktop the hook now runs on its own time-critical thread that does nothing else, instead of BAKA's UI thread. Before, a key press had to wait whenever BAKA was drawing: on the development PC, with BAKA's main thread busy, key presses were delayed by a median of 25 to 42 ms. With the new thread the median is 0.75 ms, the same as with no hook (0.66 to 0.71 ms). Turning off "Windows key opens Launchpad" in Settings removes the hook completely.
- BAKA's window-event hooks for the BAKA window buttons are also removed while a game runs.

### AI tuning prompt
- [docs/OPTIMIZE_WITH_AI.md](OPTIMIZE_WITH_AI.md): copy it into Claude Code, Codex, Gemini CLI, Cursor, Kiro or a similar agent on the BAKA PC. It inventories the hardware, benchmarks first, shows a plan, applies only changes it measured to help, never weakens security or anti-cheat requirements, and writes an undo script.

### GitHub page
- README lists every feature, a BAKA vs Windows table, the benchmark, input latency, video wallpaper results, requirements, first start, undo and FAQ.
- New [docs/BENCHMARK.md](BENCHMARK.md) with the full method, every score ratio, top processes per system, all latency runs, and the benchmark scripts in `Tests/Benchmark/`.

## Benchmark (final R14 ISO, Hyper-V, 10 minutes idle after restart)

| | Stock Windows 11 | BAKA Desktop mode | BAKA Gaming mode |
|---|---:|---:|---:|
| Score (100 = stock) | 100 | 99.4 | 101.7 |
| Score without idle CPU | 100 | 91.4 | 94.0 |
| Idle CPU | 5.5% | 2.6% | 2.9% |
| Memory in use | 2066 MB | 2539 MB | 2579 MB |
| Running services | 97 | 90 | 89 |
| BAKA Desktop's own CPU / memory | – | 0.1% / 57 MB | 0.01% / 34 MB |
| CPU / memory copy / disk write | 1871 / 18,088 / 1620 MB/s | 1871 / 17,517 / 1509 MB/s | 1870 / 17,803 / 1619 MB/s |
| Boot time | 22.0 s | 27.8 s | |
| Key latency, median / 99th percentile | 0.225 / 0.386 ms | 0.331 / 4.219 ms | 0.243 / 0.555 ms |
| Ads blocked / privacy checks | 2 of 131 / 0 of 12 | 131 of 131 / 12 of 12 | 131 of 131 / 12 of 12 |

Stock's idle CPU was mostly Microsoft Defender scanning; idle CPU varies between rounds (in R13 BAKA was higher). The BAKA VM still had WhatsApp, Spotify and To Do running from the Store test, which accounts for part of the higher memory. In earlier R14 installs the Desktop-mode 99th percentile key latency was 0.74 to 1.19 ms.

## Tests

| Test | Result |
|---|---|
| ISO structural validation (Setup signature, Windows 11 Pro 26300.9711, pinned Baka Browser 1.6.2, BAKA payload) | Passed |
| Fresh install of this exact ISO in a Hyper-V VM (Gen 2, Secure Boot, vTPM) | Passed: no account page, automatic sign-in, BAKA desktop up about 11 minutes after Setup started |
| Desktop state (`--status`) | Taskbar hidden, menu bar and dock, dock 58 px, folders open in BAKA Files, ad-block DNS on, Edge not installed, WebView2 and Baka Browser installed |
| BAKA Desktop self-test in the VM | 50 of 50 |
| BAKA Desktop self-test on the development PC | 50 of 50, 5 runs |
| Project configuration (96 checks) | Passed |
| BAKA buttons, dragging, tray (simulated mouse in the VM) | Notepad, Calculator, Media Player: buttons present, follow drags, minimize, maximize, close. All windows drag exactly. Tray button works. System Information keeps its own buttons by design |
| Store apps | Store opens; WhatsApp, Microsoft To Do, Spotify install and start; Netflix needs Edge (0x80073D31) |
| 4K video wallpaper, development PC (RTX 5060) | H.264 4K 0.2% CPU and loops, VP9 4K 2%, AV1 4K 0%; HEVC needs the HEVC extension, which BAKA installs |
| 4K video wallpaper, VM (no GPU) | H.264, HEVC and VP9 4K play; AV1 4K too slow for software decoding. On the real desktop: starts at 3840×2160, pauses when Notepad is maximized (CPU 37% → 0.05%), plays again when it closes, is closed in Gaming mode (0% CPU) and comes back after |
| Key latency with BAKA busy (development PC, 200 keys per run, BAKA's main thread kept busy like a frame being drawn) | No hook: median 0.66 to 0.71 ms. Old design (hook on the UI thread): median 25 to 42 ms and most key presses held more than 50 ms. New design (own thread): median 0.75 ms, the same as no hook within run-to-run noise |
| Key latency in the VM (median / 99th percentile) | Stock 0.225 / 0.386 ms. Final R14 ISO: BAKA Desktop mode 0.331 / 4.219 ms, Gaming mode (no hook) 0.243 / 0.555 ms. Three earlier R14 installs: Desktop 0.30 to 0.37 / 0.74 to 1.19 ms, Gaming 0.21 to 0.30 / 0.62 to 1.54 ms. Differences of this size also appear between two runs of the same system in the VM |
| Ad blocking / privacy | 131 of 131 test domains blocked; 12 of 12 privacy checks |
| Benchmark (final R14 ISO, see above) | Score 99.4 Desktop mode, 101.7 Gaming mode (100 = stock) |

## Not done or not verified

- **Game FPS and frame times**: not measurable in a VM without a GPU. Use the AI tuning prompt to measure on your PC.
- **Mouse latency and 1 ms timer** could not be measured in the Hyper-V VM (the virtual mouse does not deliver injected moves, and the VM keeps a 10 to 15 ms timer). Key latency was measured.
- **AV1 4K in the VM**: with no GPU, the VM's 4 virtual cores cannot decode 4K AV1 in real time, so it did not play there. It played on the development PC (RTX 5060) at under 1% CPU. Older GPUs without AV1 decoding (before NVIDIA RTX 30, AMD RX 6000, Intel Arc / 11th gen) should use H.264, HEVC or VP9 for 4K wallpapers.
- **Idle CPU** changes between rounds: lower than stock in R14 (2.6% vs 5.5%), higher in R13 (13.5% vs 3.6%). BAKA Desktop itself uses 0.1% or less.
- **Memory** is about 0.5 GB higher than stock in the R14 round (partly the Store test apps).
- **Netflix** and other Store apps that need Edge do not install while Edge is removed.
- **Media keys**: not testable in the VM (no sound device).
