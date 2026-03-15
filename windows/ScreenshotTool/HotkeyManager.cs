using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace ScreenshotTool;

public class HotkeyManager
{
    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private const int HOTKEY_ID = 1;
    private const uint MOD_SHIFT = 0x0004;
    private const uint MOD_CONTROL = 0x0002;
    private const uint VK_6 = 0x36;
    private const int WM_HOTKEY = 0x0312;

    private HwndSource? _source;
    private IntPtr _windowHandle;

    public event Action? OnHotkeyPressed;

    public void Register()
    {
        // Create a hidden window for receiving hotkey messages
        var helper = new WindowInteropHelper(new Window { Width = 0, Height = 0, ShowInTaskbar = false });
        helper.EnsureHandle();
        _windowHandle = helper.Handle;

        _source = HwndSource.FromHwnd(_windowHandle);
        _source?.AddHook(WndProc);

        RegisterHotKey(_windowHandle, HOTKEY_ID, MOD_SHIFT | MOD_CONTROL, VK_6);
    }

    public void Unregister()
    {
        UnregisterHotKey(_windowHandle, HOTKEY_ID);
        _source?.RemoveHook(WndProc);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WM_HOTKEY && wParam.ToInt32() == HOTKEY_ID)
        {
            OnHotkeyPressed?.Invoke();
            handled = true;
        }
        return IntPtr.Zero;
    }
}
