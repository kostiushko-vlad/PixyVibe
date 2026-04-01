using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace ScreenshotTool.Models;

public class PairedDeviceInfo
{
    public string DeviceId { get; set; } = "";
    public string DeviceName { get; set; } = "";
    public DateTime PairedAt { get; set; } = DateTime.Now;
}

public class PairedDeviceStore
{
    private static readonly string StorePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".pixyvibe", "devices.json");

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private static PairedDeviceStore? _instance;
    public static PairedDeviceStore Instance => _instance ??= Load();

    public List<PairedDeviceInfo> Devices { get; set; } = new();

    public event Action? DevicesChanged;

    public void Upsert(string deviceId, string deviceName)
    {
        var existing = Devices.FirstOrDefault(d => d.DeviceId == deviceId);
        if (existing != null)
        {
            existing.DeviceName = deviceName;
        }
        else
        {
            Devices.Add(new PairedDeviceInfo
            {
                DeviceId = deviceId,
                DeviceName = deviceName
            });
        }
        Save();
        DevicesChanged?.Invoke();
    }

    public void Remove(string deviceId)
    {
        Devices.RemoveAll(d => d.DeviceId == deviceId);
        Save();
        DevicesChanged?.Invoke();
    }

    private static PairedDeviceStore Load()
    {
        try
        {
            if (File.Exists(StorePath))
            {
                var json = File.ReadAllText(StorePath);
                _instance = JsonSerializer.Deserialize<PairedDeviceStore>(json, JsonOpts)
                    ?? new PairedDeviceStore();
                return _instance;
            }
        }
        catch { }
        _instance = new PairedDeviceStore();
        return _instance;
    }

    private void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(StorePath)!);
            File.WriteAllText(StorePath, JsonSerializer.Serialize(this, JsonOpts));
        }
        catch { }
    }
}
