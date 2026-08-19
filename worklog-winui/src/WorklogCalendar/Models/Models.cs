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

/// <summary>
/// One Google Calendar event, shaped like the worklog entries so the
/// calendar can position it with the same math. Read-only: these blocks
/// are drawn behind the worklog blocks and can't be moved or selected.
/// </summary>
public sealed class GoogleEvent
{
    public string Id { get; set; } = "";
    public string Summary { get; set; } = "";
    public long StartedUnixMs { get; set; }
    public int DurationSec { get; set; }
    /// <summary>Which configured calendar this came from — drives the block colour.</summary>
    public string CalendarId { get; set; } = "";
}

/// <summary>A calendar returned by the Google calendarList endpoint.</summary>
public sealed class GoogleCalendarInfo
{
    public string Id { get; set; } = "";
    public string Label { get; set; } = "";
    public override string ToString() => Label;
}

/// <summary>One issue's contribution to the sprint's "Disponible" hours.</summary>
public sealed class SprintAvailableItem
{
    public string Key { get; set; } = "";
    public string Summary { get; set; } = "";
    public int RemainingSec { get; set; }
}

/// <summary>One row of the subtask table (third bottom-panel view).</summary>
public sealed class JiraSubtask
{
    public string Key { get; set; } = "";
    public string Summary { get; set; } = "";
    public string Status { get; set; } = "";
    /// <summary>statusCategory.key — "new", "indeterminate" or "done".</summary>
    public string StatusCategory { get; set; } = "";
    /// <summary>statusCategory.colorName — CSS-ish color name from Jira (green / yellow / blue-gray / warm-red / medium-gray).</summary>
    public string StatusColor { get; set; } = "";
    public int RemainingSec { get; set; }
    public string ParentKey { get; set; } = "";
    public string ParentSummary { get; set; } = "";
}

/// <summary>One workflow transition for a Jira issue (right-click → Cambiar estado).</summary>
public sealed class JiraTransition
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string ToStatus { get; set; } = "";
    public string ToStatusColor { get; set; } = "";
}

/// <summary>Full issue data shown by the subtask detail dialog.</summary>
public sealed class JiraIssueDetail
{
    public string Key { get; set; } = "";
    public string Summary { get; set; } = "";
    public string Status { get; set; } = "";
    public string StatusCategory { get; set; } = "";
    public string StatusColor { get; set; } = "";
    public string Description { get; set; } = "";
    public string IssueType { get; set; } = "";
    public string Priority { get; set; } = "";
    public string Assignee { get; set; } = "";
    public string Reporter { get; set; } = "";
    public string ParentKey { get; set; } = "";
    public string ParentSummary { get; set; } = "";
    public int OriginalEstimateSec { get; set; }
    public int RemainingSec { get; set; }
    public int SpentSec { get; set; }
    public string Created { get; set; } = "";
    public string Updated { get; set; } = "";
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
