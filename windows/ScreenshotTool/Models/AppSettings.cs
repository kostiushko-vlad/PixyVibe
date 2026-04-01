using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ScreenshotTool.Models;

public class HotkeyBinding
{
    public uint Modifiers { get; set; }
    public uint VkCode { get; set; }

    [JsonIgnore]
    public string DisplayString => FormatShortcut(Modifiers, VkCode);

    private static string FormatShortcut(uint mod, uint vk)
    {
        var parts = new System.Collections.Generic.List<string>();
        if ((mod & 0x0002) != 0) parts.Add("Ctrl");
        if ((mod & 0x0004) != 0) parts.Add("Shift");
        if ((mod & 0x0001) != 0) parts.Add("Alt");
        if ((mod & 0x0008) != 0) parts.Add("Win");

        var keyName = vk switch
        {
            >= 0x30 and <= 0x39 => ((char)vk).ToString(),
            >= 0x41 and <= 0x5A => ((char)vk).ToString(),
            >= 0x70 and <= 0x87 => $"F{vk - 0x6F}",
            0x20 => "Space",
            0x2C => "PrintScreen",
            _ => $"0x{vk:X2}"
        };
        parts.Add(keyName);
        return string.Join("+", parts);
    }
}

public class AppSettings
{
    // Hotkeys
    public HotkeyBinding ScreenshotHotkey { get; set; } = new() { Modifiers = 0x0006, VkCode = 0x31 }; // Shift+Ctrl+1
    public HotkeyBinding GifHotkey { get; set; } = new() { Modifiers = 0x0006, VkCode = 0x32 };        // Shift+Ctrl+2
    public HotkeyBinding DiffHotkey { get; set; } = new() { Modifiers = 0x0006, VkCode = 0x36 };       // Shift+Ctrl+6

    // Capture
    public int GifFps { get; set; } = 10;
    public int GifMaxDuration { get; set; } = 30;
    public int ImageMaxWidth { get; set; } = 1280;
    public int JpegQuality { get; set; } = 85;

    // Output
    public string SaveLocation { get; set; } = "";
    public bool AutoCleanup { get; set; } = true;
    public int CleanupDays { get; set; } = 30;

    // State
    public bool OnboardingComplete { get; set; }

    // Paired devices (device IDs)
    public string[] PairedDeviceIds { get; set; } = Array.Empty<string>();

    private static readonly string ConfigDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".pixyvibe");
    private static readonly string ConfigPath = Path.Combine(ConfigDir, "config.json");

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private static AppSettings? _instance;
    public static AppSettings Instance => _instance ??= Load();

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(ConfigPath))
            {
                var json = File.ReadAllText(ConfigPath);
                _instance = JsonSerializer.Deserialize<AppSettings>(json, JsonOpts) ?? new AppSettings();
                return _instance;
            }
        }
        catch { }
        _instance = new AppSettings();
        return _instance;
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(ConfigDir);
            var json = JsonSerializer.Serialize(this, JsonOpts);
            File.WriteAllText(ConfigPath, json);
        }
        catch { }
    }

    public string ToRustConfigJson()
    {
        var config = new
        {
            output_dir = string.IsNullOrEmpty(SaveLocation)
                ? Path.Combine(ConfigDir, "captures")
                : SaveLocation,
            max_width = ImageMaxWidth,
            jpeg_quality = JpegQuality,
            gif_fps = GifFps,
            cleanup_enabled = AutoCleanup,
            cleanup_age_days = CleanupDays
        };
        return JsonSerializer.Serialize(config);
    }
}
