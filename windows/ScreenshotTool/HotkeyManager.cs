using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using ScreenshotTool.Models;

namespace ScreenshotTool;

public class HotkeyManager
{
    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private const int HOTKEY_SCREENSHOT = 1;
    private const int HOTKEY_GIF = 2;
    private const int HOTKEY_DIFF = 3;
    private const int WM_HOTKEY = 0x0312;

    private HwndSource? _source;
    private IntPtr _windowHandle;
    private bool _isPaused;
    private AppSettings? _settings;

    public event Action<CaptureMode>? OnAction;

    public void RegisterAll(AppSettings settings)
    {
        _settings = settings;

        // Create a hidden window for receiving hotkey messages
        var helper = new WindowInteropHelper(new Window { Width = 0, Height = 0, ShowInTaskbar = false });
        helper.EnsureHandle();
        _windowHandle = helper.Handle;

        _source = HwndSource.FromHwnd(_windowHandle);
        _source?.AddHook(WndProc);

        RegisterFromSettings();
    }

    private void RegisterFromSettings()
    {
        if (_settings == null || _windowHandle == IntPtr.Zero) return;

        RegisterHotKey(_windowHandle, HOTKEY_SCREENSHOT,
            _settings.ScreenshotHotkey.Modifiers, _settings.ScreenshotHotkey.VkCode);
        RegisterHotKey(_windowHandle, HOTKEY_GIF,
            _settings.GifHotkey.Modifiers, _settings.GifHotkey.VkCode);
        RegisterHotKey(_windowHandle, HOTKEY_DIFF,
            _settings.DiffHotkey.Modifiers, _settings.DiffHotkey.VkCode);
    }

    public void UnregisterAll()
    {
        if (_windowHandle == IntPtr.Zero) return;
        UnregisterHotKey(_windowHandle, HOTKEY_SCREENSHOT);
        UnregisterHotKey(_windowHandle, HOTKEY_GIF);
        UnregisterHotKey(_windowHandle, HOTKEY_DIFF);
    }

    public void ReregisterAll(AppSettings settings)
    {
        _settings = settings;
        UnregisterAll();
        RegisterFromSettings();
    }

    public void Pause()
    {
        if (_isPaused) return;
        _isPaused = true;
        UnregisterAll();
    }

    public void Resume()
    {
        if (!_isPaused) return;
        _isPaused = false;
        RegisterFromSettings();
    }

    public void Dispose()
    {
        UnregisterAll();
        _source?.RemoveHook(WndProc);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WM_HOTKEY && !_isPaused)
        {
            var mode = wParam.ToInt32() switch
            {
                HOTKEY_SCREENSHOT => CaptureMode.Screenshot,
                HOTKEY_GIF => CaptureMode.Gif,
                HOTKEY_DIFF => CaptureMode.Diff,
                _ => (CaptureMode?)null
            };

            if (mode.HasValue)
            {
                OnAction?.Invoke(mode.Value);
                handled = true;
            }
        }
        return IntPtr.Zero;
    }
}
