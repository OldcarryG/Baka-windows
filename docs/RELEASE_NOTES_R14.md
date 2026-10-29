# BAKA Windows R14 (2026-10-29)

Windows 11 Pro 26H2 x64 (build 26300.9711) with BAKA Desktop, gaming and privacy tuning, and Baka Browser 1.6.2.

**Download:** MEGA_LINK

ISO: `BAKA-Windows-Gaming-Edition-26H2-x64-BakaDesktop-R14-20261029.iso`, 11,174,219,776 bytes, SHA-256 `96728B57215A4C3A28D76010771B0425D0D3673796BA860D61F405B247C2CE89`. Check it after downloading with `Get-FileHash <file>.iso` in PowerShell.

## What changed since R13

### 4K video wallpaper
- New player built on Windows' own Media Foundation (MFPlay). Video is decoded by the graphics card (DXVA) and drawn straight into a native window behind the desktop, instead of going through WPF. A 4K video now costs almost no CPU on a PC with a GPU.
- Formats: MP4, MOV, MKV, WebM, WMV, AVI with H.264, HEVC, VP9 or AV1, up to 4K and beyond if the graphics card decodes it. BAKA installs the free HEVC, VP9 and AV1 extensions at first sign-in.
- It plays only while you can see it: it pauses when any maximized or fullscreen window covers the desktop, on battery, and while the PC is locked. While a game runs it is closed completely (decoder and video memory freed) and continues where it was afterwards. Each can be switched off in Settings > Wallpaper.
- Fill crops the video to the screen without black bars; Fit shows it whole.
- A video Windows cannot decode (missing codec) falls back to the picture, and Settings > Wallpaper says why. A file that has sound but no decodable picture is treated as a failure too.
- `BakaDesktop.exe --wallpaper <file>` sets the background; `--video-test <file> <result.json>` checks whether this PC plays a file and how much CPU it costs.

### Lower input latency while gaming
- BAKA's keyboard hook (for the Windows key, Win+E, Win+S) is now **removed** while a game runs, not just switched off. A low-level hook sits in the path of every key press of every app, so with it gone no key press of the game passes through BAKA. It is installed again when the game closes.

### AI tuning prompt
- [docs/OPTIMIZE_WITH_AI.md](OPTIMIZE_WITH_AI.md): copy it into Claude Code, Codex, Gemini CLI, Cursor, Kiro or a similar agent on the BAKA PC. It inventories the hardware, benchmarks first, shows a plan, applies only changes it measured to help, never weakens security or anti-cheat requirements, and writes an undo script.

### GitHub page
- README lists every feature, a BAKA vs Windows table, and the benchmark.

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
| Key latency (median / 99th percentile) | Stock 0.225 / 0.386 ms. BAKA Desktop mode 0.297 to 0.299 / 0.743 to 1.075 ms. BAKA Gaming mode 0.214 to 0.221 / 0.618 to 0.893 ms |
| Ad blocking / privacy | 131 of 131 test domains blocked; 12 of 12 privacy checks |
| Benchmark (from R13, same settings) | Score 91.8 Desktop mode, 101.9 Gaming mode (100 = stock) |

## Not done or not verified

- **Game FPS and frame times**: not measurable in a VM without a GPU. Use the AI tuning prompt to measure on your PC.
- **Mouse latency and 1 ms timer** could not be measured in the Hyper-V VM (the virtual mouse does not deliver injected moves, and the VM keeps a 10 to 15 ms timer). Key latency was measured.
- **AV1 4K in the VM**: with no GPU, the VM's 4 virtual cores cannot decode 4K AV1 in real time, so it did not play there. It played on the development PC (RTX 5060) at under 1% CPU. Older GPUs without AV1 decoding (before NVIDIA RTX 30, AMD RX 6000, Intel Arc / 11th gen) should use H.264, HEVC or VP9 for 4K wallpapers.
- **Idle CPU in Desktop mode** is higher than stock in the VM (see the benchmark); BAKA Desktop itself uses 0.03%.
- **Netflix** and other Store apps that need Edge do not install while Edge is removed.
- **Media keys**: not testable in the VM (no sound device).
