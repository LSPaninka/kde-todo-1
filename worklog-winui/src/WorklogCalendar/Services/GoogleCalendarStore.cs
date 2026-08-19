using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using WorklogCalendar.Models;

namespace WorklogCalendar.Services;

/// <summary>
/// Port of <c>GoogleCalendarStore.qml</c>. Read-only client for the Google
/// Calendar API v3 — renders calendar events as immovable background blocks
/// on the worklog grid so you can see your meetings while logging time.
///
/// Auth: OAuth 2.0 using the "TV and Limited Input devices" client type. The
/// one-time device-code authorization (run from Settings → Google) yields a
/// refresh token; this store exchanges it for short-lived access tokens at
/// runtime. Nothing is ever written back to Google — only the
/// calendar.readonly scope is requested.
///
/// Endpoints:
///   POST https://oauth2.googleapis.com/device/code            (start auth)
///   POST https://oauth2.googleapis.com/token                  (poll + refresh)
///   GET  https://www.googleapis.com/calendar/v3/users/me/calendarList
///   GET  https://www.googleapis.com/calendar/v3/calendars/{id}/events
/// </summary>
public sealed class GoogleCalendarStore : INotifyPropertyChanged
{
    private const string TokenUrl = "https://oauth2.googleapis.com/token";
    private const string DeviceCodeUrl = "https://oauth2.googleapis.com/device/code";
    private const string CalendarBase = "https://www.googleapis.com/calendar/v3";
    private const string ReadonlyScope = "https://www.googleapis.com/auth/calendar.readonly";

    private readonly AppSettings _settings;
    private readonly HttpClient _http;

    /// <summary>Fallback block colour when a calendar has no configured colour.</summary>
    public const string DefaultColor = "#e74c3c";

    public GoogleCalendarStore(AppSettings settings)
    {
        _settings = settings;
        _http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
    }

    // ----- Public state ----------------------------------------------------

    public IReadOnlyList<GoogleEvent> Events { get; private set; } = Array.Empty<GoogleEvent>();

    private bool _loading;
    public bool Loading { get => _loading; private set { _loading = value; Raise(); } }

    private string _lastError = "";
    public string LastError { get => _lastError; private set { _lastError = value; Raise(); } }

    public DateTime LastFetchedAt { get; private set; } = DateTime.MinValue;
    public int TotalCount => Events.Count;

    /// <summary>True once the user has a client id/secret AND a refresh token.</summary>
    public bool IsAuthorized =>
        !string.IsNullOrWhiteSpace(_settings.GoogleClientId) &&
        !string.IsNullOrWhiteSpace(_settings.GoogleClientSecret) &&
        !string.IsNullOrWhiteSpace(_settings.GoogleRefreshToken);

    private readonly StringBuilder _log = new();
    public string DebugLog => _log.ToString();
    public bool HasDebugLog => _log.Length > 0;

    // Short-lived access token, cached with its expiry. Refreshed when
    // missing or within 60 s of expiring.
    private string _accessToken = "";
    private DateTime _accessTokenExp = DateTime.MinValue;

    // ----- Calendar ids / colours ------------------------------------------

    /// <summary>Up to 3 configured calendar ids (blank entries dropped).</summary>
    public List<string> CalendarIds()
    {
        var outIds = new List<string>();
        foreach (var raw in _settings.GoogleCalendarIds ?? new List<string>())
        {
            var id = (raw ?? "").Trim();
            if (id.Length == 0) continue;
            outIds.Add(id);
            if (outIds.Count >= 3) break;
        }
        return outIds;
    }

    /// <summary>Base colour (hex) configured for a calendar id, or the default.</summary>
    public string ColorFor(string calendarId)
    {
        var ids = _settings.GoogleCalendarIds ?? new List<string>();
        var cols = _settings.GoogleCalendarColors ?? new List<string>();
        for (int i = 0; i < ids.Count; i++)
        {
            if ((ids[i] ?? "").Trim() != calendarId) continue;
            var c = i < cols.Count ? (cols[i] ?? "").Trim() : "";
            return c.Length > 0 ? c : DefaultColor;
        }
        return DefaultColor;
    }

    // ----- Fetch -----------------------------------------------------------

    /// <summary>Load every configured calendar's timed events for the week.</summary>
    public async Task<bool> FetchWeekAsync(DateTime weekStart)
    {
        if (Loading) { Warn("[abort] ya hay un fetch en curso."); return false; }
        if (!_settings.GoogleCalEnabled) { Log("googleCalEnabled=false — no fetch."); return false; }

        AppendDebug($"=== Google fetch {DateTime.Now:yyyy-MM-dd HH:mm:ss} ===\n");
        Loading = true;
        LastError = "";
        try
        {
            var token = await EnsureAccessTokenAsync();
            if (string.IsNullOrEmpty(token)) return false;

            var startD = weekStart.Date;
            var endD = startD.AddDays(7);
            var calIds = CalendarIds();
            if (calIds.Count == 0)
            {
                Events = Array.Empty<GoogleEvent>();
                Raise(nameof(Events));
                return true;
            }

            // Fetch every calendar concurrently, then accumulate.
            var tasks = new List<Task<List<GoogleEvent>>>();
            foreach (var id in calIds) tasks.Add(FetchOneAsync(token, id, startD, endD));
            var results = await Task.WhenAll(tasks);

            var acc = new List<GoogleEvent>();
            foreach (var r in results) acc.AddRange(r);
            acc.Sort((a, b) => a.StartedUnixMs.CompareTo(b.StartedUnixMs));
            Events = acc;
            Raise(nameof(Events));
            Raise(nameof(TotalCount));
            Log($"Eventos totales: {acc.Count} ({calIds.Count} calendario(s)).");
            return true;
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

    private async Task<List<GoogleEvent>> FetchOneAsync(string token, string calId, DateTime startD, DateTime endD)
    {
        var list = new List<GoogleEvent>();
        var url = $"{CalendarBase}/calendars/{Uri.EscapeDataString(calId)}/events" +
                  $"?timeMin={Uri.EscapeDataString(new DateTimeOffset(DateTime.SpecifyKind(startD, DateTimeKind.Local)).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"))}" +
                  $"&timeMax={Uri.EscapeDataString(new DateTimeOffset(DateTime.SpecifyKind(endD, DateTimeKind.Local)).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"))}" +
                  "&singleEvents=true&orderBy=startTime&maxResults=250";
        Log("GET " + url);
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        try
        {
            using var resp = await _http.SendAsync(req);
            var body = await resp.Content.ReadAsStringAsync();
            if (!resp.IsSuccessStatusCode)
            {
                LastError = $"HTTP {(int)resp.StatusCode} al traer eventos de Google ({calId}).";
                Warn($"events[{calId}] exit={(int)resp.StatusCode}: {Trim(body, 240)}");
                return list;
            }

            long weekStartMs = new DateTimeOffset(DateTime.SpecifyKind(startD, DateTimeKind.Local)).ToUnixTimeMilliseconds();
            long weekEndMs = new DateTimeOffset(DateTime.SpecifyKind(endD, DateTimeKind.Local)).ToUnixTimeMilliseconds();

            using var doc = JsonDocument.Parse(body);
            if (!doc.RootElement.TryGetProperty("items", out var items) || items.ValueKind != JsonValueKind.Array)
                return list;
            foreach (var ev in items.EnumerateArray())
            {
                if (ev.TryGetProperty("status", out var stE) && stE.GetString() == "cancelled") continue;
                // Timed events only — all-day entries (date, no dateTime)
                // don't map onto the hour grid.
                if (!ev.TryGetProperty("start", out var sO) || !ev.TryGetProperty("end", out var eO)) continue;
                if (!sO.TryGetProperty("dateTime", out var sDt) || !eO.TryGetProperty("dateTime", out var eDt)) continue;
                if (!DateTimeOffset.TryParse(sDt.GetString(), out var sd)) continue;
                if (!DateTimeOffset.TryParse(eDt.GetString(), out var ed)) continue;
                if (ed <= sd) continue;
                long ms = sd.ToUnixTimeMilliseconds();
                long msEnd = ed.ToUnixTimeMilliseconds();
                if (msEnd <= weekStartMs || ms >= weekEndMs) continue;
                list.Add(new GoogleEvent
                {
                    Id = calId + ":" + (ev.TryGetProperty("id", out var idE) ? idE.GetString() ?? "" : ""),
                    Summary = ev.TryGetProperty("summary", out var suE) ? suE.GetString() ?? "(sin título)" : "(sin título)",
                    StartedUnixMs = ms,
                    DurationSec = (int)Math.Round((ed - sd).TotalSeconds),
                    CalendarId = calId
                });
            }
            Log($"Eventos[{calId}]: {list.Count}.");
        }
        catch (Exception ex) { Warn($"events[{calId}]: {ex.Message}"); }
        return list;
    }

    // ----- OAuth -----------------------------------------------------------

    /// <summary>
    /// Return a valid access token, refreshing through the stored refresh
    /// token when the cached one is missing or about to expire.
    /// </summary>
    public async Task<string> EnsureAccessTokenAsync()
    {
        if (!string.IsNullOrEmpty(_accessToken) && DateTime.UtcNow < _accessTokenExp.AddSeconds(-60))
            return _accessToken;

        if (!IsAuthorized)
        {
            LastError = "Falta autorizar Google Calendar (Configurar → Google).";
            Warn("Faltan credenciales de Google.");
            return "";
        }

        Log("POST oauth2 token (refresh)");
        var form = new Dictionary<string, string>
        {
            ["client_id"] = _settings.GoogleClientId.Trim(),
            ["client_secret"] = _settings.GoogleClientSecret.Trim(),
            ["refresh_token"] = _settings.GoogleRefreshToken.Trim(),
            ["grant_type"] = "refresh_token"
        };
        var (code, body) = await PostFormAsync(TokenUrl, form);
        if (code != 200)
        {
            LastError = $"No se pudo renovar el token de Google (HTTP {code}).";
            Warn($"token refresh exit={code}: {Trim(body, 240)}");
            return "";
        }
        try
        {
            using var d = JsonDocument.Parse(body);
            _accessToken = d.RootElement.TryGetProperty("access_token", out var aE) ? aE.GetString() ?? "" : "";
            int ttl = d.RootElement.TryGetProperty("expires_in", out var tE) && tE.ValueKind == JsonValueKind.Number
                ? tE.GetInt32() : 3600;
            _accessTokenExp = DateTime.UtcNow.AddSeconds(ttl);
            Log($"Access token renovado (expira en {ttl}s).");
            return _accessToken;
        }
        catch (Exception ex) { Warn("token parse: " + ex.Message); return ""; }
    }

    /// <summary>Payload of a started device-code authorization.</summary>
    public sealed class DeviceCodeInfo
    {
        public string DeviceCode { get; set; } = "";
        public string UserCode { get; set; } = "";
        public string VerificationUrl { get; set; } = "";
        public int IntervalSec { get; set; } = 5;
        public int ExpiresInSec { get; set; } = 600;
    }

    /// <summary>Step 1 of the device flow — ask Google for a user code.</summary>
    public async Task<(DeviceCodeInfo? info, string err)> StartDeviceAuthAsync(string clientId)
    {
        var form = new Dictionary<string, string>
        {
            ["client_id"] = clientId.Trim(),
            ["scope"] = ReadonlyScope
        };
        var (code, body) = await PostFormAsync(DeviceCodeUrl, form);
        if (code != 200)
            return (null, $"Error solicitando código (HTTP {code}): {Trim(body, 200)}");
        try
        {
            using var d = JsonDocument.Parse(body);
            var r = d.RootElement;
            var info = new DeviceCodeInfo
            {
                DeviceCode = r.TryGetProperty("device_code", out var dc) ? dc.GetString() ?? "" : "",
                UserCode = r.TryGetProperty("user_code", out var uc) ? uc.GetString() ?? "" : "",
                VerificationUrl = r.TryGetProperty("verification_url", out var vu) ? vu.GetString() ?? ""
                                 : r.TryGetProperty("verification_uri", out var vu2) ? vu2.GetString() ?? "" : "",
                IntervalSec = Math.Max(2, r.TryGetProperty("interval", out var iv) && iv.ValueKind == JsonValueKind.Number ? iv.GetInt32() : 5),
                ExpiresInSec = r.TryGetProperty("expires_in", out var ex) && ex.ValueKind == JsonValueKind.Number ? ex.GetInt32() : 600
            };
            if (string.IsNullOrEmpty(info.VerificationUrl)) info.VerificationUrl = "https://www.google.com/device";
            return (info, "");
        }
        catch (Exception ex) { return (null, "Respuesta inválida del endpoint de dispositivo: " + ex.Message); }
    }

    /// <summary>
    /// Step 2 — poll until the user approves in the browser. Honours the
    /// server's <c>slow_down</c> back-off. Returns the refresh token.
    /// </summary>
    public async Task<(string refreshToken, string err)> PollForRefreshTokenAsync(
        string clientId, string clientSecret, DeviceCodeInfo info, CancellationToken ct)
    {
        var deadline = DateTime.UtcNow.AddSeconds(info.ExpiresInSec);
        int interval = info.IntervalSec;
        while (!ct.IsCancellationRequested)
        {
            if (DateTime.UtcNow > deadline) return ("", "El código expiró. Volvé a intentar.");
            try { await Task.Delay(TimeSpan.FromSeconds(interval), ct); }
            catch (OperationCanceledException) { return ("", ""); }
            if (ct.IsCancellationRequested) return ("", "");

            var form = new Dictionary<string, string>
            {
                ["client_id"] = clientId.Trim(),
                ["client_secret"] = clientSecret.Trim(),
                ["device_code"] = info.DeviceCode,
                ["grant_type"] = "urn:ietf:params:oauth:grant-type:device_code"
            };
            var (code, body) = await PostFormAsync(TokenUrl, form);
            string err = "";
            string refresh = "";
            try
            {
                using var d = JsonDocument.Parse(body);
                if (d.RootElement.TryGetProperty("refresh_token", out var rt)) refresh = rt.GetString() ?? "";
                if (d.RootElement.TryGetProperty("error", out var eE)) err = eE.GetString() ?? "";
            }
            catch { /* not json — treat as transient */ }

            if (code == 200 && !string.IsNullOrEmpty(refresh)) return (refresh, "");
            // authorization_pending / slow_down are the expected loop states.
            if (err == "authorization_pending") continue;
            if (err == "slow_down") { interval += 2; continue; }
            if (err == "access_denied") return ("", "Acceso denegado en Google.");
            if (err == "expired_token") return ("", "El código expiró. Volvé a intentar.");
            if (code != 200) return ("", $"Error autorizando (HTTP {code}): {Trim(err.Length > 0 ? err : body, 160)}");
        }
        return ("", "");
    }

    /// <summary>List the calendars the authorized account can read.</summary>
    public async Task<(List<GoogleCalendarInfo> cals, string err)> FetchCalendarListAsync()
    {
        var list = new List<GoogleCalendarInfo>();
        var token = await EnsureAccessTokenAsync();
        if (string.IsNullOrEmpty(token))
            return (list, "No se pudo obtener un access token. ¿Autorizaste arriba?");

        using var req = new HttpRequestMessage(HttpMethod.Get, $"{CalendarBase}/users/me/calendarList");
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        try
        {
            using var resp = await _http.SendAsync(req);
            var body = await resp.Content.ReadAsStringAsync();
            if (!resp.IsSuccessStatusCode)
                return (list, $"HTTP {(int)resp.StatusCode} al listar calendarios.");
            using var doc = JsonDocument.Parse(body);
            if (doc.RootElement.TryGetProperty("items", out var items) && items.ValueKind == JsonValueKind.Array)
            {
                foreach (var c in items.EnumerateArray())
                {
                    var id = c.TryGetProperty("id", out var idE) ? idE.GetString() ?? "" : "";
                    var summary = c.TryGetProperty("summary", out var sE) ? sE.GetString() ?? id : id;
                    bool primary = c.TryGetProperty("primary", out var pE) && pE.ValueKind == JsonValueKind.True;
                    list.Add(new GoogleCalendarInfo { Id = id, Label = summary + (primary ? " (principal)" : "") });
                }
            }
            Log($"calendarList: {list.Count} calendario(s).");
            return (list, "");
        }
        catch (Exception ex) { return (list, "Error de red: " + ex.Message); }
    }

    // ----- Helpers ---------------------------------------------------------

    private async Task<(int code, string body)> PostFormAsync(string url, Dictionary<string, string> form)
    {
        try
        {
            using var content = new FormUrlEncodedContent(form);
            using var resp = await _http.PostAsync(url, content);
            var body = await resp.Content.ReadAsStringAsync();
            return ((int)resp.StatusCode, body);
        }
        catch (Exception ex) { Warn("http: " + ex.Message); return (0, ""); }
    }

    private static string Trim(string s, int n) => s.Length <= n ? s : s.Substring(0, n);

    // ----- Logging ---------------------------------------------------------

    public void ClearDebugLog() { _log.Clear(); Raise(nameof(DebugLog)); Raise(nameof(HasDebugLog)); }

    private void Log(string msg)
    {
        AppendDebug(msg + "\n");
        if (_settings.GoogleCalDebug) FileLogger.Log("google", msg);
    }
    private void Warn(string msg)
    {
        AppendDebug("[!] " + msg + "\n");
        FileLogger.Log("google", "[!] " + msg);
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
