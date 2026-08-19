using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text.Json;

namespace WorklogCalendar.Services;

/// <summary>
/// Strongly-typed user settings. Persisted as JSON under
/// %LOCALAPPDATA%\WorklogCalendar\settings.json. Equivalent of the kcfg file
/// (categorizedtodorc) in the KDE plasmoid.
/// </summary>
public sealed class AppSettings : INotifyPropertyChanged
{
    // -------- Jira (instance 1) --------
    public string JiraSite { get; set; } = "";
    public string JiraEmail { get; set; } = "";
    public string JiraToken { get; set; } = "";
    public string JiraIssueJql { get; set; } =
        "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC";
    public int JiraIssueMax { get; set; } = 50;
    public bool ShowJiraSummary { get; set; } = false;
    public bool JiraDebug { get; set; } = true;

    // -------- Jira (instance 2) --------
    /// <summary>Turn the second Jira instance on. Its blocks share the Jira
    /// region of the calendar and are told apart by their own colour.</summary>
    public bool Jira2Enabled { get; set; } = false;
    public string Jira2Site { get; set; } = "";
    public string Jira2Email { get; set; } = "";
    public string Jira2Token { get; set; } = "";

    /// <summary>Block fill colour for Jira instance 1 (hex #rrggbb).</summary>
    public string Jira1BlockColor { get; set; } = "#9b91e6";
    /// <summary>Block fill colour for Jira instance 2 (hex #rrggbb).</summary>
    public string Jira2BlockColor { get; set; } = "#26a69a";

    // -------- Clockify --------
    public string ClockifyApiKey { get; set; } = "";
    public string ClockifyWorkspaceId { get; set; } = "";
    public string ClockifyUserId { get; set; } = "";
    public string ClockifyDefaultProjectId { get; set; } = "";
    public bool ClockifyBillableDefault { get; set; } = true;
    public bool ClockifyDebug { get; set; } = true;
    /// <summary>Clockify project that Jira instance 1 syncs into. Empty = no project.</summary>
    public string Jira1ClockifyProjectId { get; set; } = "";
    /// <summary>Clockify project that Jira instance 2 syncs into. Empty = no project.</summary>
    public string Jira2ClockifyProjectId { get; set; } = "";

    // -------- Google Calendar (read-only) --------
    /// <summary>Show Google Calendar events as background blocks.</summary>
    public bool GoogleCalEnabled { get; set; } = false;
    public string GoogleClientId { get; set; } = "";
    public string GoogleClientSecret { get; set; } = "";
    /// <summary>Long-lived refresh token from the device-code authorization.</summary>
    public string GoogleRefreshToken { get; set; } = "";
    /// <summary>Up to 3 calendar ids to display.</summary>
    public List<string> GoogleCalendarIds { get; set; } = new();
    /// <summary>Per-calendar base colours, parallel to GoogleCalendarIds.</summary>
    public List<string> GoogleCalendarColors { get; set; } = new();
    public bool GoogleCalDebug { get; set; } = true;

    // -------- View / behaviour --------
    /// <summary>"9h" (09:00-18:00) or "24h" (00:00-24:00).</summary>
    public string ViewMode { get; set; } = "9h";
    /// <summary>"jira", "clockify" or "jira-clockify" (split).</summary>
    public string Source { get; set; } = "jira";
    public double DailyTargetHours { get; set; } = 8;
    public int WindowWidth { get; set; } = 1280;
    public int WindowHeight { get; set; } = 760;
    public bool AlwaysOnTop { get; set; } = false;
    /// <summary>Week start day. 0 = Sunday, 1 = Monday. Default 0 to match the plasmoid.</summary>
    public int FirstDayOfWeek { get; set; } = 0;

    // -------- Modal size --------
    /// <summary>Width of the Jira / Clockify edit dialogs (px). Clamped to window − margin.</summary>
    public int ModalWidth { get; set; } = 720;
    /// <summary>Height of the Jira / Clockify edit dialogs (px). Clamped to window − margin.</summary>
    public int ModalHeight { get; set; } = 520;

    // -------- Sprint gauges (Jira / Jira-Clockify, 9h mode only) --------
    /// <summary>Render the two ring gauges below the calendar.</summary>
    public bool ShowSprintGauges { get; set; } = true;
    /// <summary>"subtask-customfield" (default), "agile-board" or "assignee-jql".</summary>
    public string SprintStrategy { get; set; } = "subtask-customfield";
    /// <summary>Custom-field id holding the sprint array. Default works on most Jira Cloud sites.</summary>
    public string SprintField { get; set; } = "customfield_10020";
    /// <summary>Board id for the agile-board strategy. 0 = unset.</summary>
    public int SprintBoardId { get; set; } = 0;
    /// <summary>"api" (Jira's remainingEstimate) or "calculated" (original - spent).</summary>
    public string RemainingMode { get; set; } = "api";

    // -------- Bottom panel --------
    /// <summary>Which bottom-panel view shows: "rings", "subtasks" or "heatmap".</summary>
    public string BottomView { get; set; } = "rings";
    /// <summary>
    /// Whether the Sprint/Horas rings are offered as a bottom-panel view.
    /// Off by default — the subtask table is the more useful day-to-day
    /// view. When off, rings is excluded from the wheel cycle and its
    /// switch button is grayed out.
    /// </summary>
    public bool ShowRingsView { get; set; } = false;
    /// <summary>Gate the third (subtask table) view on/off.</summary>
    public bool ShowSubtaskTable { get; set; } = true;
    /// <summary>JQL that drives the subtask table.</summary>
    public string SubtaskJql { get; set; } =
        "issuetype in subTaskIssueTypes() AND assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC";
    /// <summary>Show the optional "Padre" column with parent-issue key.</summary>
    public bool SubtaskShowParent { get; set; } = true;

    // Events aren't serialized by System.Text.Json — no [JsonIgnore] needed
    // (and [JsonIgnore] would fail to compile on an event anyway).
    public event PropertyChangedEventHandler? PropertyChanged;
    public void Raise([CallerMemberName] string name = "") =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

public static class SettingsService
{
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public static string ConfigDir
    {
        get
        {
            var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            return Path.Combine(root, "WorklogCalendar");
        }
    }

    public static string SettingsPath => Path.Combine(ConfigDir, "settings.json");

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(SettingsPath))
            {
                var json = File.ReadAllText(SettingsPath);
                var loaded = JsonSerializer.Deserialize<AppSettings>(json, JsonOpts);
                if (loaded != null) return loaded;
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[Settings] load failed: {ex.Message}");
        }
        return new AppSettings();
    }

    public static void Save(AppSettings s)
    {
        try
        {
            Directory.CreateDirectory(ConfigDir);
            File.WriteAllText(SettingsPath, JsonSerializer.Serialize(s, JsonOpts));
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[Settings] save failed: {ex.Message}");
        }
    }
}
