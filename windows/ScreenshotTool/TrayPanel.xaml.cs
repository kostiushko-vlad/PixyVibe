using System;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using ScreenshotTool.Models;

namespace ScreenshotTool;

public partial class TrayPanel : Window
{
    public event Action? OnCaptureClicked;
    public event Action? OnSettingsClicked;
    public event Action? OnQuitClicked;
    public event Action? OnOpenFolderClicked;
    public event Action<string>? OnHistoryItemClicked;
    public event Action<string>? OnCompanionClicked;

    public TrayPanel()
    {
        InitializeComponent();
        Refresh();
        ScreenshotHistory.Instance.HistoryChanged += () =>
            Dispatcher.Invoke(RefreshHistory);
    }

    public void Refresh()
    {
        RefreshDevices();
        RefreshHistory();
    }

    public void PositionNearTray()
    {
        var workArea = SystemParameters.WorkArea;
        Left = workArea.Right - Width - 8;
        Top = workArea.Bottom - ActualHeight - 8;
    }

    private void RefreshDevices()
    {
        DevicesContainer.Children.Clear();
        var companions = RustBridge.ListCompanions();

        if (companions.Count == 0)
        {
            DevicesHeader.Visibility = Visibility.Collapsed;
            DevicesScroller.Visibility = Visibility.Collapsed;
            return;
        }

        DevicesHeader.Visibility = Visibility.Visible;
        DevicesScroller.Visibility = Visibility.Visible;

        foreach (var device in companions)
        {
            var card = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(0x1C, 0x23, 0x33)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(0x2D, 0x35, 0x48)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(12, 8, 12, 8),
                Margin = new Thickness(0, 0, 8, 0),
                Cursor = Cursors.Hand,
                MinWidth = 100
            };

            var panel = new StackPanel();
            var nameRow = new StackPanel { Orientation = Orientation.Horizontal };

            if (device.Connected)
            {
                nameRow.Children.Add(new Ellipse
                {
                    Width = 6, Height = 6,
                    Fill = new SolidColorBrush(Color.FromRgb(0x10, 0xB9, 0x81)),
                    VerticalAlignment = VerticalAlignment.Center,
                    Margin = new Thickness(0, 0, 6, 0)
                });
            }
            nameRow.Children.Add(new TextBlock
            {
                Text = device.DeviceName,
                FontSize = 12,
                Foreground = new SolidColorBrush(Color.FromRgb(0xE6, 0xED, 0xF3))
            });
            panel.Children.Add(nameRow);
            panel.Children.Add(new TextBlock
            {
                Text = device.Connected ? "Connected" : "Offline",
                FontSize = 10,
                Foreground = new SolidColorBrush(Color.FromRgb(0x8B, 0x94, 0x9E)),
                Margin = new Thickness(0, 2, 0, 0)
            });

            card.Child = panel;
            var deviceId = device.DeviceId;
            card.MouseLeftButtonDown += (_, _) => OnCompanionClicked?.Invoke(deviceId);

            DevicesContainer.Children.Add(card);
        }
    }

    private void RefreshHistory()
    {
        HistoryGrid.Children.Clear();
        HistoryGrid.RowDefinitions.Clear();
        HistoryGrid.ColumnDefinitions.Clear();

        var entries = ScreenshotHistory.Instance.Entries;

        if (entries.Count == 0)
        {
            EmptyHistoryText.Visibility = Visibility.Visible;
            return;
        }

        EmptyHistoryText.Visibility = Visibility.Collapsed;

        // 2-column grid
        HistoryGrid.ColumnDefinitions.Add(new ColumnDefinition());
        HistoryGrid.ColumnDefinitions.Add(new ColumnDefinition());

        for (int i = 0; i < entries.Count; i++)
        {
            var entry = entries[i];
            if (i % 2 == 0)
                HistoryGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(90) });

            var card = CreateHistoryCard(entry);
            Grid.SetRow(card, i / 2);
            Grid.SetColumn(card, i % 2);
            HistoryGrid.Children.Add(card);
        }
    }

    private Border CreateHistoryCard(ScreenshotEntry entry)
    {
        var card = new Border
        {
            Background = new SolidColorBrush(Color.FromRgb(0x1C, 0x23, 0x33)),
            CornerRadius = new CornerRadius(6),
            Margin = new Thickness(2),
            Padding = new Thickness(4),
            Cursor = Cursors.Hand,
            ClipToBounds = true
        };

        var stack = new StackPanel();

        // Thumbnail
        if (File.Exists(entry.FilePath))
        {
            try
            {
                var bi = new BitmapImage();
                bi.BeginInit();
                bi.UriSource = new Uri(entry.FilePath);
                bi.DecodePixelWidth = 150;
                bi.CacheOption = BitmapCacheOption.OnLoad;
                bi.EndInit();
                bi.Freeze();

                stack.Children.Add(new Image
                {
                    Source = bi,
                    Height = 55,
                    Stretch = Stretch.Uniform,
                    HorizontalAlignment = HorizontalAlignment.Center
                });
            }
            catch { }
        }

        // Label
        stack.Children.Add(new TextBlock
        {
            Text = entry.TimeAgo,
            FontSize = 9,
            Foreground = new SolidColorBrush(Color.FromRgb(0x8B, 0x94, 0x9E)),
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 4, 0, 0)
        });

        card.Child = stack;

        var filePath = entry.FilePath;
        card.MouseLeftButtonDown += (_, _) =>
        {
            Close();
            OnHistoryItemClicked?.Invoke(filePath);
        };

        // Right-click context menu
        var menu = new ContextMenu();
        var copyItem = new MenuItem { Header = "Copy to Clipboard" };
        copyItem.Click += (_, _) =>
        {
            try
            {
                var data = File.ReadAllBytes(filePath);
                ClipboardManager.CopyImage(data);
                ToastHelper.Show("Copied");
            }
            catch { }
        };
        var deleteItem = new MenuItem { Header = "Delete" };
        deleteItem.Click += (_, _) =>
        {
            if (File.Exists(filePath)) File.Delete(filePath);
            ScreenshotHistory.Instance.Remove(filePath);
        };
        menu.Items.Add(copyItem);
        menu.Items.Add(deleteItem);
        card.ContextMenu = menu;

        return card;
    }

    private void Capture_Click(object sender, RoutedEventArgs e) { Close(); OnCaptureClicked?.Invoke(); }
    private void Clear_Click(object sender, RoutedEventArgs e) { ScreenshotHistory.Instance.Clear(); }
    private void Folder_Click(object sender, RoutedEventArgs e) { Close(); OnOpenFolderClicked?.Invoke(); }
    private void Settings_Click(object sender, RoutedEventArgs e) { Close(); OnSettingsClicked?.Invoke(); }
    private void Quit_Click(object sender, RoutedEventArgs e) { OnQuitClicked?.Invoke(); }

    private void Window_Deactivated(object sender, EventArgs e)
    {
        Hide();
    }
}
