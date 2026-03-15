using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace ScreenshotTool;

public static class ToastHelper
{
    private static Window? _currentToast;

    public static void Show(string message, double durationSeconds = 2.0)
    {
        Application.Current.Dispatcher.Invoke(() =>
        {
            _currentToast?.Close();

            var label = new TextBlock
            {
                Text = message,
                Foreground = Brushes.White,
                FontSize = 14,
                FontWeight = FontWeights.Medium,
                Padding = new Thickness(20, 12, 20, 12)
            };

            var border = new Border
            {
                Background = new SolidColorBrush(Color.FromArgb(220, 0, 0, 0)),
                CornerRadius = new CornerRadius(10),
                Child = label
            };

            var toast = new Window
            {
                WindowStyle = WindowStyle.None,
                AllowsTransparency = true,
                Background = Brushes.Transparent,
                Topmost = true,
                ShowInTaskbar = false,
                SizeToContent = SizeToContent.WidthAndHeight,
                Content = border,
                ResizeMode = ResizeMode.NoResize
            };

            toast.Loaded += (s, e) =>
            {
                var screen = SystemParameters.WorkArea;
                toast.Left = screen.Right - toast.ActualWidth - 20;
                toast.Top = screen.Top + 20;
            };

            toast.Show();
            _currentToast = toast;

            var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(durationSeconds) };
            timer.Tick += (s, e) =>
            {
                timer.Stop();
                toast.Close();
                if (_currentToast == toast) _currentToast = null;
            };
            timer.Start();
        });
    }
}
