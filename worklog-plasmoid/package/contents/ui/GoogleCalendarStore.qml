/*
 * GoogleCalendarStore.qml
 *
 * Read-only client for the Google Calendar API v3. Renders calendar
 * events as immovable background blocks on the worklog grid so you can
 * see your meetings while logging time.
 *
 * Auth: OAuth 2.0 using the "TV and Limited Input devices" client type.
 * The one-time device-code authorization (done from the config dialog)
 * yields a refresh token; this store exchanges it for short-lived
 * access tokens at runtime. Nothing is written back to Google — only
 * calendar.readonly scope is used. See docs/GOOGLE_CALENDAR.md.
 *
 * Endpoints:
 *   - POST https://oauth2.googleapis.com/token            (refresh → access)
 *   - GET  https://www.googleapis.com/calendar/v3/calendars/{id}/events
 *
 * Each in-memory event has the same `started/durationSec` shape used by
 * JiraWorklogStore / ClockifyStore so WorklogCalendar can position them
 * with the same math.
 */

import QtQuick 2.15

QtObject {
    id: store

    property var plasmoidApi: null

    property var events: []          // [{id, summary, started (ms), durationSec, calendarId}]

    property bool loading: false
    property string lastError: ""
    property real lastFetchedAt: 0
    property int version: 0

    // Short-lived access token cached with its expiry (ms epoch). Refreshed
    // automatically when missing or within 60 s of expiring.
    property string _accessToken: ""
    property real _accessTokenExp: 0

    property string lastDebugLog: ""
    property bool hasDebugLog: false

    signal changed()
    signal fetchFinished(bool ok)

    // ------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------

    function init() {
        if (!plasmoidApi) { _warn("[FATAL] plasmoidApi es null."); return; }
        _log("init: store listo.");
    }

    function totalCount() { return events.length; }

    function clearDebugLog() {
        lastDebugLog = "";
        hasDebugLog = false;
        _bump();
    }

    function _creds() {
        if (!plasmoidApi) return null;
        var pc = plasmoidApi.configuration;
        var id     = (pc.googleClientId || "").trim();
        var secret = (pc.googleClientSecret || "").trim();
        var refresh = (pc.googleRefreshToken || "").trim();
        if (!id || !secret || !refresh) {
            lastError = qsTr("Falta autorizar Google Calendar (Configurar → Google).");
            _warn("Faltan credenciales: id=" + (!!id) + " secret=" + (!!secret) +
                  " refresh=" + (!!refresh));
            _bump();
            return null;
        }
        return { id: id, secret: secret, refresh: refresh };
    }

    // Ensures a valid access token, refreshing via the refresh token when
    // needed. callback(ok, token).
    function _ensureAccessToken(callback) {
        if (!callback) callback = function() {};
        var now = Date.now();
        if (_accessToken && now < _accessTokenExp - 60000) {
            callback(true, _accessToken);
            return;
        }
        var creds = _creds();
        if (!creds) { callback(false, ""); return; }

        var body = "client_id=" + encodeURIComponent(creds.id) +
                   "&client_secret=" + encodeURIComponent(creds.secret) +
                   "&refresh_token=" + encodeURIComponent(creds.refresh) +
                   "&grant_type=refresh_token";
        _log("POST oauth2 token (refresh)");
        var xhr = new XMLHttpRequest();
        xhr.open("POST", "https://oauth2.googleapis.com/token", true);
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status !== 200) {
                _warn("token refresh exit=" + xhr.status + ": " +
                      (xhr.responseText || "").substring(0, 240));
                store.lastError = qsTr("No se pudo renovar el token de Google (HTTP %1).").arg(xhr.status);
                store._bump();
                callback(false, "");
                return;
            }
            try {
                var d = JSON.parse(xhr.responseText);
                store._accessToken = d.access_token || "";
                var ttl = (d.expires_in || 3600) * 1000;
                store._accessTokenExp = Date.now() + ttl;
                _log("Access token renovado (expira en " + Math.round(ttl / 1000) + "s).");
                callback(!!store._accessToken, store._accessToken);
            } catch (e) {
                _warn("token parse: " + e);
                callback(false, "");
            }
        };
        try { xhr.send(body); }
        catch (e) { _warn("token xhr.send threw: " + e); callback(false, ""); }
    }

    function fetchWeek(weekStartDate) {
        var ts = Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss");
        if (lastDebugLog.length > 0) _appendDebug("\n");
        _appendDebug("=== Google fetch " + ts + " ===\n");
        hasDebugLog = true;
        _bump();

        if (loading) { _warn("[abort] ya hay un fetch en curso."); return; }
        // If the user hasn't enabled the feature, don't even try.
        if (plasmoidApi && plasmoidApi.configuration.googleCalEnabled !== true) {
            _log("googleCalEnabled=false — no fetch.");
            return;
        }

        loading = true;
        lastError = "";
        _bump();

        _ensureAccessToken(function(ok, token) {
            if (!ok) {
                store.loading = false;
                store._bump();
                store.fetchFinished(false);
                return;
            }
            var startMs = _startOfDay(new Date(weekStartDate.getTime())).getTime();
            var endMs   = startMs + 7 * 24 * 60 * 60 * 1000;
            var calIds = store._calendarIds();
            if (calIds.length === 0) {
                store.events = [];
                store.lastFetchedAt = Date.now();
                store.loading = false;
                store._bump();
                store.fetchFinished(true);
                return;
            }
            // Fetch every configured calendar, accumulate, set events once.
            var pending = calIds.length;
            var acc = [];
            var anyOk = false;
            for (var i = 0; i < calIds.length; i++) {
                store._fetchOne(token, calIds[i], startMs, endMs, function(okOne, evs) {
                    if (okOne) { anyOk = true; acc = acc.concat(evs); }
                    if (--pending === 0) {
                        acc.sort(function(a, b) { return a.started - b.started; });
                        store.events = acc;
                        store.lastFetchedAt = Date.now();
                        store.loading = false;
                        store._bump();
                        _log("Eventos totales: " + acc.length + " (" + calIds.length + " calendario(s)).");
                        store.fetchFinished(anyOk);
                    }
                });
            }
        });
    }

    // Up to 3 calendar ids from googleCalendarIds; falls back to the legacy
    // single googleCalendarId when the list is empty.
    function _calendarIds() {
        var pc = plasmoidApi ? plasmoidApi.configuration : null;
        if (!pc) return [];
        var ids = pc.googleCalendarIds || [];
        if (!ids || ids.length === 0) {
            var legacy = (pc.googleCalendarId || "").trim();
            ids = legacy ? [legacy] : [];
        }
        var out = [];
        for (var i = 0; i < ids.length && out.length < 3; i++) {
            var id = ("" + (ids[i] || "")).trim();
            if (id) out.push(id);
        }
        return out;
    }

    function _fetchOne(token, calId, weekStartMs, weekEndMs, callback) {
        var url = "https://www.googleapis.com/calendar/v3/calendars/" +
                  encodeURIComponent(calId) + "/events" +
                  "?timeMin=" + encodeURIComponent(new Date(weekStartMs).toISOString()) +
                  "&timeMax=" + encodeURIComponent(new Date(weekEndMs).toISOString()) +
                  "&singleEvents=true&orderBy=startTime&maxResults=250";
        _log("GET " + url);
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url, true);
        xhr.setRequestHeader("Authorization", "Bearer " + token);
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status !== 200) {
                store.lastError = qsTr("HTTP %1 al traer eventos de Google (%2).")
                                  .arg(xhr.status).arg(calId);
                _warn("events[" + calId + "] exit=" + xhr.status + ": " +
                      (xhr.responseText || "").substring(0, 240));
                callback(false, []);
                return;
            }
            callback(true, store._parseEvents(xhr.responseText, calId, weekStartMs, weekEndMs));
        };
        try { xhr.send(); }
        catch (e) { _warn("events xhr.send threw: " + e); callback(false, []); }
    }

    function _parseEvents(body, calId, weekStartMs, weekEndMs) {
        var out = [];
        try {
            var data = JSON.parse(body);
            var items = data.items || [];
            for (var i = 0; i < items.length; i++) {
                var ev = items[i];
                if (ev.status === "cancelled") continue;
                var s = ev.start || {};
                var e = ev.end || {};
                // Skip all-day events (date, no dateTime) — they don't map
                // to a time block on the hour grid.
                if (!s.dateTime || !e.dateTime) continue;
                var startMs = new Date(s.dateTime).getTime();
                var endMs   = new Date(e.dateTime).getTime();
                if (isNaN(startMs) || isNaN(endMs) || endMs <= startMs) continue;
                if (endMs <= weekStartMs || startMs >= weekEndMs) continue;
                out.push({
                    id: calId + ":" + (ev.id || ""),
                    summary: ev.summary || qsTr("(sin título)"),
                    started: startMs,
                    durationSec: Math.round((endMs - startMs) / 1000),
                    calendarId: calId
                });
            }
            _log("Eventos[" + calId + "]: " + out.length + ".");
        } catch (e) {
            _warn("parse events[" + calId + "]: " + e);
        }
        return out;
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function _startOfDay(d) { var c = new Date(d); c.setHours(0, 0, 0, 0); return c; }

    // ------------------------------------------------------------------
    // Logging
    // ------------------------------------------------------------------

    readonly property int _maxDebugLogChars: 80000

    function _appendDebug(line) {
        var next = lastDebugLog + line;
        if (next.length > _maxDebugLogChars) {
            next = "[…log truncado…]\n" + next.substring(next.length - Math.floor(_maxDebugLogChars / 2));
        }
        lastDebugLog = next;
        if (!hasDebugLog) hasDebugLog = true;
    }

    function _log(msg) {
        _appendDebug(msg + "\n");
        if (!plasmoidApi) return;
        if (plasmoidApi.configuration.googleCalDebug === false) return;
        console.log("[GoogleCal] " + msg);
    }

    function _warn(msg) {
        _appendDebug("[!] " + msg + "\n");
        console.warn("[GoogleCal] " + msg);
    }

    function _bump() {
        version = version + 1;
        changed();
    }
}
