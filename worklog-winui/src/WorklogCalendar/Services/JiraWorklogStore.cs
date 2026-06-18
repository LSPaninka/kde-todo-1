using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using WorklogCalendar.Models;

namespace WorklogCalendar.Services;

/// <summary>
/// Port of <c>JiraWorklogStore.qml</c>. Talks to Jira Cloud REST v3:
///   - GET    /rest/api/3/myself                 (resolve accountId)
///   - GET    /rest/api/3/search/jql             (week worklogs + picker)
///   - POST/PUT/DELETE /rest/api/3/issue/&lt;key&gt;/worklog[/&lt;id&gt;]
/// Auth: HTTP Basic with email + API token.
/// </summary>
public sealed class JiraWorklogStore : INotifyPropertyChanged
{
    private readonly AppSettings _settings;
    private readonly HttpClient _http;

    public JiraWorklogStore(AppSettings settings)
    {
        _settings = settings;
        _http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
    }

    // ----- Public state ----------------------------------------------------

    public IReadOnlyList<JiraWorklog> Worklogs { get; private set; } = Array.Empty<JiraWorklog>();
    public IReadOnlyList<JiraIssue> AssignableIssues { get; private set; } = Array.Empty<JiraIssue>();
    /// <summary>Subtasks for the bottom-panel table, filled by FetchSubtasksAsync.</summary>
    public IReadOnlyList<JiraSubtask> Subtasks { get; private set; } = Array.Empty<JiraSubtask>();
    public string MyAccountId { get; private set; } = "";

    // ----- Sprint (powers the SprintGauges control) -----
    public JiraSprint? CurrentSprint { get; private set; }
    public int SprintAvailableSec { get; private set; }
    public int SprintConsumedSec { get; private set; }
    /// <summary>Per-issue breakdown of the available hours (remaining &gt; 0), sorted desc.</summary>
    public IReadOnlyList<SprintAvailableItem> SprintAvailableBreakdown { get; private set; } = Array.Empty<SprintAvailableItem>();

    private bool _loading;
    public bool Loading { get => _loading; private set { _loading = value; Raise(); } }

    private string _lastError = "";
    public string LastError { get => _lastError; private set { _lastError = value; Raise(); } }

    public DateTime LastFetchedAt { get; private set; } = DateTime.MinValue;
    public DateTime CurrentWeekStart { get; private set; }

    private readonly StringBuilder _log = new();
    public string DebugLog => _log.ToString();
    public bool HasDebugLog => _log.Length > 0;

    public int TotalCount => Worklogs.Count;

    // ----- Public API ------------------------------------------------------

    public async Task<bool> FetchWeekAsync(DateTime weekStart)
    {
        if (Loading) { Warn("[abort] ya hay un fetch en curso."); return false; }
        if (!HasCredentials(out var creds))
        {
            LastError = "Faltan credenciales (sitio, email o token). Configurá la pestaña Jira.";
            return false;
        }

        AppendDebug($"=== Worklog fetch {DateTime.Now:yyyy-MM-dd HH:mm:ss} ===\n");
        CurrentWeekStart = weekStart.Date;
        var weekEnd = CurrentWeekStart.AddDays(7);

        Loading = true;
        LastError = "";
        try
        {
            if (string.IsNullOrEmpty(MyAccountId))
            {
                Log("GET /rest/api/3/myself (cacheamos accountId)");
                var (code, body) = await SendAsync("GET", $"{creds.Site}/rest/api/3/myself", null);
                if (code != 200)
                {
                    LastError = $"No se pudo obtener el usuario actual (HTTP {code}).";
                    Warn($"myself exit={code}: {Trim(body, 200)}");
                    return false;
                }
                try
                {
                    using var d = JsonDocument.Parse(body);
                    MyAccountId = d.RootElement.TryGetProperty("accountId", out var a) ? (a.GetString() ?? "") : "";
                    Log($"accountId = {MyAccountId}");
                }
                catch (Exception ex)
                {
                    LastError = "Respuesta inválida de /myself.";
                    Warn("parse myself: " + ex.Message);
                    return false;
                }
            }

            var jql = $"worklogAuthor = currentUser() AND worklogDate >= \"{FormatJqlDate(CurrentWeekStart)}\" AND worklogDate <= \"{FormatJqlDate(weekEnd.AddDays(-1))}\"";
            var url = $"{creds.Site}/rest/api/3/search/jql?jql={Uri.EscapeDataString(jql)}&maxResults=200&fields=summary,worklog";
            Log("GET " + url);
            var (code2, body2) = await SendAsync("GET", url, null);
            if (code2 != 200)
            {
                LastError = $"HTTP {code2} al buscar issues con worklogs.";
                Warn($"search exit={code2}: {Trim(body2, 300)}");
                return false;
            }
            return ProcessWeekResponse(body2, CurrentWeekStart, weekEnd);
        }
        catch (Exception ex)
        {
            LastError = "Error de red: " + ex.Message;
            Warn("FetchWeek exception: " + ex);
            return false;
        }
        finally
        {
            Loading = false;
            LastFetchedAt = DateTime.Now;
        }
    }

    private bool ProcessWeekResponse(string body, DateTime weekStart, DateTime weekEnd)
    {
        try
        {
            using var doc = JsonDocument.Parse(body);
            var root = doc.RootElement;
            var out_ = new List<JiraWorklog>();
            if (root.TryGetProperty("issues", out var issues) && issues.ValueKind == JsonValueKind.Array)
            {
                long startMs = ToUnixMs(weekStart);
                long endMs = ToUnixMs(weekEnd);
                foreach (var iss in issues.EnumerateArray())
                {
                    string issueId = iss.TryGetProperty("id", out var idE) ? idE.GetString() ?? "" : "";
                    string issueKey = iss.TryGetProperty("key", out var keyE) ? keyE.GetString() ?? "" : "";
                    string summary = "";
                    if (iss.TryGetProperty("fields", out var fields))
                    {
                        if (fields.TryGetProperty("summary", out var sE)) summary = sE.GetString() ?? "";
                        if (fields.TryGetProperty("worklog", out var wlC) &&
                            wlC.TryGetProperty("worklogs", out var wlA) &&
                            wlA.ValueKind == JsonValueKind.Array)
                        {
                            foreach (var w in wlA.EnumerateArray())
                            {
                                long started = ParseJiraDate(w.TryGetProperty("started", out var stE) ? stE.GetString() ?? "" : "");
                                if (started < startMs || started >= endMs) continue;
                                if (!string.IsNullOrEmpty(MyAccountId) && w.TryGetProperty("author", out var au))
                                {
                                    var aid = au.TryGetProperty("accountId", out var aidE) ? aidE.GetString() ?? "" : "";
                                    if (!string.IsNullOrEmpty(aid) && aid != MyAccountId) continue;
                                }
                                int dur = w.TryGetProperty("timeSpentSeconds", out var dE) ? dE.GetInt32() : 0;
                                string wid = w.TryGetProperty("id", out var widE) ? widE.GetString() ?? "" : "";
                                string comment = "";
                                if (w.TryGetProperty("comment", out var cE)) comment = ExtractAdfText(cE);
                                out_.Add(new JiraWorklog
                                {
                                    Id = wid, IssueId = issueId, IssueKey = issueKey, IssueSummary = summary,
                                    StartedUnixMs = started, DurationSec = dur, Comment = comment
                                });
                            }
                        }
                    }
                }
            }
            out_.Sort((a, b) => a.StartedUnixMs.CompareTo(b.StartedUnixMs));
            Worklogs = out_;
            Log($"Recibí {out_.Count} worklog(s) propios en la semana.");
            Raise(nameof(Worklogs));
            Raise(nameof(TotalCount));
            return true;
        }
        catch (Exception ex)
        {
            LastError = "Error parseando la respuesta: " + ex.Message;
            Warn("parse: " + ex);
            return false;
        }
    }

    public async Task<bool> FetchAssignableIssuesAsync()
    {
        if (!HasCredentials(out var creds)) return false;
        var jql = string.IsNullOrWhiteSpace(_settings.JiraIssueJql)
            ? "assignee = currentUser() AND statusCategory != Done"
            : _settings.JiraIssueJql.Trim();
        var max = Math.Clamp(_settings.JiraIssueMax, 10, 200);
        // timeestimate = remaining estimate (seconds); timetracking is the
        // human-readable variant; we keep both for resilience across Jira
        // instances, plus timeoriginalestimate for the "calculated" mode.
        var url = $"{creds.Site}/rest/api/3/search/jql?jql={Uri.EscapeDataString(jql)}&maxResults={max}&fields=summary,status,issuetype,timeoriginalestimate,timeestimate,timetracking";
        Log("Picker GET " + url);
        var (code, body) = await SendAsync("GET", url, null);
        if (code != 200) { Warn($"Picker exit={code}: {Trim(body, 200)}"); return false; }
        try
        {
            using var doc = JsonDocument.Parse(body);
            var list = new List<JiraIssue>();
            if (doc.RootElement.TryGetProperty("issues", out var arr) && arr.ValueKind == JsonValueKind.Array)
            {
                foreach (var r in arr.EnumerateArray())
                {
                    var it = new JiraIssue
                    {
                        Key = r.TryGetProperty("key", out var kE) ? kE.GetString() ?? "" : ""
                    };
                    if (r.TryGetProperty("fields", out var f))
                    {
                        it.Summary = f.TryGetProperty("summary", out var sE) ? sE.GetString() ?? "" : "";
                        if (f.TryGetProperty("issuetype", out var tE) &&
                            tE.TryGetProperty("name", out var tnE)) it.IssueType = tnE.GetString() ?? "";
                        if (f.TryGetProperty("status", out var stE) &&
                            stE.TryGetProperty("name", out var snE)) it.Status = snE.GetString() ?? "";
                        it.RemainingSec = RemainingSec(f);
                    }
                    list.Add(it);
                }
            }
            AssignableIssues = list;
            Raise(nameof(AssignableIssues));
            Log($"Picker: {list.Count} issue(s).");
            return true;
        }
        catch (Exception ex)
        {
            Warn("Picker parse: " + ex);
            return false;
        }
    }

    // -----------------------------------------------------------------------
    // Sprint info (powers the SprintGauges control)
    // -----------------------------------------------------------------------
    // Three strategies (configurable via _settings.SprintStrategy):
    //
    //   "subtask-customfield" (default): query subtasks assigned to me
    //     with the sprint custom field (customfield_10020 on most Jira
    //     instances) and pick the entry with state="active". Works even
    //     when parent stories are unassigned and only the subtasks belong
    //     to the user.
    //
    //   "agile-board": fetch the active sprint of a specific board via
    //     /rest/agile/1.0/board/{id}/sprint?state=active. Requires the
    //     board id in _settings.SprintBoardId.
    //
    //   "assignee-jql": original behavior, "sprint in openSprints() AND
    //     assignee = currentUser()". Kept as a fallback.

    public async Task<bool> FetchSprintInfoAsync()
    {
        if (!HasCredentials(out var creds)) return false;
        if (string.IsNullOrEmpty(MyAccountId))
        {
            // Resolve accountId once — required by the consumed-by-me filter.
            var (mcode, mbody) = await SendAsync("GET", $"{creds.Site}/rest/api/3/myself", null);
            if (mcode == 200)
            {
                try
                {
                    using var d = JsonDocument.Parse(mbody);
                    MyAccountId = d.RootElement.TryGetProperty("accountId", out var a) ? (a.GetString() ?? "") : "";
                }
                catch { /* swallow */ }
            }
        }
        var strategy = (_settings.SprintStrategy ?? "subtask-customfield").ToLowerInvariant();
        Log("Sprint strategy: " + strategy);
        return strategy switch
        {
            "agile-board" => await FetchSprintAgileBoardAsync(creds),
            "assignee-jql" => await FetchSprintAssigneeJqlAsync(creds),
            _ => await FetchSprintSubtaskFieldAsync(creds)
        };
    }

    private async Task<bool> FetchSprintSubtaskFieldAsync(Creds creds)
    {
        var field = string.IsNullOrEmpty(_settings.SprintField) ? "customfield_10020" : _settings.SprintField;
        var jql = "issuetype in subTaskIssueTypes() AND assignee = currentUser()";
        var url = $"{creds.Site}/rest/api/3/search/jql?jql={Uri.EscapeDataString(jql)}" +
                  $"&maxResults=200&fields=summary,worklog,timeoriginalestimate,timeestimate,timetracking,{Uri.EscapeDataString(field)}";
        Log("Sprint(subtask) GET " + url);
        var (code, body) = await SendAsync("GET", url, null);
        if (code != 200) { Warn($"subtask-customfield exit={code}: {Trim(body, 240)}"); ClearSprint(); return false; }
        try
        {
            using var doc = JsonDocument.Parse(body);
            if (!doc.RootElement.TryGetProperty("issues", out var issues) || issues.ValueKind != JsonValueKind.Array)
            { ClearSprint(); return true; }
            Log($"subtask-customfield: {issues.GetArrayLength()} subtarea(s) recibidas.");
            if (issues.GetArrayLength() == 0) { ClearSprint(); return true; }

            var active = FindActiveSprintIn(issues, field);
            if (active == null)
            {
                Warn($"Ningún sprint activo en el campo '{field}' de las subtareas. ¿Cambió el id del custom field?");
                ClearSprint();
                return true;
            }
            SetActiveSprint(active);
            ComputeSprintTotalsFromIssues(issues, active, field);
            return true;
        }
        catch (Exception ex) { Warn("subtask-customfield parse: " + ex); ClearSprint(); return false; }
    }

    private async Task<bool> FetchSprintAgileBoardAsync(Creds creds)
    {
        var boardId = _settings.SprintBoardId;
        if (boardId <= 0)
        {
            Warn("agile-board: 'Board ID' no configurado.");
            ClearSprint();
            return false;
        }
        var url = $"{creds.Site}/rest/agile/1.0/board/{boardId}/sprint?state=active";
        Log("Sprint(agile) GET " + url);
        var (code, body) = await SendAsync("GET", url, null);
        if (code != 200) { Warn($"agile-board sprint list exit={code}: {Trim(body, 240)}"); ClearSprint(); return false; }
        try
        {
            using var doc = JsonDocument.Parse(body);
            if (!doc.RootElement.TryGetProperty("values", out var values) || values.ValueKind != JsonValueKind.Array || values.GetArrayLength() == 0)
            {
                Log($"agile-board: el board {boardId} no tiene sprints activos.");
                ClearSprint();
                return true;
            }
            var active = ParseSprintElement(values[0]);
            SetActiveSprint(active);

            var jql2 = $"sprint = {active.Id} AND assignee = currentUser()";
            var url2 = $"{creds.Site}/rest/api/3/search/jql?jql={Uri.EscapeDataString(jql2)}" +
                       "&maxResults=200&fields=summary,worklog,timeoriginalestimate,timeestimate,timetracking";
            Log("Sprint(agile) issues GET " + url2);
            var (c2, b2) = await SendAsync("GET", url2, null);
            if (c2 != 200)
            {
                Warn($"agile-board issues exit={c2}: {Trim(b2, 240)}");
                SprintAvailableSec = 0; SprintConsumedSec = 0;
                Raise(nameof(SprintAvailableSec)); Raise(nameof(SprintConsumedSec));
                return true;
            }
            try
            {
                using var d2 = JsonDocument.Parse(b2);
                if (d2.RootElement.TryGetProperty("issues", out var iss2))
                    ComputeSprintTotalsFromIssues(iss2, active, null);
                return true;
            }
            catch (Exception ex) { Warn("agile-board issues parse: " + ex); return false; }
        }
        catch (Exception ex) { Warn("agile-board parse: " + ex); ClearSprint(); return false; }
    }

    private async Task<bool> FetchSprintAssigneeJqlAsync(Creds creds)
    {
        var field = string.IsNullOrEmpty(_settings.SprintField) ? "customfield_10020" : _settings.SprintField;
        var jql = "sprint in openSprints() AND assignee = currentUser()";
        var url = $"{creds.Site}/rest/api/3/search/jql?jql={Uri.EscapeDataString(jql)}" +
                  $"&maxResults=200&fields=summary,worklog,timeoriginalestimate,timeestimate,timetracking,{Uri.EscapeDataString(field)}";
        Log("Sprint(assignee) GET " + url);
        var (code, body) = await SendAsync("GET", url, null);
        if (code != 200) { Warn($"assignee-jql exit={code}: {Trim(body, 240)}"); ClearSprint(); return false; }
        try
        {
            using var doc = JsonDocument.Parse(body);
            if (!doc.RootElement.TryGetProperty("issues", out var issues) || issues.GetArrayLength() == 0)
            { ClearSprint(); return true; }
            var active = FindActiveSprintIn(issues, field);
            if (active == null) { ClearSprint(); return true; }
            SetActiveSprint(active);
            ComputeSprintTotalsFromIssues(issues, active, field);
            return true;
        }
        catch (Exception ex) { Warn("assignee-jql parse: " + ex); ClearSprint(); return false; }
    }

    /// <summary>Scan issues' sprint custom-field arrays for the first one in state=active.</summary>
    private static JiraSprint? FindActiveSprintIn(JsonElement issues, string field)
    {
        foreach (var iss in issues.EnumerateArray())
        {
            if (!iss.TryGetProperty("fields", out var f)) continue;
            if (!f.TryGetProperty(field, out var arrE)) continue;
            // The field can be an array (most common) or a single object on
            // older Jira instances.
            if (arrE.ValueKind == JsonValueKind.Array)
            {
                foreach (var s in arrE.EnumerateArray())
                {
                    if (IsActive(s)) return ParseSprintElement(s);
                }
            }
            else if (arrE.ValueKind == JsonValueKind.Object && IsActive(arrE))
            {
                return ParseSprintElement(arrE);
            }
        }
        return null;
    }

    private static bool IsActive(JsonElement s)
    {
        if (!s.TryGetProperty("state", out var stE)) return false;
        var st = (stE.GetString() ?? "").ToLowerInvariant();
        return st == "active";
    }

    private static JiraSprint ParseSprintElement(JsonElement s) => new()
    {
        Id = s.TryGetProperty("id", out var idE) && idE.ValueKind == JsonValueKind.Number ? idE.GetInt64() : 0,
        Name = s.TryGetProperty("name", out var nE) ? nE.GetString() ?? "" : "",
        StartDate = s.TryGetProperty("startDate", out var sdE) ? sdE.GetString() ?? "" : "",
        EndDate = s.TryGetProperty("endDate", out var edE) ? edE.GetString() ?? "" : ""
    };

    private void SetActiveSprint(JiraSprint s)
    {
        CurrentSprint = s;
        Raise(nameof(CurrentSprint));
    }

    private void ClearSprint()
    {
        CurrentSprint = null;
        SprintAvailableSec = 0;
        SprintConsumedSec = 0;
        SprintAvailableBreakdown = Array.Empty<SprintAvailableItem>();
        Raise(nameof(CurrentSprint));
        Raise(nameof(SprintAvailableSec));
        Raise(nameof(SprintConsumedSec));
        Raise(nameof(SprintAvailableBreakdown));
    }

    /// <summary>
    /// Sum the current user's Jira worklogs per day-of-month for the
    /// monthly heatmap. Returns { day(1..31) =&gt; seconds }.
    /// </summary>
    public async Task<Dictionary<int, int>> FetchMonthTotalsAsync(int year, int monthIndex)
    {
        var totals = new Dictionary<int, int>();
        if (!HasCredentials(out var creds)) return totals;

        var startD = new DateTime(year, monthIndex + 1, 1);
        var endD = startD.AddMonths(1).AddDays(-1);                 // last day of month
        long startMs = ToUnixMs(startD);
        long endMs = ToUnixMs(startD.AddMonths(1));                 // first of next

        if (string.IsNullOrEmpty(MyAccountId))
        {
            var (mc, mb) = await SendAsync("GET", $"{creds.Site}/rest/api/3/myself", null);
            if (mc == 200)
            {
                try { using var d = JsonDocument.Parse(mb); MyAccountId = d.RootElement.TryGetProperty("accountId", out var a) ? a.GetString() ?? "" : ""; }
                catch { /* swallow */ }
            }
        }

        var jql = $"worklogAuthor = currentUser() AND worklogDate >= \"{FormatJqlDate(startD)}\" AND worklogDate <= \"{FormatJqlDate(endD)}\"";
        var url = $"{creds.Site}/rest/api/3/search/jql?jql={Uri.EscapeDataString(jql)}&maxResults=200&fields=worklog";
        Log("Month(Jira) GET " + url);
        var (code, body) = await SendAsync("GET", url, null);
        if (code != 200) { Warn($"month totals exit={code}: {Trim(body, 200)}"); return totals; }
        try
        {
            using var doc = JsonDocument.Parse(body);
            if (doc.RootElement.TryGetProperty("issues", out var issues) && issues.ValueKind == JsonValueKind.Array)
            {
                foreach (var iss in issues.EnumerateArray())
                {
                    if (!iss.TryGetProperty("fields", out var f)) continue;
                    if (!f.TryGetProperty("worklog", out var wlC) ||
                        !wlC.TryGetProperty("worklogs", out var wls) || wls.ValueKind != JsonValueKind.Array) continue;
                    foreach (var w in wls.EnumerateArray())
                    {
                        var startedStr = w.TryGetProperty("started", out var stE) ? stE.GetString() ?? "" : "";
                        if (!DateTimeOffset.TryParse(startedStr, out var dto)) continue;
                        long ms = dto.ToUnixTimeMilliseconds();
                        if (ms < startMs || ms >= endMs) continue;
                        if (!string.IsNullOrEmpty(MyAccountId) && w.TryGetProperty("author", out var au))
                        {
                            var aid = au.TryGetProperty("accountId", out var aidE) ? aidE.GetString() ?? "" : "";
                            if (!string.IsNullOrEmpty(aid) && aid != MyAccountId) continue;
                        }
                        int day = dto.ToLocalTime().Day;
                        int sec = w.TryGetProperty("timeSpentSeconds", out var dE) && dE.ValueKind == JsonValueKind.Number ? dE.GetInt32() : 0;
                        totals[day] = (totals.TryGetValue(day, out var cur) ? cur : 0) + sec;
                    }
                }
            }
            Log($"Month(Jira) {monthIndex + 1}/{year}: {totals.Count} day(s) with worklogs.");
        }
        catch (Exception ex) { Warn("month parse: " + ex); }
        return totals;
    }

    /// <summary>
    /// Remaining seconds per issue. "api" trusts Jira's
    /// remainingEstimateSeconds; "calculated" uses
    /// max(0, originalEstimate - timeSpent) which is what users want when
    /// remainingEstimate hasn't been kept up to date.
    /// </summary>
    private int RemainingSec(JsonElement f)
    {
        var mode = (_settings.RemainingMode ?? "api").ToLowerInvariant();
        if (mode == "calculated")
        {
            int orig = 0, spent = 0;
            if (f.TryGetProperty("timeoriginalestimate", out var oE) && oE.ValueKind == JsonValueKind.Number) orig = oE.GetInt32();
            if (f.TryGetProperty("timetracking", out var tt))
            {
                if (orig == 0 && tt.TryGetProperty("originalEstimateSeconds", out var oo) && oo.ValueKind == JsonValueKind.Number) orig = oo.GetInt32();
                if (tt.TryGetProperty("timeSpentSeconds", out var ss) && ss.ValueKind == JsonValueKind.Number) spent = ss.GetInt32();
            }
            return Math.Max(0, orig - spent);
        }
        // "api"
        if (f.TryGetProperty("timetracking", out var tt2) &&
            tt2.TryGetProperty("remainingEstimateSeconds", out var rE) && rE.ValueKind == JsonValueKind.Number)
            return rE.GetInt32();
        if (f.TryGetProperty("timeestimate", out var teE) && teE.ValueKind == JsonValueKind.Number) return teE.GetInt32();
        return 0;
    }

    /// <summary>
    /// If <paramref name="fieldOrNull"/> is non-null, only issues whose
    /// sprint custom-field array contains <c>active.Id</c> are counted.
    /// Otherwise the caller has already filtered (e.g. via "sprint = N" JQL).
    /// </summary>
    private void ComputeSprintTotalsFromIssues(JsonElement issues, JiraSprint active, string? fieldOrNull)
    {
        long sStart = DateTimeOffset.TryParse(active.StartDate, out var sd) ? sd.ToUnixTimeMilliseconds() : 0;
        long sEnd = DateTimeOffset.TryParse(active.EndDate, out var ed) ? ed.ToUnixTimeMilliseconds() : long.MaxValue;
        int available = 0, consumed = 0;
        var breakdown = new List<SprintAvailableItem>();
        foreach (var iss in issues.EnumerateArray())
        {
            if (!iss.TryGetProperty("fields", out var f)) continue;
            if (fieldOrNull != null)
            {
                bool hit = false;
                if (f.TryGetProperty(fieldOrNull, out var arrE))
                {
                    if (arrE.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var s in arrE.EnumerateArray())
                        {
                            if (s.TryGetProperty("id", out var idE) && idE.ValueKind == JsonValueKind.Number && idE.GetInt64() == active.Id) { hit = true; break; }
                        }
                    }
                    else if (arrE.ValueKind == JsonValueKind.Object &&
                             arrE.TryGetProperty("id", out var idE2) && idE2.ValueKind == JsonValueKind.Number && idE2.GetInt64() == active.Id)
                        hit = true;
                }
                if (!hit) continue;
            }
            int rem = RemainingSec(f);
            available += rem;
            if (rem > 0)
            {
                breakdown.Add(new SprintAvailableItem
                {
                    Key = iss.TryGetProperty("key", out var kE) ? kE.GetString() ?? "" : "",
                    Summary = f.TryGetProperty("summary", out var sE) ? sE.GetString() ?? "" : "",
                    RemainingSec = rem
                });
            }

            if (f.TryGetProperty("worklog", out var wlC) &&
                wlC.TryGetProperty("worklogs", out var wls) && wls.ValueKind == JsonValueKind.Array)
            {
                foreach (var w in wls.EnumerateArray())
                {
                    var startedStr = w.TryGetProperty("started", out var stE) ? stE.GetString() ?? "" : "";
                    if (!DateTimeOffset.TryParse(startedStr, out var dto)) continue;
                    long ms = dto.ToUnixTimeMilliseconds();
                    if (ms < sStart || ms > sEnd) continue;
                    if (!string.IsNullOrEmpty(MyAccountId) && w.TryGetProperty("author", out var au))
                    {
                        var aid = au.TryGetProperty("accountId", out var aidE) ? aidE.GetString() ?? "" : "";
                        if (!string.IsNullOrEmpty(aid) && aid != MyAccountId) continue;
                    }
                    if (w.TryGetProperty("timeSpentSeconds", out var dE) && dE.ValueKind == JsonValueKind.Number)
                        consumed += dE.GetInt32();
                }
            }
        }
        breakdown.Sort((a, b) => b.RemainingSec.CompareTo(a.RemainingSec));
        SprintAvailableSec = available;
        SprintConsumedSec = consumed;
        SprintAvailableBreakdown = breakdown;
        Raise(nameof(SprintAvailableSec));
        Raise(nameof(SprintConsumedSec));
        Raise(nameof(SprintAvailableBreakdown));
        Log($"Sprint '{active.Name}': remaining={available}s, consumed={consumed}s, breakdown={breakdown.Count} issue(s).");
    }

    public async Task<(bool ok, string err)> CreateWorklogAsync(string issueKey, DateTime started, int durationSec, string comment)
    {
        if (!HasCredentials(out var creds)) return (false, "Faltan credenciales.");
        var url = $"{creds.Site}/rest/api/3/issue/{Uri.EscapeDataString(issueKey)}/worklog";
        var body = BuildWorklogBody(started, durationSec, comment);
        Log("POST " + url + " body=" + body);
        var (code, resp) = await SendAsync("POST", url, body);
        if (code is 200 or 201) { Log("create OK."); return (true, ""); }
        var msg = ExtractError(resp);
        Warn($"create exit={code}: {msg}");
        return (false, $"HTTP {code}: {msg}");
    }

    public async Task<(bool ok, string err)> UpdateWorklogAsync(string issueKey, string worklogId, DateTime started, int durationSec, string comment)
    {
        if (!HasCredentials(out var creds)) return (false, "Faltan credenciales.");
        var url = $"{creds.Site}/rest/api/3/issue/{Uri.EscapeDataString(issueKey)}/worklog/{Uri.EscapeDataString(worklogId)}";
        var body = BuildWorklogBody(started, durationSec, comment);
        Log("PUT " + url + " body=" + body);
        var (code, resp) = await SendAsync("PUT", url, body);
        if (code == 200) { Log("update OK."); return (true, ""); }
        var msg = ExtractError(resp);
        Warn($"update exit={code}: {msg}");
        return (false, $"HTTP {code}: {msg}");
    }

    /// <summary>
    /// Optimistic local update: mutate the in-memory worklog and raise
    /// PropertyChanged so the UI reflects the move immediately without
    /// waiting for the next FetchWeek. Without this, a drag-to-move could
    /// "snap back" because the post-update Refresh ran with stale store
    /// data while the refetch was still in flight (or had been cached by
    /// Jira and returned the old position briefly).
    /// </summary>
    public void UpdateLocalWorklog(string worklogId, DateTime newStarted, int newDurationSec)
    {
        if (string.IsNullOrEmpty(worklogId)) return;
        var list = new List<JiraWorklog>(Worklogs);
        bool changed = false;
        for (int i = 0; i < list.Count; i++)
        {
            if (list[i].Id != worklogId) continue;
            var w = list[i];
            list[i] = new JiraWorklog
            {
                Id = w.Id,
                IssueId = w.IssueId,
                IssueKey = w.IssueKey,
                IssueSummary = w.IssueSummary,
                StartedUnixMs = new DateTimeOffset(DateTime.SpecifyKind(newStarted, DateTimeKind.Local)).ToUnixTimeMilliseconds(),
                DurationSec = newDurationSec,
                Comment = w.Comment
            };
            changed = true;
            break;
        }
        if (!changed) return;
        list.Sort((a, b) => a.StartedUnixMs.CompareTo(b.StartedUnixMs));
        Worklogs = list;
        Raise(nameof(Worklogs));
    }

    public async Task<(bool ok, string err)> DeleteWorklogAsync(string issueKey, string worklogId)
    {
        if (!HasCredentials(out var creds)) return (false, "Faltan credenciales.");
        var url = $"{creds.Site}/rest/api/3/issue/{Uri.EscapeDataString(issueKey)}/worklog/{Uri.EscapeDataString(worklogId)}";
        Log("DELETE " + url);
        var (code, resp) = await SendAsync("DELETE", url, null);
        if (code is 200 or 204) { Log("delete OK."); return (true, ""); }
        var msg = ExtractError(resp);
        Warn($"delete exit={code}: {msg}");
        return (false, $"HTTP {code}: {msg}");
    }

    // -----------------------------------------------------------------------
    // Subtask table (third bottom-panel view)
    // -----------------------------------------------------------------------

    /// <summary>
    /// Populate <see cref="Subtasks"/> with the issues returned by the
    /// configured JQL. Each row carries the fields needed by the table
    /// (key/summary/status/badge color/remaining hours/parent).
    /// </summary>
    public async Task<bool> FetchSubtasksAsync()
    {
        if (!HasCredentials(out var creds)) return false;
        var jql = string.IsNullOrWhiteSpace(_settings.SubtaskJql)
            ? "issuetype in subTaskIssueTypes() AND assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC"
            : _settings.SubtaskJql.Trim();
        var url = $"{creds.Site}/rest/api/3/search/jql?jql={Uri.EscapeDataString(jql)}" +
                  "&maxResults=100&fields=summary,status,parent,timeoriginalestimate,timeestimate,timetracking";
        Log("Subtasks GET " + url);
        var (code, body) = await SendAsync("GET", url, null);
        if (code != 200) { Warn($"Subtasks exit={code}: {Trim(body, 240)}"); return false; }
        try
        {
            using var doc = JsonDocument.Parse(body);
            var list = new List<JiraSubtask>();
            if (doc.RootElement.TryGetProperty("issues", out var arr) && arr.ValueKind == JsonValueKind.Array)
            {
                foreach (var r in arr.EnumerateArray())
                {
                    var it = new JiraSubtask
                    {
                        Key = r.TryGetProperty("key", out var kE) ? kE.GetString() ?? "" : ""
                    };
                    if (r.TryGetProperty("fields", out var f))
                    {
                        it.Summary = f.TryGetProperty("summary", out var sE) ? sE.GetString() ?? "" : "";
                        if (f.TryGetProperty("status", out var stE))
                        {
                            it.Status = stE.TryGetProperty("name", out var snE) ? snE.GetString() ?? "" : "";
                            if (stE.TryGetProperty("statusCategory", out var scE))
                            {
                                it.StatusCategory = scE.TryGetProperty("key", out var sckE) ? sckE.GetString() ?? "" : "";
                                it.StatusColor = scE.TryGetProperty("colorName", out var scnE) ? scnE.GetString() ?? "" : "";
                            }
                        }
                        it.RemainingSec = RemainingSec(f);
                        if (f.TryGetProperty("parent", out var pE) && pE.ValueKind == JsonValueKind.Object)
                        {
                            it.ParentKey = pE.TryGetProperty("key", out var pkE) ? pkE.GetString() ?? "" : "";
                            if (pE.TryGetProperty("fields", out var pfE) &&
                                pfE.TryGetProperty("summary", out var psE))
                                it.ParentSummary = psE.GetString() ?? "";
                        }
                    }
                    list.Add(it);
                }
            }
            Subtasks = list;
            Raise(nameof(Subtasks));
            Log($"Subtasks: {list.Count} row(s).");
            return true;
        }
        catch (Exception ex) { Warn("Subtasks parse: " + ex); return false; }
    }

    /// <summary>GET /rest/api/3/issue/{key}/transitions for the right-click menu.</summary>
    public async Task<List<JiraTransition>> FetchTransitionsAsync(string issueKey)
    {
        var result = new List<JiraTransition>();
        if (!HasCredentials(out var creds)) return result;
        var url = $"{creds.Site}/rest/api/3/issue/{Uri.EscapeDataString(issueKey)}/transitions";
        Log("Transitions GET " + url);
        var (code, body) = await SendAsync("GET", url, null);
        if (code != 200) { Warn($"Transitions exit={code}: {Trim(body, 200)}"); return result; }
        try
        {
            using var doc = JsonDocument.Parse(body);
            if (doc.RootElement.TryGetProperty("transitions", out var arr) && arr.ValueKind == JsonValueKind.Array)
            {
                foreach (var t in arr.EnumerateArray())
                {
                    var tr = new JiraTransition
                    {
                        Id = t.TryGetProperty("id", out var idE) ? (idE.ValueKind == JsonValueKind.Number ? idE.GetInt64().ToString() : idE.GetString() ?? "") : "",
                        Name = t.TryGetProperty("name", out var nE) ? nE.GetString() ?? "" : ""
                    };
                    if (t.TryGetProperty("to", out var to))
                    {
                        tr.ToStatus = to.TryGetProperty("name", out var tnE) ? tnE.GetString() ?? "" : "";
                        if (to.TryGetProperty("statusCategory", out var tscE))
                            tr.ToStatusColor = tscE.TryGetProperty("colorName", out var tcnE) ? tcnE.GetString() ?? "" : "";
                    }
                    result.Add(tr);
                }
            }
            return result;
        }
        catch (Exception ex) { Warn("Transitions parse: " + ex); return result; }
    }

    /// <summary>POST /rest/api/3/issue/{key}/transitions with {transition:{id}}. 204 OK.</summary>
    public async Task<(bool ok, string err)> TransitionIssueAsync(string issueKey, string transitionId)
    {
        if (!HasCredentials(out var creds)) return (false, "Faltan credenciales.");
        var url = $"{creds.Site}/rest/api/3/issue/{Uri.EscapeDataString(issueKey)}/transitions";
        var body = JsonSerializer.Serialize(new { transition = new { id = transitionId } });
        Log("POST " + url + " body=" + body);
        var (code, resp) = await SendAsync("POST", url, body);
        if (code is 200 or 204) { Log("transition OK."); return (true, ""); }
        var msg = ExtractError(resp);
        Warn($"transition exit={code}: {msg}");
        return (false, $"HTTP {code}: {msg}");
    }

    /// <summary>Full issue payload for the subtask detail dialog.</summary>
    public async Task<JiraIssueDetail?> FetchIssueDetailAsync(string issueKey)
    {
        if (!HasCredentials(out var creds)) return null;
        var url = $"{creds.Site}/rest/api/3/issue/{Uri.EscapeDataString(issueKey)}" +
                  "?fields=summary,status,description,parent,issuetype,priority,assignee,reporter," +
                  "timeoriginalestimate,timeestimate,timetracking,timespent,created,updated";
        Log("IssueDetail GET " + url);
        var (code, body) = await SendAsync("GET", url, null);
        if (code != 200) { Warn($"IssueDetail exit={code}: {Trim(body, 200)}"); return null; }
        try
        {
            using var doc = JsonDocument.Parse(body);
            var root = doc.RootElement;
            var d = new JiraIssueDetail
            {
                Key = root.TryGetProperty("key", out var kE) ? kE.GetString() ?? "" : ""
            };
            if (!root.TryGetProperty("fields", out var f)) return d;
            d.Summary = f.TryGetProperty("summary", out var sE) ? sE.GetString() ?? "" : "";
            if (f.TryGetProperty("status", out var stE))
            {
                d.Status = stE.TryGetProperty("name", out var snE) ? snE.GetString() ?? "" : "";
                if (stE.TryGetProperty("statusCategory", out var scE))
                {
                    d.StatusCategory = scE.TryGetProperty("key", out var sckE) ? sckE.GetString() ?? "" : "";
                    d.StatusColor = scE.TryGetProperty("colorName", out var scnE) ? scnE.GetString() ?? "" : "";
                }
            }
            if (f.TryGetProperty("description", out var dE)) d.Description = ExtractAdfText(dE);
            if (f.TryGetProperty("issuetype", out var itE) && itE.TryGetProperty("name", out var itnE)) d.IssueType = itnE.GetString() ?? "";
            if (f.TryGetProperty("priority", out var prE) && prE.TryGetProperty("name", out var prnE)) d.Priority = prnE.GetString() ?? "";
            if (f.TryGetProperty("assignee", out var asE) && asE.ValueKind == JsonValueKind.Object && asE.TryGetProperty("displayName", out var asnE)) d.Assignee = asnE.GetString() ?? "";
            if (f.TryGetProperty("reporter", out var rE) && rE.ValueKind == JsonValueKind.Object && rE.TryGetProperty("displayName", out var rnE)) d.Reporter = rnE.GetString() ?? "";
            if (f.TryGetProperty("parent", out var pE) && pE.ValueKind == JsonValueKind.Object)
            {
                d.ParentKey = pE.TryGetProperty("key", out var pkE) ? pkE.GetString() ?? "" : "";
                if (pE.TryGetProperty("fields", out var pfE) && pfE.TryGetProperty("summary", out var psE)) d.ParentSummary = psE.GetString() ?? "";
            }
            // Time tracking: prefer top-level numbers, fall back to timetracking sub-object.
            int orig = 0, spent = 0;
            if (f.TryGetProperty("timeoriginalestimate", out var oE) && oE.ValueKind == JsonValueKind.Number) orig = oE.GetInt32();
            if (f.TryGetProperty("timespent", out var tsE) && tsE.ValueKind == JsonValueKind.Number) spent = tsE.GetInt32();
            if (f.TryGetProperty("timetracking", out var tt))
            {
                if (orig == 0 && tt.TryGetProperty("originalEstimateSeconds", out var oo) && oo.ValueKind == JsonValueKind.Number) orig = oo.GetInt32();
                if (spent == 0 && tt.TryGetProperty("timeSpentSeconds", out var ss) && ss.ValueKind == JsonValueKind.Number) spent = ss.GetInt32();
            }
            d.OriginalEstimateSec = orig;
            d.SpentSec = spent;
            d.RemainingSec = RemainingSec(f);
            if (f.TryGetProperty("created", out var cE)) d.Created = cE.GetString() ?? "";
            if (f.TryGetProperty("updated", out var uE)) d.Updated = uE.GetString() ?? "";
            return d;
        }
        catch (Exception ex) { Warn("IssueDetail parse: " + ex); return null; }
    }

    /// <summary>Public Jira URL for {site}/browse/{key}.</summary>
    public string IssueWebUrl(string issueKey)
    {
        if (!HasCredentials(out var creds) || string.IsNullOrEmpty(issueKey)) return "";
        return $"{creds.Site}/browse/{Uri.EscapeDataString(issueKey)}";
    }

    // ----- Helpers ---------------------------------------------------------

    private record Creds(string Site, string Email, string Token);

    private bool HasCredentials(out Creds creds)
    {
        var site = (_settings.JiraSite ?? "").Trim().TrimEnd('/');
        var email = (_settings.JiraEmail ?? "").Trim();
        var token = (_settings.JiraToken ?? "").Trim();
        if (site.Length == 0 || email.Length == 0 || token.Length == 0)
        {
            creds = new Creds("", "", "");
            return false;
        }
        creds = new Creds(site, email, token);
        return true;
    }

    private async Task<(int code, string body)> SendAsync(string method, string url, string? body)
    {
        if (!HasCredentials(out var creds)) return (0, "");
        using var req = new HttpRequestMessage(new HttpMethod(method), url);
        var auth = Convert.ToBase64String(Encoding.UTF8.GetBytes($"{creds.Email}:{creds.Token}"));
        req.Headers.Authorization = new AuthenticationHeaderValue("Basic", auth);
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        if (body != null) req.Content = new StringContent(body, Encoding.UTF8, "application/json");
        try
        {
            using var resp = await _http.SendAsync(req);
            var text = await resp.Content.ReadAsStringAsync();
            return ((int)resp.StatusCode, text);
        }
        catch (Exception ex)
        {
            Warn("http: " + ex.Message);
            return (0, "");
        }
    }

    private static string BuildWorklogBody(DateTime started, int durationSec, string comment)
    {
        // Jira wants "2026-05-12T15:00:00.000+0000".
        var off = TimeZoneInfo.Local.GetUtcOffset(started);
        string sign = off >= TimeSpan.Zero ? "+" : "-";
        int absMin = (int)Math.Abs(off.TotalMinutes);
        string startedIso = started.ToString("yyyy-MM-ddTHH:mm:ss.fff") + sign + (absMin / 60).ToString("00") + (absMin % 60).ToString("00");

        var obj = new Dictionary<string, object?>
        {
            ["started"] = startedIso,
            ["timeSpentSeconds"] = durationSec,
        };
        if (!string.IsNullOrEmpty(comment))
        {
            obj["comment"] = new
            {
                type = "doc",
                version = 1,
                content = new[]
                {
                    new { type = "paragraph", content = new[] { new { type = "text", text = comment } } }
                }
            };
        }
        return JsonSerializer.Serialize(obj);
    }

    private static string FormatJqlDate(DateTime d) => d.ToString("yyyy-MM-dd");

    private static long ParseJiraDate(string s)
    {
        if (string.IsNullOrEmpty(s)) return 0;
        if (DateTimeOffset.TryParse(s, out var dto)) return dto.ToUnixTimeMilliseconds();
        return 0;
    }

    private static long ToUnixMs(DateTime localDate)
    {
        var dt = DateTime.SpecifyKind(localDate, DateTimeKind.Local);
        return new DateTimeOffset(dt).ToUnixTimeMilliseconds();
    }

    private static string ExtractAdfText(JsonElement adf)
    {
        if (adf.ValueKind == JsonValueKind.String) return adf.GetString() ?? "";
        if (adf.ValueKind != JsonValueKind.Object) return "";
        if (adf.TryGetProperty("type", out var tE))
        {
            var type = tE.GetString();
            if (type == "text" && adf.TryGetProperty("text", out var txt)) return txt.GetString() ?? "";
        }
        if (adf.TryGetProperty("content", out var cArr) && cArr.ValueKind == JsonValueKind.Array)
        {
            var sb = new StringBuilder();
            foreach (var ch in cArr.EnumerateArray())
            {
                sb.Append(ExtractAdfText(ch));
                if (ch.TryGetProperty("type", out var ct) && ct.GetString() == "paragraph") sb.Append('\n');
            }
            return sb.ToString();
        }
        return "";
    }

    private static string ExtractError(string body)
    {
        if (string.IsNullOrEmpty(body)) return "";
        try
        {
            using var d = JsonDocument.Parse(body);
            if (d.RootElement.TryGetProperty("errorMessages", out var em) && em.ValueKind == JsonValueKind.Array)
            {
                var parts = new List<string>();
                foreach (var v in em.EnumerateArray()) parts.Add(v.GetString() ?? "");
                if (parts.Count > 0) return string.Join("; ", parts);
            }
            if (d.RootElement.TryGetProperty("errors", out var er) && er.ValueKind == JsonValueKind.Object)
            {
                var parts = new List<string>();
                foreach (var p in er.EnumerateObject()) parts.Add($"{p.Name}: {p.Value}");
                if (parts.Count > 0) return string.Join("; ", parts);
            }
            if (d.RootElement.TryGetProperty("message", out var msg)) return msg.GetString() ?? "";
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
        if (_settings.JiraDebug) System.Diagnostics.Debug.WriteLine("[JiraWorklog] " + msg);
    }
    private void Warn(string msg)
    {
        AppendDebug("[!] " + msg + "\n");
        System.Diagnostics.Debug.WriteLine("[JiraWorklog] " + msg);
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
