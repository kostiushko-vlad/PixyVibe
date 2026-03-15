using System.Drawing;

namespace ScreenshotTool;

/// <summary>
/// Tracks the selection rectangle state during mouse drag.
/// </summary>
public class RegionSelector
{
    public Point StartPoint { get; set; }
    public Point CurrentPoint { get; set; }
    public bool IsSelecting { get; set; }

    public Rectangle GetSelectionRect()
    {
        var x = System.Math.Min(StartPoint.X, CurrentPoint.X);
        var y = System.Math.Min(StartPoint.Y, CurrentPoint.Y);
        var w = System.Math.Abs(CurrentPoint.X - StartPoint.X);
        var h = System.Math.Abs(CurrentPoint.Y - StartPoint.Y);
        return new Rectangle(x, y, w, h);
    }

    public bool HasValidSelection()
    {
        var rect = GetSelectionRect();
        return rect.Width > 10 && rect.Height > 10;
    }
}
