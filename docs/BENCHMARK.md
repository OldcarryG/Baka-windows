# BAKA Windows benchmark and latency (R14)

All numbers on this page come from the final R14 ISO (`BAKA-Windows-Gaming-Edition-26H2-x64-BakaDesktop-R14-20261029.iso`, SHA-256 `80E4EB67…E53E51E`) unless a row says otherwise. Measured on 2026-10-29.

- [How it was measured](#how-it-was-measured)
- [Results](#results)
- [How the score is calculated](#how-the-score-is-calculated)
- [What used the CPU and memory](#what-used-the-cpu-and-memory)
- [Input latency](#input-latency)
- [4K video wallpaper](#4k-video-wallpaper)
- [Ads and privacy](#ads-and-privacy)
- [Earlier rounds](#earlier-rounds)
- [What was not measured](#what-was-not-measured)
- [Run it yourself](#run-it-yourself)

## How it was measured

| | |
|---|---|
| Host | Development PC, Hyper-V, RTX 5060 (the GPU is not passed to the VMs) |
| VMs | Two identical Generation 2 VMs: Secure Boot, virtual TPM 2.0, 4 vCPU, 6 GB fixed memory, 64 GB disk, same virtual switch |
| Stock | The official Microsoft Windows 11 Pro 26H2 ISO (build 26300), installed with no changes |
| BAKA | The final R14 ISO, installed the normal way |
| Order | One VM at a time, the other one switched off, so they never share the host's CPU |
| Settle | Each VM was restarted, signed in, then left alone for **10 minutes** so first-boot work (indexing, Store and Defender updates, prefetch) does not count |
| Script | The same script (`Work/Vm/Guest-Bench.ps1`) on both, run over PowerShell Direct |
| BAKA Desktop mode | Normal use: menu bar, dock, widgets, BAKA window buttons on, **image** wallpaper |
| BAKA Gaming mode | The same VM about a minute after `BakaDesktop.exe --profile gaming`, which is what a detected game or Arena's Gaming card does |

What each measurement means:

| Measurement | How |
|---|---|
| Boot time | Windows' own boot event (Diagnostics-Performance, event 100): total, main boot path, post-boot |
| Memory in use / committed | Performance counters after the settle |
| Processes, threads, handles, services | Counted after the settle |
| Idle CPU | Average of all cores over 60 seconds with nobody using the PC |
| BAKA Desktop's own CPU and memory | The `BakaDesktop` process over the same 60 seconds |
| CPU | SHA-256 over a memory buffer on one core, MB/s |
| Memory copy | Copy of a 256 MB buffer, MB/s |
| Disk write | 1 GB file written with write-through (no cache), MB/s |

## Results

| Measurement | Stock Windows 11 | BAKA Desktop mode | BAKA Gaming mode |
|---|---:|---:|---:|
| **Score** (100 = stock, higher is better) | 100 | 99.4 | **101.7** |
| Boot time, total (s) | **22.0** | 27.8 | (same boot) |
| Main boot path (s) | **6.4** | 7.8 | (same boot) |
| Post-boot (s) | **15.7** | 20.0 | (same boot) |
| Memory in use at idle (MB) | **2066** | 2539 | 2579 |
| Memory committed (MB) | **1779** | 2340 | 2324 |
| Processes | 137 | 136 | 136 |
| Threads | 1562 | 1652 | **1511** |
| Handles | **49,789** | 52,898 | 53,137 |
| Running services | 97 | 90 | **89** |
| Ready scheduled tasks | 211 | **194** | **194** |
| Idle CPU, 60 s average (%) | 5.5 | **2.6** | 2.9 |
| BAKA Desktop's own CPU (%) | – | 0.1 | 0.01 |
| BAKA Desktop's own memory (MB) | – | 57 | 34 |
| Disk used on C: (GB) | **22.0** | 23.8 | 23.8 |
| Installed app packages | 51 | **35** | **35** |
| CPU: SHA-256, one core (MB/s) | 1871 | 1871 | 1870 |
| Memory copy, 256 MB (MB/s) | **18,088** | 17,517 | 17,803 |
| Disk write, 1 GB write-through (MB/s) | **1620** | 1509 | 1619 |
| Power plan | Balanced | BAKA Gaming | BAKA Gaming |

What the results say, plainly:

- **BAKA is about as fast as stock.** CPU is identical; memory copy and disk write are within 7%, which is the run-to-run range of this VM.
- **BAKA's own cost is small.** BAKA Desktop used 0.1% CPU and 57 MB on the desktop, and 0.01% CPU and 34 MB in Gaming mode.
- **Idle CPU was lower on BAKA** (2.6% vs 5.5%). Most of stock's idle CPU was Microsoft Defender scanning (2.9%). Defender also runs on BAKA, so on another day stock may be lower. In R13 BAKA was higher (13.5% vs 3.6%). Treat idle CPU as noisy.
- **Memory was higher on BAKA** (about 470 MB on the desktop, 510 MB in Gaming mode). The BAKA VM still had WhatsApp, Spotify and Microsoft To Do installed and running from the Store test; WhatsApp alone used 200 MB. Stock had none of them. The difference is real, but part of it is not BAKA.
- **Boot was 5.8 s slower on BAKA** in this round. In R13 BAKA booted 2.8 s faster. Boot time varies by several seconds between rounds on both systems.
- **Fewer services and tasks.** BAKA runs 7 to 8 fewer services and 17 fewer scheduled tasks, mostly telemetry.

## How the score is calculated

The score is the geometric mean of BAKA-vs-stock ratios, times 100. For "lower is better" metrics the ratio is stock ÷ BAKA; for "higher is better" (CPU, memory copy, disk write) it is BAKA ÷ stock. Above 1 means BAKA is better.

| Metric | Desktop mode ratio | Gaming mode ratio |
|---|---:|---:|
| Boot time | 0.79 | (not used) |
| Memory in use | 0.81 | 0.80 |
| Memory committed | 0.76 | 0.77 |
| Processes | 1.01 | 1.01 |
| Running services | 1.08 | 1.09 |
| Idle CPU | 2.12 | 1.90 |
| Disk used | 0.92 | 0.92 |
| CPU | 1.00 | 1.00 |
| Memory copy | 0.97 | 0.98 |
| Disk write | 0.93 | 1.00 |
| **Score** | **99.4** | **101.7** |

**The idle CPU ratio carries the score.** Without idle CPU, the score would be **91.4** in Desktop mode and **94.0** in Gaming mode. Since idle CPU is the noisiest measurement (see above), the fair summary is: BAKA performs the same as stock, uses about 0.5 GB more memory in this setup, and its own desktop costs well under 1% CPU.

## What used the CPU and memory

Top processes during the 60-second idle sample:

| | Stock | BAKA Desktop mode | BAKA Gaming mode |
|---|---|---|---|
| CPU | Defender (MsMpEng) 2.85%, svchost 0.37%, System 0.21%, WMI 0.10%, SysMain 0.08% | dwm 0.37%, svchost 0.27%, System 0.19%, SysMain 0.10%, **BakaDesktop 0.10%** | dwm 0.47%, svchost 0.18%, System 0.10%, WMI 0.10%, PowerShell (the test) 0.07% |
| Memory | Defender 293 MB, Explorer 161 MB, PowerShell (the test) 142 MB, Start 136 MB, Edge WebView2 118 MB, Search 109 MB | Defender 277 MB, **WhatsApp 200 MB**, Explorer 167 MB, Widgets host 157 MB, Start 143 MB, PowerShell (the test) 132 MB | Defender 233 MB, **WhatsApp 200 MB**, Explorer 167 MB, Widgets host 160 MB, PowerShell (the test) 159 MB, Start 143 MB |

Explorer and the Start menu host still run on BAKA because Windows needs them for tray icons, notifications and file dialogs.

## Input latency

**What is measured:** the time from an injected key press (`SendInput`, key F13 which no app reacts to) until the window in front receives it, 200 presses per run. Every low-level keyboard hook of every app sits in this path, so it shows what BAKA adds to every key press of a game. Script: `Work/Vm/Guest-Latency.ps1`.

### In the VMs

| Run | Median | 99th percentile |
|---|---:|---:|
| Stock Windows 11 | 0.225 ms | 0.386 ms |
| BAKA Desktop mode, final R14 ISO | 0.331 ms | 4.219 ms |
| BAKA Gaming mode, final R14 ISO | 0.243 ms | 0.555 ms |
| BAKA Desktop mode, three earlier R14 test installs | 0.30 to 0.37 ms | 0.74 to 1.19 ms |
| BAKA Gaming mode, three earlier R14 test installs | 0.21 to 0.30 ms | 0.62 to 1.54 ms |

- **In Gaming mode BAKA has no keyboard hook at all**, so a game's key presses go the same way as on stock Windows. The 0.02 to 0.08 ms difference to stock is within what two runs of the same VM differ by.
- **On the desktop BAKA adds about 0.1 ms** at the median (its hook for the Windows key). The 4.2 ms 99th percentile in the final run means 2 of 200 presses took that long; the three earlier installs stayed under 1.2 ms. A VM's virtual CPUs are sometimes descheduled by the host, which shows up exactly like this, but it was not proven to be the VM.
- Stock was measured in one install, BAKA in four.

### The R14 latency fix (development PC)

Windows holds every key press until each low-level keyboard hook answers. Until R13, BAKA's hook ran on BAKA's UI thread, so a key press had to wait whenever BAKA was busy drawing. To measure the worst case, `Work/HookLatency.ps1` kept BAKA's main thread busy the way drawing a frame does and pressed 200 keys:

| Design | Median key latency |
|---|---:|
| No hook at all (baseline) | 0.66 to 0.71 ms |
| Old: hook on the UI thread (R13) | **25 to 42 ms**, most presses held more than 50 ms |
| New: hook on its own time-critical thread (R14) | **0.75 ms** |

The new hook thread does nothing but answer the hook, at `THREAD_PRIORITY_TIME_CRITICAL`, so a busy UI no longer delays keys. In addition:

- While a game runs, the hook is **removed**, not just ignored. The window-event hooks for the BAKA window buttons are removed too.
- Turning off **Settings > "Windows key opens Launchpad"** removes the hook on the desktop as well.
- The video wallpaper's player thread does not ask for multimedia (MMCSS) priority, so it never competes with a game's audio or render threads.

## 4K video wallpaper

`BakaDesktop.exe --video-test <file> <result.json>`, 4K clips, 12 seconds each. CPU is BAKA Desktop's share of all cores.

| Format | Development PC (RTX 5060, hardware decoding) | VM (no GPU, software decoding) |
|---|---|---|
| H.264 MP4 4K | plays and loops, **0.2% CPU** | plays and loops, 35 to 37% |
| HEVC MP4 4K | needs the HEVC extension (BAKA installs it at first sign-in) | plays, about 50% |
| VP9 WebM 4K | plays, **2% CPU** | plays, about 21 to 25% |
| AV1 WebM 4K | plays, **0% CPU** | too slow without a GPU |
| Maximized window covers the desktop | – | paused, CPU 37% → **0.05%** |
| A game starts | – | player closed, decoder and video memory freed, **0% CPU**; plays again afterwards |

AV1 needs hardware decoding: NVIDIA RTX 30 or newer, AMD RX 6000 or newer, Intel Arc or 11th-gen Core graphics or newer. On older GPUs use H.264, HEVC or VP9 for 4K wallpapers.

## Ads and privacy

**Ads and trackers:** every domain of the public [d3ward ad-block test](https://d3ward.github.io/toolz/adblock), resolved through Windows the way any app does.

| | Stock | BAKA |
|---|---:|---:|
| Domains blocked | 2 of 131 (1.5%) | **131 of 131 (100%)** |

AdGuard DNS alone blocks about 82% of that list; the BAKA hosts list covers the rest. The hosts list was built with this test in mind, so 100% here does not mean 100% on every site.

**Privacy settings (12 checks):**

| | Stock | BAKA |
|---|---:|---:|
| Checks passed | 0 of 12 | **12 of 12** |
| Telemetry tasks enabled (of 16 named tasks) | 14 | 0 |
| Telemetry services running (DiagTrack, InventorySvc, TrkWks, whesvc, WSAIFabricSvc, dmwappushservice) | 5 | 0 |
| Microsoft Edge installed | yes | no |

Windows Pro still sends "required" diagnostic data. BAKA does not claim zero telemetry.

## Earlier rounds

| Round | Settle | Score Desktop / Gaming | Idle CPU stock / BAKA Desktop / Gaming | Memory in use stock / BAKA Desktop |
|---|---|---|---|---|
| **R14 final** (this page) | 10 min | **99.4 / 101.7** | 5.5 / 2.6 / 2.9% | 2066 / 2539 MB |
| R13 | 10 min | 91.8 / 101.9 | 3.6 / 13.5 / 5.0% | 2295 / 2354 MB |
| R12 | 3 min, fresh install | 80.6 / – | 3.4 / 14.2% | 2005 / 2451 MB |

One R14 run was discarded: a 4K VP9 video wallpaper from the video test was still playing in the VM (BAKA Desktop at 22.7% CPU), which is not idle.

## What was not measured

- **Game FPS and frame times.** The VMs have no GPU. Use the [AI tuning prompt](OPTIMIZE_WITH_AI.md) to benchmark on your own PC.
- **Mouse latency.** Hyper-V's virtual mouse does not deliver injected moves to the test window.
- **1 ms timer.** The VM keeps a 10 to 15 ms timer regardless of what is requested.
- **WinSAT.** Microsoft's benchmark refuses to run in a VM.
- **Media keys.** The VM has no sound device.

## Run it yourself

The scripts are in [`Tests/Benchmark/`](../Tests/Benchmark):

| Script | What it does |
|---|---|
| `Guest-Bench.ps1` | The benchmark above. Run it as administrator inside each system after a restart and 10 idle minutes; it prints JSON. `-Domains` takes the ad-test domain list (from the d3ward `adblock_data.json`). |
| `Guest-Latency.ps1 -Out <folder>` | Key and mouse latency and timer, in the signed-in user's session. On BAKA it measures Desktop mode, then Gaming mode. |
| `Guest-Video.ps1 -Out <folder>` | BAKA only: sets a video wallpaper, covers it with a maximized window, switches to Gaming mode and back, and measures CPU each time. Put 4K test clips next to the script. |
| `Compare-Bench.ps1 -ResultDir <folder>` | Reads `bench-Stock.json`, `bench-Baka.json` and `bench-BakaGaming.json` from the folder and writes `compare.md`, `compare.json` and the score. |

Save the output of `Guest-Bench.ps1` as `bench-Stock.json` on stock, `bench-Baka.json` on BAKA, and `bench-BakaGaming.json` on BAKA after `BakaDesktop.exe --profile gaming`.

On a real PC, the [AI tuning prompt](OPTIMIZE_WITH_AI.md) runs a similar benchmark before and after each change.
