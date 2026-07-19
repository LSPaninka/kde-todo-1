/*
 * WorklogEditDialog.qml - in-popup modal to create / edit / delete a worklog.
 *
 * Two flows:
 *   - openCreate(dayMs, startMs, endMs): user drag-selected; the dialog
 *     opens with the time pre-filled and the issue picker showing the
 *     configurable JQL (worklogIssueJql) results.
 *   - openEdit(entry): user clicked an existing block; time and comment
 *     are pre-filled, the issue is locked (Jira doesn't support moving a
 *     worklog between issues from the API), and a Delete button is shown.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: dlg

    property var store              // Jira instance 1
    property var store2: null       // Jira instance 2 (optional)
    property bool store2Enabled: false
    // Which Jira tab is active: 0 = instance 1, 1 = instance 2. The picker,
    // the create and the store callbacks all route through _activeStore.
    property int activeTab: 0
    readonly property var _activeStore: (activeTab === 1 && store2) ? store2 : store
    readonly property int _vActive: _activeStore ? _activeStore.version : 0

    // Picker sort: "remaining" (horas desc), "key" (código), "status".
    property string sortMode: "remaining"

    property bool isEdit: false
    property var editingEntry: null

    property real startMs: 0
    property real endMs: 0
    property string selectedIssueKey: ""
    property string selectedIssueSummary: ""

    property bool loading: false
    property string statusText: ""
    property color statusColor: PlasmaCore.Theme.textColor

    signal saved()
    signal deleted()

    visible: false
    z: 1000

    // Grab keyboard focus when visible so Escape closes the modal.
    focus: visible
    Keys.onEscapePressed: function(event) {
        if (!dlg.loading) {
            dlg.visible = false;
            event.accepted = true;
        }
    }

    function openCreate(dayMs, sMs, eMs) {
        isEdit = false;
        editingEntry = null;
        activeTab = 0;
        startMs = sMs;
        endMs = eMs;
        commentArea.text = "";
        selectedIssueKey = "";
        selectedIssueSummary = "";
        searchField.text = "";
        statusText = "";
        visible = true;
        jiraTabs.currentIndex = 0;   // reset tab to Jira 1 (imperative, see TabBar)
        dlg.forceActiveFocus();
        _refreshPicker();
        // Warm the second instance's list too so switching tabs is instant.
        if (store2Enabled && store2) store2.fetchAssignableIssues(function(ok) {});
    }

    // instanceIndex: 0 = Jira 1, 1 = Jira 2 (the block being edited belongs
    // to that instance, so the tab is locked to it).
    function openEdit(entry, instanceIndex) {
        isEdit = true;
        editingEntry = entry;
        activeTab = (instanceIndex === 1) ? 1 : 0;
        startMs = entry.started;
        endMs = entry.started + entry.durationSec * 1000;
        commentArea.text = entry.comment || "";
        selectedIssueKey = entry.issueKey;
        selectedIssueSummary = entry.issueSummary || "";
        searchField.text = "";
        statusText = "";
        visible = true;
        jiraTabs.currentIndex = dlg.activeTab;
        dlg.forceActiveFocus();
    }

    function _refreshPicker() {
        var s = dlg._activeStore;
        if (!s) return;
        dlg.loading = true;
        s.fetchAssignableIssues(function(ok) {
            dlg.loading = false;
            if (!ok) {
                statusText = i18n("No se pudo cargar la lista de issues.");
                statusColor = PlasmaCore.Theme.negativeTextColor;
            }
        });
    }

    // Filter + sort the active store's assignable issues for the picker.
    function _pickerRows() {
        var s = dlg._activeStore;
        var arr = (s && s.assignableIssues) ? s.assignableIssues.slice() : [];
        var q = (searchField.text || "").trim().toLowerCase();
        if (q.length > 0) {
            arr = arr.filter(function(it) {
                var hay = (it.key + " " + it.summary + " " + it.issuetype + " " + it.status).toLowerCase();
                return hay.indexOf(q) >= 0;
            });
        }
        if (dlg.sortMode === "remaining") {
            arr.sort(function(a, b) { return (b.remainingSec || 0) - (a.remainingSec || 0); });
        } else if (dlg.sortMode === "status") {
            arr.sort(function(a, b) { return ("" + a.status).localeCompare("" + b.status); });
        } else {
            arr.sort(function(a, b) { return ("" + a.key).localeCompare("" + b.key); });
        }
        return arr;
    }

    function _fmtTime(ms) {
        var d = new Date(ms);
        var h = d.getHours();
        var m = d.getMinutes();
        return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
    }
    function _adjust(ms, deltaMin) {
        return ms + deltaMin * 60000;
    }
    // Parses "HH:MM" from a TextField and applies the hour/minute pair to
    // dlg.startMs or dlg.endMs (preserving the date part). On invalid
    // input we just refuse — the TextField's binding-via-onChanged
    // re-formats the value back to the current ms.
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
            if (newMs >= endMs) return false;   // keep start < end
            startMs = newMs;
        } else {
            if (newMs <= startMs) return false; // keep end > start
            endMs = newMs;
        }
        return true;
    }
    function _durationSec() { return Math.max(60, Math.round((endMs - startMs) / 1000)); }
    function _fmtDuration(sec) {
        var h = Math.floor(sec / 3600);
        var m = Math.floor((sec % 3600) / 60);
        if (h > 0 && m > 0) return h + "h " + m + "m";
        if (h > 0)          return h + "h";
        return m + "m";
    }

    // -------- backdrop --------
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.55
        MouseArea { anchors.fill: parent; onClicked: if (!dlg.loading) dlg.visible = false }
    }

    // -------- card --------
    // Size taken from the configurable worklogModalWidth/Height kcfgs,
    // capped at the parent's available size minus a small margin so the
    // modal never spills outside the popup.
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
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: dlg.isEdit ? i18n("Editar worklog") : i18n("Nuevo worklog")
                    font.bold: true
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "window-close"
                    enabled: !dlg.loading
                    onClicked: dlg.visible = false
                }
            }

            // Date + time bar
            RowLayout {
                Layout.fillWidth: true
                spacing: PlasmaCore.Units.smallSpacing
                PlasmaComponents3.Label {
                    text: {
                        if (!dlg.startMs) return "";
                        var d = new Date(dlg.startMs);
                        var names = ["Dom","Lun","Mar","Mié","Jue","Vie","Sáb"];
                        return names[d.getDay()] + " " + d.getDate() + "/" +
                               ("0" + (d.getMonth() + 1)).slice(-2) + "/" + d.getFullYear();
                    }
                    font.bold: true
                }
                Item { Layout.fillWidth: true }

                // Start time
                PlasmaComponents3.Label { text: i18n("Inicio:"); opacity: 0.7 }
                PlasmaComponents3.ToolButton {
                    icon.name: "list-remove"
                    onClicked: dlg.startMs = dlg._adjust(dlg.startMs, -30)
                }
                QQC2.TextField {
                    id: startTimeField
                    Layout.preferredWidth: 60
                    horizontalAlignment: Text.AlignHCenter
                    font.family: "monospace"
                    inputMask: "99:99;_"
                    text: dlg._fmtTime(dlg.startMs)
                    onEditingFinished: {
                        if (!dlg._applyTimeText(text, true)) {
                            text = dlg._fmtTime(dlg.startMs);   // bounce back if invalid
                        }
                    }
                    // External changes (via ± buttons) should re-format the
                    // field — but only when the field isn't being edited,
                    // so we don't yank the cursor while the user types.
                    Connections {
                        target: dlg
                        function onStartMsChanged() {
                            if (!startTimeField.activeFocus) {
                                startTimeField.text = dlg._fmtTime(dlg.startMs);
                            }
                        }
                    }
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "list-add"
                    onClicked: {
                        var next = dlg._adjust(dlg.startMs, 30);
                        if (next < dlg.endMs) dlg.startMs = next;
                    }
                }

                Item { Layout.preferredWidth: 16 }

                // End time
                PlasmaComponents3.Label { text: i18n("Fin:"); opacity: 0.7 }
                PlasmaComponents3.ToolButton {
                    icon.name: "list-remove"
                    onClicked: {
                        var prev = dlg._adjust(dlg.endMs, -30);
                        if (prev > dlg.startMs) dlg.endMs = prev;
                    }
                }
                QQC2.TextField {
                    id: endTimeField
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
                            if (!endTimeField.activeFocus) {
                                endTimeField.text = dlg._fmtTime(dlg.endMs);
                            }
                        }
                    }
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "list-add"
                    onClicked: dlg.endMs = dlg._adjust(dlg.endMs, 30)
                }
            }

            // Duration moved out of the time row so resizing it (4h → 4h 30m)
            // doesn't shift the +/- buttons. Aligned right under the Fin
            // group so it's still visually anchored to the duration.
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: i18n("Duración: %1", dlg._fmtDuration(dlg._durationSec()))
                opacity: 0.65
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            }

            // Issue picker (create mode) or fixed label (edit mode).
            PlasmaComponents3.Label { text: i18n("Issue"); opacity: 0.7 }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: dlg.isEdit
                text: dlg.editingEntry
                      ? ("[" + dlg.editingEntry.issueKey + "] " + (dlg.editingEntry.issueSummary || ""))
                      : ""
                font.bold: true
                wrapMode: Text.WordWrap
            }

            // Jira instance tabs — only when a second Jira is enabled and
            // we're creating (edit locks to the block's own instance).
            // currentIndex is set imperatively from openCreate/openEdit (not
            // bound) — a user click sets it internally and would otherwise
            // break a `currentIndex:` binding, leaving the tab out of sync.
            QQC2.TabBar {
                id: jiraTabs
                Layout.fillWidth: true
                visible: dlg.store2Enabled && !dlg.isEdit
                onCurrentIndexChanged: {
                    if (currentIndex === dlg.activeTab) return;
                    dlg.activeTab = currentIndex;
                    dlg.selectedIssueKey = "";
                    dlg.selectedIssueSummary = "";
                    dlg._refreshPicker();
                }
                QQC2.TabButton { text: i18n("Jira 1") }
                QQC2.TabButton { text: i18n("Jira 2") }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: !dlg.isEdit
                spacing: PlasmaCore.Units.smallSpacing

                PlasmaCore.IconItem {
                    source: "search"
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                }
                PlasmaComponents3.TextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: i18n("Filtrar issues por texto…")
                }
                // Sort order: hours desc / code / status.
                QQC2.ComboBox {
                    id: sortCombo
                    Layout.preferredWidth: 150
                    textRole: "label"
                    model: [
                        { key: "remaining", label: i18n("Horas (desc)") },
                        { key: "key",       label: i18n("Código") },
                        { key: "status",    label: i18n("Estado") }
                    ]
                    currentIndex: {
                        if (dlg.sortMode === "key") return 1;
                        if (dlg.sortMode === "status") return 2;
                        return 0;
                    }
                    onActivated: function(idx) { dlg.sortMode = sortCombo.model[idx].key; }
                    PlasmaComponents3.ToolTip.text: i18n("Ordenar la lista")
                    PlasmaComponents3.ToolTip.visible: hovered
                    PlasmaComponents3.ToolTip.delay: 500
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "view-refresh"
                    enabled: !dlg.loading
                    onClicked: dlg._refreshPicker()
                    PlasmaComponents3.ToolTip.text: i18n("Recargar JQL")
                    PlasmaComponents3.ToolTip.visible: hovered
                    PlasmaComponents3.ToolTip.delay: 500
                }
            }

            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 180
                visible: !dlg.isEdit
                clip: true

                ListView {
                    id: pickerList
                    spacing: 2
                    model: (dlg._vActive, dlg.sortMode, searchField.text, dlg._pickerRows())
                    delegate: Rectangle {
                        width: pickerList.width
                        height: row.implicitHeight + 6
                        color: dlg.selectedIssueKey === modelData.key
                               ? Qt.rgba(PlasmaCore.Theme.highlightColor.r,
                                         PlasmaCore.Theme.highlightColor.g,
                                         PlasmaCore.Theme.highlightColor.b, 0.35)
                               : (rowMouse.containsMouse
                                  ? Qt.rgba(1, 1, 1, 0.06)
                                  : "transparent")
                        radius: 2
                        RowLayout {
                            id: row
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 6
                            PlasmaComponents3.Label {
                                text: modelData.key
                                font.family: "monospace"
                                font.bold: true
                                Layout.preferredWidth: 90
                            }
                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                text: modelData.summary
                                elide: Text.ElideRight
                            }
                            PlasmaComponents3.Label {
                                text: {
                                    var parts = [];
                                    if (modelData.issuetype) parts.push(modelData.issuetype);
                                    if (modelData.status)    parts.push(modelData.status);
                                    if (modelData.remainingSec > 0)
                                        parts.push(dlg._fmtDuration(modelData.remainingSec));
                                    return parts.join(" · ");
                                }
                                opacity: 0.6
                                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                            }
                        }
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                dlg.selectedIssueKey = modelData.key;
                                dlg.selectedIssueSummary = modelData.summary;
                            }
                        }
                    }

                    PlasmaComponents3.Label {
                        anchors.centerIn: parent
                        visible: pickerList.count === 0 && !dlg.loading
                        text: i18n("Sin resultados. Ajustá el JQL en Configurar → Jira.")
                        opacity: 0.55
                    }
                    PlasmaComponents3.BusyIndicator {
                        anchors.centerIn: parent
                        running: dlg.loading
                        visible: running
                    }
                }
            }

            // Selected issue echo (create mode).
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: !dlg.isEdit && dlg.selectedIssueKey.length > 0
                text: i18n("Seleccionada: %1 — %2",
                           dlg.selectedIssueKey, dlg.selectedIssueSummary)
                opacity: 0.85
                wrapMode: Text.WordWrap
            }

            // Comment
            PlasmaComponents3.Label { text: i18n("Comentario"); opacity: 0.7 }
            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                QQC2.TextArea {
                    id: commentArea
                    placeholderText: i18n("Notas opcionales sobre este worklog…")
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

            // Footer actions
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
                        dlg._activeStore.deleteWorklog(dlg.editingEntry.issueKey, dlg.editingEntry.id);
                    }
                }
                PlasmaComponents3.Button {
                    text: i18n("Cancelar")
                    enabled: !dlg.loading
                    onClicked: dlg.visible = false
                }
                PlasmaComponents3.Button {
                    text: dlg.isEdit ? i18n("Guardar") : i18n("Crear")
                    enabled: !dlg.loading &&
                             (dlg.isEdit || dlg.selectedIssueKey.length > 0) &&
                             dlg.endMs > dlg.startMs
                    icon.name: "document-save"
                    onClicked: {
                        dlg.loading = true;
                        dlg.statusText = dlg.isEdit ? i18n("Guardando…") : i18n("Creando…");
                        dlg.statusColor = PlasmaCore.Theme.textColor;
                        var dur = dlg._durationSec();
                        if (dlg.isEdit) {
                            dlg._activeStore.updateWorklog(
                                dlg.editingEntry.issueKey,
                                dlg.editingEntry.id,
                                new Date(dlg.startMs),
                                dur,
                                commentArea.text || ""
                            );
                        } else {
                            dlg._activeStore.createWorklog(
                                dlg.selectedIssueKey,
                                new Date(dlg.startMs),
                                dur,
                                commentArea.text || ""
                            );
                        }
                    }
                }
            }
        }
    }

    // -------- store callbacks --------
    // Target follows the active tab so both instances' create/update/delete
    // results land here (the modal is single-flight, so the target won't
    // switch mid-operation).
    Connections {
        target: dlg._activeStore
        function onCreateFinished(ok, err) {
            dlg.loading = false;
            if (ok) {
                dlg.statusText = i18n("Creado.");
                dlg.statusColor = PlasmaCore.Theme.positiveTextColor;
                dlg.visible = false;
                dlg.saved();
            } else {
                dlg.statusText = i18n("Error: %1", err);
                dlg.statusColor = PlasmaCore.Theme.negativeTextColor;
            }
        }
        function onUpdateFinished(ok, err) {
            dlg.loading = false;
            if (ok) {
                dlg.statusText = i18n("Guardado.");
                dlg.statusColor = PlasmaCore.Theme.positiveTextColor;
                dlg.visible = false;
                dlg.saved();
            } else {
                dlg.statusText = i18n("Error: %1", err);
                dlg.statusColor = PlasmaCore.Theme.negativeTextColor;
            }
        }
        function onDeleteFinished(ok, err) {
            dlg.loading = false;
            if (ok) {
                dlg.visible = false;
                dlg.deleted();
            } else {
                dlg.statusText = i18n("Error al eliminar: %1", err);
                dlg.statusColor = PlasmaCore.Theme.negativeTextColor;
            }
        }
    }
}
