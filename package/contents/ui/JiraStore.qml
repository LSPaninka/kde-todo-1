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
 * Debug logs (enabled by default via plasmoidApi.configuration.jiraDebug)
 * surface the URL, JQL, HTTP status, per-issue summary and the count
 * each category ended up with. Read them with:
 *   journalctl --user -f _COMM=plasmashell | grep -i jirastore
 */

import QtQuick 2.15

QtObject {
    id: store

    property var plasmoidApi: null
    property var database: null

    property var issues: []
    property bool loading: false
    property string lastError: ""
    property real lastFetchedAt: 0
    property int version: 0

    // Which category tab the popup should show. Bumped by requestCategory()
    // when the user clicks a panel swatch so the popup jumps to that tab.
    property int selectedCategory: 0

    // Active sprint (or null): { id, name, startDate, endDate }. Extracted
    // from the sprint custom field of the fetched issues.
    property var currentSprint: null

    // Plain-text accumulator for the in-UI debug dialog. Always populated
    // (independent of the jiraDebug console toggle).
    property string lastDebugLog: ""
    property bool hasDebugLog: false

    signal changed()
    signal fetchFinished(bool ok)
    // Emitted by requestCategory(); JiraView listens and switches tabs.
    signal categoryRequested(int index)

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
        if (!plasmoidApi) return;
        var minutes = plasmoidApi.configuration.jiraRefreshMinutes | 0;
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
        if (!database || !database.ready || !plasmoidApi) return;
        var pc = plasmoidApi.configuration;
        var restored = [];
        if (!pc.jiraSite)  { var s = database.getSetting("jira.site",  ""); if (s) { pc.jiraSite  = s; restored.push("site"); } }
        if (!pc.jiraEmail) { var e = database.getSetting("jira.email", ""); if (e) { pc.jiraEmail = e; restored.push("email"); } }
        if (!pc.jiraToken) { var t = database.getSetting("jira.token", ""); if (t) { pc.jiraToken = t; restored.push("token"); } }
        if (!pc.jiraJql)   { var j = database.getSetting("jira.jql",   ""); if (j) { pc.jiraJql   = j; restored.push("jql"); } }
        if (restored.length) _log("restored from cache: " + restored.join(", "));
    }

    function persistCredentials() {
        if (!database || !database.ready || !plasmoidApi) return;
        var pc = plasmoidApi.configuration;
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
        var sp = database.getSetting("jira.sprint", "");
        if (sp) { try { currentSprint = JSON.parse(sp); } catch (e) { /* ignore */ } }
    }

    function saveCache() {
        if (!database || !database.ready) return;
        database.saveJiraIssues(issues, lastFetchedAt);
        database.setSetting("jira.sprint", currentSprint ? JSON.stringify(currentSprint) : "");
    }

    // ------------------------------------------------------------------
    // Fetch
    // ------------------------------------------------------------------

    function clearDebugLog() {
        lastDebugLog = "";
        hasDebugLog = false;
        _bump();
    }

    function fetch() {
        // Append-only: separator between fetch attempts so the history
        // of multiple attempts is visible at once.
        var ts = Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss");
        if (lastDebugLog.length > 0) _appendDebug("\n");
        _appendDebug("=== Fetch " + ts + " ===\n");
        hasDebugLog = true;
        _bump();
        _log("fetch() invocado.");

        if (!plasmoidApi) {
            _warn("[FATAL] plasmoidApi es null — el componente no fue inicializado " +
                  "correctamente (la asignación en main.qml no llegó). Reinstalá el " +
                  "plasmoide y reiniciá plasmashell.");
            _bump();
            return;
        }
        if (loading) {
            _warn("[abort] Ya hay una carga en curso; esperá a que termine.");
            return;
        }

        var pc = plasmoidApi.configuration;
        var site  = (pc.jiraSite || "").trim().replace(/\/+$/, "");
        var email = (pc.jiraEmail || "").trim();
        var token = (pc.jiraToken || "").trim();
        var jql   = (pc.jiraJql || "").trim();
        var max   = Math.max(10, Math.min(200, pc.jiraMaxResults | 0 || 50));

        _log("Credenciales (de plasmoidApi.configuration):");
        _log("  jiraSite   = " + (site  || "(VACÍO)"));
        _log("  jiraEmail  = " + (email || "(VACÍO)"));
        _log("  jiraToken  = " + (token ? "[OK, " + token.length + " caracteres]" : "(VACÍO)"));
        _log("  jiraJql    = " + (jql   || "(VACÍO)"));
        _log("  maxResults = " + max);

        var missing = [];
        if (!site)  missing.push("site");
        if (!email) missing.push("email");
        if (!token) missing.push("token");
        if (missing.length) {
            lastError = qsTr("Faltan credenciales: ") + missing.join(", ");
            _warn("[abort] Faltan campos: " + missing.join(", ") +
                  ". Configurá la pestaña 'Jira' del diálogo de configuración.");
            _bump();
            fetchFinished(false);
            return;
        }
        if (!jql) {
            lastError = qsTr("La consulta JQL está vacía.");
            _warn("[abort] JQL vacío. Probá con: assignee = currentUser()");
            _bump();
            fetchFinished(false);
            return;
        }
        if (!/^https?:\/\//i.test(site)) {
            _warn("La URL no empieza con http:// o https://. Esto suele dar status=0.");
        }
        if (/^http:\/\//i.test(site)) {
            _warn("Estás usando HTTP (sin TLS). La conexión va en claro.");
        }

        loading = true;
        lastError = "";
        _bump();

        var sprintField = (pc.jiraSprintField || "").trim();
        var fields = "summary,status,priority,issuetype,parent,updated,timetracking";
        if (sprintField) fields += "," + sprintField;
        // /rest/api/3/search was removed in 2025; /rest/api/3/search/jql is
        // the replacement. The new endpoint returns at most `maxResults`
        // issues and uses cursor pagination (nextPageToken + isLast) instead
        // of the old `total` field. We don't paginate — first page is
        // enough for the plasmoid use case.
        var url = site + "/rest/api/3/search/jql?jql=" + encodeURIComponent(jql)
                + "&maxResults=" + max + "&fields=" + fields;
        var authHeader = "Basic " + Qt.btoa(email + ":" + token);

        _log("");
        _log("Preparando request:");
        _log("  GET " + (url.length > 250 ? url.substring(0, 250) + "…" : url));
        _log("  Authorization: " + authHeader.substring(0, 16) + "… (truncado)");
        _log("  Accept: application/json");

        var t0 = Date.now();
        var xhr = new XMLHttpRequest();

        try {
            xhr.open("GET", url, true);
            _log("xhr.open() OK.");
        } catch (openErr) {
            store.loading = false;
            store.lastError = qsTr("Error abriendo la petición: ") + openErr;
            _warn("xhr.open() lanzó: " + openErr);
            _bump();
            fetchFinished(false);
            return;
        }
        xhr.setRequestHeader("Authorization", authHeader);
        xhr.setRequestHeader("Accept", "application/json");

        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.OPENED) {
                store._log("readyState=1 (OPENED).");
            } else if (xhr.readyState === XMLHttpRequest.HEADERS_RECEIVED) {
                store._log("readyState=2 (HEADERS_RECEIVED) — status preliminar=" + xhr.status);
            } else if (xhr.readyState === XMLHttpRequest.LOADING) {
                store._log("readyState=3 (LOADING) — recibiendo cuerpo…");
            }
            if (xhr.readyState !== XMLHttpRequest.DONE) return;

            store.loading = false;
            var elapsed = Date.now() - t0;
            store._log("readyState=4 (DONE) — completado en " + elapsed + " ms.");
            store._log("HTTP status: " + xhr.status + " " + (xhr.statusText || ""));

            var body = xhr.responseText || "";
            store._log("Tamaño del cuerpo: " + body.length + " bytes.");
            if (body.length > 0) {
                var preview = body.length <= 600 ? body : body.substring(0, 600) + "…";
                store._log("Cuerpo:");
                store._log("  " + preview.replace(/\n/g, "\n  "));
            } else {
                store._log("Cuerpo: (vacío)");
            }

            if (xhr.status === 200) {
                try {
                    var data = JSON.parse(body);
                    var raw = data.issues || [];
                    var out = [];
                    for (var i = 0; i < raw.length; i++) {
                        out.push(_normalize(raw[i], site));
                    }
                    store.issues = out;
                    store.currentSprint = store._extractActiveSprint(raw, sprintField);
                    store.lastFetchedAt = Date.now();
                    store.lastError = "";
                    store.saveCache();
                    store._bump();

                    store._log("");
                    var more = (data.isLast === false) || (typeof data.nextPageToken === "string"
                                                          && data.nextPageToken.length > 0);
                    store._log("Resumen: " + out.length + " issue(s) recibida(s) " +
                               "en esta página (isLast=" + (data.isLast === undefined ? "?" : data.isLast) +
                               ", nextPageToken=" + (data.nextPageToken ? "[present]" : "(none)") + ").");
                    if (more) {
                        store._log("  Hay más issues disponibles — el plasmoide solo muestra la primera página. " +
                                   "Reducí el JQL o subí maxResults si querés ver todas.");
                    }
                    if (out.length === 0) {
                        store._warn("JQL devolvió 0 resultados. Probalo en la UI de Jira para confirmar.");
                    } else {
                        store._logIssues(out);
                        store._logCategoryCounts();
                    }
                    store.fetchFinished(true);
                } catch (e) {
                    store.lastError = qsTr("Error al parsear la respuesta: ") + e;
                    store._warn("Parse error: " + e);
                    store._bump();
                    store.fetchFinished(false);
                }
            } else if (xhr.status === 401) {
                store.lastError = qsTr("HTTP 401: credenciales rechazadas. Revisá email + token.");
                store._warn("HTTP 401 — el email/token son incorrectos o el token fue revocado.");
                store._warn("Generá un token nuevo en: id.atlassian.com/manage-profile/security/api-tokens");
                store._bump();
                store.fetchFinished(false);
            } else if (xhr.status === 403) {
                store.lastError = qsTr("HTTP 403: el token no tiene permisos sobre este recurso.");
                store._warn("HTTP 403 — el token NO tiene permisos para leer issues.");
                store._warn("El usuario debe tener 'Browse Projects' en al menos un proyecto.");
                store._warn("Si Jira tiene scopes en la cuenta, asegurate de marcar 'read:issue' (o equivalente).");
                store._bump();
                store.fetchFinished(false);
            } else if (xhr.status === 404) {
                store.lastError = qsTr("HTTP 404: el endpoint no existe en este servidor.");
                store._warn("HTTP 404 — la URL del sitio puede estar mal, o la instancia es Server/DC sin API v3.");
                store._bump();
                store.fetchFinished(false);
            } else if (xhr.status === 410) {
                var msg410 = _extractErrorMessage(body);
                store.lastError = qsTr("HTTP 410: el endpoint fue removido por Atlassian. ") + msg410;
                store._warn("HTTP 410 — Atlassian removió este endpoint.");
                store._warn("El plasmoide usa /rest/api/3/search/jql; si Atlassian publica un cambio nuevo,");
                store._warn("revisá https://developer.atlassian.com/changelog/ para la URL actual.");
                store._warn("Mensaje del servidor: " + msg410);
                store._bump();
                store.fetchFinished(false);
            } else if (xhr.status === 400) {
                var msg400 = _extractErrorMessage(body);
                store.lastError = qsTr("HTTP 400: ") + msg400;
                store._warn("HTTP 400 — JQL inválido. Mensaje del servidor: " + msg400);
                store._bump();
                store.fetchFinished(false);
            } else if (xhr.status === 0) {
                store.lastError = qsTr("No se pudo contactar el servidor. ¿La URL es correcta y hay conexión?");
                store._warn("status=0 — posibles causas:");
                store._warn("  1) URL del sitio incorrecta o DNS no resuelve");
                store._warn("  2) Falla TLS (certificado inválido / cadena rota)");
                store._warn("  3) Sin conexión de red (proxy, firewall)");
                store._warn("  4) Plasma sin permisos para abrir sockets HTTPS");
                store._bump();
                store.fetchFinished(false);
            } else {
                var msgX = _extractErrorMessage(body);
                store.lastError = qsTr("HTTP %1: %2").arg(xhr.status).arg(msgX);
                store._warn("HTTP " + xhr.status + ": " + msgX);
                store._bump();
                store.fetchFinished(false);
            }
        };

        try {
            _log("Disparando xhr.send()…");
            xhr.send();
            _log("xhr.send() retornó. Esperando respuesta async…");
        } catch (sendErr) {
            store.loading = false;
            store.lastError = qsTr("Error de red: ") + sendErr;
            store._warn("xhr.send() lanzó: " + sendErr);
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
    // Issue detail (for the click-to-open modal): a single-issue GET that
    // pulls the richer fields the list call skips (assignee, description,
    // timetracking, comments). cb(ok, detail, err).
    // ------------------------------------------------------------------

    function fetchIssueDetail(key, cb) {
        if (!plasmoidApi) { cb(false, null, qsTr("Sin configuración.")); return; }
        var pc = plasmoidApi.configuration;
        var site  = (pc.jiraSite || "").trim().replace(/\/+$/, "");
        var email = (pc.jiraEmail || "").trim();
        var token = (pc.jiraToken || "").trim();
        if (!site || !email || !token) { cb(false, null, qsTr("Faltan credenciales.")); return; }

        var fields = "summary,status,priority,issuetype,parent,assignee,description," +
                     "timetracking,created,updated,comment";
        var url = site + "/rest/api/3/issue/" + encodeURIComponent(key) + "?fields=" + fields;

        var xhr = new XMLHttpRequest();
        xhr.open("GET", url, true);
        xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(email + ":" + token));
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try {
                    var d = JSON.parse(xhr.responseText);
                    cb(true, store._normalizeDetail(d, site), "");
                } catch (e) {
                    cb(false, null, qsTr("Error al parsear la respuesta: ") + e);
                }
            } else {
                cb(false, null, qsTr("HTTP %1: %2").arg(xhr.status)
                                    .arg(store._extractErrorMessage(xhr.responseText)));
            }
        };
        try { xhr.send(); }
        catch (e) { cb(false, null, qsTr("Error de red: ") + e); }
    }

    // ------------------------------------------------------------------
    // Status transitions (mirror of worklog-calendar's flow):
    //   GET  /rest/api/3/issue/{key}/transitions  → available transitions
    //   POST /rest/api/3/issue/{key}/transitions  → apply one
    // ------------------------------------------------------------------

    function _jiraCreds() {
        if (!plasmoidApi) return null;
        var pc = plasmoidApi.configuration;
        var site  = (pc.jiraSite || "").trim().replace(/\/+$/, "");
        var email = (pc.jiraEmail || "").trim();
        var token = (pc.jiraToken || "").trim();
        if (!site || !email || !token) return null;
        return { site: site, email: email, token: token };
    }

    // cb(ok, [{ id, name, toStatus, toStatusColor }])
    function fetchTransitions(key, cb) {
        cb = cb || function() {};
        var c = _jiraCreds();
        if (!c) { cb(false, []); return; }
        var url = c.site + "/rest/api/3/issue/" + encodeURIComponent(key) + "/transitions";
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url, true);
        xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(c.email + ":" + c.token));
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText);
                    var arr = data.transitions || [];
                    var out = [];
                    for (var i = 0; i < arr.length; i++) {
                        var t = arr[i];
                        var to = t.to || {};
                        out.push({
                            id: "" + (t.id || ""),
                            name: t.name || "",
                            toStatus: to.name || "",
                            toStatusColor: (to.statusCategory || {}).colorName || ""
                        });
                    }
                    cb(true, out);
                } catch (e) {
                    store._warn("transitions parse: " + e);
                    cb(false, []);
                }
            } else {
                store._warn("transitions HTTP " + xhr.status);
                cb(false, []);
            }
        };
        try { xhr.send(); } catch (e) { store._warn("transitions send: " + e); cb(false, []); }
    }

    // cb(ok, errMsg)
    function transitionIssue(key, transitionId, cb) {
        cb = cb || function() {};
        var c = _jiraCreds();
        if (!c) { cb(false, qsTr("Faltan credenciales.")); return; }
        var url = c.site + "/rest/api/3/issue/" + encodeURIComponent(key) + "/transitions";
        var body = JSON.stringify({ transition: { id: "" + transitionId } });
        var xhr = new XMLHttpRequest();
        xhr.open("POST", url, true);
        xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(c.email + ":" + c.token));
        xhr.setRequestHeader("Accept", "application/json");
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 204 || xhr.status === 200) {
                cb(true, "");
            } else {
                cb(false, store._extractErrorMessage(xhr.responseText) || ("HTTP " + xhr.status));
            }
        };
        try { xhr.send(body); } catch (e) { cb(false, qsTr("Error de red: ") + e); }
    }

    function _normalizeDetail(raw, site) {
        var f = raw.fields || {};
        var status = f.status || {};
        var sc = status.statusCategory || {};
        var prio = f.priority || {};
        var it = f.issuetype || {};
        var parent = f.parent || null;
        var assignee = f.assignee || null;
        var tt = f.timetracking || {};
        var commentsRaw = (f.comment && f.comment.comments) || [];
        var comments = [];
        for (var i = 0; i < commentsRaw.length; i++) {
            var c = commentsRaw[i];
            comments.push({
                author: (c.author && c.author.displayName) || qsTr("(desconocido)"),
                created: c.created || "",
                body: _adfToText(c.body)
            });
        }
        return {
            key: raw.key || "",
            summary: f.summary || "",
            statusName: status.name || "",
            statusColor: sc.colorName || "",
            statusCat: sc.key || "",
            issuetype: it.name || "",
            isSubtask: !!it.subtask,
            priority: prio.name || "",
            parentKey: parent ? (parent.key || "") : "",
            parentSummary: (parent && parent.fields) ? (parent.fields.summary || "") : "",
            assignee: assignee ? (assignee.displayName || "") : "",
            description: _adfToText(f.description),
            originalEstimate: _fmtSeconds(tt.originalEstimateSeconds),
            timeSpent: _fmtSeconds(tt.timeSpentSeconds),
            remaining: _fmtSeconds(tt.remainingEstimateSeconds),
            originalSec: tt.originalEstimateSeconds | 0,
            spentSec: tt.timeSpentSeconds | 0,
            hasTime: !!(tt.originalEstimateSeconds || tt.timeSpentSeconds || tt.remainingEstimateSeconds),
            created: f.created || "",
            updated: f.updated || "",
            comments: comments,
            url: site + "/browse/" + (raw.key || "")
        };
    }

    // Flatten an Atlassian Document Format (ADF) node tree to plain text.
    function _adfToText(node) {
        if (!node) return "";
        if (typeof node === "string") return node;
        var out = "";
        function walk(n) {
            if (!n) return;
            if (n.type === "text") { out += n.text || ""; return; }
            if (n.type === "hardBreak") { out += "\n"; return; }
            var children = n.content || [];
            for (var i = 0; i < children.length; i++) walk(children[i]);
            if (n.type === "paragraph" || n.type === "heading" ||
                n.type === "listItem" || n.type === "blockquote") {
                out += "\n";
            }
        }
        walk(node);
        return out.replace(/\n{3,}/g, "\n\n").replace(/[ \t]+\n/g, "\n").trim();
    }

    // Seconds → "1h 30m" style (workday-agnostic, matches Jira's raw hours).
    function _fmtSeconds(s) {
        s = s | 0;
        if (s <= 0) return "0h";
        var hh = Math.floor(s / 3600);
        var mm = Math.floor((s % 3600) / 60);
        var parts = [];
        if (hh > 0) parts.push(hh + "h");
        if (mm > 0) parts.push(mm + "m");
        return parts.length ? parts.join(" ") : "0h";
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

    // Multi-line "KEY — summary" list for a category, for the panel tooltip.
    // Capped so a huge category doesn't produce an unwieldy tooltip.
    function issueTitlesForCategory(catIndex) {
        var lines = [];
        var max = 12;
        for (var i = 0; i < issues.length && lines.length < max; i++) {
            if (!matchesJiraCategory(issues[i], catIndex)) continue;
            var it = issues[i];
            var sm = (it.summary || "").trim();
            if (sm.length > 60) sm = sm.substring(0, 57) + "…";
            lines.push((it.key || "?") + " — " + sm);
        }
        var total = countByJiraCategory(catIndex);
        if (total === 0) return qsTr("Sin incidencias en esta categoría.");
        if (total > lines.length) lines.push(qsTr("…y %1 más.").arg(total - lines.length));
        return lines.join("\n");
    }

    // Ask the popup to open a specific category tab (from a panel swatch click).
    function requestCategory(index) {
        selectedCategory = index;
        categoryRequested(index);
    }

    function matchesJiraCategory(issue, catIndex) {
        if (!plasmoidApi) return false;
        var fields = plasmoidApi.configuration.jiraCategoryFilterFields || [];
        var values = plasmoidApi.configuration.jiraCategoryFilterValues || [];
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

    // Summed time tracking across all fetched issues (for the popup footer bar).
    function totalOriginalSec() {
        var s = 0;
        for (var i = 0; i < issues.length; i++) s += issues[i].originalSec | 0;
        return s;
    }
    function totalSpentSec() {
        var s = 0;
        for (var i = 0; i < issues.length; i++) s += issues[i].spentSec | 0;
        return s;
    }

    // Scan the raw issues for a sprint object in `field` whose state is active.
    function _extractActiveSprint(rawIssues, field) {
        if (!field) return null;
        for (var i = 0; i < rawIssues.length; i++) {
            var arr = (rawIssues[i].fields || {})[field];
            if (!arr) continue;
            if (!Array.isArray(arr)) arr = [arr];
            for (var j = 0; j < arr.length; j++) {
                var s = arr[j];
                if (s && typeof s === "object" &&
                    (s.state === "active" || s.state === "ACTIVE")) {
                    return {
                        id: s.id,
                        name: s.name || "",
                        startDate: s.startDate || "",
                        endDate: s.endDate || ""
                    };
                }
            }
        }
        return null;
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

    readonly property int _maxDebugLogChars: 80000

    function _appendDebug(line) {
        var next = lastDebugLog + line;
        if (next.length > _maxDebugLogChars) {
            // Drop the oldest half so we keep the most recent activity.
            next = "[…log truncado…]\n" + next.substring(next.length - Math.floor(_maxDebugLogChars / 2));
        }
        lastDebugLog = next;
        if (!hasDebugLog) hasDebugLog = true;
    }

    function _log(msg) {
        _appendDebug(msg + "\n");
        if (!plasmoidApi) return;
        if (plasmoidApi.configuration.jiraDebug === false) return;
        console.log("[JiraStore] " + msg);
    }

    function _warn(msg) {
        _appendDebug("[!] " + msg + "\n");
        console.warn("[JiraStore] " + msg);
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
        if (!plasmoidApi) return;
        var n = Math.min(10, Math.max(1, plasmoidApi.configuration.jiraCategoryCount | 0 || 3));
        var names  = plasmoidApi.configuration.jiraCategoryNames        || [];
        var fields = plasmoidApi.configuration.jiraCategoryFilterFields || [];
        var values = plasmoidApi.configuration.jiraCategoryFilterValues || [];
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
        var tt = f.timetracking || {};
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
            // Time tracking (seconds) for the per-card progress bar.
            originalSec: tt.originalEstimateSeconds | 0,
            spentSec: tt.timeSpentSeconds | 0,
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
