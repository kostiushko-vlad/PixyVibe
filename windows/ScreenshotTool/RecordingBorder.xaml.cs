using System.Drawing;

namespace ScreenshotTool;

public partial class RecordingBorder : System.Windows.Window
{
    public RecordingBorder(Rectangle region)
    {
        InitializeComponent();

        var pad = 4;
        Left = region.X - pad;
        Top = region.Y - pad;
        Width = region.Width + pad * 2;
        Height = region.Height + pad * 2;
    }
}
