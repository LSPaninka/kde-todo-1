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
    private readonly JiraWorklogStore _jira2;
    private readonly GoogleCalendarStore _google;
    private DateTime _weekStart;

    public MainWindow()
    {
        this.InitializeComponent();
        // Use the App-level singletons so the tray popup and the main
        // window share the same fetched data.
        _settings = App.Settings;
        _jira = App.Jira ?? new JiraWorklogStore(_settings, 1);
        _jira2 = App.Jira2 ?? new JiraWorklogStore(_settings, 2);
        _clockify = App.Clockify ?? new ClockifyStore(_settings);
        _google = App.Google ?? new GoogleCalendarStore(_settings);

        Calendar.Settings = _settings;
        Calendar.JiraStore = _jira;
        Calendar.Jira2Store = _jira2;
        Calendar.ClockifyStore = _clockify;
        Calendar.GoogleStore = _google;
        // The bottom panel (rings / subtasks / heatmap) always follows the
        // first Jira instance — matching the KDE build.
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
        Calendar.EditJiraRequested += w => _ = OpenJiraEditAsync(w, w.StartedUnixMs, w.StartedUnixMs + w.DurationSec * 1000L, 1);
        Calendar.EditJira2Requested += w => _ = OpenJiraEditAsync(w, w.StartedUnixMs, w.StartedUnixMs + w.DurationSec * 1000L, 2);
        Calendar.CreateClockifyRequested += (dayMs, sMs, eMs) => _ = OpenClockifyEditAsync(null, sMs, eMs);
        Calendar.EditClockifyRequested += c => _ = OpenClockifyEditAsync(c, c.StartedUnixMs, c.StartedUnixMs + c.DurationSec * 1000L);

        // Drag-to-move / edge-resize: one handler per source. We update the
        // store; the JiraStore.PropertyChanged hook below triggers a refetch.
        Calendar.MoveJiraRequested += (w, newStart, newDur) => _ = MoveJiraAsync(_jira, w, newStart, newDur);
        Calendar.MoveJira2Requested += (w, newStart, newDur) => _ = MoveJiraAsync(_jira2, w, newStart, newDur);
        Calendar.MoveClockifyRequested += (c, newStart, newDur) => _ = MoveClockifyAsync(c, newStart, newDur);

        // Duplicate buttons (top-right of each block on hover).
        Calendar.DuplicateJiraRequested += w => _ = DuplicateJiraAsync(_jira, w);
        Calendar.DuplicateJira2Requested += w => _ = DuplicateJiraAsync(_jira2, w);
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
        DiagOpenMenu.Click += async (s, e) =>
        {
            var d = new DiagnosticsDialog(_jira, _clockify, _jira2, _google) { XamlRoot = Content.XamlRoot };
            await d.ShowAsync();
        };
        OpenLogFileMenu.Click += (s, e) => OpenLogFile();
        OpenLogFolderMenu.Click += (s, e) => OpenLogFolder();
        ClearLogMenu.Click += (s, e) =>
        {
            try { System.IO.File.WriteAllText(FileLogger.LogPath, ""); }
            catch (Exception ex) { System.Diagnostics.Debug.WriteLine("clear log: " + ex.Message); }
            SetStatus("worklog.log limpiado.", false);
        };
        SettingsBtn.Click += async (s, e) => await OpenSettingsAsync();

        // Google Calendar overlay toggle. Persisted so it survives restarts.
        GoogleToggleBtn.IsChecked = _settings.GoogleCalEnabled;
        GoogleToggleBtn.Click += async (s, e) =>
        {
            _settings.GoogleCalEnabled = GoogleToggleBtn.IsChecked == true;
            SettingsService.Save(_settings);
            await RefreshAsync();
        };

        SyncJiraToClockifyBtn.Click += async (s, e) => await SyncJiraToClockify();

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
        _jira2.PropertyChanged += (s, e) =>
        {
            if (e.PropertyName is nameof(JiraWorklogStore.Worklogs)
                or nameof(JiraWorklogStore.Loading)
                or nameof(JiraWorklogStore.LastError))
            {
                DispatcherQueue.TryEnqueue(() => { UpdateStatus(); Calendar.Refresh(); UpdateTotals(); });
            }
        };
        _google.PropertyChanged += (s, e) =>
        {
            if (e.PropertyName is nameof(GoogleCalendarStore.Events)
                or nameof(GoogleCalendarStore.LastError))
            {
                DispatcherQueue.TryEnqueue(() => { UpdateStatus(); Calendar.Refresh(); });
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
        FileLogger.Log("refresh", $"RefreshAsync ENTER worklogsCount={_jira.Worklogs.Count} entriesCount={_clockify.Entries.Count}");
        UpdateHeaderLabels();
        Calendar.WeekStart = _weekStart;
        Calendar.Refresh();
        FileLogger.Log("refresh", "RefreshAsync first Calendar.Refresh done; starting fetches");
        var tasks = new List<Task>();
        if (Calendar.ShowJira) tasks.Add(_jira.FetchWeekAsync(_weekStart));
        if (Calendar.ShowJira2) tasks.Add(_jira2.FetchWeekAsync(_weekStart));
        if (Calendar.ShowClockify) tasks.Add(_clockify.FetchWeekAsync(_weekStart));
        if (Calendar.ShowGoogle) tasks.Add(_google.FetchWeekAsync(_weekStart));
        if (ShowBottomPanel && BottomIsRings) tasks.Add(_jira.FetchSprintInfoAsync());
        try { await Task.WhenAll(tasks); }
        catch (Exception ex) { FileLogger.Log("refresh", "fetch error: " + ex); }
        FileLogger.Log("refresh", $"RefreshAsync post-fetch worklogsCount={_jira.Worklogs.Count} entriesCount={_clockify.Entries.Count}");
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
        if (_settings.Jira2Enabled)
        {
            if (_jira2.Loading) parts.Add("Jira 2: cargando…");
            else if (!string.IsNullOrEmpty(_jira2.LastError)) parts.Add($"Jira 2: {_jira2.LastError}");
        }
        if (_clockify.Loading) parts.Add("Clockify: cargando…");
        else if (!string.IsNullOrEmpty(_clockify.LastError)) parts.Add($"Clockify: {_clockify.LastError}");
        if (_settings.GoogleCalEnabled && !string.IsNullOrEmpty(_google.LastError))
            parts.Add($"Google: {_google.LastError}");

        bool isError = !string.IsNullOrEmpty(_jira.LastError)
                       || (_settings.Jira2Enabled && !string.IsNullOrEmpty(_jira2.LastError))
                       || !string.IsNullOrEmpty(_clockify.LastError)
                       || (_settings.GoogleCalEnabled && !string.IsNullOrEmpty(_google.LastError));
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
        if (Calendar.ShowJira2)
        {
            int s = 0; foreach (var w in _jira2.Worklogs) s += w.DurationSec;
            parts.Add($"Jira 2: {s / 3600}h {(s % 3600) / 60}m");
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

    /// <summary>
    /// Open the Jira worklog modal. <paramref name="instanceId"/> selects
    /// which store to edit against; when creating (existing == null) and the
    /// second instance is enabled, the modal also offers a Jira 1 / Jira 2
    /// switch so you pick the target site there.
    /// </summary>
    private async Task OpenJiraEditAsync(JiraWorklog? existing, long startMs, long endMs, int instanceId = 1)
    {
        var s = DateTimeOffset.FromUnixTimeMilliseconds(startMs).LocalDateTime;
        var en = DateTimeOffset.FromUnixTimeMilliseconds(endMs).LocalDateTime;
        var store = instanceId == 2 ? _jira2 : _jira;
        bool allowSwitch = existing == null && _settings.Jira2Enabled;
        var dlg = new JiraEditDialog(store, _settings, s, en, existing,
                                     store2: _jira2, allowInstanceSwitch: allowSwitch)
        { XamlRoot = Content.XamlRoot };
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

    private void OpenLogFile()
    {
        try
        {
            if (!System.IO.File.Exists(FileLogger.LogPath))
                System.IO.File.WriteAllText(FileLogger.LogPath, "");
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "notepad.exe",
                Arguments = $"\"{FileLogger.LogPath}\"",
                UseShellExecute = true
            });
        }
        catch (Exception ex) { System.Diagnostics.Debug.WriteLine("open log: " + ex.Message); }
    }

    private void OpenLogFolder()
    {
        try
        {
            System.IO.Directory.CreateDirectory(SettingsService.ConfigDir);
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = $"\"{SettingsService.ConfigDir}\"",
                UseShellExecute = true
            });
        }
        catch (Exception ex) { System.Diagnostics.Debug.WriteLine("open log folder: " + ex.Message); }
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



    /// <summary>
    /// Mirror both Jira instances into Clockify. Each instance writes into
    /// its own mapped Clockify project (Settings → Clockify), so instance 1
    /// and 2 can never dedup against or overwrite each other's entries.
    /// Runs sequentially and reports the combined totals.
    /// </summary>
    private async Task SyncJiraToClockify()
    {
        SyncJiraToClockifyBtn.IsEnabled = false;
        SetStatus("Copiando Jira → Clockify…", false);
        try
        {
            int created = 0, updated = 0, skipped = 0, failed = 0;

            var p1 = string.IsNullOrEmpty(_settings.Jira1ClockifyProjectId) ? null : _settings.Jira1ClockifyProjectId;
            var r1 = await _clockify.SyncFromJiraAsync(_jira.Worklogs, p1, _settings.ClockifyBillableDefault);
            created += r1.created; updated += r1.updated; skipped += r1.skipped; failed += r1.failed;

            if (_settings.Jira2Enabled)
            {
                var p2 = string.IsNullOrEmpty(_settings.Jira2ClockifyProjectId) ? null : _settings.Jira2ClockifyProjectId;
                var r2 = await _clockify.SyncFromJiraAsync(_jira2.Worklogs, p2, _settings.ClockifyBillableDefault);
                created += r2.created; updated += r2.updated; skipped += r2.skipped; failed += r2.failed;
            }

            SetStatus($"Sync: {created} creadas, {updated} actualizadas, {skipped} ya existían, {failed} fallaron.", failed > 0);
            await _clockify.FetchWeekAsync(_weekStart);
        }
        finally { SyncJiraToClockifyBtn.IsEnabled = true; }
    }

    // -------- Move / duplicate (single Connections-style refetch) -----------

    /// <summary>Move / resize on either Jira instance — <paramref name="store"/> picks which.</summary>
    private async Task MoveJiraAsync(JiraWorklogStore store, JiraWorklog w, long newStartMs, int newDur)
    {
        FileLogger.Log("move", $"MoveJiraAsync[{store.InstanceId}] ENTER issue={w.IssueKey} id={w.Id} oldStart={w.StartedUnixMs} oldDur={w.DurationSec} → newStart={newStartMs} newDur={newDur}");
        SetStatus($"Actualizando worklog Jira {store.InstanceId}…", false);
        var start = DateTimeOffset.FromUnixTimeMilliseconds(newStartMs).LocalDateTime;
        var (ok, err) = await store.UpdateWorklogAsync(w.IssueKey, w.Id, start, newDur, w.Comment ?? "");
        FileLogger.Log("move", $"MoveJiraAsync[{store.InstanceId}] UpdateWorklogAsync returned ok={ok} err={err}");
        if (ok)
        {
            store.UpdateLocalWorklog(w.Id, start, newDur);
            await RefreshAsync();
        }
        else SetStatus($"Jira {store.InstanceId}: no se pudo guardar — {err}", true);
    }

    private async Task MoveClockifyAsync(ClockifyEntry c, long newStartMs, int newDur)
    {
        FileLogger.Log("move", $"MoveClockifyAsync ENTER id={c.Id} oldStart={c.StartedUnixMs} oldDur={c.DurationSec} → newStart={newStartMs} newDur={newDur}");
        SetStatus("Actualizando entrada Clockify…", false);
        var start = DateTimeOffset.FromUnixTimeMilliseconds(newStartMs).LocalDateTime;
        var end = start.AddSeconds(newDur);
        var (ok, err) = await _clockify.UpdateEntryAsync(c.Id, start, end, c.Description ?? "",
                                                         string.IsNullOrEmpty(c.ProjectId) ? null : c.ProjectId,
                                                         c.TagIds, c.Billable);
        FileLogger.Log("move", $"MoveClockifyAsync UpdateEntryAsync returned ok={ok} err={err}");
        if (ok)
        {
            _clockify.UpdateLocalEntry(c.Id, start, newDur);
            FileLogger.Log("move", $"MoveClockifyAsync UpdateLocalEntry done; calling RefreshAsync");
            await RefreshAsync();
        }
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
