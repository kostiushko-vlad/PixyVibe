using System;
using System.Drawing;
using System.Windows;
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

        // Position near the capture region
        Left = region.X + region.Width / 2 - Width / 2;
        Top = region.Y - Height - 10;

        _startTime = DateTime.Now;
        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _timer.Tick += (s, e) =>
        {
            var elapsed = DateTime.Now - _startTime;
            TimerText.Text = $"REC {(int)elapsed.TotalMinutes}:{elapsed.Seconds:D2}";
        };
        _timer.Start();
    }

    private void Stop_Click(object sender, RoutedEventArgs e)
    {
        _timer.Stop();
        OnStop?.Invoke();
    }
}
