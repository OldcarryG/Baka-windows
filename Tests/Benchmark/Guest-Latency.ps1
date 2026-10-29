# Runs INSIDE a test VM in the signed-in user's session. Measures latency the user can feel:
#  - input: time from injecting a key press / mouse move (SendInput) until the focused window receives it.
#    Every low-level keyboard or mouse hook in any process (BAKA has a keyboard hook for the Windows key)
#    sits in this path, so this shows what BAKA adds to every key press of a game.
#  - timer: how long Sleep(1) really takes (timer resolution and how quickly a waiting thread wakes up).
# On BAKA it measures Desktop mode, then Gaming mode (BakaDesktop.exe --profile gaming), then switches back.
param([string]$Out)
$ErrorActionPreference='Continue'
New-Item -ItemType Directory -Path $Out -Force | Out-Null
$log=Join-Path $Out 'latency.txt'
function L($m){Add-Content -LiteralPath $log -Value ('{0} {1}' -f (Get-Date -Format s),$m)}
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System; using System.Diagnostics; using System.Runtime.InteropServices; using System.Windows.Forms; using System.Collections.Generic;
public static class Lat {
  [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KEYBDINPUT ki; [FieldOffset(8)] public MOUSEINPUT mi; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] inputs, int size);
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("winmm.dll")] static extern uint timeBeginPeriod(uint p);
  [DllImport("winmm.dll")] static extern uint timeEndPeriod(uint p);
  class F : Form { public long Got; public int Kind; public F(){ KeyPreview=true; } protected override void WndProc(ref Message m){ if((Kind==1 && m.Msg==0x100) || (Kind==2 && m.Msg==0x200)) Got=Stopwatch.GetTimestamp(); base.WndProc(ref m);} }
  static double[] Stats(List<double> v){ v.Sort(); if(v.Count==0) return new double[]{-1,-1,-1,-1}; Func<double,double> q = p => v[Math.Min(v.Count-1,(int)(p*v.Count))]; double s=0; foreach(var x in v) s+=x; return new double[]{ s/v.Count, q(0.5), q(0.99), v[v.Count-1] }; }
  public static string Input(int n){
    var f=new F{ Width=400, Height=300, StartPosition=FormStartPosition.CenterScreen, TopMost=true, Text="BAKA latency test" };
    f.Show(); Application.DoEvents(); f.Activate(); SetForegroundWindow(f.Handle); System.Threading.Thread.Sleep(300); Application.DoEvents();
    // a real (injected) click on the window: Windows gives the keyboard focus to the window that was clicked
    var c = f.PointToScreen(new System.Drawing.Point(f.ClientSize.Width/2, f.ClientSize.Height/2)); Cursor.Position = c;
    var cd=new INPUT{type=0}; cd.mi.dwFlags=2; var cu=new INPUT{type=0}; cu.mi.dwFlags=4; int sz=Marshal.SizeOf(typeof(INPUT));
    SendInput(1,new[]{cd},sz); SendInput(1,new[]{cu},sz); System.Threading.Thread.Sleep(300); Application.DoEvents();
    bool fg = GetForegroundWindow()==f.Handle;
    var keys=new List<double>(); var mice=new List<double>(); int size=Marshal.SizeOf(typeof(INPUT)); double tick=1000.0/Stopwatch.Frequency;
    for(int i=0;i<n;i++){
      // key: F13 (no app reacts to it)
      f.Kind=1; f.Got=0; var down=new INPUT{type=1}; down.ki.wVk=0x7C; var up=new INPUT{type=1}; up.ki.wVk=0x7C; up.ki.dwFlags=2;
      long t0=Stopwatch.GetTimestamp(); SendInput(1,new[]{down},size);
      while(f.Got==0 && (Stopwatch.GetTimestamp()-t0)*tick<50) Application.DoEvents();
      if(f.Got!=0) keys.Add((f.Got-t0)*tick); SendInput(1,new[]{up},size); Application.DoEvents();
      // mouse: one pixel right and back, over the window
      f.Kind=2; f.Got=0; var mv=new INPUT{type=0}; mv.mi.dx=(i%2==0)?1:-1; mv.mi.dwFlags=1;
      t0=Stopwatch.GetTimestamp(); SendInput(1,new[]{mv},size);
      while(f.Got==0 && (Stopwatch.GetTimestamp()-t0)*tick<50) Application.DoEvents();
      if(f.Got!=0) mice.Add((f.Got-t0)*tick);
      System.Threading.Thread.Sleep(5);
    }
    f.Close();
    fg = fg || GetForegroundWindow()==f.Handle;
    var k=Stats(keys); var m=Stats(mice);
    return "{\"foreground\":" + (fg?"true":"false") + ",\"keySamples\":" + keys.Count + ",\"keyAvgMs\":" + N(k[0]) + ",\"keyP50Ms\":" + N(k[1]) + ",\"keyP99Ms\":" + N(k[2]) + ",\"keyMaxMs\":" + N(k[3])
      + ",\"mouseSamples\":" + mice.Count + ",\"mouseAvgMs\":" + N(m[0]) + ",\"mouseP50Ms\":" + N(m[1]) + ",\"mouseP99Ms\":" + N(m[2]) + ",\"mouseMaxMs\":" + N(m[3]) + "}";
  }
  static string N(double v){ return v.ToString("0.000", System.Globalization.CultureInfo.InvariantCulture); }
  public static string Timer(int n, bool highRes){
    if(highRes) timeBeginPeriod(1);
    var v=new List<double>(); double tick=1000.0/Stopwatch.Frequency;
    for(int i=0;i<n;i++){ long t0=Stopwatch.GetTimestamp(); System.Threading.Thread.Sleep(1); v.Add((Stopwatch.GetTimestamp()-t0)*tick); }
    if(highRes) timeEndPeriod(1);
    var s=Stats(v);
    return "{\"highRes\":" + (highRes?"true":"false") + ",\"sleep1AvgMs\":" + N(s[0]) + ",\"sleep1P50Ms\":" + N(s[1]) + ",\"sleep1P99Ms\":" + N(s[2]) + ",\"sleep1MaxMs\":" + N(s[3]) + "}";
  }
}
'@
$exe="$env:ProgramData\BAKA\Desktop\BakaDesktop.exe"
$baka=Test-Path $exe
$r=[ordered]@{ system= if($baka){'BAKA'}else{'Stock'} }
function Get-Latency($tag){
  $r["$tag-input"]=([Lat]::Input(200) | ConvertFrom-Json)
  $r["$tag-timer-default"]=([Lat]::Timer(300,$false) | ConvertFrom-Json)
  $r["$tag-timer-1ms"]=([Lat]::Timer(300,$true) | ConvertFrom-Json)
  L ("$tag input: "+($r["$tag-input"]|ConvertTo-Json -Compress)+" timer: "+($r["$tag-timer-default"]|ConvertTo-Json -Compress)+" "+($r["$tag-timer-1ms"]|ConvertTo-Json -Compress))
}
L "start system=$($r.system) user=$env:USERNAME"
try{ Get-Latency 'desktop' }catch{ L "desktop measure failed: $($_.Exception.Message)" }
if($baka){
  & $exe --profile gaming; Start-Sleep 6
  try{ Get-Latency 'gaming' }catch{ L "gaming measure failed: $($_.Exception.Message)" }
  & $exe --profile desktop; Start-Sleep 3
}
$r | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $Out 'latency.json') -Encoding UTF8
L 'DONE'
'done' | Set-Content (Join-Path $Out 'done.txt')
