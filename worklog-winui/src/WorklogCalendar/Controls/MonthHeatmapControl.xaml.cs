using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI;
using WorklogCalendar.Services;

namespace WorklogCalendar.Controls;

/// <summary>
/// Month-at-a-glance hours table. Port of <c>MonthHeatmap.qml</c>.
/// Uniform columns: an icon column (Clockify / Jira) + one per day.
/// Rows: weekday letter, day number, Clockify hours cell, Jira hours
/// cell. Cells grade gray(0) → red → yellow → green from 0 to 4h.
/// Clicking a day cell raises <see cref="DaySelected"/> so the caller
/// can jump the calendar to that day's week.
/// </summary>
public sealed partial class MonthHeatmapControl : UserControl
{
    public event Action<DateTime>? DaySelected;

    public JiraWorklogStore? JiraStore { get; set; }
    public ClockifyStore? ClockifyStore { get; set; }

    private const double LetterRowH = 14;
    private const double NumberRowH = 16;
    private const double CellRowH = 20;

    private int _monthOffset;   // 0 = current month, -1 = last month
    private int _reqId;
    private Dictionary<int, int> _clockifyTotals = new();
    private Dictionary<int, int> _jiraTotals = new();
    private string _clockifyKey = "";
    private string _jiraKey = "";

    private static readonly string[] MonthNames =
    {
        "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
        "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"
    };
    private static readonly string[] DowLetters = { "D", "L", "M", "Mi", "J", "V", "S" };
    private static readonly FontFamily SegoeMdl2 = new("Segoe MDL2 Assets");

    public MonthHeatmapControl()
    {
        this.InitializeComponent();
        PrevMonthBtn.Click += (s, e) => { if (_monthOffset > -1) { _monthOffset = -1; _ = Refresh(); } };
        NextMonthBtn.Click += (s, e) => { if (_monthOffset < 0) { _monthOffset = 0; _ = Refresh(); } };
    }

    private DateTime RefDate()
    {
        var d = new DateTime(DateTime.Today.Year, DateTime.Today.Month, 1).AddMonths(_monthOffset);
        return d;
    }

    private int Year => RefDate().Year;
    private int Month => RefDate().Month;   // 1..12
    private int DaysInMonth => DateTime.DaysInMonth(Year, Month);
    private string CurKey => $"{Year}-{Month}";

    /// <summary>Re-fetch both sources for the visible month and rebuild the grid.</summary>
    public async Task Refresh()
    {
        // Wipe + invalidate so nothing from the old month renders while
        // the new fetch is in flight.
        _clockifyTotals = new();
        _jiraTotals = new();
        _clockifyKey = "";
        _jiraKey = "";
        int req = ++_reqId;

        var rd = RefDate();
        int y = rd.Year, m = rd.Month - 1;   // store helpers take 0-based month
        string key = $"{rd.Year}-{rd.Month}";

        UpdateMonthLabel();
        BuildGrid();   // shows empty cells immediately

        var jiraTask = JiraStore != null ? JiraStore.FetchMonthTotalsAsync(y, m) : Task.FromResult(new Dictionary<int, int>());
        var clkTask = ClockifyStore != null ? ClockifyStore.FetchMonthTotalsAsync(y, m) : Task.FromResult(new Dictionary<int, int>());

        try
        {
            var clk = await clkTask;
            if (req == _reqId) { _clockifyTotals = clk; _clockifyKey = key; BuildGrid(); UpdateMonthTotals(); }
        }
        catch (Exception ex) { System.Diagnostics.Debug.WriteLine("[Heatmap] clk: " + ex.Message); }

        try
        {
            var jira = await jiraTask;
            if (req == _reqId) { _jiraTotals = jira; _jiraKey = key; BuildGrid(); UpdateMonthTotals(); }
        }
        catch (Exception ex) { System.Diagnostics.Debug.WriteLine("[Heatmap] jira: " + ex.Message); }
    }

    private void UpdateMonthLabel()
    {
        MonthLabel.Text = $"{MonthNames[Month - 1]} {Year}";
        PrevMonthBtn.IsEnabled = _monthOffset > -1;
        NextMonthBtn.IsEnabled = _monthOffset < 0;
        UpdateMonthTotals();
    }

    /// <summary>
    /// Footer summing the visible month's consumed hours per source.
    /// Month-guarded by the same clockifyKey / jiraKey stamps the cells use,
    /// so a late response for another month can never leak into the total.
    /// </summary>
    private void UpdateMonthTotals()
    {
        if (MonthTotalsLabel == null) return;
        int clkSec = _clockifyKey == CurKey ? SumDict(_clockifyTotals) : 0;
        int jiraSec = _jiraKey == CurKey ? SumDict(_jiraTotals) : 0;
        MonthTotalsLabel.Text =
            $"Total del mes — Clockify: {FormatHours(clkSec)}   ·   Jira: {FormatHours(jiraSec)}";
    }

    private static int SumDict(Dictionary<int, int> d)
    {
        int total = 0;
        foreach (var v in d.Values) total += v;
        return total;
    }

    private static string FormatHours(int sec)
    {
        if (sec <= 0) return "0h";
        int h = sec / 3600, m = (sec % 3600) / 60;
        if (h > 0 && m > 0) return $"{h}h {m}m";
        if (h > 0) return $"{h}h";
        return $"{m}m";
    }

    private void BuildGrid()
    {
        HeatGrid.Children.Clear();
        HeatGrid.RowDefinitions.Clear();
        HeatGrid.ColumnDefinitions.Clear();

        int days = DaysInMonth;
        // Column 0 = icon column, 1..days = day columns (all equal width).
        for (int c = 0; c <= days; c++)
            HeatGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        HeatGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(LetterRowH) });
        HeatGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(NumberRowH) });
        HeatGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(CellRowH) });
        HeatGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(CellRowH) });

        // Icon column: Clockify glyph (row 2) + Jira glyph (row 3).
        // Segoe MDL2 Assets: E916 = Stopwatch, E7C1 = Flag (task marker).
        var clkIcon = new FontIcon { Glyph = "\uE916", FontFamily = SegoeMdl2, FontSize = 13, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        ToolTipService.SetToolTip(clkIcon, "Clockify");
        Grid.SetRow(clkIcon, 2); Grid.SetColumn(clkIcon, 0);
        HeatGrid.Children.Add(clkIcon);

        var jiraIcon = new FontIcon { Glyph = "\uE7C1", FontFamily = SegoeMdl2, FontSize = 13, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        ToolTipService.SetToolTip(jiraIcon, "Jira");
        Grid.SetRow(jiraIcon, 3); Grid.SetColumn(jiraIcon, 0);
        HeatGrid.Children.Add(jiraIcon);

        for (int day = 1; day <= days; day++)
        {
            int col = day;
            bool weekend = IsWeekend(day);

            var letter = new TextBlock
            {
                Text = WeekdayLetter(day),
                FontSize = 10,
                TextAlignment = TextAlignment.Center,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = weekend ? DimBrush() : TextBrush(),
                Opacity = weekend ? 0.8 : 1.0
            };
            Grid.SetRow(letter, 0); Grid.SetColumn(letter, col);
            HeatGrid.Children.Add(letter);

            var num = new TextBlock
            {
                Text = day.ToString(),
                FontSize = 10,
                TextAlignment = TextAlignment.Center,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = weekend ? DimBrush() : TextBrush(),
                FontWeight = weekend ? FontWeights.Normal : FontWeights.SemiBold
            };
            Grid.SetRow(num, 1); Grid.SetColumn(num, col);
            HeatGrid.Children.Add(num);

            var clkCell = MakeCell(ClkHours(day), day);
            Grid.SetRow(clkCell, 2); Grid.SetColumn(clkCell, col);
            HeatGrid.Children.Add(clkCell);

            var jiraCell = MakeCell(JiraHours(day), day);
            Grid.SetRow(jiraCell, 3); Grid.SetColumn(jiraCell, col);
            HeatGrid.Children.Add(jiraCell);
        }
    }

    private Border MakeCell(double hours, int day)
    {
        var overlay = new Rectangle
        {
            Fill = new SolidColorBrush(Colors.White),
            Opacity = 0,
            RadiusX = 2, RadiusY = 2
        };
        var label = new TextBlock
        {
            Text = FmtNum(hours),
            FontSize = 10,
            FontWeight = FontWeights.Bold,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = new SolidColorBrush(CellTextColor(hours))
        };
        var grid = new Grid();
        grid.Children.Add(overlay);
        grid.Children.Add(label);

        var cell = new Border
        {
            Background = new SolidColorBrush(CellColor(hours)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(0x26, 0, 0, 0)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Margin = new Thickness(0.5),
            Child = grid
        };
        // Hover: fade a white overlay in/out (~180 ms).
        cell.PointerEntered += (s, e) => AnimateOverlay(overlay, 0.28);
        cell.PointerExited += (s, e) => AnimateOverlay(overlay, 0.0);
        cell.PointerPressed += (s, e) => DaySelected?.Invoke(new DateTime(Year, Month, day));
        return cell;
    }

    private static void AnimateOverlay(Rectangle r, double to)
    {
        var sb = new Storyboard();
        var a = new DoubleAnimation
        {
            To = to,
            Duration = TimeSpan.FromMilliseconds(180),
            EnableDependentAnimation = true,
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut }
        };
        Storyboard.SetTarget(a, r);
        Storyboard.SetTargetProperty(a, "Opacity");
        sb.Children.Add(a);
        sb.Begin();
    }

    // ---- Per-day value lookups (month-guarded) -----------------------

    private double ClkHours(int day) =>
        _clockifyKey != CurKey ? 0 : HoursDecimal(_clockifyTotals.TryGetValue(day, out var s) ? s : 0);
    private double JiraHours(int day) =>
        _jiraKey != CurKey ? 0 : HoursDecimal(_jiraTotals.TryGetValue(day, out var s) ? s : 0);

    private static double HoursDecimal(int sec) => sec <= 0 ? 0 : Math.Round(sec / 3600.0 * 10) / 10;

    private static string FmtNum(double h)
    {
        if (h <= 0) return "";
        if (h == Math.Floor(h)) return ((int)h).ToString();
        return h.ToString("0.0");
    }

    // ---- Color grading ----------------------------------------------

    private static Color Lerp(Color a, Color b, double t) => Color.FromArgb(
        255,
        (byte)(a.R + (b.R - a.R) * t),
        (byte)(a.G + (b.G - a.G) * t),
        (byte)(a.B + (b.B - a.B) * t));

    private static Color CellColor(double h)
    {
        if (h <= 0) return Color.FromArgb(0x10, 0xFF, 0xFF, 0xFF);
        var red = Color.FromArgb(255, 231, 76, 60);
        var yellow = Color.FromArgb(255, 241, 196, 15);
        var green = Color.FromArgb(255, 129, 199, 132);
        double c = Math.Min(4, h);
        return c <= 2 ? Lerp(red, yellow, c / 2) : Lerp(yellow, green, (c - 2) / 2);
    }

    private static Color CellTextColor(double h) =>
        h > 0 ? Color.FromArgb(255, 26, 26, 26) : Color.FromArgb(255, 220, 220, 220);

    // ---- Calendar helpers -------------------------------------------

    private int Dow(int day) => (int)new DateTime(Year, Month, day).DayOfWeek;  // Sunday=0
    private bool IsWeekend(int day) { int d = Dow(day); return d == 0 || d == 6; }
    private string WeekdayLetter(int day) => DowLetters[Dow(day)];

    private static SolidColorBrush TextBrush() => new(Color.FromArgb(255, 230, 230, 230));
    private static SolidColorBrush DimBrush() => new(Color.FromArgb(255, 140, 140, 140));
}
