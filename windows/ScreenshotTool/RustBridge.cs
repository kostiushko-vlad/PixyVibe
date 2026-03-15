using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace ScreenshotTool;

public static class RustBridge
{
    private const string DLL = "screenshottool.dll";

    [StructLayout(LayoutKind.Sequential)]
    public struct SST_PixelData
    {
        public IntPtr pixels;
        public uint width;
        public uint height;
        public uint stride;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SST_ScreenshotResult
    {
        public IntPtr image_data;
        public nuint image_len;
        public IntPtr file_path;
        public IntPtr error;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SST_DiffResult
    {
        public IntPtr image_data;
        public nuint image_len;
        public IntPtr file_path;
        public float change_percentage;
        public IntPtr error;
    }

    [DllImport(DLL)] private static extern bool sst_init(string config_json);
    [DllImport(DLL)] private static extern void sst_shutdown();
    [DllImport(DLL)] private static extern SST_ScreenshotResult sst_process_screenshot(SST_PixelData pixels);
    [DllImport(DLL)] private static extern IntPtr sst_gif_start();
    [DllImport(DLL)] private static extern bool sst_gif_add_frame(string session_id, SST_PixelData pixels);
    [DllImport(DLL)] private static extern SST_ScreenshotResult sst_gif_finish(string session_id);
    [DllImport(DLL)] private static extern bool sst_diff_store_before(SST_PixelData pixels);
    [DllImport(DLL)] private static extern SST_DiffResult sst_diff_compare(SST_PixelData pixels);
    [DllImport(DLL)] private static extern void sst_free_result(SST_ScreenshotResult result);
    [DllImport(DLL)] private static extern void sst_free_string(IntPtr s);

    private static bool _initialized;

    public static void Initialize()
    {
        if (_initialized) return;
        _initialized = sst_init("{}");
    }

    public static void Shutdown()
    {
        if (!_initialized) return;
        sst_shutdown();
        _initialized = false;
    }

    public static byte[]? CaptureAndProcess(Rectangle rect)
    {
        using var bitmap = ScreenCapture.CaptureRegion(rect);
        var bitmapData = bitmap.LockBits(
            new Rectangle(0, 0, bitmap.Width, bitmap.Height),
            ImageLockMode.ReadOnly,
            PixelFormat.Format32bppArgb
        );

        try
        {
            var pixelData = new SST_PixelData
            {
                pixels = bitmapData.Scan0,
                width = (uint)bitmap.Width,
                height = (uint)bitmap.Height,
                stride = (uint)bitmapData.Stride
            };

            var result = sst_process_screenshot(pixelData);
            try
            {
                if (result.error != IntPtr.Zero) return null;
                var data = new byte[(int)result.image_len];
                Marshal.Copy(result.image_data, data, 0, (int)result.image_len);
                return data;
            }
            finally
            {
                sst_free_result(result);
            }
        }
        finally
        {
            bitmap.UnlockBits(bitmapData);
        }
    }

    public static string? GifStart()
    {
        var ptr = sst_gif_start();
        if (ptr == IntPtr.Zero) return null;
        var id = Marshal.PtrToStringAnsi(ptr)!;
        sst_free_string(ptr);
        return id;
    }

    public static bool GifAddFrame(string sessionId, Rectangle rect)
    {
        using var bitmap = ScreenCapture.CaptureRegion(rect);
        var bitmapData = bitmap.LockBits(
            new Rectangle(0, 0, bitmap.Width, bitmap.Height),
            ImageLockMode.ReadOnly,
            PixelFormat.Format32bppArgb
        );
        try
        {
            var pixelData = new SST_PixelData
            {
                pixels = bitmapData.Scan0,
                width = (uint)bitmap.Width,
                height = (uint)bitmap.Height,
                stride = (uint)bitmapData.Stride
            };
            return sst_gif_add_frame(sessionId, pixelData);
        }
        finally
        {
            bitmap.UnlockBits(bitmapData);
        }
    }

    public static byte[]? GifFinish(string sessionId)
    {
        var result = sst_gif_finish(sessionId);
        try
        {
            if (result.error != IntPtr.Zero) return null;
            var data = new byte[(int)result.image_len];
            Marshal.Copy(result.image_data, data, 0, (int)result.image_len);
            return data;
        }
        finally
        {
            sst_free_result(result);
        }
    }

    public static bool DiffStoreBefore(Rectangle rect)
    {
        using var bitmap = ScreenCapture.CaptureRegion(rect);
        var bitmapData = bitmap.LockBits(
            new Rectangle(0, 0, bitmap.Width, bitmap.Height),
            ImageLockMode.ReadOnly,
            PixelFormat.Format32bppArgb
        );
        try
        {
            var pixelData = new SST_PixelData
            {
                pixels = bitmapData.Scan0,
                width = (uint)bitmap.Width,
                height = (uint)bitmap.Height,
                stride = (uint)bitmapData.Stride
            };
            return sst_diff_store_before(pixelData);
        }
        finally
        {
            bitmap.UnlockBits(bitmapData);
        }
    }

    public static byte[]? DiffCompare(Rectangle rect)
    {
        using var bitmap = ScreenCapture.CaptureRegion(rect);
        var bitmapData = bitmap.LockBits(
            new Rectangle(0, 0, bitmap.Width, bitmap.Height),
            ImageLockMode.ReadOnly,
            PixelFormat.Format32bppArgb
        );
        try
        {
            var pixelData = new SST_PixelData
            {
                pixels = bitmapData.Scan0,
                width = (uint)bitmap.Width,
                height = (uint)bitmap.Height,
                stride = (uint)bitmapData.Stride
            };
            var result = sst_diff_compare(pixelData);
            try
            {
                if (result.error != IntPtr.Zero) return null;
                var data = new byte[(int)result.image_len];
                Marshal.Copy(result.image_data, data, 0, (int)result.image_len);
                return data;
            }
            finally
            {
                // Free diff result manually since struct is different
                if (result.image_data != IntPtr.Zero)
                    Marshal.FreeHGlobal(result.image_data);
                if (result.file_path != IntPtr.Zero)
                    sst_free_string(result.file_path);
                if (result.error != IntPtr.Zero)
                    sst_free_string(result.error);
            }
        }
        finally
        {
            bitmap.UnlockBits(bitmapData);
        }
    }
}
