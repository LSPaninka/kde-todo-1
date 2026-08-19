using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using WorklogCalendar.Models;
using WorklogCalendar.Services;

namespace WorklogCalendar.Views;

public sealed partial class SettingsDialog : ContentDialog
{
    private readonly AppSettings _s;

    public SettingsDialog(AppSettings s)
    {
        this.InitializeComponent();
        _s = s;

        ViewModeChooser.SelectedIndex = _s.ViewMode == "24h" ? 1 : 0;
        SourceChooser.SelectedIndex = _s.Source switch
        {
            "clockify" => 2,
            "jira-clockify" => 1,
            _ => 0
        };
        FirstDayChooser.SelectedIndex = _s.FirstDayOfWeek == 1 ? 1 : 0;
        DailyTarget.Value = _s.DailyTargetHours;
        WinWidth.Value = _s.WindowWidth;
        WinHeight.Value = _s.WindowHeight;
        AlwaysOnTop.IsChecked = _s.AlwaysOnTop;
        ModalW.Value = _s.ModalWidth;
        ModalH.Value = _s.ModalHeight;

        ShowGauges.IsChecked = _s.ShowSprintGauges;
        ShowRingsView.IsChecked = _s.ShowRingsView;
        ShowSubtaskTable.IsChecked = _s.ShowSubtaskTable;
        SubtaskShowParent.IsChecked = _s.SubtaskShowParent;
        SubtaskJql.Text = _s.SubtaskJql;
        SprintStrategyChooser.SelectedIndex = _s.SprintStrategy switch
        {
            "agile-board" => 1,
            "assignee-jql" => 2,
            _ => 0
        };
        SprintField.Text = _s.SprintField;
        SprintBoardId.Value = _s.SprintBoardId;
        RemainingChooser.SelectedIndex = _s.RemainingMode == "calculated" ? 1 : 0;

        JiraSite.Text = _s.JiraSite;
        JiraEmail.Text = _s.JiraEmail;
        JiraToken.Password = _s.JiraToken;
        JiraJql.Text = _s.JiraIssueJql;
        JiraIssueMax.Value = _s.JiraIssueMax;
        JiraShowSummary.IsChecked = _s.ShowJiraSummary;
        JiraDebug.IsChecked = _s.JiraDebug;
        Jira1Color.Text = _s.Jira1BlockColor;

        Jira2Enabled.IsChecked = _s.Jira2Enabled;
        Jira2Site.Text = _s.Jira2Site;
        Jira2Email.Text = _s.Jira2Email;
        Jira2Token.Password = _s.Jira2Token;
        Jira2Color.Text = _s.Jira2BlockColor;

        ClockifyKey.Password = _s.ClockifyApiKey;
        ClockifyWorkspace.Text = _s.ClockifyWorkspaceId;
        ClockifyDefaultProject.Text = _s.ClockifyDefaultProjectId;
        ClockifyBillable.IsChecked = _s.ClockifyBillableDefault;
        ClockifyDebug.IsChecked = _s.ClockifyDebug;

        GoogleEnabled.IsChecked = _s.GoogleCalEnabled;
        GoogleClientId.Text = _s.GoogleClientId;
        GoogleClientSecret.Password = _s.GoogleClientSecret;
        GoogleRefreshToken.Password = _s.GoogleRefreshToken;
        GoogleDebug.IsChecked = _s.GoogleCalDebug;
        GoogleCal1Color.Text = ColorAt(0, "#e74c3c");
        GoogleCal2Color.Text = ColorAt(1, "#3498db");
        GoogleCal3Color.Text = ColorAt(2, "#9b59b6");

        LoadProjectsBtn.Click += async (sender, e) => await LoadClockifyProjects();
        GoogleAuthBtn.Click += async (sender, e) => await RunGoogleDeviceAuth();
        GoogleAuthCancelBtn.Click += (sender, e) => _googleAuthCts?.Cancel();
        GoogleLoadCalsBtn.Click += async (sender, e) => await LoadGoogleCalendars();

        // Pre-fill the pickers with whatever is cached in the live stores so
        // the dialog is useful before the user clicks the load buttons.
        SeedClockifyProjects();
        SeedGoogleCalendars();

        this.PrimaryButtonClick += (sender, e) => Persist();
        this.Closed += (sender, e) => _googleAuthCts?.Cancel();
    }

    private string ColorAt(int i, string fallback)
    {
        var cols = _s.GoogleCalendarColors;
        if (cols != null && i < cols.Count && !string.IsNullOrWhiteSpace(cols[i])) return cols[i].Trim();
        return fallback;
    }

    private string CalIdAt(int i)
    {
        var ids = _s.GoogleCalendarIds;
        return (ids != null && i < ids.Count) ? (ids[i] ?? "").Trim() : "";
    }

    // ---- Clockify project pickers -----------------------------------------

    private void SeedClockifyProjects()
    {
        var store = App.Clockify;
        if (store == null || store.Projects.Count == 0) return;
        FillProjectCombos(new List<ClockifyProject>(store.Projects));
    }

    private void FillProjectCombos(List<ClockifyProject> projects)
    {
        var list = new List<ClockifyProject> { new() { Id = "", Name = "(sin proyecto)" } };
        list.AddRange(projects);
        Jira1ProjectCombo.ItemsSource = list;
        Jira2ProjectCombo.ItemsSource = new List<ClockifyProject>(list);
        Jira1ProjectCombo.SelectedIndex = IndexOfProject(list, _s.Jira1ClockifyProjectId);
        Jira2ProjectCombo.SelectedIndex = IndexOfProject(list, _s.Jira2ClockifyProjectId);
    }

    private static int IndexOfProject(List<ClockifyProject> list, string? id)
    {
        for (int i = 0; i < list.Count; i++) if (list[i].Id == (id ?? "")) return i;
        return 0;
    }

    private async Task LoadClockifyProjects()
    {
        var store = App.Clockify;
        if (store == null) { ProjectsStatus.Text = "Clockify no inicializado."; return; }
        // Persist the key first so EnsureContext uses whatever was just typed.
        _s.ClockifyApiKey = ClockifyKey.Password ?? "";
        _s.ClockifyWorkspaceId = (ClockifyWorkspace.Text ?? "").Trim();
        SettingsService.Save(_s);

        LoadProjectsBtn.IsEnabled = false;
        ProjectsStatus.Text = "Cargando proyectos…";
        try
        {
            bool ok = await store.EnsureContextAsync();
            if (!ok) { ProjectsStatus.Text = "No se pudo conectar: " + store.LastError; return; }
            FillProjectCombos(new List<ClockifyProject>(store.Projects));
            ProjectsStatus.Text = $"{store.Projects.Count} proyecto(s) cargado(s).";
        }
        finally { LoadProjectsBtn.IsEnabled = true; }
    }

    // ---- Google device-code auth ------------------------------------------

    private CancellationTokenSource? _googleAuthCts;

    private async Task RunGoogleDeviceAuth()
    {
        var store = App.Google;
        if (store == null) { GoogleAuthStatus.Text = "Google no inicializado."; return; }
        var id = (GoogleClientId.Text ?? "").Trim();
        var secret = GoogleClientSecret.Password ?? "";
        if (id.Length == 0 || secret.Length == 0)
        {
            GoogleAuthStatus.Text = "Completá Client ID y Client secret primero.";
            return;
        }

        GoogleAuthBtn.IsEnabled = false;
        GoogleAuthCancelBtn.IsEnabled = true;
        GoogleAuthStatus.Text = "Solicitando código de dispositivo…";
        _googleAuthCts = new CancellationTokenSource();
        try
        {
            var (info, err) = await store.StartDeviceAuthAsync(id);
            if (info == null) { GoogleAuthStatus.Text = err; return; }

            GoogleUserCode.Text = info.UserCode;
            GoogleVerifUrl.Text = info.VerificationUrl;
            GoogleCodeBox.Visibility = Visibility.Visible;
            GoogleAuthStatus.Text = "Abrí la página de Google, ingresá el código y aprobá. Esperando…";
            try { await Windows.System.Launcher.LaunchUriAsync(new Uri(info.VerificationUrl)); }
            catch { /* the code is on screen either way */ }

            var (refresh, perr) = await store.PollForRefreshTokenAsync(id, secret, info, _googleAuthCts.Token);
            if (!string.IsNullOrEmpty(refresh))
            {
                GoogleRefreshToken.Password = refresh;
                // Persist right away so "Cargar calendarios" works without
                // having to save + reopen the dialog first.
                _s.GoogleClientId = id;
                _s.GoogleClientSecret = secret;
                _s.GoogleRefreshToken = refresh;
                SettingsService.Save(_s);
                GoogleAuthStatus.Text = "¡Listo! Google Calendar autorizado. Cargá tus calendarios abajo.";
            }
            else if (!string.IsNullOrEmpty(perr)) GoogleAuthStatus.Text = perr;
            else GoogleAuthStatus.Text = "Autorización cancelada.";
        }
        finally
        {
            GoogleCodeBox.Visibility = Visibility.Collapsed;
            GoogleAuthBtn.IsEnabled = true;
            GoogleAuthCancelBtn.IsEnabled = false;
            _googleAuthCts?.Dispose();
            _googleAuthCts = null;
        }
    }

    private void SeedGoogleCalendars()
    {
        // Show the saved ids even before a fetch, so the selection isn't lost
        // when the user opens the dialog without hitting "Cargar calendarios".
        var seeded = new List<GoogleCalendarInfo>();
        for (int i = 0; i < 3; i++)
        {
            var id = CalIdAt(i);
            if (id.Length > 0 && !seeded.Exists(c => c.Id == id))
                seeded.Add(new GoogleCalendarInfo { Id = id, Label = id });
        }
        if (seeded.Count > 0) FillCalendarCombos(seeded);
    }

    private void FillCalendarCombos(List<GoogleCalendarInfo> cals)
    {
        var list = new List<GoogleCalendarInfo> { new() { Id = "", Label = "(ninguno)" } };
        list.AddRange(cals);
        GoogleCal1.ItemsSource = list;
        GoogleCal2.ItemsSource = new List<GoogleCalendarInfo>(list);
        GoogleCal3.ItemsSource = new List<GoogleCalendarInfo>(list);
        GoogleCal1.SelectedIndex = IndexOfCal(list, CalIdAt(0));
        GoogleCal2.SelectedIndex = IndexOfCal(list, CalIdAt(1));
        GoogleCal3.SelectedIndex = IndexOfCal(list, CalIdAt(2));
    }

    private static int IndexOfCal(List<GoogleCalendarInfo> list, string id)
    {
        for (int i = 0; i < list.Count; i++) if (list[i].Id == id) return i;
        return 0;
    }

    private async Task LoadGoogleCalendars()
    {
        var store = App.Google;
        if (store == null) { GoogleCalStatus.Text = "Google no inicializado."; return; }
        // Persist creds first so EnsureAccessToken sees the typed values.
        _s.GoogleClientId = (GoogleClientId.Text ?? "").Trim();
        _s.GoogleClientSecret = GoogleClientSecret.Password ?? "";
        _s.GoogleRefreshToken = GoogleRefreshToken.Password ?? "";
        SettingsService.Save(_s);

        GoogleLoadCalsBtn.IsEnabled = false;
        GoogleCalStatus.Text = "Cargando calendarios…";
        try
        {
            var (cals, err) = await store.FetchCalendarListAsync();
            if (!string.IsNullOrEmpty(err)) { GoogleCalStatus.Text = err; return; }
            FillCalendarCombos(cals);
            GoogleCalStatus.Text = $"{cals.Count} calendario(s) encontrado(s).";
        }
        finally { GoogleLoadCalsBtn.IsEnabled = true; }
    }

    private void Persist()
    {
        _s.ViewMode = ViewModeChooser.SelectedIndex == 1 ? "24h" : "9h";
        _s.Source = SourceChooser.SelectedIndex switch
        {
            2 => "clockify",
            1 => "jira-clockify",
            _ => "jira"
        };
        _s.FirstDayOfWeek = FirstDayChooser.SelectedIndex == 1 ? 1 : 0;
        _s.DailyTargetHours = DailyTarget.Value;
        _s.WindowWidth = (int)WinWidth.Value;
        _s.WindowHeight = (int)WinHeight.Value;
        _s.AlwaysOnTop = AlwaysOnTop.IsChecked == true;
        _s.ModalWidth = (int)ModalW.Value;
        _s.ModalHeight = (int)ModalH.Value;

        _s.ShowSprintGauges = ShowGauges.IsChecked == true;
        _s.ShowRingsView = ShowRingsView.IsChecked == true;
        _s.ShowSubtaskTable = ShowSubtaskTable.IsChecked == true;
        _s.SubtaskShowParent = SubtaskShowParent.IsChecked == true;
        _s.SubtaskJql = SubtaskJql.Text ?? "";
        _s.SprintStrategy = SprintStrategyChooser.SelectedIndex switch
        {
            1 => "agile-board",
            2 => "assignee-jql",
            _ => "subtask-customfield"
        };
        _s.SprintField = (SprintField.Text ?? "").Trim();
        _s.SprintBoardId = (int)SprintBoardId.Value;
        _s.RemainingMode = RemainingChooser.SelectedIndex == 1 ? "calculated" : "api";

        _s.JiraSite = (JiraSite.Text ?? "").Trim();
        _s.JiraEmail = (JiraEmail.Text ?? "").Trim();
        _s.JiraToken = JiraToken.Password ?? "";
        _s.JiraIssueJql = JiraJql.Text ?? "";
        _s.JiraIssueMax = (int)JiraIssueMax.Value;
        _s.ShowJiraSummary = JiraShowSummary.IsChecked == true;
        _s.JiraDebug = JiraDebug.IsChecked == true;

        _s.Jira1BlockColor = NormalizeHex(Jira1Color.Text, "#9b91e6");

        _s.Jira2Enabled = Jira2Enabled.IsChecked == true;
        _s.Jira2Site = (Jira2Site.Text ?? "").Trim();
        _s.Jira2Email = (Jira2Email.Text ?? "").Trim();
        _s.Jira2Token = Jira2Token.Password ?? "";
        _s.Jira2BlockColor = NormalizeHex(Jira2Color.Text, "#26a69a");

        _s.ClockifyApiKey = ClockifyKey.Password ?? "";
        _s.ClockifyWorkspaceId = (ClockifyWorkspace.Text ?? "").Trim();
        _s.ClockifyDefaultProjectId = (ClockifyDefaultProject.Text ?? "").Trim();
        _s.ClockifyBillableDefault = ClockifyBillable.IsChecked == true;
        _s.ClockifyDebug = ClockifyDebug.IsChecked == true;
        _s.Jira1ClockifyProjectId = (Jira1ProjectCombo.SelectedItem as ClockifyProject)?.Id ?? _s.Jira1ClockifyProjectId;
        _s.Jira2ClockifyProjectId = (Jira2ProjectCombo.SelectedItem as ClockifyProject)?.Id ?? _s.Jira2ClockifyProjectId;

        _s.GoogleCalEnabled = GoogleEnabled.IsChecked == true;
        _s.GoogleClientId = (GoogleClientId.Text ?? "").Trim();
        _s.GoogleClientSecret = GoogleClientSecret.Password ?? "";
        _s.GoogleRefreshToken = GoogleRefreshToken.Password ?? "";
        _s.GoogleCalDebug = GoogleDebug.IsChecked == true;

        // Keep the id + colour lists parallel: only rows with a real
        // calendar selected are stored, so index i of both lists always
        // describes the same calendar.
        var ids = new List<string>();
        var cols = new List<string>();
        void AddRow(ComboBox combo, TextBox colorBox, string fallback)
        {
            var id = (combo.SelectedItem as GoogleCalendarInfo)?.Id ?? "";
            if (string.IsNullOrWhiteSpace(id)) return;
            ids.Add(id.Trim());
            cols.Add(NormalizeHex(colorBox.Text, fallback));
        }
        AddRow(GoogleCal1, GoogleCal1Color, "#e74c3c");
        AddRow(GoogleCal2, GoogleCal2Color, "#3498db");
        AddRow(GoogleCal3, GoogleCal3Color, "#9b59b6");
        _s.GoogleCalendarIds = ids;
        _s.GoogleCalendarColors = cols;

        SettingsService.Save(_s);
    }

    /// <summary>Accept "#rrggbb" or "rrggbb"; anything else falls back.</summary>
    private static string NormalizeHex(string? raw, string fallback)
    {
        var h = (raw ?? "").Trim();
        if (h.Length == 6 && !h.StartsWith("#")) h = "#" + h;
        if (h.Length != 7 || h[0] != '#') return fallback;
        for (int i = 1; i < 7; i++)
            if (!Uri.IsHexDigit(h[i])) return fallback;
        return h.ToLowerInvariant();
    }
}
