# Source repository workflow

The BAKA source repository is hosted at [OldcarryG/Baka-windows](https://github.com/OldcarryG/Baka-windows). Source changes are reviewed and tested before they are pushed. ISO images and other installation media are not published in ordinary source commits.

## Local validation

Run the isolated checks from the project root in Windows PowerShell or PowerShell 7:

```powershell
./Tests/Test-DesktopConfiguration.ps1
./Tests/Test-DockContrast.ps1
./Tests/Test-GameDetection.ps1
./Tests/Test-GamingProfiles.ps1
./Tests/Test-SystemMonitoring.ps1
./Tests/Test-ReleasePipelineGuards.ps1
./Tests/Test-BakaCompanionPreview.ps1
./Tests/Test-ProjectConfiguration.ps1
```

The full project preflight verifies the pinned Microsoft source image, servicing packages, and Baka Browser installer. Keep those external files at the paths recorded in the project manifests before running it. The unsigned Browser installer is only hash/signature-checked by preflight; this check does not authorize or execute it.

To validate source code in a checkout without those external files, run:

```powershell
./Tests/Test-ProjectConfiguration.ps1 -SkipExternalArtifactChecks
```

That option skips only media and installer byte/signature checks. It records each skipped check explicitly; manifest structure, hashes, source configuration, deployment scripts, JSON, and PowerShell syntax checks still run. Local release preflight should use the default strict mode.

## GitHub Actions

`.github/workflows/source-validation.yml` runs the source-level checks on a Windows runner for pushes, pull requests, and manual runs. Its project preflight explicitly skips checks that require excluded installation media, servicing packages, or the unsigned Browser installer. The workflow does not build an ISO, claim installed-image acceptance, run games, or measure gaming performance.

## Change and release process

1. Make a focused change on a topic branch.
2. Run the relevant local checks and the full project preflight when its pinned external inputs are available.
3. Review the complete diff for credentials, host paths, generated files, and unintended changes.
4. Commit source, tests, documentation, and licensed/original assets with a descriptive message.
5. Push the topic branch and review its GitHub Actions result before merging.
6. Build a release image only on the documented Windows technician environment, to a new output path, after release approval. Preserve previous images and compare their recorded hashes.
7. Keep build logs and test records locally. Publish only sanitized evidence that contains no machine-specific paths or credentials.
