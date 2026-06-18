using System;
using System.Collections.Generic;
using Microsoft.UI;
using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;
using Windows.System;
using Windows.UI;
using WorklogCalendar.Models;
using WorklogCalendar.Services;

namespace WorklogCalendar.Controls;

/// <summary>
/// Week-view calendar grid. Port of <c>WorklogCalendar.qml</c>.
/// Renders 7 day columns × N rows of 30-min slots with Jira / Clockify
/// blocks drawn as absolutely-positioned cards on each day's Canvas.
///
/// Pointer interactions on every block (chosen by Y at press time):
///   - top 5 px       → resize from top  (changes start + duration)
///   - bottom 5 px    → resize from bottom (duration only)
///   - middle         → drag-to-move (X+Y, cross-day OK) or click-to-edit
/// All three end at <see cref="EmitChange"/> which clamps and fires
/// <see cref="MoveJiraRequested"/> / <see cref="MoveClockifyRequested"/>.
///
/// Each block has a small duplicate button in the top-right that shows
/// on hover and emits <see cref="DuplicateJiraRequested"/> /
/// <see cref="DuplicateClockifyRequested"/>.
/// </summary>
public sealed partial class WeekCalendarControl : UserControl
{
    public event Action<long /*dayMs*/, long /*startMs*/, long /*endMs*/>? CreateJiraRequested;
    public event Action<long, long, long>? CreateClockifyRequested;
    public event Action<JiraWorklog>? EditJiraRequested;
    public event Action<ClockifyEntry>? EditClockifyRequested;
    /// <summary>Fired after a drag-to-move or edge-resize on a Jira block.</summary>
    public event Action<JiraWorklog /*entry*/, long /*newStartMs*/, int /*newDurationSec*/>? MoveJiraRequested;
    public event Action<ClockifyEntry, long, int>? MoveClockifyRequested;
    public event Action<JiraWorklog>? DuplicateJiraRequested;
    public event Action<ClockifyEntry>? DuplicateClockifyRequested;

    public AppSettings? Settings { get; set; }
    public JiraWorklogStore? JiraStore { get; set; }
    public ClockifyStore? ClockifyStore { get; set; }
    public DateTime WeekStart { get; set; } = DateTime.Today;
    public string Source => Settings?.Source ?? "jira";
    public bool IsCombined => Source == "jira-clockify";
    public bool ShowJira => Source is "jira" or "jira-clockify";
    public bool ShowClockify => Source is "clockify" or "jira-clockify";

    private const double RowHeight = 22;
    private const double HourColWidth = 64;
    private const double HeaderRowHeight = 26;
    private const double TotalsRowHeight = 24;
    private const double EdgePx = 5;       // top/bottom resize hot-zone

    private readonly List<Canvas> _dayCanvases = new();
    private readonly List<Border> _totalsCells = new();
    private readonly Dictionary<Canvas, Rectangle> _dragOverlays = new();
    private readonly Dictionary<Canvas, Border> _dragLabels = new();

    public WeekCalendarControl()
    {
        this.InitializeComponent();
    }

    public int StartHour => (Settings?.ViewMode ?? "9h") == "24h" ? 0 : 9;
    public int EndHour => (Settings?.ViewMode ?? "9h") == "24h" ? 24 : 18;
    public int SlotsPerDay => (EndHour - StartHour) * 2;

    /// <summary>Rebuild the whole grid. Cheap enough to call on every store change.</summary>
    public void Refresh()
    {
        if (Settings == null) return;
        RootGrid.Children.Clear();
        RootGrid.RowDefinitions.Clear();
        RootGrid.ColumnDefinitions.Clear();
        _dayCanvases.Clear();
        _totalsCells.Clear();
        _dragOverlays.Clear();
        _dragLabels.Clear();

        RootGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(HourColWidth) });
        for (int i = 0; i < 7; i++)
            RootGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        RootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(HeaderRowHeight) });
        RootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(TotalsRowHeight) });
        RootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(SlotsPerDay * RowHeight) });

        BuildCornerAndHeaders();
        BuildHourColumn();
        BuildDayColumns();
        UpdateTotalsCells();
        RenderEntries();
    }

    private void BuildCornerAndHeaders()
    {
        var corner = new Border
        {
            Background = NeutralBrush(0.06),
            BorderBrush = NeutralBrush(0.16),
            BorderThickness = new Thickness(1),
            Child = new TextBlock
            {
                Text = "total",
                FontSize = 11,
                Opacity = 0.6,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            }
        };
        Grid.SetRow(corner, 0); Grid.SetRowSpan(corner, 2); Grid.SetColumn(corner, 0);
        RootGrid.Children.Add(corner);

        for (int i = 0; i < 7; i++)
        {
            var dayDate = WeekStart.AddDays(i);
            bool isToday = dayDate.Date == DateTime.Today;
            bool isWeekend = dayDate.DayOfWeek is DayOfWeek.Saturday or DayOfWeek.Sunday;
            // Today wins; weekend gets a slightly darker neutral; weekdays neutral.
            var headerBg = isToday
                ? AccentBrush(0.22)
                : (isWeekend ? new SolidColorBrush(Color.FromArgb(0x3D, 0x00, 0x00, 0x00))
                             : NeutralBrush(0.06));
            var header = new Border
            {
                Background = headerBg,
                BorderBrush = NeutralBrush(0.16),
                BorderThickness = new Thickness(1),
                Child = new TextBlock
                {
                    Text = FormatDayHeader(i, dayDate),
                    FontWeight = isToday ? Microsoft.UI.Text.FontWeights.Bold : Microsoft.UI.Text.FontWeights.SemiBold,
                    FontSize = 12,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center
                }
            };
            Grid.SetRow(header, 0); Grid.SetColumn(header, i + 1);
            RootGrid.Children.Add(header);

            var totalsCell = new Border
            {
                BorderBrush = NeutralBrush(0.16),
                BorderThickness = new Thickness(1)
            };
            Grid.SetRow(totalsCell, 1); Grid.SetColumn(totalsCell, i + 1);
            RootGrid.Children.Add(totalsCell);
            _totalsCells.Add(totalsCell);
        }
    }

    private void BuildHourColumn()
    {
        var stack = new Canvas { Width = HourColWidth };
        for (int slot = 0; slot < SlotsPerDay; slot++)
        {
            var bg = new Rectangle
            {
                Width = HourColWidth,
                Height = RowHeight,
                Fill = (slot % 2 == 0) ? NeutralBrush(0.02) : new SolidColorBrush(Colors.Transparent)
            };
            Canvas.SetLeft(bg, 0); Canvas.SetTop(bg, slot * RowHeight);
            stack.Children.Add(bg);

            // Align the label to the TOP of its slot so it lines up with a
            // block that starts on that slot boundary (a block at 09:00
            // starts at y=0, so "09:00" must sit at the top of slot 0, not
            // centered in it).
            var tb = new TextBlock
            {
                Text = SlotLabel(slot),
                FontSize = 10,
                Opacity = slot % 2 == 0 ? 0.85 : 0.45,
                TextAlignment = TextAlignment.Right,
                Width = HourColWidth - 6
            };
            Canvas.SetLeft(tb, 0); Canvas.SetTop(tb, slot * RowHeight + 1);
            stack.Children.Add(tb);
        }
        Grid.SetRow(stack, 2); Grid.SetColumn(stack, 0);
        RootGrid.Children.Add(stack);
    }

    private void BuildDayColumns()
    {
        for (int day = 0; day < 7; day++)
        {
            var dayDate = WeekStart.AddDays(day);
            bool isToday = dayDate.Date == DateTime.Today;
            bool isWeekend = dayDate.DayOfWeek is DayOfWeek.Saturday or DayOfWeek.Sunday;

            var canvas = new Canvas
            {
                Background = new SolidColorBrush(Colors.Transparent),
                Height = SlotsPerDay * RowHeight,
                HorizontalAlignment = HorizontalAlignment.Stretch,
                // Keep the parent ScrollViewer from stealing touch / pen
                // gestures that start inside a day column (equivalent of
                // QML's preventStealing).
                ManipulationMode = ManipulationModes.None
            };
            // Weekend tint sits at the very bottom of the z-stack.
            if (isWeekend)
            {
                var wknd = new Rectangle
                {
                    Fill = new SolidColorBrush(Color.FromArgb(0x2E, 0x00, 0x00, 0x00)), // ~0.18 black
                    Height = SlotsPerDay * RowHeight
                };
                Canvas.SetTop(wknd, 0); Canvas.SetLeft(wknd, 0);
                canvas.Children.Add(wknd);
                canvas.SizeChanged += (s, e) => wknd.Width = e.NewSize.Width;
            }
            // Today-column tint underneath everything else (stacks over weekend).
            if (isToday)
            {
                var tint = new Rectangle { Fill = AccentBrush(0.10), Height = SlotsPerDay * RowHeight };
                Canvas.SetTop(tint, 0); Canvas.SetLeft(tint, 0);
                canvas.Children.Add(tint);
                canvas.SizeChanged += (s, e) => tint.Width = e.NewSize.Width;
            }
            // Background slot stripes & borders.
            for (int slot = 0; slot < SlotsPerDay; slot++)
            {
                var row = new Rectangle
                {
                    Fill = (slot % 2 == 0) ? NeutralBrush(0.03) : NeutralBrush(0.0),
                    Stroke = NeutralBrush(0.08),
                    StrokeThickness = 0.5,
                    Height = RowHeight,
                    HorizontalAlignment = HorizontalAlignment.Stretch
                };
                Canvas.SetTop(row, slot * RowHeight);
                Canvas.SetLeft(row, 0);
                canvas.Children.Add(row);
            }

            // The drag-overlay rectangle (hidden until a drag starts).
            var drag = new Rectangle
            {
                Fill = AccentBrush(0.30),
                Stroke = AccentBrush(1.0),
                StrokeThickness = 1,
                IsHitTestVisible = false,
                Visibility = Visibility.Collapsed
            };
            Canvas.SetZIndex(drag, 9999);
            canvas.Children.Add(drag);
            _dragOverlays[canvas] = drag;

            // A centered "HH:MM–HH:MM" capsule that updates live as the
            // user drags (and flashes briefly on click-to-create).
            var lbl = new Border
            {
                Background = new SolidColorBrush(Color.FromArgb(0x8C, 0, 0, 0)),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(6, 1, 6, 1),
                IsHitTestVisible = false,
                Visibility = Visibility.Collapsed,
                Child = new TextBlock
                {
                    FontSize = 10,
                    Foreground = new SolidColorBrush(Colors.White)
                }
            };
            Canvas.SetZIndex(lbl, 10000);
            canvas.Children.Add(lbl);
            _dragLabels[canvas] = lbl;

            if (IsCombined)
            {
                var div = new Rectangle
                {
                    Fill = NeutralBrush(0.18),
                    Width = 1,
                    Height = SlotsPerDay * RowHeight
                };
                Canvas.SetTop(div, 0);
                Canvas.SetLeft(div, 0);
                Canvas.SetZIndex(div, 5);
                canvas.Children.Add(div);
                canvas.SizeChanged += (s, e) => Canvas.SetLeft(div, e.NewSize.Width / 2 - 0.5);
            }

            canvas.SizeChanged += (s, e) =>
            {
                foreach (var child in canvas.Children)
                {
                    if (child is Rectangle r && r.Height == RowHeight && r != drag)
                        r.Width = e.NewSize.Width;
                }
                LayoutEntryBlocks(canvas, e.NewSize.Width);
            };

            int dayIdx = day;
            canvas.PointerPressed += (s, e) => OnDayPressed(canvas, dayIdx, e);
            canvas.PointerMoved += (s, e) => OnDayMoved(canvas, dayIdx, e);
            canvas.PointerReleased += (s, e) => OnDayReleased(canvas, dayIdx, e);
            canvas.PointerCaptureLost += (s, e) => HideDragOverlay(canvas);

            Grid.SetRow(canvas, 2); Grid.SetColumn(canvas, day + 1);
            RootGrid.Children.Add(canvas);
            _dayCanvases.Add(canvas);
        }
    }

    private void UpdateTotalsCells()
    {
        for (int i = 0; i < 7 && i < _totalsCells.Count; i++)
        {
            var s = TotalSecForDay(i);
            var cell = _totalsCells[i];
            if (s <= 0)
            {
                cell.Background = NeutralBrush(0.02);
                cell.Child = MakeText("-", 11);
            }
            else
            {
                var target = (Settings?.DailyTargetHours ?? 8) * 3600;
                cell.Background = s >= target
                    ? new SolidColorBrush(Color.FromArgb(0x2E, 0x2E, 0xCC, 0x71))
                    : new SolidColorBrush(Color.FromArgb(0x2E, 0xF1, 0xC4, 0x0F));
                cell.Child = MakeText($"Logged: {FormatTotal(s)} {FormatDiff(s)}", 11);
            }
        }
    }

    private TextBlock MakeText(string s, double sz) => new TextBlock
    {
        Text = s, FontSize = sz,
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center
    };

    private int TotalSecForDay(int idx)
    {
        int s = 0;
        if (ShowJira && JiraStore != null)
        {
            long startMs = ToMs(WeekStart.AddDays(idx)), endMs = ToMs(WeekStart.AddDays(idx + 1));
            foreach (var w in JiraStore.Worklogs)
                if (w.StartedUnixMs >= startMs && w.StartedUnixMs < endMs) s += w.DurationSec;
            if (s > 0 || !ShowClockify) return s;
        }
        if (ShowClockify && ClockifyStore != null)
        {
            long startMs = ToMs(WeekStart.AddDays(idx)), endMs = ToMs(WeekStart.AddDays(idx + 1));
            foreach (var w in ClockifyStore.Entries)
                if (w.StartedUnixMs >= startMs && w.StartedUnixMs < endMs) s += w.DurationSec;
        }
        return s;
    }

    private void RenderEntries()
    {
        foreach (var canvas in _dayCanvases) ClearEntryBlocks(canvas);
        for (int day = 0; day < 7 && day < _dayCanvases.Count; day++)
        {
            var canvas = _dayCanvases[day];
            long dayStart = ToMs(WeekStart.AddDays(day));
            long dayEnd = ToMs(WeekStart.AddDays(day + 1));
            if (ShowJira && JiraStore != null)
            {
                foreach (var w in JiraStore.Worklogs)
                    if (w.StartedUnixMs >= dayStart && w.StartedUnixMs < dayEnd)
                        canvas.Children.Add(BuildBlock(w, isJira: true));
            }
            if (ShowClockify && ClockifyStore != null)
            {
                foreach (var e in ClockifyStore.Entries)
                    if (e.StartedUnixMs >= dayStart && e.StartedUnixMs < dayEnd)
                        canvas.Children.Add(BuildBlock(e, isJira: false));
            }
            if (canvas.ActualWidth > 0)
                LayoutEntryBlocks(canvas, canvas.ActualWidth);
        }
    }

    private void ClearEntryBlocks(Canvas canvas)
    {
        for (int i = canvas.Children.Count - 1; i >= 0; i--)
            if (canvas.Children[i] is Border) canvas.Children.RemoveAt(i);
    }

    private Border BuildBlock(object entry, bool isJira)
    {
        long startedMs; int durSec; string title; string subtitle; SolidColorBrush fill; SolidColorBrush border;
        if (isJira)
        {
            var w = (JiraWorklog)entry;
            startedMs = w.StartedUnixMs; durSec = w.DurationSec;
            title = FormatTimeRange(w.StartedUnixMs, w.DurationSec);
            bool showSummary = Settings?.ShowJiraSummary ?? false;
            subtitle = showSummary && !string.IsNullOrEmpty(w.IssueSummary) ? $"{w.IssueKey}: {w.IssueSummary}" : w.IssueKey;
            fill = (SolidColorBrush)Application.Current.Resources["JiraFillBrush"];
            border = (SolidColorBrush)Application.Current.Resources["JiraBorderBrush"];
        }
        else
        {
            var c = (ClockifyEntry)entry;
            startedMs = c.StartedUnixMs; durSec = c.DurationSec;
            title = FormatTimeRange(c.StartedUnixMs, c.DurationSec);
            var desc = string.IsNullOrEmpty(c.Description) ? "(sin descripción)" : c.Description;
            subtitle = !string.IsNullOrEmpty(c.ProjectName) ? $"[{c.ProjectName}] {desc}" : desc;
            if (!IsCombined && !string.IsNullOrEmpty(c.ProjectColor) && TryParseHex(c.ProjectColor, out var col))
            {
                fill = new SolidColorBrush(Color.FromArgb(0x8C, col.R, col.G, col.B));
                border = new SolidColorBrush(col);
            }
            else
            {
                fill = (SolidColorBrush)Application.Current.Resources["ClockifyFillBrush"];
                border = (SolidColorBrush)Application.Current.Resources["ClockifyBorderBrush"];
            }
        }

        bool isShort = durSec <= 30 * 60;
        var stack = new StackPanel { Orientation = Orientation.Vertical, Spacing = 0 };
        stack.Children.Add(new TextBlock
        {
            Text = isShort ? FormatTimeShort(startedMs) + "  " + subtitle : title,
            Foreground = new SolidColorBrush(Colors.White),
            FontSize = isShort || IsCombined ? 10 : 11,
            TextTrimming = TextTrimming.CharacterEllipsis,
            TextWrapping = TextWrapping.NoWrap
        });
        if (!isShort)
        {
            stack.Children.Add(new TextBlock
            {
                Text = subtitle,
                Foreground = new SolidColorBrush(Colors.White),
                FontSize = IsCombined ? 10 : 11,
                TextTrimming = TextTrimming.CharacterEllipsis,
                TextWrapping = TextWrapping.NoWrap
            });
        }

        // Wrap stack + duplicate button in a Grid so the button sits in the
        // top-right corner without participating in the layout flow.
        var inner = new Grid();
        inner.Children.Add(stack);

        var dupBtn = new Border
        {
            Width = 18,
            Height = 18,
            CornerRadius = new CornerRadius(3),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, 1, 1, 0),
            Background = new SolidColorBrush(Color.FromArgb(0x4D, 0x00, 0x00, 0x00)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(0x80, 0xFF, 0xFF, 0xFF)),
            BorderThickness = new Thickness(1),
            Opacity = 0,
            IsHitTestVisible = false,
            Child = new TextBlock
            {
                // Segoe MDL2 Assets glyph U+E8C8 (Copy).
                FontFamily = new FontFamily("Segoe MDL2 Assets"),
                Text = "",
                FontSize = 10,
                Foreground = new SolidColorBrush(Colors.White),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            }
        };
        Canvas.SetZIndex(dupBtn, 10);
        inner.Children.Add(dupBtn);

        var card = new CursorBorder
        {
            Background = fill,
            BorderBrush = border,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(3),
            Padding = new Thickness(3),
            Content = inner,
            // Don't let the parent ScrollViewer treat a press-and-move on
            // this block as a scroll/pan gesture (preventStealing in QML).
            ManipulationMode = ManipulationModes.None
        };
        var tag = new BlockTag(isJira, startedMs, durSec, entry);
        card.Tag = tag;

        // Show / hide the duplicate button on hover. PointerEntered fires
        // on the parent Border for the whole card area.
        card.PointerEntered += (s, e) => { dupBtn.Opacity = 1; dupBtn.IsHitTestVisible = true; };
        card.PointerExited += (s, e) =>
        {
            if (tag.IsDragging) return;
            dupBtn.Opacity = 0; dupBtn.IsHitTestVisible = false;
        };
        dupBtn.PointerPressed += (s, e) =>
        {
            e.Handled = true;
            if (isJira) DuplicateJiraRequested?.Invoke((JiraWorklog)entry);
            else DuplicateClockifyRequested?.Invoke((ClockifyEntry)entry);
        };

        // Drag / resize / click. PointerPressed picks the mode by Y; the
        // day-canvas's handlers do NOT trigger because the Border swallows
        // the event before bubbling.
        card.PointerPressed += (s, e) => OnBlockPressed(card, tag, e);
        card.PointerMoved += (s, e) => OnBlockMoved(card, tag, e);
        card.PointerReleased += (s, e) => OnBlockReleased(card, tag, e);
        card.PointerCaptureLost += (s, e) => ResetBlock(card, tag);

        return card;
    }

    /// <summary>Per-block interaction state.</summary>
    private sealed class BlockTag
    {
        public bool IsJira;
        public long StartedMs;
        public int DurationSec;
        public object Entry;
        // Geometry at press time, used to compute deltas.
        public double OrigLeft;
        public double OrigTop;
        public double OrigWidth;
        public double OrigHeight;
        public Point PressInParent;     // pointer pos in the parent Canvas
        // 0 = idle, 1 = move, 2 = resize-top, 3 = resize-bottom
        public int Mode;
        public bool Dragged;
        public bool IsDragging => Mode != 0;
        public BlockTag(bool isJira, long startedMs, int durationSec, object entry)
        { IsJira = isJira; StartedMs = startedMs; DurationSec = durationSec; Entry = entry; }
    }

    private void LayoutEntryBlocks(Canvas canvas, double width)
    {
        int day = _dayCanvases.IndexOf(canvas);
        if (day < 0) return;
        foreach (var child in canvas.Children)
        {
            if (child is not Border b || b.Tag is not BlockTag t) continue;
            if (t.IsDragging) continue;   // don't yank a block out from under the cursor
            // Minute-precise positioning so 10-min blocks render at their
            // real size (1 row = 30 min = RowHeight).
            double y = YForMs(t.StartedMs, day);
            double h = Math.Max(RowHeight / 3.0, t.DurationSec / 1800.0 * RowHeight) - 2;
            double left, w;
            if (IsCombined)
            {
                if (t.IsJira) { left = 2; w = width / 2 - 4; }
                else { left = width / 2 + 1; w = width / 2 - 3; }
            }
            else { left = 2; w = width - 4; }
            Canvas.SetLeft(b, left);
            Canvas.SetTop(b, y);
            b.Width = Math.Max(0, w);
            b.Height = Math.Max(0, h);
        }
    }

    // ---- Block interaction ------------------------------------------------

    private void OnBlockPressed(Border card, BlockTag tag, PointerRoutedEventArgs e)
    {
        var pt = e.GetCurrentPoint(card);
        if (!pt.Properties.IsLeftButtonPressed) return;

        var canvas = card.Parent as Canvas;
        if (canvas == null) return;

        tag.OrigLeft = Canvas.GetLeft(card);
        tag.OrigTop = Canvas.GetTop(card);
        tag.OrigWidth = card.ActualWidth;
        tag.OrigHeight = card.ActualHeight;
        tag.PressInParent = card.TransformToVisual(canvas).TransformPoint(pt.Position);
        tag.Dragged = false;

        if (pt.Position.Y < EdgePx) tag.Mode = 2;
        else if (pt.Position.Y > card.ActualHeight - EdgePx) tag.Mode = 3;
        else tag.Mode = 1;

        if (tag.Mode == 1)
        {
            // Float the block AND its day-column above siblings so a
            // cross-day drag isn't visually clipped by the next column.
            Canvas.SetZIndex(card, 999);
            Canvas.SetZIndex(canvas, 999);
        }
        card.CapturePointer(e.Pointer);
        e.Handled = true;
    }

    private void OnBlockMoved(Border card, BlockTag tag, PointerRoutedEventArgs e)
    {
        if (tag.Mode == 0)
        {
            // Plain hover (not dragging): pick the cursor by pointer Y —
            // top/bottom 5 px advertise the resize, the middle the move.
            if (card is CursorBorder cb)
            {
                double y = e.GetCurrentPoint(card).Position.Y;
                bool nearEdge = y < EdgePx || y > card.ActualHeight - EdgePx;
                cb.SetCursorShape(nearEdge
                    ? Microsoft.UI.Input.InputSystemCursorShape.SizeNorthSouth
                    : Microsoft.UI.Input.InputSystemCursorShape.SizeAll);
            }
            return;
        }
        var canvas = card.Parent as Canvas;
        if (canvas == null) return;
        var pos = card.TransformToVisual(canvas).TransformPoint(e.GetCurrentPoint(card).Position);
        double dx = pos.X - tag.PressInParent.X;
        double dy = pos.Y - tag.PressInParent.Y;

        // Shift → snap to 10-min steps (RowHeight/3 px) instead of 30 (RowHeight).
        bool fine = IsShiftDown();
        double stepPx = fine ? RowHeight / 3.0 : RowHeight;

        if (tag.Mode == 1)
        {
            if (!tag.Dragged && Math.Abs(dx) < 4 && Math.Abs(dy) < 4) return;
            tag.Dragged = true;
            double colW = canvas.ActualWidth;
            double snappedDx = colW > 0 ? Math.Round(dx / colW) * colW : 0;
            double snappedDy = Math.Round(dy / stepPx) * stepPx;
            double newY = tag.OrigTop + snappedDy;
            double maxY = Math.Max(0, canvas.ActualHeight - card.ActualHeight);
            newY = Math.Max(0, Math.Min(maxY, newY));
            Canvas.SetLeft(card, tag.OrigLeft + snappedDx);
            Canvas.SetTop(card, newY);
        }
        else if (tag.Mode == 2)
        {
            if (Math.Abs(dy) > 2) tag.Dragged = true;
            double stepY = Math.Round(dy / stepPx) * stepPx;
            double minH = stepPx;
            double newY = tag.OrigTop + stepY;
            double newH = tag.OrigHeight - stepY;
            if (newY < 0) { newH += newY; newY = 0; }
            if (newH < minH) { newH = minH; newY = tag.OrigTop + tag.OrigHeight - minH; }
            Canvas.SetTop(card, newY);
            card.Height = newH;
        }
        else if (tag.Mode == 3)
        {
            if (Math.Abs(dy) > 2) tag.Dragged = true;
            double stepDH = Math.Round(dy / stepPx) * stepPx;
            double newH = tag.OrigHeight + stepDH;
            if (newH < stepPx) newH = stepPx;
            double maxH = Math.Max(stepPx, canvas.ActualHeight - Canvas.GetTop(card));
            if (newH > maxH) newH = maxH;
            card.Height = newH;
        }
    }

    private void OnBlockReleased(Border card, BlockTag tag, PointerRoutedEventArgs e)
    {
        var canvas = card.Parent as Canvas;
        if (canvas == null) return;
        card.ReleasePointerCapture(e.Pointer);
        int mode = tag.Mode;
        bool dragged = tag.Dragged;
        tag.Mode = 0;
        Canvas.SetZIndex(card, 0);
        Canvas.SetZIndex(canvas, 0);

        if (!dragged)
        {
            // Plain click → edit.
            if (tag.IsJira) EditJiraRequested?.Invoke((JiraWorklog)tag.Entry);
            else EditClockifyRequested?.Invoke((ClockifyEntry)tag.Entry);
            return;
        }

        double dx = Canvas.GetLeft(card) - tag.OrigLeft;
        double dy = Canvas.GetTop(card) - tag.OrigTop;
        double dh = card.ActualHeight - tag.OrigHeight;
        double colW = canvas.ActualWidth;
        bool fine = IsShiftDown();
        if (mode == 1)
        {
            int days = colW > 0 ? (int)Math.Round(dx / colW) : 0;
            int stepMin = PxToSnappedMin(dy, fine);
            if (days == 0 && stepMin == 0) { Refresh(); return; }
            long newStart = tag.StartedMs + days * 86400000L + stepMin * 60_000L;
            EmitChange(tag, newStart, tag.DurationSec);
        }
        else if (mode == 2)
        {
            int stepMin = PxToSnappedMin(dy, fine);
            if (stepMin == 0) { Refresh(); return; }
            long newStart = tag.StartedMs + stepMin * 60_000L;
            int newDur = tag.DurationSec - stepMin * 60;
            EmitChange(tag, newStart, newDur);
        }
        else if (mode == 3)
        {
            int stepMin = PxToSnappedMin(dh, fine);
            if (stepMin == 0) { Refresh(); return; }
            int newDur = tag.DurationSec + stepMin * 60;
            EmitChange(tag, tag.StartedMs, newDur);
        }
    }

    /// <summary>True if either Shift key is currently held (10-min fine snap).</summary>
    private static bool IsShiftDown()
    {
        var state = InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift);
        return (state & Windows.UI.Core.CoreVirtualKeyStates.Down) != 0;
    }

    /// <summary>Pixel delta → snapped minutes. Shift snaps to 10, else 30.</summary>
    private int PxToSnappedMin(double px, bool fine)
    {
        int g = fine ? 10 : 30;
        double rawMin = px / RowHeight * 30.0;
        return (int)(Math.Round(rawMin / g) * g);
    }

    private void ResetBlock(Border card, BlockTag tag)
    {
        if (tag.Mode == 0) return;
        tag.Mode = 0;
        if (card.Parent is Canvas cv) Canvas.SetZIndex(cv, 0);
        Canvas.SetZIndex(card, 0);
        Refresh();
    }

    /// <summary>
    /// Single exit point for move + edge-resize gestures. Clamps the new
    /// (start, duration) to the visible week and enforces a 30-min floor.
    /// </summary>
    private void EmitChange(BlockTag tag, long newStartMs, int newDurationSec)
    {
        long wsMs = ToMs(WeekStart);
        long weMs = ToMs(WeekStart.AddDays(7));
        long durMs = newDurationSec * 1000L;
        if (newStartMs < wsMs) newStartMs = wsMs;
        if (newStartMs + durMs > weMs) newStartMs = weMs - durMs;
        if (newDurationSec < 600) newDurationSec = 600;   // 10-min floor
        if (newStartMs == tag.StartedMs && newDurationSec == tag.DurationSec) { Refresh(); return; }
        if (tag.IsJira) MoveJiraRequested?.Invoke((JiraWorklog)tag.Entry, newStartMs, newDurationSec);
        else MoveClockifyRequested?.Invoke((ClockifyEntry)tag.Entry, newStartMs, newDurationSec);
    }

    // ---- Day-canvas drag-to-create ----------------------------------------

    private record DragState(double PressY, bool PressLeft);
    private readonly Dictionary<Canvas, DragState> _drag = new();

    private void OnDayPressed(Canvas canvas, int day, PointerRoutedEventArgs e)
    {
        var pt = e.GetCurrentPoint(canvas);
        if (!pt.Properties.IsLeftButtonPressed) return;
        // Don't start a drag if the press originated on a block — the
        // block's handler already set e.Handled and stole the pointer.
        if (e.Handled) return;
        canvas.CapturePointer(e.Pointer);
        bool left = !IsCombined || pt.Position.X < canvas.ActualWidth / 2;
        _drag[canvas] = new DragState(pt.Position.Y, left);
        var overlay = _dragOverlays[canvas];
        overlay.Visibility = Visibility.Visible;
        UpdateDragOverlay(canvas, pt.Position.Y);
    }

    private void OnDayMoved(Canvas canvas, int day, PointerRoutedEventArgs e)
    {
        if (!_drag.TryGetValue(canvas, out _)) return;
        var pt = e.GetCurrentPoint(canvas);
        UpdateDragOverlay(canvas, pt.Position.Y);
    }

    private void OnDayReleased(Canvas canvas, int day, PointerRoutedEventArgs e)
    {
        if (!_drag.TryGetValue(canvas, out var st)) return;
        canvas.ReleasePointerCapture(e.Pointer);
        var pt = e.GetCurrentPoint(canvas);
        _drag.Remove(canvas);

        bool fine = IsShiftDown();
        var dayDate = WeekStart.AddDays(day);
        var startMs = MsAtSnappedPx(dayDate, Math.Min(st.PressY, pt.Position.Y), fine);
        var endMs = MsAtSnappedPx(dayDate, Math.Max(st.PressY, pt.Position.Y), fine);
        int floorMin = fine ? 10 : 30;
        if (endMs <= startMs) endMs = startMs + floorMin * 60_000;
        long dayMs = ToMs(dayDate);

        // Flash the marker briefly so the chosen slot is visible behind the
        // create modal, then auto-clear after ~400 ms.
        FlashMarker(canvas);

        if (IsCombined)
        {
            if (st.PressLeft) CreateJiraRequested?.Invoke(dayMs, startMs, endMs);
            else CreateClockifyRequested?.Invoke(dayMs, startMs, endMs);
        }
        else if (Source == "jira") CreateJiraRequested?.Invoke(dayMs, startMs, endMs);
        else CreateClockifyRequested?.Invoke(dayMs, startMs, endMs);
    }

    /// <summary>Keep the overlay + range label visible for ~400 ms, then hide.</summary>
    private void FlashMarker(Canvas canvas)
    {
        var timer = DispatcherQueue.CreateTimer();
        timer.Interval = TimeSpan.FromMilliseconds(400);
        timer.IsRepeating = false;
        timer.Tick += (s, e) => { timer.Stop(); HideDragOverlay(canvas); };
        timer.Start();
    }

    private void HideDragOverlay(Canvas canvas)
    {
        if (_dragOverlays.TryGetValue(canvas, out var ov)) ov.Visibility = Visibility.Collapsed;
        if (_dragLabels.TryGetValue(canvas, out var lb)) lb.Visibility = Visibility.Collapsed;
    }

    private void UpdateDragOverlay(Canvas canvas, double curY)
    {
        if (!_drag.TryGetValue(canvas, out var st)) return;
        bool fine = IsShiftDown();
        double stepPx = fine ? RowHeight / 3.0 : RowHeight;
        var overlay = _dragOverlays[canvas];
        double top = SnapPx(Math.Min(st.PressY, curY), stepPx);
        double bot = SnapPx(Math.Max(st.PressY, curY), stepPx) + stepPx;
        double left = IsCombined ? (st.PressLeft ? 0 : canvas.ActualWidth / 2) : 0;
        double w = IsCombined ? canvas.ActualWidth / 2 : canvas.ActualWidth;
        Canvas.SetTop(overlay, top);
        Canvas.SetLeft(overlay, left);
        overlay.Width = w;
        overlay.Height = Math.Max(stepPx, bot - top);

        // Live "HH:MM–HH:MM" label centered in the rectangle.
        int day = _dayCanvases.IndexOf(canvas);
        if (day >= 0) ShowRangeLabel(canvas, day, top, bot, left, w, fine);
    }

    /// <summary>Position + fill the time-range capsule over a drag/flash rectangle.</summary>
    private void ShowRangeLabel(Canvas canvas, int day, double top, double bot, double left, double w, bool fine)
    {
        if (!_dragLabels.TryGetValue(canvas, out var lbl)) return;
        var dayDate = WeekStart.AddDays(day);
        long startMs = MsAtSnappedPx(dayDate, top, fine);
        long endMs = MsAtSnappedPx(dayDate, bot, fine);
        if (lbl.Child is TextBlock tb)
            tb.Text = $"{ShortTime(startMs)}–{ShortTime(endMs)}";
        lbl.Visibility = Visibility.Visible;
        // Center horizontally over the rectangle; vertically centered in it.
        lbl.Measure(new Windows.Foundation.Size(double.PositiveInfinity, double.PositiveInfinity));
        double lw = lbl.DesiredSize.Width, lh = lbl.DesiredSize.Height;
        Canvas.SetLeft(lbl, left + (w - lw) / 2);
        Canvas.SetTop(lbl, top + Math.Max(0, (bot - top - lh) / 2));
    }

    private static string ShortTime(long ms) =>
        DateTimeOffset.FromUnixTimeMilliseconds(ms).LocalDateTime.ToString("HH:mm");

    private double SnapPx(double y, double stepPx)
    {
        double maxPx = SlotsPerDay * RowHeight;
        double s = Math.Round(y / stepPx) * stepPx;
        return Math.Clamp(s, 0, maxPx);
    }

    // ---- Helpers ----------------------------------------------------------

    /// <summary>Convert a snapped pixel Y in a day column to an absolute unix-ms.</summary>
    private long MsAtSnappedPx(DateTime day, double y, bool fine)
    {
        double stepPx = fine ? RowHeight / 3.0 : RowHeight;
        double snapped = SnapPx(y, stepPx);
        int minFromViewStart = (int)Math.Round(snapped / RowHeight * 30.0);
        var dt = day.Date.AddHours(StartHour).AddMinutes(minFromViewStart);
        return new DateTimeOffset(DateTime.SpecifyKind(dt, DateTimeKind.Local)).ToUnixTimeMilliseconds();
    }

    /// <summary>Minute-precise Y (px) of a worklog's start within its day column.</summary>
    private double YForMs(long ms, int day)
    {
        var local = DateTimeOffset.FromUnixTimeMilliseconds(ms).LocalDateTime;
        var dayStart = WeekStart.AddDays(day).Date;
        double minFromViewStart = (local - dayStart).TotalMinutes - StartHour * 60;
        return minFromViewStart / 30.0 * RowHeight;
    }

    private static long ToMs(DateTime d) =>
        new DateTimeOffset(DateTime.SpecifyKind(d.Date, DateTimeKind.Local)).ToUnixTimeMilliseconds();

    private static string FormatDayHeader(int idx, DateTime d)
    {
        var names = new[] { "Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb" };
        var months = new[] { "Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic" };
        return $"{names[(int)d.DayOfWeek]} {d.Day}/{months[d.Month - 1]}";
    }

    private string SlotLabel(int slot)
    {
        int totalMin = StartHour * 60 + slot * 30;
        return $"{totalMin / 60:00}:{totalMin % 60:00}";
    }

    private static string FormatTotal(int sec)
    {
        if (sec <= 0) return "-";
        int h = sec / 3600, m = (sec % 3600) / 60;
        if (h > 0 && m > 0) return $"{h}h {m}m";
        if (h > 0) return $"{h}h";
        return $"{m}m";
    }

    private string FormatDiff(int sec)
    {
        var target = (Settings?.DailyTargetHours ?? 8) * 3600;
        var diff = sec - target;
        if (Math.Abs(diff) < 1) return "";
        var sign = diff > 0 ? "+" : "-";
        int abs = (int)Math.Abs(diff);
        int h = abs / 3600, m = (abs % 3600) / 60;
        string body = (h > 0 ? $"{h}h" : "") + (m > 0 ? (h > 0 ? " " : "") + $"{m}m" : "");
        return $"({sign}{body})";
    }

    private static string FormatTimeRange(long startMs, int durationSec)
    {
        var s = DateTimeOffset.FromUnixTimeMilliseconds(startMs).LocalDateTime;
        var e = s.AddSeconds(durationSec);
        return $"{s:HH:mm} - {e:HH:mm} ({FormatTotal(durationSec)})";
    }

    private static string FormatTimeShort(long ms) =>
        DateTimeOffset.FromUnixTimeMilliseconds(ms).LocalDateTime.ToString("HH:mm");

    private static SolidColorBrush NeutralBrush(double alpha) =>
        new(Color.FromArgb((byte)Math.Clamp(alpha * 255, 0, 255), 255, 255, 255));

    private static SolidColorBrush AccentBrush(double alpha)
    {
        var c = (Color)Application.Current.Resources["SystemAccentColor"];
        return new SolidColorBrush(Color.FromArgb((byte)Math.Clamp(alpha * 255, 0, 255), c.R, c.G, c.B));
    }

    private static bool TryParseHex(string hex, out Color col)
    {
        col = Colors.Transparent;
        if (string.IsNullOrEmpty(hex)) return false;
        var s = hex.StartsWith("#") ? hex.Substring(1) : hex;
        if (s.Length == 6 && byte.TryParse(s.Substring(0, 2), System.Globalization.NumberStyles.HexNumber, null, out var r)
                          && byte.TryParse(s.Substring(2, 2), System.Globalization.NumberStyles.HexNumber, null, out var g)
                          && byte.TryParse(s.Substring(4, 2), System.Globalization.NumberStyles.HexNumber, null, out var b))
        { col = Color.FromArgb(255, r, g, b); return true; }
        return false;
    }
}

/// <summary>
/// A ContentPresenter that can swap its pointer cursor. UIElement
/// .ProtectedCursor is only settable from a subclass and the obvious
/// candidate (Border) is sealed in WinUI 3, so we subclass
/// ContentPresenter — same Background / BorderBrush / BorderThickness /
/// CornerRadius / Padding / Content surface.
/// </summary>
public sealed class CursorBorder : Microsoft.UI.Xaml.Controls.ContentPresenter
{
    private Microsoft.UI.Input.InputSystemCursorShape? _current;

    public void SetCursorShape(Microsoft.UI.Input.InputSystemCursorShape shape)
    {
        if (_current == shape) return;
        _current = shape;
        this.ProtectedCursor = Microsoft.UI.Input.InputSystemCursor.Create(shape);
    }
}
