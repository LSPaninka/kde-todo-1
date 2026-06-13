using System;
using System.Collections.Generic;
using System.ComponentModel;
using Microsoft.UI;
using Microsoft.UI.Xaml.Controls;
using Windows.UI;
using WorklogCalendar.Services;

namespace WorklogCalendar.Controls;

/// <summary>
/// Twin-ring sprint widget. Port of <c>SprintGauges.qml</c>:
///   left  = % of time elapsed in the active Jira sprint
///   right = % of (consumed / (available + consumed)) hours logged
///           in the sprint by the current user.
/// </summary>
public sealed partial class SprintGaugesControl : UserControl
{
    private JiraWorklogStore? _store;

    public SprintGaugesControl()
    {
        this.InitializeComponent();
        Refresh();
    }

    public JiraWorklogStore? Store
    {
        get => _store;
        set
        {
            if (_store != null) _store.PropertyChanged -= OnStoreChanged;
            _store = value;
            if (_store != null) _store.PropertyChanged += OnStoreChanged;
            Refresh();
        }
    }

    public void StartFillAnimation()
    {
        SprintRing.StartFill();
        HoursRing.StartFill();
    }

    private void OnStoreChanged(object? s, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(JiraWorklogStore.CurrentSprint)
            or nameof(JiraWorklogStore.SprintAvailableSec)
            or nameof(JiraWorklogStore.SprintConsumedSec)
            or nameof(JiraWorklogStore.SprintAvailableBreakdown))
        {
            // We were probably called from the UI thread; if not, the
            // SetValue calls below will still work because UI properties
            // marshal automatically — but to be safe queue on the dispatcher.
            DispatcherQueue.TryEnqueue(Refresh);
        }
    }

    private void Refresh()
    {
        var sprint = _store?.CurrentSprint;
        double sprintPct = ComputeSprintPct(sprint);
        double hoursPct = ComputeHoursPct(_store);

        SprintRing.Value = sprintPct;
        SprintRing.BaseColor = SprintColor(sprintPct);
        SprintLegend.Text = sprint != null
            ? $"Inicio: {FormatDate(sprint.StartDate)}\nFin: {FormatDate(sprint.EndDate)}"
            : "Sin sprint activo";

        HoursRing.Value = hoursPct;
        HoursRing.BaseColor = HoursBase(hoursPct);
        HoursRing.Intermittent = sprintPct >= 85 && hoursPct < 99;
        DisponibleLegend.Text = _store != null ? $"Disponible: {FormatHours(_store.SprintAvailableSec)}" : "";
        QuemadasLegend.Text = _store != null ? $"Quemadas: {FormatHours(_store.SprintConsumedSec)}" : "";

        // Per-issue breakdown tooltip on the "Disponible" line. Cleared if
        // there's nothing to show.
        var breakdown = _store?.SprintAvailableBreakdown;
        if (breakdown != null && breakdown.Count > 0)
        {
            var lines = new List<string>();
            int max = Math.Min(breakdown.Count, 20);
            for (int i = 0; i < max; i++)
                lines.Add($"{breakdown[i].Key}: {FormatHours(breakdown[i].RemainingSec)}");
            if (breakdown.Count > max) lines.Add($"…y {breakdown.Count - max} más");
            ToolTipService.SetToolTip(DisponibleLegend, new ToolTip
            {
                Content = new TextBlock { Text = string.Join("\n", lines), FontSize = 11 }
            });
        }
        else
        {
            ToolTipService.SetToolTip(DisponibleLegend, null);
        }
    }

    private static double ComputeSprintPct(Models.JiraSprint? s)
    {
        if (s == null) return 0;
        if (!DateTimeOffset.TryParse(s.StartDate, out var start) || !DateTimeOffset.TryParse(s.EndDate, out var end)) return 0;
        var now = DateTimeOffset.UtcNow;
        if (end <= start) return 0;
        if (now <= start) return 0;
        if (now >= end) return 100;
        return (now - start).TotalMilliseconds / (end - start).TotalMilliseconds * 100;
    }

    private static double ComputeHoursPct(JiraWorklogStore? store)
    {
        if (store == null) return 0;
        long avail = store.SprintAvailableSec;
        long consumed = store.SprintConsumedSec;
        long total = avail + consumed;
        if (total <= 0) return 0;
        return Math.Max(0, Math.Min(100, (double)consumed / total * 100));
    }

    private static Color SprintColor(double pct)
    {
        if (pct >= 100) return Color.FromArgb(0xFF, 0xB7, 0x1C, 0x1C); // dark red
        if (pct >= 90) return Color.FromArgb(0xFF, 0xE5, 0x39, 0x35);  // red
        if (pct >= 85) return Color.FromArgb(0xFF, 0xFB, 0x8C, 0x00);  // orange
        if (pct >= 75) return Color.FromArgb(0xFF, 0xFB, 0xC0, 0x2D);  // yellow
        return Color.FromArgb(0xFF, 0x29, 0xB6, 0xF6);                  // celeste
    }
    private static Color HoursBase(double pct) =>
        pct >= 100 ? Color.FromArgb(0xFF, 0x4C, 0xAF, 0x50) : Color.FromArgb(0xFF, 0x81, 0xC7, 0x84);

    private static string FormatDate(string iso)
    {
        if (string.IsNullOrEmpty(iso)) return "-";
        if (!DateTimeOffset.TryParse(iso, out var d)) return "-";
        return $"{d.Day}/{d.Month}";
    }
    private static string FormatHours(int sec)
    {
        if (sec <= 0) return "0h";
        int h = sec / 3600, m = (sec % 3600) / 60;
        if (h > 0 && m > 0) return $"{h}h {m}m";
        if (h > 0) return $"{h}h";
        return $"{m}m";
    }
}
