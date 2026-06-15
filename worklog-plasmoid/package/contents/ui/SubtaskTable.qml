/*
 * SubtaskTable.qml - third bottom-panel view (rings / subtasks / heatmap).
 *
 * Renders the rows in jiraStore.subtasks (populated by fetchSubtasks(), JQL
 * comes from worklogSubtaskJql). Columns:
 *   1: code + summary  (monospace key, then title)
 *   2: status badge    (colored by Jira's statusCategory.colorName)
 *   3: remaining hours (uses the same _remainingSec() strategy as the rings)
 *   4: parent issue    (optional, gated by worklogSubtaskShowParent)
 *
 * Left-click on a row → emits subtaskActivated(subtask) so the parent shows
 * the SubtaskDetailDialog.
 * Right-click → menu with "Cambiar estado" (transitions submenu, fetched
 * lazily on open) and "Ver en Jira". Both fire signals back up.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: tbl

    property var jiraStore
    readonly property int _v: jiraStore ? jiraStore.version : 0
    readonly property var _rows: jiraStore ? (jiraStore.subtasks || []) : []
    readonly property bool _showParent:
        plasmoid.configuration.worklogSubtaskShowParent !== false

    signal subtaskActivated(var subtask)
    signal openInJiraRequested(string issueKey)
    signal transitionRequested(var subtask, string transitionId)

    implicitHeight: col.implicitHeight

    // Refresh hook for FullRepresentation.
    function refresh() {
        if (jiraStore && jiraStore.fetchSubtasks) jiraStore.fetchSubtasks();
    }

    // Right-click menu state — populated when the user opens the menu on
    // a row. Transitions are fetched lazily then injected via Instantiator.
    property var _menuSubtask: null
    property var _menuTransitions: []
    property bool _menuLoading: false

    function _openMenuFor(subtask, x, y) {
        tbl._menuSubtask = subtask;
        tbl._menuTransitions = [];
        tbl._menuLoading = true;
        rowMenu.x = x;
        rowMenu.y = y;
        rowMenu.open();
        if (jiraStore && jiraStore.fetchTransitions) {
            jiraStore.fetchTransitions(subtask.key, function(ok, arr) {
                tbl._menuLoading = false;
                tbl._menuTransitions = ok ? arr : [];
            });
        } else {
            tbl._menuLoading = false;
        }
    }

    function _fmtHours(sec) {
        if (!sec || sec <= 0) return "—";
        var h = Math.floor(sec / 3600);
        var m = Math.floor((sec % 3600) / 60);
        if (h > 0 && m > 0) return h + "h " + m + "m";
        if (h > 0)          return h + "h";
        return m + "m";
    }

    // Jira's statusCategory.colorName values are CSS-like; map them onto
    // theme-friendly tones. Fallback: neutral gray.
    function _statusBg(colorName) {
        switch ((colorName || "").toLowerCase()) {
            case "green":         return Qt.rgba(129/255, 199/255, 132/255, 0.85);
            case "yellow":        return Qt.rgba(241/255, 196/255,  15/255, 0.85);
            case "blue-gray":     return Qt.rgba(120/255, 144/255, 156/255, 0.85);
            case "warm-red":      return Qt.rgba(231/255,  76/255,  60/255, 0.85);
            case "medium-gray":   return Qt.rgba(158/255, 158/255, 158/255, 0.85);
            default:              return Qt.rgba(120/255, 144/255, 156/255, 0.65);
        }
    }
    function _statusFg() { return "#1a1a1a"; }

    ColumnLayout {
        id: col
        anchors.fill: parent
        spacing: 2

        // -------- Header --------
        RowLayout {
            Layout.fillWidth: true
            spacing: PlasmaCore.Units.smallSpacing

            PlasmaComponents3.Label {
                text: i18n("Subtareas")
                font.bold: true
            }
            PlasmaComponents3.Label {
                text: tbl._rows.length > 0 ? ("(" + tbl._rows.length + ")") : ""
                opacity: 0.6
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            }
            Item { Layout.fillWidth: true }
            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh"
                onClicked: tbl.refresh()
                PlasmaComponents3.ToolTip.text: i18n("Recargar subtareas")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
        }

        // -------- Column header --------
        RowLayout {
            Layout.fillWidth: true
            spacing: PlasmaCore.Units.smallSpacing

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: i18n("Subtarea")
                opacity: 0.6
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                font.bold: true
            }
            PlasmaComponents3.Label {
                Layout.preferredWidth: 110
                text: i18n("Estado")
                opacity: 0.6
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                font.bold: true
            }
            PlasmaComponents3.Label {
                Layout.preferredWidth: 70
                horizontalAlignment: Text.AlignRight
                text: i18n("Disp.")
                opacity: 0.6
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                font.bold: true
            }
            PlasmaComponents3.Label {
                Layout.preferredWidth: 90
                visible: tbl._showParent
                text: i18n("Padre")
                opacity: 0.6
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                font.bold: true
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: PlasmaCore.Theme.textColor
            opacity: 0.15
        }

        // -------- Rows --------
        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: list
                spacing: 1
                model: (tbl._v, tbl._rows)
                delegate: Rectangle {
                    width: list.width
                    height: row.implicitHeight + 6
                    color: rowMouse.containsMouse
                           ? Qt.rgba(1, 1, 1, 0.06)
                           : "transparent"
                    radius: 2

                    RowLayout {
                        id: row
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: PlasmaCore.Units.smallSpacing

                        // Code + summary
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                PlasmaComponents3.Label {
                                    text: modelData.key
                                    font.family: "monospace"
                                    font.bold: true
                                }
                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: modelData.summary
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // Status badge
                        Rectangle {
                            Layout.preferredWidth: 110
                            Layout.preferredHeight: 18
                            radius: 9
                            color: tbl._statusBg(modelData.statusColor)
                            PlasmaComponents3.Label {
                                anchors.centerIn: parent
                                text: modelData.status
                                color: tbl._statusFg()
                                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                                font.bold: true
                                elide: Text.ElideRight
                                width: parent.width - 8
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        // Remaining hours
                        PlasmaComponents3.Label {
                            Layout.preferredWidth: 70
                            horizontalAlignment: Text.AlignRight
                            text: tbl._fmtHours(modelData.remainingSec)
                            font.family: "monospace"
                        }

                        // Parent (optional)
                        PlasmaComponents3.Label {
                            id: parentLabel
                            Layout.preferredWidth: 90
                            visible: tbl._showParent
                            text: modelData.parentKey || ""
                            font.family: "monospace"
                            elide: Text.ElideRight
                            opacity: modelData.parentKey ? 0.85 : 0.35

                            PlasmaComponents3.ToolTip.text: modelData.parentSummary
                                                            ? (modelData.parentKey + " — " + modelData.parentSummary)
                                                            : ""
                            PlasmaComponents3.ToolTip.visible: parentHover.containsMouse &&
                                                               !!modelData.parentSummary
                            PlasmaComponents3.ToolTip.delay: 300

                            MouseArea {
                                id: parentHover
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: function(mouse) {
                            if (mouse.button === Qt.LeftButton) {
                                tbl.subtaskActivated(modelData);
                            } else if (mouse.button === Qt.RightButton) {
                                var p = mapToItem(tbl, mouse.x, mouse.y);
                                tbl._openMenuFor(modelData, p.x, p.y);
                            }
                        }
                    }
                }

                PlasmaComponents3.Label {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: i18n("Sin subtareas. Ajustá el JQL en Configurar.")
                    opacity: 0.55
                }
            }
        }
    }

    // -------- Right-click menu (shared across rows) --------
    QQC2.Menu {
        id: rowMenu

        QQC2.Menu {
            id: stateMenu
            title: i18n("Cambiar estado")
            enabled: !tbl._menuLoading && tbl._menuTransitions.length > 0

            QQC2.MenuItem {
                text: i18n("Cargando…")
                enabled: false
                visible: tbl._menuLoading
                height: visible ? implicitHeight : 0
            }
            QQC2.MenuItem {
                text: i18n("(sin transiciones)")
                enabled: false
                visible: !tbl._menuLoading && tbl._menuTransitions.length === 0
                height: visible ? implicitHeight : 0
            }
            Instantiator {
                model: tbl._menuTransitions
                delegate: QQC2.MenuItem {
                    text: modelData.toStatus
                          ? (modelData.name + " → " + modelData.toStatus)
                          : modelData.name
                    onTriggered: {
                        if (tbl._menuSubtask) {
                            tbl.transitionRequested(tbl._menuSubtask, modelData.id);
                        }
                        rowMenu.close();
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
            onTriggered: {
                if (tbl._menuSubtask) {
                    tbl.openInJiraRequested(tbl._menuSubtask.key);
                }
                rowMenu.close();
            }
        }
    }
}
