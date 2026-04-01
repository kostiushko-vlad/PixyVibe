using System;
using System.IO;
using System.Threading;
using System.Windows;
using ScreenshotTool.Models;

namespace ScreenshotTool;

public partial class App : Application
{
    private static Mutex? _mutex;
    private HotkeyManager? _hotkeyManager;
    private TrayIconManager? _trayManager;
    private bool _isDiffPending;
    private System.Drawing.Rectangle? _lastDiffRegion;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Global exception handler — log to file so we can diagnose crashes
        DispatcherUnhandledException += (_, args) =>
        {
            var text = args.Exception.ToString();
            var logPath = System.IO.Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".pixyvibe", "crash.log");
            try
            {
                System.IO.Directory.CreateDirectory(System.IO.Path.GetDirectoryName(logPath)!);
                System.IO.File.AppendAllText(logPath, $"\n[{DateTime.Now}]\n{text}\n");
            }
            catch { }
            args.Handled = true;
            Clipboard.SetText(text);
            MessageBox.Show(text + "\n\n(Copied to clipboard)", "PixyVibe Error", MessageBoxButton.OK, MessageBoxImage.Error);
        };

        // Single instance check
        _mutex = new Mutex(true, "PixyVibe_ScreenshotTool", out bool createdNew);
        if (!createdNew)
        {
            MessageBox.Show("PixyVibe is already running.", "PixyVibe");
            Shutdown();
            return;
        }

        var settings = AppSettings.Instance;

        // Initialize Rust core with settings
        RustBridge.Initialize(settings.ToRustConfigJson());

        // Show onboarding if first run
        if (!settings.OnboardingComplete)
        {
            var onboarding = new OnboardingWindow();
            onboarding.ShowDialog();
            settings.OnboardingComplete = true;
            settings.Save();
        }

        // Setup system tray
        _trayManager = new TrayIconManager();
        _trayManager.OnCaptureClicked += () => ShowModePickerOrCapture(null);
        _trayManager.OnSettingsClicked += ShowSettings;
        _trayManager.OnQuitClicked += () => Shutdown();
        _trayManager.OnOpenFolderClicked += OpenCapturesFolder;
        _trayManager.OnHistoryItemClicked += OpenInEditor;

        // Register global hotkeys
        _hotkeyManager = new HotkeyManager();
        _hotkeyManager.OnAction += HandleHotkeyAction;
        _hotkeyManager.RegisterAll(settings);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _hotkeyManager?.Dispose();
        _trayManager?.Dispose();
        RustBridge.Shutdown();
        _mutex?.ReleaseMutex();
        base.OnExit(e);
    }

    private void HandleHotkeyAction(CaptureMode mode)
    {
        ShowOverlay(mode);
    }

    public void ShowModePickerOrCapture(CaptureMode? directMode)
    {
        if (directMode.HasValue)
        {
            HandleHotkeyAction(directMode.Value);
            return;
        }

        // If in diff-after mode, go straight to overlay
        if (_isDiffPending)
        {
            ShowOverlay(CaptureMode.Diff);
            return;
        }

        var picker = new ModePickerOverlay();
        picker.OnModeSelected += selectedMode =>
        {
            picker.Close();
            HandleHotkeyAction(selectedMode);
        };
        picker.OnCompanionSelected += deviceId =>
        {
            picker.Close();
            ShowCompanionPreview(deviceId);
        };
        picker.Show();
    }

    private void ShowOverlay(CaptureMode mode)
    {
        var overlay = new OverlayWindow(_isDiffPending, mode);
        overlay.OnScreenshot += region =>
        {
            var (imageData, filePath) = RustBridge.CaptureAndProcessWithPath(region);
            if (imageData != null)
            {
                ClipboardManager.CopyImage(imageData);
                ScreenshotHistory.Instance.Add(filePath, imageData);
                ShowCapturePreview(imageData, filePath);
            }
        };
        overlay.OnGifStart += StartGifRecording;
        overlay.OnDiffBefore += region =>
        {
            if (RustBridge.DiffStoreBefore(region))
            {
                _isDiffPending = true;
                _lastDiffRegion = region;
                ToastHelper.Show("Before captured — press hotkey again to capture after");
            }
        };
        overlay.OnDiffAfter += HandleDiffAfter;
        overlay.OnCompanionSelected += deviceId => ShowCompanionPreview(deviceId);
        overlay.Show();
    }

    private void HandleDiffAfter(System.Drawing.Rectangle region)
    {
        var (imageData, filePath) = RustBridge.DiffCompareWithPath(region);
        if (imageData != null)
        {
            _isDiffPending = false;
            _lastDiffRegion = null;
            ClipboardManager.CopyImage(imageData);
            ScreenshotHistory.Instance.Add(filePath, imageData);
            ShowCapturePreview(imageData, filePath);
        }
    }

    private void StartGifRecording(System.Drawing.Rectangle region)
    {
        var sessionId = RustBridge.GifStart();
        if (sessionId == null) return;

        var settings = AppSettings.Instance;
        var border = new RecordingBorder(region);
        border.Show();
        var pill = new RecordingPill(region);
        pill.Show();

        var frameInterval = Math.Max(33, 1000 / settings.GifFps);
        var elapsed = 0;

        var timer = new System.Windows.Threading.DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(frameInterval)
        };
        timer.Tick += (s, e) =>
        {
            elapsed += frameInterval;
            if (elapsed >= settings.GifMaxDuration * 1000)
            {
                StopGif();
                return;
            }
            RustBridge.GifAddFrame(sessionId, region);
        };
        timer.Start();

        void StopGif()
        {
            try
            {
                timer.Stop();
                border.Close();
                pill.Close();
                var (imageData, filePath) = RustBridge.GifFinishWithPath(sessionId);
                if (imageData != null)
                {
                    ClipboardManager.CopyImage(imageData);
                    ScreenshotHistory.Instance.Add(filePath, imageData);
                    ShowCapturePreview(imageData, filePath);
                }
            }
            catch (Exception ex)
            {
                Clipboard.SetText(ex.ToString());
                MessageBox.Show(ex.ToString() + "\n\n(Copied to clipboard)", "GIF Error", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        pill.OnStop += StopGif;
    }

    private void ShowCapturePreview(byte[] imageData, string? filePath)
    {
        var preview = new CapturePreviewPanel(imageData, filePath);
        preview.OnEdit += path =>
        {
            if (path != null) OpenInEditor(path);
        };
        preview.Show();
    }

    private void ShowCompanionPreview(string deviceId)
    {
        var window = new CompanionPreviewWindow(deviceId);
        window.OnCaptured += (imageData, filePath) => ShowCapturePreview(imageData, filePath);
        window.Show();
    }

    private void OpenInEditor(string filePath)
    {
        if (!File.Exists(filePath)) return;
        var editor = new EditorWindow(filePath);
        editor.Show();
    }

    private void OpenCapturesFolder()
    {
        var dir = string.IsNullOrEmpty(AppSettings.Instance.SaveLocation)
            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".pixyvibe", "captures")
            : AppSettings.Instance.SaveLocation;
        if (Directory.Exists(dir))
            System.Diagnostics.Process.Start("explorer.exe", dir);
    }

    private void ShowSettings()
    {
        _hotkeyManager?.Pause();
        var settingsWin = new SettingsWindow();
        settingsWin.OnSettingsChanged += () =>
        {
            _hotkeyManager?.ReregisterAll(AppSettings.Instance);
        };
        settingsWin.ShowDialog();
        _hotkeyManager?.Resume();
    }
}
