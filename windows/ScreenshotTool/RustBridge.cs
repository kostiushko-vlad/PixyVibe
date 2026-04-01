using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace ScreenshotTool;

public static class RustBridge
{
    private const string DLL = "pixyvibe_core";

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

    public delegate void SSTCaptureCallback(IntPtr pixelData);

    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern bool sst_init(string config_json);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern void sst_shutdown();
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern SST_ScreenshotResult sst_process_screenshot(SST_PixelData pixels);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr sst_gif_start();
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern bool sst_gif_add_frame(string session_id, SST_PixelData pixels);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern SST_ScreenshotResult sst_gif_finish(string session_id);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern bool sst_diff_store_before(SST_PixelData pixels);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern SST_DiffResult sst_diff_compare(SST_PixelData pixels);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern void sst_free_result(SST_ScreenshotResult result);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern void sst_free_string(IntPtr s);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr sst_list_companions();
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern SST_ScreenshotResult sst_companion_screenshot(string device_id);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern SST_ScreenshotResult sst_companion_latest_frame(string device_id);
    [DllImport(DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern void sst_register_capture_callback(SSTCaptureCallback callback);

    private static bool _initialized;
    private static SSTCaptureCallback? _callbackRef; // prevent GC

    public static void Initialize(string configJson = "{}")
    {
        if (_initialized) return;
        _initialized = sst_init(configJson);
    }

    public static void Shutdown()
    {
        if (!_initialized) return;
        sst_shutdown();
        _initialized = false;
    }

    public static void RegisterCaptureCallback(SSTCaptureCallback callback)
    {
        _callbackRef = callback;
        sst_register_capture_callback(callback);
    }

    // Screenshot — returns (imageData, filePath)
    public static (byte[]? imageData, string? filePath) CaptureAndProcessWithPath(Rectangle rect)
    {
        using var bitmap = ScreenCapture.CaptureRegion(rect);
        var pixelData = LockAndCreatePixelData(bitmap, out var bitmapData);
        try
        {
            var result = sst_process_screenshot(pixelData);
            try
            {
                if (result.error != IntPtr.Zero) return (null, null);
                var data = new byte[(int)result.image_len];
                Marshal.Copy(result.image_data, data, 0, (int)result.image_len);
                var path = result.file_path != IntPtr.Zero ? Marshal.PtrToStringAnsi(result.file_path) : null;
                return (data, path);
            }
            finally { sst_free_result(result); }
        }
        finally { bitmap.UnlockBits(bitmapData); }
    }

    public static byte[]? CaptureAndProcess(Rectangle rect)
    {
        return CaptureAndProcessWithPath(rect).imageData;
    }

    // GIF
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
        var pixelData = LockAndCreatePixelData(bitmap, out var bitmapData);
        try { return sst_gif_add_frame(sessionId, pixelData); }
        finally { bitmap.UnlockBits(bitmapData); }
    }

    public static (byte[]? imageData, string? filePath) GifFinishWithPath(string sessionId)
    {
        var result = sst_gif_finish(sessionId);
        try
        {
            if (result.error != IntPtr.Zero) return (null, null);
            var data = new byte[(int)result.image_len];
            Marshal.Copy(result.image_data, data, 0, (int)result.image_len);
            var path = result.file_path != IntPtr.Zero ? Marshal.PtrToStringAnsi(result.file_path) : null;
            return (data, path);
        }
        finally { sst_free_result(result); }
    }

    public static byte[]? GifFinish(string sessionId) => GifFinishWithPath(sessionId).imageData;

    // Diff
    public static bool DiffStoreBefore(Rectangle rect)
    {
        using var bitmap = ScreenCapture.CaptureRegion(rect);
        var pixelData = LockAndCreatePixelData(bitmap, out var bitmapData);
        try { return sst_diff_store_before(pixelData); }
        finally { bitmap.UnlockBits(bitmapData); }
    }

    public static (byte[]? imageData, string? filePath) DiffCompareWithPath(Rectangle rect)
    {
        using var bitmap = ScreenCapture.CaptureRegion(rect);
        var pixelData = LockAndCreatePixelData(bitmap, out var bitmapData);
        try
        {
            var result = sst_diff_compare(pixelData);
            try
            {
                if (result.error != IntPtr.Zero) return (null, null);
                var data = new byte[(int)result.image_len];
                Marshal.Copy(result.image_data, data, 0, (int)result.image_len);
                var path = result.file_path != IntPtr.Zero ? Marshal.PtrToStringAnsi(result.file_path) : null;
                return (data, path);
            }
            finally
            {
                if (result.image_data != IntPtr.Zero) Marshal.FreeHGlobal(result.image_data);
                if (result.file_path != IntPtr.Zero) sst_free_string(result.file_path);
                if (result.error != IntPtr.Zero) sst_free_string(result.error);
            }
        }
        finally { bitmap.UnlockBits(bitmapData); }
    }

    public static byte[]? DiffCompare(Rectangle rect) => DiffCompareWithPath(rect).imageData;

    // Companion devices
    public static List<CompanionDevice> ListCompanions()
    {
        var ptr = sst_list_companions();
        if (ptr == IntPtr.Zero) return new List<CompanionDevice>();
        var json = Marshal.PtrToStringAnsi(ptr)!;
        sst_free_string(ptr);
        try
        {
            return JsonSerializer.Deserialize<List<CompanionDevice>>(json,
                new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower })
                ?? new List<CompanionDevice>();
        }
        catch { return new List<CompanionDevice>(); }
    }

    public static byte[]? CompanionScreenshot(string deviceId)
    {
        var result = sst_companion_screenshot(deviceId);
        try
        {
            if (result.error != IntPtr.Zero) return null;
            if (result.image_len == 0) return null;
            var data = new byte[(int)result.image_len];
            Marshal.Copy(result.image_data, data, 0, (int)result.image_len);
            return data;
        }
        finally { sst_free_result(result); }
    }

    public static byte[]? CompanionLatestFrame(string deviceId)
    {
        var result = sst_companion_latest_frame(deviceId);
        try
        {
            if (result.error != IntPtr.Zero) return null;
            if (result.image_len == 0) return null;
            var data = new byte[(int)result.image_len];
            Marshal.Copy(result.image_data, data, 0, (int)result.image_len);
            return data;
        }
        finally { sst_free_result(result); }
    }

    // Helpers
    private static SST_PixelData LockAndCreatePixelData(Bitmap bitmap, out BitmapData bitmapData)
    {
        bitmapData = bitmap.LockBits(
            new Rectangle(0, 0, bitmap.Width, bitmap.Height),
            ImageLockMode.ReadOnly,
            PixelFormat.Format32bppArgb);

        return new SST_PixelData
        {
            pixels = bitmapData.Scan0,
            width = (uint)bitmap.Width,
            height = (uint)bitmap.Height,
            stride = (uint)bitmapData.Stride
        };
    }
}

public class CompanionDevice
{
    public string DeviceId { get; set; } = "";
    public string DeviceName { get; set; } = "";
    public bool Connected { get; set; }
}
