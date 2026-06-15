/*
 * main.qml - root for the Jira Worklog Calendar plasmoid.
 *
 * Hosts both the JiraWorklogStore (already there) and the new
 * ClockifyStore, and dispatches compact / full representations. The
 * "worklogPinned" kcfg bool keeps the popup open across focus loss
 * (toggled by the pin button in the header).
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore

Item {
    id: root

    Plasmoid.switchWidth: PlasmaCore.Units.gridUnit * 14
    Plasmoid.switchHeight: PlasmaCore.Units.gridUnit * 10

    readonly property string source: plasmoid.configuration.worklogSource || "jira"
    readonly property bool pinned:   plasmoid.configuration.worklogPinned === true

    Plasmoid.fullRepresentation: FullRepresentation {
        jiraStore: _jira
        clockifyStore: _clockify
        Layout.minimumWidth: plasmoid.configuration.worklogPopupWidth
        Layout.minimumHeight: plasmoid.configuration.worklogPopupHeight
        Layout.preferredWidth: plasmoid.configuration.worklogPopupWidth
        Layout.preferredHeight: plasmoid.configuration.worklogPopupHeight
    }

    Plasmoid.compactRepresentation: CompactRepresentation { }

    Plasmoid.toolTipMainText: {
        if (root.source === "clockify")      return i18n("Clockify Worklog");
        if (root.source === "jira-clockify") return i18n("Jira / Clockify Worklog");
        return i18n("Jira Worklog Calendar");
    }
    Plasmoid.toolTipSubText: {
        var parts = [];
        if ((root.source === "jira" || root.source === "jira-clockify") && _jira) {
            if (_jira.loading) parts.push(i18n("Jira: cargando…"));
            else if (_jira.lastError) parts.push(i18n("Jira: %1", _jira.lastError));
            else parts.push(i18np("%1 worklog Jira", "%1 worklogs Jira", _jira.totalCount()));
        }
        if ((root.source === "clockify" || root.source === "jira-clockify") && _clockify) {
            if (_clockify.loading) parts.push(i18n("Clockify: cargando…"));
            else if (_clockify.lastError) parts.push(i18n("Clockify: %1", _clockify.lastError));
            else parts.push(i18np("%1 entry Clockify", "%1 entries Clockify", _clockify.totalCount()));
        }
        return parts.join("  ·  ");
    }

    JiraWorklogStore {
        id: _jira
        plasmoidApi: plasmoid
    }
    ClockifyStore {
        id: _clockify
        plasmoidApi: plasmoid
    }

    Component.onCompleted: {
        _jira.plasmoidApi     = plasmoid;
        _clockify.plasmoidApi = plasmoid;
        _jira.init();
        _clockify.init();
        // Apply the pinned state on startup.
        plasmoid.hideOnWindowDeactivate = !root.pinned;
    }

    Connections {
        target: plasmoid.configuration
        function onWorklogPinnedChanged() {
            plasmoid.hideOnWindowDeactivate = !plasmoid.configuration.worklogPinned;
        }
    }
}
