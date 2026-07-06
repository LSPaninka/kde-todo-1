/*
 * JiraIssueDialog.qml - detail modal for a single Jira issue.
 *
 * Opened by clicking an issue in JiraView. Shows type, priority, parent,
 * assignee, the time-tracking triple (original / spent / remaining), the
 * description and the comments. "Abrir en Jira" opens the issue in the
 * browser. Detail is fetched lazily via JiraStore.fetchIssueDetail().
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
    property var basicIssue: null      // the list item we were opened from
    property var detail: null          // the fetched detail (or null)
    property bool loadingDetail: false
    property string detailError: ""

    modal: true
    anchors.centerIn: parent
    width: Math.min(560, (parent ? parent.width : 560) - 24)
    height: Math.min(560, (parent ? parent.height : 560) - 24)
    padding: 0
    // No standardButtons — the footer buttons are custom (Cerrar / Abrir).

    function openFor(issue) {
        basicIssue = issue;
        detail = null;
        detailError = "";
        loadingDetail = true;
        open();
        if (jira && issue && issue.key) {
            jira.fetchIssueDetail(issue.key, function(ok, d, err) {
                dlg.loadingDetail = false;
                if (ok) dlg.detail = d;
                else dlg.detailError = err || i18n("No se pudo cargar el detalle.");
            });
        } else {
            loadingDetail = false;
            detailError = i18n("Sin datos de la incidencia.");
        }
    }

    function _key()      { return detail ? detail.key      : (basicIssue ? basicIssue.key : ""); }
    function _summary()  { return detail ? detail.summary  : (basicIssue ? basicIssue.summary : ""); }
    function _status()   { return detail ? detail.statusName : (basicIssue ? basicIssue.statusName : ""); }
    function _url()      { return detail ? detail.url : (basicIssue ? basicIssue.url : ""); }

    function _fmtDate(iso) {
        if (!iso) return "—";
        var d = new Date(iso);
        if (isNaN(d.getTime())) return iso;
        return Qt.formatDateTime(d, "yyyy-MM-dd hh:mm");
    }

    function _statusColor() {
        var name = _status();
        var s = (name || "").trim().toLowerCase();
        var names  = plasmoid.configuration.jiraStatusNames  || [];
        var colors = plasmoid.configuration.jiraStatusColors || [];
        for (var i = 0; i < names.length; i++) {
            if ((names[i] || "").trim().toLowerCase() === s) {
                var c = (colors[i] || "").trim();
                if (c) return c;
            }
        }
        var cn = detail ? detail.statusColor : (basicIssue ? basicIssue.statusColor : "");
        switch ((cn || "").toLowerCase()) {
            case "blue-gray":
            case "medium-gray": return "#42526e";
            case "yellow":      return "#f5a623";
            case "green":       return "#2ecc71";
            case "brown":       return "#8b572a";
            case "warm-red":    return "#e74c3c";
            case "purple":      return "#9b59b6";
            case "blue":        return "#3498db";
        }
        return "#7f8c8d";
    }

    background: Rectangle {
        color: PlasmaCore.Theme.backgroundColor
        border.color: PlasmaCore.Theme.textColor
        border.width: 1
        radius: 6
    }

    contentItem: ColumnLayout {
        spacing: 0

        // -------- Header --------
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: PlasmaCore.Units.smallSpacing * 2
            spacing: PlasmaCore.Units.smallSpacing

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: "[" + dlg._key() + "]  " + dlg._summary()
                font.bold: true
                font.pixelSize: PlasmaCore.Theme.defaultFont.pixelSize + 1
                wrapMode: Text.WordWrap
            }
            PlasmaComponents3.ToolButton {
                icon.name: "window-close"
                onClicked: dlg.close()
            }
        }

        // Status chip.
        Rectangle {
            Layout.leftMargin: PlasmaCore.Units.smallSpacing * 2
            Layout.preferredHeight: 22
            Layout.preferredWidth: statusChipLbl.implicitWidth + 18
            visible: dlg._status().length > 0
            radius: 4
            color: dlg._statusColor()
            PlasmaComponents3.Label {
                id: statusChipLbl
                anchors.centerIn: parent
                text: dlg._status()
                color: "white"
                font.bold: true
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: PlasmaCore.Units.smallSpacing
            Layout.preferredHeight: 1
            color: Qt.rgba(1, 1, 1, 0.12)
        }

        // -------- Scrollable body --------
        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: dlg.availableWidth
                spacing: PlasmaCore.Units.smallSpacing
                // GridLayout of label/value pairs.
                GridLayout {
                    Layout.fillWidth: true
                    Layout.margins: PlasmaCore.Units.smallSpacing * 2
                    columns: 2
                    columnSpacing: PlasmaCore.Units.largeSpacing
                    rowSpacing: PlasmaCore.Units.smallSpacing

                    PlasmaComponents3.Label { text: i18n("Tipo de actividad:"); opacity: 0.7 }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: (dlg.detail ? dlg.detail.issuetype : (dlg.basicIssue ? dlg.basicIssue.issuetype : "")) || "—"
                        font.bold: true
                    }

                    PlasmaComponents3.Label { text: i18n("Prioridad:"); opacity: 0.7 }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: (dlg.detail ? dlg.detail.priority : (dlg.basicIssue ? dlg.basicIssue.priority : "")) || "—"
                    }

                    PlasmaComponents3.Label {
                        text: i18n("Padre:"); opacity: 0.7
                        visible: dlg.detail && dlg.detail.parentKey
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        visible: dlg.detail && dlg.detail.parentKey
                        wrapMode: Text.WordWrap
                        text: dlg.detail && dlg.detail.parentKey
                              ? (dlg.detail.parentKey + "  —  " + (dlg.detail.parentSummary || ""))
                              : ""
                        font.bold: true
                    }

                    PlasmaComponents3.Label {
                        text: i18n("Asignado a:"); opacity: 0.7
                        visible: dlg.detail && dlg.detail.assignee
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        visible: dlg.detail && dlg.detail.assignee
                        text: dlg.detail ? dlg.detail.assignee : ""
                    }
                }

                // Time-tracking triple.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: PlasmaCore.Units.smallSpacing * 2
                    Layout.rightMargin: PlasmaCore.Units.smallSpacing * 2
                    spacing: PlasmaCore.Units.largeSpacing * 2
                    visible: dlg.detail && dlg.detail.hasTime

                    ColumnLayout {
                        spacing: 0
                        PlasmaComponents3.Label { text: i18n("Original"); opacity: 0.6; font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize }
                        PlasmaComponents3.Label { text: dlg.detail ? dlg.detail.originalEstimate : ""; font.bold: true }
                    }
                    ColumnLayout {
                        spacing: 0
                        PlasmaComponents3.Label { text: i18n("Quemadas"); opacity: 0.6; font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize }
                        PlasmaComponents3.Label { text: dlg.detail ? dlg.detail.timeSpent : ""; font.bold: true }
                    }
                    ColumnLayout {
                        spacing: 0
                        PlasmaComponents3.Label { text: i18n("Disponible"); opacity: 0.6; font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize }
                        PlasmaComponents3.Label { text: dlg.detail ? dlg.detail.remaining : ""; font.bold: true }
                    }
                    Item { Layout.fillWidth: true }
                }

                // Description.
                PlasmaComponents3.Label {
                    Layout.leftMargin: PlasmaCore.Units.smallSpacing * 2
                    text: i18n("Descripción"); opacity: 0.7; font.bold: true
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: PlasmaCore.Units.smallSpacing * 2
                    Layout.rightMargin: PlasmaCore.Units.smallSpacing * 2
                    Layout.preferredHeight: Math.min(160, Math.max(48, descLbl.implicitHeight + 16))
                    radius: 4
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1
                    QQC2.ScrollView {
                        anchors.fill: parent
                        anchors.margins: 8
                        clip: true
                        PlasmaComponents3.Label {
                            id: descLbl
                            width: dlg.availableWidth - PlasmaCore.Units.smallSpacing * 4 - 16
                            wrapMode: Text.WordWrap
                            text: {
                                if (dlg.loadingDetail) return i18n("Cargando…");
                                if (dlg.detailError) return dlg.detailError;
                                var d = dlg.detail ? dlg.detail.description : "";
                                return d && d.length ? d : i18n("(sin descripción)");
                            }
                        }
                    }
                }

                // Comments.
                PlasmaComponents3.Label {
                    Layout.leftMargin: PlasmaCore.Units.smallSpacing * 2
                    Layout.topMargin: PlasmaCore.Units.smallSpacing
                    text: dlg.detail
                          ? i18np("Comentario (%1)", "Comentarios (%1)", dlg.detail.comments.length)
                          : i18n("Comentarios")
                    opacity: 0.7
                    font.bold: true
                }

                PlasmaComponents3.Label {
                    Layout.leftMargin: PlasmaCore.Units.smallSpacing * 2
                    visible: dlg.detail && dlg.detail.comments.length === 0
                    opacity: 0.55
                    text: i18n("Sin comentarios.")
                }

                Repeater {
                    model: dlg.detail ? dlg.detail.comments : []
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: PlasmaCore.Units.smallSpacing * 2
                        Layout.rightMargin: PlasmaCore.Units.smallSpacing * 2
                        Layout.bottomMargin: PlasmaCore.Units.smallSpacing
                        radius: 4
                        color: Qt.rgba(1, 1, 1, 0.04)
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1
                        implicitHeight: cmtCol.implicitHeight + 12
                        ColumnLayout {
                            id: cmtCol
                            x: 8; y: 6
                            width: parent.width - 16
                            spacing: 2
                            RowLayout {
                                Layout.fillWidth: true
                                PlasmaComponents3.Label {
                                    text: modelData.author
                                    font.bold: true
                                    font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize + 1
                                }
                                Item { Layout.fillWidth: true }
                                PlasmaComponents3.Label {
                                    text: dlg._fmtDate(modelData.created)
                                    opacity: 0.55
                                    font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                                }
                            }
                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                text: modelData.body || ""
                                wrapMode: Text.WordWrap
                                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize + 1
                            }
                        }
                    }
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

            ColumnLayout {
                spacing: 0
                visible: dlg.detail
                PlasmaComponents3.Label {
                    text: dlg.detail ? i18n("Creada: %1", dlg._fmtDate(dlg.detail.created)) : ""
                    opacity: 0.55
                    font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                }
                PlasmaComponents3.Label {
                    text: dlg.detail ? i18n("Actualizada: %1", dlg._fmtDate(dlg.detail.updated)) : ""
                    opacity: 0.55
                    font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                }
            }
            Item { Layout.fillWidth: true }

            PlasmaComponents3.Button {
                text: i18n("Cerrar")
                onClicked: dlg.close()
            }
            PlasmaComponents3.Button {
                text: i18n("Abrir en Jira")
                icon.name: "globe"
                enabled: dlg._url().length > 0
                onClicked: { if (dlg._url()) Qt.openUrlExternally(dlg._url()); }
            }
        }
    }
}
