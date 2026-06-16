using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.System;
using Windows.UI;
using WorklogCalendar.Models;
using WorklogCalendar.Services;

namespace WorklogCalendar.Controls;

/// <summary>
/// Third bottom-panel view (rings / subtasks / heatmap). Port of
/// <c>SubtaskTable.qml</c>. Renders JiraStore.Subtasks as a sortable
/// table with optional inline filter; left-click on a row raises
/// <see cref="SubtaskActivated"/>; right-click shows a context menu
/// with "Cambiar estado" (transitions fetched lazily) and "Ver en Jira".
/// </summary>
public sealed partial class SubtaskTableControl : UserControl
{
    public event Action<JiraSubtask>? SubtaskActivated;
    public event Action<string>? OpenInJiraRequested;
    public event Action<JiraSubtask, string /*transitionId*/>? TransitionRequested;

    private JiraWorklogStore? _store;
    private AppSettings? _settings;
    private string _sortKey = "";
    private bool _sortAsc = true;
    private bool _searchOpen;
    private string _searchText = "";
    private static readonly FontFamily SegoeMdl2 = new("Segoe MDL2 Assets");

    public SubtaskTableControl()
    {
        this.InitializeComponent();
        SearchBtn.Click += (s, e) => ToggleSearch();
        SearchBox.TextChanged += (s, e) => { _searchText = SearchBox.Text ?? ""; Rebuild(); };
        SearchBox.KeyDown += (s, e) =>
        {
            if (e.Key == VirtualKey.Escape) { SearchBox.Text = ""; ToggleSearch(); e.Handled = true; }
        };
        RefreshBtn.Click += async (s, e) => await Refresh();

        // Clickable headers.
        AttachSortHandler(HSubtarea, "key");
        AttachSortHandler(HEstado, "status");
        AttachSortHandler(HDisp, "remaining");
        AttachSortHandler(HPadre, "parent");
    }

    public AppSettings? Settings
    {
        get => _settings;
        set { _settings = value; ApplyParentColumnVisibility(); Rebuild(); }
    }

    public JiraWorklogStore? Store
    {
        get => _store;
        set
        {
            if (_store != null) _store.PropertyChanged -= OnStoreChanged;
            _store = value;
            if (_store != null) _store.PropertyChanged += OnStoreChanged;
            Rebuild();
        }
    }

    private void OnStoreChanged(object? s, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(JiraWorklogStore.Subtasks))
            DispatcherQueue.TryEnqueue(Rebuild);
    }

    /// <summary>Public hook for the parent — calls FetchSubtasksAsync.</summary>
    public async Task Refresh()
    {
        if (_store == null) return;
        await _store.FetchSubtasksAsync();
    }

    private void ToggleSearch()
    {
        _searchOpen = !_searchOpen;
        SearchBox.Visibility = _searchOpen ? Visibility.Visible : Visibility.Collapsed;
        SearchBtn.IsChecked = _searchOpen;
        if (!_searchOpen) { _searchText = ""; SearchBox.Text = ""; }
        else SearchBox.Focus(FocusState.Programmatic);
        Rebuild();
    }

    private void ApplyParentColumnVisibility()
    {
        bool show = _settings?.SubtaskShowParent ?? true;
        // The header column is part of a Grid with 5 ColumnDefinitions; we
        // just toggle the visibility of the parent header — the body rows
        // honor the same flag.
        HPadre.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
    }

    private void AttachSortHandler(TextBlock header, string key)
    {
        header.Tag = key;
        header.PointerEntered += (s, e) => header.Opacity = 0.95;
        header.PointerExited += (s, e) => header.Opacity = _sortKey == key ? 0.9 : 0.6;
        header.Tapped += (s, e) =>
        {
            if (_sortKey == key) _sortAsc = !_sortAsc;
            else { _sortKey = key; _sortAsc = true; }
            Rebuild();
        };
    }

    private static string SortGlyph(bool active, bool asc) =>
        !active ? "" : (asc ? "  ▲" : "  ▼");   // ▲ / ▼

    private IEnumerable<JiraSubtask> Filtered()
    {
        var src = (IEnumerable<JiraSubtask>?)_store?.Subtasks ?? Array.Empty<JiraSubtask>();
        var q = (_searchText ?? "").Trim().ToLowerInvariant();
        if (!string.IsNullOrEmpty(q))
        {
            src = src.Where(r =>
            {
                var hay = ($"{r.Key} {r.Summary} {r.Status} {r.ParentKey} {r.ParentSummary}").ToLowerInvariant();
                return hay.Contains(q);
            });
        }
        if (string.IsNullOrEmpty(_sortKey)) return src;
        var cmp = StringComparer.OrdinalIgnoreCase;
        return _sortKey switch
        {
            "remaining" => _sortAsc ? src.OrderBy(r => r.RemainingSec) : src.OrderByDescending(r => r.RemainingSec),
            "status"    => _sortAsc ? src.OrderBy(r => r.Status, cmp) : src.OrderByDescending(r => r.Status, cmp),
            "parent"    => _sortAsc ? src.OrderBy(r => r.ParentKey, cmp) : src.OrderByDescending(r => r.ParentKey, cmp),
            _           => _sortAsc ? src.OrderBy(r => r.Key, cmp) : src.OrderByDescending(r => r.Key, cmp),
        };
    }

    private void Rebuild()
    {
        if (RowsHost == null) return;
        ApplyParentColumnVisibility();
        // Header glyphs
        HSubtarea.Text = "Subtarea" + SortGlyph(_sortKey == "key", _sortAsc);
        HEstado.Text   = "Estado"   + SortGlyph(_sortKey == "status", _sortAsc);
        HDisp.Text     = "Disp."    + SortGlyph(_sortKey == "remaining", _sortAsc);
        HPadre.Text    = "Padre"    + SortGlyph(_sortKey == "parent", _sortAsc);

        var rows = Filtered().ToList();
        CountLabel.Text = rows.Count > 0 ? $"({rows.Count})" : "";
        RowsHost.Items.Clear();
        bool showParent = _settings?.SubtaskShowParent ?? true;
        foreach (var r in rows) RowsHost.Items.Add(BuildRow(r, showParent));

        EmptyLabel.Visibility = rows.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private Border BuildRow(JiraSubtask r, bool showParent)
    {
        var grid = new Grid { Padding = new Thickness(4, 3, 4, 3), ColumnSpacing = 6 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(110) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(70) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(16) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(showParent ? 90 : 0) });

        // Code + summary
        var codeBox = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, VerticalAlignment = VerticalAlignment.Center };
        codeBox.Children.Add(new TextBlock
        {
            Text = r.Key,
            FontFamily = new FontFamily("Consolas"),
            FontWeight = FontWeights.Bold
        });
        codeBox.Children.Add(new TextBlock
        {
            Text = r.Summary,
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center
        });
        Grid.SetColumn(codeBox, 0);
        grid.Children.Add(codeBox);

        // Status badge
        var badge = new Border
        {
            Background = new SolidColorBrush(StatusBg(r.StatusColor)),
            CornerRadius = new CornerRadius(9),
            Height = 20,
            Padding = new Thickness(8, 0, 8, 0),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            VerticalAlignment = VerticalAlignment.Center,
            Child = new TextBlock
            {
                Text = r.Status,
                Foreground = new SolidColorBrush(Color.FromArgb(255, 26, 26, 26)),
                FontSize = 11,
                FontWeight = FontWeights.Bold,
                TextAlignment = TextAlignment.Center,
                TextTrimming = TextTrimming.CharacterEllipsis,
                HorizontalAlignment = HorizontalAlignment.Stretch,
                VerticalAlignment = VerticalAlignment.Center
            }
        };
        Grid.SetColumn(badge, 1);
        grid.Children.Add(badge);

        // Remaining hours
        var disp = new TextBlock
        {
            Text = FmtHours(r.RemainingSec),
            FontFamily = new FontFamily("Consolas"),
            TextAlignment = TextAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(disp, 2);
        grid.Children.Add(disp);

        // Parent
        if (showParent)
        {
            var parentLbl = new TextBlock
            {
                Text = r.ParentKey,
                FontFamily = new FontFamily("Consolas"),
                Opacity = string.IsNullOrEmpty(r.ParentKey) ? 0.35 : 0.85,
                TextTrimming = TextTrimming.CharacterEllipsis,
                VerticalAlignment = VerticalAlignment.Center
            };
            if (!string.IsNullOrEmpty(r.ParentSummary))
                ToolTipService.SetToolTip(parentLbl, $"{r.ParentKey} — {r.ParentSummary}");
            Grid.SetColumn(parentLbl, 4);
            grid.Children.Add(parentLbl);
        }

        var rowBg = new Border
        {
            Background = new SolidColorBrush(Colors.Transparent),
            CornerRadius = new CornerRadius(2),
            Child = grid
        };
        rowBg.PointerEntered += (s, e) => rowBg.Background = new SolidColorBrush(Color.FromArgb(0x10, 0xFF, 0xFF, 0xFF));
        rowBg.PointerExited += (s, e) => rowBg.Background = new SolidColorBrush(Colors.Transparent);
        rowBg.Tapped += (s, e) => SubtaskActivated?.Invoke(r);
        rowBg.RightTapped += async (s, e) => { e.Handled = true; await ShowRowMenu(rowBg, r); };
        return rowBg;
    }

    private async Task ShowRowMenu(FrameworkElement anchor, JiraSubtask row)
    {
        var menu = new MenuFlyout();
        var stateItem = new MenuFlyoutSubItem { Text = "Cambiar estado" };
        var loading = new MenuFlyoutItem { Text = "Cargando…", IsEnabled = false };
        stateItem.Items.Add(loading);
        menu.Items.Add(stateItem);
        menu.Items.Add(new MenuFlyoutSeparator());
        var verEnJira = new MenuFlyoutItem { Text = "Ver en Jira" };
        verEnJira.Click += (s, e) => OpenInJiraRequested?.Invoke(row.Key);
        menu.Items.Add(verEnJira);

        menu.ShowAt(anchor);

        if (_store == null) return;
        var transitions = await _store.FetchTransitionsAsync(row.Key);
        stateItem.Items.Clear();
        if (transitions.Count == 0)
        {
            stateItem.Items.Add(new MenuFlyoutItem { Text = "(sin transiciones)", IsEnabled = false });
            return;
        }
        foreach (var t in transitions)
        {
            string label = !string.IsNullOrEmpty(t.ToStatus) ? $"{t.Name} → {t.ToStatus}" : t.Name;
            var item = new MenuFlyoutItem { Text = label };
            var captured = t;
            item.Click += (s, e) =>
            {
                TransitionRequested?.Invoke(row, captured.Id);
                menu.Hide();
            };
            stateItem.Items.Add(item);
        }
    }

    // ---- Helpers ----------------------------------------------------------

    private static string FmtHours(int sec)
    {
        if (sec <= 0) return "—";   // em-dash
        int h = sec / 3600, m = (sec % 3600) / 60;
        if (h > 0 && m > 0) return $"{h}h {m}m";
        if (h > 0) return $"{h}h";
        return $"{m}m";
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
