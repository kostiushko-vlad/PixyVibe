using System;
using System.IO;
using System.Windows;
using System.Windows.Media.Imaging;

namespace ScreenshotTool;

public static class ClipboardManager
{
    public static void CopyImage(byte[] imageData)
    {
        using var ms = new MemoryStream(imageData);
        BitmapDecoder decoder;
        try
        {
            decoder = BitmapDecoder.Create(ms, BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
        }
        catch
        {
            // If decoding fails, copy raw bytes as file drop (for GIF etc.)
            Clipboard.SetData("image", imageData);
            return;
        }

        if (decoder.Frames.Count > 0)
            Clipboard.SetImage(decoder.Frames[0]);
    }

    public static void CopyFilePath(string path)
    {
        Clipboard.SetText(path);
    }
}
