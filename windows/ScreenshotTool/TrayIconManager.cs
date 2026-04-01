using System;
using System.Windows;
using System.Windows.Controls;

namespace ScreenshotTool;

public class TrayIconManager : IDisposable
{
    private Hardcodet.Wpf.TaskbarNotification.TaskbarIcon? _trayIcon;
    private TrayPanel? _trayPanel;

    public event Action? OnCaptureClicked;
    public event Action? OnSettingsClicked;
    public event Action? OnQuitClicked;
    public event Action? OnOpenFolderClicked;
    public event Action<string>? OnHistoryItemClicked;

    public TrayIconManager()
    {
        _trayIcon = new Hardcodet.Wpf.TaskbarNotification.TaskbarIcon
        {
            ToolTipText = "PixyVibe Screenshot Tool"
        };

        _trayIcon.TrayLeftMouseUp += (_, _) => ToggleTrayPanel();

        // Right-click fallback context menu
        var menu = new ContextMenu();
        var captureItem = new MenuItem { Header = "Capture" };
        captureItem.Click += (_, _) => OnCaptureClicked?.Invoke();
        menu.Items.Add(captureItem);

        menu.Items.Add(new Separator());

        var settingsItem = new MenuItem { Header = "Settings..." };
        settingsItem.Click += (_, _) => OnSettingsClicked?.Invoke();
        menu.Items.Add(settingsItem);

        var folderItem = new MenuItem { Header = "Open Captures Folder" };
        folderItem.Click += (_, _) => OnOpenFolderClicked?.Invoke();
        menu.Items.Add(folderItem);

        menu.Items.Add(new Separator());

        var quitItem = new MenuItem { Header = "Quit PixyVibe" };
        quitItem.Click += (_, _) => OnQuitClicked?.Invoke();
        menu.Items.Add(quitItem);

        _trayIcon.ContextMenu = menu;
    }

    private void ToggleTrayPanel()
    {
        if (_trayPanel != null && _trayPanel.IsVisible)
        {
            _trayPanel.Hide();
            return;
        }

        _trayPanel ??= CreateTrayPanel();
        _trayPanel.Refresh();
        _trayPanel.Show();
        _trayPanel.PositionNearTray();
        _trayPanel.Activate();
    }

    private TrayPanel CreateTrayPanel()
    {
        var panel = new TrayPanel();
        panel.OnCaptureClicked += () => OnCaptureClicked?.Invoke();
        panel.OnSettingsClicked += () => OnSettingsClicked?.Invoke();
        panel.OnQuitClicked += () => OnQuitClicked?.Invoke();
        panel.OnOpenFolderClicked += () => OnOpenFolderClicked?.Invoke();
        panel.OnHistoryItemClicked += path => OnHistoryItemClicked?.Invoke(path);
        panel.OnCompanionClicked += deviceId =>
        {
            panel.Hide();
            var window = new CompanionPreviewWindow(deviceId);
            window.Show();
        };
        return panel;
    }

    public void Dispose()
    {
        _trayPanel?.Close();
        _trayIcon?.Dispose();
        _trayIcon = null;
    }
}
