using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace ScreenshotTool.Models;

public class ScreenshotEntry
{
    public string FilePath { get; set; } = "";
    public DateTime Timestamp { get; set; } = DateTime.Now;

    public string FileName => Path.GetFileName(FilePath);

    public string TimeAgo
    {
        get
        {
            var span = DateTime.Now - Timestamp;
            if (span.TotalSeconds < 60) return "just now";
            if (span.TotalMinutes < 60) return $"{(int)span.TotalMinutes}m ago";
            if (span.TotalHours < 24) return $"{(int)span.TotalHours}h ago";
            return $"{(int)span.TotalDays}d ago";
        }
    }
}

public class ScreenshotHistory
{
    private const int MaxEntries = 10;
    private static readonly string HistoryPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".pixyvibe", "history.json");

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private static ScreenshotHistory? _instance;
    public static ScreenshotHistory Instance => _instance ??= Load();

    public List<ScreenshotEntry> Entries { get; set; } = new();

    public event Action? HistoryChanged;

    public void Add(string? filePath, byte[]? imageData = null)
    {
        if (string.IsNullOrEmpty(filePath)) return;

        // Remove duplicate
        Entries.RemoveAll(e => e.FilePath == filePath);

        Entries.Insert(0, new ScreenshotEntry
        {
            FilePath = filePath,
            Timestamp = DateTime.Now
        });

        // Trim to max
        while (Entries.Count > MaxEntries)
            Entries.RemoveAt(Entries.Count - 1);

        Save();
        HistoryChanged?.Invoke();
    }

    public void Remove(string filePath)
    {
        Entries.RemoveAll(e => e.FilePath == filePath);
        Save();
        HistoryChanged?.Invoke();
    }

    public void Clear()
    {
        Entries.Clear();
        Save();
        HistoryChanged?.Invoke();
    }

    private static ScreenshotHistory Load()
    {
        try
        {
            if (File.Exists(HistoryPath))
            {
                var json = File.ReadAllText(HistoryPath);
                var history = JsonSerializer.Deserialize<ScreenshotHistory>(json, JsonOpts)
                    ?? new ScreenshotHistory();

                // Remove entries for files that no longer exist
                history.Entries = history.Entries.Where(e => File.Exists(e.FilePath)).ToList();
                _instance = history;
                return history;
            }
        }
        catch { }
        _instance = new ScreenshotHistory();
        return _instance;
    }

    private void Save()
    {
        try
        {
            var dir = Path.GetDirectoryName(HistoryPath)!;
            Directory.CreateDirectory(dir);
            var json = JsonSerializer.Serialize(this, JsonOpts);
            File.WriteAllText(HistoryPath, json);
        }
        catch { }
    }
}
