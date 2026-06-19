using System;
using System.IO;
using H.NotifyIcon;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using WorklogCalendar.Services;
using WorklogCalendar.Views;

namespace WorklogCalendar;

public partial class App : Application
{
    public static Window? MainWindow { get; private set; }

    // App-owned singletons. The main window and the tray popup share
    // the same stores so a fetch driven by either UI updates both.
    public static AppSettings Settings { get; private set; } = new();
    public static JiraWorklogStore? Jira { get; private set; }
    public static ClockifyStore? Clockify { get; private set; }

    private TaskbarIcon? _tray;
    private TrayPopupWindow? _trayPopup;
    private bool _trayPopupVisible;
    private bool _exiting;

    public App()
    {
        this.InitializeComponent();
        this.UnhandledException += (s, e) =>
        {
            System.Diagnostics.Debug.WriteLine($"[Unhandled] {e.Exception}");
            e.Handled = true;
        };
    }

    protected override void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
    {
        try
        {
            FileLogger.Section($"App start {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
            FileLogger.Log("app", $"BaseDir={AppContext.BaseDirectory}");
            Settings = SettingsService.Load();
            Jira = new JiraWorklogStore(Settings);
            Clockify = new ClockifyStore(Settings);
            Clockify.Init();

            MainWindow = new MainWindow();
            MainWindow.Activate();
            // Close button on the main window exits the whole app
            // (tray included). Use the tray menu's "Salir" otherwise.
            MainWindow.Closed += (s, e) => Exit();

            InitializeTrayIcon();
        }
        catch (System.Exception ex)
        {
            var path = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "WorklogCalendar-crash.txt");
            try { File.WriteAllText(path, ex.ToString()); }
            catch { /* nothing else to do */ }
            throw;
        }
    }

    /// <summary>
    /// Build the notification-area icon. Left-click toggles a small
    /// Mica-styled popup with the Sprint + Horas gauges; clicking the
    /// popup brings the main window forward. Right-click shows a menu.
    /// </summary>
    private void InitializeTrayIcon()
    {
        _tray = new TaskbarIcon
        {
            ToolTipText = "Worklog Calendar"
        };

        // H.NotifyIcon.WinUI's IconSource is a Microsoft.UI.Xaml.Media.ImageSource
        // (not a Controls.IconSource as the name suggests). BitmapImage with a
        // file:// URI works for unpackaged apps; WinUI 3's BitmapImage decodes
        // .ico via WIC so the multi-size bundle is used as-is.
        try
        {
            var icoPath = Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico");
            if (File.Exists(icoPath))
            {
                var bmp = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage();
                bmp.UriSource = new Uri(icoPath, UriKind.Absolute);
                _tray.IconSource = bmp;
            }
        }
        catch (System.Exception ex)
        {
            System.Diagnostics.Debug.WriteLine("[Tray] icon load failed: " + ex.Message);
        }

        _tray.LeftClickCommand = new RelayCommand(_ => ToggleTrayPopup());
        _tray.NoLeftClickDelay = true;

        // Build a fresh MenuFlyout for the right-click. Re-creating the
        // items each show avoids the "menu only works once" bug that
        // hits cached flyouts on tray icons in unpackaged WinUI 3.
        _tray.ContextFlyout = BuildContextMenu();

        _tray.ForceCreate();
    }

    private MenuFlyout BuildContextMenu()
    {
        var menu = new MenuFlyout();
        var open = new MenuFlyoutItem { Text = "Abrir Worklog Calendar" };
        open.Click += (s, e) => BringMainToFront();
        var sprint = new MenuFlyoutItem { Text = "Ver sprint" };
        sprint.Click += (s, e) => ShowTrayPopup();
        var exit = new MenuFlyoutItem { Text = "Salir" };
        exit.Click += (s, e) => Exit();
        menu.Items.Add(open);
        menu.Items.Add(sprint);
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(exit);
        // Recreate the entire flyout on each open so its dispatcher /
        // XamlRoot association stays fresh.
        menu.Opening += (s, e) => { /* keep the flyout alive; nothing extra */ };
        return menu;
    }

    private void ToggleTrayPopup()
    {
        if (_trayPopupVisible) HideTrayPopup();
        else                   ShowTrayPopup();
    }

    private void ShowTrayPopup()
    {
        if (Jira == null || Clockify == null) return;
        // Always create a fresh window. WinUI 3 windows that have been
        // hidden via AppWindow.Hide don't always reactivate cleanly, and
        // recreating sidesteps stale state for both the popup body and
        // the slide-in animation.
        try { _trayPopup?.Close(); } catch { /* already gone */ }
        _trayPopup = new TrayPopupWindow(Settings, Jira, Clockify)
        {
            OpenMainRequested = BringMainToFront
        };
        _trayPopup.HideRequested = () =>
        {
            _trayPopupVisible = false;
            try { _trayPopup?.Close(); } catch { /* swallow */ }
            _trayPopup = null;
        };
        _trayPopupVisible = true;
        _trayPopup.ShowNearTray();
    }

    private void HideTrayPopup()
    {
        if (_trayPopup == null) { _trayPopupVisible = false; return; }
        try { _trayPopup.Close(); } catch { /* swallow */ }
        _trayPopup = null;
        _trayPopupVisible = false;
    }

    private void BringMainToFront()
    {
        if (MainWindow == null) return;
        HideTrayPopup();
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(MainWindow);
        var wid = Microsoft.UI.Win32Interop.GetWindowIdFromWindow(hwnd);
        var aw = Microsoft.UI.Windowing.AppWindow.GetFromWindowId(wid);
        aw?.Show();
        MainWindow.Activate();
    }

    private new void Exit()
    {
        if (_exiting) return;
        _exiting = true;
        try { _tray?.Dispose(); } catch { /* tray already gone */ }
        try { _trayPopup?.Close(); } catch { /* swallow */ }
        try { MainWindow?.Close(); } catch { /* already closing */ }
        Application.Current.Exit();
    }

    // -------- Tiny ICommand impl for the tray button --------------------
    private sealed class RelayCommand : System.Windows.Input.ICommand
    {
        private readonly Action<object?> _exec;
        public RelayCommand(Action<object?> exec) { _exec = exec; }
        public bool CanExecute(object? parameter) => true;
        public void Execute(object? parameter) => _exec(parameter);
        public event EventHandler? CanExecuteChanged { add { } remove { } }
    }
}
