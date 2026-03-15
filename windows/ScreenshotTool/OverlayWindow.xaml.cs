using System;
using System.Drawing;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;

namespace ScreenshotTool;

public partial class OverlayWindow : Window
{
    private System.Windows.Point? _startPoint;
    private System.Windows.Shapes.Rectangle? _selectionRect;
    private bool _isDiffAfterMode;

    public event Action<System.Drawing.Rectangle>? OnScreenshot;
    public event Action<System.Drawing.Rectangle>? OnGifStart;
    public event Action<System.Drawing.Rectangle>? OnDiffBefore;
    public event Action<System.Drawing.Rectangle>? OnDiffAfter;

    public OverlayWindow(bool isDiffPending)
    {
        InitializeComponent();
        _isDiffAfterMode = isDiffPending;

        // Cover all monitors
        Left = SystemParameters.VirtualScreenLeft;
        Top = SystemParameters.VirtualScreenTop;
        Width = SystemParameters.VirtualScreenWidth;
        Height = SystemParameters.VirtualScreenHeight;
    }

    private void Window_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        _startPoint = e.GetPosition(this);
        CaptureMouse();
    }

    private void Window_MouseMove(object sender, MouseEventArgs e)
    {
        if (_startPoint == null) return;
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
        ReleaseMouseCapture();
        if (_selectionRect == null || _selectionRect.Width < 10 || _selectionRect.Height < 10)
        {
            return;
        }

        var rect = GetSelectionRect();
        ShowToolbar(rect);
    }

    private void Window_KeyDown(object sender, KeyEventArgs e)
    {
        switch (e.Key)
        {
            case Key.Escape:
                Close();
                break;
            case Key.S:
                if (HasSelection())
                {
                    Close();
                    OnScreenshot?.Invoke(GetSelectionRect());
                }
                break;
            case Key.G:
                if (HasSelection())
                {
                    Close();
                    OnGifStart?.Invoke(GetSelectionRect());
                }
                break;
            case Key.D:
                if (HasSelection())
                {
                    Close();
                    if (_isDiffAfterMode)
                        OnDiffAfter?.Invoke(GetSelectionRect());
                    else
                        OnDiffBefore?.Invoke(GetSelectionRect());
                }
                break;
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
        // Offset by virtual screen position
        return new System.Drawing.Rectangle(
            x + (int)SystemParameters.VirtualScreenLeft,
            y + (int)SystemParameters.VirtualScreenTop,
            w, h);
    }

    private void ShowToolbar(System.Drawing.Rectangle region)
    {
        var toolbar = new ActionToolbar(_isDiffAfterMode);
        toolbar.OnScreenshot += () => { Close(); OnScreenshot?.Invoke(region); };
        toolbar.OnGif += () => { Close(); OnGifStart?.Invoke(region); };
        toolbar.OnDiff += () =>
        {
            Close();
            if (_isDiffAfterMode)
                OnDiffAfter?.Invoke(region);
            else
                OnDiffBefore?.Invoke(region);
        };

        var x = Canvas.GetLeft(_selectionRect!) + _selectionRect!.Width / 2 - 150;
        var y = Canvas.GetTop(_selectionRect!) + _selectionRect!.Height + 10;
        Canvas.SetLeft(toolbar, x);
        Canvas.SetTop(toolbar, y);
        SelectionCanvas.Children.Add(toolbar);
    }
}
