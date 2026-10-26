# VMware Windows A/B comparison — status and protocol

**Updated:** 2026-10-26  
**Status:** Preparation documented; VMware is not installed and no comparison VMs or results exist yet.

## Objective

Compare an official Windows 11 Pro installation with the BAKA Liquid UI-R2 candidate in VMware on the same host. Keep the two guests matched so measurements describe the tested virtual configurations. Do not use VM results as evidence of native RTX gaming performance.

## Current environment and prerequisites

| Item | Observed state |
| --- | --- |
| Host OS | Windows 10 Pro, build 19045 |
| Processor | Intel Core i5-14400F, 10 cores / 16 logical processors |
| Graphics | NVIDIA GeForce RTX 5060, host driver 32.0.16.1742 |
| Memory | 31.8 GiB installed |
| Free system-drive space | About 405 GiB at the time of this check |
| Host hypervisor | Hyper-V is active |
| VMware Workstation | Not installed; no `vmrun` or Workstation executable found |
| BAKA image | UI-R2 ISO, SHA-256 `55E6883CC303AE5AD8D22EDD3C8A7E9344C13498F6623A79F4D5D1D5DF877CD8`, structurally validated but not accepted |
| Stock install source | Official Windows 11 Pro x64 ISO, build 26300.9457 |

Broadcom lists VMware Workstation Pro 26H1 as the current desktop-hypervisor release. The official download page requires a Broadcom Support Portal sign-in; the user has said they will sign in. No credentials are requested or recorded here. [Release information](https://blogs.vmware.com/cloud-foundation/2026/05/14/announcing-vmware-workstation-and-fusion-26h1/) · [Download and license instructions](https://knowledge.broadcom.com/external/article/368667/download-and-license-information-for-vmw.html)

The BAKA candidate is build 26300.9711 while the pinned stock source is 26300.9457. For a fair comparison, the stock guest must be serviced to 26300.9711 with the same approved update before comparing behavior. Record VMware Tools version, guest edition/build, virtual hardware, firmware, display resolution, and update state for both VMs.

## Proposed lab configuration

- Two Generation 2 UEFI Windows 11 Pro guests: `BAKA-Stock-Reference` and `BAKA-Liquid-R2`.
- Secure Boot and virtual TPM enabled when supported by the installed VMware release.
- Matched virtual hardware: 4 vCPUs, 12 GiB RAM, 180 GiB thin-provisioned disk, identical 1920×1080 display settings, and the same VMware Tools version.
- Enable the same VMware 3D-acceleration setting in both guests. Verify the guest graphics adapter and DirectX capability before attempting a game.
- Run performance and game captures one guest at a time. A side-by-side desktop screenshot may be captured separately with both guests idle.
- Keep the existing Hyper-V VMs and all source/candidate ISOs untouched. Do not disable host security or Hyper-V settings to improve a score.

The proposed RAM and disk allocations are subject to checking host free space immediately before VM creation. If both VMs cannot run comfortably at once for a screenshot, capture each desktop independently and label the images with the guest name and timestamp rather than implying simultaneous execution.

## Measurement protocol

1. Confirm both guests are Windows 11 Pro build 26300.9711, fully at the same patch level, with the same VMware Tools, vCPU/RAM, display mode, and power source. Record any unavoidable difference.
2. Create clean checkpoints after setup. Run each guest separately, wait five minutes after sign-in, then sample ten minutes of idle CPU use, committed/available memory, disk activity, and BAKA companion process use. Repeat three times and report median and spread.
3. Measure boot-to-interactive-desktop time three times per guest. Use the same definition and reset state between runs.
4. Install the same free games and game versions in each guest. Test **Counter-Strike 2** and **Team Fortress 2** if the VMware virtual graphics adapter passes their launch requirements. Steam lists CS2 as free-to-play with an 8 GB RAM and DirectX 11 / Shader Model 5.0 minimum; TF2 is also free-to-play. [CS2](https://store.steampowered.com/app/730/) · [TF2](https://store.steampowered.com/app/440/)
5. Use the same resolution, graphics settings, map or demo, warm-up, and capture duration in both guests. Repeat at least three runs per game. Record average FPS, 1% lows, frame-time consistency, guest CPU/RAM, and virtual GPU load only when the counter is available. If online/anti-cheat behavior is not supported in a VM, use an offline practice path or mark that game test not run.
6. Capture genuine screenshots of each desktop, the Workstation side-by-side view, guest resource use, and game results. Include the VM name, build, resolution, timestamp, and test state. Never substitute generated mockups for screenshots of actual guest behavior.
7. Publish raw CSV files and a short summary with run count, median, spread, and limitations. A result is inconclusive if the runs vary beyond the observed change.

VMware graphics are virtualized, and Hyper-V is active on the host. These runs can compare the two guests under this lab setup; they cannot establish how either OS performs when installed natively on the RTX 5060 or on other gaming hardware.

## Progress

| Work item | Status |
| --- | --- |
| Host and image audit | **Complete** |
| VMware installation | **Blocked on official Broadcom portal download access** |
| Stock and BAKA VMware guests | **Not started** |
| Authentic desktop screenshots | **Not captured** |
| Idle resource and startup measurements | **Not measured** |
| CS2 and TF2 install/launch/gameplay | **Not run** |
| Performance comparison and conclusion | **Not measured; no gain claimed** |

The earlier Hyper-V boot failure remains unresolved. A VMware boot attempt is not evidence until the guest visibly reaches Windows Setup and the installed desktop is observed.
