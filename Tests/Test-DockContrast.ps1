[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$manifest=Get-Content -LiteralPath (Join-Path $root 'Config\DesktopThemes.json') -Raw|ConvertFrom-Json
$required=@('BAKA Obsidian','BAKA Liquid','BAKA Minimal','BAKA Gaming')
$actual=@($manifest.themes|ForEach-Object {$_.name})
if(@($required|Where-Object {$_ -notin $actual}).Count){throw 'Theme manifest must define Obsidian, Liquid, Minimal, and Gaming presets.'}
function Get-RelativeLuminance([string]$Hex){
    $channels=@([Convert]::ToInt32($Hex.Substring(1,2),16),[Convert]::ToInt32($Hex.Substring(3,2),16),[Convert]::ToInt32($Hex.Substring(5,2),16))
    $linear=@($channels|ForEach-Object {$value=$_/255.0;if($value -le 0.04045){$value/12.92}else{[math]::Pow(($value+0.055)/1.055,2.4)}})
    return (0.2126*$linear[0])+(0.7152*$linear[1])+(0.0722*$linear[2])
}
function Get-ContrastRatio([string]$Foreground,[string]$Background){
    $a=Get-RelativeLuminance $Foreground;$b=Get-RelativeLuminance $Background
    return ([math]::Max($a,$b)+0.05)/([math]::Min($a,$b)+0.05)
}
$checks=[System.Collections.Generic.List[object]]::new()
foreach($theme in $manifest.themes){
    foreach($pair in @(
        [pscustomobject]@{Name='body text';Color=$theme.text;Minimum=4.5},
        [pscustomobject]@{Name='secondary text';Color=$theme.muted;Minimum=4.5},
        [pscustomobject]@{Name='accent controls';Color=$theme.accent;Minimum=3.0},
        [pscustomobject]@{Name='panel border';Color=$theme.border;Minimum=3.0}
    )){$checks.Add([pscustomobject]@{Theme=$theme.name;Element=$pair.Name;Contrast=(Get-ContrastRatio $pair.Color $theme.surface);Minimum=$pair.Minimum})}
}
$checks|Format-Table Theme,Element,@{Label='Contrast';Expression={[math]::Round($_.Contrast,2)}},Minimum -AutoSize
$failed=@($checks|Where-Object {$_.Contrast -lt $_.Minimum})
if($failed.Count){throw ('Theme contrast failed: '+(($failed|ForEach-Object {'{0}/{1}={2:N2}' -f $_.Theme,$_.Element,$_.Contrast}) -join ', '))}
Write-Output ('PASS: {0} BAKA theme contrast checks passed; four required presets are present.' -f $checks.Count)
