using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using ScreenshotTool.Models;

namespace ScreenshotTool;

public partial class CompanionPreviewWindow : Window
{
    private readonly string _deviceId;
    private readonly DispatcherTimer _frameTimer;
    private bool _hasFrame;
    private bool _broadcastRequested;

    public event Action<byte[], string?>? OnCaptured;

    private enum CMode { Screenshot, Gif }
    private enum AMode { Full, Region }
    private enum RecState { Idle, Ready, Recording }

    private CMode _captureMode = CMode.Screenshot;
    private AMode _areaMode = AMode.Full;
    private RecState _recordingState = RecState.Idle;
    private DateTime _recordingStart;
    private DispatcherTimer? _recTimer;

    public CompanionPreviewWindow(string deviceId)
    {
        InitializeComponent();
        _deviceId = deviceId;

        var companions = RustBridge.ListCompanions();
        var device = companions.FirstOrDefault(d => d.DeviceId == deviceId);
        DeviceNameText.Text = device?.DeviceName ?? "Unknown Device";

        if (device?.Connected == true)
            StatusDot.Fill = new SolidColorBrush(Color.FromRgb(0x10, 0xB9, 0x81));

        _frameTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(100) };
        _frameTimer.Tick += PollFrame;
        _frameTimer.Start();

        Closed += (_, _) => { _frameTimer.Stop(); _recTimer?.Stop(); };

        RebuildToolbar();
    }

    // --- Toolbar state ---

    private void RebuildToolbar()
    {
        var accent = new SolidColorBrush(Color.FromArgb(38, 0x38, 0xBD, 0xF8));
        var accentBorder = new LinearGradientBrush(
            Color.FromRgb(0x38, 0xBD, 0xF8), Color.FromRgb(0x81, 0x8C, 0xF8), 0);
        var clear = Brushes.Transparent;
        var textPrimary = new SolidColorBrush(Color.FromRgb(0xE6, 0xED, 0xF3));
        var textSecondary = new SolidColorBrush(Color.FromRgb(0x8B, 0x94, 0x9E));

        // Mode buttons
        var isSS = _captureMode == CMode.Screenshot && _recordingState != RecState.Recording;
        BtnScreenshot.Background = isSS ? accent : clear;
        BtnScreenshot.BorderBrush = isSS ? accentBorder : clear;
        BtnScreenshot.BorderThickness = new Thickness(isSS ? 1.5 : 0);
        LblScreenshot.Foreground = isSS ? textPrimary : textSecondary;

        var isGif = _captureMode == CMode.Gif && _recordingState != RecState.Recording;
        BtnGif.Background = isGif ? accent : clear;
        BtnGif.BorderBrush = isGif ? accentBorder : clear;
        BtnGif.BorderThickness = new Thickness(isGif ? 1.5 : 0);
        LblGif.Foreground = isGif ? textPrimary : textSecondary;

        // Area toggle (only in GIF mode, not recording)
        var showArea = _captureMode == CMode.Gif && _recordingState != RecState.Recording;
        AreaDivider.Visibility = showArea ? Visibility.Visible : Visibility.Collapsed;
        BtnFull.Visibility = showArea ? Visibility.Visible : Visibility.Collapsed;
        BtnRegion.Visibility = showArea ? Visibility.Visible : Visibility.Collapsed;

        if (showArea)
        {
            var isFull = _areaMode == AMode.Full;
            BtnFull.Background = isFull ? new SolidColorBrush(Color.FromArgb(38, 255, 255, 255)) : clear;
            BtnRegion.Background = !isFull ? new SolidColorBrush(Color.FromArgb(38, 255, 255, 255)) : clear;
        }

        // Start/Stop button
        if (_recordingState == RecState.Recording)
        {
            BtnScreenshot.Visibility = Visibility.Collapsed;
            BtnGif.Visibility = Visibility.Collapsed;
            AreaDivider.Visibility = Visibility.Collapsed;
            BtnFull.Visibility = Visibility.Collapsed;
            BtnRegion.Visibility = Visibility.Collapsed;

            StartDivider.Visibility = Visibility.Collapsed;
            BtnStart.Visibility = Visibility.Visible;
            BtnStart.Background = new LinearGradientBrush(
                Color.FromRgb(0xEF, 0x44, 0x44), Color.FromRgb(0xF9, 0x73, 0x16), 0);
            LblStart.Text = $"REC {FormatTime(DateTime.Now - _recordingStart)}  Stop";
        }
        else
        {
            BtnScreenshot.Visibility = Visibility.Visible;
            BtnGif.Visibility = Visibility.Visible;

            var showStart = _captureMode == CMode.Gif;
            StartDivider.Visibility = showStart ? Visibility.Visible : Visibility.Collapsed;
            BtnStart.Visibility = showStart ? Visibility.Visible : Visibility.Collapsed;

            if (showStart)
            {
                BtnStart.Background = new LinearGradientBrush(
                    Color.FromRgb(0x10, 0xB9, 0x81), Color.FromRgb(0x06, 0xB6, 0xD4), 0);
                LblStart.Text = "Start";
            }
        }

        Title = _captureMode == CMode.Gif
            ? $"iPhone Live View — click to record GIF {(_areaMode == AMode.Full ? "full screen" : "region")}"
            : "iPhone Live View — click to screenshot";
    }

    // --- Mode/Area handlers ---

    private void Mode_Screenshot(object sender, MouseButtonEventArgs e)
    {
        _captureMode = CMode.Screenshot;
        RebuildToolbar();
        e.Handled = true;
    }

    private void Mode_Gif(object sender, MouseButtonEventArgs e)
    {
        _captureMode = CMode.Gif;
        RebuildToolbar();
        e.Handled = true;
    }

    private void Area_Full(object sender, MouseButtonEventArgs e)
    {
        _areaMode = AMode.Full;
        RebuildToolbar();
        e.Handled = true;
    }

    private void Area_Region(object sender, MouseButtonEventArgs e)
    {
        _areaMode = AMode.Region;
        RebuildToolbar();
        e.Handled = true;
    }

    private void Start_Click(object sender, MouseButtonEventArgs e)
    {
        if (_recordingState == RecState.Recording)
            StopGifRecording();
        else
            StartGifRecording();
        e.Handled = true;
    }

    // --- Frame polling ---

    private void PollFrame(object? sender, EventArgs e)
    {
        var frameData = RustBridge.CompanionLatestFrame(_deviceId);
        if (frameData == null || frameData.Length == 0)
        {
            if (!_hasFrame)
            {
                ConnectionOverlay.Visibility = Visibility.Visible;
                if (!_broadcastRequested)
                {
                    _broadcastRequested = true;
                    System.Threading.Tasks.Task.Run(() => RustBridge.CompanionScreenshot(_deviceId));
                }
            }
            return;
        }

        _hasFrame = true;
        ConnectionOverlay.Visibility = Visibility.Collapsed;

        try
        {
            var bi = new BitmapImage();
            bi.BeginInit();
            bi.StreamSource = new MemoryStream(frameData);
            bi.CacheOption = BitmapCacheOption.OnLoad;
            bi.EndInit();
            bi.Freeze();
            PreviewImage.Source = bi;
        }
        catch { }
    }

    // --- Screenshot ---

    private void CaptureScreenshot()
    {
        var data = RustBridge.CompanionScreenshot(_deviceId);
        if (data != null)
        {
            ClipboardManager.CopyImage(data);
            var dir = string.IsNullOrEmpty(AppSettings.Instance.SaveLocation)
                ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".pixyvibe", "captures")
                : AppSettings.Instance.SaveLocation;
            Directory.CreateDirectory(dir);
            var path = Path.Combine(dir, $"companion_{DateTime.Now:yyyyMMdd_HHmmss}.png");
            File.WriteAllBytes(path, data);
            ScreenshotHistory.Instance.Add(path, data);
            Close();
            OnCaptured?.Invoke(data, path);
        }
    }

    // --- GIF Recording ---

    private void StartGifRecording()
    {
        _recordingState = RecState.Recording;
        _recordingStart = DateTime.Now;
        RebuildToolbar();

        _recTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _recTimer.Tick += (_, _) => RebuildToolbar(); // update timer display
        _recTimer.Start();

        // Start capturing frames via the Rust GIF pipeline
        var sessionId = RustBridge.GifStart();
        if (sessionId == null) { _recordingState = RecState.Idle; RebuildToolbar(); return; }

        var settings = AppSettings.Instance;
        var frameInterval = Math.Max(33, 1000 / settings.GifFps);

        var gifTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(frameInterval) };
        gifTimer.Tick += (_, _) =>
        {
            // Capture the preview area as a frame
            var region = GetPreviewRegion();
            if (region.Width > 0 && region.Height > 0)
                RustBridge.GifAddFrame(sessionId, region);
        };
        gifTimer.Start();

        // Store for stop
        _gifFrameTimer = gifTimer;
        _gifSessionId = sessionId;
    }

    private DispatcherTimer? _gifFrameTimer;
    private string? _gifSessionId;

    private void StopGifRecording()
    {
        _recordingState = RecState.Idle;
        _recTimer?.Stop();
        _gifFrameTimer?.Stop();
        RebuildToolbar();

        if (_gifSessionId != null)
        {
            var (data, path) = RustBridge.GifFinishWithPath(_gifSessionId);
            _gifSessionId = null;
            if (data != null)
            {
                ClipboardManager.CopyImage(data);
                ScreenshotHistory.Instance.Add(path, data);
                Close();
                OnCaptured?.Invoke(data, path);
            }
        }
    }

    private System.Drawing.Rectangle GetPreviewRegion()
    {
        var point = PreviewImage.PointToScreen(new Point(0, 0));
        return new System.Drawing.Rectangle(
            (int)point.X, (int)point.Y,
            (int)PreviewImage.ActualWidth, (int)PreviewImage.ActualHeight);
    }

    // --- Region selection on preview ---

    private Point? _regionStart;
    private System.Windows.Shapes.Rectangle? _selectionRect;
    private byte[]? _currentFrameData;

    private void Preview_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (_recordingState == RecState.Recording) return;

        // Clear previous selection
        if (_selectionRect != null)
        {
            RegionCanvas.Children.Remove(_selectionRect);
            _selectionRect = null;
        }

        _regionStart = e.GetPosition(RegionCanvas);
        RegionCanvas.CaptureMouse();
        e.Handled = true;
    }

    private void Preview_MouseMove(object sender, MouseEventArgs e)
    {
        if (_regionStart == null) return;
        var current = e.GetPosition(RegionCanvas);

        if (_selectionRect == null)
        {
            _selectionRect = new System.Windows.Shapes.Rectangle
            {
                Stroke = new SolidColorBrush(Color.FromRgb(0x38, 0xBD, 0xF8)),
                StrokeThickness = 2,
                StrokeDashArray = new DoubleCollection { 4, 2 },
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

    private void Preview_MouseUp(object sender, MouseButtonEventArgs e)
    {
        RegionCanvas.ReleaseMouseCapture();
        var start = _regionStart;
        _regionStart = null;

        if (_captureMode == CMode.Screenshot)
        {
            // If no drag (click) or tiny region → full screenshot
            if (_selectionRect == null || _selectionRect.Width < 5 || _selectionRect.Height < 5)
            {
                if (_selectionRect != null)
                {
                    RegionCanvas.Children.Remove(_selectionRect);
                    _selectionRect = null;
                }
                CaptureScreenshot();
            }
            else
            {
                // Region screenshot — capture the screen region under the selection
                var region = GetSelectionScreenRect();
                RegionCanvas.Children.Remove(_selectionRect);
                _selectionRect = null;
                CaptureRegionScreenshot(region);
            }
        }
        else if (_captureMode == CMode.Gif && _areaMode == AMode.Region)
        {
            // Region is set for GIF — keep it visible, user clicks Start
        }
    }

    private System.Drawing.Rectangle GetSelectionScreenRect()
    {
        var x = Canvas.GetLeft(_selectionRect!);
        var y = Canvas.GetTop(_selectionRect!);
        var w = _selectionRect!.Width;
        var h = _selectionRect!.Height;

        // Convert from canvas coordinates to screen coordinates
        var canvasOrigin = RegionCanvas.PointToScreen(new Point(0, 0));
        return new System.Drawing.Rectangle(
            (int)(canvasOrigin.X + x),
            (int)(canvasOrigin.Y + y),
            (int)w, (int)h);
    }

    private void CaptureRegionScreenshot(System.Drawing.Rectangle screenRect)
    {
        try
        {
            using var bitmap = ScreenCapture.CaptureRegion(screenRect);
            var pngBytes = ScreenCapture.ToPngBytes(bitmap);

            ClipboardManager.CopyImage(pngBytes);
            var dir = string.IsNullOrEmpty(AppSettings.Instance.SaveLocation)
                ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".pixyvibe", "captures")
                : AppSettings.Instance.SaveLocation;
            Directory.CreateDirectory(dir);
            var path = Path.Combine(dir, $"companion_region_{DateTime.Now:yyyyMMdd_HHmmss}.png");
            File.WriteAllBytes(path, pngBytes);
            ScreenshotHistory.Instance.Add(path, pngBytes);
            Close();
            OnCaptured?.Invoke(pngBytes, path);
        }
        catch (Exception ex)
        {
            ToastHelper.Show($"Error: {ex.Message}");
        }
    }

    // --- Keyboard ---

    private void Window_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            if (_recordingState == RecState.Recording)
                StopGifRecording();
            else
                Close();
        }
    }

    private static string FormatTime(TimeSpan ts) =>
        $"{(int)ts.TotalMinutes}:{ts.Seconds:D2}";
}
