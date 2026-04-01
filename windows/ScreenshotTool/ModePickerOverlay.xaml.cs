using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using ScreenshotTool.Models;
using CaptureMode = ScreenshotTool.Models.CaptureMode;

namespace ScreenshotTool;

public partial class ModePickerOverlay : Window
{
    private readonly List<string> _deviceIds = new();

    public event Action<CaptureMode>? OnModeSelected;
    public event Action<string>? OnCompanionSelected;

    public ModePickerOverlay()
    {
        InitializeComponent();
        PositionAtBottom();
        PopulateDevices();
        Loaded += (_, _) => Activate();
    }

    private void PositionAtBottom()
    {
        var workArea = SystemParameters.WorkArea;
        WindowStartupLocation = WindowStartupLocation.Manual;
        // Will be centered after measuring
        Loaded += (_, _) =>
        {
            Left = workArea.Left + (workArea.Width - ActualWidth) / 2;
            Top = workArea.Bottom - ActualHeight - 40;
        };
    }

    private void PopulateDevices()
    {
        var companions = RustBridge.ListCompanions();
        if (companions.Count == 0) return;

        DevicesPanel.Visibility = Visibility.Visible;

        for (int i = 0; i < companions.Count && i < 9; i++)
        {
            var device = companions[i];
            _deviceIds.Add(device.DeviceId);

            var btn = new Button
            {
                Width = 100,
                Height = 50,
                Margin = new Thickness(0, 0, 8, 0),
                ToolTip = $"Press {i + 1}"
            };

            var panel = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center };

            // Connection indicator
            var namePanel = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
            if (device.Connected)
            {
                namePanel.Children.Add(new Ellipse
                {
                    Width = 6, Height = 6,
                    Fill = new SolidColorBrush(Color.FromRgb(0x10, 0xB9, 0x81)),
                    Margin = new Thickness(0, 0, 4, 0),
                    VerticalAlignment = VerticalAlignment.Center
                });
            }
            namePanel.Children.Add(new TextBlock
            {
                Text = device.DeviceName,
                FontSize = 11,
                TextTrimming = TextTrimming.CharacterEllipsis
            });
            panel.Children.Add(namePanel);
            panel.Children.Add(new TextBlock
            {
                Text = $"[{i + 1}]",
                FontSize = 9,
                Foreground = new SolidColorBrush(Color.FromRgb(0x8B, 0x94, 0x9E)),
                HorizontalAlignment = HorizontalAlignment.Center
            });

            btn.Content = panel;

            var deviceId = device.DeviceId;
            btn.Click += (_, _) => { OnCompanionSelected?.Invoke(deviceId); };

            DevicesPanel.Children.Add(btn);
        }
    }

    private void Screenshot_Click(object sender, RoutedEventArgs e) => OnModeSelected?.Invoke(CaptureMode.Screenshot);
    private void Gif_Click(object sender, RoutedEventArgs e) => OnModeSelected?.Invoke(CaptureMode.Gif);
    private void Diff_Click(object sender, RoutedEventArgs e) => OnModeSelected?.Invoke(CaptureMode.Diff);

    private void Window_KeyDown(object sender, KeyEventArgs e)
    {
        switch (e.Key)
        {
            case Key.S:
                OnModeSelected?.Invoke(CaptureMode.Screenshot);
                break;
            case Key.G:
                OnModeSelected?.Invoke(CaptureMode.Gif);
                break;
            case Key.D:
                OnModeSelected?.Invoke(CaptureMode.Diff);
                break;
            case Key.Escape:
                Close();
                break;
            case >= Key.D1 and <= Key.D9:
            {
                var idx = e.Key - Key.D1;
                if (idx < _deviceIds.Count)
                    OnCompanionSelected?.Invoke(_deviceIds[idx]);
                break;
            }
        }
    }

    private void Window_Deactivated(object sender, EventArgs e)
    {
        Close();
    }
}
