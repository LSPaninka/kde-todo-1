/*
 * main.qml - Categorized ToDo plasmoid root.
 *
 * Hosts both representations and owns the shared stores. The plasmoid
 * has four operating modes (configurable):
 *   - "todo":   local task list (TaskStore + SQLite).
 *   - "jira":   read-only view of Jira issues assigned to the user.
 *   - "gh":     read-only view of a GitHub Projects (V2) project.
 *   - "notion": pages from Notion via the `ntn` CLI (read + inline edit).
 *
 * Persistence: SQLite via QtQuick.LocalStorage 2.15. See
 * docs/PERSISTENCE.md for the storage path and layout.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore

Item {
    id: root

    Plasmoid.switchWidth: PlasmaCore.Units.gridUnit * 10
    Plasmoid.switchHeight: PlasmaCore.Units.gridUnit * 8

    readonly property string mode: plasmoid.configuration.mode || "todo"

    // Set by the CompactRepresentation's hover signal so the native Plasma
    // tooltip (Plasmoid.toolTipMainText/SubText) can show per-square detail
    // instead of always showing the widget-wide summary. Empty = use default.
    property string compactHoverMain: ""
    property string compactHoverSub: ""

    Plasmoid.fullRepresentation: FullRepresentation {
        store: _store
        jira: _jira
        gh: _gh
        notion: _notion
        Layout.minimumWidth: plasmoid.configuration.popupWidth
        Layout.minimumHeight: plasmoid.configuration.popupHeight
        Layout.preferredWidth: plasmoid.configuration.popupWidth
        Layout.preferredHeight: plasmoid.configuration.popupHeight
    }

    Plasmoid.compactRepresentation: CompactRepresentation {
        store: _store
        jira: _jira
        gh: _gh
        notion: _notion
        onHoverChanged: function(isHov, mainText, subText) {
            root.compactHoverMain = isHov ? mainText : "";
            root.compactHoverSub  = isHov ? subText  : "";
        }
    }

    Plasmoid.toolTipMainText: {
        // Per-square hover wins over the widget-wide summary.
        if (root.compactHoverMain.length > 0) return root.compactHoverMain;
        if (root.mode === "jira")   return i18n("Jira — assigned issues");
        if (root.mode === "gh")     return i18n("GitHub Projects");
        if (root.mode === "notion") return i18n("Notion pages");
        return i18n("Categorized ToDo");
    }

    Plasmoid.toolTipSubText: {
        if (root.compactHoverSub.length > 0) return root.compactHoverSub;
        if (root.mode === "jira") {
            if (!_jira) return "";
            if (_jira.lastError) return _jira.lastError;
            return i18np("%1 issue", "%1 issues", _jira.totalCount());
        }
        if (root.mode === "gh") {
            if (!_gh) return "";
            if (_gh.lastError) return _gh.lastError;
            return i18np("%1 item", "%1 items", _gh.totalCount());
        }
        if (root.mode === "notion") {
            if (!_notion) return "";
            if (_notion.lastError) return _notion.lastError;
            return i18np("%1 page", "%1 pages", _notion.totalCount());
        }
        return _store ? i18np("%1 pending task", "%1 pending tasks", _store.totalPending()) : "";
    }

    Database {
        id: _db
    }

    TaskStore {
        id: _store
        plasmoid: plasmoid
        database: _db
    }

    JiraStore {
        id: _jira
        plasmoidApi: plasmoid
        database: _db
    }

    GhStore {
        id: _gh
        plasmoidApi: plasmoid
        database: _db
    }

    NotionStore {
        id: _notion
        plasmoidApi: plasmoid
    }

    Component.onCompleted: {
        // Belt-and-suspenders: re-assign plasmoidApi explicitly in case the
        // declarative binding above didn't fire for some reason.
        _jira.plasmoidApi   = plasmoid;
        _gh.plasmoidApi     = plasmoid;
        _notion.plasmoidApi = plasmoid;

        _db.init();
        _store.load();
        _jira.init();
        _gh.init();
        _notion.init();

        // The init() above may have written restored credentials back
        // into Plasmoid.configuration; mirror them straight back into
        // SQLite so the two layers stay in sync.
        _jira.persistCredentials();
        _gh.persistCredentials();

        if (root.mode === "jira" && _jira.lastFetchedAt === 0) {
            _jira.fetch();
        }
        if (root.mode === "gh" && _gh.lastFetchedAt === 0) {
            _gh.fetch();
        }
        if (root.mode === "notion" && _notion.lastFetchedAt === 0) {
            _notion.fetch();
        }
    }

    // React to category changes (todo mode) and Jira config changes.
    Connections {
        target: plasmoid.configuration

        function onCategoryCountChanged() {
            var n = Math.min(7, Math.max(1, plasmoid.configuration.categoryCount || 4));
            _store.reassignOutOfRangeCategories(n);
        }
        function onCategoryNamesChanged() {
            _store.notifyCategoryNamesChanged();
        }

        // Mirror Jira credentials to SQLite on every change so a
        // Plasma config loss doesn't wipe them out.
        function onJiraSiteChanged()  { _jira.persistCredentials(); }
        function onJiraEmailChanged() { _jira.persistCredentials(); }
        function onJiraTokenChanged() { _jira.persistCredentials(); }
        function onJiraJqlChanged()   { _jira.persistCredentials(); }

        function onJiraRefreshMinutesChanged() { _jira.applyRefreshSchedule(); }

        // Mirror GitHub credentials too.
        function onGhTokenChanged() { _gh.persistCredentials(); }
        function onGhOwnerChanged() { _gh.persistCredentials(); }
        function onGhRefreshMinutesChanged() { _gh.applyRefreshSchedule(); }

        // Notion has no credentials in config (ntn login does the work).
        function onNotionRefreshMinutesChanged() { _notion.applyRefreshSchedule(); }

        function onModeChanged() {
            if (root.mode === "jira" && _jira.lastFetchedAt === 0 && !_jira.loading) {
                _jira.fetch();
            }
            if (root.mode === "gh" && _gh.lastFetchedAt === 0 && !_gh.loading) {
                _gh.fetch();
            }
            if (root.mode === "notion" && _notion.lastFetchedAt === 0 && !_notion.loading) {
                _notion.fetch();
            }
        }
    }
}
