using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using WinRT.Interop;
using WorklogCalendar.Models;
using WorklogCalendar.Services;
using WorklogCalendar.Views;

namespace WorklogCalendar;

/// <summary>
/// Desktop window. Owns the two stores, the current week, and dispatches
/// to the WeekCalendarControl + dialogs. Equivalent to
/// FullRepresentation.qml + main.qml on the KDE side.
/// </summary>
public sealed partial class MainWindow : Window
{
    private readonly AppSettings _settings;
    private readonly JiraWorklogStore _jira;
    private readonly ClockifyStore _clockify;
    private DateTime _weekStart;

    public MainWindow()
    {
        this.InitializeComponent();
        // Use the App-level singletons so the tray popup and the main
        // window share the same fetched data.
        _settings = App.Settings;
        _jira = App.Jira ?? new JiraWorklogStore(_settings);
        _clockify = App.Clockify ?? new ClockifyStore(_settings);

        Calendar.Settings = _settings;
        Calendar.JiraStore = _jira;
        Calendar.ClockifyStore = _clockify;
        Gauges.Store = _jira;
        Heatmap.JiraStore = _jira;
        Heatmap.ClockifyStore = _clockify;
        Heatmap.DaySelected += async date =>
        {
            _weekStart = WeekStartOf(date);
            await RefreshAsync();
        };
        Subtasks.Store = _jira;
        Subtasks.Settings = _settings;
        Subtasks.SubtaskActivated += sub => _ = OpenSubtaskDetailAsync(sub);
        Subtasks.OpenInJiraRequested += key =>
        {
            var url = _jira.IssueWebUrl(key);
            if (!string.IsNullOrEmpty(url)) _ = Windows.System.Launcher.LaunchUriAsync(new Uri(url));
        };
        Subtasks.TransitionRequested += async (sub, transitionId) =>
        {
            SetStatus($"Cambiando estado de {sub.Key}…", false);
            var (ok, err) = await _jira.TransitionIssueAsync(sub.Key, transitionId);
            if (!ok) SetStatus($"Jira: no se pudo cambiar estado — {err}", true);
            else await Subtasks.Refresh();
        };
        // Vertical switch (rings → subtasks → heatmap).
        RingsSwitchBtn.Click    += (s, e) => SetBottomView("rings");
        SubtasksSwitchBtn.Click += (s, e) => SetBottomView("subtasks");
        HeatmapSwitchBtn.Click  += (s, e) => SetBottomView("heatmap");
        // Mouse wheel cycles through the available views, clamping at the ends.
        BottomPanel.PointerWheelChanged += (s, e) =>
        {
            var d = e.GetCurrentPoint(BottomPanel).Properties.MouseWheelDelta;
            if (d == 0) return;
            CycleBottomView(d < 0 ? +1 : -1);
        };

        Title = "Worklog Calendar";
        ApplyWindowGeometry();
        ApplyDarkTitleBar();
        ApplyWindowIcon();

        _weekStart = WeekStartOf(DateTime.Today);
        Calendar.WeekStart = _weekStart;

        // Wire events
        Calendar.CreateJiraRequested += (dayMs, sMs, eMs) => _ = OpenJiraEditAsync(null, sMs, eMs);
        Calendar.EditJiraRequested += w => _ = OpenJiraEditAsync(w, w.StartedUnixMs, w.StartedUnixMs + w.DurationSec * 1000L);
        Calendar.CreateClockifyRequested += (dayMs, sMs, eMs) => _ = OpenClockifyEditAsync(null, sMs, eMs);
        Calendar.EditClockifyRequested += c => _ = OpenClockifyEditAsync(c, c.StartedUnixMs, c.StartedUnixMs + c.DurationSec * 1000L);

        // Drag-to-move / edge-resize: one handler per source. We update the
        // store; the JiraStore.PropertyChanged hook below triggers a refetch.
        Calendar.MoveJiraRequested += (w, newStart, newDur) => _ = MoveJiraAsync(w, newStart, newDur);
        Calendar.MoveClockifyRequested += (c, newStart, newDur) => _ = MoveClockifyAsync(c, newStart, newDur);

        // Duplicate buttons (top-right of each block on hover).
        Calendar.DuplicateJiraRequested += w => _ = DuplicateJiraAsync(w);
        Calendar.DuplicateClockifyRequested += c => _ = DuplicateClockifyAsync(c);

        PrevBtn.Click += async (s, e) => { _weekStart = _weekStart.AddDays(-7); await RefreshAsync(); };
        NextBtn.Click += async (s, e) => { _weekStart = _weekStart.AddDays(7); await RefreshAsync(); };
        TodayBtn.Click += async (s, e) => { _weekStart = WeekStartOf(DateTime.Today); await RefreshAsync(); };
        RefreshBtn.Click += async (s, e) => await RefreshAsync();
        ViewModeBtn.Click += async (s, e) =>
        {
            _settings.ViewMode = _settings.ViewMode == "24h" ? "9h" : "24h";
            SettingsService.Save(_settings);
            UpdateHeaderLabels();
            Calendar.Refresh();
            await RefreshAsync();
        };
        DiagBtn.Click += async (s, e) =>
        {
            var d = new DiagnosticsDialog(_jira, _clockify) { XamlRoot = Content.XamlRoot };
            await d.ShowAsync();
        };
        SettingsBtn.Click += async (s, e) => await OpenSettingsAsync();

        SyncJiraToClockifyBtn.Click += async (s, e) => await SyncJiraToClockify();
        SyncProjectCombo.SelectionChanged += (s, e) =>
        {
            var p = SyncProjectCombo.SelectedItem as ClockifyProject;
            _settings.ClockifyDefaultProjectId = p?.Id ?? "";
            SettingsService.Save(_settings);
            UpdateSyncProjectSwatch();
        };

        // Store change notifications: rebuild calendar on each property change.
        // CRITICAL: marshal to the UI thread. PropertyChanged can fire from
        // the HttpClient's worker thread (no SynchronizationContext on the
        // setter), and touching UI from there silently throws — which is
        // why a drag-to-move appeared to "snap back" on release (the
        // post-Update refetch's Refresh exception was being swallowed and
        // the UI kept the stale store positions).
        _jira.PropertyChanged += (s, e) =>
        {
            if (e.PropertyName is nameof(JiraWorklogStore.Worklogs)
                or nameof(JiraWorklogStore.Loading)
                or nameof(JiraWorklogStore.LastError))
            {
                DispatcherQueue.TryEnqueue(() => { UpdateStatus(); Calendar.Refresh(); UpdateTotals(); });
            }
        };
        _clockify.PropertyChanged += (s, e) =>
        {
            if (e.PropertyName is nameof(ClockifyStore.Entries)
                or nameof(ClockifyStore.Loading)
                or nameof(ClockifyStore.LastError)
                or nameof(ClockifyStore.Projects))
            {
                DispatcherQueue.TryEnqueue(() =>
                {
                    UpdateStatus();
                    RefillSyncProjectCombo();
                    Calendar.Refresh();
                    UpdateTotals();
                });
            }
        };

        UpdateHeaderLabels();
        // Run initial fetch once the visual tree is up.
        DispatcherQueue.TryEnqueue(() => { _ = InitialFetchAsync(); });
    }

    private async Task InitialFetchAsync()
    {
        Calendar.Refresh();
        await RefreshAsync();
    }

    // -------- Window geometry, title bar -------------------------------

    /// <summary>
    /// Paint the system title bar (and its min/max/close buttons) dark to
    /// match the rest of the UI. Uses AppWindowTitleBar customization
    /// directly so it works without ExtendsContentIntoTitleBar.
    /// </summary>
    private void ApplyDarkTitleBar()
    {
        try
        {
            var hwnd = WindowNative.GetWindowHandle(this);
            var wid = Win32Interop.GetWindowIdFromWindow(hwnd);
            var aw = AppWindow.GetFromWindowId(wid);
            if (aw == null) return;
            if (!AppWindowTitleBar.IsCustomizationSupported()) return;

            var tb = aw.TitleBar;
            var bg = Windows.UI.Color.FromArgb(0xFF, 0x1F, 0x1F, 0x1F);
            var bgHover = Windows.UI.Color.FromArgb(0xFF, 0x33, 0x33, 0x33);
            var bgPress = Windows.UI.Color.FromArgb(0xFF, 0x40, 0x40, 0x40);
            var fg = Windows.UI.Color.FromArgb(0xFF, 0xEE, 0xEE, 0xEE);
            var fgDim = Windows.UI.Color.FromArgb(0xFF, 0xAA, 0xAA, 0xAA);

            tb.BackgroundColor = bg;
            tb.InactiveBackgroundColor = bg;
            tb.ForegroundColor = fg;
            tb.InactiveForegroundColor = fgDim;
            tb.ButtonBackgroundColor = bg;
            tb.ButtonInactiveBackgroundColor = bg;
            tb.ButtonForegroundColor = fg;
            tb.ButtonInactiveForegroundColor = fgDim;
            tb.ButtonHoverBackgroundColor = bgHover;
            tb.ButtonHoverForegroundColor = fg;
            tb.ButtonPressedBackgroundColor = bgPress;
            tb.ButtonPressedForegroundColor = fg;
        }
        catch (System.Exception ex)
        {
            System.Diagnostics.Debug.WriteLine("[TitleBar] dark theme failed: " + ex.Message);
        }
    }

    /// <summary>Set the .ico shown in the window's top-left corner, Alt-Tab and taskbar.</summary>
    private void ApplyWindowIcon()
    {
        try
        {
            var hwnd = WindowNative.GetWindowHandle(this);
            var wid = Win32Interop.GetWindowIdFromWindow(hwnd);
            var aw = AppWindow.GetFromWindowId(wid);
            if (aw == null) return;
            var icoPath = System.IO.Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico");
            if (System.IO.File.Exists(icoPath)) aw.SetIcon(icoPath);
        }
        catch (System.Exception ex)
        {
            System.Diagnostics.Debug.WriteLine("[Window] icon set failed: " + ex.Message);
        }
    }

    private void ApplyWindowGeometry()
    {
        var hwnd = WindowNative.GetWindowHandle(this);
        var wid = Win32Interop.GetWindowIdFromWindow(hwnd);
        var aw = AppWindow.GetFromWindowId(wid);
        if (aw == null) return;
        aw.Resize(new Windows.Graphics.SizeInt32(_settings.WindowWidth, _settings.WindowHeight));
        if (aw.Presenter is OverlappedPresenter op)
        {
            op.IsAlwaysOnTop = _settings.AlwaysOnTop;
            op.IsResizable = true;
        }
    }

    private void ReapplyAlwaysOnTop()
    {
        var hwnd = WindowNative.GetWindowHandle(this);
        var wid = Win32Interop.GetWindowIdFromWindow(hwnd);
        var aw = AppWindow.GetFromWindowId(wid);
        if (aw?.Presenter is OverlappedPresenter op) op.IsAlwaysOnTop = _settings.AlwaysOnTop;
    }

    // -------- Refresh / fetch -----------------------------------------------

    private async Task RefreshAsync()
    {
        UpdateHeaderLabels();
        Calendar.WeekStart = _weekStart;
        Calendar.Refresh();
        var tasks = new List<Task>();
        if (Calendar.ShowJira) tasks.Add(_jira.FetchWeekAsync(_weekStart));
        if (Calendar.ShowClockify) tasks.Add(_clockify.FetchWeekAsync(_weekStart));
        // Only the rings need a synchronous sprint-info fetch; the
        // subtask table + heatmap fetch their own data on view switch.
        if (ShowBottomPanel && BottomIsRings) tasks.Add(_jira.FetchSprintInfoAsync());
        try { await Task.WhenAll(tasks); }
        catch (Exception ex) { System.Diagnostics.Debug.WriteLine("Refresh error: " + ex); }
        if (ShowBottomPanel && BottomIsRings) Gauges.StartFillAnimation();
        if (ShowBottomPanel && BottomIsSubtasks) _ = Subtasks.Refresh();
        if (ShowBottomPanel && BottomIsHeatmap) _ = Heatmap.Refresh();
    }

    /// <summary>The bottom panel shows whenever the master toggle is on (every mode).</summary>
    private bool ShowBottomPanel => _settings.ShowSprintGauges;
    private bool BottomIsRings    => CurrentBottomView == "rings";
    private bool BottomIsSubtasks => CurrentBottomView == "subtasks";
    private bool BottomIsHeatmap  => CurrentBottomView == "heatmap";

    /// <summary>
    /// Views in switch / wheel order. Rings only appear when the user opts
    /// in (ShowRingsView); subtasks only when ShowSubtaskTable is on. The
    /// order mirrors the macOS build: rings-first when enabled, otherwise
    /// subtasks → heatmap (rings still reachable via its grayed button but
    /// excluded from the wheel cycle).
    /// </summary>
    private List<string> AvailableBottomViews()
    {
        var v = new List<string>();
        if (_settings.ShowRingsView) v.Add("rings");
        if (_settings.ShowSubtaskTable) v.Add("subtasks");
        v.Add("heatmap");
        return v;
    }

    /// <summary>Saved view, falling back to the first available one if the
    /// active view was disabled (e.g. rings off, or subtask table off).</summary>
    private string CurrentBottomView
    {
        get
        {
            var views = AvailableBottomViews();
            var v = _settings.BottomView ?? "";
            return views.Contains(v) ? v : views[0];
        }
    }

    /// <summary>Mouse-wheel cycle handler — clamps at the ends, doesn't wrap.</summary>
    private void CycleBottomView(int delta)
    {
        var views = AvailableBottomViews();
        int idx = views.IndexOf(CurrentBottomView);
        if (idx < 0) idx = 0;
        int next = idx + (delta > 0 ? 1 : -1);
        if (next < 0) next = 0;
        if (next >= views.Count) next = views.Count - 1;
        if (next != idx) SetBottomView(views[next]);
    }

    private void SetBottomView(string view)
    {
        if (CurrentBottomView == view) return;
        // Pick animation direction from the relative index, so the slide
        // stays consistent regardless of which view we're going to.
        var views = AvailableBottomViews();
        int oldIdx = views.IndexOf(CurrentBottomView);
        int newIdx = views.IndexOf(view);
        if (oldIdx < 0) oldIdx = 0;
        if (newIdx < 0) newIdx = 0;
        bool forward = newIdx > oldIdx;

        _settings.BottomView = view;
        SettingsService.Save(_settings);
        AnimateBottomSwitch(forward);

        if (view == "rings") { _ = _jira.FetchSprintInfoAsync(); Gauges.StartFillAnimation(); }
        else if (view == "subtasks") _ = Subtasks.Refresh();
        else _ = Heatmap.Refresh();
    }

    private void UpdateBottomPanel()
    {
        BottomPanel.Visibility = ShowBottomPanel ? Visibility.Visible : Visibility.Collapsed;
        Gauges.Visibility   = BottomIsRings    ? Visibility.Visible : Visibility.Collapsed;
        Subtasks.Visibility = BottomIsSubtasks ? Visibility.Visible : Visibility.Collapsed;
        Heatmap.Visibility  = BottomIsHeatmap  ? Visibility.Visible : Visibility.Collapsed;
        RingsSwitchBtn.IsChecked    = BottomIsRings;
        SubtasksSwitchBtn.IsChecked = BottomIsSubtasks;
        HeatmapSwitchBtn.IsChecked  = BottomIsHeatmap;
        SubtasksSwitchBtn.Visibility = _settings.ShowSubtaskTable ? Visibility.Visible : Visibility.Collapsed;

        // Rings is opt-in. When off, gray + disable its button and move it
        // to the bottom of the switch (matches the macOS build); the wheel
        // cycle already excludes it via AvailableBottomViews.
        bool ringsOn = _settings.ShowRingsView;
        RingsSwitchBtn.IsEnabled = ringsOn;
        RingsSwitchBtn.Opacity = ringsOn ? 1.0 : 0.45;
        ReorderSwitchButtons(ringsOn);
    }

    private void ReorderSwitchButtons(bool ringsFirst)
    {
        // Desired order: rings-first when enabled, else subtasks → heatmap → rings.
        var order = ringsFirst
            ? new UIElement[] { RingsSwitchBtn, SubtasksSwitchBtn, HeatmapSwitchBtn }
            : new UIElement[] { SubtasksSwitchBtn, HeatmapSwitchBtn, RingsSwitchBtn };
        // Only touch the panel if the order actually differs (avoids reflow churn).
        bool same = SwitchPanel.Children.Count == order.Length;
        if (same)
            for (int i = 0; i < order.Length; i++)
                if (!ReferenceEquals(SwitchPanel.Children[i], order[i])) { same = false; break; }
        if (same) return;
        SwitchPanel.Children.Clear();
        foreach (var el in order) SwitchPanel.Children.Add(el);
    }

    /// <summary>Fade + slide the bottom content when switching views.</summary>
    private void AnimateBottomSwitch(bool forward)
    {
        int dir = forward ? 1 : -1;
        var sb = new Microsoft.UI.Xaml.Media.Animation.Storyboard();

        var fadeOut = new Microsoft.UI.Xaml.Media.Animation.DoubleAnimation
        { To = 0, Duration = TimeSpan.FromMilliseconds(130) };
        Microsoft.UI.Xaml.Media.Animation.Storyboard.SetTarget(fadeOut, BottomContent);
        Microsoft.UI.Xaml.Media.Animation.Storyboard.SetTargetProperty(fadeOut, "Opacity");
        sb.Children.Add(fadeOut);

        var slideOut = new Microsoft.UI.Xaml.Media.Animation.DoubleAnimation
        { To = dir * 26, Duration = TimeSpan.FromMilliseconds(130) };
        Microsoft.UI.Xaml.Media.Animation.Storyboard.SetTarget(slideOut, BottomSlide);
        Microsoft.UI.Xaml.Media.Animation.Storyboard.SetTargetProperty(slideOut, "Y");
        sb.Children.Add(slideOut);

        sb.Completed += (s, e) =>
        {
            UpdateBottomPanel();
            BottomSlide.Y = -dir * 26;
            var inb = new Microsoft.UI.Xaml.Media.Animation.Storyboard();
            var fadeIn = new Microsoft.UI.Xaml.Media.Animation.DoubleAnimation
            { To = 1, Duration = TimeSpan.FromMilliseconds(160) };
            Microsoft.UI.Xaml.Media.Animation.Storyboard.SetTarget(fadeIn, BottomContent);
            Microsoft.UI.Xaml.Media.Animation.Storyboard.SetTargetProperty(fadeIn, "Opacity");
            inb.Children.Add(fadeIn);
            var slideIn = new Microsoft.UI.Xaml.Media.Animation.DoubleAnimation
            { To = 0, Duration = TimeSpan.FromMilliseconds(160) };
            Microsoft.UI.Xaml.Media.Animation.Storyboard.SetTarget(slideIn, BottomSlide);
            Microsoft.UI.Xaml.Media.Animation.Storyboard.SetTargetProperty(slideIn, "Y");
            inb.Children.Add(slideIn);
            inb.Begin();
        };
        sb.Begin();
    }

    private void UpdateHeaderLabels()
    {
        TitleText.Text = _settings.Source switch
        {
            "clockify" => "Clockify",
            "jira-clockify" => "Jira / Clockify",
            _ => "Jira Worklog"
        };
        SourceBtn.Content = TitleText.Text;
        ViewModeBtn.Content = _settings.ViewMode == "9h" ? "Modo 9h" : "Modo 24h";
        WeekLabel.Text = FormatWeekLabel(_weekStart);

        bool combined = _settings.Source == "jira-clockify";
        SyncProjectCombo.Visibility = combined ? Visibility.Visible : Visibility.Collapsed;
        SyncProjectSwatch.Visibility = combined ? Visibility.Visible : Visibility.Collapsed;
        SyncJiraToClockifyBtn.Visibility = combined ? Visibility.Visible : Visibility.Collapsed;
        UpdateBottomPanel();
    }

    // The status label always renders a non-breaking space so its height
    // is reserved — opacity goes to 0 when there's nothing to say. Avoids
    // the calendar below jumping up/down on every sync/clear cycle.
    private CancellationTokenSource? _statusOverrideCts;
    private bool _statusOverrideActive;

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

    /// <summary>Show a transient status message; clears after 6 s.</summary>
    private void SetStatus(string text, bool isError)
    {
        _statusOverrideActive = true;
        ApplyStatus(text, isError);
        _statusOverrideCts?.Cancel();
        _statusOverrideCts = new CancellationTokenSource();
        var ct = _statusOverrideCts.Token;
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
            StatusLabel.Text = " ";    // NBSP keeps line height
            StatusLabel.Opacity = 0;
            return;
        }
        StatusLabel.Text = text;
        StatusLabel.Opacity = 0.85;
        StatusLabel.Foreground = isError
            ? new SolidColorBrush(Color.FromArgb(255, 234, 90, 84))
            : new SolidColorBrush(Color.FromArgb(255, 120, 200, 130));
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

    // -------- Source picker --------------------------------------------------

    private async void OnSourceChanged(object sender, RoutedEventArgs e)
    {
        if (sender is not MenuFlyoutItem mi || mi.Tag is not string src) return;
        _settings.Source = src;
        SettingsService.Save(_settings);
        UpdateHeaderLabels();
        await RefreshAsync();
    }

    // -------- Dialogs --------------------------------------------------------

    private async Task OpenJiraEditAsync(JiraWorklog? existing, long startMs, long endMs)
    {
        var s = DateTimeOffset.FromUnixTimeMilliseconds(startMs).LocalDateTime;
        var en = DateTimeOffset.FromUnixTimeMilliseconds(endMs).LocalDateTime;
        var dlg = new JiraEditDialog(_jira, _settings, s, en, existing) { XamlRoot = Content.XamlRoot };
        await dlg.ShowAsync();
        if (dlg.Mutated) await RefreshAsync();
    }

    private async Task OpenClockifyEditAsync(ClockifyEntry? existing, long startMs, long endMs)
    {
        var s = DateTimeOffset.FromUnixTimeMilliseconds(startMs).LocalDateTime;
        var en = DateTimeOffset.FromUnixTimeMilliseconds(endMs).LocalDateTime;
        var dlg = new ClockifyEditDialog(_clockify, _settings, s, en, existing) { XamlRoot = Content.XamlRoot };
        await dlg.ShowAsync();
        if (dlg.Mutated) await RefreshAsync();
    }

    private async Task OpenSubtaskDetailAsync(JiraSubtask sub)
    {
        var dlg = new SubtaskDetailDialog(_jira, _settings, sub) { XamlRoot = Content.XamlRoot };
        await dlg.ShowAsync();
    }

    private async Task OpenSettingsAsync()
    {
        var dlg = new SettingsDialog(_settings) { XamlRoot = Content.XamlRoot };
        var r = await dlg.ShowAsync();
        if (r == ContentDialogResult.Primary)
        {
            UpdateHeaderLabels();
            ApplyWindowGeometry();
            ReapplyAlwaysOnTop();
            _clockify.Init();
            Subtasks.Settings = _settings;
            // If the user disabled the view that was showing (rings or the
            // subtask table), persist the normalized fallback so the saved
            // BottomView stays valid.
            var normalized = CurrentBottomView;
            if (_settings.BottomView != normalized)
            {
                _settings.BottomView = normalized;
                SettingsService.Save(_settings);
            }
            Calendar.Refresh();
            await RefreshAsync();
        }
    }

    // -------- Combined sync --------------------------------------------------

    private void RefillSyncProjectCombo()
    {
        var list = new List<ClockifyProject> { new() { Id = "", Name = "(sin proyecto)" } };
        list.AddRange(_clockify.Projects);
        SyncProjectCombo.ItemsSource = list;
        int idx = 0;
        for (int i = 0; i < list.Count; i++)
            if (list[i].Id == _settings.ClockifyDefaultProjectId) { idx = i; break; }
        SyncProjectCombo.SelectedIndex = idx;
        UpdateSyncProjectSwatch();
    }

    private void UpdateSyncProjectSwatch()
    {
        var p = SyncProjectCombo.SelectedItem as ClockifyProject;
        SolidColorBrush brush = new(Colors.Transparent);
        if (p != null && !string.IsNullOrEmpty(p.Color) && TryParseHex(p.Color, out var col))
            brush = new SolidColorBrush(col);
        SyncProjectSwatch.Background = brush;
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

    // -------- Move / duplicate (single Connections-style refetch) -----------

    private async Task MoveJiraAsync(JiraWorklog w, long newStartMs, int newDur)
    {
        SetStatus("Actualizando worklog Jira…", false);
        var start = DateTimeOffset.FromUnixTimeMilliseconds(newStartMs).LocalDateTime;
        var (ok, err) = await _jira.UpdateWorklogAsync(w.IssueKey, w.Id, start, newDur, w.Comment ?? "");
        if (ok)
        {
            // Optimistic: patch the local list NOW so the upcoming Refresh
            // (and the post-refetch Refresh) paints the block at the new
            // slot. Without this, the block briefly snaps back to its old
            // position while FetchWeekAsync is still in flight — and stays
            // there if Jira's response hasn't propagated yet.
            _jira.UpdateLocalWorklog(w.Id, start, newDur);
            await RefreshAsync();
        }
        else SetStatus($"Jira: no se pudo guardar — {err}", true);
    }

    private async Task MoveClockifyAsync(ClockifyEntry c, long newStartMs, int newDur)
    {
        SetStatus("Actualizando entrada Clockify…", false);
        var start = DateTimeOffset.FromUnixTimeMilliseconds(newStartMs).LocalDateTime;
        var end = start.AddSeconds(newDur);
        var (ok, err) = await _clockify.UpdateEntryAsync(c.Id, start, end, c.Description ?? "",
                                                         string.IsNullOrEmpty(c.ProjectId) ? null : c.ProjectId,
                                                         c.TagIds, c.Billable);
        if (ok)
        {
            _clockify.UpdateLocalEntry(c.Id, start, newDur);
            await RefreshAsync();
        }
        else SetStatus($"Clockify: no se pudo guardar — {err}", true);
    }

    private async Task DuplicateJiraAsync(JiraWorklog w)
    {
        SetStatus("Duplicando worklog Jira…", false);
        var start = DateTimeOffset.FromUnixTimeMilliseconds(w.StartedUnixMs).LocalDateTime;
        var (ok, err) = await _jira.CreateWorklogAsync(w.IssueKey, start, w.DurationSec, w.Comment ?? "");
        if (ok) await RefreshAsync();
        else SetStatus($"Jira: no se pudo duplicar — {err}", true);
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

    // -------- Helpers --------------------------------------------------------

    private DateTime WeekStartOf(DateTime d)
    {
        int dow = (int)d.DayOfWeek; // Sunday=0
        int offset = _settings.FirstDayOfWeek == 1
            ? (dow == 0 ? 6 : dow - 1)  // Monday-start
            : dow;                       // Sunday-start
        return d.Date.AddDays(-offset);
    }

    private string FormatWeekLabel(DateTime start)
    {
        var end = start.AddDays(6);
        var months = new[] { "Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic" };
        return $"{start.Day} {months[start.Month - 1]} — {end.Day} {months[end.Month - 1]} {end.Year}";
    }

    private static bool TryParseHex(string hex, out Color col)
    {
        col = Colors.Transparent;
        if (string.IsNullOrEmpty(hex)) return false;
        var s = hex.StartsWith("#") ? hex.Substring(1) : hex;
        if (s.Length == 6 &&
            byte.TryParse(s.Substring(0, 2), System.Globalization.NumberStyles.HexNumber, null, out var r) &&
            byte.TryParse(s.Substring(2, 2), System.Globalization.NumberStyles.HexNumber, null, out var g) &&
            byte.TryParse(s.Substring(4, 2), System.Globalization.NumberStyles.HexNumber, null, out var b))
        { col = Color.FromArgb(255, r, g, b); return true; }
        return false;
    }
}
