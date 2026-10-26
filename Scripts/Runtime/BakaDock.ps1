[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$dataRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $dataRoot 'Modules\GamingProfiles.psm1') -Force
$profileConfigPath = Join-Path $dataRoot 'PerformanceProfiles.json'
$profileConfig = Get-Content -LiteralPath $profileConfigPath -Raw | ConvertFrom-Json
$script:gameDetectionProcesses = @($profileConfig.gameDetection.processes)
$logDirectory = Join-Path $env:LOCALAPPDATA 'BAKA\Logs'
if (-not (Test-Path -LiteralPath $logDirectory)) { New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null }
$script:logPath = Join-Path $logDirectory 'Profiles.log'
$script:activeProfile = 'Desktop'
$script:manualOverride = $null
$script:autoGaming = $false
$script:detectedGameName = $null
$script:profileButtons = @{}
$script:colors = @{
    Canvas = [System.Drawing.Color]::FromArgb(20,21,24)
    Surface = [System.Drawing.Color]::FromArgb(34,36,40)
    SurfaceHover = [System.Drawing.Color]::FromArgb(49,52,58)
    Accent = [System.Drawing.Color]::FromArgb(232,234,238)
    Text = [System.Drawing.Color]::FromArgb(231,233,237)
    Muted = [System.Drawing.Color]::FromArgb(154,159,168)
    Border = [System.Drawing.Color]::FromArgb(98,102,110)
}
$script:fontRegular = [System.Drawing.Font]::new('Segoe UI Variable',9,[System.Drawing.FontStyle]::Regular)
$script:fontStrong = [System.Drawing.Font]::new('Segoe UI Variable',9,[System.Drawing.FontStyle]::Bold)

$script:dockForm = New-Object System.Windows.Forms.Form
$script:dockForm.Text = 'BAKA System Dock'
$script:dockForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$script:dockForm.ShowInTaskbar = $false
$script:dockForm.TopMost = $true
$script:dockForm.AccessibleName = 'BAKA Gaming Dock'
$script:dockForm.AccessibleDescription = 'Monochrome controls for Desktop, Gaming, and Benchmark profiles.'
$script:dockForm.BackColor = $script:colors.Canvas
$script:dockForm.Opacity = 0.97
$script:dockForm.AutoSize = $true
$script:dockForm.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$script:dockForm.Padding = [System.Windows.Forms.Padding]::new(10,8,10,8)
$script:dockForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$script:dockForm.KeyPreview = $true

# Windows 11 supplies the native rounded corners and shadow; older builds keep a clean square fallback.
try {
    $nativeStyling = @'
using System;
using System.Runtime.InteropServices;
public static class BakaDockNativeStyling {
    [DllImport("dwmapi.dll", PreserveSig=true)]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
}
'@
    Add-Type -TypeDefinition $nativeStyling -ErrorAction Stop
    $script:dockForm.Add_Shown({
        $cornerPreference = 2
        [void][BakaDockNativeStyling]::DwmSetWindowAttribute($script:dockForm.Handle,33,[ref]$cornerPreference,[Runtime.InteropServices.Marshal]::SizeOf([int]))
    })
} catch { }

$rootPanel = New-Object System.Windows.Forms.TableLayoutPanel
$rootPanel.AutoSize = $true
$rootPanel.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$rootPanel.ColumnCount = 1
$rootPanel.RowCount = 2
$rootPanel.Margin = [System.Windows.Forms.Padding]::Empty
$rootPanel.Padding = [System.Windows.Forms.Padding]::Empty
$rootPanel.BackColor = [System.Drawing.Color]::Transparent
$script:dockForm.Controls.Add($rootPanel)

$header = New-Object System.Windows.Forms.TableLayoutPanel
$header.AutoSize = $true
$header.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$header.ColumnCount = 2
$header.RowCount = 1
$header.Dock = [System.Windows.Forms.DockStyle]::Fill
$header.Margin = [System.Windows.Forms.Padding]::new(4,0,4,5)
$header.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
$header.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)))
$rootPanel.Controls.Add($header,0,0)

$brand = New-Object System.Windows.Forms.Label
$brand.Text = 'BAKA'
$brand.AutoSize = $true
$brand.ForeColor = $script:colors.Text
$brand.Font = [System.Drawing.Font]::new('Segoe UI Variable Display',11,[System.Drawing.FontStyle]::Bold)
$brand.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$brand.Padding = [System.Windows.Forms.Padding]::new(3,3,13,1)
$header.Controls.Add($brand,0,0)

$script:status = New-Object System.Windows.Forms.Label
$script:status.Text = 'DESKTOP  ·  BALANCED'
$script:status.AutoSize = $true
$script:status.ForeColor = $script:colors.Muted
$script:status.Font = [System.Drawing.Font]::new('Segoe UI Variable',8.5,[System.Drawing.FontStyle]::Regular)
$script:status.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$script:status.Padding = [System.Windows.Forms.Padding]::new(10,4,2,1)
$header.Controls.Add($script:status,1,0)

$buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$buttonPanel.AutoSize = $true
$buttonPanel.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$buttonPanel.WrapContents = $false
$buttonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$buttonPanel.BackColor = [System.Drawing.Color]::Transparent
$buttonPanel.Margin = [System.Windows.Forms.Padding]::Empty
$buttonPanel.Padding = [System.Windows.Forms.Padding]::Empty
$rootPanel.Controls.Add($buttonPanel,0,1)

$script:toolTip = New-Object System.Windows.Forms.ToolTip
$script:toolTip.AutoPopDelay = 5000
$script:toolTip.InitialDelay = 500
$script:toolTip.ReshowDelay = 100
$script:toolTip.ShowAlways = $true

function Update-ProfileAppearance {
    foreach ($name in $script:profileButtons.Keys) {
        $button = $script:profileButtons[$name]
        $active = ($name -eq $script:activeProfile)
        $button.BackColor = if ($active) { [System.Drawing.Color]::FromArgb(218,221,226) } else { $script:colors.Surface }
        $button.ForeColor = if ($active) { [System.Drawing.Color]::FromArgb(20,21,24) } else { $script:colors.Text }
        $button.Font = if ($active) { $script:fontStrong } else { $script:fontRegular }
    }
}

function Get-DetectedGame {
    $runningProcessNames = @(
        foreach ($definition in $script:gameDetectionProcesses) {
            $processName = [string]$definition.processName
            if (-not [string]::IsNullOrWhiteSpace($processName) -and (Get-Process -Name $processName -ErrorAction SilentlyContinue | Select-Object -First 1)) {
                $processName
            }
        }
    )
    Resolve-BakaDetectedGame -RunningProcessNames $runningProcessNames -Definitions $script:gameDetectionProcesses
}

function Set-Profile([string]$Profile,[string]$Reason) {
    try {
        if ($script:activeProfile -ne $Profile) {
            $null = Set-BakaGamingProfile -Profile $Profile -ErrorAction Stop
            $script:activeProfile = $Profile
            Add-Content -LiteralPath $script:logPath -Value ('{0} profile={1} reason={2}' -f (Get-Date -Format 'o'),$Profile,$Reason) -Encoding UTF8
        }
        $source = if ($Reason -eq 'Manual') { 'MANUAL' } elseif ($Reason -eq 'Auto') { 'AUTO' } elseif ($Reason -eq 'Game detected') { 'AUTO · ' + $script:detectedGameName } else { 'SYSTEM' }
        $power = 'BALANCED POWER'
        $script:status.Text = '{0}  ·  {1}  ·  {2}' -f $source,$Profile.ToUpperInvariant(),$power
        Update-ProfileAppearance
    } catch {
        Add-Content -LiteralPath $script:logPath -Value ('{0} profile-change-failed requested={1} error={2}' -f (Get-Date -Format 'o'),$Profile,$_.Exception.Message) -Encoding UTF8
        $script:status.Text = 'PROFILE CHANGE FAILED  ·  SEE BAKA LOGS'
        $script:status.ForeColor = [System.Drawing.Color]::FromArgb(220,170,170)
    }
}

function Add-DockButton([string]$Text,[string]$Hint,[scriptblock]$Action,[string]$ProfileName) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.AutoSize = $true
    $button.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $button.MinimumSize = [System.Drawing.Size]::new(78,36)
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = $script:colors.Surface
    $button.ForeColor = $script:colors.Text
    $button.Font = [System.Drawing.Font]::new('Segoe UI Variable',8,[System.Drawing.FontStyle]::Regular)
    $button.Margin = [System.Windows.Forms.Padding]::new(3,2,3,2)
    $button.Padding = [System.Windows.Forms.Padding]::new(8,2,8,2)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.AccessibleName = $Text
    $button.AccessibleDescription = $Hint
    $script:toolTip.SetToolTip($button,$Hint)
    $button.Add_MouseEnter({ if ($this.BackColor -ne [System.Drawing.Color]::FromArgb(218,221,226)) { $this.BackColor = $script:colors.SurfaceHover } })
    $button.Add_MouseLeave({ Update-ProfileAppearance })
    $button.Add_Click($Action)
    $buttonPanel.Controls.Add($button)
    if ($ProfileName) { $script:profileButtons[$ProfileName] = $button }
}

Add-DockButton 'Desktop' 'Restore the normal visual baseline.' { $script:manualOverride='Desktop'; Set-Profile 'Desktop' 'Manual' } 'Desktop'
Add-DockButton 'Gaming' 'Toggle Gaming Mode. Automatic CS2 and TF2 detection resumes when Auto is selected.' {
    if ($script:manualOverride -eq 'CompetitiveGaming') {
        $script:manualOverride=$null
        $game=Get-DetectedGame
        if ($game) { $script:autoGaming=$true; $script:detectedGameName=$game.DisplayName; Set-Profile 'CompetitiveGaming' 'Game detected' } else { $script:autoGaming=$false; $script:detectedGameName=$null; Set-Profile 'Desktop' 'Auto' }
    } else { $script:manualOverride='CompetitiveGaming'; Set-Profile 'CompetitiveGaming' 'Manual' }
} 'CompetitiveGaming'
Add-DockButton 'Benchmark' 'Use the clean baseline for controlled experiments.' { $script:manualOverride='Benchmark'; Set-Profile 'Benchmark' 'Manual' } 'Benchmark'
Add-DockButton 'Auto' 'Resume automatic CS2 and TF2 detection.' {
    $script:manualOverride=$null
    $game=Get-DetectedGame
    $script:autoGaming=[bool]$game
    $script:detectedGameName=if($game){$game.DisplayName}else{$null}
    if ($game) { Set-Profile 'CompetitiveGaming' 'Game detected' } else { Set-Profile 'Desktop' 'Auto' }
} $null
Add-DockButton 'Task Mgr' 'Open Windows Task Manager.' { Start-Process -FilePath (Join-Path $env:WINDIR 'System32\Taskmgr.exe') } $null
Add-DockButton 'Settings' 'Open Windows Settings.' { Start-Process 'ms-settings:' } $null
Add-DockButton 'Browser' 'Open Baka Browser, or use the approved app installer.' {
    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $link = if (Test-Path -LiteralPath $startMenu) { Get-ChildItem -LiteralPath $startMenu -Filter '*Baka*.lnk' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 } else { $null }
    if ($link) { Start-Process -FilePath $link.FullName }
    else { [System.Windows.Forms.MessageBox]::Show('Use “BAKA Install Selected Apps” on the desktop to review and install Baka Browser.','BAKA Browser','OK','Information') | Out-Null }
} $null
Add-DockButton '×' 'Close the dock. Reopen it from the BAKA Gaming Dock shortcut.' { $script:dockForm.Close() } $null

$script:dockForm.Add_Paint({
    $pen = New-Object System.Drawing.Pen($script:colors.Border,1)
    try { $_.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias; $_.Graphics.DrawRectangle($pen,0,0,$script:dockForm.ClientSize.Width-1,$script:dockForm.ClientSize.Height-1) }
    finally { $pen.Dispose() }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 4000
$timer.Add_Tick({
    $game = Get-DetectedGame
    if (-not $script:manualOverride) {
        if ($game -and (-not $script:autoGaming -or $script:detectedGameName -ne $game.DisplayName)) {
            $script:autoGaming=$true
            $script:detectedGameName=$game.DisplayName
            Set-Profile 'CompetitiveGaming' 'Game detected'
        } elseif (-not $game -and $script:autoGaming) {
            $script:autoGaming=$false
            $script:detectedGameName=$null
            Set-Profile 'Desktop' 'Auto'
        }
    }
    if ($game -and -not $script:manualOverride) { $script:dockForm.Hide() }
    elseif (-not $script:dockForm.Visible) { $script:dockForm.Show(); $script:dockForm.Activate() }
})
$script:dockForm.Add_Shown({
    $area=[System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $script:dockForm.Location=[System.Drawing.Point]::new([int]($area.Left+($area.Width-$script:dockForm.Width)/2),[int]($area.Top+$area.Height-$script:dockForm.Height-18))
    $timer.Start()
})
$script:dockForm.Add_FormClosing({
    $timer.Stop()
    try { $null = Set-BakaGamingProfile -Profile 'Desktop' } catch { Add-Content -LiteralPath $script:logPath -Value ('{0} close-restore-failed error={1}' -f (Get-Date -Format 'o'),$_.Exception.Message) -Encoding UTF8 }
})
$script:dockForm.Add_KeyDown({ if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $script:dockForm.Close() } })
Update-ProfileAppearance
[System.Windows.Forms.Application]::Run($script:dockForm)
