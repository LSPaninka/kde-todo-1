using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.Graphics;
using Windows.UI;
using WinRT.Interop;
using WorklogCalendar.Models;
using WorklogCalendar.Services;

namespace WorklogCalendar.Views;

/// <summary>
/// Control-Center-style fly-out that hosts the same calendar + ring
/// gauges as the main window, but trimmed: no mode selector, no
/// settings, no diagnostics. The "Abrir app" button hands off to the
/// main window when the user wants the full toolbar (mode picker,
/// view-mode toggle, configuration, etc.).
///
/// Auto-hides when it loses focus. Skips the auto-hide while an edit
/// dialog is open so clicking an entry doesn't dismiss the popup.
/// </summary>
public sealed partial class TrayPopupWindow : Window
{
    private const int DesiredWidth = 1000;
    private const int DesiredHeight = 700;

    public Action? OpenMainRequested;
    public Action? HideRequested;

    private readonly AppSettings _settings;
    private readonly JiraWorklogStore _jira;
    private readonly JiraWorklogStore _jira2;
    private readonly ClockifyStore _clockify;
    private readonly GoogleCalendarStore? _google;
    private DateTime _weekStart;
    private int _dialogDepth;     // skip auto-hide while > 0
    private CancellationTokenSource? _statusCts;
    private bool _statusOverrideActive;

    public TrayPopupWindow(AppSettings settings, JiraWorklogStore jira, ClockifyStore clockify,
                           JiraWorklogStore? jira2 = null, GoogleCalendarStore? google = null)
    {
        this.InitializeComponent();
        _settings = settings;
        _jira = jira;
        _jira2 = jira2 ?? new JiraWorklogStore(settings, 2);
        _clockify = clockify;
        _google = google;

        // ---- Frame-less window setup ----
        var hwnd = WindowNative.GetWindowHandle(this);
        var wid = Win32Interop.GetWindowIdFromWindow(hwnd);
        var aw = AppWindow.GetFromWindowId(wid);
        if (aw != null)
        {
            if (aw.Presenter is OverlappedPresenter op)
            {
                op.IsResizable = false;
                op.IsMaximizable = false;
                op.IsMinimizable = false;
                op.SetBorderAndTitleBar(false, false);
                op.IsAlwaysOnTop = true;
            }
            aw.IsShownInSwitchers = false;
        }
        TrySetMicaBackdrop();

        // ---- Wire calendar + gauges to the App-level stores ----
        Calendar.Settings = _settings;
        Calendar.JiraStore = _jira;
        Calendar.Jira2Store = _jira2;
        Calendar.ClockifyStore = _clockify;
        Calendar.GoogleStore = _google;
        Gauges.Store = _jira;

        _weekStart = WeekStartOf(DateTime.Today);
        Calendar.WeekStart = _weekStart;

        // Calendar interactions reuse the same handlers as MainWindow.
        Calendar.CreateJiraRequested += (dayMs, sMs, eMs) => _ = OpenJiraEditAsync(null, sMs, eMs);
        Calendar.EditJiraRequested += w => _ = OpenJiraEditAsync(w, w.StartedUnixMs, w.StartedUnixMs + w.DurationSec * 1000L, 1);
        Calendar.EditJira2Requested += w => _ = OpenJiraEditAsync(w, w.StartedUnixMs, w.StartedUnixMs + w.DurationSec * 1000L, 2);
        Calendar.CreateClockifyRequested += (dayMs, sMs, eMs) => _ = OpenClockifyEditAsync(null, sMs, eMs);
        Calendar.EditClockifyRequested += c => _ = OpenClockifyEditAsync(c, c.StartedUnixMs, c.StartedUnixMs + c.DurationSec * 1000L);
        Calendar.MoveJiraRequested += (w, newStart, newDur) => _ = MoveJiraAsync(_jira, w, newStart, newDur);
        Calendar.MoveJira2Requested += (w, newStart, newDur) => _ = MoveJiraAsync(_jira2, w, newStart, newDur);
        Calendar.MoveClockifyRequested += (c, newStart, newDur) => _ = MoveClockifyAsync(c, newStart, newDur);
        Calendar.DuplicateJiraRequested += w => _ = DuplicateJiraAsync(_jira, w);
        Calendar.DuplicateJira2Requested += w => _ = DuplicateJiraAsync(_jira2, w);
        Calendar.DuplicateClockifyRequested += c => _ = DuplicateClockifyAsync(c);

        // Store change notifications.
        _jira.PropertyChanged += OnStoreChanged;
        _clockify.PropertyChanged += OnStoreChanged;

        // ---- Header buttons ----
        PrevBtn.Click += async (s, e) => { _weekStart = _weekStart.AddDays(-7); await RefreshAsync(); };
        NextBtn.Click += async (s, e) => { _weekStart = _weekStart.AddDays(7); await RefreshAsync(); };
        TodayBtn.Click += async (s, e) => { _weekStart = WeekStartOf(DateTime.Today); await RefreshAsync(); };
        RefreshBtn.Click += async (s, e) => await RefreshAsync();
        OpenMainBtn.Click += (s, e) =>
        {
            OpenMainRequested?.Invoke();
            HideRequested?.Invoke();
        };
        SyncJiraToClockifyBtn.Click += async (s, e) => await SyncJiraToClockify();

        // Auto-hide on focus loss, except while a dialog is open.
        this.Activated += (s, e) =>
        {
            if (e.WindowActivationState != WindowActivationState.Deactivated) return;
            if (_dialogDepth > 0) return;
            HideRequested?.Invoke();
        };

        UpdateHeaderLabels();
        UpdateTotals();

        // First fetch after the visual tree is up.
        DispatcherQueue.TryEnqueue(() => { _ = RefreshAsync(); });
    }

    // -------- Backdrop / animation -------------------------------------

    private void TrySetMicaBackdrop()
    {
        if (MicaController.IsSupported())
        {
            try { this.SystemBackdrop = new MicaBackdrop { Kind = MicaKind.BaseAlt }; return; }
            catch { /* fall through */ }
        }
        Root.Background = new SolidColorBrush(Color.FromArgb(0xF2, 0x1F, 0x1F, 0x1F));
    }

    /// <summary>Position near the bottom-right (above the tray) and animate in.</summary>
    public void ShowNearTray()
    {
        var hwnd = WindowNative.GetWindowHandle(this);
        var wid = Win32Interop.GetWindowIdFromWindow(hwnd);
        var aw = AppWindow.GetFromWindowId(wid);
        if (aw != null)
        {
            var da = DisplayArea.GetFromWindowId(wid, DisplayAreaFallback.Primary);
            var work = da.WorkArea;
            const int margin = 12;
            // Clamp the size so we don't overflow a small screen.
            int w = Math.Min(DesiredWidth, Math.Max(720, work.Width - margin * 2));
            int h = Math.Min(DesiredHeight, Math.Max(520, work.Height - margin * 2));
            int x = work.X + work.Width - w - margin;
            int y = work.Y + work.Height - h - margin;
            aw.MoveAndResize(new RectInt32(x, y, w, h));
        }

        this.Activate();
        Calendar.Refresh();
        AnimateSlideIn();
    }

    private void AnimateSlideIn()
    {
        Root.Opacity = 0;
        RootTransform.TranslateY = 24;

        var sb = new Storyboard();
        var fade = new DoubleAnimation
        {
            From = 0, To = 1,
            Duration = TimeSpan.FromMilliseconds(180),
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
        };
        Storyboard.SetTarget(fade, Root);
        Storyboard.SetTargetProperty(fade, "Opacity");
        sb.Children.Add(fade);

        var slide = new DoubleAnimation
        {
            From = 24, To = 0,
            Duration = TimeSpan.FromMilliseconds(240),
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
        };
        Storyboard.SetTarget(slide, RootTransform);
        Storyboard.SetTargetProperty(slide, "TranslateY");
        sb.Children.Add(slide);

        sb.Begin();
    }

    // -------- Refresh / fetch -----------------------------------------

    private async Task RefreshAsync()
    {
        UpdateHeaderLabels();
        Calendar.WeekStart = _weekStart;
        Calendar.Refresh();
        var tasks = new List<Task>();
        if (Calendar.ShowJira) tasks.Add(_jira.FetchWeekAsync(_weekStart));
        if (Calendar.ShowJira2) tasks.Add(_jira2.FetchWeekAsync(_weekStart));
        if (Calendar.ShowClockify) tasks.Add(_clockify.FetchWeekAsync(_weekStart));
        if (Calendar.ShowGoogle && _google != null) tasks.Add(_google.FetchWeekAsync(_weekStart));
        if (ShowGauges) tasks.Add(_jira.FetchSprintInfoAsync());
        try { await Task.WhenAll(tasks); }
        catch (Exception ex) { System.Diagnostics.Debug.WriteLine("[Popup] refresh: " + ex); }
        if (ShowGauges) Gauges.StartFillAnimation();
    }

    private bool ShowGauges =>
        _settings.ShowSprintGauges
        && _settings.ViewMode == "9h"
        && (_settings.Source == "jira" || _settings.Source == "jira-clockify");

    private void OnStoreChanged(object? s, PropertyChangedEventArgs e)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            UpdateStatus();
            Calendar.Refresh();
            UpdateTotals();
        });
    }

    private void UpdateHeaderLabels()
    {
        TitleText.Text = _settings.Source switch
        {
            "clockify" => "Clockify",
            "jira-clockify" => "Jira / Clockify",
            _ => "Jira"
        };
        WeekLabel.Text = FormatWeekLabel(_weekStart);
        SyncJiraToClockifyBtn.Visibility = _settings.Source == "jira-clockify"
            ? Visibility.Visible : Visibility.Collapsed;
        Gauges.Visibility = ShowGauges ? Visibility.Visible : Visibility.Collapsed;
    }

    private void UpdateTotals()
    {
        var parts = new List<string>();
        if (Calendar.ShowJira)
        {
            int s = 0; foreach (var w in _jira.Worklogs) s += w.DurationSec;
            parts.Add($"Jira: {s / 3600}h {(s % 3600) / 60}m");
        }
        if (Calendar.ShowClockify)
        {
            int s = 0; foreach (var w in _clockify.Entries) s += w.DurationSec;
            parts.Add($"Clockify: {s / 3600}h {(s % 3600) / 60}m");
        }
        TotalsLabel.Text = string.Join("   ·   ", parts);
    }

    private void UpdateStatus()
    {
        if (_statusOverrideActive) return;
        var parts = new List<string>();
        if (_jira.Loading) parts.Add("Jira: cargando…");
        else if (!string.IsNullOrEmpty(_jira.LastError)) parts.Add($"Jira: {_jira.LastError}");
        if (_clockify.Loading) parts.Add("Clockify: cargando…");
        else if (!string.IsNullOrEmpty(_clockify.LastError)) parts.Add($"Clockify: {_clockify.LastError}");
        bool isError = !string.IsNullOrEmpty(_jira.LastError) || !string.IsNullOrEmpty(_clockify.LastError);
        ApplyStatus(string.Join("   ·   ", parts), isError);
    }

    private void SetStatus(string text, bool isError)
    {
        _statusOverrideActive = true;
        ApplyStatus(text, isError);
        _statusCts?.Cancel();
        _statusCts = new CancellationTokenSource();
        var ct = _statusCts.Token;
        _ = Task.Delay(6000, ct).ContinueWith(_ =>
        {
            if (ct.IsCancellationRequested) return;
            DispatcherQueue.TryEnqueue(() =>
            {
                _statusOverrideActive = false;
                UpdateStatus();
            });
        }, TaskScheduler.Default);
    }

    private void ApplyStatus(string text, bool isError)
    {
        if (string.IsNullOrEmpty(text))
        {
            StatusLabel.Text = " ";
            StatusLabel.Opacity = 0;
            return;
        }
        StatusLabel.Text = text;
        StatusLabel.Opacity = 0.85;
        StatusLabel.Foreground = isError
            ? new SolidColorBrush(Color.FromArgb(255, 234, 90, 84))
            : new SolidColorBrush(Color.FromArgb(255, 120, 200, 130));
    }

    // -------- Dialogs --------------------------------------------------

    private async Task OpenJiraEditAsync(JiraWorklog? existing, long startMs, long endMs, int instanceId = 1)
    {
        var s = DateTimeOffset.FromUnixTimeMilliseconds(startMs).LocalDateTime;
        var en = DateTimeOffset.FromUnixTimeMilliseconds(endMs).LocalDateTime;
        var store = instanceId == 2 ? _jira2 : _jira;
        bool allowSwitch = existing == null && _settings.Jira2Enabled;
        var dlg = new JiraEditDialog(store, _settings, s, en, existing,
                                     store2: _jira2, allowInstanceSwitch: allowSwitch)
            { XamlRoot = Content.XamlRoot };
        _dialogDepth++;
        try { await dlg.ShowAsync(); }
        finally { _dialogDepth--; }
        if (dlg.Mutated) await RefreshAsync();
    }

    private async Task OpenClockifyEditAsync(ClockifyEntry? existing, long startMs, long endMs)
    {
        var s = DateTimeOffset.FromUnixTimeMilliseconds(startMs).LocalDateTime;
        var en = DateTimeOffset.FromUnixTimeMilliseconds(endMs).LocalDateTime;
        var dlg = new ClockifyEditDialog(_clockify, _settings, s, en, existing) { XamlRoot = Content.XamlRoot };
        _dialogDepth++;
        try { await dlg.ShowAsync(); }
        finally { _dialogDepth--; }
        if (dlg.Mutated) await RefreshAsync();
    }

    // -------- Move / duplicate / sync ---------------------------------

    private async Task MoveJiraAsync(JiraWorklogStore store, JiraWorklog w, long newStartMs, int newDur)
    {
        SetStatus($"Actualizando worklog Jira {store.InstanceId}…", false);
        var start = DateTimeOffset.FromUnixTimeMilliseconds(newStartMs).LocalDateTime;
        var (ok, err) = await store.UpdateWorklogAsync(w.IssueKey, w.Id, start, newDur, w.Comment ?? "");
        if (ok) { store.UpdateLocalWorklog(w.Id, start, newDur); await RefreshAsync(); }
        else SetStatus($"Jira {store.InstanceId}: no se pudo guardar — {err}", true);
    }

    private async Task MoveClockifyAsync(ClockifyEntry c, long newStartMs, int newDur)
    {
        SetStatus("Actualizando entrada Clockify…", false);
        var start = DateTimeOffset.FromUnixTimeMilliseconds(newStartMs).LocalDateTime;
        var end = start.AddSeconds(newDur);
        var (ok, err) = await _clockify.UpdateEntryAsync(c.Id, start, end, c.Description ?? "",
                                                         string.IsNullOrEmpty(c.ProjectId) ? null : c.ProjectId,
                                                         c.TagIds, c.Billable);
        if (ok) { _clockify.UpdateLocalEntry(c.Id, start, newDur); await RefreshAsync(); }
        else SetStatus($"Clockify: no se pudo guardar — {err}", true);
    }

    private async Task DuplicateJiraAsync(JiraWorklogStore store, JiraWorklog w)
    {
        SetStatus($"Duplicando worklog Jira {store.InstanceId}…", false);
        var start = DateTimeOffset.FromUnixTimeMilliseconds(w.StartedUnixMs).LocalDateTime;
        var (ok, err) = await store.CreateWorklogAsync(w.IssueKey, start, w.DurationSec, w.Comment ?? "");
        if (ok) await RefreshAsync();
        else SetStatus($"Jira {store.InstanceId}: no se pudo duplicar — {err}", true);
    }

    private async Task DuplicateClockifyAsync(ClockifyEntry c)
    {
        SetStatus("Duplicando entrada Clockify…", false);
        var start = DateTimeOffset.FromUnixTimeMilliseconds(c.StartedUnixMs).LocalDateTime;
        var end = start.AddSeconds(c.DurationSec);
        var (ok, err) = await _clockify.CreateEntryAsync(start, end, c.Description ?? "",
                                                         string.IsNullOrEmpty(c.ProjectId) ? null : c.ProjectId,
                                                         c.TagIds, c.Billable);
        if (ok) await RefreshAsync();
        else SetStatus($"Clockify: no se pudo duplicar — {err}", true);
    }

    private async Task SyncJiraToClockify()
    {
        SyncJiraToClockifyBtn.IsEnabled = false;
        SetStatus("Copiando Jira → Clockify…", false);
        try
        {
            var projectId = string.IsNullOrEmpty(_settings.ClockifyDefaultProjectId) ? null : _settings.ClockifyDefaultProjectId;
            var (created, updated, skipped, failed) = await _clockify.SyncFromJiraAsync(_jira.Worklogs, projectId, _settings.ClockifyBillableDefault);
            SetStatus($"Sync: {created} creadas, {updated} actualizadas, {skipped} ya existían, {failed} fallaron.", failed > 0);
            await _clockify.FetchWeekAsync(_weekStart);
        }
        finally { SyncJiraToClockifyBtn.IsEnabled = true; }
    }

    // -------- Helpers --------------------------------------------------

    private DateTime WeekStartOf(DateTime d)
    {
        int dow = (int)d.DayOfWeek;
        int offset = _settings.FirstDayOfWeek == 1 ? (dow == 0 ? 6 : dow - 1) : dow;
        return d.Date.AddDays(-offset);
    }

    private string FormatWeekLabel(DateTime start)
    {
        var end = start.AddDays(6);
        var months = new[] { "Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic" };
        return $"{start.Day} {months[start.Month - 1]} — {end.Day} {months[end.Month - 1]} {end.Year}";
    }
}
