/*
 * SubtaskDetailDialog.qml - read-only modal showing key info of a Jira
 * issue (subtask) plus an "Abrir en Jira" button.
 *
 * openFor(subtask) shows the dialog with the lightweight info that's
 * already in the row, then fires fetchIssueDetail() to enrich it with
 * description, parent summary, original / spent / remaining estimates
 * and a few audit fields. Falls back to the row data if the fetch fails.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: dlg

    property var store

    // Snapshot used while waiting for the detail fetch. Replaced by the
    // enriched object once fetchIssueDetail() returns.
    property var detail: null
    property bool loading: false
    property string errorText: ""

    visible: false
    z: 1000

    focus: visible
    Keys.onEscapePressed: function(event) {
        dlg.visible = false;
        event.accepted = true;
    }

    function openFor(subtask) {
        if (!subtask) return;
        // Seed with what we know so the modal isn't blank.
        detail = {
            key: subtask.key || "",
            summary: subtask.summary || "",
            status: subtask.status || "",
            statusCategory: subtask.statusCategory || "",
            statusColor: subtask.statusColor || "",
            description: "",
            issuetype: "",
            priority: "",
            assignee: "",
            reporter: "",
            parentKey: subtask.parentKey || "",
            parentSummary: subtask.parentSummary || "",
            originalEstimateSec: 0,
            remainingSec: subtask.remainingSec || 0,
            spentSec: 0,
            created: "",
            updated: ""
        };
        errorText = "";
        visible = true;
        dlg.forceActiveFocus();

        if (!store || !store.fetchIssueDetail) return;
        loading = true;
        store.fetchIssueDetail(subtask.key, function(ok, full) {
            loading = false;
            if (ok && full) {
                detail = full;
            } else {
                errorText = i18n("No se pudo cargar el detalle.");
            }
        });
    }

    function _fmtHours(sec) {
        if (!sec || sec <= 0) return "—";
        var h = Math.floor(sec / 3600);
        var m = Math.floor((sec % 3600) / 60);
        if (h > 0 && m > 0) return h + "h " + m + "m";
        if (h > 0)          return h + "h";
        return m + "m";
    }
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
    function _fmtDate(iso) {
        if (!iso) return "";
        var d = new Date(iso);
        if (isNaN(d.getTime())) return iso;
        var pad = function(n) { return n < 10 ? "0" + n : "" + n; };
        return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) +
               " " + pad(d.getHours()) + ":" + pad(d.getMinutes());
    }

    // -------- backdrop --------
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.55
        MouseArea { anchors.fill: parent; onClicked: dlg.visible = false }
    }

    // -------- card --------
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(plasmoid.configuration.worklogModalWidth || 720,
                        Math.max(420, parent.width  - 24))
        height: Math.min(plasmoid.configuration.worklogModalHeight || 520,
                        Math.max(360, parent.height - 36))
        color: PlasmaCore.Theme.backgroundColor
        border.color: PlasmaCore.Theme.textColor
        border.width: 1
        radius: 4

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: PlasmaCore.Units.smallSpacing

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: PlasmaCore.Units.smallSpacing

                PlasmaComponents3.Label {
                    text: dlg.detail ? ("[" + dlg.detail.key + "]") : ""
                    font.family: "monospace"
                    font.bold: true
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: dlg.detail ? (dlg.detail.summary || "") : ""
                    font.bold: true
                    wrapMode: Text.WordWrap
                }
                PlasmaComponents3.BusyIndicator {
                    visible: dlg.loading
                    running: visible
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "window-close"
                    onClicked: dlg.visible = false
                }
            }

            // Meta row: status badge + issuetype + priority + parent
            Flow {
                Layout.fillWidth: true
                spacing: PlasmaCore.Units.smallSpacing

                Rectangle {
                    visible: dlg.detail && (dlg.detail.status || "").length > 0
                    width: badgeLabel.implicitWidth + 16
                    height: 20
                    radius: 10
                    color: dlg.detail ? dlg._statusBg(dlg.detail.statusColor) : "transparent"
                    PlasmaComponents3.Label {
                        id: badgeLabel
                        anchors.centerIn: parent
                        text: dlg.detail ? (dlg.detail.status || "") : ""
                        color: "#1a1a1a"
                        font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                        font.bold: true
                    }
                }
                PlasmaComponents3.Label {
                    text: dlg.detail && dlg.detail.issuetype
                          ? i18n("Tipo: %1", dlg.detail.issuetype) : ""
                    visible: text.length > 0
                    opacity: 0.7
                }
                PlasmaComponents3.Label {
                    text: dlg.detail && dlg.detail.priority
                          ? i18n("Prioridad: %1", dlg.detail.priority) : ""
                    visible: text.length > 0
                    opacity: 0.7
                }
                PlasmaComponents3.Label {
                    text: dlg.detail && dlg.detail.parentKey
                          ? i18n("Padre: %1 — %2", dlg.detail.parentKey,
                                                    dlg.detail.parentSummary || "")
                          : ""
                    visible: text.length > 0
                    opacity: 0.7
                    wrapMode: Text.WordWrap
                }
            }

            // Estimates
            RowLayout {
                Layout.fillWidth: true
                spacing: PlasmaCore.Units.largeSpacing

                ColumnLayout {
                    spacing: 0
                    PlasmaComponents3.Label {
                        text: i18n("Original")
                        opacity: 0.6
                        font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                    }
                    PlasmaComponents3.Label {
                        text: dlg.detail ? dlg._fmtHours(dlg.detail.originalEstimateSec) : "—"
                        font.bold: true
                        font.family: "monospace"
                    }
                }
                ColumnLayout {
                    spacing: 0
                    PlasmaComponents3.Label {
                        text: i18n("Quemadas")
                        opacity: 0.6
                        font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                    }
                    PlasmaComponents3.Label {
                        text: dlg.detail ? dlg._fmtHours(dlg.detail.spentSec) : "—"
                        font.bold: true
                        font.family: "monospace"
                    }
                }
                ColumnLayout {
                    spacing: 0
                    PlasmaComponents3.Label {
                        text: i18n("Disponible")
                        opacity: 0.6
                        font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                    }
                    PlasmaComponents3.Label {
                        text: dlg.detail ? dlg._fmtHours(dlg.detail.remainingSec) : "—"
                        font.bold: true
                        font.family: "monospace"
                    }
                }
                Item { Layout.fillWidth: true }
                ColumnLayout {
                    spacing: 0
                    PlasmaComponents3.Label {
                        text: i18n("Asignado a")
                        opacity: 0.6
                        font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                    }
                    PlasmaComponents3.Label {
                        text: dlg.detail ? (dlg.detail.assignee || "—") : "—"
                    }
                }
            }

            // Description
            PlasmaComponents3.Label {
                text: i18n("Descripción")
                opacity: 0.7
            }
            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                QQC2.TextArea {
                    id: descArea
                    text: dlg.detail ? (dlg.detail.description || "") : ""
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    font.pixelSize: 12
                    placeholderText: dlg.loading ? i18n("Cargando…") : i18n("(sin descripción)")
                }
            }

            // Created / updated stamps
            RowLayout {
                Layout.fillWidth: true
                visible: dlg.detail && (dlg.detail.created || dlg.detail.updated)
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    opacity: 0.55
                    font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                    text: dlg.detail
                          ? (i18n("Creada: %1", dlg._fmtDate(dlg.detail.created)) + "    " +
                             i18n("Actualizada: %1", dlg._fmtDate(dlg.detail.updated)))
                          : ""
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: dlg.errorText.length > 0
                text: dlg.errorText
                color: PlasmaCore.Theme.negativeTextColor
                wrapMode: Text.WordWrap
            }

            // Footer
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                PlasmaComponents3.Button {
                    text: i18n("Cerrar")
                    onClicked: dlg.visible = false
                }
                PlasmaComponents3.Button {
                    text: i18n("Abrir en Jira")
                    icon.name: "internet-services"
                    enabled: dlg.detail && dlg.detail.key && dlg.store
                    onClicked: {
                        var url = dlg.store ? dlg.store.issueWebUrl(dlg.detail.key) : "";
                        if (url.length > 0) Qt.openUrlExternally(url);
                    }
                }
            }
        }
    }
}
