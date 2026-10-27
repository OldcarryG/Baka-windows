# BAKA Windows Gaming Edition — decisions and current state

Updated: 2026-10-27

## Release state

- The user authorized building a new, distinct candidate in the Windows 11 technician environment after a separate temporary VM could not reach Setup. That build completed; the new candidate passed structural ISO validation.
- The original ISO and the 2026-10-16 candidate must remain unchanged. Recalculated hashes match the pinned values.
- Structural validation is not release acceptance. Do not describe the candidate as fully tested until Windows SIM, boot/install/OOBE, installed runtime, security/update restoration, and required game acceptance have evidence.
- The current candidate is `Output/BAKA-Windows-Gaming-Edition-26H2-x64-BakaLiquid-UI-R2-20261024.iso`, SHA-256 `55E6883CC303AE5AD8D22EDD3C8A7E9344C13498F6623A79F4D5D1D5DF877CD8`. Host-side rehash on 2026-10-26 matches.
- The build technician VM is Saved with guest state preserved after building and copying evidence. The acceptance VM is Off after the latest repeat boot failure. The UI-R2 DVD remains first in UEFI boot order with Secure Boot On and TPM enabled; a fresh 80 GiB test disk is attached and the old system disk is detached. Hyper-V created an automatic checkpoint. VMConnect opens, but ten guest-console captures have timed out; Setup/OOBE was not observed, no guest input was sent, and no partition/erase action occurred. Raw host logs are retained locally and are not published.
- The earlier separate technician-VM attempt remains Off after shutdown before Setup; it was not the successful build environment.

## Product decisions retained

- Base: pinned official Windows 11 Pro x64 en-US source, build 10.0.26300.9457, SHA-256 `BD4307DF32BC8AF33B39CCECB1174AEB345386630F89A2B86C7A4E36B55EA650`.
- Servicing: KB5127648, Windows build 10.0.26300.9711. The older checkpoint was skipped because the source already contained a superseding rollup.
- The integrated desktop is an optional WPF companion with Explorer retained as the shell. It includes the dock, optional status bar, Quick Panel, settings editor, and core widgets. It does not globally patch native Win32 window frames.
- BAKA Liquid is the default. Required presets are Obsidian, Liquid, Minimal, and Gaming; Violet is optional. Gaming/Benchmark reduce optional motion and widgets. High-contrast and remote sessions use an opaque fallback.
- Desktop, Competitive Gaming, and Benchmark remain reversible profiles. Balanced power, native Windows CPU scheduling, and approved security protections remain the defaults. Do not enable unverified global affinity, MSI, interrupt, storage, or polling-rate changes.
- Game detection targets Counter-Strike 2 and Team Fortress 2. VALORANT is explicitly excluded. Unit detection tests do not count as game compatibility tests.
- Microsoft Store and WebView2 are retained. The user-selected Baka Browser payload is pinned at SHA-256 `E381B835A0607EE2006A9A89588161DA2125518398AEBDB8FFE0CCFB1C342488`, is unsigned, and has not been executed. Earlier authorization permits running it only in the isolated acceptance VM.
- Setup keeps interactive disk selection. Account handling changed in R4 (see below): a passwordless local account signs in automatically. No disk erasure or physical installation is authorized.
- Windows Update suppression must remain reversible. Do not claim the suppression or administrator restore workflow works until it passes in the installed candidate.
- No measured BAKA performance gain is established. Physical hardware is unavailable, so physical FPS, frametime, input, USB, DPC/ISR, and stability results must remain blocked rather than inferred.

## 2026-10-27 source remediation decision

- Keep the PowerShell/WPF companion architecture and apply focused reliability fixes rather than rebuild the image without evidence. The source preview passed after the changes.
- Treat the host preview memory result (212.76 MiB average working set) as a failed initial budget sample, not as proof of installed-image behavior. Do not claim the 150 MiB target until a targeted optimization and installed Windows 11 measurement support it.
- Do not rebuild or replace an ISO solely from the shared Hyper-V/VMware EFI timeout. Candidate and official source media produced the same pre-Setup result, and the read-only boot-file comparison found zero differences; the image root cause remains unresolved.
- Keep ISO rebuilding in the preserved Windows 11 technician VM. The current Windows 10 host lacks the required ADK/OSCDIMG/WinPE/WSIM toolchain; its preflight now reports that limitation cleanly.

## 2026-10-27 R4 "Liquid Shell" decisions (user request)

- The user asked to skip the Windows sign-in page. This supersedes the earlier "local or Microsoft account choice" decision: the answer file now creates one passwordless local administrator (`BAKA`) and signs it in automatically. Anyone with physical access can use the PC; setting a password in Windows restores the sign-in screen (BAKA never stores a password). Disk selection stays interactive (no `windowsPE` pass) and TPM/Secure Boot checks are not bypassed.
- Debloat now covers 19 exact provisioned packages (adds Bing Search, new Outlook, To Do, Power Automate, Get Help, Feedback Hub, Dev Home, Phone Link, Cross Device, Quick Assist, Xbox speech overlay). Xbox identity/TCUI, Store, Windows Security, App Installer, codecs, and inbox tools are protected by blocked patterns. The same list is also removed online at first logon, so older images get it too.
- Telemetry upload services/tasks are disabled and ads, suggestions, Copilot, Recall, Start web search, and activity history are turned off through `Config/SystemTuning.json` and `Config/PrivacySettings.json`. Every prior value is backed up; "Restore BAKA System Tuning" puts them back. Security, Update, Xbox sign-in, audio, and network services are on a protected list the code refuses to change.
- Baka Browser installs silently per user at first logon (Velopack `--silent`), registers itself under Default Programs, and becomes the default for http/https/.htm/.html through the Windows default-associations policy. Edge and WebView2 are kept because Windows components and the browser itself depend on WebView2.
- The companion becomes a taskbar replacement while keeping Explorer as the shell: a Start button, open-window strip, and auto-hidden native taskbar (restored on exit). Users can set any image, looping video, or solid color as the wallpaper and custom dock icons. Video wallpaper pauses during Gaming/Benchmark profiles.

## Evidence and maintenance

- Raw build records and host logs remain in local `Logs/` and are not part of the source repository. A sanitized source-check summary is published in `docs/evidence/SOURCE_VALIDATION_20261026.md`.
- The GitHub repository had no published refs before this source import. The reviewed source tree is the initial versioned baseline; ISO and external build inputs remain local. No existing remote history was overwritten.
- The new candidate, original, previous candidate, and Microsoft source hashes are recorded in `docs/BUILD_STATUS.md` and `docs/ACCEPTANCE_MATRIX.md`.
- Preserve the candidate until acceptance decisions are complete. Any rebuild must use a distinct output and retain the original/source snapshots and logs.
