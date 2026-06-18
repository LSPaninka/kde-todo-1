using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Net.Http;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using WorklogCalendar.Models;

namespace WorklogCalendar.Services;

/// <summary>
/// Port of <c>ClockifyStore.qml</c>. Reads / writes time entries against
/// https://api.clockify.me/api/v1. Auth: X-Api-Key header.
/// </summary>
public sealed class ClockifyStore : INotifyPropertyChanged
{
    private const string BaseUrl = "https://api.clockify.me/api/v1";
    private static readonly Regex ObjectIdRx = new("^[0-9a-fA-F]{24}$", RegexOptions.Compiled);

    private readonly AppSettings _settings;
    private readonly HttpClient _http;

    public ClockifyStore(AppSettings settings)
    {
        _settings = settings;
        _http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
    }

    public string WorkspaceId { get; private set; } = "";
    public string UserId { get; private set; } = "";

    public IReadOnlyList<ClockifyProject> Projects { get; private set; } = Array.Empty<ClockifyProject>();
    public IReadOnlyList<ClockifyTag> Tags { get; private set; } = Array.Empty<ClockifyTag>();
    public IReadOnlyList<ClockifyEntry> Entries { get; private set; } = Array.Empty<ClockifyEntry>();

    private bool _loading;
    public bool Loading { get => _loading; private set { _loading = value; Raise(); } }

    private string _lastError = "";
    public string LastError { get => _lastError; private set { _lastError = value; Raise(); } }

    public DateTime LastFetchedAt { get; private set; } = DateTime.MinValue;
    public int TotalCount => Entries.Count;

    private readonly StringBuilder _log = new();
    public string DebugLog => _log.ToString();
    public bool HasDebugLog => _log.Length > 0;

    public bool Ready => !string.IsNullOrWhiteSpace(_settings.ClockifyApiKey);

    public void Init()
    {
        var w = (_settings.ClockifyWorkspaceId ?? "").Trim();
        var u = (_settings.ClockifyUserId ?? "").Trim();
        WorkspaceId = ObjectIdRx.IsMatch(w) ? w : "";
        UserId = ObjectIdRx.IsMatch(u) ? u : "";
        Log($"init: workspace={(WorkspaceId.Length == 0 ? "(empty)" : WorkspaceId)} user={(UserId.Length == 0 ? "(empty)" : UserId)} hasKey={Ready}");
    }

    public async Task<bool> EnsureContextAsync()
    {
        if (!Ready)
        {
            LastError = "Falta la API key de Clockify. Configurala en la pestaña Clockify.";
            Warn("API key vacía.");
            return false;
        }
        // Refresh from settings, validating Object IDs.
        var rw = (_settings.ClockifyWorkspaceId ?? "").Trim();
        var ru = (_settings.ClockifyUserId ?? "").Trim();
        WorkspaceId = ObjectIdRx.IsMatch(rw) ? rw : "";
        UserId = ObjectIdRx.IsMatch(ru) ? ru : "";

        if (!string.IsNullOrEmpty(WorkspaceId) && !string.IsNullOrEmpty(UserId) && Projects.Count > 0)
            return true;

        Log("Resolviendo usuario + workspace + proyectos…");
        var (code, body) = await SendAsync("GET", $"{BaseUrl}/user", null);
        if (code != 200) { LastError = $"HTTP {code} contra /user."; Warn($"GET /user exit={code}: {Trim(body, 200)}"); return false; }

        try
        {
            using var doc = JsonDocument.Parse(body);
            var root = doc.RootElement;
            UserId = root.TryGetProperty("id", out var idE) ? idE.GetString() ?? "" : "";
            if (!ObjectIdRx.IsMatch(WorkspaceId))
            {
                if (root.TryGetProperty("defaultWorkspace", out var dwE)) WorkspaceId = dwE.GetString() ?? "";
                if (!ObjectIdRx.IsMatch(WorkspaceId) && root.TryGetProperty("activeWorkspace", out var awE))
                    WorkspaceId = awE.GetString() ?? "";
            }
            _settings.ClockifyUserId = UserId;
            _settings.ClockifyWorkspaceId = WorkspaceId;
            SettingsService.Save(_settings);

            if (!ObjectIdRx.IsMatch(WorkspaceId))
            {
                LastError = "No pude resolver un workspace válido — /user no devolvió defaultWorkspace.";
                Warn(LastError);
                return false;
            }
            Log($"user={UserId} workspace={WorkspaceId}");
        }
        catch (Exception ex)
        {
            LastError = "Respuesta inválida de /user.";
            Warn("parse /user: " + ex);
            return false;
        }

        if (!await LoadProjectsAsync()) return false;
        await LoadTagsAsync();
        return true;
    }

    private async Task<bool> LoadProjectsAsync()
    {
        var (code, body) = await SendAsync("GET", $"{BaseUrl}/workspaces/{WorkspaceId}/projects?archived=false&page-size=200", null);
        if (code != 200) { Warn($"GET projects exit={code}"); return false; }
        try
        {
            using var doc = JsonDocument.Parse(body);
            var list = new List<ClockifyProject>();
            foreach (var p in doc.RootElement.EnumerateArray())
            {
                list.Add(new ClockifyProject
                {
                    Id = p.TryGetProperty("id", out var idE) ? idE.GetString() ?? "" : "",
                    Name = p.TryGetProperty("name", out var nE) ? nE.GetString() ?? "" : "",
                    Color = p.TryGetProperty("color", out var cE) ? cE.GetString() ?? "" : "",
                    Billable = p.TryGetProperty("billable", out var bE) && bE.ValueKind == JsonValueKind.True
                });
            }
            Projects = list;
            Raise(nameof(Projects));
            Log($"Proyectos cargados: {list.Count}");
            return true;
        }
        catch (Exception ex) { Warn("parse projects: " + ex); return false; }
    }

    private async Task LoadTagsAsync()
    {
        var (code, body) = await SendAsync("GET", $"{BaseUrl}/workspaces/{WorkspaceId}/tags?archived=false&page-size=200", null);
        if (code != 200) { Warn($"GET tags exit={code}"); Tags = Array.Empty<ClockifyTag>(); Raise(nameof(Tags)); return; }
        try
        {
            using var doc = JsonDocument.Parse(body);
            var list = new List<ClockifyTag>();
            foreach (var t in doc.RootElement.EnumerateArray())
            {
                list.Add(new ClockifyTag
                {
                    Id = t.TryGetProperty("id", out var idE) ? idE.GetString() ?? "" : "",
                    Name = t.TryGetProperty("name", out var nE) ? nE.GetString() ?? "" : ""
                });
            }
            Tags = list;
            Raise(nameof(Tags));
            Log($"Tags cargados: {list.Count}");
        }
        catch (Exception ex) { Warn("parse tags: " + ex); Tags = Array.Empty<ClockifyTag>(); Raise(nameof(Tags)); }
    }

    public async Task<bool> FetchWeekAsync(DateTime weekStart)
    {
        if (Loading) { Warn("[abort] ya hay un fetch en curso."); return false; }
        AppendDebug($"=== Clockify fetch {DateTime.Now:yyyy-MM-dd HH:mm:ss} ===\n");
        Loading = true;
        LastError = "";
        try
        {
            if (!await EnsureContextAsync()) return false;
            var startMs = weekStart.Date;
            var endMs = startMs.AddDays(7);
            var url = $"{BaseUrl}/workspaces/{WorkspaceId}/user/{UserId}/time-entries" +
                      $"?start={Uri.EscapeDataString(ToUtcIso(startMs))}" +
                      $"&end={Uri.EscapeDataString(ToUtcIso(endMs))}" +
                      "&page-size=200";
            Log("GET " + url);
            var (code, body) = await SendAsync("GET", url, null);
            if (code != 200)
            {
                LastError = $"HTTP {code} al traer time entries.";
                Warn($"time-entries exit={code}: {Trim(body, 240)}");
                return false;
            }
            return ProcessEntries(body);
        }
        finally
        {
            Loading = false;
            LastFetchedAt = DateTime.Now;
        }
    }

    /// <summary>
    /// Sum the user's Clockify time entries per day-of-month for the
    /// monthly heatmap. Paginated. Returns { day(1..31) =&gt; seconds }.
    /// </summary>
    public async Task<Dictionary<int, int>> FetchMonthTotalsAsync(int year, int monthIndex)
    {
        var totals = new Dictionary<int, int>();
        if (!await EnsureContextAsync()) return totals;

        var startD = new DateTime(year, monthIndex + 1, 1, 0, 0, 0, DateTimeKind.Local);
        var endD = startD.AddMonths(1);
        const int pageSize = 200;
        int page = 1;
        while (true)
        {
            var url = $"{BaseUrl}/workspaces/{WorkspaceId}/user/{UserId}/time-entries" +
                      $"?start={Uri.EscapeDataString(ToUtcIso(startD))}" +
                      $"&end={Uri.EscapeDataString(ToUtcIso(endD))}" +
                      $"&page-size={pageSize}&page={page}";
            Log("Month(Clockify) GET " + url);
            var (code, body) = await SendAsync("GET", url, null);
            if (code != 200) { Warn($"month totals exit={code}: {Trim(body, 200)}"); break; }
            int count;
            try
            {
                using var doc = JsonDocument.Parse(body);
                count = doc.RootElement.GetArrayLength();
                foreach (var e in doc.RootElement.EnumerateArray())
                {
                    if (!e.TryGetProperty("timeInterval", out var ti)) continue;
                    var startS = ti.TryGetProperty("start", out var sE) ? sE.GetString() : null;
                    var endS = ti.TryGetProperty("end", out var eE) && eE.ValueKind == JsonValueKind.String ? eE.GetString() : null;
                    if (string.IsNullOrEmpty(startS) || string.IsNullOrEmpty(endS)) continue;
                    if (!DateTimeOffset.TryParse(startS, out var sd) || !DateTimeOffset.TryParse(endS, out var ed)) continue;
                    if (ed <= sd) continue;
                    var local = sd.ToLocalTime();
                    if (local.Year != year || local.Month != monthIndex + 1) continue;
                    int day = local.Day;
                    int sec = (int)Math.Round((ed - sd).TotalSeconds);
                    totals[day] = (totals.TryGetValue(day, out var cur) ? cur : 0) + sec;
                }
            }
            catch (Exception ex) { Warn("month parse: " + ex); break; }
            if (count >= pageSize) { page++; continue; }
            Log($"Month(Clockify) {monthIndex + 1}/{year}: {totals.Count} day(s) with entries.");
            break;
        }
        return totals;
    }

    private bool ProcessEntries(string body)
    {
        try
        {
            using var doc = JsonDocument.Parse(body);
            var list = new List<ClockifyEntry>();
            foreach (var e in doc.RootElement.EnumerateArray())
            {
                if (!e.TryGetProperty("timeInterval", out var ti)) continue;
                var startS = ti.TryGetProperty("start", out var sE) ? sE.GetString() : null;
                var endS = ti.TryGetProperty("end", out var eE) && eE.ValueKind == JsonValueKind.String ? eE.GetString() : null;
                if (string.IsNullOrEmpty(startS) || string.IsNullOrEmpty(endS)) continue;
                if (!DateTimeOffset.TryParse(startS, out var sd) || !DateTimeOffset.TryParse(endS, out var ed)) continue;
                if (ed <= sd) continue;
                var entry = new ClockifyEntry
                {
                    Id = e.TryGetProperty("id", out var idE) ? idE.GetString() ?? "" : "",
                    StartedUnixMs = sd.ToUnixTimeMilliseconds(),
                    DurationSec = (int)Math.Round((ed - sd).TotalSeconds),
                    Description = e.TryGetProperty("description", out var dE) ? dE.GetString() ?? "" : "",
                    ProjectId = e.TryGetProperty("projectId", out var pE) && pE.ValueKind == JsonValueKind.String ? pE.GetString() ?? "" : "",
                    Billable = e.TryGetProperty("billable", out var bE) && bE.ValueKind == JsonValueKind.True
                };
                var proj = ProjectById(entry.ProjectId);
                entry.ProjectName = proj?.Name ?? "";
                entry.ProjectColor = proj?.Color ?? "";
                if (e.TryGetProperty("tagIds", out var tagsE) && tagsE.ValueKind == JsonValueKind.Array)
                {
                    foreach (var t in tagsE.EnumerateArray())
                        if (t.ValueKind == JsonValueKind.String) entry.TagIds.Add(t.GetString() ?? "");
                    entry.TagNames = TagNamesFromIds(entry.TagIds);
                }
                list.Add(entry);
            }
            list.Sort((a, b) => a.StartedUnixMs.CompareTo(b.StartedUnixMs));
            Entries = list;
            Raise(nameof(Entries));
            Raise(nameof(TotalCount));
            Log($"Entries: {list.Count}.");
            return true;
        }
        catch (Exception ex)
        {
            LastError = "Error parseando la respuesta: " + ex.Message;
            Warn("parse entries: " + ex);
            return false;
        }
    }

    private ClockifyProject? ProjectById(string id)
    {
        if (string.IsNullOrEmpty(id)) return null;
        foreach (var p in Projects) if (p.Id == id) return p;
        return null;
    }
    private List<string> TagNamesFromIds(IEnumerable<string> ids)
    {
        var out_ = new List<string>();
        foreach (var id in ids) foreach (var t in Tags) if (t.Id == id) { out_.Add(t.Name); break; }
        return out_;
    }

    // ----- CRUD ------------------------------------------------------------

    public async Task<(bool ok, string err)> CreateEntryAsync(DateTime start, DateTime end, string description, string? projectId, IEnumerable<string>? tagIds, bool billable)
    {
        if (!ContextReady(out var err1)) return (false, err1);
        var url = $"{BaseUrl}/workspaces/{WorkspaceId}/time-entries";
        var body = BuildEntryBody(start, end, description, projectId, tagIds, billable, false);
        Log("POST " + url + " body=" + body);
        var (code, resp) = await SendAsync("POST", url, body);
        if (code is >= 200 and < 300) return (true, "");
        var msg = ExtractError(resp);
        Warn($"create exit={code}: {msg}");
        return (false, $"HTTP {code}: {msg}");
    }

    public async Task<(bool ok, string err)> UpdateEntryAsync(string entryId, DateTime start, DateTime end, string description, string? projectId, IEnumerable<string>? tagIds, bool billable)
    {
        if (!ContextReady(out var err1)) return (false, err1);
        var url = $"{BaseUrl}/workspaces/{WorkspaceId}/time-entries/{Uri.EscapeDataString(entryId)}";
        var body = BuildEntryBody(start, end, description, projectId, tagIds, billable, true);
        Log("PUT " + url + " body=" + body);
        var (code, resp) = await SendAsync("PUT", url, body);
        if (code is >= 200 and < 300) return (true, "");
        var msg = ExtractError(resp);
        Warn($"update exit={code}: {msg}");
        return (false, $"HTTP {code}: {msg}");
    }

    public async Task<(bool ok, string err)> DeleteEntryAsync(string entryId)
    {
        if (!ContextReady(out var err1)) return (false, err1);
        var url = $"{BaseUrl}/workspaces/{WorkspaceId}/time-entries/{Uri.EscapeDataString(entryId)}";
        Log("DELETE " + url);
        var (code, resp) = await SendAsync("DELETE", url, null);
        if (code is 200 or 204) return (true, "");
        var msg = ExtractError(resp);
        Warn($"delete exit={code}: {msg}");
        return (false, $"HTTP {code}: {msg}");
    }

    private bool ContextReady(out string err)
    {
        if (string.IsNullOrEmpty(WorkspaceId) || string.IsNullOrEmpty(UserId))
        {
            err = "Llamá EnsureContextAsync() (o sincronizá) primero.";
            return false;
        }
        err = "";
        return true;
    }

    private static string BuildEntryBody(DateTime start, DateTime end, string description, string? projectId, IEnumerable<string>? tagIds, bool billable, bool includeEmptyTags)
    {
        var d = new Dictionary<string, object?>
        {
            ["start"] = ToUtcIso(start),
            ["end"] = ToUtcIso(end),
            ["description"] = description ?? "",
            ["billable"] = billable
        };
        if (!string.IsNullOrEmpty(projectId)) d["projectId"] = projectId;
        var list = new List<string>();
        if (tagIds != null) list.AddRange(tagIds);
        if (list.Count > 0 || includeEmptyTags) d["tagIds"] = list;
        return JsonSerializer.Serialize(d);
    }

    // ----- Sync from Jira --------------------------------------------------

    /// <summary>
    /// For each Jira worklog: if a Clockify entry already exists with the
    /// SAME description on that same calendar day, decide whether it's
    /// already in sync (skip) or needs to be re-aligned (update its start +
    /// duration). Only when there's no description match on that day do we
    /// create a fresh entry. This avoids the old behaviour where bumping a
    /// Jira worklog by 10 minutes produced a duplicate Clockify entry next
    /// to the original one.
    /// </summary>
    public async Task<(int created, int updated, int skipped, int failed)> SyncFromJiraAsync(
        IReadOnlyList<JiraWorklog> jiraWorklogs, string? defaultProjectId, bool defaultBillable)
    {
        if (jiraWorklogs.Count == 0) return (0, 0, 0, 0);
        if (!await EnsureContextAsync()) return (0, 0, 0, 0);

        var toCreate = new List<(DateTime start, DateTime end, string desc)>();
        var toUpdate = new List<(ClockifyEntry existing, DateTime start, DateTime end)>();
        int skipped = 0;
        // Per-day match index — first wins. Mark a matched entry so a
        // second Jira worklog with the same description on the same day
        // (rare but possible) doesn't fight over it.
        var consumed = new HashSet<string>();

        foreach (var j in jiraWorklogs)
        {
            var desc = j.IssueKey + (string.IsNullOrEmpty(j.IssueSummary) ? "" : ": " + j.IssueSummary);
            var jStart = DateTimeOffset.FromUnixTimeMilliseconds(j.StartedUnixMs).LocalDateTime;
            var jDay = jStart.Date;

            ClockifyEntry? match = null;
            foreach (var c in Entries)
            {
                if (consumed.Contains(c.Id)) continue;
                if (c.Description != desc) continue;
                var cDay = DateTimeOffset.FromUnixTimeMilliseconds(c.StartedUnixMs).LocalDateTime.Date;
                if (cDay != jDay) continue;
                match = c; break;
            }

            if (match != null)
            {
                consumed.Add(match.Id);
                bool sameStart = Math.Abs(match.StartedUnixMs - j.StartedUnixMs) <= 60_000;
                bool sameDur   = Math.Abs(match.DurationSec - j.DurationSec) <= 60;
                if (sameStart && sameDur) { skipped++; continue; }
                toUpdate.Add((match, jStart, jStart.AddSeconds(j.DurationSec)));
            }
            else
            {
                toCreate.Add((jStart, jStart.AddSeconds(j.DurationSec), desc));
            }
        }
        Log($"Sync: create={toCreate.Count} update={toUpdate.Count} skip={skipped}");

        int created = 0, updated = 0, failed = 0;
        foreach (var (exist, st, en) in toUpdate)
        {
            // Preserve the existing project / tags / billable so we only
            // re-align the time window — the user already set those.
            var (ok, err) = await UpdateEntryAsync(exist.Id, st, en, exist.Description,
                string.IsNullOrEmpty(exist.ProjectId) ? null : exist.ProjectId,
                exist.TagIds, exist.Billable);
            if (ok) updated++;
            else { failed++; Warn($"Sync update failed ({exist.Description}) — {err}"); }
        }
        foreach (var (start, end, desc) in toCreate)
        {
            var (ok, err) = await CreateEntryAsync(start, end, desc, defaultProjectId, null, defaultBillable);
            if (ok) created++;
            else { failed++; Warn($"Sync create failed ({desc}) — {err}"); }
        }
        return (created, updated, skipped, failed);
    }

    // ----- Helpers ---------------------------------------------------------

    private async Task<(int code, string body)> SendAsync(string method, string url, string? body)
    {
        var key = (_settings.ClockifyApiKey ?? "").Trim();
        if (string.IsNullOrEmpty(key)) { Warn("_send abortado: no hay API key."); return (0, ""); }
        using var req = new HttpRequestMessage(new HttpMethod(method), url);
        req.Headers.Add("X-Api-Key", key);
        req.Headers.Add("Accept", "application/json");
        if (body != null) req.Content = new StringContent(body, Encoding.UTF8, "application/json");
        try
        {
            using var resp = await _http.SendAsync(req);
            var text = await resp.Content.ReadAsStringAsync();
            return ((int)resp.StatusCode, text);
        }
        catch (Exception ex) { Warn("http: " + ex.Message); return (0, ""); }
    }

    private static string ToUtcIso(DateTime d)
    {
        var u = DateTime.SpecifyKind(d, d.Kind == DateTimeKind.Unspecified ? DateTimeKind.Local : d.Kind).ToUniversalTime();
        return u.ToString("yyyy-MM-ddTHH:mm:ss.fffZ");
    }

    private static string ExtractError(string body)
    {
        if (string.IsNullOrEmpty(body)) return "";
        try
        {
            using var d = JsonDocument.Parse(body);
            if (d.RootElement.TryGetProperty("message", out var m)) return m.GetString() ?? "";
            if (d.RootElement.TryGetProperty("error", out var e)) return e.ValueKind == JsonValueKind.String ? e.GetString() ?? "" : e.ToString();
        }
        catch { /* not json */ }
        return Trim(body, 240);
    }

    private static string Trim(string s, int n) => s.Length <= n ? s : s.Substring(0, n);

    // ----- Logging ---------------------------------------------------------

    public void ClearDebugLog() { _log.Clear(); Raise(nameof(DebugLog)); Raise(nameof(HasDebugLog)); }

    private void Log(string msg)
    {
        AppendDebug(msg + "\n");
        if (_settings.ClockifyDebug) System.Diagnostics.Debug.WriteLine("[Clockify] " + msg);
    }
    private void Warn(string msg)
    {
        AppendDebug("[!] " + msg + "\n");
        System.Diagnostics.Debug.WriteLine("[Clockify] " + msg);
    }
    private void AppendDebug(string s)
    {
        const int max = 80000;
        if (_log.Length + s.Length > max)
        {
            var keep = _log.ToString().Substring(_log.Length / 2);
            _log.Clear();
            _log.Append("[…log truncado…]\n").Append(keep);
        }
        _log.Append(s);
        Raise(nameof(DebugLog));
        Raise(nameof(HasDebugLog));
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string name = "") =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
