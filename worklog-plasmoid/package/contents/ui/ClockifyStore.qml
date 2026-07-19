/*
 * ClockifyStore.qml
 *
 * Reads / writes time entries against the Clockify REST API
 * (https://api.clockify.me/api/v1). Auth: X-Api-Key header.
 *
 * On first use the store resolves the user id and the default workspace
 * via GET /user and caches both in plasmoid.configuration so subsequent
 * fetches skip the lookup. Projects and tags are pulled once per session
 * (they rarely change).
 *
 * Endpoints used:
 *   - GET    /user                                                   (me)
 *   - GET    /workspaces/{wid}/projects?archived=false                (projects + colors)
 *   - GET    /workspaces/{wid}/tags?archived=false                    (tags)
 *   - GET    /workspaces/{wid}/user/{uid}/time-entries?start=…&end=…  (week)
 *   - POST   /workspaces/{wid}/time-entries                           (create)
 *   - PUT    /workspaces/{wid}/time-entries/{id}                      (edit)
 *   - DELETE /workspaces/{wid}/time-entries/{id}                      (delete)
 *
 * Each in-memory entry has the same `started/durationSec` shape used by
 * JiraWorklogStore so WorklogCalendar can render both with the same code.
 */

import QtQuick 2.15

QtObject {
    id: store

    property var plasmoidApi: null

    // Resolved & cached in plasmoid.configuration so reloads can skip the
    // /user lookup. Filled by ensureContext().
    property string workspaceId: ""
    property string userId: ""

    property var projects: []   // [{id, name, color, billable}]
    property var tags: []       // [{id, name}]
    property var entries: []    // [{id, started, durationSec, description, projectId, projectName, projectColor, tagIds, tagNames, billable}]

    // Always reads fresh from KCfg so the user changing the key in the
    // config dialog takes effect on the next request. Don't cache.
    function _apiKey() {
        if (!plasmoidApi) return "";
        return (plasmoidApi.configuration.clockifyApiKey || "").trim();
    }

    // Clockify object ids are 24-character lowercase hex strings (Mongo
    // ObjectId). Anything else (e.g. a workspace *name* like "PEPERINA")
    // would cause /workspaces/{wid}/* to 403, so we treat it as empty and
    // let `/user`'s defaultWorkspace fill it in.
    function _isValidObjectId(s) {
        return typeof s === "string" && /^[0-9a-fA-F]{24}$/.test(s);
    }

    readonly property bool ready: _apiKey().length > 0

    property bool loading: false
    property string lastError: ""
    property real lastFetchedAt: 0
    property int version: 0

    property string lastDebugLog: ""
    property bool hasDebugLog: false

    signal changed()
    signal fetchFinished(bool ok)
    signal createFinished(bool ok, string err)
    signal updateFinished(bool ok, string err)
    signal deleteFinished(bool ok, string err)
    signal syncFinished(int created, int skipped, int failed)

    // ------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------

    function init() {
        if (!plasmoidApi) {
            _warn("[FATAL] plasmoidApi null.");
            return;
        }
        var pc = plasmoidApi.configuration;
        var rawWid = (pc.clockifyWorkspaceId || "").trim();
        var rawUid = (pc.clockifyUserId      || "").trim();
        workspaceId = _isValidObjectId(rawWid) ? rawWid : "";
        userId      = _isValidObjectId(rawUid) ? rawUid : "";
        if (rawWid && !workspaceId) {
            _warn("Workspace ID guardado ('" + rawWid + "') no es un Object ID válido " +
                  "(24 hex chars); voy a auto-resolverlo desde /user.");
        }
        _log("init: workspaceId=" + (workspaceId || "(empty)") +
             " userId=" + (userId || "(empty)") +
             " hasKey=" + ready);
    }

    function totalCount() { return entries.length; }

    function clearDebugLog() {
        lastDebugLog = "";
        hasDebugLog = false;
        _bump();
    }

    // Resolve userId + workspaceId via /user, then load projects + tags,
    // then call the supplied callback (with ok=true on success).
    function ensureContext(callback) {
        var key = _apiKey();
        if (!key) {
            lastError = qsTr("Falta la API key de Clockify. Configurala en la pestaña Clockify.");
            _warn("Falta API key (plasmoid.configuration.clockifyApiKey está vacío).");
            _bump();
            callback(false);
            return;
        }
        // Refresh cached ids from config — but treat anything that isn't a
        // 24-hex Object ID as empty (a wrong value like the workspace
        // *name* would 403 on /workspaces/{wid}/* otherwise).
        if (plasmoidApi) {
            var rawWid = (plasmoidApi.configuration.clockifyWorkspaceId || "").trim();
            var rawUid = (plasmoidApi.configuration.clockifyUserId      || "").trim();
            workspaceId = _isValidObjectId(rawWid) ? rawWid : "";
            userId      = _isValidObjectId(rawUid) ? rawUid : "";
            if (rawWid && !workspaceId) {
                _warn("Workspace ID guardado ('" + rawWid + "') no es un Object ID hex " +
                      "de 24 chars (¿usaste el nombre?). Voy a usar el default del usuario.");
            }
        }
        if (workspaceId && userId && projects.length > 0) {
            callback(true);
            return;
        }

        _log("Resolviendo usuario + workspace + proyectos…");
        _send("GET", "https://api.clockify.me/api/v1/user", null, function(code, body) {
            if (code !== 200) {
                store.lastError = qsTr("HTTP %1 contra /user.").arg(code);
                _warn("GET /user exit=" + code + ": " + body.substring(0, 200));
                _bump();
                callback(false);
                return;
            }
            try {
                var u = JSON.parse(body);
                store.userId = u.id || "";
                // Always overwrite an invalid workspaceId with the user's
                // default, AND persist it back so the user doesn't have to
                // clear the wrong value manually.
                if (!_isValidObjectId(store.workspaceId)) {
                    store.workspaceId = u.defaultWorkspace || u.activeWorkspace || "";
                }
                plasmoidApi.configuration.clockifyUserId      = store.userId;
                plasmoidApi.configuration.clockifyWorkspaceId = store.workspaceId;
                _log("user=" + store.userId + "  workspace=" + store.workspaceId);
                if (!_isValidObjectId(store.workspaceId)) {
                    store.lastError = qsTr("No pude resolver un workspace válido — " +
                                           "/user no devolvió defaultWorkspace.");
                    _warn(store.lastError);
                    _bump();
                    callback(false);
                    return;
                }
                _loadProjectsThen(callback);
            } catch (e) {
                store.lastError = qsTr("Respuesta inválida de /user.");
                _warn("parse /user: " + e);
                _bump();
                callback(false);
            }
        });
    }

    function _loadProjectsThen(callback) {
        var url = "https://api.clockify.me/api/v1/workspaces/" + workspaceId +
                  "/projects?archived=false&page-size=200";
        _send("GET", url, null, function(code, body) {
            if (code !== 200) {
                _warn("GET projects exit=" + code);
                callback(false);
                return;
            }
            try {
                var raw = JSON.parse(body);
                var out = [];
                for (var i = 0; i < raw.length; i++) {
                    out.push({
                        id:       raw[i].id || "",
                        name:     raw[i].name || "",
                        color:    raw[i].color || "",
                        billable: !!raw[i].billable
                    });
                }
                store.projects = out;
                _log("Proyectos cargados: " + out.length);
                _loadTagsThen(callback);
            } catch (e) {
                _warn("parse projects: " + e);
                callback(false);
            }
        });
    }
    function _loadTagsThen(callback) {
        var url = "https://api.clockify.me/api/v1/workspaces/" + workspaceId +
                  "/tags?archived=false&page-size=200";
        _send("GET", url, null, function(code, body) {
            if (code !== 200) {
                _warn("GET tags exit=" + code);
                // Tags are optional — don't fail the whole flow.
                store.tags = [];
                callback(true);
                return;
            }
            try {
                var raw = JSON.parse(body);
                var out = [];
                for (var i = 0; i < raw.length; i++) {
                    out.push({ id: raw[i].id || "", name: raw[i].name || "" });
                }
                store.tags = out;
                _log("Tags cargados: " + out.length);
                callback(true);
            } catch (e) {
                _warn("parse tags: " + e);
                store.tags = [];
                callback(true);
            }
        });
    }

    // Fetch all entries in [weekStartDate, weekStartDate+7d).
    function fetchWeek(weekStartDate) {
        var ts = Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss");
        if (lastDebugLog.length > 0) _appendDebug("\n");
        _appendDebug("=== Clockify fetch " + ts + " ===\n");
        hasDebugLog = true;
        _bump();

        if (loading) { _warn("[abort] ya hay un fetch en curso."); return; }

        loading = true;
        lastError = "";
        _bump();

        ensureContext(function(ok) {
            if (!ok) {
                store.loading = false;
                _bump();
                store.fetchFinished(false);
                return;
            }
            var startMs = _startOfDay(new Date(weekStartDate.getTime())).getTime();
            var endMs   = startMs + 7 * 24 * 60 * 60 * 1000;
            var url = "https://api.clockify.me/api/v1/workspaces/" + workspaceId +
                      "/user/" + userId + "/time-entries" +
                      "?start=" + encodeURIComponent(_toUtcIso(new Date(startMs))) +
                      "&end="   + encodeURIComponent(_toUtcIso(new Date(endMs))) +
                      "&page-size=200";
            _log("GET " + url);
            _send("GET", url, null, function(code, body) {
                if (code !== 200) {
                    store.loading = false;
                    store.lastError = qsTr("HTTP %1 al traer time entries.").arg(code);
                    _warn("time-entries exit=" + code + ": " + body.substring(0, 240));
                    _bump();
                    store.fetchFinished(false);
                    return;
                }
                _processEntries(body);
            });
        });
    }

    function _processEntries(body) {
        try {
            var raw = JSON.parse(body);
            var out = [];
            for (var i = 0; i < raw.length; i++) {
                var e = raw[i];
                var ti = e.timeInterval || {};
                if (!ti.start || !ti.end) continue;   // skip running timers
                var startMs = new Date(ti.start).getTime();
                var endMs   = new Date(ti.end).getTime();
                if (isNaN(startMs) || isNaN(endMs) || endMs <= startMs) continue;
                var p = _projectById(e.projectId);
                out.push({
                    id:           e.id || "",
                    started:      startMs,
                    durationSec:  Math.round((endMs - startMs) / 1000),
                    description:  e.description || "",
                    projectId:    e.projectId || "",
                    projectName:  p ? p.name : "",
                    projectColor: p ? p.color : "",
                    tagIds:       e.tagIds || [],
                    tagNames:     _tagNamesFromIds(e.tagIds || []),
                    billable:     !!e.billable
                });
            }
            out.sort(function(a, b) { return a.started - b.started; });
            store.entries = out;
            store.lastFetchedAt = Date.now();
            store.loading = false;
            store._bump();
            _log("Entries: " + out.length + ".");
            for (var k = 0; k < Math.min(out.length, 20); k++) {
                var w = out[k];
                _log("  - " + new Date(w.started).toISOString().substring(0, 16) +
                     " (" + _fmtDur(w.durationSec) + ") " +
                     (w.projectName ? "[" + w.projectName + "] " : "") +
                     (w.description || "").substring(0, 50));
            }
            store.fetchFinished(true);
        } catch (e) {
            store.loading = false;
            store.lastError = qsTr("Error parseando la respuesta: ") + e;
            _warn("parse entries: " + e);
            store._bump();
            store.fetchFinished(false);
        }
    }

    // Aggregates my Clockify time-entry seconds per day-of-month for the
    // given month. Paginates (200/page) and does NOT touch entries[].
    // callback(ok, { 1: sec, 2: sec, ... }).
    function fetchMonthTotals(year, monthIndex, callback) {
        if (!callback) callback = function() {};
        ensureContext(function(ok) {
            if (!ok) { callback(false, {}); return; }
            var startD = new Date(year, monthIndex, 1, 0, 0, 0, 0);
            var endD   = new Date(year, monthIndex + 1, 1, 0, 0, 0, 0);
            var totals = {};
            var page = 1;
            var pageSize = 200;
            var fetchPage = function() {
                var url = "https://api.clockify.me/api/v1/workspaces/" + workspaceId +
                          "/user/" + userId + "/time-entries" +
                          "?start=" + encodeURIComponent(_toUtcIso(startD)) +
                          "&end="   + encodeURIComponent(_toUtcIso(endD)) +
                          "&page-size=" + pageSize + "&page=" + page;
                _log("Month(Clockify) GET " + url);
                _send("GET", url, null, function(code, body) {
                    if (code !== 200) {
                        _warn("month totals exit=" + code + ": " + body.substring(0, 200));
                        callback(false, totals);
                        return;
                    }
                    var raw;
                    try { raw = JSON.parse(body); }
                    catch (e) { _warn("month parse: " + e); callback(false, totals); return; }
                    for (var i = 0; i < raw.length; i++) {
                        var ti = raw[i].timeInterval || {};
                        if (!ti.start || !ti.end) continue;
                        var s  = new Date(ti.start).getTime();
                        var en = new Date(ti.end).getTime();
                        if (isNaN(s) || isNaN(en) || en <= s) continue;
                        var d = new Date(s);
                        if (d.getFullYear() === year && d.getMonth() === monthIndex) {
                            var day = d.getDate();
                            totals[day] = (totals[day] || 0) + Math.round((en - s) / 1000);
                        }
                    }
                    if (raw.length >= pageSize) { page++; fetchPage(); }
                    else {
                        _log("Month(Clockify) " + (monthIndex + 1) + "/" + year + ": " +
                             Object.keys(totals).length + " day(s) with entries.");
                        callback(true, totals);
                    }
                });
            };
            fetchPage();
        });
    }

    function _projectById(id) {
        if (!id) return null;
        for (var i = 0; i < projects.length; i++) {
            if (projects[i].id === id) return projects[i];
        }
        return null;
    }
    function _tagNamesFromIds(ids) {
        var out = [];
        for (var i = 0; i < (ids || []).length; i++) {
            for (var j = 0; j < tags.length; j++) {
                if (tags[j].id === ids[i]) { out.push(tags[j].name); break; }
            }
        }
        return out;
    }

    // ------------------------------------------------------------------
    // Create / Update / Delete
    // ------------------------------------------------------------------

    function createEntry(startDate, endDate, description, projectId, tagIds, billable) {
        if (!_contextReady()) return;
        var url = "https://api.clockify.me/api/v1/workspaces/" + workspaceId + "/time-entries";
        var body = {
            start: _toUtcIso(startDate),
            end:   _toUtcIso(endDate),
            description: description || "",
            billable: billable === true
        };
        if (projectId) body.projectId = projectId;
        if (tagIds && tagIds.length > 0) body.tagIds = tagIds;
        _log("POST " + url + "  body=" + JSON.stringify(body));
        _send("POST", url, JSON.stringify(body), function(code, respBody) {
            if (code >= 200 && code < 300) {
                _log("create OK.");
                store.createFinished(true, "");
            } else {
                var msg = _extractError(respBody);
                _warn("create exit=" + code + ": " + msg);
                store.createFinished(false, "HTTP " + code + ": " + msg);
            }
        });
    }

    function updateEntry(entryId, startDate, endDate, description, projectId, tagIds, billable) {
        if (!_contextReady()) return;
        var url = "https://api.clockify.me/api/v1/workspaces/" + workspaceId +
                  "/time-entries/" + encodeURIComponent(entryId);
        // PUT replaces the whole entry — include all fields.
        var body = {
            start: _toUtcIso(startDate),
            end:   _toUtcIso(endDate),
            description: description || "",
            billable: billable === true
        };
        if (projectId) body.projectId = projectId;
        body.tagIds = tagIds || [];
        _log("PUT " + url + "  body=" + JSON.stringify(body));
        _send("PUT", url, JSON.stringify(body), function(code, respBody) {
            if (code >= 200 && code < 300) {
                _log("update OK.");
                store.updateFinished(true, "");
            } else {
                var msg = _extractError(respBody);
                _warn("update exit=" + code + ": " + msg);
                store.updateFinished(false, "HTTP " + code + ": " + msg);
            }
        });
    }

    function deleteEntry(entryId) {
        if (!_contextReady()) return;
        var url = "https://api.clockify.me/api/v1/workspaces/" + workspaceId +
                  "/time-entries/" + encodeURIComponent(entryId);
        _log("DELETE " + url);
        _send("DELETE", url, null, function(code, respBody) {
            if (code === 204 || code === 200) {
                _log("delete OK.");
                store.deleteFinished(true, "");
            } else {
                var msg = _extractError(respBody);
                _warn("delete exit=" + code + ": " + msg);
                store.deleteFinished(false, "HTTP " + code + ": " + msg);
            }
        });
    }

    function _contextReady() {
        if (!workspaceId || !userId) {
            lastError = qsTr("Llamá ensureContext() (o sincronizá) primero.");
            _warn("workspace/user no resueltos todavía.");
            _bump();
            return false;
        }
        return true;
    }

    // ------------------------------------------------------------------
    // Sync from Jira: for each Jira worklog of the week create a Clockify
    // entry with description "<key>: <summary>". Dedup is overlap-based:
    // if Clockify already has an entry with the same description whose
    // time range overlaps the Jira block (any overlap, not just exact
    // start/duration match), the Jira block is treated as already-synced
    // and is skipped. This is what catches the "Jira block got 10 minutes
    // longer" case — without overlap-based dedup the previous logic
    // (±60 s start / ±60 s duration) would create a second Clockify entry
    // sitting on top of the old one.
    //
    // Dedup + creation are BOTH scoped to `defaultProjectId`: only Clockify
    // entries in that project are considered when checking for duplicates,
    // and new entries are created in it. This keeps two Jira instances that
    // map to different projects from interfering with each other's sync.
    // ------------------------------------------------------------------

    function syncFromJira(jiraWorklogs, defaultProjectId, defaultBillable, callback) {
        if (!jiraWorklogs || jiraWorklogs.length === 0) {
            callback(0, 0, 0);
            return;
        }
        var targetProject = defaultProjectId || "";
        ensureContext(function(ok) {
            if (!ok) { callback(0, 0, 0); return; }
            var toCreate = [];
            for (var i = 0; i < jiraWorklogs.length; i++) {
                var j = jiraWorklogs[i];
                var desc = j.issueKey + (j.issueSummary ? ": " + j.issueSummary : "");
                var jStart = j.started;
                var jEnd   = j.started + j.durationSec * 1000;
                // Already there? Same PROJECT + same description + any
                // time-range overlap.
                var hit = false;
                for (var k = 0; k < store.entries.length; k++) {
                    var c = store.entries[k];
                    if ((c.projectId || "") !== targetProject) continue;
                    if (c.description !== desc) continue;
                    var cStart = c.started;
                    var cEnd   = c.started + c.durationSec * 1000;
                    // Half-open intervals: touching ranges (cEnd === jStart)
                    // do not count as overlap.
                    if (jStart < cEnd && cStart < jEnd) { hit = true; break; }
                }
                if (hit) continue;
                toCreate.push({
                    start: new Date(j.started),
                    end:   new Date(j.started + j.durationSec * 1000),
                    desc:  desc
                });
            }
            _log("Sync: " + toCreate.length + " entries to create, " +
                 (jiraWorklogs.length - toCreate.length) + " already present.");
            if (toCreate.length === 0) {
                callback(0, jiraWorklogs.length, 0);
                return;
            }
            var created = 0, failed = 0, pending = toCreate.length;
            var step = function(idx) {
                if (idx >= toCreate.length) {
                    callback(created, jiraWorklogs.length - toCreate.length, failed);
                    store.syncFinished(created, jiraWorklogs.length - toCreate.length, failed);
                    return;
                }
                var t = toCreate[idx];
                var url = "https://api.clockify.me/api/v1/workspaces/" + workspaceId + "/time-entries";
                var bodyObj = {
                    start: _toUtcIso(t.start),
                    end:   _toUtcIso(t.end),
                    description: t.desc,
                    billable: defaultBillable === true
                };
                if (defaultProjectId) bodyObj.projectId = defaultProjectId;
                var bodyJson = JSON.stringify(bodyObj);
                if (idx === 0) _log("Sync POST body sample: " + bodyJson);
                _send("POST", url, bodyJson, function(code, respBody) {
                    if (code >= 200 && code < 300) {
                        created++;
                    } else {
                        failed++;
                        var detail = _extractError(respBody);
                        _warn("Sync create exit=" + code + " (" + t.desc + ") — " + detail);
                    }
                    step(idx + 1);
                });
            };
            step(0);
        });
    }

    // ------------------------------------------------------------------
    // HTTP plumbing
    // ------------------------------------------------------------------

    function _send(method, url, body, callback) {
        var key = _apiKey();
        if (!key) {
            _warn("_send abortado: no hay API key todavía.");
            callback(0, "");
            return;
        }
        var xhr = new XMLHttpRequest();
        xhr.open(method, url, true);
        xhr.setRequestHeader("X-Api-Key", key);
        xhr.setRequestHeader("Accept", "application/json");
        if (body) xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            callback(xhr.status | 0, xhr.responseText || "");
        };
        try { xhr.send(body); }
        catch (e) { _warn("xhr.send threw: " + e); callback(0, ""); }
    }

    // Returns "2026-05-12T15:00:00.000Z" — Clockify's docs and examples
    // include the milliseconds; some endpoints reject the shortened form
    // with HTTP 400.
    function _toUtcIso(d) {
        function p(n) { return n < 10 ? "0" + n : "" + n; }
        function p3(n) {
            if (n < 10)  return "00" + n;
            if (n < 100) return "0"  + n;
            return "" + n;
        }
        return d.getUTCFullYear() + "-" + p(d.getUTCMonth() + 1) + "-" + p(d.getUTCDate()) +
               "T" + p(d.getUTCHours()) + ":" + p(d.getUTCMinutes()) + ":" + p(d.getUTCSeconds()) +
               "." + p3(d.getUTCMilliseconds()) + "Z";
    }
    function _startOfDay(d) {
        var c = new Date(d); c.setHours(0, 0, 0, 0); return c;
    }
    function _fmtDur(sec) {
        var h = Math.floor(sec / 3600);
        var m = Math.floor((sec % 3600) / 60);
        if (h > 0 && m > 0) return h + "h " + m + "m";
        if (h > 0)          return h + "h";
        return m + "m";
    }
    function _extractError(body) {
        if (!body) return "";
        try {
            var d = JSON.parse(body);
            if (d.message) return d.message;
            if (d.error) return typeof d.error === "string" ? d.error : JSON.stringify(d.error);
        } catch (e) { /* not json */ }
        return String(body).substring(0, 240);
    }

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
        if (plasmoidApi.configuration.clockifyDebug === false) return;
        console.log("[Clockify] " + msg);
    }

    function _warn(msg) {
        _appendDebug("[!] " + msg + "\n");
        console.warn("[Clockify] " + msg);
    }

    function _bump() {
        version = version + 1;
        changed();
    }
}
