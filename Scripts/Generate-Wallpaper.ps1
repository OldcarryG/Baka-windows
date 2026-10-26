[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
if (-not $OutputPath) { $OutputPath = Join-Path $root 'Assets\Wallpapers\BAKA-BlackGlass-4K.png' }
$width=3840; $height=2160
$bitmap=New-Object System.Drawing.Bitmap($width,$height,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics=[System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode=[System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.CompositingQuality=[System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$graphics.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$graphics.PixelOffsetMode=[System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$graphics.Clear([System.Drawing.Color]::FromArgb(255,2,2,4))
$background=New-Object System.Drawing.Drawing2D.LinearGradientBrush([System.Drawing.Rectangle]::new(0,0,$width,$height),[System.Drawing.Color]::FromArgb(255,2,2,4),[System.Drawing.Color]::FromArgb(255,14,15,19),35.0)
$graphics.FillRectangle($background,0,0,$width,$height)
$glowPath=New-Object System.Drawing.Drawing2D.GraphicsPath
$glowPath.AddEllipse(-300,160,$width+500,$height-150)
$glow=New-Object System.Drawing.Drawing2D.PathGradientBrush($glowPath)
$glow.CenterPoint=[System.Drawing.PointF]::new(2250,1180)
$glow.CenterColor=[System.Drawing.Color]::FromArgb(42,145,150,160)
$glow.SurroundColors=@([System.Drawing.Color]::FromArgb(0,0,0,0))
$graphics.FillEllipse($glow,-300,160,$width+500,$height-150)
$ribbon=New-Object System.Drawing.Drawing2D.GraphicsPath
$ribbon.AddBezier(-250,1590,750,760,1460,2280,2400,1150)
$ribbon.AddBezier(2400,1150,2920,550,3360,660,4100,120)
$rect=[System.Drawing.Rectangle]::new(0,0,$width,$height)
foreach($stroke in @(@{W=150;A=7},@{W=90;A=11},@{W=38;A=22},@{W=13;A=56},@{W=3;A=155})){
    $pen=New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb($stroke.A,214,218,226),$stroke.W)
    $pen.LineJoin=[System.Drawing.Drawing2D.LineJoin]::Round
    $pen.StartCap=[System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap=[System.Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawPath($pen,$ribbon)
    $pen.Dispose()
}
$arcRect=[System.Drawing.Rectangle]::new(1900,-820,1900,2050)
foreach($stroke in @(@{W=58;A=7},@{W=20;A=22},@{W=4;A=105})){
    $pen=New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb($stroke.A,230,232,237),$stroke.W)
    $graphics.DrawArc($pen,$arcRect,145,235)
    $pen.Dispose()
}
$folder=Split-Path -Parent $OutputPath
if(-not(Test-Path -LiteralPath $folder)){New-Item -ItemType Directory -Path $folder -Force|Out-Null}
$bitmap.Save($OutputPath,[System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose();$bitmap.Dispose();$glow.Dispose();$glowPath.Dispose();$ribbon.Dispose();$background.Dispose()
Get-Item -LiteralPath $OutputPath | Select-Object FullName,Length
