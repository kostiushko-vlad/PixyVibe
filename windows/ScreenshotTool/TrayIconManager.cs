using System;
using System.Windows;
using System.Windows.Controls;

namespace ScreenshotTool;

public class TrayIconManager : IDisposable
{
    private Hardcodet.Wpf.TaskbarNotification.TaskbarIcon? _trayIcon;

    public event Action? OnCaptureClicked;
    public event Action? OnSettingsClicked;
    public event Action? OnQuitClicked;

    public TrayIconManager()
    {
        _trayIcon = new Hardcodet.Wpf.TaskbarNotification.TaskbarIcon
        {
            ToolTipText = "PixyVibe Screenshot Tool"
        };

        var menu = new ContextMenu();

        var captureItem = new MenuItem { Header = "Capture Region (Shift+Ctrl+6)" };
        captureItem.Click += (s, e) => OnCaptureClicked?.Invoke();
        menu.Items.Add(captureItem);

        menu.Items.Add(new Separator());

        var settingsItem = new MenuItem { Header = "Settings..." };
        settingsItem.Click += (s, e) => OnSettingsClicked?.Invoke();
        menu.Items.Add(settingsItem);

        menu.Items.Add(new Separator());

        var quitItem = new MenuItem { Header = "Quit PixyVibe" };
        quitItem.Click += (s, e) => OnQuitClicked?.Invoke();
        menu.Items.Add(quitItem);

        _trayIcon.ContextMenu = menu;
    }

    public void Dispose()
    {
        _trayIcon?.Dispose();
        _trayIcon = null;
    }
}
