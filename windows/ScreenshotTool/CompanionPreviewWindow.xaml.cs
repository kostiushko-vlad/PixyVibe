using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;
using ScreenshotTool.Models;

namespace ScreenshotTool;

public partial class CompanionPreviewWindow : Window
{
    private readonly string _deviceId;
    private readonly DispatcherTimer _frameTimer;
    private bool _hasFrame;

    // Region selection
    private Point? _regionStart;
    private Rectangle? _selectionRect;

    // GIF recording
    private bool _isRecording;
    private string? _gifSessionId;
    private DispatcherTimer? _gifTimer;

    public CompanionPreviewWindow(string deviceId)
    {
        InitializeComponent();
        _deviceId = deviceId;

        // Find device name
        var companions = RustBridge.ListCompanions();
        var device = companions.FirstOrDefault(d => d.DeviceId == deviceId);
        DeviceNameText.Text = device?.DeviceName ?? "Unknown Device";

        if (device?.Connected == true)
        {
            StatusDot.Fill = new SolidColorBrush(Color.FromRgb(0x10, 0xB9, 0x81));
        }

        // Frame polling timer
        _frameTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(100) };
        _frameTimer.Tick += PollFrame;
        _frameTimer.Start();

        Closed += (_, _) =>
        {
            _frameTimer.Stop();
            StopGifRecording();
        };
    }

    private void PollFrame(object? sender, EventArgs e)
    {
        var frameData = RustBridge.CompanionLatestFrame(_deviceId);
        if (frameData == null || frameData.Length == 0)
        {
            if (!_hasFrame)
            {
                ConnectionOverlay.Visibility = Visibility.Visible;
                OverlayTitle.Text = "Waiting for broadcast...";
                OverlaySubtitle.Text = "Start broadcasting from your companion app";
            }
            return;
        }

        _hasFrame = true;
        ConnectionOverlay.Visibility = Visibility.Collapsed;

        var bi = new BitmapImage();
        bi.BeginInit();
        bi.StreamSource = new MemoryStream(frameData);
        bi.CacheOption = BitmapCacheOption.OnLoad;
        bi.EndInit();
        bi.Freeze();
        PreviewImage.Source = bi;
    }

    private void Capture_Click(object sender, RoutedEventArgs e)
    {
        if (ModeGif.IsChecked == true)
        {
            if (_isRecording)
                StopGifRecording();
            else
                StartGifRecording();
            return;
        }

        // Screenshot mode
        var data = RustBridge.CompanionScreenshot(_deviceId);
        if (data != null)
        {
            ClipboardManager.CopyImage(data);
            // Save to captures folder
            var dir = string.IsNullOrEmpty(AppSettings.Instance.SaveLocation)
                ? System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".pixyvibe", "captures")
                : AppSettings.Instance.SaveLocation;
            Directory.CreateDirectory(dir);
            var path = System.IO.Path.Combine(dir, $"companion_{DateTime.Now:yyyyMMdd_HHmmss}.png");
            File.WriteAllBytes(path, data);
            ScreenshotHistory.Instance.Add(path, data);
            ToastHelper.Show("Companion screenshot captured");
        }
    }

    private void StartGifRecording()
    {
        _gifSessionId = RustBridge.GifStart();
        if (_gifSessionId == null) return;

        _isRecording = true;
        CaptureBtn.Content = "Stop Recording";

        var settings = AppSettings.Instance;
        var frameInterval = Math.Max(33, 1000 / settings.GifFps);

        _gifTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(frameInterval) };
        _gifTimer.Tick += (_, _) =>
        {
            var frame = RustBridge.CompanionLatestFrame(_deviceId);
            if (frame != null && _gifSessionId != null)
            {
                // Add frame via the Rust bridge - uses companion frame data
                // We need to process this through the GIF pipeline
                // For companion GIFs, we capture the preview image area
                var region = GetPreviewRegion();
                if (region.Width > 0 && region.Height > 0)
                    RustBridge.GifAddFrame(_gifSessionId, region);
            }
        };
        _gifTimer.Start();
    }

    private void StopGifRecording()
    {
        if (!_isRecording || _gifSessionId == null) return;

        _gifTimer?.Stop();
        _isRecording = false;
        CaptureBtn.Content = "Capture";

        var (data, path) = RustBridge.GifFinishWithPath(_gifSessionId);
        _gifSessionId = null;

        if (data != null)
        {
            ClipboardManager.CopyImage(data);
            ScreenshotHistory.Instance.Add(path, data);
            ToastHelper.Show("Companion GIF recorded");
        }
    }

    private System.Drawing.Rectangle GetPreviewRegion()
    {
        var point = PreviewImage.PointToScreen(new Point(0, 0));
        return new System.Drawing.Rectangle(
            (int)point.X, (int)point.Y,
            (int)PreviewImage.ActualWidth, (int)PreviewImage.ActualHeight);
    }

    private void Area_Changed(object sender, RoutedEventArgs e)
    {
        if (AreaRegion.IsChecked == true)
        {
            RegionCanvas.Visibility = Visibility.Visible;
            RegionCanvas.Cursor = Cursors.Cross;
        }
        else
        {
            RegionCanvas.Visibility = Visibility.Collapsed;
            ClearRegionSelection();
        }
    }

    private void Region_MouseDown(object sender, MouseButtonEventArgs e)
    {
        ClearRegionSelection();
        _regionStart = e.GetPosition(RegionCanvas);
        RegionCanvas.CaptureMouse();
    }

    private void Region_MouseMove(object sender, MouseEventArgs e)
    {
        if (_regionStart == null) return;
        var current = e.GetPosition(RegionCanvas);

        if (_selectionRect == null)
        {
            _selectionRect = new Rectangle
            {
                Stroke = new SolidColorBrush(Color.FromRgb(0x38, 0xBD, 0xF8)),
                StrokeThickness = 2,
                StrokeDashArray = { 4, 2 },
                Fill = new SolidColorBrush(Color.FromArgb(30, 0x38, 0xBD, 0xF8))
            };
            RegionCanvas.Children.Add(_selectionRect);
        }

        var x = Math.Min(_regionStart.Value.X, current.X);
        var y = Math.Min(_regionStart.Value.Y, current.Y);
        Canvas.SetLeft(_selectionRect, x);
        Canvas.SetTop(_selectionRect, y);
        _selectionRect.Width = Math.Abs(current.X - _regionStart.Value.X);
        _selectionRect.Height = Math.Abs(current.Y - _regionStart.Value.Y);
    }

    private void Region_MouseUp(object sender, MouseButtonEventArgs e)
    {
        RegionCanvas.ReleaseMouseCapture();
        _regionStart = null;
    }

    private void ClearRegionSelection()
    {
        if (_selectionRect != null)
        {
            RegionCanvas.Children.Remove(_selectionRect);
            _selectionRect = null;
        }
    }

    private void Window_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            if (_isRecording)
                StopGifRecording();
            else
                Close();
        }
    }
}
