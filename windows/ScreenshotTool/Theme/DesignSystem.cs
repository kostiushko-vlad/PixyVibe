using System.Windows.Media;

namespace ScreenshotTool.Theme;

public static class PV
{
    // Colors
    public static readonly Color BaseColor = FromHex(0x0D0F14);
    public static readonly Color SurfaceColor = FromHex(0x161B22);
    public static readonly Color SurfaceHighColor = FromHex(0x1C2333);
    public static readonly Color BorderColor = FromHex(0x2D3548);
    public static readonly Color TextPrimaryColor = FromHex(0xE6EDF3);
    public static readonly Color TextSecondaryColor = FromHex(0x8B949E);

    // Brushes
    public static readonly SolidColorBrush Base = Freeze(new SolidColorBrush(BaseColor));
    public static readonly SolidColorBrush Surface = Freeze(new SolidColorBrush(SurfaceColor));
    public static readonly SolidColorBrush SurfaceHigh = Freeze(new SolidColorBrush(SurfaceHighColor));
    public static readonly SolidColorBrush Border = Freeze(new SolidColorBrush(BorderColor));
    public static readonly SolidColorBrush TextPrimary = Freeze(new SolidColorBrush(TextPrimaryColor));
    public static readonly SolidColorBrush TextSecondary = Freeze(new SolidColorBrush(TextSecondaryColor));
    public static readonly SolidColorBrush Transparent = Freeze(new SolidColorBrush(Colors.Transparent));

    // Accent gradient colors
    private static readonly Color AccentStart = FromHex(0x38BDF8);
    private static readonly Color AccentEnd = FromHex(0x818CF8);
    private static readonly Color RecordingStart = FromHex(0xEF4444);
    private static readonly Color RecordingEnd = FromHex(0xF97316);
    private static readonly Color SuccessStart = FromHex(0x10B981);
    private static readonly Color SuccessEnd = FromHex(0x06B6D4);

    // Solid accent brush
    public static readonly SolidColorBrush AccentSolid = Freeze(new SolidColorBrush(AccentStart));

    // Border helpers
    public static readonly SolidColorBrush BorderThin = Freeze(new SolidColorBrush(Color.FromArgb(15, 255, 255, 255)));
    public static readonly SolidColorBrush BorderFocus = Freeze(new SolidColorBrush(Color.FromArgb(26, 255, 255, 255)));

    // Radii
    public const double RadiusSmall = 8;
    public const double RadiusMedium = 12;
    public const double RadiusLarge = 16;

    // Gradient brushes
    public static LinearGradientBrush AccentGradient => MakeGradient(AccentStart, AccentEnd);
    public static LinearGradientBrush RecordingGradient => MakeGradient(RecordingStart, RecordingEnd);
    public static LinearGradientBrush SuccessGradient => MakeGradient(SuccessStart, SuccessEnd);

    // Editor colors
    public static readonly Color[] EditorColors =
    {
        FromHex(0xEF4444), // Red
        FromHex(0xF97316), // Orange
        FromHex(0xEAB308), // Yellow
        FromHex(0x22C55E), // Green
        FromHex(0x3B82F6), // Blue
        FromHex(0xA855F7), // Purple
        Colors.White,
        Colors.Black
    };

    private static Color FromHex(uint hex)
    {
        var r = (byte)((hex >> 16) & 0xFF);
        var g = (byte)((hex >> 8) & 0xFF);
        var b = (byte)(hex & 0xFF);
        return Color.FromRgb(r, g, b);
    }

    private static LinearGradientBrush MakeGradient(Color start, Color end)
    {
        var brush = new LinearGradientBrush(start, end, 0);
        brush.Freeze();
        return brush;
    }

    private static SolidColorBrush Freeze(SolidColorBrush brush)
    {
        brush.Freeze();
        return brush;
    }
}
