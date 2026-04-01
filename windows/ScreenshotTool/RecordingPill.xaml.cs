using System;
using System.Drawing;
using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;

namespace ScreenshotTool;

public partial class RecordingPill : Window
{
    private readonly DispatcherTimer _timer;
    private DateTime _startTime;

    public event Action? OnStop;

    public RecordingPill(Rectangle region)
    {
        InitializeComponent();

        // Position above the region, or below if no room
        var pillX = region.X + region.Width / 2 - Width / 2;
        var pillYAbove = region.Y - Height - 10;
        var pillYBelow = region.Y + region.Height + 10;

        Left = pillX;
        Top = pillYAbove >= 0 ? pillYAbove : pillYBelow;

        _startTime = DateTime.Now;
        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _timer.Tick += (s, e) =>
        {
            var elapsed = DateTime.Now - _startTime;
            TimerText.Text = $"REC {(int)elapsed.TotalMinutes}:{elapsed.Seconds:D2}";
        };
        _timer.Start();

        Loaded += (_, _) => { Focus(); Activate(); };
    }

    private void Stop_Click(object sender, RoutedEventArgs e)
    {
        _timer.Stop();
        OnStop?.Invoke();
    }

    private void Window_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            _timer.Stop();
            OnStop?.Invoke();
            e.Handled = true;
        }
    }
}
