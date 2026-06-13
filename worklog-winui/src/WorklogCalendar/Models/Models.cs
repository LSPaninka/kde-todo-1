using System.Collections.Generic;

namespace WorklogCalendar.Models;

/// <summary>One Jira worklog as rendered on the calendar.</summary>
public sealed class JiraWorklog
{
    public string Id { get; set; } = "";
    public string IssueId { get; set; } = "";
    public string IssueKey { get; set; } = "";
    public string IssueSummary { get; set; } = "";
    public long StartedUnixMs { get; set; }
    public int DurationSec { get; set; }
    public string Comment { get; set; } = "";
}

/// <summary>Issue in the picker shown by the Jira "new worklog" dialog.</summary>
public sealed class JiraIssue
{
    public string Key { get; set; } = "";
    public string Summary { get; set; } = "";
    public string IssueType { get; set; } = "";
    public string Status { get; set; } = "";
    /// <summary>Remaining estimate in seconds. Shown in the picker's right column.</summary>
    public int RemainingSec { get; set; }
    public string Display => $"{Key} - {Summary}";

    /// <summary>"Subtarea · EN CURSO · 2h 30m" — meta column in the picker.</summary>
    public string MetaDisplay
    {
        get
        {
            var parts = new System.Collections.Generic.List<string>();
            if (!string.IsNullOrEmpty(IssueType)) parts.Add(IssueType);
            if (!string.IsNullOrEmpty(Status)) parts.Add(Status);
            if (RemainingSec > 0)
            {
                int h = RemainingSec / 3600, m = (RemainingSec % 3600) / 60;
                parts.Add(h > 0 && m > 0 ? $"{h}h {m}m" : h > 0 ? $"{h}h" : $"{m}m");
            }
            return string.Join(" · ", parts);
        }
    }
}

/// <summary>Active Jira sprint as discovered by JiraWorklogStore.</summary>
public sealed class JiraSprint
{
    public long Id { get; set; }
    public string Name { get; set; } = "";
    /// <summary>ISO-8601 start date, e.g. "2026-05-19T13:00:00.000Z". Empty if unknown.</summary>
    public string StartDate { get; set; } = "";
    public string EndDate { get; set; } = "";
}

/// <summary>One issue's contribution to the sprint's "Disponible" hours.</summary>
public sealed class SprintAvailableItem
{
    public string Key { get; set; } = "";
    public string Summary { get; set; } = "";
    public int RemainingSec { get; set; }
}

/// <summary>One Clockify time entry as rendered on the calendar.</summary>
public sealed class ClockifyEntry
{
    public string Id { get; set; } = "";
    public long StartedUnixMs { get; set; }
    public int DurationSec { get; set; }
    public string Description { get; set; } = "";
    public string ProjectId { get; set; } = "";
    public string ProjectName { get; set; } = "";
    public string ProjectColor { get; set; } = "";
    public List<string> TagIds { get; set; } = new();
    public List<string> TagNames { get; set; } = new();
    public bool Billable { get; set; }
}

public sealed class ClockifyProject
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Color { get; set; } = "";
    public bool Billable { get; set; }
    public string DisplayName => string.IsNullOrEmpty(Name) ? "(sin nombre)" : Name;
}

public sealed class ClockifyTag
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
}
