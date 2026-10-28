Set-StrictMode -Version Latest

function Get-BakaDefaultDesktopConfiguration {
    [pscustomobject]@{
        SchemaVersion=1
        Appearance=[pscustomobject]@{ Theme='BAKA Carbon'; AccentColor='#FAFAFA'; GlassIntensity=40; AnimationIntensity='Full'; ReducedMotion=$false }
        Dock=[pscustomobject]@{ Alignment='Center'; IconSize=52; Spacing=9; AutoHide=$false; Magnification=$true; Monitor='Primary' }
        TopBar=[pscustomobject]@{ Enabled=$true; ShowProfile=$true; ShowDate=$true; Monitor='Primary' }
        Widgets=[pscustomobject]@{
            Enabled=$false; RefreshSeconds=3
            Items=@(
                [pscustomobject]@{ Id='clock'; Enabled=$true; Left=32; Top=48; Width=260; Height=120 },
                [pscustomobject]@{ Id='calendar'; Enabled=$true; Left=32; Top=182; Width=260; Height=250 },
                [pscustomobject]@{ Id='system'; Enabled=$true; Left=308; Top=48; Width=300; Height=190 },
                [pscustomobject]@{ Id='notes'; Enabled=$false; Left=308; Top=252; Width=300; Height=190 }
            )
        }
        Wallpaper=(Get-BakaDefaultWallpaperSettings)
        Taskbar=(Get-BakaDefaultTaskbarSettings)
        PinnedApps=@(
            [pscustomobject]@{ Id='baka-browser'; Name='Baka Browser'; Kind='Executable'; Target='%LOCALAPPDATA%\BakaBrowser\current\baka.exe'; Arguments=''; ProcessName='baka'; Glyph=[string][char]0xE774; IconPath='' },
            [pscustomobject]@{ Id='explorer'; Name='Files'; Kind='Executable'; Target='%WINDIR%\explorer.exe'; Arguments=''; ProcessName='explorer'; Glyph=[string][char]0xE8B7; IconPath='' },
            [pscustomobject]@{ Id='settings'; Name='Settings'; Kind='Uri'; Target='ms-settings:'; Arguments=''; ProcessName='SystemSettings'; Glyph=[string][char]0xE713; IconPath='' },
            [pscustomobject]@{ Id='taskmgr'; Name='Task Manager'; Kind='Executable'; Target='%WINDIR%\System32\Taskmgr.exe'; Arguments=''; ProcessName='Taskmgr'; Glyph=[string][char]0xE9D9; IconPath='' }
        )
    }
}

function Get-BakaDefaultWallpaperSettings {
    # Default keeps the shipped BAKA image. Users may choose any image, video, or solid color.
    [pscustomobject]@{ Mode='Image'; Path='%ProgramData%\BAKA\Assets\BAKA-Aurora-4K.png'; Fit='Fill'; Color='#05060A'; Muted=$true; PauseInGames=$true }
}

function Get-BakaDefaultTaskbarSettings {
    # The BAKA dock becomes the primary launcher; the native taskbar stays reachable at the screen edge.
    [pscustomobject]@{ AutoHideWindowsTaskbar=$true; ShowRunningApps=$true; ShowStartButton=$true }
}

function Get-BakaConfigMember {
    param($Object,[Parameter(Mandatory)][string]$Name)
    if($null -eq $Object){return $null}
    $property=$Object.PSObject.Properties[$Name]
    if($property){return $property.Value}
    return $null
}

function Complete-BakaDesktopConfiguration {
    # Adds sections introduced after schema 1 shipped (wallpaper, taskbar, custom dock icons) so older
    # saved settings keep loading. Existing user values are never overwritten.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Configuration)
    foreach($section in @(@{Name='Wallpaper';Defaults=(Get-BakaDefaultWallpaperSettings)},@{Name='Taskbar';Defaults=(Get-BakaDefaultTaskbarSettings)})){
        $current=Get-BakaConfigMember $Configuration $section.Name
        if($null -eq $current){
            $Configuration | Add-Member -NotePropertyName $section.Name -NotePropertyValue $section.Defaults -Force
            continue
        }
        foreach($property in $section.Defaults.PSObject.Properties){
            if(-not $current.PSObject.Properties[$property.Name]){$current | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force}
        }
    }
    foreach($app in @(Get-BakaConfigMember $Configuration 'PinnedApps')){
        if($app -and -not $app.PSObject.Properties['IconPath']){$app | Add-Member -NotePropertyName IconPath -NotePropertyValue '' -Force}
    }
    return $Configuration
}

function Test-BakaHexColor {
    param([string]$Value)
    return $Value -match '^#[0-9A-Fa-f]{6}$'
}

function Test-BakaDesktopConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Configuration)
    $errors=[System.Collections.Generic.List[string]]::new()
    if ([int]$Configuration.SchemaVersion -ne 1) { $errors.Add('SchemaVersion must be 1.') }
    $themes=@('BAKA Carbon','BAKA Carbon Red','BAKA Liquid Glass','BAKA Pop Glass','BAKA Pop Sunset','BAKA Pop Mint','BAKA Pop Sakura','BAKA Obsidian','BAKA Liquid','BAKA Violet','BAKA Minimal','BAKA Gaming')
    if ([string]$Configuration.Appearance.Theme -notin $themes) { $errors.Add('Appearance.Theme is not a supported BAKA preset.') }
    if (-not (Test-BakaHexColor ([string]$Configuration.Appearance.AccentColor))) { $errors.Add('Appearance.AccentColor must be a six-digit #RRGGBB color.') }
    if ([int]$Configuration.Appearance.GlassIntensity -lt 0 -or [int]$Configuration.Appearance.GlassIntensity -gt 45) { $errors.Add('Appearance.GlassIntensity must be between 0 and 45.') }
    if ([string]$Configuration.Appearance.AnimationIntensity -notin @('Off','Subtle','Full')) { $errors.Add('Appearance.AnimationIntensity must be Off, Subtle, or Full.') }
    if ([int]$Configuration.Dock.IconSize -lt 40 -or [int]$Configuration.Dock.IconSize -gt 72) { $errors.Add('Dock.IconSize must be between 40 and 72.') }
    if ([int]$Configuration.Dock.Spacing -lt 4 -or [int]$Configuration.Dock.Spacing -gt 18) { $errors.Add('Dock.Spacing must be between 4 and 18.') }
    if ([string]$Configuration.Dock.Alignment -notin @('Left','Center','Right')) { $errors.Add('Dock.Alignment must be Left, Center, or Right.') }
    if ([int]$Configuration.Widgets.RefreshSeconds -lt 2 -or [int]$Configuration.Widgets.RefreshSeconds -gt 30) { $errors.Add('Widgets.RefreshSeconds must be between 2 and 30 seconds.') }
    $widgetIds=@('clock','calendar','system','notes')
    foreach ($item in @($Configuration.Widgets.Items)) {
        if ([string]$item.Id -notin $widgetIds) { $errors.Add("Unsupported widget id '$($item.Id)'.") }
        if ([int]$item.Width -lt 180 -or [int]$item.Width -gt 720 -or [int]$item.Height -lt 100 -or [int]$item.Height -gt 720) { $errors.Add("Widget '$($item.Id)' dimensions are outside supported limits.") }
        if ([int]$item.Left -lt 0 -or [int]$item.Top -lt 0) { $errors.Add("Widget '$($item.Id)' position cannot be negative.") }
    }
    $appIds=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($app in @($Configuration.PinnedApps)) {
        if ([string]::IsNullOrWhiteSpace([string]$app.Id) -or -not $appIds.Add([string]$app.Id)) { $errors.Add('Pinned application ids must be non-empty and unique.') }
        if ([string]$app.Kind -notin @('Executable','Uri')) { $errors.Add("Pinned application '$($app.Name)' has an unsupported kind.") }
        if ([string]::IsNullOrWhiteSpace([string]$app.Target)) { $errors.Add("Pinned application '$($app.Name)' has no target.") }
        if ([string]$app.Kind -eq 'Uri' -and [string]$app.Target -notmatch '^[a-z][a-z0-9+.-]*:' ) { $errors.Add("Pinned application '$($app.Name)' has an invalid URI target.") }
        $iconPath=[string](Get-BakaConfigMember $app 'IconPath')
        if ($iconPath -and [IO.Path]::GetExtension($iconPath).ToLowerInvariant() -notin @('.png','.jpg','.jpeg','.bmp','.ico','.gif')) { $errors.Add("Pinned application '$($app.Name)' icon must be a .png, .jpg, .bmp, .ico, or .gif file.") }
    }
    $wallpaper=Get-BakaConfigMember $Configuration 'Wallpaper'
    if ($null -ne $wallpaper) {
        $mode=[string](Get-BakaConfigMember $wallpaper 'Mode')
        $path=[string](Get-BakaConfigMember $wallpaper 'Path')
        if ($mode -notin @('Default','Image','Video','Color')) { $errors.Add('Wallpaper.Mode must be Default, Image, Video, or Color.') }
        if ([string](Get-BakaConfigMember $wallpaper 'Fit') -notin @('Fill','Fit','Stretch','Center','Span')) { $errors.Add('Wallpaper.Fit must be Fill, Fit, Stretch, Center, or Span.') }
        if (-not (Test-BakaHexColor ([string](Get-BakaConfigMember $wallpaper 'Color')))) { $errors.Add('Wallpaper.Color must be a six-digit #RRGGBB color.') }
        $extension=if($path){[IO.Path]::GetExtension($path).ToLowerInvariant()}else{''}
        if ($mode -eq 'Image' -and $extension -notin @('.jpg','.jpeg','.jfif','.png','.bmp','.gif','.webp')) { $errors.Add('Wallpaper.Path must name a .jpg, .png, .bmp, .gif, or .webp image when Mode is Image.') }
        if ($mode -eq 'Video' -and $extension -notin @('.mp4','.m4v','.mov','.wmv','.avi','.mkv','.webm')) { $errors.Add('Wallpaper.Path must name a .mp4, .m4v, .mov, .wmv, .avi, .mkv, or .webm video when Mode is Video.') }
    }
    $taskbar=Get-BakaConfigMember $Configuration 'Taskbar'
    if ($null -ne $taskbar) {
        foreach ($name in @('AutoHideWindowsTaskbar','ShowRunningApps','ShowStartButton')) {
            $value=Get-BakaConfigMember $taskbar $name
            if ($null -ne $value -and $value -isnot [bool]) { $errors.Add("Taskbar.$name must be true or false.") }
        }
    }
    if ($errors.Count) { return [pscustomobject]@{ Valid=$false; Errors=@($errors.ToArray()) } }
    [pscustomobject]@{ Valid=$true; Errors=@() }
}

function Write-BakaConfigurationFile {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Configuration,[switch]$CreateBackup)
    $directory=Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $temp=Join-Path $directory ('.desktop-settings.{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    $backup=$Path+'.bak'
    $replaceBackup=Join-Path $directory ('.desktop-settings.{0}.old' -f [Guid]::NewGuid().ToString('N'))
    try {
        $json=ConvertTo-Json -InputObject $Configuration -Depth 12
        [IO.File]::WriteAllText($temp,$json,[System.Text.UTF8Encoding]::new($true))
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            if ($CreateBackup) { Copy-Item -LiteralPath $Path -Destination $backup -Force }
            [IO.File]::Replace($temp,$Path,$replaceBackup,$true)
        } else { [IO.File]::Move($temp,$Path) }
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $replaceBackup) { Remove-Item -LiteralPath $replaceBackup -Force -ErrorAction SilentlyContinue }
    }
}

function Read-BakaDesktopConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$DefaultPath
    )
    $defaults=Get-BakaDefaultDesktopConfiguration
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        if (Test-Path -LiteralPath $DefaultPath -PathType Leaf) {
            try { $candidate=Get-Content -LiteralPath $DefaultPath -Raw | ConvertFrom-Json -ErrorAction Stop }
            catch { $candidate=$defaults }
        } else { $candidate=$defaults }
        $validation=Test-BakaDesktopConfiguration -Configuration $candidate
        if (-not $validation.Valid) { $candidate=$defaults }
        $candidate=Complete-BakaDesktopConfiguration -Configuration $candidate
        Write-BakaConfigurationFile -Path $Path -Configuration $candidate
        return $candidate
    }
    $parseErrors=[System.Collections.Generic.List[string]]::new()
    foreach ($candidatePath in @($Path,($Path+'.bak'))) {
        if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) { continue }
        try {
            $candidate=Get-Content -LiteralPath $candidatePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $validation=Test-BakaDesktopConfiguration -Configuration $candidate
            if (-not $validation.Valid) { throw ($validation.Errors -join ' ') }
            $candidate=Complete-BakaDesktopConfiguration -Configuration $candidate
            if ($candidatePath -ne $Path) { Write-BakaConfigurationFile -Path $Path -Configuration $candidate }
            return $candidate
        } catch { $parseErrors.Add(('{0}: {1}' -f $candidatePath,$_.Exception.Message)) }
    }
    $invalidPath=$Path+'.invalid-'+(Get-Date -Format 'yyyyMMdd-HHmmss')
    if (Test-Path -LiteralPath $Path -PathType Leaf) { Move-Item -LiteralPath $Path -Destination $invalidPath -Force }
    Write-BakaConfigurationFile -Path $Path -Configuration $defaults
    return $defaults
}

function Save-BakaDesktopConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Configuration)
    $validation=Test-BakaDesktopConfiguration -Configuration $Configuration
    if (-not $validation.Valid) { throw ('Desktop settings were not saved: {0}' -f ($validation.Errors -join ' ')) }
    Write-BakaConfigurationFile -Path $Path -Configuration $Configuration -CreateBackup
    return $true
}

function Export-BakaDesktopConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Configuration)
    $validation=Test-BakaDesktopConfiguration -Configuration $Configuration
    if (-not $validation.Valid) { throw ('Desktop settings cannot be exported: {0}' -f ($validation.Errors -join ' ')) }
    Write-BakaConfigurationFile -Path $Path -Configuration $Configuration
    return $true
}

function Import-BakaDesktopConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$DestinationPath)
    $candidate=Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $validation=Test-BakaDesktopConfiguration -Configuration $candidate
    if (-not $validation.Valid) { throw ('Imported settings are invalid: {0}' -f ($validation.Errors -join ' ')) }
    $candidate=Complete-BakaDesktopConfiguration -Configuration $candidate
    Save-BakaDesktopConfiguration -Path $DestinationPath -Configuration $candidate
    return $candidate
}

Export-ModuleMember -Function Get-BakaDefaultDesktopConfiguration,Get-BakaDefaultWallpaperSettings,Get-BakaDefaultTaskbarSettings,Complete-BakaDesktopConfiguration,Test-BakaHexColor,Test-BakaDesktopConfiguration,Read-BakaDesktopConfiguration,Save-BakaDesktopConfiguration,Export-BakaDesktopConfiguration,Import-BakaDesktopConfiguration
