/*
 * GhStore.qml
 *
 * GitHub Projects (V2) integration. Fetches the items of a user/org
 * project via the GraphQL API (api.github.com/graphql), normalizes them
 * and exposes them grouped by user-defined categories.
 *
 * Auth: HTTP Bearer with a Personal Access Token.
 *   - Classic PATs need scopes: project, read:org, repo.
 *   - Fine-grained PATs need read access to "Projects" (and "Issues" /
 *     "Pull requests" of the linked repos).
 *
 * The token is mirrored to SQLite so a Plasma config loss doesn't wipe
 * it out. The most recent successful response is cached in the gh_cache
 * table so the popup is populated immediately on next launch.
 *
 * Debug logs (enabled by default via plasmoidApi.configuration.ghDebug)
 * surface the GraphQL response status and the per-category counts. Read
 * them with:
 *   journalctl --user -f _COMM=plasmashell | grep -i ghstore
 */

import QtQuick 2.15

QtObject {
    id: store

    property var plasmoidApi: null
    property var database: null

    property var items: []
    property bool loading: false
    property string lastError: ""
    property real lastFetchedAt: 0
    property int version: 0

    // Available status options as returned by the project's status field.
    // Populated on every successful fetch so the config dialog can offer
    // them as autocomplete.
    property var statusOptions: []

    property string lastDebugLog: ""
    property bool hasDebugLog: false

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
        _log("init: " + items.length + " cached item(s); lastFetchedAt=" +
             (lastFetchedAt ? new Date(lastFetchedAt).toISOString() : "never"));
    }

    function applyRefreshSchedule() {
        if (!plasmoidApi) return;
        var minutes = plasmoidApi.configuration.ghRefreshMinutes | 0;
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
        if (!pc.ghToken) { var t = database.getSetting("gh.token", ""); if (t) { pc.ghToken = t; restored.push("token"); } }
        if (!pc.ghOwner) { var o = database.getSetting("gh.owner", ""); if (o) { pc.ghOwner = o; restored.push("owner"); } }
        if (restored.length) _log("restored from cache: " + restored.join(", "));
    }

    function persistCredentials() {
        if (!database || !database.ready || !plasmoidApi) return;
        var pc = plasmoidApi.configuration;
        database.setSetting("gh.token", pc.ghToken || "");
        database.setSetting("gh.owner", pc.ghOwner || "");
    }

    // ------------------------------------------------------------------
    // Cache
    // ------------------------------------------------------------------

    function loadCache() {
        if (!database || !database.ready) return;
        var d = database.loadGhItems();
        if (d.items && d.items.length > 0) {
            items = d.items;
            lastFetchedAt = d.fetchedAt;
            _bump();
        }
    }

    function saveCache() {
        if (!database || !database.ready) return;
        database.saveGhItems(items, lastFetchedAt);
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
        var ts = Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss");
        if (lastDebugLog.length > 0) _appendDebug("\n");
        _appendDebug("=== Fetch " + ts + " ===\n");
        hasDebugLog = true;
        _bump();
        _log("fetch() invocado.");

        if (!plasmoidApi) {
            _warn("[FATAL] plasmoidApi es null — el componente no fue inicializado " +
                  "correctamente. Reinstalá el plasmoide y reiniciá plasmashell.");
            _bump();
            return;
        }
        if (loading) {
            _warn("[abort] Ya hay una carga en curso.");
            return;
        }

        var pc = plasmoidApi.configuration;
        var token = (pc.ghToken || "").trim();
        var owner = (pc.ghOwner || "").trim();
        var ownerType = (pc.ghOwnerType || "user").trim().toLowerCase();
        var number = pc.ghProjectNumber | 0;
        var max = Math.max(10, Math.min(300, pc.ghMaxResults | 0 || 100));

        _log("Credenciales / config:");
        _log("  ghToken         = " + (token ? "[OK, " + token.length + " chars]" : "(VACÍO)"));
        _log("  ghOwner         = " + (owner || "(VACÍO)"));
        _log("  ghOwnerType     = " + ownerType);
        _log("  ghProjectNumber = " + number);
        _log("  ghMaxResults    = " + max);

        var missing = [];
        if (!token) missing.push("token");
        if (!owner) missing.push("owner");
        if (!number) missing.push("project number");
        if (missing.length) {
            lastError = qsTr("Faltan campos: ") + missing.join(", ");
            _warn("[abort] " + lastError);
            _bump();
            fetchFinished(false);
            return;
        }
        if (ownerType !== "user" && ownerType !== "organization") {
            lastError = qsTr("ownerType debe ser 'user' u 'organization'.");
            _warn("[abort] " + lastError);
            _bump();
            fetchFinished(false);
            return;
        }

        loading = true;
        lastError = "";
        _bump();

        var ownerSelector = (ownerType === "organization") ? "organization" : "user";
        var query =
            "query($login: String!, $number: Int!, $first: Int!) {" +
            "  " + ownerSelector + "(login: $login) {" +
            "    projectV2(number: $number) {" +
            "      title" +
            "      items(first: $first) {" +
            "        totalCount" +
            "        nodes {" +
            "          id" +
            "          type" +
            "          updatedAt" +
            "          content {" +
            "            __typename" +
            "            ... on Issue { number title url state repository { nameWithOwner } labels(first: 5) { nodes { name color } } }" +
            "            ... on PullRequest { number title url state isDraft repository { nameWithOwner } labels(first: 5) { nodes { name color } } }" +
            "            ... on DraftIssue { title body }" +
            "          }" +
            "          fieldValues(first: 20) {" +
            "            nodes {" +
            "              __typename" +
            "              ... on ProjectV2ItemFieldSingleSelectValue {" +
            "                name" +
            "                optionId" +
            "                field { ... on ProjectV2SingleSelectField { name } }" +
            "              }" +
            "              ... on ProjectV2ItemFieldTextValue {" +
            "                text" +
            "                field { ... on ProjectV2Field { name } }" +
            "              }" +
            "              ... on ProjectV2ItemFieldNumberValue {" +
            "                number" +
            "                field { ... on ProjectV2Field { name } }" +
            "              }" +
            "              ... on ProjectV2ItemFieldIterationValue {" +
            "                title" +
            "                field { ... on ProjectV2IterationField { name } }" +
            "              }" +
            "            }" +
            "          }" +
            "        }" +
            "      }" +
            "    }" +
            "  }" +
            "}";

        var variables = { login: owner, number: number, first: max };
        var body = JSON.stringify({ query: query, variables: variables });

        _log("");
        _log("Preparando request:");
        _log("  POST https://api.github.com/graphql");
        _log("  Authorization: Bearer " + token.substring(0, 6) + "… (truncado)");
        _log("  variables: " + JSON.stringify(variables));

        var t0 = Date.now();
        var xhr = new XMLHttpRequest();

        try {
            xhr.open("POST", "https://api.github.com/graphql", true);
        } catch (openErr) {
            store.loading = false;
            store.lastError = qsTr("Error abriendo la petición: ") + openErr;
            _warn("xhr.open() lanzó: " + openErr);
            _bump();
            fetchFinished(false);
            return;
        }
        xhr.setRequestHeader("Authorization", "Bearer " + token);
        xhr.setRequestHeader("Accept", "application/json");
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.setRequestHeader("User-Agent", "kde-categorizedtodo-plasmoid");

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;

            store.loading = false;
            var elapsed = Date.now() - t0;
            store._log("HTTP " + xhr.status + " — " + elapsed + " ms.");

            var rawBody = xhr.responseText || "";
            var preview = rawBody.length <= 600 ? rawBody : rawBody.substring(0, 600) + "…";
            store._log("Cuerpo (" + rawBody.length + " bytes): " + preview.replace(/\n/g, "\n  "));

            if (xhr.status === 200) {
                try {
                    var data = JSON.parse(rawBody);
                    if (data.errors && data.errors.length) {
                        var msg = data.errors.map(function(e) { return e.message || JSON.stringify(e); }).join("; ");
                        store.lastError = qsTr("GraphQL: ") + msg;
                        store._warn("GraphQL errors: " + msg);
                        store._bump();
                        store.fetchFinished(false);
                        return;
                    }
                    var ownerNode = data.data ? (data.data.user || data.data.organization) : null;
                    if (!ownerNode || !ownerNode.projectV2) {
                        store.lastError = qsTr("No se encontró el proyecto para %1 #%2").arg(owner).arg(number);
                        store._warn(store.lastError);
                        store._bump();
                        store.fetchFinished(false);
                        return;
                    }
                    var nodes = (ownerNode.projectV2.items && ownerNode.projectV2.items.nodes) || [];
                    var out = [];
                    var seenStatuses = {};
                    var includeClosed = (plasmoidApi.configuration.ghIncludeClosed !== false);
                    var statusField = (plasmoidApi.configuration.ghStatusField || "Status").trim();
                    for (var i = 0; i < nodes.length; i++) {
                        var n = _normalize(nodes[i], statusField);
                        if (!includeClosed && (n.state === "CLOSED" || n.state === "MERGED")) continue;
                        if (n.statusName) seenStatuses[n.statusName] = true;
                        out.push(n);
                    }
                    store.items = out;
                    var opts = [];
                    for (var k in seenStatuses) opts.push(k);
                    opts.sort();
                    store.statusOptions = opts;

                    store.lastFetchedAt = Date.now();
                    store.lastError = "";
                    store.saveCache();
                    store._bump();
                    store._log("Resumen: " + out.length + " item(s) — proyecto «" +
                               (ownerNode.projectV2.title || "?") + "».");
                    store._log("Status options vistos: " + opts.join(", "));
                    store._logCategoryCounts();
                    store.fetchFinished(true);
                } catch (e) {
                    store.lastError = qsTr("Error al parsear la respuesta: ") + e;
                    store._warn("Parse error: " + e);
                    store._bump();
                    store.fetchFinished(false);
                }
            } else if (xhr.status === 401) {
                store.lastError = qsTr("HTTP 401: token rechazado. Revisá scopes del PAT.");
                store._warn(store.lastError);
                store._bump();
                store.fetchFinished(false);
            } else if (xhr.status === 403) {
                store.lastError = qsTr("HTTP 403: sin permisos. ¿Le diste acceso a Projects en el token?");
                store._warn(store.lastError);
                store._bump();
                store.fetchFinished(false);
            } else if (xhr.status === 0) {
                store.lastError = qsTr("No se pudo contactar api.github.com. ¿Hay conexión?");
                store._warn(store.lastError);
                store._bump();
                store.fetchFinished(false);
            } else {
                var emsg = _extractErrorMessage(rawBody);
                store.lastError = qsTr("HTTP %1: %2").arg(xhr.status).arg(emsg);
                store._warn(store.lastError);
                store._bump();
                store.fetchFinished(false);
            }
        };

        try {
            xhr.send(body);
            _log("xhr.send() retornó. Esperando respuesta async…");
        } catch (sendErr) {
            store.loading = false;
            store.lastError = qsTr("Error de red: ") + sendErr;
            store._warn("xhr.send() lanzó: " + sendErr);
            store._bump();
            store.fetchFinished(false);
        }
    }

    function testConnection(token, callback) {
        token = (token || "").trim();
        if (!token) {
            callback(false, qsTr("Completá el token antes de probar."));
            return;
        }
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "https://api.github.com/user", true);
        xhr.setRequestHeader("Authorization", "Bearer " + token);
        xhr.setRequestHeader("Accept", "application/vnd.github+json");
        xhr.setRequestHeader("User-Agent", "kde-categorizedtodo-plasmoid");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try {
                    var d = JSON.parse(xhr.responseText);
                    callback(true, qsTr("OK — autenticado como %1").arg(d.login || "?"));
                } catch (e) {
                    callback(true, qsTr("OK (200, respuesta inesperada)."));
                }
            } else if (xhr.status === 401 || xhr.status === 403) {
                callback(false, qsTr("Credenciales rechazadas (HTTP %1).").arg(xhr.status));
            } else if (xhr.status === 0) {
                callback(false, qsTr("No se pudo contactar api.github.com."));
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

    function itemsByGhCategory(catIndex) {
        var out = [];
        for (var i = 0; i < items.length; i++) {
            if (matchesGhCategory(items[i], catIndex)) out.push(items[i]);
        }
        return out;
    }

    function countByGhCategory(catIndex) {
        var c = 0;
        for (var i = 0; i < items.length; i++) {
            if (matchesGhCategory(items[i], catIndex)) c++;
        }
        return c;
    }

    function matchesGhCategory(item, catIndex) {
        if (!plasmoidApi) return false;
        var fields = plasmoidApi.configuration.ghCategoryFilterFields || [];
        var values = plasmoidApi.configuration.ghCategoryFilterValues || [];
        var field = (fields[catIndex] || "").trim();
        var value = (values[catIndex] || "").trim();

        if (!field) return true;
        if (!value) return true;

        var actual = _itemFieldValue(item, field);
        if (actual === undefined || actual === null || actual === "") return false;

        var accepts = value.split(/[;,]/).map(function(s) { return s.trim().toLowerCase(); });
        var got = String(actual).trim().toLowerCase();
        for (var i = 0; i < accepts.length; i++) {
            if (accepts[i] && accepts[i] === got) return true;
        }
        return false;
    }

    function _itemFieldValue(item, field) {
        switch (field) {
            case "status": return item.statusName;
            case "type":   return item.type;
            case "state":  return item.state;
            case "repo":   return item.repo;
        }
        return "";
    }

    function totalCount() {
        return items.length;
    }

    function openCount() {
        var c = 0;
        for (var i = 0; i < items.length; i++) {
            if (items[i].state === "OPEN") c++;
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
            next = "[…log truncado…]\n" + next.substring(next.length - Math.floor(_maxDebugLogChars / 2));
        }
        lastDebugLog = next;
        if (!hasDebugLog) hasDebugLog = true;
    }

    function _log(msg) {
        _appendDebug(msg + "\n");
        if (!plasmoidApi) return;
        if (plasmoidApi.configuration.ghDebug === false) return;
        console.log("[GhStore] " + msg);
    }

    function _warn(msg) {
        _appendDebug("[!] " + msg + "\n");
        console.warn("[GhStore] " + msg);
    }

    function _logCategoryCounts() {
        if (!plasmoidApi) return;
        var n = Math.min(4, Math.max(1, plasmoidApi.configuration.ghCategoryCount | 0 || 3));
        var names  = plasmoidApi.configuration.ghCategoryNames        || [];
        var fields = plasmoidApi.configuration.ghCategoryFilterFields || [];
        var values = plasmoidApi.configuration.ghCategoryFilterValues || [];
        for (var i = 0; i < n; i++) {
            var label = names[i] || ("Cat. " + (i + 1));
            var field = fields[i] || "(sin filtro)";
            var value = values[i] || "(cualquiera)";
            var c = countByGhCategory(i);
            _log("category #" + i + " '" + label + "' [" +
                 field + " = " + value + "]: " + c + " item(s)");
        }
    }

    function _bump() {
        version = version + 1;
        changed();
    }

    function _normalize(node, statusFieldName) {
        var content = node.content || {};
        var tn = content.__typename || node.type || "";
        var type = tn || "";
        // Normalize type so it matches the category-filter values exactly.
        if (type === "ISSUE" || type === "Issue") type = "Issue";
        else if (type === "PULL_REQUEST" || type === "PullRequest") type = "PullRequest";
        else if (type === "DRAFT_ISSUE" || type === "DraftIssue") type = "DraftIssue";

        var statusName = "";
        var fvNodes = (node.fieldValues && node.fieldValues.nodes) || [];
        var customFields = {};
        for (var i = 0; i < fvNodes.length; i++) {
            var fv = fvNodes[i];
            var fname = fv.field ? (fv.field.name || "") : "";
            if (!fname) continue;
            if (fv.__typename === "ProjectV2ItemFieldSingleSelectValue") {
                customFields[fname] = fv.name || "";
                if (statusFieldName && fname.toLowerCase() === statusFieldName.toLowerCase()) {
                    statusName = fv.name || "";
                }
            } else if (fv.__typename === "ProjectV2ItemFieldTextValue") {
                customFields[fname] = fv.text || "";
            } else if (fv.__typename === "ProjectV2ItemFieldNumberValue") {
                customFields[fname] = String(fv.number);
            } else if (fv.__typename === "ProjectV2ItemFieldIterationValue") {
                customFields[fname] = fv.title || "";
            }
        }

        var labels = [];
        var ln = (content.labels && content.labels.nodes) || [];
        for (var j = 0; j < ln.length; j++) {
            labels.push({ name: ln[j].name || "", color: ln[j].color || "808080" });
        }

        var state = content.state || "";
        if (type === "PullRequest" && content.isDraft) state = "DRAFT";
        if (type === "DraftIssue" && !state) state = "DRAFT";

        return {
            id: node.id || "",
            type: type,
            title: content.title || "(sin título)",
            url: content.url || "",
            number: content.number || 0,
            state: state,
            isDraft: !!content.isDraft,
            repo: content.repository ? (content.repository.nameWithOwner || "") : "",
            updated: node.updatedAt || "",
            statusName: statusName,
            labels: labels,
            customFields: customFields
        };
    }

    function _extractErrorMessage(body) {
        if (!body) return "";
        try {
            var d = JSON.parse(body);
            if (d.errors && d.errors.length) return d.errors.map(function(e) { return e.message; }).join("; ");
            if (d.message) return d.message;
        } catch (e) { /* not json */ }
        return String(body).substring(0, 200);
    }
}
