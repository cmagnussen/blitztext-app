using System.IO;
using System.Text.Json;
using BlitztextWin.Core;

namespace BlitztextWin.App.Services;

public sealed class SettingsStore
{
    private static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true,
    };

    private readonly string settingsPath;

    public SettingsStore()
    {
        var directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Blitztext");
        Directory.CreateDirectory(directory);
        settingsPath = Path.Combine(directory, "windows-settings.json");
    }

    public BlitztextSettings Load()
    {
        if (!File.Exists(settingsPath))
        {
            return new BlitztextSettings();
        }

        try
        {
            var json = File.ReadAllText(settingsPath);
            return JsonSerializer.Deserialize<BlitztextSettings>(json, Options) ?? new BlitztextSettings();
        }
        catch (JsonException)
        {
            return new BlitztextSettings();
        }
        catch (IOException)
        {
            return new BlitztextSettings();
        }
    }

    public void Save(BlitztextSettings settings)
    {
        var json = JsonSerializer.Serialize(settings, Options);
        File.WriteAllText(settingsPath, json);
    }
}
