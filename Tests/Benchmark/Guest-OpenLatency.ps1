# Runs INSIDE a test VM in the signed-in user's session. How long after the key press does the start
# surface appear? Windows key: BAKA Launchpad (BAKA) or Start (stock). Win+E: BAKA Files or File Explorer.
param([string]$Out,[int]$N=10)
$ErrorActionPreference='Continue'
New-Item -ItemType Directory -Path $Out -Force | Out-Null
$log=Join-Path $Out 'open.txt'
function L($m){Add-Content -LiteralPath $log -Value ('{0} {1}' -f (Get-Date -Format s),$m)}
Add-Type -TypeDefinition @'
using System; using System.Diagnostics; using System.Runtime.InteropServices; using System.Text; using System.Collections.Generic;
public static class OpenLat {
  [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr FindWindow(string cls, string title);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
  static string Cls(IntPtr h){ var s=new StringBuilder(256); GetClassName(h,s,256); return s.ToString(); }
  static string Txt(IntPtr h){ var s=new StringBuilder(256); GetWindowText(h,s,256); return s.ToString(); }
  static bool Cloaked(IntPtr h){ int v; return DwmGetWindowAttribute(h,14,out v,4)==0 && v!=0; }
  static string FgProc(){ uint pid; GetWindowThreadProcessId(GetForegroundWindow(), out pid); try { return Process.GetProcessById((int)pid).ProcessName; } catch { return ""; } }
  static double Ms(long t0){ return (Stopwatch.GetTimestamp()-t0)*1000.0/Stopwatch.Frequency; }
  static List<IntPtr> Windows(Func<IntPtr,bool> f){ var l=new List<IntPtr>(); EnumWindows((h,x)=>{ if(IsWindowVisible(h) && !Cloaked(h) && f(h)) l.Add(h); return true; }, IntPtr.Zero); return l; }
  public static bool startAlsoOpened;
  // Windows key alone. Returns ms until the start surface is visible and in front, or -1.
  public static double WinKey(bool baka){
    long t0=Stopwatch.GetTimestamp();
    // a quick human tap holds the key about 50 ms; time is measured from the release, when Start/Launchpad open
    keybd_event(0x5B,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(50); t0=Stopwatch.GetTimestamp(); keybd_event(0x5B,0,2,UIntPtr.Zero);
    while(Ms(t0)<3000){
      if(baka){ var h=FindWindow(null,"BAKA Launchpad"); if(h!=IntPtr.Zero && IsWindowVisible(h) && GetForegroundWindow()==h){ double t=Ms(t0); System.Threading.Thread.Sleep(250); startAlsoOpened = FgProc()=="SearchHost" || FgProc()=="StartMenuExperienceHost"; return t; } }
      else { var fg=FgProc(); if(fg=="StartMenuExperienceHost" || fg=="SearchHost") return Ms(t0);
             if(Windows(h => Cls(h)=="Windows.UI.Core.CoreWindow" && Txt(h)=="Start").Count>0) return Ms(t0); }
      System.Threading.Thread.Sleep(1);
    }
    return -1;
  }
  public static string Foreground(){ var h=GetForegroundWindow(); return Cls(h)+" | "+Txt(h)+" | "+FgProc()+" | launchpad="+(FindWindow(null,"BAKA Launchpad")!=IntPtr.Zero && IsWindowVisible(FindWindow(null,"BAKA Launchpad"))); }
  public static string VisibleCore(){ var sb=new StringBuilder(); foreach(var h in Windows(x => Cls(x)=="Windows.UI.Core.CoreWindow")) sb.Append("["+Txt(h)+"]"); return sb.ToString(); }
  public static void Escape(){ keybd_event(0x1B,0,0,UIntPtr.Zero); keybd_event(0x1B,0,2,UIntPtr.Zero); }
  // Win+E. Returns ms until a new file window is visible, then closes it.
  public static double WinE(bool baka){
    Func<IntPtr,bool> isFiles = h => baka ? Txt(h).EndsWith("BAKA Files") : Cls(h)=="CabinetWClass";
    var before=new HashSet<IntPtr>(Windows(isFiles));
    long t0=Stopwatch.GetTimestamp();
    keybd_event(0x5B,0,0,UIntPtr.Zero); keybd_event(0x45,0,0,UIntPtr.Zero); keybd_event(0x45,0,2,UIntPtr.Zero); keybd_event(0x5B,0,2,UIntPtr.Zero);
    while(Ms(t0)<8000){
      foreach(var h in Windows(isFiles)) if(!before.Contains(h)){ double t=Ms(t0); System.Threading.Thread.Sleep(600); PostMessage(h,0x0010,IntPtr.Zero,IntPtr.Zero); return t; }
      System.Threading.Thread.Sleep(1);
    }
    return -1;
  }
}
'@
$baka=Test-Path "$env:ProgramData\BAKA\Desktop\BakaDesktop.exe"
L "start baka=$baka user=$env:USERNAME"
$res=[ordered]@{ system= if($baka){'BAKA'}else{'Stock'}; winKey=@(); winE=@() }
Start-Sleep 2
L ("before: fg=" + [OpenLat]::Foreground() + " core=" + [OpenLat]::VisibleCore())
$res.startAlsoOpened=0
for($i=0;$i -lt $N;$i++){ [OpenLat]::startAlsoOpened=$false; $t=[OpenLat]::WinKey($baka); $res.winKey+=[math]::Round($t,1); if([OpenLat]::startAlsoOpened){$res.startAlsoOpened++}; Start-Sleep -Milliseconds 300
  if($i -lt 3){ L ("after win $($i): t=$t fg=" + [OpenLat]::Foreground() + " core=" + [OpenLat]::VisibleCore()) }
  Start-Sleep -Milliseconds 400; [OpenLat]::Escape(); Start-Sleep -Milliseconds 1300 }
for($i=0;$i -lt [math]::Min($N,6);$i++){ $t=[OpenLat]::WinE($baka); $res.winE+=[math]::Round($t,1); Start-Sleep -Milliseconds 1500 }
L ("winKey ms: " + ($res.winKey -join ', ') + "; Start/Search also opened: $($res.startAlsoOpened)")
L ("winE ms: " + ($res.winE -join ', '))
$res | ConvertTo-Json | Set-Content (Join-Path $Out 'open.json')
'done' | Set-Content (Join-Path $Out 'done.txt')
