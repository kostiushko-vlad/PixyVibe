using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using ScreenshotTool.Models;
using CaptureMode = ScreenshotTool.Models.CaptureMode;

namespace ScreenshotTool;

public partial class OverlayWindow : Window
{
    private System.Windows.Point? _startPoint;
    private System.Windows.Shapes.Rectangle? _selectionRect;
    private bool _isDiffAfterMode;
    private bool _selectionComplete;
    private CaptureMode _selectedMode;

    // Drag state for mode panel
    private bool _isDraggingPanel;
    private System.Windows.Point _panelDragStart;
    private Thickness _panelMarginStart;

    // Companion devices
    private readonly List<string> _deviceIds = new();

    public event Action<System.Drawing.Rectangle>? OnScreenshot;
    public event Action<System.Drawing.Rectangle>? OnGifStart;
    public event Action<System.Drawing.Rectangle>? OnDiffBefore;
    public event Action<System.Drawing.Rectangle>? OnDiffAfter;
    public event Action<string>? OnCompanionSelected;

    public OverlayWindow(bool isDiffPending, CaptureMode initialMode = CaptureMode.Screenshot)
    {
        InitializeComponent();
        _isDiffAfterMode = isDiffPending;
        _selectedMode = initialMode;

        // Cover all monitors
        Left = SystemParameters.VirtualScreenLeft;
        Top = SystemParameters.VirtualScreenTop;
        Width = SystemParameters.VirtualScreenWidth;
        Height = SystemParameters.VirtualScreenHeight;

        PopulateDeviceButtons();
        UpdateModeHighlight();
    }

    // --- Mode panel button handlers ---

    private void Mode_Screenshot(object sender, MouseButtonEventArgs e)
    {
        _selectedMode = CaptureMode.Screenshot;
        UpdateModeHighlight();
        e.Handled = true;
    }

    private void Mode_Gif(object sender, MouseButtonEventArgs e)
    {
        _selectedMode = CaptureMode.Gif;
        UpdateModeHighlight();
        e.Handled = true;
    }

    private void Mode_Diff(object sender, MouseButtonEventArgs e)
    {
        _selectedMode = CaptureMode.Diff;
        UpdateModeHighlight();
        e.Handled = true;
    }

    private void Close_Click(object sender, MouseButtonEventArgs e)
    {
        Close();
        e.Handled = true;
    }

    private void UpdateModeHighlight()
    {
        var accentBg = new SolidColorBrush(System.Windows.Media.Color.FromArgb(38, 0x38, 0xBD, 0xF8));
        var transparent = System.Windows.Media.Brushes.Transparent;

        // Accent border brush
        var accentBorder = new LinearGradientBrush(
            System.Windows.Media.Color.FromRgb(0x38, 0xBD, 0xF8),
            System.Windows.Media.Color.FromRgb(0x81, 0x8C, 0xF8), 0);
        var noBorder = System.Windows.Media.Brushes.Transparent;

        SetModeStyle(BtnScreenshot, _selectedMode == CaptureMode.Screenshot, accentBg, transparent, accentBorder, noBorder);
        SetModeStyle(BtnGif, _selectedMode == CaptureMode.Gif, accentBg, transparent, accentBorder, noBorder);
        SetModeStyle(BtnDiff, _selectedMode == CaptureMode.Diff, accentBg, transparent, accentBorder, noBorder);

        // Update device buttons
        for (int i = 0; i < DeviceButtonsPanel.Children.Count; i++)
        {
            if (DeviceButtonsPanel.Children[i] is Border deviceBorder && deviceBorder.Tag is string deviceId)
            {
                // Device buttons are never "selected" in the core mode sense
                deviceBorder.Background = transparent;
                deviceBorder.BorderBrush = noBorder;
                deviceBorder.BorderThickness = new Thickness(0);
            }
        }
    }

    private void SetModeStyle(Border btn, bool selected,
        System.Windows.Media.Brush accentBg, System.Windows.Media.Brush transparentBg,
        System.Windows.Media.Brush accentBorder, System.Windows.Media.Brush noBorder)
    {
        btn.Background = selected ? accentBg : transparentBg;
        btn.BorderBrush = selected ? accentBorder : noBorder;
        btn.BorderThickness = new Thickness(selected ? 1.5 : 0);
    }

    private void PopulateDeviceButtons()
    {
        var companions = RustBridge.ListCompanions();
        if (companions.Count == 0) return;

        for (int i = 0; i < companions.Count && i < 9; i++)
        {
            var device = companions[i];
            _deviceIds.Add(device.DeviceId);

            // Divider
            var divider = new Border
            {
                Width = 1,
                Background = new SolidColorBrush(System.Windows.Media.Color.FromArgb(38, 255, 255, 255)),
                Margin = new Thickness(4, 8, 4, 8)
            };
            DeviceButtonsPanel.Children.Add(divider);

            // Device button
            var btn = new Border
            {
                Width = 90, Height = 58,
                CornerRadius = new CornerRadius(12),
                Cursor = Cursors.Hand,
                Background = System.Windows.Media.Brushes.Transparent,
                Tag = device.DeviceId
            };

            var stack = new StackPanel
            {
                VerticalAlignment = VerticalAlignment.Center,
                HorizontalAlignment = System.Windows.HorizontalAlignment.Center
            };

            // Phone icon with connection dot
            var iconGrid = new Grid { HorizontalAlignment = System.Windows.HorizontalAlignment.Center };
            iconGrid.Children.Add(new TextBlock
            {
                Text = "\uE8EA",
                FontFamily = new System.Windows.Media.FontFamily("Segoe MDL2 Assets"),
                FontSize = 16,
                Foreground = new SolidColorBrush(System.Windows.Media.Color.FromRgb(0xE6, 0xED, 0xF3)),
                HorizontalAlignment = System.Windows.HorizontalAlignment.Center
            });
            var dot = new Ellipse
            {
                Width = 6, Height = 6,
                Fill = device.Connected
                    ? new SolidColorBrush(System.Windows.Media.Color.FromRgb(0x10, 0xB9, 0x81))
                    : new SolidColorBrush(System.Windows.Media.Color.FromRgb(0x2D, 0x35, 0x48)),
                HorizontalAlignment = System.Windows.HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Top,
                Margin = new Thickness(0, -2, -4, 0)
            };
            iconGrid.Children.Add(dot);
            stack.Children.Add(iconGrid);

            stack.Children.Add(new TextBlock
            {
                Text = device.DeviceName,
                FontSize = 10, FontWeight = FontWeights.Medium,
                HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
                Foreground = new SolidColorBrush(System.Windows.Media.Color.FromRgb(0x8B, 0x94, 0x9E)),
                Margin = new Thickness(0, 3, 0, 0),
                TextTrimming = TextTrimming.CharacterEllipsis,
                MaxWidth = 80
            });
            stack.Children.Add(new TextBlock
            {
                Text = $"{i + 1}",
                FontSize = 9,
                HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
                Foreground = new SolidColorBrush(System.Windows.Media.Color.FromRgb(0x8B, 0x94, 0x9E)),
                Margin = new Thickness(0, 1, 0, 0)
            });

            btn.Child = stack;

            var deviceId = device.DeviceId;
            btn.MouseLeftButtonDown += (_, ev) =>
            {
                Close();
                OnCompanionSelected?.Invoke(deviceId);
                ev.Handled = true;
            };

            DeviceButtonsPanel.Children.Add(btn);
        }
    }

    // --- Panel dragging ---

    private void ModePanel_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.OriginalSource is Border b && (b == ModePanel || b.Parent == ModePanel))
        {
            _isDraggingPanel = true;
            _panelDragStart = e.GetPosition(this);
            _panelMarginStart = ModePanel.Margin;
            ModePanel.CaptureMouse();
            e.Handled = true;
        }
    }

    private void ModePanel_MouseMove(object sender, MouseEventArgs e)
    {
        if (!_isDraggingPanel) return;
        var current = e.GetPosition(this);
        var dx = current.X - _panelDragStart.X;
        var dy = current.Y - _panelDragStart.Y;

        ModePanel.HorizontalAlignment = System.Windows.HorizontalAlignment.Left;
        ModePanel.VerticalAlignment = VerticalAlignment.Top;
        ModePanel.Margin = new Thickness(
            _panelMarginStart.Left + (_panelDragStart.X - ModePanel.ActualWidth / 2) + dx,
            _panelMarginStart.Top + (_panelDragStart.Y - ModePanel.ActualHeight / 2) + dy,
            0, 0);
        e.Handled = true;
    }

    private void ModePanel_MouseUp(object sender, MouseButtonEventArgs e)
    {
        if (_isDraggingPanel)
        {
            _isDraggingPanel = false;
            ModePanel.ReleaseMouseCapture();
            e.Handled = true;
        }
    }

    // --- Region selection ---

    private void Window_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (_selectionComplete || _isDraggingPanel) return;
        _startPoint = e.GetPosition(this);
        CaptureMouse();
    }

    private void Window_MouseMove(object sender, MouseEventArgs e)
    {
        if (_startPoint == null || _selectionComplete || _isDraggingPanel) return;
        var current = e.GetPosition(this);

        if (_selectionRect == null)
        {
            _selectionRect = new System.Windows.Shapes.Rectangle
            {
                Stroke = System.Windows.Media.Brushes.White,
                StrokeThickness = 2,
                Fill = System.Windows.Media.Brushes.Transparent
            };
            SelectionCanvas.Children.Add(_selectionRect);
        }

        var x = Math.Min(_startPoint.Value.X, current.X);
        var y = Math.Min(_startPoint.Value.Y, current.Y);
        var w = Math.Abs(current.X - _startPoint.Value.X);
        var h = Math.Abs(current.Y - _startPoint.Value.Y);

        Canvas.SetLeft(_selectionRect, x);
        Canvas.SetTop(_selectionRect, y);
        _selectionRect.Width = w;
        _selectionRect.Height = h;
    }

    private void Window_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (_isDraggingPanel) return;

        ReleaseMouseCapture();
        _startPoint = null;

        if (_selectionRect == null || _selectionRect.Width < 10 || _selectionRect.Height < 10)
            return;

        _selectionComplete = true;
        var rect = GetSelectionRect();
        Close();
        ExecuteMode(_selectedMode, rect);
    }

    private void ExecuteMode(CaptureMode mode, System.Drawing.Rectangle region)
    {
        switch (mode)
        {
            case CaptureMode.Screenshot:
                OnScreenshot?.Invoke(region);
                break;
            case CaptureMode.Gif:
                OnGifStart?.Invoke(region);
                break;
            case CaptureMode.Diff:
                if (_isDiffAfterMode)
                    OnDiffAfter?.Invoke(region);
                else
                    OnDiffBefore?.Invoke(region);
                break;
        }
    }

    private void Window_KeyDown(object sender, KeyEventArgs e)
    {
        switch (e.Key)
        {
            case Key.Escape:
                Close();
                break;
            case Key.S:
                _selectedMode = CaptureMode.Screenshot;
                UpdateModeHighlight();
                break;
            case Key.G:
                _selectedMode = CaptureMode.Gif;
                UpdateModeHighlight();
                break;
            case Key.D:
                _selectedMode = CaptureMode.Diff;
                UpdateModeHighlight();
                break;
            case >= Key.D1 and <= Key.D9:
            {
                var idx = e.Key - Key.D1;
                if (idx < _deviceIds.Count)
                {
                    Close();
                    OnCompanionSelected?.Invoke(_deviceIds[idx]);
                }
                break;
            }
        }
    }

    private bool HasSelection() =>
        _selectionRect != null && _selectionRect.Width > 10 && _selectionRect.Height > 10;

    private System.Drawing.Rectangle GetSelectionRect()
    {
        var x = (int)Canvas.GetLeft(_selectionRect!);
        var y = (int)Canvas.GetTop(_selectionRect!);
        var w = (int)_selectionRect!.Width;
        var h = (int)_selectionRect!.Height;
        return new System.Drawing.Rectangle(
            x + (int)SystemParameters.VirtualScreenLeft,
            y + (int)SystemParameters.VirtualScreenTop,
            w, h);
    }
}
