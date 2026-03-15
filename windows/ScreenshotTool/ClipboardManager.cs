using System.IO;
using System.Windows;
using System.Windows.Media.Imaging;

namespace ScreenshotTool;

public static class ClipboardManager
{
    public static void CopyImage(byte[] pngData)
    {
        using var ms = new MemoryStream(pngData);
        var decoder = new PngBitmapDecoder(ms, BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
        var frame = decoder.Frames[0];
        Clipboard.SetImage(frame);
    }

    public static void CopyFilePath(string path)
    {
        Clipboard.SetText(path);
    }
}
