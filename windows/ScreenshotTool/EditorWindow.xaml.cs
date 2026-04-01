using System;
using System.Collections.Generic;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Ink;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using ScreenshotTool.Models;
using ScreenshotTool.Theme;

namespace ScreenshotTool;

public partial class EditorWindow : Window
{
    private readonly string _filePath;
    private string _currentTool = "Pen";
    private Color _currentColor;
    private double _currentWidth = 3;

    // Shape drawing state
    private Point? _shapeStart;
    private Shape? _activeShape;

    // Undo/Redo
    private readonly Stack<UndoAction> _undoStack = new();
    private readonly Stack<UndoAction> _redoStack = new();

    // Text editing
    private TextBox? _activeTextBox;

    public EditorWindow(string filePath)
    {
        InitializeComponent();
        _filePath = filePath;
        _currentColor = PV.EditorColors[0];

        LoadImage();
        SetupInkCanvas();

        ColorPicker.ColorSelected += c =>
        {
            _currentColor = c;
            UpdateInkAttributes();
        };
    }

    private void LoadImage()
    {
        var bi = new BitmapImage();
        bi.BeginInit();
        bi.UriSource = new Uri(_filePath);
        bi.CacheOption = BitmapCacheOption.OnLoad;
        bi.EndInit();
        bi.Freeze();
        BackgroundImage.Source = bi;
        Title = $"PixyVibe Editor — {System.IO.Path.GetFileName(_filePath)}";
    }

    private void SetupInkCanvas()
    {
        UpdateInkAttributes();
        DrawingCanvas.StrokeCollected += (_, e) =>
        {
            _undoStack.Push(new UndoAction(UndoType.StrokeAdded, UndoStroke: e.Stroke));
            _redoStack.Clear();
        };
    }

    private void UpdateInkAttributes()
    {
        DrawingCanvas.DefaultDrawingAttributes = new DrawingAttributes
        {
            Color = _currentColor,
            Width = _currentWidth,
            Height = _currentWidth,
            StylusTip = StylusTip.Ellipse,
            FitToCurve = true,
            IsHighlighter = false
        };
    }

    private void Tool_Click(object sender, RoutedEventArgs e)
    {
        CommitTextBox();
        if (sender is RadioButton rb && rb.Tag is string tool)
        {
            _currentTool = tool;
            switch (tool)
            {
                case "Hand":
                    DrawingCanvas.EditingMode = InkCanvasEditingMode.None;
                    ShapeCanvas.IsHitTestVisible = false;
                    break;
                case "Pen":
                    DrawingCanvas.EditingMode = InkCanvasEditingMode.Ink;
                    ShapeCanvas.IsHitTestVisible = false;
                    break;
                case "Arrow":
                case "Rect":
                    DrawingCanvas.EditingMode = InkCanvasEditingMode.None;
                    ShapeCanvas.IsHitTestVisible = true;
                    break;
                case "Text":
                    DrawingCanvas.EditingMode = InkCanvasEditingMode.None;
                    ShapeCanvas.IsHitTestVisible = true;
                    break;
            }
        }
    }

    private void Canvas_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (_currentTool == "Pen" || _currentTool == "Hand") return;

        var pos = e.GetPosition(ShapeCanvas);

        if (_currentTool == "Text")
        {
            CommitTextBox();
            _activeTextBox = new TextBox
            {
                Background = Brushes.Transparent,
                Foreground = new SolidColorBrush(_currentColor),
                BorderThickness = new Thickness(1),
                BorderBrush = new SolidColorBrush(Color.FromArgb(100, _currentColor.R, _currentColor.G, _currentColor.B)),
                FontSize = Math.Max(14, _currentWidth * 5),
                MinWidth = 80,
                AcceptsReturn = true,
                CaretBrush = new SolidColorBrush(_currentColor),
                Padding = new Thickness(4)
            };
            Canvas.SetLeft(_activeTextBox, pos.X);
            Canvas.SetTop(_activeTextBox, pos.Y);
            ShapeCanvas.IsHitTestVisible = true;
            ShapeCanvas.Children.Add(_activeTextBox);
            _activeTextBox.Focus();
            e.Handled = true;
            return;
        }

        _shapeStart = pos;

        if (_currentTool == "Arrow")
        {
            _activeShape = new Line
            {
                X1 = pos.X, Y1 = pos.Y,
                X2 = pos.X, Y2 = pos.Y,
                Stroke = new SolidColorBrush(_currentColor),
                StrokeThickness = _currentWidth,
                StrokeEndLineCap = PenLineCap.Triangle
            };
        }
        else if (_currentTool == "Rect")
        {
            _activeShape = new Rectangle
            {
                Stroke = new SolidColorBrush(_currentColor),
                StrokeThickness = _currentWidth,
                Fill = Brushes.Transparent
            };
            Canvas.SetLeft(_activeShape, pos.X);
            Canvas.SetTop(_activeShape, pos.Y);
        }

        if (_activeShape != null)
            ShapeCanvas.Children.Add(_activeShape);

        DrawingCanvas.CaptureMouse();
    }

    private void Canvas_MouseMove(object sender, MouseEventArgs e)
    {
        if (_shapeStart == null || _activeShape == null) return;
        var pos = e.GetPosition(ShapeCanvas);

        if (_activeShape is Line line)
        {
            line.X2 = pos.X;
            line.Y2 = pos.Y;
        }
        else if (_activeShape is Rectangle rect)
        {
            var x = Math.Min(_shapeStart.Value.X, pos.X);
            var y = Math.Min(_shapeStart.Value.Y, pos.Y);
            Canvas.SetLeft(rect, x);
            Canvas.SetTop(rect, y);
            rect.Width = Math.Abs(pos.X - _shapeStart.Value.X);
            rect.Height = Math.Abs(pos.Y - _shapeStart.Value.Y);
        }
    }

    private void Canvas_MouseUp(object sender, MouseButtonEventArgs e)
    {
        DrawingCanvas.ReleaseMouseCapture();
        if (_activeShape != null)
        {
            _undoStack.Push(new UndoAction(UndoType.ShapeAdded, UndoShape: _activeShape));
            _redoStack.Clear();
        }
        _activeShape = null;
        _shapeStart = null;
    }

    private void CommitTextBox()
    {
        if (_activeTextBox == null) return;
        var text = _activeTextBox.Text;
        var left = Canvas.GetLeft(_activeTextBox);
        var top = Canvas.GetTop(_activeTextBox);

        ShapeCanvas.Children.Remove(_activeTextBox);

        if (!string.IsNullOrWhiteSpace(text))
        {
            var tb = new TextBlock
            {
                Text = text,
                Foreground = new SolidColorBrush(_currentColor),
                FontSize = _activeTextBox.FontSize
            };
            Canvas.SetLeft(tb, left);
            Canvas.SetTop(tb, top);
            ShapeCanvas.Children.Add(tb);
            _undoStack.Push(new UndoAction(UndoType.ShapeAdded, UndoShape: tb));
            _redoStack.Clear();
        }

        _activeTextBox = null;
    }

    private void Undo_Click(object sender, RoutedEventArgs e) => PerformUndo();
    private void Redo_Click(object sender, RoutedEventArgs e) => PerformRedo();

    private void PerformUndo()
    {
        if (_undoStack.Count == 0) return;
        var action = _undoStack.Pop();
        _redoStack.Push(action);

        switch (action.Type)
        {
            case UndoType.StrokeAdded:
                if (action.UndoStroke != null)
                    DrawingCanvas.Strokes.Remove(action.UndoStroke);
                break;
            case UndoType.ShapeAdded:
                if (action.UndoShape != null)
                    ShapeCanvas.Children.Remove(action.UndoShape as UIElement);
                break;
        }
    }

    private void PerformRedo()
    {
        if (_redoStack.Count == 0) return;
        var action = _redoStack.Pop();
        _undoStack.Push(action);

        switch (action.Type)
        {
            case UndoType.StrokeAdded:
                if (action.UndoStroke != null)
                    DrawingCanvas.Strokes.Add(action.UndoStroke);
                break;
            case UndoType.ShapeAdded:
                if (action.UndoShape is UIElement elem)
                    ShapeCanvas.Children.Add(elem);
                break;
        }
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        CommitTextBox();
        SaveToFile(_filePath);
        ToastHelper.Show("Saved");
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (File.Exists(_filePath))
        {
            File.Delete(_filePath);
            ScreenshotHistory.Instance.Remove(_filePath);
            ToastHelper.Show("Deleted");
        }
        Close();
    }

    private void SaveToFile(string path)
    {
        // Render the entire editor canvas to a bitmap
        var container = CanvasContainer;
        var renderWidth = (int)container.ActualWidth;
        var renderHeight = (int)container.ActualHeight;
        if (renderWidth == 0 || renderHeight == 0) return;

        var rtb = new RenderTargetBitmap(renderWidth, renderHeight, 96, 96, PixelFormats.Pbgra32);
        rtb.Render(container);

        BitmapEncoder encoder;
        if (path.EndsWith(".jpg", StringComparison.OrdinalIgnoreCase) ||
            path.EndsWith(".jpeg", StringComparison.OrdinalIgnoreCase))
        {
            encoder = new JpegBitmapEncoder { QualityLevel = AppSettings.Instance.JpegQuality };
        }
        else
        {
            encoder = new PngBitmapEncoder();
        }

        encoder.Frames.Add(BitmapFrame.Create(rtb));
        using var fs = new FileStream(path, FileMode.Create);
        encoder.Save(fs);
    }

    private void LineWidth_Changed(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        _currentWidth = e.NewValue;
        if (LineWidthLabel != null) LineWidthLabel.Text = $"{(int)e.NewValue}px";
        UpdateInkAttributes();
    }

    private void Window_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Z && Keyboard.Modifiers == ModifierKeys.Control)
        {
            PerformUndo();
            e.Handled = true;
        }
        else if ((e.Key == Key.Y && Keyboard.Modifiers == ModifierKeys.Control) ||
                 (e.Key == Key.Z && Keyboard.Modifiers == (ModifierKeys.Control | ModifierKeys.Shift)))
        {
            PerformRedo();
            e.Handled = true;
        }
        else if (e.Key == Key.S && Keyboard.Modifiers == ModifierKeys.Control)
        {
            CommitTextBox();
            SaveToFile(_filePath);
            ToastHelper.Show("Saved");
            e.Handled = true;
        }
    }

    private enum UndoType { StrokeAdded, ShapeAdded }

    private record UndoAction(UndoType Type, Stroke? UndoStroke = null, object? UndoShape = null);
}
