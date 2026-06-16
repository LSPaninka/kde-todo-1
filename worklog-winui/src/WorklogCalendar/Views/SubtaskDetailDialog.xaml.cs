using System;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.System;
using Windows.UI;
using WorklogCalendar.Models;
using WorklogCalendar.Services;

namespace WorklogCalendar.Views;

/// <summary>
/// Read-only modal showing the relevant info of a Jira subtask plus an
/// "Abrir en Jira" primary button. Seeds itself with the row data so the
/// modal isn't blank while FetchIssueDetailAsync is in flight; replaces
/// the seed with the enriched payload on completion.
/// </summary>
public sealed partial class SubtaskDetailDialog : ContentDialog
{
    private readonly JiraWorklogStore _store;
    private string _key = "";

    public SubtaskDetailDialog(JiraWorklogStore store, AppSettings settings, JiraSubtask seed)
    {
        this.InitializeComponent();
        _store = store;
        const int margin = 80;
        BodyGrid.Width = Math.Clamp(settings.ModalWidth, 360, Math.Max(360, settings.WindowWidth - margin));
        BodyGrid.Height = Math.Clamp(settings.ModalHeight, 280, Math.Max(280, settings.WindowHeight - margin));

        // Seed display from the row so the dialog isn't blank.
        ApplyDetail(new JiraIssueDetail
        {
            Key = seed.Key,
            Summary = seed.Summary,
            Status = seed.Status,
            StatusColor = seed.StatusColor,
            ParentKey = seed.ParentKey,
            ParentSummary = seed.ParentSummary,
            RemainingSec = seed.RemainingSec
        });

        PrimaryButtonClick += (s, e) =>
        {
            var url = _store.IssueWebUrl(_key);
            if (!string.IsNullOrEmpty(url)) _ = Launcher.LaunchUriAsync(new Uri(url));
        };

        Loaded += async (s, e) => await LoadDetailAsync(seed.Key);
    }

    private async System.Threading.Tasks.Task LoadDetailAsync(string key)
    {
        Busy.IsActive = true;
        try
        {
            var d = await _store.FetchIssueDetailAsync(key);
            if (d != null) ApplyDetail(d);
            else { ErrorText.Text = "No se pudo cargar el detalle."; ErrorText.Visibility = Visibility.Visible; }
        }
        finally { Busy.IsActive = false; }
    }

    private void ApplyDetail(JiraIssueDetail d)
    {
        _key = d.Key;
        KeyText.Text = string.IsNullOrEmpty(d.Key) ? "" : $"[{d.Key}]";
        SummaryText.Text = d.Summary ?? "";

        if (!string.IsNullOrEmpty(d.Status))
        {
            StatusBadge.Visibility = Visibility.Visible;
            StatusBadge.Background = new SolidColorBrush(StatusBg(d.StatusColor));
            StatusText.Text = d.Status;
        }
        else StatusBadge.Visibility = Visibility.Collapsed;

        TypeText.Text = string.IsNullOrEmpty(d.IssueType) ? "—" : d.IssueType;
        PriorityText.Text = string.IsNullOrEmpty(d.Priority) ? "—" : d.Priority;
        AssigneeText.Text = string.IsNullOrEmpty(d.Assignee) ? "—" : d.Assignee;

        bool hasParent = !string.IsNullOrEmpty(d.ParentKey);
        ParentLabel.Visibility = hasParent ? Visibility.Visible : Visibility.Collapsed;
        ParentText.Visibility = hasParent ? Visibility.Visible : Visibility.Collapsed;
        ParentText.Text = hasParent
            ? d.ParentKey + (string.IsNullOrEmpty(d.ParentSummary) ? "" : "  —  " + d.ParentSummary)
            : "";

        OrigText.Text = FmtHours(d.OriginalEstimateSec);
        SpentText.Text = FmtHours(d.SpentSec);
        RemText.Text = FmtHours(d.RemainingSec);

        DescBox.Text = d.Description ?? "";
        DescBox.PlaceholderText = string.IsNullOrEmpty(d.Description) ? "(sin descripción)" : "";

        if (!string.IsNullOrEmpty(d.Created) || !string.IsNullOrEmpty(d.Updated))
        {
            StampsText.Text = $"Creada: {FmtDate(d.Created)}    Actualizada: {FmtDate(d.Updated)}";
            StampsText.Visibility = Visibility.Visible;
        }
        else StampsText.Visibility = Visibility.Collapsed;

        IsPrimaryButtonEnabled = !string.IsNullOrEmpty(d.Key);
    }

    private static string FmtHours(int sec)
    {
        if (sec <= 0) return "—";
        int h = sec / 3600, m = (sec % 3600) / 60;
        if (h > 0 && m > 0) return $"{h}h {m}m";
        if (h > 0) return $"{h}h";
        return $"{m}m";
    }

    private static string FmtDate(string iso)
    {
        if (string.IsNullOrEmpty(iso)) return "";
        if (DateTimeOffset.TryParse(iso, out var d))
            return d.LocalDateTime.ToString("yyyy-MM-dd HH:mm");
        return iso;
    }

    private static Color StatusBg(string? colorName) => (colorName ?? "").ToLowerInvariant() switch
    {
        "green" => Color.FromArgb(0xD9, 0x81, 0xC7, 0x84),
        "yellow" => Color.FromArgb(0xD9, 0xF1, 0xC4, 0x0F),
        "blue-gray" => Color.FromArgb(0xD9, 0x78, 0x90, 0x9C),
        "warm-red" => Color.FromArgb(0xD9, 0xE7, 0x4C, 0x3C),
        "medium-gray" => Color.FromArgb(0xD9, 0x9E, 0x9E, 0x9E),
        _ => Color.FromArgb(0xA6, 0x78, 0x90, 0x9C),
    };
}
