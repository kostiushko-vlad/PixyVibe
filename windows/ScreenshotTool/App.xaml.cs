using System;
using System.Threading;
using System.Windows;

namespace ScreenshotTool;

public partial class App : Application
{
    private static Mutex? _mutex;
    private HotkeyManager? _hotkeyManager;
    private TrayIconManager? _trayManager;
    private bool _isDiffPending;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Single instance check
        _mutex = new Mutex(true, "PixyVibe_ScreenshotTool", out bool createdNew);
        if (!createdNew)
        {
            MessageBox.Show("PixyVibe is already running.", "PixyVibe");
            Shutdown();
            return;
        }

        // Initialize Rust core
        RustBridge.Initialize();

        // Setup system tray
        _trayManager = new TrayIconManager();
        _trayManager.OnCaptureClicked += HandleHotkey;
        _trayManager.OnSettingsClicked += ShowSettings;
        _trayManager.OnQuitClicked += () => Shutdown();

        // Register global hotkey (Shift+Ctrl+6)
        _hotkeyManager = new HotkeyManager();
        _hotkeyManager.OnHotkeyPressed += HandleHotkey;
        _hotkeyManager.Register();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _hotkeyManager?.Unregister();
        _trayManager?.Dispose();
        RustBridge.Shutdown();
        _mutex?.ReleaseMutex();
        base.OnExit(e);
    }

    private void HandleHotkey()
    {
        var overlay = new OverlayWindow(_isDiffPending);
        overlay.OnScreenshot += (region) =>
        {
            var result = RustBridge.CaptureAndProcess(region);
            if (result != null)
            {
                ClipboardManager.CopyImage(result);
                ToastHelper.Show("Copied to clipboard");
            }
        };
        overlay.OnGifStart += (region) => StartGifRecording(region);
        overlay.OnDiffBefore += (region) =>
        {
            if (RustBridge.DiffStoreBefore(region))
            {
                _isDiffPending = true;
                ToastHelper.Show("Before captured - make changes, then press Shift+Ctrl+6");
            }
        };
        overlay.OnDiffAfter += (region) =>
        {
            var result = RustBridge.DiffCompare(region);
            if (result != null)
            {
                _isDiffPending = false;
                ClipboardManager.CopyImage(result);
                ToastHelper.Show("Diff copied to clipboard");
            }
        };
        overlay.Show();
    }

    private void StartGifRecording(System.Drawing.Rectangle region)
    {
        var sessionId = RustBridge.GifStart();
        if (sessionId == null) return;

        var pill = new RecordingPill(region);
        pill.Show();

        var timer = new System.Windows.Threading.DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(100) // 10fps
        };
        timer.Tick += (s, e) =>
        {
            RustBridge.GifAddFrame(sessionId, region);
        };
        timer.Start();

        pill.OnStop += () =>
        {
            timer.Stop();
            pill.Close();
            var result = RustBridge.GifFinish(sessionId);
            if (result != null)
            {
                ClipboardManager.CopyImage(result);
                ToastHelper.Show("GIF copied to clipboard");
            }
        };
    }

    private void ShowSettings()
    {
        var settings = new SettingsWindow();
        settings.ShowDialog();
    }
}
