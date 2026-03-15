using System;
using System.Windows;
using System.Windows.Controls;

namespace ScreenshotTool;

public partial class ActionToolbar : UserControl
{
    public event Action? OnScreenshot;
    public event Action? OnGif;
    public event Action? OnDiff;

    public ActionToolbar(bool isDiffAfterMode)
    {
        InitializeComponent();

        if (isDiffAfterMode)
        {
            BtnScreenshot.Visibility = Visibility.Collapsed;
            BtnGif.Visibility = Visibility.Collapsed;
            BtnDiff.Content = "Capture AFTER (D)";
        }
    }

    private void Screenshot_Click(object sender, RoutedEventArgs e) => OnScreenshot?.Invoke();
    private void Gif_Click(object sender, RoutedEventArgs e) => OnGif?.Invoke();
    private void Diff_Click(object sender, RoutedEventArgs e) => OnDiff?.Invoke();
}
