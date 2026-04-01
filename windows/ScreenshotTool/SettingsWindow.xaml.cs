using System;
using System.Windows;
using Microsoft.Win32;
using ScreenshotTool.Models;

namespace ScreenshotTool;

public partial class SettingsWindow : Window
{
    private readonly AppSettings _settings;
    public event Action? OnSettingsChanged;

    public SettingsWindow()
    {
        InitializeComponent();
        _settings = AppSettings.Instance;
        LoadSettings();
        Closed += (_, _) => SaveSettings();
    }

    private void LoadSettings()
    {
        // Hotkeys
        ScreenshotHotkey.Binding = _settings.ScreenshotHotkey;
        GifHotkey.Binding = _settings.GifHotkey;
        DiffHotkey.Binding = _settings.DiffHotkey;

        ScreenshotHotkey.ShortcutChanged += b => _settings.ScreenshotHotkey = b;
        GifHotkey.ShortcutChanged += b => _settings.GifHotkey = b;
        DiffHotkey.ShortcutChanged += b => _settings.DiffHotkey = b;

        // Capture
        FpsSlider.Value = _settings.GifFps;
        DurationSlider.Value = _settings.GifMaxDuration;
        MaxWidthSlider.Value = _settings.ImageMaxWidth;
        QualitySlider.Value = _settings.JpegQuality;

        // Output
        SavePath.Text = string.IsNullOrEmpty(_settings.SaveLocation)
            ? System.IO.Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".pixyvibe", "captures")
            : _settings.SaveLocation;
        AutoCleanupCheck.IsChecked = _settings.AutoCleanup;
        CleanupSlider.Value = _settings.CleanupDays;
        CleanupAgePanel.Visibility = _settings.AutoCleanup ? Visibility.Visible : Visibility.Collapsed;
    }

    private void SaveSettings()
    {
        _settings.GifFps = (int)FpsSlider.Value;
        _settings.GifMaxDuration = (int)DurationSlider.Value;
        _settings.ImageMaxWidth = (int)MaxWidthSlider.Value;
        _settings.JpegQuality = (int)QualitySlider.Value;
        _settings.AutoCleanup = AutoCleanupCheck.IsChecked == true;
        _settings.CleanupDays = (int)CleanupSlider.Value;
        _settings.Save();
        OnSettingsChanged?.Invoke();
    }

    private void Browse_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = "Choose save location" };
        if (dialog.ShowDialog() == true)
        {
            SavePath.Text = dialog.FolderName;
            _settings.SaveLocation = dialog.FolderName;
        }
    }

    private void ResetHotkeys_Click(object sender, RoutedEventArgs e)
    {
        _settings.ScreenshotHotkey = new HotkeyBinding { Modifiers = 0x0006, VkCode = 0x31 };
        _settings.GifHotkey = new HotkeyBinding { Modifiers = 0x0006, VkCode = 0x32 };
        _settings.DiffHotkey = new HotkeyBinding { Modifiers = 0x0006, VkCode = 0x36 };
        ScreenshotHotkey.Binding = _settings.ScreenshotHotkey;
        GifHotkey.Binding = _settings.GifHotkey;
        DiffHotkey.Binding = _settings.DiffHotkey;
    }

    private void FpsSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (FpsLabel != null) FpsLabel.Text = $"{(int)e.NewValue} fps";
    }

    private void DurationSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (DurationLabel != null) DurationLabel.Text = $"{(int)e.NewValue}s";
    }

    private void MaxWidthSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (MaxWidthLabel != null) MaxWidthLabel.Text = $"{(int)e.NewValue}px";
    }

    private void QualitySlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (QualityLabel != null) QualityLabel.Text = $"{(int)e.NewValue}%";
    }

    private void AutoCleanup_Changed(object sender, RoutedEventArgs e)
    {
        if (CleanupAgePanel != null)
            CleanupAgePanel.Visibility = AutoCleanupCheck.IsChecked == true
                ? Visibility.Visible : Visibility.Collapsed;
    }

    private void CleanupSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (CleanupLabel != null)
        {
            var days = (int)e.NewValue;
            CleanupLabel.Text = days == 1 ? "1 day" : $"{days} days";
        }
    }
}
