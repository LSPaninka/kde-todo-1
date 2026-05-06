/*
 * JiraStore.qml
 *
 * Connects to a Jira Cloud REST API (v3), fetches the issues matching
 * the configured JQL, normalizes them and exposes them grouped by the
 * user-defined Jira categories. Caches the last successful response in
 * SQLite so the popup is populated immediately on next launch.
 *
 * Auth: HTTP Basic with email + API token. Credentials are mirrored to
 * SQLite so a Plasma config loss doesn't wipe them out.
 *
 * Debug logs (enabled by default via plasmoid.configuration.jiraDebug)
 * surface the URL, JQL, HTTP status, per-issue summary and the count
 * each category ended up with. Read them with:
 *   journalctl --user -f _COMM=plasmashell | grep -i jirastore
 */

import QtQuick 2.15

QtObject {
    id: store

    property var plasmoid: null
    property var database: null

    property var issues: []
    property bool loading: false
    property string lastError: ""
    property real lastFetchedAt: 0
    property int version: 0

    signal changed()
    signal fetchFinished(bool ok)

    property var _refreshTimer: Timer {
        repeat: true
        running: false
        onTriggered: store.fetch()
    }

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    function init() {
        restoreCredentialsFromCache();
        loadCache();
        applyRefreshSchedule();
        _log("init: " + issues.length + " cached issue(s); lastFetchedAt=" +
             (lastFetchedAt ? new Date(lastFetchedAt).toISOString() : "never"));
    }

    function applyRefreshSchedule() {
        if (!plasmoid) return;
        var minutes = plasmoid.configuration.jiraRefreshMinutes | 0;
        if (minutes > 0) {
            _refreshTimer.interval = minutes * 60 * 1000;
            _refreshTimer.running = true;
            _log("auto-refresh scheduled every " + minutes + " min");
        } else {
            _refreshTimer.running = false;
            _log("auto-refresh disabled (manual only)");
        }
    }

    // ------------------------------------------------------------------
    // Credentials mirror
    // ------------------------------------------------------------------

    function restoreCredentialsFromCache() {
        if (!database || !database.ready || !plasmoid) return;
        var pc = plasmoid.configuration;
        var restored = [];
        if (!pc.jiraSite)  { var s = database.getSetting("jira.site",  ""); if (s) { pc.jiraSite  = s; restored.push("site"); } }
        if (!pc.jiraEmail) { var e = database.getSetting("jira.email", ""); if (e) { pc.jiraEmail = e; restored.push("email"); } }
        if (!pc.jiraToken) { var t = database.getSetting("jira.token", ""); if (t) { pc.jiraToken = t; restored.push("token"); } }
        if (!pc.jiraJql)   { var j = database.getSetting("jira.jql",   ""); if (j) { pc.jiraJql   = j; restored.push("jql"); } }
        if (restored.length) _log("restored from cache: " + restored.join(", "));
    }

    function persistCredentials() {
        if (!database || !database.ready || !plasmoid) return;
        var pc = plasmoid.configuration;
        database.setSetting("jira.site",  pc.jiraSite  || "");
        database.setSetting("jira.email", pc.jiraEmail || "");
        database.setSetting("jira.token", pc.jiraToken || "");
        database.setSetting("jira.jql",   pc.jiraJql   || "");
    }

    // ------------------------------------------------------------------
    // Cache (issue list)
    // ------------------------------------------------------------------

    function loadCache() {
        if (!database || !database.ready) return;
        var d = database.loadJiraIssues();
        if (d.issues && d.issues.length > 0) {
            issues = d.issues;
            lastFetchedAt = d.fetchedAt;
            _bump();
        }
    }

    function saveCache() {
        if (!database || !database.ready) return;
        database.saveJiraIssues(issues, lastFetchedAt);
    }

    // ------------------------------------------------------------------
    // Fetch
    // ------------------------------------------------------------------

    function fetch() {
        if (loading) {
            _log("fetch skipped: already loading");
            return;
        }
        if (!plasmoid) return;

        var site  = (plasmoid.configuration.jiraSite || "").trim().replace(/\/+$/, "");
        var email = (plasmoid.configuration.jiraEmail || "").trim();
        var token = (plasmoid.configuration.jiraToken || "").trim();
        var jql   = (plasmoid.configuration.jiraJql || "").trim();
        var max   = Math.max(10, Math.min(200, plasmoid.configuration.jiraMaxResults | 0 || 50));

        if (!site || !email || !token) {
            lastError = qsTr("Configurá la URL del sitio, el email y el API token de Jira.");
            _log("fetch aborted: missing credentials (site=" + (!!site) +
                 " email=" + (!!email) + " token=" + (!!token) + ")");
            _bump();
            fetchFinished(false);
            return;
        }
        if (!jql) {
            lastError = qsTr("La consulta JQL está vacía.");
            _log("fetch aborted: empty JQL");
            _bump();
            fetchFinished(false);
            return;
        }

        loading = true;
        lastError = "";
        _bump();

        var fields = "summary,status,priority,issuetype,parent,updated";
        var url = site + "/rest/api/3/search?jql=" + encodeURIComponent(jql)
                + "&maxResults=" + max + "&fields=" + fields;

        _log("fetch start: GET " + site + "/rest/api/3/search");
        _log("  JQL : " + jql);
        _log("  max : " + max + ", fields: " + fields);

        var t0 = Date.now();
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url, true);
        xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(email + ":" + token));
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            store.loading = false;
            var elapsed = Date.now() - t0;

            if (xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText);
                    var raw = data.issues || [];
                    var out = [];
                    for (var i = 0; i < raw.length; i++) {
                        out.push(_normalize(raw[i], site));
                    }
                    store.issues = out;
                    store.lastFetchedAt = Date.now();
                    store.lastError = "";
                    store.saveCache();
                    store._bump();

                    _log("fetch ok in " + elapsed + " ms — " + out.length +
                         " issue(s) (total in JQL: " + (data.total || "?") + ")");
                    if (out.length === 0) {
                        _log("  ⚠  JQL devolvió 0 resultados. Probalo en la UI de Jira " +
                             "para confirmar que la consulta es correcta.");
                    } else {
                        store._logIssues(out);
                        store._logCategoryCounts();
                    }
                    store.fetchFinished(true);
                } catch (e) {
                    store.lastError = qsTr("Error al parsear la respuesta: ") + e;
                    console.warn("[JiraStore] parse error:", e,
                                 "body:", String(xhr.responseText || "").substring(0, 400));
                    store._bump();
                    store.fetchFinished(false);
                }
            } else if (xhr.status === 401 || xhr.status === 403) {
                store.lastError = qsTr("Credenciales inválidas (HTTP %1). Revisá email + API token.").arg(xhr.status);
                console.warn("[JiraStore] auth error: HTTP " + xhr.status);
                store._bump();
                store.fetchFinished(false);
            } else if (xhr.status === 0) {
                store.lastError = qsTr("No se pudo contactar el servidor. ¿La URL es correcta y hay conexión?");
                console.warn("[JiraStore] network error: status=0 (timeout, DNS, TLS, CORS-ish)");
                store._bump();
                store.fetchFinished(false);
            } else {
                var msg = _extractErrorMessage(xhr.responseText);
                store.lastError = qsTr("HTTP %1: %2").arg(xhr.status).arg(msg);
                console.warn("[JiraStore] HTTP " + xhr.status + ": " + msg);
                if (xhr.status === 400) {
                    console.warn("[JiraStore] (HTTP 400 suele indicar un JQL inválido — revisá la consulta)");
                }
                store._bump();
                store.fetchFinished(false);
            }
        };
        try {
            xhr.send();
        } catch (sendErr) {
            store.loading = false;
            store.lastError = qsTr("Error de red: ") + sendErr;
            console.warn("[JiraStore] send error:", sendErr);
            store._bump();
            store.fetchFinished(false);
        }
    }

    function testConnection(site, email, token, callback) {
        site = (site || "").trim().replace(/\/+$/, "");
        email = (email || "").trim();
        token = (token || "").trim();
        if (!site || !email || !token) {
            callback(false, qsTr("Completá los tres campos antes de probar."));
            return;
        }
        var xhr = new XMLHttpRequest();
        xhr.open("GET", site + "/rest/api/3/myself", true);
        xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(email + ":" + token));
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText);
                    callback(true, qsTr("OK — autenticado como %1").arg(data.displayName || email));
                } catch (e) {
                    callback(true, qsTr("OK (respuesta inesperada pero el servidor aceptó las credenciales)."));
                }
            } else if (xhr.status === 401 || xhr.status === 403) {
                callback(false, qsTr("Credenciales rechazadas (HTTP %1).").arg(xhr.status));
            } else if (xhr.status === 0) {
                callback(false, qsTr("No se pudo contactar el servidor."));
            } else {
                callback(false, qsTr("HTTP %1: %2").arg(xhr.status).arg(_extractErrorMessage(xhr.responseText)));
            }
        };
        try {
            xhr.send();
        } catch (e) {
            callback(false, qsTr("Error de red: ") + e);
        }
    }

    // ------------------------------------------------------------------
    // Configurable category filtering
    // ------------------------------------------------------------------

    // Returns the list of issues that match category #catIndex.
    function issuesByJiraCategory(catIndex) {
        var out = [];
        for (var i = 0; i < issues.length; i++) {
            if (matchesJiraCategory(issues[i], catIndex)) out.push(issues[i]);
        }
        return out;
    }

    function countByJiraCategory(catIndex) {
        var c = 0;
        for (var i = 0; i < issues.length; i++) {
            if (matchesJiraCategory(issues[i], catIndex)) c++;
        }
        return c;
    }

    function matchesJiraCategory(issue, catIndex) {
        if (!plasmoid) return false;
        var fields = plasmoid.configuration.jiraCategoryFilterFields || [];
        var values = plasmoid.configuration.jiraCategoryFilterValues || [];
        var field = (fields[catIndex] || "").trim();
        var value = (values[catIndex] || "").trim();

        if (!field) return true;     // category with no filter -> match all
        if (!value) return true;

        var actual = _issueFieldValue(issue, field);
        if (!actual) return false;

        // Comma-or-semicolon separated list of acceptable values.
        var accepts = value.split(/[;,]/).map(function(s) { return s.trim().toLowerCase(); });
        var got = String(actual).trim().toLowerCase();
        for (var i = 0; i < accepts.length; i++) {
            if (accepts[i] && accepts[i] === got) return true;
        }
        return false;
    }

    function _issueFieldValue(issue, field) {
        switch (field) {
            case "statusCategory": return issue.statusCat;
            case "status":         return issue.statusName;
            case "issuetype":      return issue.issuetype;
            case "priority":       return issue.priority;
        }
        return "";
    }

    function totalCount() {
        return issues.length;
    }

    function pendingCount() {
        var c = 0;
        for (var i = 0; i < issues.length; i++) {
            if (issues[i].statusCat !== "done") c++;
        }
        return c;
    }

    // ------------------------------------------------------------------
    // Internals — logging + normalization
    // ------------------------------------------------------------------

    function _log(msg) {
        if (!plasmoid) return;
        if (plasmoid.configuration.jiraDebug === false) return;
        console.log("[JiraStore] " + msg);
    }

    function _logIssues(arr) {
        for (var i = 0; i < arr.length; i++) {
            var it = arr[i];
            var line = "  - " + it.key
                     + " [" + (it.issuetype || "?") + "]"
                     + " (" + (it.statusName || "?") + " / " + (it.statusCat || "?") + ")"
                     + (it.priority ? " {" + it.priority + "}" : "")
                     + " — " + (it.summary || "(sin título)").substring(0, 80);
            if (it.parentKey) line += "  ↳ parent=" + it.parentKey;
            _log(line);
        }
    }

    function _logCategoryCounts() {
        if (!plasmoid) return;
        var n = Math.min(4, Math.max(1, plasmoid.configuration.jiraCategoryCount | 0 || 3));
        var names  = plasmoid.configuration.jiraCategoryNames        || [];
        var fields = plasmoid.configuration.jiraCategoryFilterFields || [];
        var values = plasmoid.configuration.jiraCategoryFilterValues || [];
        for (var i = 0; i < n; i++) {
            var label = names[i] || ("Cat. " + (i + 1));
            var field = fields[i] || "(sin filtro)";
            var value = values[i] || "(cualquiera)";
            var c = countByJiraCategory(i);
            _log("category #" + i + " '" + label + "' [" +
                 field + " = " + value + "]: " + c + " issue(s)");
        }
    }

    function _bump() {
        version = version + 1;
        changed();
    }

    function _normalize(raw, site) {
        var f = raw.fields || {};
        var status = f.status || {};
        var sc = status.statusCategory || {};
        var prio = f.priority || {};
        var it = f.issuetype || {};
        var parent = f.parent || null;
        var parentSummary = "";
        if (parent && parent.fields && parent.fields.summary) {
            parentSummary = parent.fields.summary;
        }
        return {
            key: raw.key || "",
            summary: f.summary || "",
            statusName: status.name || "",
            statusCat: sc.key || "undefined",
            statusColor: sc.colorName || "",
            priority: prio.name || "",
            priorityIconUrl: prio.iconUrl || "",
            issuetype: it.name || "",
            isSubtask: !!it.subtask,
            parentKey: parent ? (parent.key || "") : "",
            parentSummary: parentSummary,
            updated: f.updated || "",
            url: site + "/browse/" + (raw.key || "")
        };
    }

    function _extractErrorMessage(body) {
        if (!body) return "";
        try {
            var d = JSON.parse(body);
            if (d.errorMessages && d.errorMessages.length) return d.errorMessages.join("; ");
            if (d.message) return d.message;
        } catch (e) { /* not json */ }
        return String(body).substring(0, 200);
    }
}
