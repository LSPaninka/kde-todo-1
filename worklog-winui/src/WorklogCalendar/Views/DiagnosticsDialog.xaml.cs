using Microsoft.UI.Xaml.Controls;
using WorklogCalendar.Services;

namespace WorklogCalendar.Views;

public sealed partial class DiagnosticsDialog : ContentDialog
{
    private readonly JiraWorklogStore _jira;
    private readonly JiraWorklogStore? _jira2;
    private readonly ClockifyStore _clockify;
    private readonly GoogleCalendarStore? _google;

    public DiagnosticsDialog(JiraWorklogStore jira, ClockifyStore clockify,
                             JiraWorklogStore? jira2 = null, GoogleCalendarStore? google = null)
    {
        this.InitializeComponent();
        _jira = jira;
        _jira2 = jira2;
        _clockify = clockify;
        _google = google;
        Refresh();
        SecondaryButtonClick += (s, e) =>
        {
            e.Cancel = true; // don't close
            _jira.ClearDebugLog();
            _jira2?.ClearDebugLog();
            _clockify.ClearDebugLog();
            _google?.ClearDebugLog();
            Refresh();
        };
    }

    private void Refresh()
    {
        var j = _jira.HasDebugLog ? _jira.DebugLog : "(vacío)";
        var j2 = (_jira2?.HasDebugLog ?? false) ? _jira2!.DebugLog : "(vacío)";
        var c = _clockify.HasDebugLog ? _clockify.DebugLog : "(vacío)";
        var g = (_google?.HasDebugLog ?? false) ? _google!.DebugLog : "(vacío)";
        bool any = _jira.HasDebugLog || (_jira2?.HasDebugLog ?? false)
                   || _clockify.HasDebugLog || (_google?.HasDebugLog ?? false);
        LogBox.Text = any
            ? $"---- JIRA ----\n{j}\n\n---- JIRA 2 ----\n{j2}\n\n---- CLOCKIFY ----\n{c}\n\n---- GOOGLE ----\n{g}"
            : "Sin datos. Pulsá Sincronizar para empezar.";
    }
}
