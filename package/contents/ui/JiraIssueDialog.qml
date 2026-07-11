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
    property string _currentKey: ""

    // When opened from a linked ToDo task, this holds that task's id so the
    // "Cambiar subtarea anexada" button can offer to re-pick. 0 = plain mode.
    property int linkTaskId: 0
    signal relinkRequested(int taskId)

    // Status-transition menu state.
    property var _transitions: []
    property bool _transitionsLoading: false

    modal: true
    anchors.centerIn: parent
    width: Math.min(560, (parent ? parent.width : 560) - 24)
    height: Math.min(560, (parent ? parent.height : 560) - 24)
    padding: 0
    // No standardButtons — the footer buttons are custom (Cerrar / Abrir).

    // Always start scrolled at the top; QQC2.ScrollView otherwise keeps its
    // previous scroll offset across reopens (top rows appeared cut off).
    onOpened: if (bodyScroll.contentItem) bodyScroll.contentItem.contentY = 0;

    function openFor(issue) {
        linkTaskId = 0;
        basicIssue = issue;
        _currentKey = issue ? (issue.key || "") : "";
        _transitions = [];
        _transitionsLoading = false;
        open();
        _fetchDetail();
    }

    // Opened from a linked ToDo task: shows the "Cambiar subtarea" button.
    function openForLinked(jiraKey, taskId) {
        linkTaskId = taskId || 0;
        basicIssue = { key: jiraKey || "" };
        _currentKey = jiraKey || "";
        _transitions = [];
        _transitionsLoading = false;
        open();
        _fetchDetail();
    }

    function _fetchDetail() {
        detail = null;
        detailError = "";
        if (jira && _currentKey) {
            loadingDetail = true;
            jira.fetchIssueDetail(_currentKey, function(ok, d, err) {
                dlg.loadingDetail = false;
                if (ok) dlg.detail = d;
                else dlg.detailError = err || i18n("No se pudo cargar el detalle.");
            });
        } else {
            loadingDetail = false;
            detailError = i18n("Sin datos de la incidencia.");
        }
    }

    // -------- Status transitions --------
    function _openStateMenu() {
        dlg._transitions = [];
        dlg._transitionsLoading = true;
        stateMenuDlg.open();
        if (jira && dlg._currentKey) {
            jira.fetchTransitions(dlg._currentKey, function(ok, arr) {
                dlg._transitionsLoading = false;
                dlg._transitions = ok ? arr : [];
            });
        } else {
            dlg._transitionsLoading = false;
        }
    }
    function _applyTransition(id) {
        if (!jira || !dlg._currentKey) return;
        jira.transitionIssue(dlg._currentKey, id, function(ok, err) {
            if (ok) {
                dlg._fetchDetail();   // refresh the modal
                jira.fetch();         // refresh the list behind it
            }
        });
    }

    // -------- Consumed-hours helpers (calculated strategy) --------
    function _fmtH(sec) {
        if (!sec || sec <= 0) return "0h";
        var h = Math.floor(sec / 3600);
        var m = Math.floor((sec % 3600) / 60);
        if (h > 0 && m > 0) return h + "h " + m + "m";
        if (h > 0) return h + "h";
        return m + "m";
    }
    function _barColorFor(orig, spent) {
        if (spent > orig) return "#e74c3c";
        var r = orig > 0 ? spent / orig : 0;
        if (r >= 0.9) return "#e67e22";
        if (r >= 0.7) return "#f1c40f";
        return "#2ecc71";
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

    // NB: the content is wrapped in a plain Item (not a Layout directly as
    // contentItem). A ColumnLayout used as contentItem collapses to its
    // implicit height on reopen (a QQC2.Dialog quirk) — the body was cut in
    // half the 2nd time. The Item is sized reliably by the Dialog and the
    // ColumnLayout anchors-fills it.
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
            id: bodyScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth   // never scroll horizontally

            ColumnLayout {
                width: bodyScroll.availableWidth
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

                // Consumed-hours bar (min(spent, original) / original).
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: PlasmaCore.Units.smallSpacing * 2
                    Layout.rightMargin: PlasmaCore.Units.smallSpacing * 2
                    visible: dlg.detail && dlg.detail.originalSec > 0
                    spacing: PlasmaCore.Units.smallSpacing

                    Rectangle {
                        id: dlgBarTrack
                        Layout.fillWidth: true
                        Layout.preferredHeight: 8
                        radius: 4
                        color: Qt.rgba(1, 1, 1, 0.10)
                        Rectangle {
                            width: {
                                if (!dlg.detail || dlg.detail.originalSec <= 0) return 0;
                                var r = Math.min(1, dlg.detail.spentSec / dlg.detail.originalSec);
                                return Math.round(dlgBarTrack.width * r);
                            }
                            height: parent.height
                            radius: 4
                            color: dlg.detail ? dlg._barColorFor(dlg.detail.originalSec, dlg.detail.spentSec) : "#2ecc71"
                        }
                    }
                    PlasmaComponents3.Label {
                        text: dlg.detail ? (dlg._fmtH(dlg.detail.spentSec) + " / " + dlg._fmtH(dlg.detail.originalSec)) : ""
                        font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                        opacity: 0.7
                    }
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
                    Layout.preferredHeight: Math.min(240, Math.max(120, descLbl.implicitHeight + 16))
                    radius: 4
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1
                    QQC2.ScrollView {
                        anchors.fill: parent
                        anchors.margins: 8
                        clip: true
                        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
                        PlasmaComponents3.Label {
                            id: descLbl
                            width: dlg.availableWidth - PlasmaCore.Units.smallSpacing * 4 - 16
                            wrapMode: Text.WordWrap
                            // Same type/size as the comment bodies below.
                            font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize + 1
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

            // Icon-only actions (tooltips describe them).
            PlasmaComponents3.ToolButton {
                icon.name: "checkmark"
                enabled: dlg.jira && dlg._currentKey.length > 0
                onClicked: dlg._openStateMenu()
                PlasmaComponents3.ToolTip.text: i18n("Cambiar estado")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500

                QQC2.Menu {
                    id: stateMenuDlg
                    y: -implicitHeight   // open above the footer button

                    QQC2.MenuItem {
                        text: i18n("Cargando…")
                        enabled: false
                        visible: dlg._transitionsLoading
                        height: visible ? implicitHeight : 0
                    }
                    QQC2.MenuItem {
                        text: i18n("(sin transiciones)")
                        enabled: false
                        visible: !dlg._transitionsLoading && dlg._transitions.length === 0
                        height: visible ? implicitHeight : 0
                    }
                    Instantiator {
                        model: dlg._transitions
                        delegate: QQC2.MenuItem {
                            text: modelData.toStatus
                                  ? (modelData.name + " → " + modelData.toStatus)
                                  : modelData.name
                            onTriggered: {
                                dlg._applyTransition(modelData.id);
                                stateMenuDlg.close();
                            }
                        }
                        onObjectAdded: function(index, object) { stateMenuDlg.insertItem(index, object); }
                        onObjectRemoved: function(index, object) { stateMenuDlg.removeItem(object); }
                    }
                }
            }

            // Only shown when the modal was opened from a linked ToDo task.
            PlasmaComponents3.ToolButton {
                visible: dlg.linkTaskId > 0
                icon.name: "document-swap"
                onClicked: {
                    var t = dlg.linkTaskId;
                    dlg.close();
                    dlg.relinkRequested(t);
                }
                PlasmaComponents3.ToolTip.text: i18n("Cambiar subtarea anexada")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
            PlasmaComponents3.ToolButton {
                icon.name: "globe"
                enabled: dlg._url().length > 0
                onClicked: { if (dlg._url()) Qt.openUrlExternally(dlg._url()); }
                PlasmaComponents3.ToolTip.text: i18n("Abrir en Jira")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
        }
      }
    }
}
