/*
 * HuDialog.qml - modal for a user story (HU / parent): lists all its
 * sub-tasks in a table (código, nombre, estado, horas restantes,
 * responsable), with a "solo mis subtareas" toggle. Opened from the HU tab.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

QQC2.Dialog {
    id: dlg

    property var jira
    property string cfgPrefix: "jira"
    property string parentKey: ""
    property string parentSummary: ""
    property var subtasks: []
    property bool loading: false
    property string error: ""
    property bool onlyMine: false

    modal: true
    anchors.centerIn: parent
    width: Math.min(640, (parent ? parent.width : 640) - 20)
    height: Math.min(560, (parent ? parent.height : 560) - 20)
    padding: 0

    onOpened: if (bodyScroll.contentItem) bodyScroll.contentItem.contentY = 0;

    function openFor(key, summary) {
        parentKey = key || "";
        parentSummary = summary || "";
        subtasks = [];
        error = "";
        loading = true;
        open();
        if (jira && parentKey) {
            jira.fetchSubtasksOfParent(parentKey, function(ok, arr, err) {
                dlg.loading = false;
                if (ok) dlg.subtasks = arr;
                else dlg.error = err || i18n("No se pudieron cargar las subtareas.");
            });
        } else {
            loading = false;
            error = i18n("Sin datos.");
        }
    }

    readonly property var _rows: {
        if (!onlyMine) return subtasks;
        var mine = jira ? jira.myAccountId : "";
        if (!mine) return subtasks;
        var out = [];
        for (var i = 0; i < subtasks.length; i++) {
            if (subtasks[i].assigneeAccountId === mine) out.push(subtasks[i]);
        }
        return out;
    }

    function _fmtH(sec) {
        if (!sec || sec <= 0) return "—";
        var h = Math.floor(sec / 3600);
        var m = Math.floor((sec % 3600) / 60);
        if (h > 0 && m > 0) return h + "h " + m + "m";
        if (h > 0) return h + "h";
        return m + "m";
    }

    function _statusColor(statusName, colorName, statusCat) {
        var s = (statusName || "").trim().toLowerCase();
        var names  = plasmoid.configuration[cfgPrefix+"StatusNames"]  || [];
        var colors = plasmoid.configuration[cfgPrefix+"StatusColors"] || [];
        for (var i = 0; i < names.length; i++) {
            if ((names[i] || "").trim().toLowerCase() === s) {
                var c = (colors[i] || "").trim();
                if (c) return c;
            }
        }
        switch ((colorName || "").toLowerCase()) {
            case "blue-gray":
            case "medium-gray": return "#42526e";
            case "yellow":      return "#f5a623";
            case "green":       return "#2ecc71";
            case "brown":       return "#8b572a";
            case "warm-red":    return "#e74c3c";
            case "purple":      return "#9b59b6";
            case "blue":        return "#3498db";
        }
        switch (statusCat) {
            case "new":           return "#42526e";
            case "indeterminate": return "#f5a623";
            case "done":          return "#2ecc71";
        }
        return "#7f8c8d";
    }

    // Column geometry (shared by header + rows).
    readonly property int _wCode: 84
    readonly property int _wStatus: 96
    readonly property int _wHours: 76
    readonly property int _wResp: 130

    background: Rectangle {
        color: PlasmaCore.Theme.backgroundColor
        border.color: PlasmaCore.Theme.textColor
        border.width: 1
        radius: 6
    }

    contentItem: Item {
      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // -------- Header --------
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: PlasmaCore.Units.smallSpacing * 2
            spacing: PlasmaCore.Units.smallSpacing

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: "[" + dlg.parentKey + "]  " + dlg.parentSummary
                font.bold: true
                font.pixelSize: PlasmaCore.Theme.defaultFont.pixelSize + 1
                wrapMode: Text.WordWrap
            }
            PlasmaComponents3.ToolButton {
                icon.name: "window-close"
                onClicked: dlg.close()
            }
        }

        // -------- Filter row --------
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: PlasmaCore.Units.smallSpacing * 2
            Layout.rightMargin: PlasmaCore.Units.smallSpacing * 2
            spacing: PlasmaCore.Units.smallSpacing

            PlasmaComponents3.CheckBox {
                text: i18n("Solo mis subtareas")
                checked: dlg.onlyMine
                onToggled: dlg.onlyMine = checked
            }
            Item { Layout.fillWidth: true }
            PlasmaComponents3.Label {
                text: dlg.loading ? i18n("Cargando…")
                                  : i18np("%1 subtarea", "%1 subtareas", dlg._rows.length)
                opacity: 0.6
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            }
        }

        // -------- Table header --------
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: PlasmaCore.Units.smallSpacing * 2
            Layout.rightMargin: PlasmaCore.Units.smallSpacing * 2
            Layout.topMargin: PlasmaCore.Units.smallSpacing
            spacing: PlasmaCore.Units.smallSpacing
            PlasmaComponents3.Label { text: i18n("Código");      Layout.preferredWidth: dlg._wCode;   font.bold: true; opacity: 0.7; font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize }
            PlasmaComponents3.Label { text: i18n("Nombre");      Layout.fillWidth: true;               font.bold: true; opacity: 0.7; font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize }
            PlasmaComponents3.Label { text: i18n("Estado");      Layout.preferredWidth: dlg._wStatus; font.bold: true; opacity: 0.7; font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize }
            PlasmaComponents3.Label { text: i18n("Hs. rest.");   Layout.preferredWidth: dlg._wHours;  font.bold: true; opacity: 0.7; font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize; horizontalAlignment: Text.AlignRight }
            PlasmaComponents3.Label { text: i18n("Responsable"); Layout.preferredWidth: dlg._wResp;   font.bold: true; opacity: 0.7; font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 2
            Layout.preferredHeight: 1
            color: Qt.rgba(1, 1, 1, 0.12)
        }

        // -------- Table body --------
        QQC2.ScrollView {
            id: bodyScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth

            ListView {
                id: list
                spacing: 2
                model: dlg._rows
                delegate: Rectangle {
                    width: list.width
                    implicitHeight: rowLay.implicitHeight + 8
                    radius: 3
                    color: rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { if (modelData && modelData.url) Qt.openUrlExternally(modelData.url); }
                    }

                    RowLayout {
                        id: rowLay
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: PlasmaCore.Units.smallSpacing * 2
                        anchors.rightMargin: PlasmaCore.Units.smallSpacing * 2
                        spacing: PlasmaCore.Units.smallSpacing

                        PlasmaComponents3.Label {
                            Layout.preferredWidth: dlg._wCode
                            text: modelData ? modelData.key : ""
                            font.family: "monospace"
                            elide: Text.ElideRight
                            font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize + 1
                        }
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: modelData ? modelData.summary : ""
                            elide: Text.ElideRight
                            font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize + 1
                        }
                        Rectangle {
                            Layout.preferredWidth: dlg._wStatus
                            Layout.preferredHeight: 18
                            radius: 3
                            color: modelData ? dlg._statusColor(modelData.statusName, modelData.statusColor, modelData.statusCat) : "#7f8c8d"
                            PlasmaComponents3.Label {
                                anchors.centerIn: parent
                                width: parent.width - 6
                                text: modelData ? modelData.statusName : ""
                                color: "white"
                                font.bold: true
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                            }
                        }
                        PlasmaComponents3.Label {
                            Layout.preferredWidth: dlg._wHours
                            text: modelData ? dlg._fmtH(modelData.remainingSec) : ""
                            horizontalAlignment: Text.AlignRight
                            font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize + 1
                        }
                        PlasmaComponents3.Label {
                            Layout.preferredWidth: dlg._wResp
                            text: modelData ? modelData.assignee : ""
                            elide: Text.ElideRight
                            opacity: 0.85
                            font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize + 1
                        }
                    }
                }

                PlasmaComponents3.BusyIndicator {
                    anchors.centerIn: parent
                    running: dlg.loading && list.count === 0
                    visible: running
                }
                PlasmaComponents3.Label {
                    anchors.centerIn: parent
                    width: parent.width - 40
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible: !dlg.loading && list.count === 0
                    opacity: 0.55
                    text: dlg.error ? dlg.error
                                    : (dlg.onlyMine ? i18n("No tenés subtareas en esta historia.")
                                                    : i18n("Sin subtareas."))
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Qt.rgba(1, 1, 1, 0.12)
        }

        // -------- Footer --------
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: PlasmaCore.Units.smallSpacing * 2
            spacing: PlasmaCore.Units.smallSpacing
            Item { Layout.fillWidth: true }
            PlasmaComponents3.ToolButton {
                icon.name: "window-close"
                onClicked: dlg.close()
                PlasmaComponents3.ToolTip.text: i18n("Cerrar")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
            PlasmaComponents3.ToolButton {
                icon.name: "globe"
                enabled: dlg.parentKey.length > 0
                onClicked: {
                    var u = dlg.jira ? dlg.jira.browseUrl(dlg.parentKey) : "";
                    if (u) Qt.openUrlExternally(u);
                }
                PlasmaComponents3.ToolTip.text: i18n("Abrir la historia en Jira")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
        }
      }
    }
}
