/*
 * NotionStore.qml
 *
 * Shells out to the Notion CLI (`ntn`) to list and edit pages. Auth is
 * delegated entirely to ntn — the user runs `ntn login` once (or exports
 * NOTION_API_TOKEN) and the plasmoid just reads its stdout. No tokens are
 * stored in plasmoid.configuration.
 *
 * The executable data engine (PlasmaCore.DataSource engine="executable")
 * is used to invoke ntn. Each command runs through `sh -c '<cmd>'` with
 * single-quoted shell-safe arguments. All variable input is escaped via
 * _shellQuote so a malicious page title can't break out and execute
 * arbitrary shell code.
 *
 * Endpoints used:
 *   - ntn api v1/search -X POST -d <json>   →  list of pages
 *   - ntn pages get <id>                    →  Markdown body
 *   - ntn pages update <id> --title …       →  title rename
 *   - ntn pages update <id> --content …     →  body replacement
 *
 * See docs/NOTION.md for setup instructions.
 */

import QtQuick 2.15
import org.kde.plasma.core 2.0 as PlasmaCore

QtObject {
    id: store

    property var plasmoidApi: null

    property var pages: []
    property bool loading: false
    property string lastError: ""
    property real lastFetchedAt: 0
    property int version: 0

    property string lastDebugLog: ""
    property bool hasDebugLog: false

    signal changed()
    signal fetchFinished(bool ok)
    signal pageContentReady(string pageId, string markdown, bool ok, string err)
    signal pageUpdated(string pageId, bool ok, string err)

    property var _refreshTimer: Timer {
        repeat: true
        running: false
        onTriggered: store.fetch()
    }

    property var _cmd: PlasmaCore.DataSource {
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var exitCode = data["exit code"];
            var stdout = data["stdout"] || "";
            var stderr = data["stderr"] || "";
            disconnectSource(sourceName);
            var cb = store._pending[sourceName];
            if (cb) {
                delete store._pending[sourceName];
                try { cb(exitCode | 0, stdout, stderr); }
                catch (e) { store._warn("callback threw: " + e); }
            }
        }
    }
    property var _pending: ({})
    property int _seq: 0

    // ------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------

    function init() {
        applyRefreshSchedule();
        _log("init: NotionStore listo. Comando: " + _ntnBin() + ".");
        _log("Para autenticarte corré `ntn login` (o exportá NOTION_API_TOKEN) " +
             "antes de usar el modo.");
    }

    function applyRefreshSchedule() {
        if (!plasmoidApi) return;
        var minutes = plasmoidApi.configuration.notionRefreshMinutes | 0;
        if (minutes > 0) {
            _refreshTimer.interval = minutes * 60 * 1000;
            _refreshTimer.running = true;
            _log("auto-refresh cada " + minutes + " min.");
        } else {
            _refreshTimer.running = false;
            _log("auto-refresh deshabilitado (manual).");
        }
    }

    function totalCount() {
        return pages.length;
    }

    function clearDebugLog() {
        lastDebugLog = "";
        hasDebugLog = false;
        _bump();
    }

    // ------------------------------------------------------------------
    // Fetch: list pages via /v1/search
    // ------------------------------------------------------------------

    function fetch() {
        var ts = Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss");
        if (lastDebugLog.length > 0) _appendDebug("\n");
        _appendDebug("=== Notion fetch " + ts + " ===\n");
        hasDebugLog = true;
        _bump();
        _log("fetch() invocado.");

        if (!plasmoidApi) {
            _warn("[FATAL] plasmoidApi es null.");
            _bump();
            return;
        }
        if (loading) {
            _warn("[abort] Ya hay una carga en curso.");
            return;
        }

        var pc = plasmoidApi.configuration;
        var query  = (pc.notionQuery  || "").trim();
        var filter = (pc.notionFilter || "page").trim();
        var max    = Math.max(10, Math.min(200, pc.notionMaxResults | 0 || 50));

        _log("Parámetros:");
        _log("  query  = " + (query || "(vacío)"));
        _log("  filter = " + filter);
        _log("  max    = " + max);

        loading = true;
        lastError = "";
        _bump();

        // Body for /v1/search.
        var bodyObj = {
            page_size: max,
            filter: { property: "object", value: filter }
        };
        if (query.length > 0) bodyObj.query = query;
        var body = JSON.stringify(bodyObj);

        var cmd = _ntnBin() + " api v1/search -X POST -d " + _shellQuote(body);
        _log("Comando: " + cmd);

        var t0 = Date.now();
        _run(cmd, function(code, stdout, stderr) {
            store.loading = false;
            var elapsed = Date.now() - t0;
            store._log("Completado en " + elapsed + " ms (exit=" + code + ").");
            if (stderr.length > 0) {
                store._log("stderr (primeros 400 bytes):");
                store._log("  " + stderr.substring(0, 400).replace(/\n/g, "\n  "));
            }
            if (stdout.length > 0) {
                var preview = stdout.length <= 600 ? stdout : stdout.substring(0, 600) + "…";
                store._log("stdout (" + stdout.length + " bytes):");
                store._log("  " + preview.replace(/\n/g, "\n  "));
            } else {
                store._log("stdout: (vacío)");
            }

            if (code !== 0) {
                store.lastError = qsTr("ntn salió con código %1.").arg(code);
                store._warn("ntn salió con código " + code + ".");
                if (stderr.indexOf("Not logged in") >= 0 ||
                    stderr.indexOf("authentication") >= 0 ||
                    stderr.indexOf("401") >= 0) {
                    store._warn("Parece que no estás autenticado — corré `ntn login`.");
                }
                if (stderr.indexOf("not found") >= 0 || stderr.indexOf("No such file") >= 0) {
                    store._warn("Parece que `ntn` no está en el PATH. Instalalo desde " +
                                "https://ntn.dev o seteá la ruta en la pestaña Notion.");
                }
                store._bump();
                store.fetchFinished(false);
                return;
            }

            try {
                var data = JSON.parse(stdout);
                var raw = data.results || [];
                var out = [];
                for (var i = 0; i < raw.length; i++) {
                    out.push(_normalize(raw[i]));
                }
                store.pages = out;
                store.lastFetchedAt = Date.now();
                store.lastError = "";
                store._bump();
                store._log("");
                store._log("Resumen: " + out.length + " página(s) recibida(s). " +
                           "has_more=" + (data.has_more === true) +
                           (data.next_cursor ? ", next_cursor=[present]" : "") + ".");
                if (data.has_more === true) {
                    store._log("  (Hay más páginas; el plasmoide solo muestra la primera tanda.)");
                }
                store._logPages(out);
                store.fetchFinished(true);
            } catch (e) {
                store.lastError = qsTr("Error al parsear la respuesta JSON: ") + e;
                store._warn("parse error: " + e);
                store._bump();
                store.fetchFinished(false);
            }
        });
    }

    // ------------------------------------------------------------------
    // Read full page content as Markdown (for the edit dialog)
    // ------------------------------------------------------------------

    function getPageContent(pageId) {
        _log("getPageContent(" + pageId + ")");
        var cmd = _ntnBin() + " pages get " + _shellQuote(pageId);
        _run(cmd, function(code, stdout, stderr) {
            if (code !== 0) {
                store._warn("ntn pages get exit=" + code + ": " +
                            stderr.substring(0, 200));
                store.pageContentReady(pageId, "", false, stderr || ("exit " + code));
                return;
            }
            store.pageContentReady(pageId, stdout, true, "");
        });
    }

    // ------------------------------------------------------------------
    // Update title and/or content
    // ------------------------------------------------------------------

    function updatePage(pageId, newTitle, newContent) {
        _log("updatePage(" + pageId + ", title=" + (newTitle ? "yes" : "no") +
             ", content=" + (newContent !== null && newContent !== undefined ? "yes" : "no") + ")");

        // Title update via the raw API (PATCH /v1/pages/<id> with the
        // appropriate properties.title block). This is more portable than
        // relying on `ntn pages update`'s undocumented --title flag.
        if (newTitle && newTitle.length > 0) {
            var titleBody = JSON.stringify({
                properties: {
                    title: { title: [{ text: { content: newTitle } }] }
                }
            });
            var cmdT = _ntnBin() + " api v1/pages/" + _shellQuote(pageId) +
                       " -X PATCH -d " + _shellQuote(titleBody);
            _log("Comando título: " + cmdT);
            _run(cmdT, function(code, stdout, stderr) {
                if (code !== 0) {
                    store._warn("update title exit=" + code + ": " + stderr.substring(0, 300));
                    store.pageUpdated(pageId, false, stderr || ("exit " + code));
                    return;
                }
                store._log("Título actualizado OK.");
                // Apply local title bump so the UI refreshes without a full fetch.
                store._applyLocalTitle(pageId, newTitle);
                if (newContent === null || newContent === undefined) {
                    store.pageUpdated(pageId, true, "");
                } else {
                    _doUpdateContent(pageId, newContent);
                }
            });
        } else if (newContent !== null && newContent !== undefined) {
            _doUpdateContent(pageId, newContent);
        } else {
            store.pageUpdated(pageId, true, "");
        }
    }

    function _doUpdateContent(pageId, newContent) {
        var cmdC = _ntnBin() + " pages update " + _shellQuote(pageId) +
                   " --content " + _shellQuote(newContent);
        _log("Comando contenido: ntn pages update " + pageId + " --content <…" +
             newContent.length + " caracteres>");
        _run(cmdC, function(code, stdout, stderr) {
            if (code !== 0) {
                store._warn("update content exit=" + code + ": " + stderr.substring(0, 300));
                store.pageUpdated(pageId, false, stderr || ("exit " + code));
                return;
            }
            store._log("Contenido actualizado OK.");
            store.pageUpdated(pageId, true, "");
        });
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    function _ntnBin() {
        if (!plasmoidApi) return "ntn";
        var p = (plasmoidApi.configuration.notionCliPath || "").trim();
        return p.length > 0 ? p : "ntn";
    }

    // POSIX shell single-quote escape: wrap in single quotes and replace
    // every literal ' with '\''. Safe against all metacharacters.
    function _shellQuote(s) {
        return "'" + String(s || "").replace(/'/g, "'\\''") + "'";
    }

    function _run(cmd, callback) {
        // Wrap in sh -c so we get shell features (quoting, etc.). We append
        // a per-invocation counter as a trailing positional arg ($0 for the
        // shell, which sh -c ignores for command execution) so each call has
        // a unique source name — the DataSource caches by source name and
        // would otherwise reuse the previous run's output.
        store._seq = store._seq + 1;
        var wrapped = "sh -c " + _shellQuote(cmd) + " seq" + store._seq;
        store._pending[wrapped] = callback;
        store._cmd.connectSource(wrapped);
    }

    function _normalize(raw) {
        // raw is a Notion page object; the title lives inside the properties
        // dict under a property whose .type === "title". We scan for it.
        var title = "";
        if (raw.properties) {
            for (var key in raw.properties) {
                if (!raw.properties.hasOwnProperty(key)) continue;
                var prop = raw.properties[key];
                if (prop && prop.type === "title" && Array.isArray(prop.title)) {
                    title = prop.title.map(function(seg) {
                        return (seg && seg.plain_text) || "";
                    }).join("");
                    break;
                }
            }
        }
        if (!title) title = "(sin título)";
        return {
            id: raw.id || "",
            title: title,
            url: raw.url || "",
            createdTime: raw.created_time || "",
            lastEditedTime: raw.last_edited_time || "",
            archived: !!raw.archived,
            parentType: (raw.parent && raw.parent.type) || "",
            object: raw.object || "page",
            icon: raw.icon ? (raw.icon.emoji || raw.icon.external && raw.icon.external.url || "") : ""
        };
    }

    function _applyLocalTitle(pageId, newTitle) {
        var found = false;
        for (var i = 0; i < pages.length; i++) {
            if (pages[i].id === pageId) {
                pages[i].title = newTitle;
                found = true;
                break;
            }
        }
        if (found) {
            pages = pages.slice();  // reassign so QML bindings refresh
            _bump();
        }
    }

    readonly property int _maxDebugLogChars: 80000

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
        console.log("[NotionStore] " + msg);
    }

    function _warn(msg) {
        _appendDebug("[!] " + msg + "\n");
        console.warn("[NotionStore] " + msg);
    }

    function _logPages(arr) {
        for (var i = 0; i < Math.min(arr.length, 20); i++) {
            var p = arr[i];
            var line = "  - " + (p.title || "(sin título)").substring(0, 60) +
                       "  [" + (p.id || "").substring(0, 8) + "…]" +
                       (p.lastEditedTime ? " (edit: " + p.lastEditedTime.substring(0, 10) + ")" : "");
            _log(line);
        }
        if (arr.length > 20) _log("  …y " + (arr.length - 20) + " más.");
    }

    function _bump() {
        version = version + 1;
        changed();
    }
}
