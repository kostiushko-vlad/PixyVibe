using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace ScreenshotTool;

public static class ScreenCapture
{
    /// <summary>
    /// Capture a region of the screen using GDI+.
    /// </summary>
    public static Bitmap CaptureRegion(Rectangle rect)
    {
        var bitmap = new Bitmap(rect.Width, rect.Height, PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(bitmap);
        g.CopyFromScreen(rect.Left, rect.Top, 0, 0, rect.Size);
        return bitmap;
    }

    /// <summary>
    /// Extract raw RGBA pixel data from a bitmap.
    /// </summary>
    public static (IntPtr pixels, int width, int height, int stride) GetPixelData(Bitmap bitmap)
    {
        var bitmapData = bitmap.LockBits(
            new Rectangle(0, 0, bitmap.Width, bitmap.Height),
            ImageLockMode.ReadOnly,
            PixelFormat.Format32bppArgb
        );

        return (bitmapData.Scan0, bitmap.Width, bitmap.Height, bitmapData.Stride);
    }

    /// <summary>
    /// Convert bitmap to PNG byte array.
    /// </summary>
    public static byte[] ToPngBytes(Bitmap bitmap)
    {
        using var ms = new System.IO.MemoryStream();
        bitmap.Save(ms, ImageFormat.Png);
        return ms.ToArray();
    }
}
