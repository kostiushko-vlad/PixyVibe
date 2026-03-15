using System.Windows;
using Microsoft.Win32;

namespace ScreenshotTool;

public partial class SettingsWindow : Window
{
    public SettingsWindow()
    {
        InitializeComponent();
    }

    private void Browse_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog
        {
            Title = "Choose save location"
        };
        if (dialog.ShowDialog() == true)
        {
            SavePath.Text = dialog.FolderName;
        }
    }
}
