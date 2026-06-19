using System;
using System.IO;

namespace WorklogCalendar.Services;

/// <summary>
/// Append-only file logger. Lives at %LOCALAPPDATA%\WorklogCalendar\worklog.log.
/// Lock-coordinated across threads. No external dependencies, no async — meant
/// to be cheap enough to drop into any code path (drag callbacks included)
/// without changing call shape.
///
/// Rotates when the file passes ~2 MB: renames worklog.log → worklog.prev.log
/// and starts a fresh file.
/// </summary>
public static class FileLogger
{
    private static readonly object _gate = new();
    private const long MaxBytes = 2L * 1024 * 1024;

    public static string LogPath { get; } =
        Path.Combine(SettingsService.ConfigDir, "worklog.log");

    private static string PrevPath { get; } =
        Path.Combine(SettingsService.ConfigDir, "worklog.prev.log");

    public static void Log(string tag, string message)
    {
        try
        {
            lock (_gate)
            {
                Directory.CreateDirectory(SettingsService.ConfigDir);
                if (File.Exists(LogPath))
                {
                    var info = new FileInfo(LogPath);
                    if (info.Length > MaxBytes)
                    {
                        try { if (File.Exists(PrevPath)) File.Delete(PrevPath); } catch { }
                        try { File.Move(LogPath, PrevPath); } catch { }
                    }
                }
                var line = $"{DateTime.Now:HH:mm:ss.fff} [{tag}] {message}\n";
                File.AppendAllText(LogPath, line);
            }
        }
        catch { /* never let logging crash the app */ }
    }

    public static void Section(string title)
    {
        Log("---", "");
        Log("---", title);
        Log("---", "");
    }
}
