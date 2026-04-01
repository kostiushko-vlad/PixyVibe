using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using ScreenshotTool.Models;

namespace ScreenshotTool.Controls;

public partial class HotkeyRecorderControl : UserControl
{
    private bool _isRecording;
    private HotkeyBinding _binding = new();

    public event Action<HotkeyBinding>? ShortcutChanged;

    public HotkeyRecorderControl()
    {
        InitializeComponent();
    }

    public HotkeyBinding Binding
    {
        get => _binding;
        set
        {
            _binding = value;
            ShortcutText.Text = _binding.DisplayString;
        }
    }

    private void OnClick(object sender, MouseButtonEventArgs e)
    {
        _isRecording = true;
        ShortcutText.Text = "Press shortcut...";
        Bd.BorderBrush = new SolidColorBrush(Color.FromRgb(0x38, 0xBD, 0xF8));
        Bd.BorderThickness = new Thickness(2);
        Focus();
        e.Handled = true;
    }

    private void OnKeyDown(object sender, KeyEventArgs e)
    {
        if (!_isRecording) return;

        var key = e.Key == Key.System ? e.SystemKey : e.Key;

        // Ignore lone modifier keys
        if (key is Key.LeftShift or Key.RightShift or Key.LeftCtrl or Key.RightCtrl
            or Key.LeftAlt or Key.RightAlt or Key.LWin or Key.RWin)
        {
            return;
        }

        if (key == Key.Escape)
        {
            StopRecording();
            e.Handled = true;
            return;
        }

        uint modifiers = 0;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) modifiers |= 0x0002;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)) modifiers |= 0x0004;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Alt)) modifiers |= 0x0001;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Windows)) modifiers |= 0x0008;

        // Require at least one modifier
        if (modifiers == 0) return;

        var vk = (uint)KeyInterop.VirtualKeyFromKey(key);

        _binding = new HotkeyBinding { Modifiers = modifiers, VkCode = vk };
        ShortcutText.Text = _binding.DisplayString;
        StopRecording();
        ShortcutChanged?.Invoke(_binding);
        e.Handled = true;
    }

    private void OnLostFocus(object sender, RoutedEventArgs e)
    {
        if (_isRecording) StopRecording();
    }

    private void StopRecording()
    {
        _isRecording = false;
        ShortcutText.Text = _binding.DisplayString;
        Bd.BorderBrush = new SolidColorBrush(Color.FromRgb(0x2D, 0x35, 0x48));
        Bd.BorderThickness = new Thickness(1);
    }
}
