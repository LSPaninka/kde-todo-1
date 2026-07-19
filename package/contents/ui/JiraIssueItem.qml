/*
 * JiraIssueItem.qml - delegate for a single Jira issue.
 *
 *  [type] [KEY-123]  Summary text...        [priority]  [status]
 *                    ↳ Parent: PARENT-12 — parent summary
 *                    [====== consumed-hours bar ======]  8h / 10h
 *
 * Left click: open the detail modal (via the `activated` signal).
 * Right click: context menu to change the issue's status (available
 * transitions) or open it in Jira.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Rectangle {
    id: item

    property var issue        // normalized issue from JiraStore
    property var jira: null   // the JiraStore (for transitions)
    property string cfgPrefix: "jira"

    // Emitted on left click; JiraView opens the detail modal.
    signal activated(var issue)

    // Right-click menu state (transitions fetched lazily).
    property var _transitions: []
    property bool _transitionsLoading: false

    width: parent ? parent.width : 0
    implicitHeight: col.implicitHeight + PlasmaCore.Units.smallSpacing * 2
    radius: 4
    color: cardMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.04)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)

    // -------- Consumed-hours helpers (calculated strategy) --------
    // remaining = max(0, original - spent), so consumed = min(spent, original)
    // and the bar never exceeds 100% even when time is overrun.
    readonly property int _origSec:  issue && issue.originalSec ? issue.originalSec : 0
    readonly property int _spentSec: issue && issue.spentSec  ? issue.spentSec  : 0
    readonly property real _progress: _origSec > 0 ? Math.min(1, _spentSec / _origSec) : 0
    readonly property bool _hasEstimate: _origSec > 0

    function _fmtH(sec) {
        if (!sec || sec <= 0) return "0h";
        var h = Math.floor(sec / 3600);
        var m = Math.floor((sec % 3600) / 60);
        if (h > 0 && m > 0) return h + "h " + m + "m";
        if (h > 0) return h + "h";
        return m + "m";
    }
    function _barColor() {
        if (_spentSec > _origSec) return "#e74c3c";   // overrun
        if (_progress >= 0.9) return "#e67e22";
        if (_progress >= 0.7) return "#f1c40f";
        return "#2ecc71";
    }

    // A user-configured color for this exact status name (case-insensitive)
    // wins over Jira's own colorName mapping. Returns "" if none is set.
    function _configuredStatusColor(statusName) {
        var s = (statusName || "").trim().toLowerCase();
        if (!s) return "";
        var names  = plasmoid.configuration[cfgPrefix+"StatusNames"]  || [];
        var colors = plasmoid.configuration[cfgPrefix+"StatusColors"] || [];
        for (var i = 0; i < names.length; i++) {
            if ((names[i] || "").trim().toLowerCase() === s) {
                var c = (colors[i] || "").trim();
                if (c.length > 0) return c;
            }
        }
        return "";
    }

    function _statusColor(name) {
        // A per-status override configured by the user takes precedence.
        var cfg = _configuredStatusColor(issue ? issue.statusName : "");
        if (cfg) return cfg;
        // Map Jira's named colorName to a real RGB. Jira returns names
        // like "blue-gray", "yellow", "green", "warm-red", etc.
        switch ((name || "").toLowerCase()) {
            case "blue-gray":
            case "medium-gray": return "#42526e";
            case "yellow":      return "#f5a623";
            case "green":       return "#2ecc71";
            case "brown":       return "#8b572a";
            case "warm-red":    return "#e74c3c";
            case "purple":      return "#9b59b6";
            case "blue":        return "#3498db";
        }
        // Fallback by category.
        switch (issue && issue.statusCat) {
            case "new":           return "#42526e";
            case "indeterminate": return "#f5a623";
            case "done":          return "#2ecc71";
        }
        return "#7f8c8d";
    }

    function _typeBadge(name, isSub) {
        if (isSub) return "↳";
        var n = (name || "").toLowerCase();
        if (n.indexOf("story") >= 0)   return "S";
        if (n.indexOf("bug") >= 0)     return "B";
        if (n.indexOf("epic") >= 0)    return "E";
        if (n.indexOf("task") >= 0)    return "T";
        return (name || "?").substring(0, 1).toUpperCase();
    }

    function _typeColor(name, isSub) {
        if (isSub) return "#5e6c84";
        var n = (name || "").toLowerCase();
        if (n.indexOf("story") >= 0) return "#65ba43";
        if (n.indexOf("bug") >= 0)   return "#e5493a";
        if (n.indexOf("epic") >= 0)  return "#904ee2";
        if (n.indexOf("task") >= 0)  return "#4bade8";
        return "#7f8c8d";
    }

    // -------- Right-click menu --------
    function _openContextMenu(x, y) {
        item._transitions = [];
        item._transitionsLoading = true;
        ctxMenu.x = x;
        ctxMenu.y = y;
        ctxMenu.open();
        if (jira && issue) {
            jira.fetchTransitions(issue.key, function(ok, arr) {
                item._transitionsLoading = false;
                item._transitions = ok ? arr : [];
            });
        } else {
            item._transitionsLoading = false;
        }
    }

    function _applyTransition(id) {
        if (!jira || !issue) return;
        jira.transitionIssue(issue.key, id, function(ok, err) {
            if (ok) jira.fetch();
        });
    }

    MouseArea {
        id: cardMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (mouse.button === Qt.RightButton) item._openContextMenu(mouse.x, mouse.y);
            else item.activated(issue);
        }
    }

    QQC2.Menu {
        id: ctxMenu

        QQC2.MenuItem {
            text: i18n("Ver detalle")
            icon.name: "dialog-information"
            onTriggered: item.activated(issue)
        }

        QQC2.Menu {
            id: stateMenu
            title: i18n("Cambiar estado")
            enabled: !item._transitionsLoading && item._transitions.length > 0

            QQC2.MenuItem {
                text: i18n("Cargando…")
                enabled: false
                visible: item._transitionsLoading
                height: visible ? implicitHeight : 0
            }
            QQC2.MenuItem {
                text: i18n("(sin transiciones)")
                enabled: false
                visible: !item._transitionsLoading && item._transitions.length === 0
                height: visible ? implicitHeight : 0
            }
            Instantiator {
                model: item._transitions
                delegate: QQC2.MenuItem {
                    text: modelData.toStatus
                          ? (modelData.name + " → " + modelData.toStatus)
                          : modelData.name
                    onTriggered: {
                        item._applyTransition(modelData.id);
                        ctxMenu.close();
                    }
                }
                onObjectAdded: function(index, object) { stateMenu.insertItem(index, object); }
                onObjectRemoved: function(index, object) { stateMenu.removeItem(object); }
            }
        }

        QQC2.MenuSeparator {}

        QQC2.MenuItem {
            text: i18n("Ver en Jira")
            icon.name: "internet-services"
            onTriggered: { if (issue && issue.url) Qt.openUrlExternally(issue.url); }
        }
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: PlasmaCore.Units.smallSpacing
        anchors.rightMargin: PlasmaCore.Units.smallSpacing
        anchors.topMargin: PlasmaCore.Units.smallSpacing
        anchors.bottomMargin: PlasmaCore.Units.smallSpacing
        spacing: 2

        // -------- Header row --------
        RowLayout {
            Layout.fillWidth: true
            spacing: PlasmaCore.Units.smallSpacing

            // Issuetype badge
            Rectangle {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                radius: 3
                color: item._typeColor(issue ? issue.issuetype : "", issue ? issue.isSubtask : false)
                Text {
                    anchors.centerIn: parent
                    text: item._typeBadge(issue ? issue.issuetype : "", issue ? issue.isSubtask : false)
                    color: "white"
                    font.bold: true
                    font.pixelSize: 12
                }
            }

            // Issue key (monospace)
            PlasmaComponents3.Label {
                text: issue ? issue.key : ""
                font.family: "monospace"
                font.bold: true
                opacity: 0.9
            }

            // Summary
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: issue ? issue.summary : ""
                elide: Text.ElideRight
            }

            // Priority chip
            Rectangle {
                visible: issue && issue.priority
                Layout.preferredHeight: 18
                Layout.preferredWidth: prioLbl.implicitWidth + 12
                radius: 9
                color: Qt.rgba(1, 1, 1, 0.08)
                border.color: Qt.rgba(1, 1, 1, 0.15)
                border.width: 1
                PlasmaComponents3.Label {
                    id: prioLbl
                    anchors.centerIn: parent
                    text: issue ? issue.priority : ""
                    font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                    opacity: 0.9
                }
            }

            // Status chip
            Rectangle {
                Layout.preferredHeight: 20
                Layout.preferredWidth: statusLbl.implicitWidth + 14
                radius: 4
                color: item._statusColor(issue ? issue.statusColor : "")
                PlasmaComponents3.Label {
                    id: statusLbl
                    anchors.centerIn: parent
                    text: issue ? issue.statusName : ""
                    color: "white"
                    font.bold: true
                    font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                }
            }
        }

        // -------- Optional parent line for subtasks --------
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            Layout.leftMargin: 28
            visible: issue && issue.parentKey
            text: issue
                  ? i18n("↳ Parent: %1 — %2", issue.parentKey, issue.parentSummary)
                  : ""
            elide: Text.ElideRight
            opacity: 0.6
            font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            font.italic: true
        }

        // -------- Consumed-hours progress bar --------
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 28
            Layout.topMargin: 2
            visible: item._hasEstimate
            spacing: PlasmaCore.Units.smallSpacing

            Rectangle {
                id: barTrack
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                radius: 3
                color: Qt.rgba(1, 1, 1, 0.10)

                Rectangle {
                    width: Math.round(barTrack.width * item._progress)
                    height: parent.height
                    radius: 3
                    color: item._barColor()
                }
            }

            PlasmaComponents3.Label {
                text: item._fmtH(item._spentSec) + " / " + item._fmtH(item._origSec)
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                opacity: 0.7
            }
        }
    }
}
