using System;
using System.Diagnostics;
using System.IO;
using Microsoft.Win32;

namespace KeyStats.Services;

public class StartupManager
{
    private static StartupManager? _instance;
    public static StartupManager Instance => _instance ??= new StartupManager();

    private const string RegistryKeyPath = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";
    private const string AppName = "KeyStats";

    private StartupManager() { }

    public bool IsEnabled
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(RegistryKeyPath, false);
                return key?.GetValue(AppName) != null;
            }
            catch
            {
                return false;
            }
        }
    }

    public void SyncWithSettings()
    {
        try
        {
            var shouldEnable = StatsManager.Instance.Settings.LaunchAtStartup;
            if (!shouldEnable)
            {
                return;
            }

            using var key = Registry.CurrentUser.OpenSubKey(RegistryKeyPath, true);
            if (key == null)
            {
                return;
            }

            var currentExePath = GetCurrentExecutablePath();
            if (string.IsNullOrWhiteSpace(currentExePath))
            {
                return;
            }

            var configuredExePath = GetConfiguredExecutablePath(key);
            if (!PathsEqual(configuredExePath, currentExePath))
            {
                key.SetValue(AppName, $"\"{currentExePath}\"");
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error syncing startup: {ex.Message}");
        }
    }

    public void SetEnabled(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RegistryKeyPath, true);
            if (key == null)
            {
                return;
            }

            if (enabled)
            {
                var exePath = GetCurrentExecutablePath();
                if (!string.IsNullOrWhiteSpace(exePath))
                {
                    key.SetValue(AppName, $"\"{exePath}\"");
                }
            }
            else
            {
                key.DeleteValue(AppName, false);
            }

            StatsManager.Instance.Settings.LaunchAtStartup = enabled;
            StatsManager.Instance.SaveSettings();
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error setting startup: {ex.Message}");
            throw;
        }
    }

    private static string? GetCurrentExecutablePath()
    {
        try
        {
            var exePath = Process.GetCurrentProcess().MainModule?.FileName;
            if (!string.IsNullOrWhiteSpace(exePath))
            {
                return Path.GetFullPath(exePath);
            }
        }
        catch
        {
        }

        try
        {
            var exePath = System.Reflection.Assembly.GetExecutingAssembly().Location;
            if (!string.IsNullOrWhiteSpace(exePath))
            {
                return Path.GetFullPath(exePath);
            }
        }
        catch
        {
        }

        return null;
    }

    private static string? GetConfiguredExecutablePath(RegistryKey key)
    {
        if (key.GetValue(AppName) is not string rawValue || string.IsNullOrWhiteSpace(rawValue))
        {
            return null;
        }

        var trimmed = rawValue.Trim();
        if (trimmed.StartsWith("\"", StringComparison.Ordinal))
        {
            var closingQuoteIndex = trimmed.IndexOf('"', 1);
            if (closingQuoteIndex > 1)
            {
                trimmed = trimmed.Substring(1, closingQuoteIndex - 1);
            }
        }
        else
        {
            var firstSpaceIndex = trimmed.IndexOf(' ');
            if (firstSpaceIndex > 0)
            {
                trimmed = trimmed.Substring(0, firstSpaceIndex);
            }
        }

        try
        {
            return Path.GetFullPath(trimmed);
        }
        catch
        {
            return trimmed;
        }
    }

    private static bool PathsEqual(string? left, string? right)
    {
        if (string.IsNullOrWhiteSpace(left) || string.IsNullOrWhiteSpace(right))
        {
            return false;
        }

        return string.Equals(left, right, StringComparison.OrdinalIgnoreCase);
    }
}
