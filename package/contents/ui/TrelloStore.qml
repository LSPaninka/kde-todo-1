/*
 * TrelloStore.qml
 *
 * Trello integration (REST API v1, https://api.trello.com/1). One board;
 * the popup shows one tab per open list of that board (lists can be hidden
 * and colored from the config). Cards can be read, created, edited, moved
 * between lists, and their checklists / comments managed.
 *
 * Auth: API key + user token, sent in the Authorization header
 *   Authorization: OAuth oauth_consumer_key="<key>", oauth_token="<token>"
 * so they never end up in URLs / logs. The token needs read,write scope.
 *
 * Key / token / board are mirrored to SQLite (settings table) so a Plasma
 * config loss doesn't wipe them. The last successful board snapshot is
 * cached as JSON in the settings table ("trello.cache") so the popup is
 * populated immediately on next launch.
 *
 * Debug logs (trelloDebug, on by default):
 *   journalctl --user -f _COMM=plasmashell | grep -i trellostore
 */

import QtQuick

QtObject {
    id: store

    property var plasmoidApi: null
    property var database: null

    // Overridable only so a local mock server can stand in during tests.
    property string apiBase: "https://api.trello.com/1"

    // Board snapshot.
    property var board: null       // { id, name, url }
    property var lists: []         // [{ id, name, pos }] open lists, by pos
    property var cards: []         // normalized cards (see _normalizeCard)
    property var labels: []        // [{ id, name, color }]
    property var members: []       // [{ id, fullName, username, initials }]
    property string myId: ""

    property bool loading: false
    property string lastError: ""
    property real lastFetchedAt: 0
    property int version: 0

    // Which (visible) list tab the popup should show — set by requestList()
    // when a panel swatch is clicked.
    property int selectedList: -1

    signal changed()
    signal fetchFinished(bool ok)
    signal listRequested(int index)

    property var _refreshTimer: Timer {
        repeat: true
        running: false
        onTriggered: store.fetch()
    }

    // Default palette for lists without a configured color.
    readonly property var _palette: ["#0079bf", "#d29034", "#519839", "#b04632",
                                     "#89609e", "#cd5a91", "#4bbf6b", "#00aecc",
                                     "#838c91", "#e6c60d"]

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    function init() {
        restoreCredentialsFromCache();
        loadCache();
        applyRefreshSchedule();
        _log("init: " + cards.length + " tarjeta(s) en caché; lastFetchedAt=" +
             (lastFetchedAt ? new Date(lastFetchedAt).toISOString() : "never"));
    }

    function applyRefreshSchedule() {
        if (!plasmoidApi) return;
        var minutes = plasmoidApi.configuration.trelloRefreshMinutes | 0;
        if (minutes > 0) {
            _refreshTimer.interval = minutes * 60 * 1000;
            _refreshTimer.running = true;
        } else {
            _refreshTimer.running = false;
        }
    }

    function isConfigured() {
        if (!plasmoidApi) return false;
        var pc = plasmoidApi.configuration;
        return !!((pc.trelloApiKey || "").trim() && (pc.trelloToken || "").trim()
                  && boardRef());
    }

    // ------------------------------------------------------------------
    // Credentials mirror
    // ------------------------------------------------------------------

    function restoreCredentialsFromCache() {
        if (!database || !database.ready || !plasmoidApi) return;
        var pc = plasmoidApi.configuration;
        var restored = [];
        if (!pc.trelloApiKey) { var k = database.getSetting("trello.key", "");   if (k) { pc.trelloApiKey = k; restored.push("key"); } }
        if (!pc.trelloToken)  { var t = database.getSetting("trello.token", ""); if (t) { pc.trelloToken = t;  restored.push("token"); } }
        if (!pc.trelloBoard)  { var b = database.getSetting("trello.board", ""); if (b) { pc.trelloBoard = b;  restored.push("board"); } }
        if (restored.length) _log("restaurado desde caché: " + restored.join(", "));
    }

    function persistCredentials() {
        if (!database || !database.ready || !plasmoidApi) return;
        var pc = plasmoidApi.configuration;
        database.setSetting("trello.key",   pc.trelloApiKey || "");
        database.setSetting("trello.token", pc.trelloToken || "");
        database.setSetting("trello.board", pc.trelloBoard || "");
    }

    // ------------------------------------------------------------------
    // Cache (JSON blob in the settings table)
    // ------------------------------------------------------------------

    function loadCache() {
        if (!database || !database.ready) return;
        var raw = database.getSetting("trello.cache", "");
        if (!raw) return;
        try {
            var d = JSON.parse(raw);
            board   = d.board || null;
            lists   = d.lists || [];
            cards   = d.cards || [];
            labels  = d.labels || [];
            members = d.members || [];
            myId    = d.myId || "";
            lastFetchedAt = d.fetchedAt || 0;
            _bump();
        } catch (e) {
            _warn("caché ilegible: " + e);
        }
    }

    function saveCache() {
        if (!database || !database.ready) return;
        database.setSetting("trello.cache", JSON.stringify({
            board: board, lists: lists, cards: cards, labels: labels,
            members: members, myId: myId, fetchedAt: lastFetchedAt
        }));
    }

    // ------------------------------------------------------------------
    // HTTP
    // ------------------------------------------------------------------

    function _creds() {
        if (!plasmoidApi) return null;
        var pc = plasmoidApi.configuration;
        var key = (pc.trelloApiKey || "").trim();
        var token = (pc.trelloToken || "").trim();
        if (!key || !token) return null;
        return { key: key, token: token };
    }

    // Accepts a board URL (https://trello.com/b/<shortLink>/<slug>), a short
    // link or a full id, and returns what the API accepts as {idBoard}.
    function boardRef() {
        if (!plasmoidApi) return "";
        return parseBoardRef(plasmoidApi.configuration.trelloBoard || "");
    }
    function parseBoardRef(s) {
        s = (s || "").trim();
        if (!s) return "";
        var m = s.match(/trello\.com\/b\/([A-Za-z0-9]+)/);
        if (m) return m[1];
        return s.replace(/[^A-Za-z0-9]/g, "");
    }

    function _qs(query) {
        if (!query) return "";
        var parts = [];
        for (var k in query) {
            if (!query.hasOwnProperty(k)) continue;
            parts.push(encodeURIComponent(k) + "=" + encodeURIComponent(query[k]));
        }
        return parts.length ? "?" + parts.join("&") : "";
    }

    function _extractError(status, body) {
        var msg = "";
        if (body) {
            try {
                var d = JSON.parse(body);
                msg = d.message || d.error || "";
            } catch (e) {
                msg = String(body).substring(0, 200);
            }
        }
        if (status === 401) return qsTr("HTTP 401: key/token rechazados (¿el token tiene permiso read,write?).");
        if (status === 404) return qsTr("HTTP 404: no encontrado (¿tablero correcto?). ") + msg;
        if (status === 0)   return qsTr("No se pudo contactar api.trello.com. ¿Hay conexión?");
        return qsTr("HTTP %1: %2").arg(status).arg(msg);
    }

    // cb(ok, data, errMsg)
    function _request(method, path, query, body, cb) {
        var c = _creds();
        if (!c) { cb(false, null, qsTr("Faltan la API key o el token de Trello.")); return; }
        var url = apiBase + path + _qs(query);
        var xhr = new XMLHttpRequest();
        try {
            xhr.open(method, url, true);
        } catch (e) {
            cb(false, null, qsTr("Error abriendo la petición: ") + e);
            return;
        }
        xhr.setRequestHeader("Authorization",
            'OAuth oauth_consumer_key="' + c.key + '", oauth_token="' + c.token + '"');
        xhr.setRequestHeader("Accept", "application/json");
        if (body !== null && body !== undefined)
            xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            var txt = xhr.responseText || "";
            if (xhr.status >= 200 && xhr.status < 300) {
                var data = null;
                if (txt) { try { data = JSON.parse(txt); } catch (e) { data = txt; } }
                cb(true, data, "");
            } else {
                var err = store._extractError(xhr.status, txt);
                store._warn(method + " " + path + " → " + err);
                cb(false, null, err);
            }
        };
        try {
            xhr.send(body !== null && body !== undefined ? JSON.stringify(body) : null);
        } catch (e) {
            cb(false, null, qsTr("Error de red: ") + e);
        }
    }

    // ------------------------------------------------------------------
    // Fetch the whole board snapshot
    // ------------------------------------------------------------------

    function fetch() {
        if (!plasmoidApi) return;
        if (loading) { _log("fetch ignorado: ya hay una carga en curso."); return; }
        var b = boardRef();
        var missing = [];
        if (!(plasmoidApi.configuration.trelloApiKey || "").trim()) missing.push("API key");
        if (!(plasmoidApi.configuration.trelloToken || "").trim()) missing.push("token");
        if (!b) missing.push(qsTr("tablero"));
        if (missing.length) {
            lastError = qsTr("Faltan campos: ") + missing.join(", ");
            _warn(lastError);
            _bump();
            fetchFinished(false);
            return;
        }

        loading = true;
        lastError = "";
        _bump();
        _log("fetch tablero=" + b);

        var path = "/boards/" + encodeURIComponent(b);
        var result = {};
        var pending = 6;
        var firstErr = "";

        function done(key, ok, data, err) {
            if (ok) result[key] = data;
            else if (!firstErr) firstErr = err;
            pending--;
            if (pending === 0) store._finishFetch(result, firstErr);
        }

        _request("GET", "/members/me", { fields: "id,username,fullName,initials" }, null,
                 function(ok, d, e) { done("me", ok, d, e); });
        _request("GET", path, { fields: "id,name,url,shortLink" }, null,
                 function(ok, d, e) { done("board", ok, d, e); });
        _request("GET", path + "/lists", { filter: "open", fields: "id,name,pos" }, null,
                 function(ok, d, e) { done("lists", ok, d, e); });
        _request("GET", path + "/cards/open", {
                     fields: "id,name,desc,idList,idMembers,idLabels,due,dueComplete,url,shortUrl,pos,badges,dateLastActivity"
                 }, null, function(ok, d, e) { done("cards", ok, d, e); });
        _request("GET", path + "/labels", { fields: "id,name,color", limit: 1000 }, null,
                 function(ok, d, e) { done("labels", ok, d, e); });
        _request("GET", path + "/members", { fields: "id,fullName,username,initials" }, null,
                 function(ok, d, e) { done("members", ok, d, e); });
    }

    function _finishFetch(r, err) {
        loading = false;
        if (err || !r.board || !r.lists || !r.cards) {
            lastError = err || qsTr("Respuesta incompleta de Trello.");
            _warn("fetch falló: " + lastError);
            _bump();
            fetchFinished(false);
            return;
        }
        if (r.me && r.me.id) myId = r.me.id;
        board = { id: r.board.id, name: r.board.name || "", url: r.board.url || "" };

        var ls = (r.lists || []).map(function(l) { return { id: l.id, name: l.name || "", pos: l.pos || 0 }; });
        ls.sort(function(a, b) { return a.pos - b.pos; });
        lists = ls;

        var cs = (r.cards || []).map(_normalizeCard);
        cs.sort(function(a, b) { return a.pos - b.pos; });
        cards = cs;

        labels = (r.labels || []).map(function(l) { return { id: l.id, name: l.name || "", color: l.color || "" }; });
        members = (r.members || []).map(function(m) {
            return { id: m.id, fullName: m.fullName || m.username || "",
                     username: m.username || "", initials: m.initials || _initialsOf(m.fullName || m.username) };
        });

        lastFetchedAt = Date.now();
        lastError = "";
        saveCache();
        _bump();
        _log("OK: tablero «" + board.name + "», " + lists.length + " lista(s), " +
             cards.length + " tarjeta(s), myId=" + (myId ? "[OK]" : "(VACÍO)"));
        fetchFinished(true);
    }

    // ------------------------------------------------------------------
    // Queries
    // ------------------------------------------------------------------

    function _onlyMine() {
        return plasmoidApi ? plasmoidApi.configuration.trelloOnlyMine !== false : true;
    }

    function _hiddenIds() {
        return plasmoidApi ? (plasmoidApi.configuration.trelloHiddenLists || []) : [];
    }

    // Open lists the user didn't hide, in board order.
    function visibleLists() {
        var hidden = _hiddenIds();
        var out = [];
        for (var i = 0; i < lists.length; i++) {
            if (hidden.indexOf(lists[i].id) < 0) out.push(lists[i]);
        }
        return out;
    }

    function listById(id) {
        for (var i = 0; i < lists.length; i++) if (lists[i].id === id) return lists[i];
        return null;
    }
    function listIndex(id) {
        for (var i = 0; i < lists.length; i++) if (lists[i].id === id) return i;
        return -1;
    }

    function isMine(card) {
        return !!(myId && card && card.idMembers && card.idMembers.indexOf(myId) >= 0);
    }

    // Cards of a list, honoring the "only mine" toggle.
    function cardsForList(listId) {
        var mine = _onlyMine();
        var out = [];
        for (var i = 0; i < cards.length; i++) {
            var c = cards[i];
            if (c.idList !== listId) continue;
            if (mine && !isMine(c)) continue;
            out.push(c);
        }
        return out;
    }
    function countForList(listId) { return cardsForList(listId).length; }

    function totalCount() {
        var vis = visibleLists();
        var n = 0;
        for (var i = 0; i < vis.length; i++) n += countForList(vis[i].id);
        return n;
    }

    // Bulleted card titles for the panel tooltip (max 10).
    function cardTitlesForList(listId) {
        var arr = cardsForList(listId);
        if (arr.length === 0) return qsTr("Sin tarjetas.");
        var lines = [];
        for (var i = 0; i < Math.min(10, arr.length); i++) lines.push("• " + arr[i].name);
        if (arr.length > 10) lines.push(qsTr("…y %1 más.").arg(arr.length - 10));
        return lines.join("\n");
    }

    function labelById(id) {
        for (var i = 0; i < labels.length; i++) if (labels[i].id === id) return labels[i];
        return null;
    }
    function memberById(id) {
        for (var i = 0; i < members.length; i++) if (members[i].id === id) return members[i];
        return null;
    }
    function cardById(id) {
        for (var i = 0; i < cards.length; i++) if (cards[i].id === id) return cards[i];
        return null;
    }

    // ------------------------------------------------------------------
    // Colors
    // ------------------------------------------------------------------

    function _mapLookup(key, id) {
        var arr = plasmoidApi ? (plasmoidApi.configuration[key] || []) : [];
        var prefix = id + "=";
        for (var i = 0; i < arr.length; i++) {
            var s = String(arr[i]);
            if (s.indexOf(prefix) === 0) return s.substring(prefix.length);
        }
        return "";
    }

    function listColor(listId) {
        var c = _mapLookup("trelloListColors", listId);
        if (c) return c;
        var i = listIndex(listId);
        return _palette[(i < 0 ? 0 : i) % _palette.length];
    }
    function listTextColor(listId) {
        return _mapLookup("trelloListTextColors", listId) === "black" ? "black" : "white";
    }

    // Trello label color names → hex (current Trello palette).
    function labelColor(name) {
        switch (name) {
            case "green":         return "#4bce97";
            case "green_dark":    return "#1f845a";
            case "green_light":   return "#baf3db";
            case "yellow":        return "#f5cd47";
            case "yellow_dark":   return "#946f00";
            case "yellow_light":  return "#f8e6a0";
            case "orange":        return "#fea362";
            case "orange_dark":   return "#c25100";
            case "orange_light":  return "#fedec8";
            case "red":           return "#f87168";
            case "red_dark":      return "#c9372c";
            case "red_light":     return "#ffd5d2";
            case "purple":        return "#9f8fef";
            case "purple_dark":   return "#6e5dc6";
            case "purple_light":  return "#dfd8fd";
            case "blue":          return "#579dff";
            case "blue_dark":     return "#0c66e4";
            case "blue_light":    return "#cce0ff";
            case "sky":           return "#6cc3e0";
            case "sky_dark":      return "#227d9b";
            case "sky_light":     return "#c6edfb";
            case "lime":          return "#94c748";
            case "lime_dark":     return "#5b7f24";
            case "lime_light":    return "#d3f1a7";
            case "pink":          return "#e774bb";
            case "pink_dark":     return "#ae4787";
            case "pink_light":    return "#fdd0ec";
            case "black":         return "#8590a2";
            case "black_dark":    return "#626f86";
            case "black_light":   return "#dcdfe4";
        }
        return "#6b778c";   // no color
    }

    // Black or white text depending on the background luminance.
    function contrastText(hex) {
        var h = String(hex || "").replace("#", "");
        if (h.length !== 6) return "white";
        var r = parseInt(h.substr(0, 2), 16) / 255;
        var g = parseInt(h.substr(2, 2), 16) / 255;
        var b = parseInt(h.substr(4, 2), 16) / 255;
        var lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        return lum > 0.55 ? "#172b4d" : "white";
    }

    // Stable avatar color per member id.
    function memberColor(id) {
        var s = String(id || "");
        var h = 0;
        for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) & 0x7fffffff;
        var pal = ["#0079bf", "#519839", "#b04632", "#89609e", "#cd5a91",
                   "#00aecc", "#d29034", "#4bbf6b", "#838c91", "#0052cc"];
        return pal[h % pal.length];
    }

    // ------------------------------------------------------------------
    // Panel swatch → popup tab
    // ------------------------------------------------------------------

    function requestList(index) {
        selectedList = index;
        listRequested(index);
    }

    // ------------------------------------------------------------------
    // Writes
    // ------------------------------------------------------------------

    function _replaceCard(raw) {
        var n = _normalizeCard(raw);
        var arr = cards.slice();
        var found = false;
        for (var i = 0; i < arr.length; i++) {
            if (arr[i].id === n.id) {
                // PUT responses don't always carry badges; keep the old ones.
                if (!raw.badges) n.badges = arr[i].badges;
                arr[i] = n;
                found = true;
                break;
            }
        }
        if (!found) arr.push(n);
        arr.sort(function(a, b) { return a.pos - b.pos; });
        cards = arr;
        saveCache();
        _bump();
        return n;
    }

    // fields: { name, desc, idList, idLabels:[], idMembers:[], due (ISO|null), pos }
    // cb(ok, card, err)
    function createCard(fields, cb) {
        var body = {
            idList: fields.idList,
            name: fields.name || "",
            desc: fields.desc || "",
            pos: fields.pos || "bottom",
            idLabels: (fields.idLabels || []).join(","),
            idMembers: (fields.idMembers || []).join(",")
        };
        if (fields.due) body.due = fields.due;
        _log("crear tarjeta en lista " + fields.idList);
        _request("POST", "/cards", null, body, function(ok, data, err) {
            if (!ok) { if (cb) cb(false, null, err); return; }
            var n = store._replaceCard(data);
            if (cb) cb(true, n, "");
        });
    }

    // fields may contain: name, desc, idList, pos, idLabels:[], idMembers:[],
    // due (ISO string or null to clear), dueComplete (bool).
    function updateCard(cardId, fields, cb) {
        var body = {};
        for (var k in fields) {
            if (!fields.hasOwnProperty(k)) continue;
            var v = fields[k];
            if (k === "idLabels" || k === "idMembers") v = (v || []).join(",");
            body[k] = v;
        }
        _log("actualizar tarjeta " + cardId + " (" + Object.keys(body).join(",") + ")");
        _request("PUT", "/cards/" + cardId, null, body, function(ok, data, err) {
            if (!ok) { if (cb) cb(false, null, err); return; }
            var n = store._replaceCard(data);
            if (cb) cb(true, n, "");
        });
    }

    function moveCard(cardId, idList, cb) {
        updateCard(cardId, { idList: idList, pos: "top" }, cb);
    }

    // Detail: card + checklists + comments. cb(ok, detail, err)
    function fetchCardDetail(cardId, cb) {
        var out = {};
        var pending = 3;
        var firstErr = "";
        function done(key, ok, data, err) {
            if (ok) out[key] = data;
            else if (!firstErr) firstErr = err;
            pending--;
            if (pending > 0) return;
            if (firstErr || !out.card) { cb(false, null, firstErr || qsTr("Sin datos.")); return; }
            var card = store._replaceCard(out.card);
            var cls = (out.checklists || []).map(function(cl) {
                var items = (cl.checkItems || []).map(function(it) {
                    return { id: it.id, name: it.name || "", state: it.state || "incomplete", pos: it.pos || 0 };
                });
                items.sort(function(a, b) { return a.pos - b.pos; });
                return { id: cl.id, name: cl.name || "", pos: cl.pos || 0, items: items };
            });
            cls.sort(function(a, b) { return a.pos - b.pos; });
            var cms = (out.actions || []).map(function(a) {
                var mc = a.memberCreator || {};
                return {
                    id: a.id,
                    author: mc.fullName || mc.username || "?",
                    initials: mc.initials || store._initialsOf(mc.fullName || mc.username),
                    authorId: a.idMemberCreator || mc.id || "",
                    date: a.date || "",
                    text: (a.data && a.data.text) || ""
                };
            });
            cb(true, { card: card, checklists: cls, comments: cms }, "");
        }
        _request("GET", "/cards/" + cardId, {
                     fields: "id,name,desc,idList,idMembers,idLabels,due,dueComplete,url,shortUrl,pos,badges,dateLastActivity"
                 }, null, function(ok, d, e) { done("card", ok, d, e); });
        _request("GET", "/cards/" + cardId + "/checklists",
                 { checkItems: "all", checkItem_fields: "name,state,pos", fields: "name,pos" }, null,
                 function(ok, d, e) { done("checklists", ok, d, e); });
        _request("GET", "/cards/" + cardId + "/actions",
                 { filter: "commentCard", limit: 100 }, null,
                 function(ok, d, e) { done("actions", ok, d, e); });
    }

    // Keep the list badges in sync after checklist edits in the modal.
    function syncChecklistBadges(cardId, checklists) {
        var total = 0, checked = 0;
        for (var i = 0; i < checklists.length; i++) {
            var items = checklists[i].items || [];
            total += items.length;
            for (var j = 0; j < items.length; j++) if (items[j].state === "complete") checked++;
        }
        _patchBadges(cardId, { checkItems: total, checkItemsChecked: checked });
    }
    function _patchBadges(cardId, patch) {
        var arr = cards.slice();
        for (var i = 0; i < arr.length; i++) {
            if (arr[i].id !== cardId) continue;
            var c = JSON.parse(JSON.stringify(arr[i]));
            for (var k in patch) c.badges[k] = patch[k];
            arr[i] = c;
            cards = arr;
            saveCache();
            _bump();
            return;
        }
    }

    function setCheckItemState(cardId, checkItemId, complete, cb) {
        _request("PUT", "/cards/" + cardId + "/checkItem/" + checkItemId, null,
                 { state: complete ? "complete" : "incomplete" },
                 function(ok, d, e) { if (cb) cb(ok, d, e); });
    }

    function addCheckItem(checklistId, name, cb) {
        _request("POST", "/checklists/" + checklistId + "/checkItems", null, { name: name },
                 function(ok, d, e) { if (cb) cb(ok, d, e); });
    }

    function deleteCheckItem(checklistId, checkItemId, cb) {
        _request("DELETE", "/checklists/" + checklistId + "/checkItems/" + checkItemId, null, null,
                 function(ok, d, e) { if (cb) cb(ok, d, e); });
    }

    function createChecklist(cardId, name, cb) {
        _request("POST", "/checklists", null, { idCard: cardId, name: name || "Checklist" },
                 function(ok, d, e) { if (cb) cb(ok, d, e); });
    }

    function addComment(cardId, text, cb) {
        _request("POST", "/cards/" + cardId + "/actions/comments", null, { text: text },
                 function(ok, d, e) {
                     if (ok) {
                         var c = store.cardById(cardId);
                         if (c) store._patchBadges(cardId, { comments: ((c.badges && c.badges.comments) | 0) + 1 });
                     }
                     if (cb) cb(ok, d, e);
                 });
    }

    // Used by the config page's "Probar conexión". cb(ok, message)
    function testConnection(cb) {
        _request("GET", "/members/me", { fields: "fullName,username" }, null, function(ok, d, e) {
            if (ok) cb(true, qsTr("OK — autenticado como %1").arg((d && (d.fullName || d.username)) || "?"));
            else cb(false, e);
        });
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    function _initialsOf(name) {
        var parts = String(name || "").trim().split(/\s+/);
        var s = "";
        for (var i = 0; i < parts.length && s.length < 2; i++) if (parts[i]) s += parts[i][0];
        return s.toUpperCase() || "?";
    }

    function _normalizeCard(c) {
        var b = c.badges || {};
        return {
            id: c.id,
            name: c.name || "",
            desc: c.desc || "",
            idList: c.idList || "",
            idMembers: c.idMembers || [],
            idLabels: c.idLabels || [],
            due: c.due || "",
            dueComplete: !!c.dueComplete,
            url: c.shortUrl || c.url || "",
            pos: c.pos || 0,
            lastActivity: c.dateLastActivity || "",
            badges: {
                checkItems: b.checkItems | 0,
                checkItemsChecked: b.checkItemsChecked | 0,
                comments: b.comments | 0,
                description: !!(b.description || c.desc),
                attachments: b.attachments | 0
            }
        };
    }

    function _bump() {
        version = version + 1;
        changed();
    }

    function _log(msg) {
        if (plasmoidApi && plasmoidApi.configuration.trelloDebug === false) return;
        console.log("[TrelloStore] " + msg);
    }

    function _warn(msg) {
        console.warn("[TrelloStore] " + msg);
    }
}
