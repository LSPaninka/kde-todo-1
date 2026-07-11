/*
 * JiraSubtaskPicker.qml - modal to pick a Jira issue/subtask to attach to a
 * local ToDo task (the "todoJiraLink" feature).
 *
 * Searches the issues already loaded by JiraStore (the configured JQL,
 * typically the user's assigned issues/subtasks) and filters them
 * client-side by key + summary, like the worklog-calendar's picker.
 * Emits picked(taskId, key); an empty key unlinks.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

QQC2.Dialog {
    id: picker

    property var jira
    property int taskId: 0
    property string currentKey: ""

    signal picked(int taskId, string key)

    modal: true
    anchors.centerIn: parent
    width: Math.min(520, (parent ? parent.width : 520) - 24)
    height: Math.min(520, (parent ? parent.height : 520) - 24)
    title: i18n("Anexar subtarea de Jira")
    // No standardButtons — the footer has a custom Cancel button.

    readonly property int _v: jira ? jira.version : 0

    function openFor(task) {
        taskId = task ? task.id : 0;
        currentKey = task ? (task.jiraKey || "") : "";
        searchField.text = "";
        open();
        // Make sure there's something to search; fetch if the cache is empty.
        if (jira && jira.issues.length === 0 && !jira.loading) jira.fetch();
        searchField.forceActiveFocus();
    }

    function _filtered() {
        var arr = (picker._v, jira ? jira.issues : []);
        var q = searchField.text.trim().toLowerCase();
        if (!q) return arr;
        var out = [];
        for (var i = 0; i < arr.length; i++) {
            var it = arr[i];
            var hay = ((it.key || "") + " " + (it.summary || "")).toLowerCase();
            if (hay.indexOf(q) >= 0) out.push(it);
        }
        return out;
    }

    contentItem: ColumnLayout {
        spacing: PlasmaCore.Units.smallSpacing

        // Search + refresh.
        RowLayout {
            Layout.fillWidth: true
            spacing: PlasmaCore.Units.smallSpacing

            PlasmaCore.IconItem {
                source: "search"
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
            }
            PlasmaComponents3.TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: i18n("Buscar por código o título (ej: CP-123)…")
                Keys.onEscapePressed: text = ""
            }
            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh"
                enabled: picker.jira && !(picker._v, picker.jira.loading)
                onClicked: if (picker.jira) picker.jira.fetch()
                PlasmaComponents3.ToolTip.text: i18n("Refrescar issues de Jira")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
        }

        // "Unlink" row (only when currently linked).
        PlasmaComponents3.Button {
            Layout.fillWidth: true
            visible: picker.currentKey.length > 0
            icon.name: "edit-delete-remove"
            text: i18n("Quitar anexión (%1)", picker.currentKey)
            onClicked: { picker.picked(picker.taskId, ""); picker.close(); }
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: list
                spacing: 4
                model: picker._filtered()

                delegate: Rectangle {
                    width: list.width
                    implicitHeight: rowLay.implicitHeight + PlasmaCore.Units.smallSpacing * 2
                    radius: 4
                    color: rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: (modelData && modelData.key === picker.currentKey)
                                  ? PlasmaCore.Theme.highlightColor
                                  : Qt.rgba(1, 1, 1, 0.08)

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            picker.picked(picker.taskId, modelData.key);
                            picker.close();
                        }
                    }

                    RowLayout {
                        id: rowLay
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: PlasmaCore.Units.smallSpacing
                        anchors.rightMargin: PlasmaCore.Units.smallSpacing
                        spacing: PlasmaCore.Units.smallSpacing

                        PlasmaComponents3.Label {
                            text: modelData ? modelData.key : ""
                            font.family: "monospace"
                            font.bold: true
                            opacity: 0.9
                        }
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: modelData ? modelData.summary : ""
                            elide: Text.ElideRight
                        }
                        PlasmaComponents3.Label {
                            visible: modelData && modelData.statusName
                            text: modelData ? modelData.statusName : ""
                            opacity: 0.6
                            font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                        }
                    }
                }

                PlasmaComponents3.BusyIndicator {
                    anchors.centerIn: parent
                    running: picker.jira && picker.jira.loading && list.count === 0
                    visible: running
                }
                PlasmaComponents3.Label {
                    anchors.centerIn: parent
                    width: parent.width - 40
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible: list.count === 0 && picker.jira && !picker.jira.loading
                    opacity: 0.55
                    text: {
                        if (!picker.jira) return i18n("Jira no está configurado.");
                        if (picker.jira.lastError) return picker.jira.lastError;
                        if (searchField.text.length > 0) return i18n("Ningún issue coincide con la búsqueda.");
                        return i18n("No hay issues cargados. Pulsá ↻ para traerlos desde Jira.");
                    }
                }
            }
        }

        // Footer.
        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: i18n("Se buscan tus issues de Jira (según el JQL configurado).")
                opacity: 0.55
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                elide: Text.ElideRight
            }
            PlasmaComponents3.Button {
                text: i18n("Cancelar")
                onClicked: picker.close()
            }
        }
    }
}
