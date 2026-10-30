using System;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using global::Windows.Graphics.DirectX;
using global::Windows.Graphics.Imaging;
using global::Windows.Media;
using global::Windows.Media.Core;
using MediaPlayer = global::Windows.Media.Playback.MediaPlayer;

namespace Baka.Desktop
{
    // A looping, muted video for the dock / menu bar / widget backgrounds, drawn into a small picture.
    // WPF's built-in player needs Windows Media Player, which this Windows edition removed, so it failed with
    // "Windows Media Player version 10 or later is required". Windows' media engine (the one Movies & TV and
    // the Store apps use) decodes on the graphics card instead: each frame is scaled on the GPU into a
    // 640 x 360 surface, copied out, and written into a WPF bitmap that the background brushes show.
    // At most 20 frames a second, nothing while paused (games, gaming profile).
    sealed class SurfaceVideo : IDisposable
    {
        public const int W = 640, H = 360;
        const int MaxFps = 20;
        public readonly WriteableBitmap Bitmap = new WriteableBitmap(W, H, 96, 96, PixelFormats.Bgra32, null);
        readonly string path;
        MediaPlayer player;
        VideoFrame gpuFrame, cpuFrame;
        byte[] pixels = new byte[W * H * 4];
        volatile bool busy, disposed, paused;
        DateTime lastFrame = DateTime.MinValue;
        int frames;

        public SurfaceVideo(string path, bool startPaused)
        {
            this.path = path; paused = startPaused;
            try
            {
                player = new MediaPlayer { IsMuted = true, IsLoopingEnabled = true, IsVideoFrameServerEnabled = true, AutoPlay = !startPaused };
                player.VideoFrameAvailable += OnFrame;
                player.MediaFailed += (s, e) => Log.Write("surface-video-failed path=\"" + path + "\" error=\"" + e.ErrorMessage + " " + e.Error + "\"");
                player.MediaOpened += (s, e) => Log.Write("surface-video-playing path=\"" + path + "\"");
                player.Source = MediaSource.CreateFromUri(new Uri(path));
            }
            catch (Exception e) { Log.Write("surface-video-failed path=\"" + path + "\" error=\"" + e.Message + "\""); }
        }

        void OnFrame(MediaPlayer sender, object args)
        {
            if (disposed || paused || busy) return;
            var now = DateTime.UtcNow;
            if ((now - lastFrame).TotalMilliseconds < 1000.0 / MaxFps) return;
            lastFrame = now; busy = true;
            CopyFrame().ContinueWith(t => { busy = false; if (t.Exception != null && frames < 3) Log.Write("surface-video-frame-failed error=\"" + t.Exception.GetBaseException().Message + "\""); });
        }

        async Task CopyFrame()
        {
            if (gpuFrame == null) gpuFrame = VideoFrame.CreateAsDirect3D11SurfaceBacked(DirectXPixelFormat.B8G8R8A8UIntNormalized, W, H);
            if (cpuFrame == null) cpuFrame = new VideoFrame(BitmapPixelFormat.Bgra8, W, H, BitmapAlphaMode.Premultiplied);
            player.CopyFrameToVideoSurface(gpuFrame.Direct3DSurface);   // decode + scale on the GPU
            await gpuFrame.CopyToAsync(cpuFrame);                        // read back the small frame
            cpuFrame.SoftwareBitmap.CopyToBuffer(pixels.AsBuffer());
            if (frames++ == 0) Log.Write("surface-video-first-frame path=\"" + path + "\"");
            var app = Application.Current;
            if (app == null || disposed) return;
            await app.Dispatcher.InvokeAsync(() =>
            {
                if (disposed) return;
                Bitmap.WritePixels(new Int32Rect(0, 0, W, H), pixels, W * 4, 0);
            }, System.Windows.Threading.DispatcherPriority.Render);
        }

        public void SetPaused(bool pause)
        {
            paused = pause;
            try { if (pause) player?.Pause(); else player?.Play(); } catch { }
        }

        public void Dispose()
        {
            disposed = true;
            try { if (player != null) { player.VideoFrameAvailable -= OnFrame; player.Pause(); player.Source = null; player.Dispose(); } } catch { }
            try { gpuFrame?.Dispose(); cpuFrame?.Dispose(); } catch { }
            player = null;
        }
    }
}
