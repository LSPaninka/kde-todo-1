/*
 * ClockifyEditDialog.qml - in-popup modal to create / edit / delete a
 * Clockify time entry. Mirrors the layout of WorklogEditDialog but
 * swaps the Jira issue picker for a Clockify project ComboBox and
 * adds a tags multi-select + billable toggle.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: dlg
    property var store

    property bool isEdit: false
    property var editingEntry: null

    property real startMs: 0
    property real endMs: 0
    property string selectedProjectId: ""
    property var selectedTagIds: []
    property bool billable: true

    property bool loading: false
    property string statusText: ""
    property color statusColor: PlasmaCore.Theme.textColor

    signal saved()
    signal deleted()

    visible: false
    z: 1000

    focus: visible
    Keys.onEscapePressed: function(event) {
        if (!dlg.loading) {
            dlg.visible = false;
            event.accepted = true;
        }
    }

    function openCreate(sMs, eMs) {
        isEdit = false;
        editingEntry = null;
        startMs = sMs;
        endMs = eMs;
        descArea.text = "";
        selectedProjectId = plasmoidConfigDefaultProject();
        selectedTagIds = [];
        billable = plasmoidConfigDefaultBillable();
        statusText = "";
        visible = true;
        dlg.forceActiveFocus();
        _ensureContext();
    }
    function openEdit(entry) {
        isEdit = true;
        editingEntry = entry;
        startMs = entry.started;
        endMs = entry.started + entry.durationSec * 1000;
        descArea.text = entry.description || "";
        selectedProjectId = entry.projectId || "";
        selectedTagIds = (entry.tagIds || []).slice();
        billable = entry.billable === true;
        statusText = "";
        visible = true;
        dlg.forceActiveFocus();
        _ensureContext();
    }

    function plasmoidConfigDefaultProject() {
        return (typeof plasmoid !== "undefined" && plasmoid)
               ? (plasmoid.configuration.clockifyDefaultProjectId || "")
               : "";
    }
    function plasmoidConfigDefaultBillable() {
        if (typeof plasmoid === "undefined" || !plasmoid) return true;
        return plasmoid.configuration.clockifyBillableDefault !== false;
    }

    function _ensureContext() {
        if (!store) return;
        dlg.loading = true;
        store.ensureContext(function(ok) {
            dlg.loading = false;
            if (!ok) {
                statusText = i18n("No se pudo conectar a Clockify (revisá la API key).");
                statusColor = PlasmaCore.Theme.negativeTextColor;
            }
        });
    }

    function _fmtTime(ms) {
        var d = new Date(ms);
        function p(n) { return n < 10 ? "0" + n : "" + n; }
        return p(d.getHours()) + ":" + p(d.getMinutes());
    }
    function _adjust(ms, deltaMin) { return ms + deltaMin * 60000; }
    function _applyTimeText(text, isStart) {
        if (!text) return false;
        var m = text.match(/^\s*(\d{1,2})\s*:\s*(\d{1,2})\s*$/);
        if (!m) return false;
        var hh = parseInt(m[1], 10);
        var mm = parseInt(m[2], 10);
        if (isNaN(hh) || isNaN(mm) || hh < 0 || hh > 23 || mm < 0 || mm > 59) return false;
        var d = new Date(isStart ? startMs : endMs);
        d.setHours(hh, mm, 0, 0);
        var newMs = d.getTime();
        if (isStart) {
            if (newMs >= endMs) return false;
            startMs = newMs;
        } else {
            if (newMs <= startMs) return false;
            endMs = newMs;
        }
        return true;
    }
    function _durationSec() { return Math.max(60, Math.round((endMs - startMs) / 1000)); }
    function _fmtDur(sec) {
        var h = Math.floor(sec / 3600);
        var m = Math.floor((sec % 3600) / 60);
        if (h > 0 && m > 0) return h + "h " + m + "m";
        if (h > 0)          return h + "h";
        return m + "m";
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.55
        MouseArea { anchors.fill: parent; onClicked: if (!dlg.loading) dlg.visible = false }
    }

    // Card size taken from the configurable worklogModalWidth/Height
    // kcfg, capped at parent's available size minus a small margin.
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

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: dlg.isEdit ? i18n("Editar entrada Clockify")
                                     : i18n("Nueva entrada Clockify")
                    font.bold: true
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "window-close"
                    enabled: !dlg.loading
                    onClicked: dlg.visible = false
                }
            }

            // Time row.
            RowLayout {
                Layout.fillWidth: true
                spacing: PlasmaCore.Units.smallSpacing

                PlasmaComponents3.Label {
                    text: {
                        if (!dlg.startMs) return "";
                        var d = new Date(dlg.startMs);
                        var names = ["Dom","Lun","Mar","Mié","Jue","Vie","Sáb"];
                        function p(n) { return n < 10 ? "0" + n : "" + n; }
                        return names[d.getDay()] + " " + d.getDate() + "/" +
                               p(d.getMonth() + 1) + "/" + d.getFullYear();
                    }
                    font.bold: true
                }
                Item { Layout.fillWidth: true }

                PlasmaComponents3.Label { text: i18n("Inicio:"); opacity: 0.7 }
                PlasmaComponents3.ToolButton {
                    icon.name: "list-remove"
                    onClicked: dlg.startMs = dlg._adjust(dlg.startMs, -30)
                }
                QQC2.TextField {
                    id: startTimeFieldC
                    Layout.preferredWidth: 60
                    horizontalAlignment: Text.AlignHCenter
                    font.family: "monospace"
                    inputMask: "99:99;_"
                    text: dlg._fmtTime(dlg.startMs)
                    onEditingFinished: {
                        if (!dlg._applyTimeText(text, true)) {
                            text = dlg._fmtTime(dlg.startMs);
                        }
                    }
                    Connections {
                        target: dlg
                        function onStartMsChanged() {
                            if (!startTimeFieldC.activeFocus) {
                                startTimeFieldC.text = dlg._fmtTime(dlg.startMs);
                            }
                        }
                    }
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "list-add"
                    onClicked: {
                        var n = dlg._adjust(dlg.startMs, 30);
                        if (n < dlg.endMs) dlg.startMs = n;
                    }
                }
                Item { Layout.preferredWidth: 16 }
                PlasmaComponents3.Label { text: i18n("Fin:"); opacity: 0.7 }
                PlasmaComponents3.ToolButton {
                    icon.name: "list-remove"
                    onClicked: {
                        var p = dlg._adjust(dlg.endMs, -30);
                        if (p > dlg.startMs) dlg.endMs = p;
                    }
                }
                QQC2.TextField {
                    id: endTimeFieldC
                    Layout.preferredWidth: 60
                    horizontalAlignment: Text.AlignHCenter
                    font.family: "monospace"
                    inputMask: "99:99;_"
                    text: dlg._fmtTime(dlg.endMs)
                    onEditingFinished: {
                        if (!dlg._applyTimeText(text, false)) {
                            text = dlg._fmtTime(dlg.endMs);
                        }
                    }
                    Connections {
                        target: dlg
                        function onEndMsChanged() {
                            if (!endTimeFieldC.activeFocus) {
                                endTimeFieldC.text = dlg._fmtTime(dlg.endMs);
                            }
                        }
                    }
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "list-add"
                    onClicked: dlg.endMs = dlg._adjust(dlg.endMs, 30)
                }
            }

            // Duration moved below the time row so it doesn't shove the
            // +/- buttons every time the rounding changes width.
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: i18n("Duración: %1", dlg._fmtDur(dlg._durationSec()))
                opacity: 0.65
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            }

            // Project picker.
            PlasmaComponents3.Label { text: i18n("Proyecto"); opacity: 0.7 }
            RowLayout {
                Layout.fillWidth: true
                spacing: PlasmaCore.Units.smallSpacing

                Rectangle {
                    width: 14
                    height: 14
                    radius: 2
                    color: {
                        if (!store) return "transparent";
                        var p = store ? _projectById(store.projects, dlg.selectedProjectId) : null;
                        return p && p.color ? p.color : "transparent";
                    }
                    border.color: Qt.rgba(1, 1, 1, 0.3)
                    border.width: 1
                    Layout.alignment: Qt.AlignVCenter
                }
                QQC2.ComboBox {
                    id: projectCombo
                    Layout.fillWidth: true
                    model: store ? [{id:"", name: i18n("(sin proyecto)")}].concat(store.projects) : []
                    textRole: "name"
                    valueRole: "id"
                    currentIndex: _indexOfId(model, dlg.selectedProjectId)
                    onActivated: dlg.selectedProjectId = model[currentIndex].id
                    function _indexOfId(arr, id) {
                        for (var i = 0; i < arr.length; i++) {
                            if (arr[i].id === id) return i;
                        }
                        return 0;
                    }
                }
            }

            // Tags (multi-select via inline chips).
            PlasmaComponents3.Label {
                text: i18n("Tags") + (store && store.tags.length === 0 ? "  " + i18n("(no hay tags)") : "")
                opacity: 0.7
            }
            Flow {
                Layout.fillWidth: true
                spacing: 4
                visible: store && store.tags.length > 0
                Repeater {
                    model: store ? store.tags : []
                    Rectangle {
                        property bool checked: dlg.selectedTagIds.indexOf(modelData.id) >= 0
                        height: 20
                        width: tagLabel.implicitWidth + 14
                        radius: 10
                        color: checked
                               ? PlasmaCore.Theme.highlightColor
                               : Qt.rgba(1, 1, 1, 0.06)
                        border.color: checked
                                      ? PlasmaCore.Theme.highlightColor
                                      : Qt.rgba(1, 1, 1, 0.2)
                        border.width: 1
                        PlasmaComponents3.Label {
                            id: tagLabel
                            anchors.centerIn: parent
                            text: modelData.name
                            color: checked ? "white" : PlasmaCore.Theme.textColor
                            font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var arr = dlg.selectedTagIds.slice();
                                var i = arr.indexOf(modelData.id);
                                if (i >= 0) arr.splice(i, 1);
                                else arr.push(modelData.id);
                                dlg.selectedTagIds = arr;
                            }
                        }
                    }
                }
            }

            // Billable.
            QQC2.CheckBox {
                text: i18n("Facturable (billable)")
                checked: dlg.billable
                onToggled: dlg.billable = checked
            }

            // Description.
            PlasmaComponents3.Label { text: i18n("Descripción"); opacity: 0.7 }
            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                QQC2.TextArea {
                    id: descArea
                    placeholderText: i18n("Qué hiciste en este intervalo")
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    font.pixelSize: 12
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: dlg.statusText.length > 0
                text: dlg.statusText
                color: dlg.statusColor
                wrapMode: Text.WordWrap
            }

            // Footer.
            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents3.BusyIndicator {
                    visible: dlg.loading
                    running: visible
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents3.Button {
                    visible: dlg.isEdit
                    enabled: !dlg.loading
                    icon.name: "edit-delete"
                    text: i18n("Eliminar")
                    onClicked: {
                        if (!dlg.editingEntry) return;
                        dlg.loading = true;
                        dlg.statusText = i18n("Eliminando…");
                        store.deleteEntry(dlg.editingEntry.id);
                    }
                }
                PlasmaComponents3.Button {
                    text: i18n("Cancelar")
                    enabled: !dlg.loading
                    onClicked: dlg.visible = false
                }
                PlasmaComponents3.Button {
                    text: dlg.isEdit ? i18n("Guardar") : i18n("Crear")
                    enabled: !dlg.loading && dlg.endMs > dlg.startMs
                    icon.name: "document-save"
                    onClicked: {
                        dlg.loading = true;
                        dlg.statusText = dlg.isEdit ? i18n("Guardando…") : i18n("Creando…");
                        dlg.statusColor = PlasmaCore.Theme.textColor;
                        var sd = new Date(dlg.startMs);
                        var ed = new Date(dlg.endMs);
                        if (dlg.isEdit) {
                            store.updateEntry(
                                dlg.editingEntry.id,
                                sd, ed,
                                descArea.text || "",
                                dlg.selectedProjectId || "",
                                dlg.selectedTagIds,
                                dlg.billable
                            );
                        } else {
                            store.createEntry(
                                sd, ed,
                                descArea.text || "",
                                dlg.selectedProjectId || "",
                                dlg.selectedTagIds,
                                dlg.billable
                            );
                        }
                    }
                }
            }
        }
    }

    function _projectById(arr, id) {
        if (!id) return null;
        for (var i = 0; i < (arr || []).length; i++) {
            if (arr[i].id === id) return arr[i];
        }
        return null;
    }

    Connections {
        target: dlg.store
        function onCreateFinished(ok, err) {
            dlg.loading = false;
            if (ok) { dlg.visible = false; dlg.saved(); }
            else {
                dlg.statusText = i18n("Error: %1", err);
                dlg.statusColor = PlasmaCore.Theme.negativeTextColor;
            }
        }
        function onUpdateFinished(ok, err) {
            dlg.loading = false;
            if (ok) { dlg.visible = false; dlg.saved(); }
            else {
                dlg.statusText = i18n("Error: %1", err);
                dlg.statusColor = PlasmaCore.Theme.negativeTextColor;
            }
        }
        function onDeleteFinished(ok, err) {
            dlg.loading = false;
            if (ok) { dlg.visible = false; dlg.deleted(); }
            else {
                dlg.statusText = i18n("Error al eliminar: %1", err);
                dlg.statusColor = PlasmaCore.Theme.negativeTextColor;
            }
        }
    }
}
