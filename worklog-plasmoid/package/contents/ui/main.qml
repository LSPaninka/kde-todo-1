/*
 * main.qml - root for the Jira Worklog Calendar plasmoid.
 *
 * Hosts both the JiraWorklogStore (already there) and the new
 * ClockifyStore, and dispatches compact / full representations. The
 * "worklogPinned" kcfg bool keeps the popup open across focus loss
 * (toggled by the pin button in the header).
 */

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    switchWidth: Kirigami.Units.gridUnit * 14
    switchHeight: Kirigami.Units.gridUnit * 10

    readonly property string source: Plasmoid.configuration.worklogSource || "jira"
    readonly property bool pinned:   Plasmoid.configuration.worklogPinned === true

    fullRepresentation: FullRepresentation {
        plasmoidItem: root
        jiraStore: _jira
        clockifyStore: _clockify
        googleStore: _google
        Layout.minimumWidth: Plasmoid.configuration.worklogPopupWidth
        Layout.minimumHeight: Plasmoid.configuration.worklogPopupHeight
        Layout.preferredWidth: Plasmoid.configuration.worklogPopupWidth
        Layout.preferredHeight: Plasmoid.configuration.worklogPopupHeight
    }

    compactRepresentation: CompactRepresentation {
        plasmoidItem: root
    }

    toolTipMainText: {
        if (root.source === "clockify")      return i18n("Clockify Worklog");
        if (root.source === "jira-clockify") return i18n("Jira / Clockify Worklog");
        return i18n("Jira Worklog Calendar");
    }
    toolTipSubText: {
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
        plasmoidApi: Plasmoid
    }
    ClockifyStore {
        id: _clockify
        plasmoidApi: Plasmoid
    }
    GoogleCalendarStore {
        id: _google
        plasmoidApi: Plasmoid
    }

    Component.onCompleted: {
        _jira.plasmoidApi     = Plasmoid;
        _clockify.plasmoidApi = Plasmoid;
        _google.plasmoidApi   = Plasmoid;
        _jira.init();
        _clockify.init();
        _google.init();
        // Apply the pinned state on startup.
        root.hideOnWindowDeactivate = !root.pinned;
    }

    Connections {
        target: Plasmoid.configuration
        function onWorklogPinnedChanged() {
            root.hideOnWindowDeactivate = !Plasmoid.configuration.worklogPinned;
        }
    }
}
