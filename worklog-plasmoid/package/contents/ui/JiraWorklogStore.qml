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
    property real sprintAvailableSec: 0   // sum of originalEstimate across the sprint's issues
    property real sprintConsumedSec: 0    // sum of *my* worklogs inside the sprint's date range

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
                  "&fields=summary,status,issuetype,timeestimate,timetracking";

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
                    var remaining = 0;
                    if (typeof f.timeestimate === "number") {
                        remaining = f.timeestimate;
                    } else if (f.timetracking && typeof f.timetracking.remainingEstimateSeconds === "number") {
                        remaining = f.timetracking.remainingEstimateSeconds;
                    }
                    out.push({
                        key: r.key || "",
                        summary: f.summary || "",
                        issuetype: (f.issuetype && f.issuetype.name) || "",
                        status: (f.status && f.status.name) || "",
                        remainingSec: remaining | 0
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
    // Reads every issue in any open sprint that's assigned to me, picks
    // the first one with state="active" as THE sprint, then sums
    // originalEstimate (= available) and my worklogs within the sprint's
    // date range (= consumed).
    //
    // If the Jira instance doesn't expose `sprint` as a top-level field,
    // the user can override the field name via worklogSprintField in the
    // config (defaults to "sprint" — works on modern Jira Cloud).

    function fetchSprintInfo(callback) {
        if (!callback) callback = function() {};
        var creds = _creds();
        if (!creds) { callback(false); return; }
        if (!myAccountId) {
            // Resolve /myself first so we can filter worklog authors.
            _jiraGet(creds.site + "/rest/api/3/myself", creds, function(code, body) {
                if (code === 200) {
                    try {
                        var d = JSON.parse(body);
                        store.myAccountId = d.accountId || "";
                    } catch (e) { /* swallow */ }
                }
                _doFetchSprint(creds, callback);
            });
        } else {
            _doFetchSprint(creds, callback);
        }
    }

    function _doFetchSprint(creds, callback) {
        var sprintField = (plasmoidApi && plasmoidApi.configuration.worklogSprintField) || "sprint";
        var jql = "sprint in openSprints() AND assignee = currentUser()";
        var url = creds.site + "/rest/api/3/search/jql?jql=" + encodeURIComponent(jql) +
                  "&maxResults=200" +
                  "&fields=summary,worklog,timeoriginalestimate,timeestimate,timetracking," +
                  encodeURIComponent(sprintField);
        _log("Sprint GET " + url);
        _jiraGet(url, creds, function(code, body) {
            if (code !== 200) {
                _warn("fetchSprintInfo exit=" + code + ": " + body.substring(0, 200));
                store.currentSprint = null;
                store.sprintAvailableSec = 0;
                store.sprintConsumedSec  = 0;
                store._bump();
                callback(false);
                return;
            }
            try {
                var data = JSON.parse(body);
                var issues = data.issues || [];
                if (issues.length === 0) {
                    _log("Sprint: 0 issues — no active sprint visible.");
                    store.currentSprint = null;
                    store.sprintAvailableSec = 0;
                    store.sprintConsumedSec  = 0;
                    store._bump();
                    callback(true);
                    return;
                }

                // Pick the first sprint with state="active" across all issues.
                var active = null;
                for (var i = 0; i < issues.length && !active; i++) {
                    var fld = (issues[i].fields || {})[sprintField];
                    var sprintArr = Array.isArray(fld) ? fld
                                  : (fld ? [fld] : []);
                    for (var j = 0; j < sprintArr.length; j++) {
                        var s = sprintArr[j];
                        if (s && (s.state === "active" || s.state === "ACTIVE")) {
                            active = s; break;
                        }
                    }
                }
                if (!active) {
                    _log("Sprint: ningún sprint con state=active.");
                    store.currentSprint = null;
                    store.sprintAvailableSec = 0;
                    store.sprintConsumedSec  = 0;
                    store._bump();
                    callback(true);
                    return;
                }

                store.currentSprint = {
                    id:        active.id,
                    name:      active.name || "",
                    startDate: active.startDate || "",
                    endDate:   active.endDate   || ""
                };
                var sStart = new Date(store.currentSprint.startDate).getTime();
                var sEnd   = new Date(store.currentSprint.endDate).getTime();

                var total = 0;
                var consumed = 0;
                for (var k = 0; k < issues.length; k++) {
                    // Only count issues that belong to THIS sprint (an issue
                    // may have been moved across sprints).
                    var inThis = false;
                    var f = issues[k].fields || {};
                    var arr = Array.isArray(f[sprintField]) ? f[sprintField]
                            : (f[sprintField] ? [f[sprintField]] : []);
                    for (var m = 0; m < arr.length; m++) {
                        if (arr[m] && arr[m].id === active.id) { inThis = true; break; }
                    }
                    if (!inThis) continue;

                    if (typeof f.timeoriginalestimate === "number") {
                        total += f.timeoriginalestimate;
                    } else if (f.timetracking &&
                               typeof f.timetracking.originalEstimateSeconds === "number") {
                        total += f.timetracking.originalEstimateSeconds;
                    } else if (typeof f.timeestimate === "number") {
                        total += f.timeestimate;
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
                store.sprintAvailableSec = total;
                store.sprintConsumedSec  = consumed;
                store._bump();
                _log("Sprint '" + store.currentSprint.name + "': " +
                     "available=" + total + "s, consumed=" + consumed + "s.");
                callback(true);
            } catch (e) {
                _warn("fetchSprintInfo parse: " + e);
                store.currentSprint = null;
                store.sprintAvailableSec = 0;
                store.sprintConsumedSec  = 0;
                store._bump();
                callback(false);
            }
        });
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
