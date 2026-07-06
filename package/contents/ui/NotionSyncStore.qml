/*
 * NotionSyncStore.qml
 *
 * Two-way sync between the local ToDo tasks (TaskStore + SQLite) and a
 * Notion database, over the official Notion HTTP API (api.notion.com/v1).
 * Unlike NotionStore.qml (which shells out to the `ntn` CLI and drives the
 * standalone "notion" mode — now disabled), this store talks HTTP directly
 * with an Internal Integration token and keeps the ToDo list itself in sync.
 *
 * Auth: HTTP Bearer with a Notion internal integration token
 * (secret_… / ntn_…). The token is mirrored to SQLite so a Plasma config
 * loss doesn't wipe it out. The database id is remembered the same way.
 *
 * Sync model (see docs/NOTION.md): each task maps to one Notion page. New
 * tasks on either side are created on the other; when a task changed on both
 * sides the most recently edited one wins; deletions are never propagated
 * (nothing is auto-deleted). The "Archived" checkbox mirrors the local
 * archive state and subtasks travel as a JSON blob in a rich_text property.
 *
 * Notion database schema (created by createDatabase()):
 *   Name (title), Description (rich_text), Category (number),
 *   Priority (select XS/S/M/L/XL), Done (checkbox), Archived (checkbox),
 *   Subtasks (rich_text = JSON), LocalId (number).
 */

import QtQuick 2.15

QtObject {
    id: store

    property var plasmoidApi: null
    property var database: null
    property var tasks: null          // the TaskStore instance

    property bool loading: false
    property string lastError: ""
    property real lastSyncedAt: 0
    property int version: 0

    property string lastDebugLog: ""
    property bool hasDebugLog: false

    signal changed()
    signal syncFinished(bool ok, int pulled, int pushed)

    readonly property string _apiBase: "https://api.notion.com/v1"
    readonly property string _notionVersion: "2022-06-28"

    property var _refreshTimer: Timer {
        repeat: true
        running: false
        onTriggered: store.sync(null)
    }

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    function init() {
        restoreCredentialsFromCache();
        applyRefreshSchedule();
        _log("init: NotionSyncStore listo. configured=" + isConfigured() +
             ", dbId=" + (_databaseId() ? "[set]" : "(none)"));
    }

    function applyRefreshSchedule() {
        if (!plasmoidApi) return;
        var minutes = plasmoidApi.configuration.notionRefreshMinutes | 0;
        if (minutes > 0 && isConfigured()) {
            _refreshTimer.interval = minutes * 60 * 1000;
            _refreshTimer.running = true;
            _log("auto-sync cada " + minutes + " min.");
        } else {
            _refreshTimer.running = false;
        }
    }

    function isConfigured() {
        return _token().length > 0 && _databaseId().length > 0;
    }

    function _token() {
        if (!plasmoidApi) return "";
        return (plasmoidApi.configuration.notionApiToken || "").trim();
    }
    function _databaseId() {
        if (!plasmoidApi) return "";
        return (plasmoidApi.configuration.notionDatabaseId || "").trim();
    }
    function _parentPageId() {
        if (!plasmoidApi) return "";
        return (plasmoidApi.configuration.notionParentPageId || "").trim();
    }

    // ------------------------------------------------------------------
    // Credentials mirror (token + database id survive a config wipe)
    // ------------------------------------------------------------------

    function restoreCredentialsFromCache() {
        if (!database || !database.ready || !plasmoidApi) return;
        var pc = plasmoidApi.configuration;
        if (!pc.notionApiToken)  { var t = database.getSetting("notion.token", ""); if (t) pc.notionApiToken  = t; }
        if (!pc.notionDatabaseId){ var d = database.getSetting("notion.dbid",  ""); if (d) pc.notionDatabaseId = d; }
    }

    function persistCredentials() {
        if (!database || !database.ready || !plasmoidApi) return;
        var pc = plasmoidApi.configuration;
        database.setSetting("notion.token", pc.notionApiToken  || "");
        database.setSetting("notion.dbid",  pc.notionDatabaseId || "");
    }

    // ------------------------------------------------------------------
    // Low-level HTTP
    // ------------------------------------------------------------------

    // method: "GET"|"POST"|"PATCH". body: object or null. cb(ok, json, status, rawText).
    function _api(method, path, body, cb) {
        var token = _token();
        if (!token) { cb(false, null, 0, "no token"); return; }
        var xhr = new XMLHttpRequest();
        try {
            xhr.open(method, _apiBase + path, true);
        } catch (e) {
            cb(false, null, 0, "open() threw: " + e);
            return;
        }
        xhr.setRequestHeader("Authorization", "Bearer " + token);
        xhr.setRequestHeader("Notion-Version", _notionVersion);
        xhr.setRequestHeader("Accept", "application/json");
        if (body !== null && body !== undefined)
            xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            var raw = xhr.responseText || "";
            var json = null;
            try { json = raw.length ? JSON.parse(raw) : null; } catch (e) { /* leave null */ }
            var ok = (xhr.status >= 200 && xhr.status < 300);
            if (!ok) {
                var m = json && json.message ? json.message : ("HTTP " + xhr.status);
                store._warn(method + " " + path + " -> " + xhr.status + ": " + m);
            }
            cb(ok, json, xhr.status, raw);
        };
        try {
            xhr.send(body !== null && body !== undefined ? JSON.stringify(body) : undefined);
        } catch (e) {
            cb(false, null, 0, "send() threw: " + e);
        }
    }

    // ------------------------------------------------------------------
    // Test connection (used by the config page)
    // ------------------------------------------------------------------

    function testConnection(token, cb) {
        token = (token || "").trim();
        if (!token) { cb(false, qsTr("Completá el token antes de probar.")); return; }
        var xhr = new XMLHttpRequest();
        xhr.open("GET", _apiBase + "/users/me", true);
        xhr.setRequestHeader("Authorization", "Bearer " + token);
        xhr.setRequestHeader("Notion-Version", _notionVersion);
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try {
                    var d = JSON.parse(xhr.responseText);
                    var who = d.name || (d.bot && d.bot.owner ? "bot" : "") || "OK";
                    cb(true, qsTr("OK — integración «%1» autenticada.").arg(who));
                } catch (e) {
                    cb(true, qsTr("OK (200)."));
                }
            } else if (xhr.status === 401) {
                cb(false, qsTr("Token rechazado (HTTP 401). Revisá el secret de la integración."));
            } else if (xhr.status === 0) {
                cb(false, qsTr("No se pudo contactar api.notion.com."));
            } else {
                var msg = xhr.responseText || xhr.statusText || "";
                cb(false, qsTr("HTTP %1: %2").arg(xhr.status).arg(msg.substring(0, 200)));
            }
        };
        try { xhr.send(); } catch (e) { cb(false, qsTr("Error de red: %1").arg(e)); }
    }

    // ------------------------------------------------------------------
    // First-time setup: create the database under a parent page
    // ------------------------------------------------------------------

    function createDatabase(cb) {
        var parent = _parentPageId();
        if (!_token())  { if (cb) cb(false, qsTr("Falta el token de Notion.")); return; }
        if (!parent)    { if (cb) cb(false, qsTr("Falta el ID de la página padre.")); return; }

        _log("createDatabase() bajo parent=" + parent);
        var body = {
            parent: { type: "page_id", page_id: parent },
            title: [ { type: "text", text: { content: "Categorized ToDo" } } ],
            properties: {
                "Name":        { title: {} },
                "Description": { rich_text: {} },
                "Category":    { number: {} },
                "Priority":    { select: { options: [
                                    { name: "XS" }, { name: "S" }, { name: "M" },
                                    { name: "L" }, { name: "XL" } ] } },
                "Done":        { checkbox: {} },
                "Archived":    { checkbox: {} },
                "Subtasks":    { rich_text: {} },
                "LocalId":     { number: {} }
            }
        };
        _api("POST", "/databases", body, function(ok, json, status, raw) {
            if (!ok || !json || !json.id) {
                var m = (json && json.message) ? json.message : ("HTTP " + status);
                store.lastError = qsTr("No se pudo crear la base: ") + m;
                store._bump();
                if (cb) cb(false, store.lastError);
                return;
            }
            // Persist the new database id both in config and settings.
            if (plasmoidApi) plasmoidApi.configuration.notionDatabaseId = json.id;
            store.persistCredentials();
            store._log("Base creada. id=" + json.id);
            store.applyRefreshSchedule();
            store._bump();
            if (cb) cb(true, json.id);
        });
    }

    // ------------------------------------------------------------------
    // Sync
    // ------------------------------------------------------------------

    function sync(cb) {
        var ts = Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss");
        if (lastDebugLog.length > 0) _appendDebug("\n");
        _appendDebug("=== Notion sync " + ts + " ===\n");
        hasDebugLog = true;

        if (!plasmoidApi || !tasks) {
            _warn("[abort] plasmoidApi o tasks es null.");
            if (cb) cb(false);
            return;
        }
        if (!isConfigured()) {
            lastError = qsTr("Notion no está configurado (token + base de datos).");
            _log(lastError);
            _bump();
            if (cb) cb(false);
            return;
        }
        if (loading) { _warn("[abort] ya hay un sync en curso."); return; }

        loading = true;
        lastError = "";
        _bump();

        var dbId = _databaseId();
        _log("sync() db=" + dbId);

        _queryAllPages(dbId, [], null, function(ok, pages, err) {
            if (!ok) {
                store.loading = false;
                store.lastError = qsTr("Error al consultar Notion: ") + err;
                store._warn(store.lastError);
                store._bump();
                store.syncFinished(false, 0, 0);
                if (cb) cb(false);
                return;
            }
            store._reconcile(pages, cb);
        });
    }

    // Fetch every page of the database (follows pagination).
    function _queryAllPages(dbId, acc, cursor, done) {
        var body = { page_size: 100 };
        if (cursor) body.start_cursor = cursor;
        _api("POST", "/databases/" + dbId + "/query", body, function(ok, json, status, raw) {
            if (!ok || !json) {
                var m = (json && json.message) ? json.message : ("HTTP " + status);
                done(false, acc, m);
                return;
            }
            var results = json.results || [];
            for (var i = 0; i < results.length; i++) acc.push(results[i]);
            if (json.has_more && json.next_cursor) {
                store._queryAllPages(dbId, acc, json.next_cursor, done);
            } else {
                done(true, acc, "");
            }
        });
    }

    function _reconcile(pages, cb) {
        _log("reconcile: " + pages.length + " página(s) en Notion.");

        // Index local tasks by their mapped page id.
        var snapshot = tasks.allTasksForSync();
        var localByPage = {};
        for (var i = 0; i < snapshot.length; i++) {
            var lt = snapshot[i];
            if (lt.notionPageId) localByPage[lt.notionPageId] = lt;
        }

        var pulled = 0;
        var pushUpdates = [];   // { taskId, pageId }
        var seenPages = {};

        for (var p = 0; p < pages.length; p++) {
            var page = pages[p];
            if (!page || !page.id) continue;
            seenPages[page.id] = true;
            var remote = _pageToRemote(page);
            var local = localByPage[page.id];

            if (!local) {
                // New page in Notion → create locally.
                tasks.applyRemoteUpsert(remote);
                pulled++;
                continue;
            }

            var remoteChanged = (page.last_edited_time !== (local.notionLastEdited || ""));
            var localChanged  = tasks.notionLocalChanged(local);

            if (remoteChanged && localChanged) {
                // Conflict → newest wins (epoch-ms comparison; rare path).
                var remoteMs = Date.parse(page.last_edited_time) || 0;
                if (remoteMs >= (local.updatedAt | 0)) {
                    tasks.applyRemoteUpsert(remote); pulled++;
                } else {
                    pushUpdates.push({ taskId: local.id, pageId: page.id });
                }
            } else if (remoteChanged) {
                tasks.applyRemoteUpsert(remote); pulled++;
            } else if (localChanged) {
                pushUpdates.push({ taskId: local.id, pageId: page.id });
            }
            // else: already in sync — leave the task untouched (no DB churn).
        }

        // Local tasks with no Notion page yet → create in Notion.
        var pushCreates = [];
        for (var j = 0; j < snapshot.length; j++) {
            var t = snapshot[j];
            if (!t.notionPageId) pushCreates.push(t.id);
            // A mapped task whose page wasn't returned was removed/trashed in
            // Notion; we don't propagate deletions, so we leave it as-is.
        }

        // Build the async op queue (creates + updates), run sequentially.
        var ops = [];
        var pushedCount = { n: 0 };

        for (var u = 0; u < pushUpdates.length; u++) {
            (function(item) {
                ops.push(function(next) { store._pushUpdate(item.taskId, item.pageId, pushedCount, next); });
            })(pushUpdates[u]);
        }
        for (var c = 0; c < pushCreates.length; c++) {
            (function(taskId) {
                ops.push(function(next) { store._pushCreate(taskId, pushedCount, next); });
            })(pushCreates[c]);
        }

        _runOps(ops, 0, function() {
            store.loading = false;
            store.lastSyncedAt = Date.now();
            store._log("sync OK: " + pulled + " traída(s), " + pushedCount.n + " enviada(s).");
            store._bump();
            store.syncFinished(true, pulled, pushedCount.n);
            if (cb) cb(true);
        });
    }

    function _runOps(ops, i, done) {
        if (i >= ops.length) { done(); return; }
        ops[i](function() { store._runOps(ops, i + 1, done); });
    }

    function _pushUpdate(taskId, pageId, counter, next) {
        var t = tasks.getAnyTask(taskId);
        if (!t) { next(); return; }
        var body = { properties: _taskToProperties(t), archived: false };
        _api("PATCH", "/pages/" + pageId, body, function(ok, json, status, raw) {
            if (ok && json) {
                tasks.markPushed(taskId, pageId, json.last_edited_time || "");
                counter.n = counter.n + 1;
            } else {
                store._warn("push update falló para task " + taskId);
            }
            next();
        });
    }

    function _pushCreate(taskId, counter, next) {
        var t = tasks.getAnyTask(taskId);
        if (!t) { next(); return; }
        var body = {
            parent: { database_id: _databaseId() },
            properties: _taskToProperties(t)
        };
        _api("POST", "/pages", body, function(ok, json, status, raw) {
            if (ok && json && json.id) {
                tasks.markPushed(taskId, json.id, json.last_edited_time || "");
                counter.n = counter.n + 1;
            } else {
                store._warn("push create falló para task " + taskId);
            }
            next();
        });
    }

    // ------------------------------------------------------------------
    // Mapping helpers
    // ------------------------------------------------------------------

    function _taskToProperties(t) {
        var props = {};
        props["Name"]        = { title: _richText(t.title || "") };
        props["Description"] = { rich_text: _richText(t.description || "") };
        props["Category"]    = { number: (t.category | 0) };
        props["Priority"]    = { select: { name: t.priority || "M" } };
        props["Done"]        = { checkbox: !!t.done };
        props["Archived"]    = { checkbox: tasks.isArchived(t.id) };
        props["Subtasks"]    = { rich_text: _richText(_serializeSubtasks(t.subtasks || [])) };
        props["LocalId"]     = { number: (t.id | 0) };
        return props;
    }

    // Notion rich_text content is capped at 2000 chars per segment; split.
    function _richText(s) {
        s = String(s === undefined || s === null ? "" : s);
        if (s.length === 0) return [];
        var out = [];
        var CHUNK = 1900;
        for (var i = 0; i < s.length; i += CHUNK) {
            out.push({ type: "text", text: { content: s.substring(i, i + CHUNK) } });
        }
        return out;
    }

    function _plainText(richArr) {
        if (!richArr || !richArr.length) return "";
        var s = "";
        for (var i = 0; i < richArr.length; i++) {
            s += (richArr[i] && richArr[i].plain_text) || "";
        }
        return s;
    }

    function _serializeSubtasks(subs) {
        var arr = [];
        for (var i = 0; i < subs.length; i++) {
            arr.push({ title: subs[i].title || "",
                       priority: subs[i].priority || "M",
                       done: !!subs[i].done });
        }
        return arr.length ? JSON.stringify(arr) : "";
    }

    function _parseSubtasks(s) {
        if (!s) return [];
        try {
            var arr = JSON.parse(s);
            if (!Array.isArray(arr)) return [];
            return arr.map(function(x) {
                return { title: (x && x.title) || "",
                         priority: (x && x.priority) || "M",
                         done: !!(x && x.done) };
            });
        } catch (e) { return []; }
    }

    // Convert a Notion page object into the `remote` shape TaskStore expects.
    function _pageToRemote(page) {
        var pr = page.properties || {};
        function txt(name)  { var p = pr[name]; return p ? _plainText(p.rich_text) : ""; }
        function ttl(name)  { var p = pr[name]; return p ? _plainText(p.title) : ""; }
        function num(name)  { var p = pr[name]; return (p && p.number !== null && p.number !== undefined) ? p.number : 0; }
        function chk(name)  { var p = pr[name]; return !!(p && p.checkbox); }
        function sel(name)  { var p = pr[name]; return (p && p.select && p.select.name) ? p.select.name : ""; }

        return {
            notionPageId: page.id,
            notionLastEdited: page.last_edited_time || "",
            title: ttl("Name") || txt("Name") || "(sin título)",
            description: txt("Description"),
            category: num("Category") | 0,
            priority: sel("Priority") || "M",
            done: chk("Done"),
            archived: chk("Archived"),
            subtasks: _parseSubtasks(txt("Subtasks"))
        };
    }

    // ------------------------------------------------------------------
    // Debug log
    // ------------------------------------------------------------------

    readonly property int _maxDebugLogChars: 80000

    function clearDebugLog() {
        lastDebugLog = "";
        hasDebugLog = false;
        _bump();
    }

    function _appendDebug(line) {
        var next = lastDebugLog + line;
        if (next.length > _maxDebugLogChars) {
            next = "[…log truncado…]\n" +
                   next.substring(next.length - Math.floor(_maxDebugLogChars / 2));
        }
        lastDebugLog = next;
        if (!hasDebugLog) hasDebugLog = true;
    }

    function _log(msg) {
        _appendDebug(msg + "\n");
        if (!plasmoidApi) return;
        if (plasmoidApi.configuration.notionDebug === false) return;
        console.log("[NotionSyncStore] " + msg);
    }

    function _warn(msg) {
        _appendDebug("[!] " + msg + "\n");
        console.warn("[NotionSyncStore] " + msg);
    }

    function _bump() {
        version = version + 1;
        changed();
    }
}
