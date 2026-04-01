using System;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;
using ScreenshotTool.Models;

namespace ScreenshotTool;

public partial class CapturePreviewPanel : Window
{
    private readonly byte[] _imageData;
    private readonly string? _filePath;
    private readonly DispatcherTimer _dismissTimer;
    private bool _isHovering;

    public event Action<string?>? OnEdit;

    private DispatcherTimer? _gifTimer;
    private BitmapFrame[]? _gifFrames;
    private int _gifIndex;

    public CapturePreviewPanel(byte[] imageData, string? filePath)
    {
        InitializeComponent();
        _imageData = imageData;
        _filePath = filePath;

        var isGif = filePath?.EndsWith(".gif", StringComparison.OrdinalIgnoreCase) == true;

        if (isGif)
        {
            try
            {
                using var ms = new MemoryStream(imageData);
                var decoder = new System.Windows.Media.Imaging.GifBitmapDecoder(
                    ms, BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
                _gifFrames = new BitmapFrame[decoder.Frames.Count];
                for (int i = 0; i < decoder.Frames.Count; i++)
                    _gifFrames[i] = decoder.Frames[i];

                if (_gifFrames.Length > 0)
                    ThumbnailImage.Source = _gifFrames[0];

                if (_gifFrames.Length > 1)
                {
                    _gifTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(100) };
                    _gifTimer.Tick += (_, _) =>
                    {
                        _gifIndex = (_gifIndex + 1) % _gifFrames.Length;
                        ThumbnailImage.Source = _gifFrames[_gifIndex];
                    };
                    _gifTimer.Start();
                }
            }
            catch
            {
                // Fallback: show first frame as static
                LoadStaticImage(imageData);
            }
        }
        else
        {
            LoadStaticImage(imageData);
        }

        FileNameText.Text = filePath != null ? Path.GetFileName(filePath) : "capture";

        // Position at right edge, bottom-aligned to work area
        var workArea = SystemParameters.WorkArea;
        Left = workArea.Right;  // Start off-screen

        Top = workArea.Bottom - 350; // initial estimate

        // Auto-dismiss timer
        _dismissTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(4) };
        _dismissTimer.Tick += (_, _) =>
        {
            if (!_isHovering) SlideOut();
        };

        Loaded += (_, _) =>
        {
            Top = workArea.Bottom - ActualHeight - 8;
            SlideIn();
            _dismissTimer.Start();
        };
    }

    private void SlideIn()
    {
        var workArea = SystemParameters.WorkArea;
        var target = workArea.Right - ActualWidth - 8;

        var anim = new DoubleAnimation
        {
            From = workArea.Right,
            To = target,
            Duration = TimeSpan.FromMilliseconds(350),
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut }
        };
        BeginAnimation(LeftProperty, anim);

        var fadeIn = new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(250));
        BeginAnimation(OpacityProperty, fadeIn);
    }

    private void SlideOut()
    {
        _dismissTimer.Stop();
        _gifTimer?.Stop();
        var workArea = SystemParameters.WorkArea;

        var anim = new DoubleAnimation
        {
            To = workArea.Right + 20,
            Duration = TimeSpan.FromMilliseconds(300),
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseIn }
        };
        anim.Completed += (_, _) => Close();
        BeginAnimation(LeftProperty, anim);

        var fadeOut = new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(250));
        BeginAnimation(OpacityProperty, fadeOut);
    }

    private void OnMouseEnter(object sender, System.Windows.Input.MouseEventArgs e)
    {
        _isHovering = true;
        _dismissTimer.Stop();
    }

    private void OnMouseLeave(object sender, System.Windows.Input.MouseEventArgs e)
    {
        _isHovering = false;
        _dismissTimer.Start();
    }

    private void Edit_Click(object sender, RoutedEventArgs e)
    {
        Close();
        OnEdit?.Invoke(_filePath);
    }

    private void SaveAs_Click(object sender, RoutedEventArgs e)
    {
        var ext = _filePath?.EndsWith(".gif", StringComparison.OrdinalIgnoreCase) == true ? "gif" : "png";
        var dialog = new SaveFileDialog
        {
            FileName = Path.GetFileName(_filePath ?? $"capture.{ext}"),
            Filter = ext == "gif" ? "GIF files|*.gif" : "PNG files|*.png|JPEG files|*.jpg"
        };
        if (dialog.ShowDialog() == true)
        {
            File.WriteAllBytes(dialog.FileName, _imageData);
            ToastHelper.Show("Saved");
        }
    }

    private void Reveal_Click(object sender, RoutedEventArgs e)
    {
        if (_filePath != null && File.Exists(_filePath))
            Process.Start("explorer.exe", $"/select,\"{_filePath}\"");
    }

    private void LoadStaticImage(byte[] data)
    {
        var bi = new BitmapImage();
        bi.BeginInit();
        bi.StreamSource = new MemoryStream(data);
        bi.CacheOption = BitmapCacheOption.OnLoad;
        bi.EndInit();
        bi.Freeze();
        ThumbnailImage.Source = bi;
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (_filePath != null && File.Exists(_filePath))
        {
            File.Delete(_filePath);
            ScreenshotHistory.Instance.Remove(_filePath);
            ToastHelper.Show("Deleted");
        }
        Close();
    }
}
