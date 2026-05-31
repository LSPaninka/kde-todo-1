/*
 * JiraWorklogStore.qml
 *
 * Talks to the Jira Cloud REST API to:
 *   - fetch worklogs in a given week (POST /rest/api/3/search/jql with
 *     fields=summary,worklog, filtering by author client-side),
 *   - resolve current user (GET /rest/api/3/myself) for that filter,
 *   - list assignable issues for the picker (POST /search/jql with the
 *     configured worklogIssueJql),
 *   - create / update / delete worklogs against /rest/api/3/issue/<id>/worklog.
 *
 * Auth: HTTP Basic with email + API token. Credentials are read from the
 * *same* KConfig file as the Categorized ToDo plasmoid (categorizedtodorc),
 * so editing them in either widget updates both.
 */

import QtQuick 2.15

QtObject {
    id: store

    property var plasmoidApi: null

    property var worklogs: []         // {id, issueKey, issueSummary, started (ms), durationSec, comment}
    property var assignableIssues: [] // {key, summary, issuetype, status, remainingSec}
    property string myAccountId: ""

    // Active sprint of the user (or null). Filled by fetchSprintInfo().
    property var currentSprint: null  // {id, name, startDate, endDate}
    property real sprintAvailableSec: 0   // sum of remaining estimate across the sprint's issues
    property real sprintConsumedSec: 0    // sum of *my* worklogs inside the sprint's date range
    // Per-issue breakdown of the available hours (for the tooltip under
    // the Horas ring): [{ key, summary, remainingSec }], only issues with
    // remainingSec > 0, sorted descending by remainingSec. Always sums to
    // sprintAvailableSec.
    property var sprintAvailableBreakdown: []

    property bool loading: false
    property string lastError: ""
    property real lastFetchedAt: 0
    property int version: 0

    property real currentWeekStartMs: 0   // 00:00 of Sunday of the week being shown

    property string lastDebugLog: ""
    property bool hasDebugLog: false

    signal changed()
    signal fetchFinished(bool ok)
    signal createFinished(bool ok, string err)
    signal updateFinished(bool ok, string err)
    signal deleteFinished(bool ok, string err)

    // ------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------

    function init() {
        if (!plasmoidApi) {
            _warn("[FATAL] plasmoidApi es null.");
            return;
        }
        _log("init: store listo.");
    }

    function totalCount() { return worklogs.length; }

    function clearDebugLog() {
        lastDebugLog = "";
        hasDebugLog = false;
        _bump();
    }

    function fetchWeek(weekStartDate) {
        var ts = Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss");
        if (lastDebugLog.length > 0) _appendDebug("\n");
        _appendDebug("=== Worklog fetch " + ts + " ===\n");
        hasDebugLog = true;
        _bump();

        if (!plasmoidApi) { _warn("[FATAL] plasmoidApi null."); return; }
        if (loading)      { _warn("[abort] ya hay un fetch en curso."); return; }

        var creds = _creds();
        if (!creds) return;

        currentWeekStartMs = _startOfDay(new Date(weekStartDate.getTime())).getTime();
        var weekEndMs = currentWeekStartMs + 7 * 24 * 60 * 60 * 1000;
        var weekStartJql = _formatJqlDate(new Date(currentWeekStartMs));
        var weekEndJql   = _formatJqlDate(new Date(weekEndMs - 1));

        loading = true;
        lastError = "";
        _bump();

        _log("Semana: " + new Date(currentWeekStartMs).toISOString() +
             " → " + new Date(weekEndMs).toISOString());
        _log("JQL: worklogAuthor = currentUser() AND worklogDate >= '" +
             weekStartJql + "' AND worklogDate <= '" + weekEndJql + "'");

        // 1) Resolve current user (one-shot, then cached on store.myAccountId)
        var doSearch = function() {
            var jql = "worklogAuthor = currentUser() AND worklogDate >= \"" +
                       weekStartJql + "\" AND worklogDate <= \"" + weekEndJql + "\"";
            var url = creds.site + "/rest/api/3/search/jql?jql=" +
                      encodeURIComponent(jql) +
                      "&maxResults=200&fields=summary,worklog";
            _log("GET " + url);
            _jiraGet(url, creds, function(code, body) {
                if (code !== 200) {
                    store.loading = false;
                    store.lastError = qsTr("HTTP %1 al buscar issues con worklogs.").arg(code);
                    _warn("Search /search/jql exit=" + code + ": " + body.substring(0, 300));
                    store._bump();
                    store.fetchFinished(false);
                    return;
                }
                _processWeekResponse(body, currentWeekStartMs, weekEndMs);
            });
        };

        if (!myAccountId) {
            _log("GET /rest/api/3/myself (cacheamos accountId)");
            _jiraGet(creds.site + "/rest/api/3/myself", creds, function(code, body) {
                if (code !== 200) {
                    store.loading = false;
                    store.lastError = qsTr("No se pudo obtener el usuario actual (HTTP %1).").arg(code);
                    _warn("myself exit=" + code + ": " + body.substring(0, 200));
                    store._bump();
                    store.fetchFinished(false);
                    return;
                }
                try {
                    var data = JSON.parse(body);
                    store.myAccountId = data.accountId || "";
                    _log("accountId = " + store.myAccountId);
                    doSearch();
                } catch (e) {
                    store.loading = false;
                    _warn("parse myself: " + e);
                    store.lastError = qsTr("Respuesta inválida de /myself.");
                    store._bump();
                    store.fetchFinished(false);
                }
            });
        } else {
            doSearch();
        }
    }

    function _processWeekResponse(body, weekStartMs, weekEndMs) {
        try {
            var data = JSON.parse(body);
            var issues = data.issues || [];
            var out = [];
            for (var i = 0; i < issues.length; i++) {
                var iss = issues[i];
                var fields = iss.fields || {};
                var summary = fields.summary || "";
                var wlContainer = fields.worklog || {};
                var wls = wlContainer.worklogs || [];
                for (var j = 0; j < wls.length; j++) {
                    var w = wls[j];
                    // Filter: only mine, and only in this week.
                    var startedMs = _parseJiraDate(w.started);
                    if (startedMs < weekStartMs || startedMs >= weekEndMs) continue;
                    var author = w.author || {};
                    if (myAccountId && author.accountId !== myAccountId) continue;
                    out.push({
                        id: "" + (w.id || ""),
                        issueId: "" + (iss.id || ""),
                        issueKey: iss.key || "",
                        issueSummary: summary,
                        started: startedMs,
                        durationSec: w.timeSpentSeconds | 0,
                        comment: _extractAdfText(w.comment)
                    });
                }
            }
            out.sort(function(a, b) { return a.started - b.started; });
            store.worklogs = out;
            store.lastFetchedAt = Date.now();
            store.loading = false;
            store._bump();

            _log("Recibí " + issues.length + " issue(s); filtré a " + out.length +
                 " worklog(s) propios en la semana.");
            for (var k = 0; k < Math.min(out.length, 25); k++) {
                var w2 = out[k];
                _log("  - " + w2.issueKey + " " +
                     new Date(w2.started).toISOString().substring(0, 16) +
                     " (" + _formatHours(w2.durationSec) + ") " +
                     (w2.comment || "").substring(0, 40));
            }
            store.fetchFinished(true);
        } catch (e) {
            store.loading = false;
            store.lastError = qsTr("Error parseando la respuesta: ") + e;
            _warn("parse error: " + e);
            store._bump();
            store.fetchFinished(false);
        }
    }

    // ------------------------------------------------------------------
    // Issue picker (for the new-worklog modal)
    // ------------------------------------------------------------------

    function fetchAssignableIssues(callback) {
        var creds = _creds();
        if (!creds) { callback(false); return; }

        var pc = plasmoidApi.configuration;
        var jql = (pc.worklogIssueJql || "assignee = currentUser() AND statusCategory != Done").trim();
        var max = Math.max(10, Math.min(200, pc.worklogIssueMax | 0 || 50));

        var url = creds.site + "/rest/api/3/search/jql?jql=" +
                  encodeURIComponent(jql) +
                  "&maxResults=" + max +
                  // timeestimate = remaining estimate (seconds). timetracking
                  // is the human-readable variant; we keep both for
                  // resilience across Jira instances.
                  "&fields=summary,status,issuetype,timeoriginalestimate,timeestimate,timetracking";

        _log("Picker GET " + url);
        _jiraGet(url, creds, function(code, body) {
            if (code !== 200) {
                _warn("Picker exit=" + code + ": " + body.substring(0, 200));
                callback(false);
                return;
            }
            try {
                var data = JSON.parse(body);
                var raw = data.issues || [];
                var out = [];
                for (var i = 0; i < raw.length; i++) {
                    var r = raw[i];
                    var f = r.fields || {};
                    out.push({
                        key: r.key || "",
                        summary: f.summary || "",
                        issuetype: (f.issuetype && f.issuetype.name) || "",
                        status: (f.status && f.status.name) || "",
                        // Mirrors the same mode the gauge uses so the column
                        // on the right of the picker shows consistent values.
                        remainingSec: _remainingSec(f)
                    });
                }
                store.assignableIssues = out;
                store._bump();
                _log("Picker: " + out.length + " issue(s).");
                callback(true);
            } catch (e) {
                _warn("Picker parse error: " + e);
                callback(false);
            }
        });
    }

    // ------------------------------------------------------------------
    // Sprint info (for the gauges at the bottom of the popup)
    // ------------------------------------------------------------------
    // Three strategies (configurable via worklogSprintStrategy):
    //
    //   "subtask-customfield" (default): query subtasks assigned to me
    //     with the sprint custom field (customfield_10020 on most Jira
    //     instances) and pick the entry with state="active". This works
    //     even when parent stories are unassigned and only the subtasks
    //     belong to the user.
    //
    //   "agile-board": fetch the active sprint of a specific board via
    //     /rest/agile/1.0/board/{id}/sprint?state=active. Requires the
    //     board id in worklogSprintBoardId. Most direct lookup; useful
    //     when you know exactly which board to ask.
    //
    //   "assignee-jql": original 0.4.0 behavior — query "sprint in
    //     openSprints() AND assignee = currentUser()" relying on the
    //     `sprint` field being exposed top-level. Kept as a fallback for
    //     setups where the previous strategy worked.

    function fetchSprintInfo(callback) {
        if (!callback) callback = function() {};
        var creds = _creds();
        if (!creds) { callback(false); return; }
        var doIt = function() { _dispatchSprintStrategy(creds, callback); };
        if (!myAccountId) {
            _jiraGet(creds.site + "/rest/api/3/myself", creds, function(code, body) {
                if (code === 200) {
                    try { store.myAccountId = JSON.parse(body).accountId || ""; }
                    catch (e) { /* swallow */ }
                }
                doIt();
            });
        } else {
            doIt();
        }
    }

    function _dispatchSprintStrategy(creds, callback) {
        var s = (plasmoidApi && plasmoidApi.configuration.worklogSprintStrategy) || "subtask-customfield";
        _log("Sprint strategy: " + s);
        if (s === "agile-board")        _fetchSprintAgileBoard(creds, callback);
        else if (s === "assignee-jql")  _fetchSprintAssigneeJql(creds, callback);
        else                            _fetchSprintSubtaskField(creds, callback);
    }

    // ----- Strategy: subtask + customfield_10020 ----------------------
    function _fetchSprintSubtaskField(creds, callback) {
        var field = (plasmoidApi && plasmoidApi.configuration.worklogSprintField) || "customfield_10020";
        // Don't filter by statusCategory — Done subtasks still contribute
        // to "Quemadas" (consumed) for this sprint.
        var jql = "issuetype in subTaskIssueTypes() AND assignee = currentUser()";
        var url = creds.site + "/rest/api/3/search/jql?jql=" + encodeURIComponent(jql) +
                  "&maxResults=200" +
                  "&fields=summary,worklog,timeoriginalestimate,timeestimate,timetracking," +
                  encodeURIComponent(field);
        _log("Sprint(subtask) GET " + url);
        _jiraGet(url, creds, function(code, body) {
            if (code !== 200) {
                _warn("subtask-customfield exit=" + code + ": " + body.substring(0, 240));
                _clearSprint(); callback(false); return;
            }
            try {
                var data = JSON.parse(body);
                var issues = data.issues || [];
                _log("subtask-customfield: " + issues.length + " subtarea(s) recibidas.");
                if (issues.length === 0) { _clearSprint(); callback(true); return; }

                var active = _findActiveSprintIn(issues, field);
                if (!active) {
                    _warn("Ningún sprint activo en el campo '" + field +
                          "' de las subtareas. ¿Cambió el id del custom field? " +
                          "Configurá worklogSprintField si hace falta.");
                    _clearSprint(); callback(true); return;
                }
                _setActiveSprint(active);
                _computeSprintTotalsFromIssues(issues, active, field);
                callback(true);
            } catch (e) {
                _warn("subtask-customfield parse: " + e);
                _clearSprint(); callback(false);
            }
        });
    }

    // ----- Strategy: agile board → active sprint → issues -------------
    function _fetchSprintAgileBoard(creds, callback) {
        var boardId = ((plasmoidApi && plasmoidApi.configuration.worklogSprintBoardId) | 0);
        if (boardId <= 0) {
            _warn("agile-board: 'Board ID' no configurado. Seteá worklogSprintBoardId.");
            _clearSprint(); callback(false); return;
        }
        var url = creds.site + "/rest/agile/1.0/board/" + boardId + "/sprint?state=active";
        _log("Sprint(agile) GET " + url);
        _jiraGet(url, creds, function(code, body) {
            if (code !== 200) {
                _warn("agile-board sprint list exit=" + code + ": " + body.substring(0, 240));
                _clearSprint(); callback(false); return;
            }
            try {
                var data = JSON.parse(body);
                var values = data.values || [];
                if (values.length === 0) {
                    _log("agile-board: el board " + boardId + " no tiene sprints activos.");
                    _clearSprint(); callback(true); return;
                }
                var active = values[0];
                _setActiveSprint(active);

                // Now grab the issues in that sprint assigned to me.
                var jql2 = "sprint = " + active.id + " AND assignee = currentUser()";
                var url2 = creds.site + "/rest/api/3/search/jql?jql=" + encodeURIComponent(jql2) +
                           "&maxResults=200" +
                           "&fields=summary,worklog,timeoriginalestimate,timeestimate,timetracking";
                _log("Sprint(agile) issues GET " + url2);
                _jiraGet(url2, creds, function(c2, b2) {
                    if (c2 !== 200) {
                        _warn("agile-board issues exit=" + c2 + ": " + b2.substring(0, 240));
                        // We still have the sprint id + dates; just zero out totals.
                        store.sprintAvailableSec = 0;
                        store.sprintConsumedSec  = 0;
                        store.sprintAvailableBreakdown = [];
                        store._bump();
                        callback(true);
                        return;
                    }
                    try {
                        var d2 = JSON.parse(b2);
                        // No need to filter by sprint id — JQL already did.
                        _computeSprintTotalsFromIssues(d2.issues || [], active, null);
                        callback(true);
                    } catch (e) {
                        _warn("agile-board issues parse: " + e);
                        callback(false);
                    }
                });
            } catch (e) {
                _warn("agile-board parse: " + e);
                _clearSprint(); callback(false);
            }
        });
    }

    // ----- Strategy: original assignee + openSprints ------------------
    function _fetchSprintAssigneeJql(creds, callback) {
        var field = (plasmoidApi && plasmoidApi.configuration.worklogSprintField) || "customfield_10020";
        var jql = "sprint in openSprints() AND assignee = currentUser()";
        var url = creds.site + "/rest/api/3/search/jql?jql=" + encodeURIComponent(jql) +
                  "&maxResults=200" +
                  "&fields=summary,worklog,timeoriginalestimate,timeestimate,timetracking," +
                  encodeURIComponent(field);
        _log("Sprint(assignee) GET " + url);
        _jiraGet(url, creds, function(code, body) {
            if (code !== 200) {
                _warn("assignee-jql exit=" + code + ": " + body.substring(0, 240));
                _clearSprint(); callback(false); return;
            }
            try {
                var data = JSON.parse(body);
                var issues = data.issues || [];
                if (issues.length === 0) { _clearSprint(); callback(true); return; }
                var active = _findActiveSprintIn(issues, field);
                if (!active) { _clearSprint(); callback(true); return; }
                _setActiveSprint(active);
                _computeSprintTotalsFromIssues(issues, active, field);
                callback(true);
            } catch (e) {
                _warn("assignee-jql parse: " + e);
                _clearSprint(); callback(false);
            }
        });
    }

    // ----- Helpers used by all strategies -----------------------------
    function _findActiveSprintIn(issues, field) {
        for (var i = 0; i < issues.length; i++) {
            var arr = (issues[i].fields || {})[field] || [];
            if (!Array.isArray(arr)) arr = arr ? [arr] : [];
            for (var j = 0; j < arr.length; j++) {
                if (arr[j] && (arr[j].state === "active" || arr[j].state === "ACTIVE"))
                    return arr[j];
            }
        }
        return null;
    }
    function _setActiveSprint(s) {
        store.currentSprint = {
            id:        s.id,
            name:      s.name || "",
            startDate: s.startDate || "",
            endDate:   s.endDate || ""
        };
    }
    function _clearSprint() {
        store.currentSprint = null;
        store.sprintAvailableSec = 0;
        store.sprintConsumedSec  = 0;
        store.sprintAvailableBreakdown = [];
        store._bump();
    }

    // Remaining-hours strategy (selectable from config). "api" trusts
    // Jira's remainingEstimateSeconds; "calculated" computes
    // max(0, originalEstimate - timeSpent) which is what users want when
    // remainingEstimate hasn't been kept up to date.
    function _remainingSec(f) {
        if (!f) return 0;
        var mode = (plasmoidApi && plasmoidApi.configuration.worklogRemainingMode) || "api";
        if (mode === "calculated") {
            var orig = (typeof f.timeoriginalestimate === "number")
                       ? f.timeoriginalestimate
                       : (f.timetracking && typeof f.timetracking.originalEstimateSeconds === "number")
                           ? f.timetracking.originalEstimateSeconds
                           : 0;
            var spent = (f.timetracking && typeof f.timetracking.timeSpentSeconds === "number")
                        ? f.timetracking.timeSpentSeconds
                        : 0;
            return Math.max(0, orig - spent);
        }
        // "api"
        if (f.timetracking && typeof f.timetracking.remainingEstimateSeconds === "number") {
            return f.timetracking.remainingEstimateSeconds;
        }
        if (typeof f.timeestimate === "number") return f.timeestimate;
        return 0;
    }

    // If `fieldOrNull` is a string, only issues whose sprint custom-field
    // array contains the active.id are counted. If null, the caller has
    // pre-filtered (e.g. via "sprint = N" JQL).
    function _computeSprintTotalsFromIssues(issues, active, fieldOrNull) {
        var sStart = new Date(active.startDate).getTime();
        var sEnd   = new Date(active.endDate).getTime();
        var available = 0, consumed = 0;
        var breakdown = [];
        for (var k = 0; k < issues.length; k++) {
            var f = issues[k].fields || {};
            if (fieldOrNull) {
                var arr = f[fieldOrNull] || [];
                if (!Array.isArray(arr)) arr = arr ? [arr] : [];
                var hit = false;
                for (var x = 0; x < arr.length; x++) {
                    if (arr[x] && arr[x].id === active.id) { hit = true; break; }
                }
                if (!hit) continue;
            }
            // "Disponible" is now what's still pending for THIS issue, not
            // the original estimate — issues fully consumed in earlier
            // sprints contribute 0 instead of bloating the total.
            var rem = _remainingSec(f);
            available += rem;
            if (rem > 0) {
                breakdown.push({
                    key: issues[k].key || "",
                    summary: f.summary || "",
                    remainingSec: rem
                });
            }

            var wls = (f.worklog && f.worklog.worklogs) || [];
            for (var w = 0; w < wls.length; w++) {
                var wo = wls[w];
                var sm = _parseJiraDate(wo.started);
                if (sm < sStart || sm > sEnd) continue;
                var auth = wo.author || {};
                if (myAccountId && auth.accountId !== myAccountId) continue;
                consumed += wo.timeSpentSeconds | 0;
            }
        }
        breakdown.sort(function(a, b) { return b.remainingSec - a.remainingSec; });
        store.sprintAvailableSec = available;
        store.sprintConsumedSec  = consumed;
        store.sprintAvailableBreakdown = breakdown;
        store._bump();
        _log("Sprint '" + active.name + "': remaining=" + available + "s, consumed=" + consumed +
             "s, breakdown=" + breakdown.length + " issue(s).");
    }

    // ------------------------------------------------------------------
    // Create / Update / Delete
    // ------------------------------------------------------------------

    function createWorklog(issueKey, startedDate, durationSec, comment) {
        var creds = _creds();
        if (!creds) return;
        var url = creds.site + "/rest/api/3/issue/" + encodeURIComponent(issueKey) + "/worklog";
        var body = {
            started: _formatJiraStarted(startedDate),
            timeSpentSeconds: durationSec | 0
        };
        if (comment && comment.length > 0) body.comment = _commentAdf(comment);

        _log("POST " + url + "  body=" + JSON.stringify(body));
        _jiraSend("POST", url, creds, JSON.stringify(body), function(code, respBody) {
            if (code === 200 || code === 201) {
                _log("create OK.");
                store.createFinished(true, "");
            } else {
                var msg = _extractErrorMessage(respBody);
                _warn("create exit=" + code + ": " + msg);
                store.createFinished(false, "HTTP " + code + ": " + msg);
            }
        });
    }

    function updateWorklog(issueKey, worklogId, startedDate, durationSec, comment) {
        var creds = _creds();
        if (!creds) return;
        var url = creds.site + "/rest/api/3/issue/" + encodeURIComponent(issueKey) +
                  "/worklog/" + encodeURIComponent(worklogId);
        var body = {
            started: _formatJiraStarted(startedDate),
            timeSpentSeconds: durationSec | 0
        };
        if (comment !== undefined && comment !== null) body.comment = _commentAdf(comment);

        _log("PUT " + url + "  body=" + JSON.stringify(body));
        _jiraSend("PUT", url, creds, JSON.stringify(body), function(code, respBody) {
            if (code === 200) {
                _log("update OK.");
                store.updateFinished(true, "");
            } else {
                var msg = _extractErrorMessage(respBody);
                _warn("update exit=" + code + ": " + msg);
                store.updateFinished(false, "HTTP " + code + ": " + msg);
            }
        });
    }

    function deleteWorklog(issueKey, worklogId) {
        var creds = _creds();
        if (!creds) return;
        var url = creds.site + "/rest/api/3/issue/" + encodeURIComponent(issueKey) +
                  "/worklog/" + encodeURIComponent(worklogId);
        _log("DELETE " + url);
        _jiraSend("DELETE", url, creds, null, function(code, respBody) {
            if (code === 204 || code === 200) {
                _log("delete OK.");
                store.deleteFinished(true, "");
            } else {
                var msg = _extractErrorMessage(respBody);
                _warn("delete exit=" + code + ": " + msg);
                store.deleteFinished(false, "HTTP " + code + ": " + msg);
            }
        });
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function _creds() {
        if (!plasmoidApi) return null;
        var pc = plasmoidApi.configuration;
        var site  = (pc.jiraSite  || "").trim().replace(/\/+$/, "");
        var email = (pc.jiraEmail || "").trim();
        var token = (pc.jiraToken || "").trim();
        if (!site || !email || !token) {
            lastError = qsTr("Faltan credenciales (sitio, email o token). Configurá la pestaña Jira.");
            _warn("Faltan credenciales: site=" + (!!site) + " email=" + (!!email) + " token=" + (!!token));
            _bump();
            return null;
        }
        return { site: site, email: email, token: token };
    }

    function _jiraGet(url, creds, callback) {
        _jiraSend("GET", url, creds, null, callback);
    }

    function _jiraSend(method, url, creds, body, callback) {
        var xhr = new XMLHttpRequest();
        xhr.open(method, url, true);
        xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(creds.email + ":" + creds.token));
        xhr.setRequestHeader("Accept", "application/json");
        if (body) xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            callback(xhr.status | 0, xhr.responseText || "");
        };
        try {
            xhr.send(body);
        } catch (e) {
            _warn("xhr.send threw: " + e);
            callback(0, "");
        }
    }

    function _startOfDay(d) {
        var c = new Date(d);
        c.setHours(0, 0, 0, 0);
        return c;
    }

    function _formatJqlDate(d) {
        return d.getFullYear() + "-" +
               _pad2(d.getMonth() + 1) + "-" +
               _pad2(d.getDate());
    }

    // Jira wants "2026-05-12T15:00:00.000+0000" (with timezone).
    function _formatJiraStarted(d) {
        var y  = d.getFullYear();
        var mo = _pad2(d.getMonth() + 1);
        var da = _pad2(d.getDate());
        var hh = _pad2(d.getHours());
        var mm = _pad2(d.getMinutes());
        var ss = _pad2(d.getSeconds());
        var off = -d.getTimezoneOffset();  // minutes east of UTC
        var sign = off >= 0 ? "+" : "-";
        var ao = Math.abs(off);
        var oh = _pad2(Math.floor(ao / 60));
        var om = _pad2(ao % 60);
        return y + "-" + mo + "-" + da + "T" + hh + ":" + mm + ":" + ss + ".000" + sign + oh + om;
    }

    function _parseJiraDate(s) {
        if (!s) return 0;
        var d = new Date(s);
        return isNaN(d.getTime()) ? 0 : d.getTime();
    }

    function _pad2(n) { return n < 10 ? "0" + n : "" + n; }

    // Minimal ADF wrapper for plain-text comments. Anything fancier
    // (mentions, formatting) would need a richer editor.
    function _commentAdf(text) {
        return {
            type: "doc",
            version: 1,
            content: [{
                type: "paragraph",
                content: [{ type: "text", text: text }]
            }]
        };
    }

    // Walk an ADF tree and concatenate every text node, preserving
    // paragraph breaks so the result reads like the comment did in Jira.
    function _extractAdfText(adf) {
        if (!adf) return "";
        if (typeof adf === "string") return adf;
        if (adf.type === "text") return adf.text || "";
        if (adf.type === "paragraph") {
            var paraTxt = (adf.content || []).map(_extractAdfText).join("");
            return paraTxt + "\n";
        }
        if (adf.content && Array.isArray(adf.content)) {
            return adf.content.map(_extractAdfText).join("");
        }
        return "";
    }

    function _extractErrorMessage(body) {
        if (!body) return "";
        try {
            var d = JSON.parse(body);
            if (d.errorMessages && d.errorMessages.length) return d.errorMessages.join("; ");
            if (d.errors) {
                var parts = [];
                for (var k in d.errors) parts.push(k + ": " + d.errors[k]);
                if (parts.length) return parts.join("; ");
            }
            if (d.message) return d.message;
        } catch (e) { /* not json */ }
        return String(body).substring(0, 240);
    }

    function _formatHours(sec) {
        if (!sec) return "0";
        var h = Math.floor(sec / 3600);
        var m = Math.floor((sec % 3600) / 60);
        if (h > 0 && m > 0) return h + "h " + m + "m";
        if (h > 0)          return h + "h";
        return m + "m";
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
        if (plasmoidApi.configuration.worklogDebug === false) return;
        console.log("[JiraWorklog] " + msg);
    }

    function _warn(msg) {
        _appendDebug("[!] " + msg + "\n");
        console.warn("[JiraWorklog] " + msg);
    }

    function _bump() {
        version = version + 1;
        changed();
    }
}
