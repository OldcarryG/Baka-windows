[CmdletBinding()]
param([string]$OutputDirectory='',[int]$Width=3840,[int]$Height=2160)
if(-not $OutputDirectory){$OutputDirectory=Join-Path (Split-Path -Parent $PSScriptRoot) 'Assets\Wallpapers'}
# Renders the original BAKA liquid wallpapers (soft colour fields + glass ribbons) with WPF.
# Run with: powershell -STA -File Tools\New-BakaWallpapers.ps1
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase
function C([string]$Hex,[byte]$Alpha=255){$c=[System.Windows.Media.ColorConverter]::ConvertFromString($Hex);[System.Windows.Media.Color]::FromArgb($Alpha,$c.R,$c.G,$c.B)}
function Blob($Canvas,[double]$X,[double]$Y,[double]$Rx,[double]$Ry,[string]$Hex,[byte]$Alpha){
    $brush=[System.Windows.Media.RadialGradientBrush]::new()
    $brush.GradientStops.Add([System.Windows.Media.GradientStop]::new((C $Hex $Alpha),0.0))
    $brush.GradientStops.Add([System.Windows.Media.GradientStop]::new((C $Hex ([byte]($Alpha*0.45))),0.55))
    $brush.GradientStops.Add([System.Windows.Media.GradientStop]::new((C $Hex 0),1.0))
    $e=[System.Windows.Shapes.Ellipse]::new();$e.Width=$Rx*2;$e.Height=$Ry*2;$e.Fill=$brush
    [System.Windows.Controls.Canvas]::SetLeft($e,$X-$Rx);[System.Windows.Controls.Canvas]::SetTop($e,$Y-$Ry);[void]$Canvas.Children.Add($e)
}
function Ribbon($Canvas,[string]$Data,[double]$Thickness,[string]$Hex,[byte]$Alpha,[double]$Blur){
    $path=[System.Windows.Shapes.Path]::new();$path.Data=[System.Windows.Media.Geometry]::Parse($Data)
    $stroke=[System.Windows.Media.LinearGradientBrush]::new();$stroke.StartPoint=[System.Windows.Point]::new(0,0);$stroke.EndPoint=[System.Windows.Point]::new(1,1)
    $stroke.GradientStops.Add([System.Windows.Media.GradientStop]::new((C '#FFFFFF' $Alpha),0.0))
    $stroke.GradientStops.Add([System.Windows.Media.GradientStop]::new((C $Hex $Alpha),0.5))
    $stroke.GradientStops.Add([System.Windows.Media.GradientStop]::new((C '#FFFFFF' ([byte]($Alpha*0.4))),1.0))
    $path.Stroke=$stroke;$path.StrokeThickness=$Thickness;$path.StrokeStartLineCap='Round';$path.StrokeEndLineCap='Round'
    if($Blur -gt 0){$path.Effect=[System.Windows.Media.Effects.BlurEffect]::new();$path.Effect.Radius=$Blur}
    [void]$Canvas.Children.Add($path)
}
function Save-Wallpaper([string]$Name,[string]$Base,[object[]]$Blobs,[string]$RibbonColor){
    $canvas=[System.Windows.Controls.Canvas]::new();$canvas.Width=$Width;$canvas.Height=$Height;$canvas.Background=[System.Windows.Media.SolidColorBrush]::new((C $Base))
    $field=[System.Windows.Controls.Canvas]::new();$field.Width=$Width;$field.Height=$Height
    foreach($b in $Blobs){Blob $field ($b[0]*$Width) ($b[1]*$Height) ($b[2]*$Width) ($b[3]*$Height) $b[4] $b[5]}
    $field.Effect=[System.Windows.Media.Effects.BlurEffect]::new();$field.Effect.Radius=180;$field.Effect.RenderingBias='Quality'
    [void]$canvas.Children.Add($field)
    $w=$Width;$h=$Height
    $main=('M {0},{1} C {2},{3} {4},{5} {6},{7} S {8},{9} {10},{11}' -f (-0.05*$w),(0.72*$h),(0.25*$w),(0.48*$h),(0.45*$w),(0.95*$h),(0.66*$w),(0.62*$h),(0.92*$w),(0.18*$h),(1.06*$w),(0.30*$h))
    $second=('M {0},{1} C {2},{3} {4},{5} {6},{7}' -f (0.10*$w),(1.05*$h),(0.38*$w),(0.70*$h),(0.70*$w),(0.98*$h),(1.05*$w),(0.58*$h))
    Ribbon $canvas $main 150 $RibbonColor 60 40
    Ribbon $canvas $main 26 $RibbonColor 150 4
    Ribbon $canvas $second 90 $RibbonColor 40 30
    Ribbon $canvas $second 12 '#FFFFFF' 110 2
    # A soft vignette keeps desktop icons and the dock readable.
    $vignette=[System.Windows.Shapes.Rectangle]::new();$vignette.Width=$Width;$vignette.Height=$Height
    $vb=[System.Windows.Media.RadialGradientBrush]::new();$vb.RadiusX=0.75;$vb.RadiusY=0.75
    $vb.GradientStops.Add([System.Windows.Media.GradientStop]::new((C '#000000' 0),0.55));$vb.GradientStops.Add([System.Windows.Media.GradientStop]::new((C '#000000' 120),1.0))
    $vignette.Fill=$vb;[void]$canvas.Children.Add($vignette)
    $canvas.Measure([System.Windows.Size]::new($Width,$Height));$canvas.Arrange([System.Windows.Rect]::new(0,0,$Width,$Height));$canvas.UpdateLayout()
    $bitmap=[System.Windows.Media.Imaging.RenderTargetBitmap]::new($Width,$Height,96,96,[System.Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($canvas)
    $encoder=[System.Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $target=Join-Path $OutputDirectory $Name
    $stream=[IO.File]::Create($target);try{$encoder.Save($stream)}finally{$stream.Dispose()}
    Write-Output $target
}
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
# x, y, radiusX, radiusY (fractions of the screen), colour, alpha
Save-Wallpaper 'BAKA-Aurora-4K.png' '#060816' @(
    @(0.18,0.20,0.42,0.55,'#2563EB',230),@(0.78,0.18,0.40,0.50,'#7C3AED',220),@(0.55,0.78,0.48,0.45,'#06B6D4',200),@(0.92,0.80,0.30,0.40,'#DB2777',150),@(0.40,0.45,0.25,0.30,'#38BDF8',120)
) '#93C5FD'
Save-Wallpaper 'BAKA-Sunset-4K.png' '#12060E' @(
    @(0.20,0.25,0.45,0.55,'#F97316',220),@(0.78,0.22,0.40,0.50,'#DB2777',220),@(0.55,0.82,0.50,0.45,'#7C3AED',200),@(0.10,0.85,0.30,0.35,'#FACC15',120),@(0.48,0.50,0.25,0.30,'#FB7185',120)
) '#FDBA74'
Save-Wallpaper 'BAKA-Lagoon-4K.png' '#03100F' @(
    @(0.22,0.22,0.45,0.55,'#0D9488',220),@(0.80,0.25,0.40,0.50,'#2563EB',200),@(0.55,0.80,0.48,0.45,'#22C55E',170),@(0.92,0.85,0.30,0.35,'#06B6D4',160),@(0.42,0.48,0.25,0.30,'#5EEAD4',110)
) '#99F6E4'
