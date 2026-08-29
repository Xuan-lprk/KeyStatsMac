using System;
using System.Windows;
using System.Windows.Input;
using System.Reflection;
using System.IO;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using KeyStats.Helpers;
using KeyStats.Services;
using KeyStats.Views;
using DrawingIcon = System.Drawing.Icon;
using PixelFormat = System.Drawing.Imaging.PixelFormat;
using static KeyStats.Helpers.NativeInterop;

namespace KeyStats.ViewModels;

public class TrayIconViewModel : ViewModelBase
{
    private DrawingIcon? _trayIcon;
    private string _tooltipText = "KeyStats";
    private StatsPopupWindow? _trayPopupWindow;
    private StatsPopupWindow? _mainWindow;

    public DrawingIcon? TrayIcon
    {
        get => _trayIcon;
        set => SetProperty(ref _trayIcon, value);
    }

    public string TooltipText
    {
        get => _tooltipText;
        set => SetProperty(ref _tooltipText, value);
    }

    public ICommand TogglePopupCommand { get; }
    public ICommand ShowStatsCommand { get; }
    public ICommand QuitCommand { get; }

    public TrayIconViewModel()
    {
        TogglePopupCommand = new RelayCommand(TogglePopup);
        ShowStatsCommand = new RelayCommand(ShowStats);
        QuitCommand = new RelayCommand(Quit);

        LoadTrayIconOnce();
    }

    private void LoadTrayIconOnce()
    {
        // Use the static tray icon image and size it once for the current DPI.
        try
        {
            var assembly = Assembly.GetExecutingAssembly();
            var resourceName = "KeyStats.Resources.Icons.tray-icon.png";

            using var stream = assembly.GetManifestResourceStream(resourceName);
            if (stream != null)
            {
                using var originalBitmap = new Bitmap(stream);
                var iconSize = GetSystemTrayIconSize();
                using var resizedBitmap = ResizeBitmapHighQuality(originalBitmap, iconSize, iconSize);
                var hIcon = resizedBitmap.GetHicon();
                var tempIcon = DrawingIcon.FromHandle(hIcon);
                TrayIcon = (DrawingIcon)tempIcon.Clone();
                tempIcon.Dispose();
                NativeInterop.DestroyIcon(hIcon);
                return;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error loading tray icon: {ex.Message}");
        }

        try
        {
            var exePath = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
            var iconPath = Path.Combine(exePath ?? string.Empty, "Resources", "Icons", "tray-icon.png");
            if (File.Exists(iconPath))
            {
                using var originalBitmap = new Bitmap(iconPath);
                var iconSize = GetSystemTrayIconSize();
                using var resizedBitmap = ResizeBitmapHighQuality(originalBitmap, iconSize, iconSize);
                var hIcon = resizedBitmap.GetHicon();
                var tempIcon = DrawingIcon.FromHandle(hIcon);
                TrayIcon = (DrawingIcon)tempIcon.Clone();
                tempIcon.Dispose();
                NativeInterop.DestroyIcon(hIcon);
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error loading tray icon from file: {ex.Message}");
        }
    }

    private static int GetSystemTrayIconSize()
    {
        using var screen = Graphics.FromHwnd(IntPtr.Zero);
        var dpiX = screen.DpiX;

        var size = (int)(16 * dpiX / 96);

        if (size <= 16) return 16;
        if (size <= 20) return 20;
        if (size <= 24) return 24;
        if (size <= 32) return 32;
        if (size <= 48) return 48;
        return 64;
    }

    /// <summary>
    /// Resize the tray image with high quality sampling to keep edges sharp.
    /// </summary>
    private static Bitmap ResizeBitmapHighQuality(Bitmap original, int width, int height)
    {
        var resized = new Bitmap(width, height, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(resized))
        {
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.SmoothingMode = SmoothingMode.HighQuality;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.CompositingQuality = CompositingQuality.HighQuality;
            g.DrawImage(original, 0, 0, width, height);
        }

        return resized;
    }

    private void TogglePopup()
    {
        Console.WriteLine("=== TogglePopup called ===");
        try
        {
            if (_trayPopupWindow != null && _trayPopupWindow.IsVisible)
            {
                Console.WriteLine("Closing existing window");
                _trayPopupWindow.CloseWindow(force: true);
                _trayPopupWindow = null;
            }
            else
            {
                Console.WriteLine("Calling ShowStats...");
                ShowPopup();
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"TogglePopup error: {ex}");
        }
    }

    public void ShowStats()
    {
        ShowStats(null);
    }

    public void ShowStats(System.Drawing.Point? anchorPoint)
    {
        ShowPopup(anchorPoint);
    }

    public void ShowPopup(System.Drawing.Point? anchorPoint = null)
    {
        try
        {
            Console.WriteLine("ShowPopup called...");
            if (_trayPopupWindow != null)
            {
                if (!_trayPopupWindow.IsVisible)
                {
                    _trayPopupWindow.ShowWindow(anchorPoint);
                    return;
                }

                if (_trayPopupWindow.WindowState == WindowState.Minimized)
                {
                    _trayPopupWindow.WindowState = WindowState.Normal;
                }

                _trayPopupWindow.Activate();
                return;
            }

            Console.WriteLine("Creating tray popup window...");
            _trayPopupWindow = new StatsPopupWindow(StatsPopupWindow.DisplayMode.TrayPopup, anchorPoint);
            _trayPopupWindow.Closed += (_, _) => _trayPopupWindow = null;
            Console.WriteLine("Showing window...");
            _trayPopupWindow.ShowWindow(anchorPoint);
            Console.WriteLine("Window shown.");
        }
        catch (Exception ex)
        {
            Console.WriteLine("=== ERROR IN SHOWPOPUP ===");
            Console.WriteLine(ex.ToString());
            Console.WriteLine("=== END ERROR ===");
        }
    }

    public void ShowMainWindow()
    {
        try
        {
            Console.WriteLine("ShowMainWindow called...");
            if (_mainWindow != null)
            {
                if (!_mainWindow.IsVisible)
                {
                    _mainWindow.ShowWindow();
                    return;
                }

                if (_mainWindow.WindowState == WindowState.Minimized)
                {
                    _mainWindow.WindowState = WindowState.Normal;
                }

                _mainWindow.Activate();
                return;
            }

            Console.WriteLine("Creating main window...");
            _mainWindow = new StatsPopupWindow(StatsPopupWindow.DisplayMode.Windowed);
            _mainWindow.Closed += (_, _) => _mainWindow = null;
            _mainWindow.ShowWindow();
        }
        catch (Exception ex)
        {
            Console.WriteLine("=== ERROR IN SHOWMAINWINDOW ===");
            Console.WriteLine(ex.ToString());
            Console.WriteLine("=== END ERROR ===");
        }
    }

    private void Quit()
    {
        PrepareForExit();
        StatsManager.Instance.FlushPendingSave();
        InputMonitorService.Instance.StopMonitoring();
        Application.Current.Shutdown();
    }

    public void PrepareForExit()
    {
        _trayPopupWindow?.PrepareForExit();
        _mainWindow?.PrepareForExit();
    }

    public void Cleanup()
    {
        _trayPopupWindow = null;
        _mainWindow = null;
        _trayIcon?.Dispose();
        _trayIcon = null;
    }
}
