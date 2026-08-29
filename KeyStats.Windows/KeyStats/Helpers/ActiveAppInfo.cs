using System;

namespace KeyStats.Helpers;

public sealed class ActiveAppInfo
{
    public static ActiveAppInfo Unknown { get; } = new("Unknown", "Unknown", string.Empty, 0, IntPtr.Zero);

    public string AppName { get; }
    public string DisplayName { get; }
    public string WindowTitle { get; }
    public uint ProcessId { get; }
    public IntPtr WindowHandle { get; }

    public bool IsKnown => !string.Equals(AppName, "Unknown", StringComparison.OrdinalIgnoreCase);

    public ActiveAppInfo(string appName, string displayName, string windowTitle, uint processId, IntPtr windowHandle)
    {
        AppName = string.IsNullOrWhiteSpace(appName) ? "Unknown" : appName.Trim();
        DisplayName = string.IsNullOrWhiteSpace(displayName) ? AppName : displayName.Trim();
        WindowTitle = windowTitle?.Trim() ?? string.Empty;
        ProcessId = processId;
        WindowHandle = windowHandle;
    }
}
