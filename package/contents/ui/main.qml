/*
 * main.qml - Categorized ToDo plasmoid root.
 *
 * Hosts both representations and owns the shared stores. The plasmoid
 * has two operating modes (configurable):
 *   - "todo": local task list (TaskStore + SQLite).
 *   - "jira": read-only view of Jira issues assigned to the user.
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

    Plasmoid.fullRepresentation: FullRepresentation {
        store: _store
        jira: _jira
        Layout.minimumWidth: plasmoid.configuration.popupWidth
        Layout.minimumHeight: plasmoid.configuration.popupHeight
        Layout.preferredWidth: plasmoid.configuration.popupWidth
        Layout.preferredHeight: plasmoid.configuration.popupHeight
    }

    Plasmoid.compactRepresentation: CompactRepresentation {
        store: _store
        jira: _jira
    }

    Plasmoid.toolTipMainText: root.mode === "jira"
            ? i18n("Jira — assigned issues")
            : i18n("Categorized ToDo")

    Plasmoid.toolTipSubText: {
        if (root.mode === "jira") {
            if (!_jira) return "";
            if (_jira.lastError) return _jira.lastError;
            return i18np("%1 issue", "%1 issues", _jira.totalCount());
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
        plasmoid: plasmoid
        database: _db
    }

    Component.onCompleted: {
        _db.init();
        _store.load();
        _jira.init();

        // The init() above may have written restored credentials back
        // into Plasmoid.configuration; mirror them straight back into
        // SQLite so the two layers stay in sync.
        _jira.persistCredentials();

        if (root.mode === "jira" && _jira.lastFetchedAt === 0) {
            _jira.fetch();
        }
    }

    // React to category changes (todo mode) and Jira config changes.
    Connections {
        target: plasmoid.configuration

        function onCategoryCountChanged() {
            var n = Math.min(4, Math.max(1, plasmoid.configuration.categoryCount || 4));
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

        function onModeChanged() {
            if (root.mode === "jira" && _jira.lastFetchedAt === 0 && !_jira.loading) {
                _jira.fetch();
            }
        }
    }
}
