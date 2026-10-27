# VMware Windows A/B comparison — status and protocol

**Updated:** 2026-10-27
**Status:** Workstation 26H1 is installed. The preserved matched AB shells still time out at the EFI CD-ROM handoff for both candidate and source, but a new disposable VMware acceptance VM reached a genuine Windows 11 Setup screen before stopping at the missing TPM 2.0 requirement. Installation and guest acceptance remain unverified.

The 2026-10-27 source remediation was not rebuilt into a new ISO: the candidate and stock source produced the same pre-Setup timeout in the preserved AB shells, so no image-specific boot correction is supported by that comparison. The four local ISO hashes were rechecked and remain unchanged. A separate disposable acceptance VM was created and reached Setup; its vTPM configuration remains pending.

The disposable acceptance VM created on 2026-10-27 did reach Windows 11 Setup. Setup reported that TPM 2.0 was missing. The VM was intentionally kept separate from the preserved AB shells and the unrelated existing user VM. See `docs/evidence/VMWARE_ACCEPTANCE_20261027.md`.

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
| VMware Workstation | 26H1 build 25388281; Broadcom installer signature valid; `vmrun` and `vmcli` available; guest log reports `Monitor Mode: ULM` with Hyper-V detected |
| BAKA image | UI-R2 ISO, SHA-256 `55E6883CC303AE5AD8D22EDD3C8A7E9344C13498F6623A79F4D5D1D5DF877CD8`, structurally validated but not accepted |
| Stock install source | Official Windows 11 Pro x64 ISO, build 26300.9457 |

Broadcom lists VMware Workstation Pro 26H1 as the current desktop-hypervisor release. The downloaded installer is `VMware-Workstation-Full-26H1-25388281.exe`, signed by Broadcom Inc.; Authenticode status was `Valid`, and SHA-256 is `A0EF9087607D9CAD20B08139E73E41242E044AD5BD8CEE141D3BAD314586737F`. [Release information](https://blogs.vmware.com/cloud-foundation/2026/05/14/announcing-vmware-workstation-and-fusion-26h1/) · [Download and license instructions](https://knowledge.broadcom.com/external/article/368667/download-and-license-information-for-vmw.html)

The BAKA candidate is build 26300.9711 while the pinned stock source is 26300.9457. For a fair comparison, the stock guest must be serviced to 26300.9711 with the same approved update before comparing behavior. Record VMware Tools version, guest edition/build, virtual hardware, firmware, display resolution, and update state for both VMs.

## Proposed lab configuration

- Two UEFI Windows 11 Pro guests: `BAKA-Stock-Reference` and `BAKA-Liquid-R2`.
- Secure Boot and virtual TPM enabled when supported by the installed VMware release.
- Matched virtual hardware: 4 vCPUs, 12 GiB RAM, 160 GiB growable virtual disks, identical 1920×1080 display settings, and the same VMware Tools version.
- Enable the same VMware 3D-acceleration setting in both guests. Verify the guest graphics adapter and DirectX capability before attempting a game.
- Run performance and game captures one guest at a time. A side-by-side desktop screenshot may be captured separately with both guests idle.
- Keep the existing Hyper-V VMs and all source/candidate ISOs untouched. Do not disable host security or Hyper-V settings to improve a score.

Both guest folders were created under the ignored `Work/VMware-AB-20261026/` directory with matched CPU/RAM/disk settings and the official source ISO or BAKA candidate attached. In both VMware logs, Secure Boot reports `SECUREBOOT: Image APPROVED`, followed by `About to do EFI boot` and `Status upon boot failure: Time out`. The candidate's timeout occurred with its CD-ROM on SATA port 1, SATA port 0, and IDE. A timed Enter-key event did not alter the logged timeout. The candidate VM was also checked with the vendor-recommended Windows 10 x64 guest type; the loader still timed out. The stock VM, using the matched Windows 11 x64 guest type, produced the same timeout on SATA. Neither guest reached Windows Setup. This matching source result does not establish a candidate-only problem. Screenshots are in `docs/evidence/screenshots/`. The Workstation logs report `Monitor Mode: ULM` and Hyper-V detected. Neither guest has a vTPM. Broadcom documents vTPM setup through Workstation VM encryption and the Hardware settings UI; its employee response says `vmcli` does not support VM encryption or vTPM creation. [Windows 11 guest requirements](https://knowledge.broadcom.com/external/article/315650) · [VMCLI support response](https://community.broadcom.com/vmware-cloud-foundation/discussion/vmcli-add-encryption-for-enabling-tpm)

At VM creation time, the host had about 405 GiB free. Preserve at least 80 GiB free; reduce the disk cap or defer game installation if needed. Both guests are configured with 12 GiB, so run game tests sequentially. If both cannot run comfortably for a screenshot, capture each desktop separately and label each image rather than implying simultaneous execution.

Hyper-V is active on this host. Broadcom documents that Workstation uses Windows Hypervisor Platform when Hyper-V/VBS is enabled and that this can affect VM performance; Workstation 25H2 and later can identify the VM monitor mode. Record the actual mode from the Workstation log/UI and keep the host's Hyper-V, VBS, and memory-integrity settings unchanged during this comparison. [Broadcom monitor-mode guidance](https://knowledge.broadcom.com/external/article/417896/after-the-host-os-upgrade-to-version-win.html)

## Measurement protocol

1. Confirm both guests are Windows 11 Pro build 26300.9711, fully at the same patch level, with the same VMware Tools, vCPU/RAM, display mode, and power source. Record any unavoidable difference.
2. Create clean checkpoints after setup. Run each guest separately, wait five minutes after sign-in, then sample ten minutes of idle CPU use, committed/available memory, disk activity, and BAKA companion process use. Repeat three times and report median and spread.
3. Measure boot-to-interactive-desktop time three times per guest. Use the same definition and reset state between runs.
4. Install the same free games and game versions in each guest. Test **Counter-Strike 2** and **Team Fortress 2** if the VMware virtual graphics adapter passes their launch requirements. Steam lists CS2 as free-to-play with an 8 GB RAM and DirectX 11 / Shader Model 5.0 minimum; TF2 is also free-to-play. [CS2](https://store.steampowered.com/app/730/) · [TF2](https://store.steampowered.com/app/440/)
5. Use the same resolution, graphics settings, map or demo, warm-up, and capture duration in both guests. Repeat at least three runs per game. Record average FPS, 1% lows, frame-time consistency, guest CPU/RAM, and virtual GPU load only when the counter is available. If online/anti-cheat behavior is not supported in a VM, use an offline practice path or mark that game test not run.
6. Capture genuine screenshots of each desktop, the Workstation side-by-side view, guest resource use, and game results. Include the VM name, build, resolution, timestamp, and test state. Never substitute generated mockups for screenshots of actual guest behavior.
7. Publish raw CSV files and a short summary with run count, median, spread, and limitations. A result is inconclusive if the runs vary beyond the observed change.

`Scripts/Diagnostics/Collect-ABGuestMetrics.ps1` is prepared to collect guest CPU, available/committed memory, disk throughput, and detected BAKA/game process usage into timestamped CSV and JSON files. Its PowerShell syntax and output path were smoke-checked on the host only; that smoke check is not a Windows guest measurement or performance result. Run it inside each guest after setup, using the same sample count and interval for both. Missing optional performance counters are recorded as unavailable; missing required CPU or available-memory counters stop collection.

VMware graphics are virtualized, and Hyper-V is active on the host. These runs can compare the two guests under this lab setup; they cannot establish how either OS performs when installed natively on the RTX 5060 or on other gaming hardware.

## Progress

| Work item | Status |
| --- | --- |
| Host and image audit | **Complete** |
| VMware Workstation installation | **Complete; Broadcom Authenticode signature verified** |
| Stock and BAKA VMware guest shells | **Created and matched; each has 4 vCPU, 12 GiB RAM, and a 160 GiB growable disk** |
| UEFI/Secure Boot boot check | **Passed in new disposable VM; preserved AB comparison still times out** |
| Windows 11 Setup requirement check | **Reached Setup; blocked by missing TPM 2.0** |
| vTPM configuration | **Pending Workstation encryption + TPM device setup** |
| Guest metric collector | **Prepared; host-only syntax/output smoke check passed** |
| Authentic installed-desktop screenshots | **Not captured; only UEFI boot-path and stock timeout screenshots exist** |
| Idle resource and startup measurements | **Not measured** |
| CS2 and TF2 install/launch/gameplay | **Not run** |
| Performance comparison and conclusion | **Not measured; no gain claimed** |

The earlier Hyper-V boot failure remains unresolved. The VMware firmware evidence does not count as a Windows Setup or installed-desktop pass.
