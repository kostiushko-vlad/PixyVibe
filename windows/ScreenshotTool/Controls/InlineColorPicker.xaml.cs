using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using ScreenshotTool.Theme;

namespace ScreenshotTool.Controls;

public partial class InlineColorPicker : UserControl
{
    private Ellipse? _selectedEllipse;

    public event Action<Color>? ColorSelected;

    public Color SelectedColor { get; private set; } = PV.EditorColors[0];

    public InlineColorPicker()
    {
        InitializeComponent();
        BuildSwatches();
    }

    private void BuildSwatches()
    {
        for (int i = 0; i < PV.EditorColors.Length; i++)
        {
            var color = PV.EditorColors[i];
            var ellipse = new Ellipse
            {
                Width = 24,
                Height = 24,
                Fill = new SolidColorBrush(color),
                Stroke = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255)),
                StrokeThickness = 1,
                Margin = new Thickness(3, 0, 3, 0),
                Cursor = Cursors.Hand
            };

            if (i == 0)
            {
                _selectedEllipse = ellipse;
                ellipse.StrokeThickness = 2.5;
                ellipse.Stroke = Brushes.White;
            }

            ellipse.MouseLeftButtonDown += (_, _) =>
            {
                if (_selectedEllipse != null)
                {
                    _selectedEllipse.StrokeThickness = 1;
                    _selectedEllipse.Stroke = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255));
                }
                _selectedEllipse = ellipse;
                ellipse.StrokeThickness = 2.5;
                ellipse.Stroke = Brushes.White;
                SelectedColor = color;
                ColorSelected?.Invoke(color);
            };

            ColorPanel.Children.Add(ellipse);
        }
    }
}
