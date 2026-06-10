/*
 * FullRepresentation.qml - popup contents.
 *
 * Header   : title, week nav (← Today →), week label, view-mode toggle
 *            (9h ↔ 24h), sync ↻, debug ⓘ, pin 📌.
 * Body     : WorklogCalendar wired to both stores; emits separate
 *            create/edit signals for Jira and Clockify entries.
 * Footer   : week-total + (in jira-clockify mode) "Sync Jira → Clockify"
 *            button, mode hamburger menu (Jira / Jira-Clockify / Clockify),
 *            Configure… button.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: full

    property var jiraStore
    property var clockifyStore

    property date currentWeekStart: _sundayOf(new Date())
    readonly property int _vJira: jiraStore ? jiraStore.version : 0
    readonly property int _vClockify: clockifyStore ? clockifyStore.version : 0

    readonly property string source: plasmoid.configuration.worklogSource || "jira"
    readonly property bool _isCombined: source === "jira-clockify"
    readonly property bool _showJira: source === "jira" || source === "jira-clockify"
    readonly property bool _showClockify: source === "clockify" || source === "jira-clockify"

    // Transient status text driven by sync flows. The status label's text
    // is a *binding* on these three values — never assigned imperatively
    // (doing so would clobber the binding, which is what made the message
    // stick previously).
    property string _statusOverride: ""
    property color  _statusOverrideColor: PlasmaCore.Theme.textColor
    property bool   _statusOverrideHoldsError: false

    Timer {
        id: _clearStatusTimer
        interval: 6000
        onTriggered: {
            full._statusOverride = "";
            full._statusOverrideHoldsError = false;
        }
    }
    function _setStatus(text, isError) {
        _statusOverride = text;
        _statusOverrideColor = isError ? PlasmaCore.Theme.negativeTextColor
                                        : PlasmaCore.Theme.positiveTextColor;
        _statusOverrideHoldsError = !!isError;
        _clearStatusTimer.restart();
    }

    // Project selected from the footer ComboBox used by the
    // "Jira → Clockify" sync button. Initialised from the config default;
    // changes are written back so the choice persists across reloads.
    property string syncProjectId: plasmoid.configuration.clockifyDefaultProjectId || ""

    Connections {
        target: plasmoid.configuration
        function onClockifyDefaultProjectIdChanged() {
            // Keep the in-memory value in sync if the user edits the
            // config dialog while the popup is open.
            full.syncProjectId = plasmoid.configuration.clockifyDefaultProjectId || "";
        }
    }

    function _sundayOf(d) {
        var c = new Date(d);
        c.setHours(0, 0, 0, 0);
        c.setDate(c.getDate() - c.getDay());
        return c;
    }
    function _formatWeekLabel(start) {
        var end = new Date(start.getTime() + 6 * 24 * 60 * 60 * 1000);
        var months = ["Ene","Feb","Mar","Abr","May","Jun","Jul","Ago","Sep","Oct","Nov","Dic"];
        return start.getDate() + " " + months[start.getMonth()] + " — " +
               end.getDate()   + " " + months[end.getMonth()] + " " + end.getFullYear();
    }

    // The bottom panel (below the calendar) is available in EVERY mode and
    // can show either the Sprint/Horas rings or the monthly heatmap. A
    // vertical switch on its right flips between the two views. The whole
    // panel can be hidden via worklogShowSprintGauges (master toggle).
    readonly property bool _showBottomPanel:
        plasmoid.configuration.worklogShowSprintGauges !== false
    readonly property string _bottomView:
        plasmoid.configuration.worklogBottomView || "rings"
    readonly property bool _bottomIsRings:   _bottomView !== "heatmap"
    readonly property bool _bottomIsHeatmap: _bottomView === "heatmap"

    function syncNow() {
        if (_showJira     && jiraStore)     jiraStore.fetchWeek(currentWeekStart);
        if (_showClockify && clockifyStore) clockifyStore.fetchWeek(currentWeekStart);
        if (_showBottomPanel && _bottomIsRings   && jiraStore) jiraStore.fetchSprintInfo();
        if (_showBottomPanel && _bottomIsHeatmap)              monthHeatmap.refresh();
    }

    function syncJiraIntoClockify() {
        if (!jiraStore || !clockifyStore) return;
        full._setStatus(i18n("Copiando Jira → Clockify…"), false);
        // Don't auto-clear while the sync is in flight.
        _clearStatusTimer.stop();
        var projectForSync = full.syncProjectId || "";
        var defaultBillable = plasmoid.configuration.clockifyBillableDefault !== false;
        clockifyStore.syncFromJira(jiraStore.worklogs, projectForSync, defaultBillable,
            function(created, skipped, failed) {
                full._setStatus(
                    i18n("Sync terminado: %1 creadas, %2 ya existían, %3 fallaron.",
                         created, skipped, failed),
                    failed > 0);
                if (clockifyStore) clockifyStore.fetchWeek(full.currentWeekStart);
            });
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: PlasmaCore.Units.smallSpacing
        spacing: PlasmaCore.Units.smallSpacing

        // -------- Header --------
        RowLayout {
            Layout.fillWidth: true
            spacing: PlasmaCore.Units.smallSpacing

            PlasmaCore.IconItem {
                source: "view-calendar-week"
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
            }
            PlasmaComponents3.Label {
                text: {
                    if (full.source === "clockify") return i18n("Clockify");
                    if (full.source === "jira-clockify") return i18n("Jira / Clockify");
                    return i18n("Jira Worklog");
                }
                font.bold: true
            }

            PlasmaComponents3.ToolButton {
                icon.name: "go-previous"
                onClicked: {
                    var d = new Date(full.currentWeekStart.getTime());
                    d.setDate(d.getDate() - 7);
                    full.currentWeekStart = d;
                    full.syncNow();
                }
            }
            PlasmaComponents3.Button {
                text: i18n("Hoy")
                onClicked: {
                    full.currentWeekStart = full._sundayOf(new Date());
                    full.syncNow();
                }
            }
            PlasmaComponents3.ToolButton {
                icon.name: "go-next"
                onClicked: {
                    var d = new Date(full.currentWeekStart.getTime());
                    d.setDate(d.getDate() + 7);
                    full.currentWeekStart = d;
                    full.syncNow();
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: full._formatWeekLabel(full.currentWeekStart)
                font.bold: true
            }

            PlasmaComponents3.Button {
                text: plasmoid.configuration.worklogViewMode === "9h" ? i18n("Modo 9h") : i18n("Modo 24h")
                onClicked: {
                    plasmoid.configuration.worklogViewMode =
                        plasmoid.configuration.worklogViewMode === "9h" ? "24h" : "9h";
                }
                PlasmaComponents3.ToolTip.text: i18n("Cambiar entre vista 09:00–18:00 y 00:00–24:00")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh"
                enabled: (!jiraStore || !jiraStore.loading) && (!clockifyStore || !clockifyStore.loading)
                onClicked: full.syncNow()
                PlasmaComponents3.ToolTip.text: i18n("Sincronizar")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
            PlasmaComponents3.ToolButton {
                icon.name: "dialog-information"
                onClicked: debugOverlay.visible = true
                PlasmaComponents3.ToolTip.text: i18n("Ver diagnóstico")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
            // Pin button — keeps the popup open until toggled off.
            PlasmaComponents3.ToolButton {
                id: pinBtn
                icon.name: plasmoid.configuration.worklogPinned ? "window-pin" : "window-unpin"
                checkable: true
                checked: plasmoid.configuration.worklogPinned === true
                onClicked: {
                    plasmoid.configuration.worklogPinned = !plasmoid.configuration.worklogPinned;
                }
                PlasmaComponents3.ToolTip.text: plasmoid.configuration.worklogPinned
                                                ? i18n("Despinear (cerrar al perder foco)")
                                                : i18n("Pinear (mantener abierto)")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
        }

        // Status / errors. Pure binding — never assigned imperatively;
        // transient messages go through _setStatus() which writes
        // _statusOverride + restarts the auto-clear timer. The "no
        // message" state still returns a non-breaking space so the line
        // keeps its height and the calendar below doesn't jump up/down.
        PlasmaComponents3.Label {
            id: statusLabel
            Layout.fillWidth: true
            text: {
                if (full._statusOverride.length > 0) return full._statusOverride;
                if (jiraStore && jiraStore.loading) return i18n("Jira: cargando…");
                if (clockifyStore && clockifyStore.loading) return i18n("Clockify: cargando…");
                if (jiraStore && jiraStore.lastError.length > 0)
                    return i18n("Jira: %1", jiraStore.lastError);
                if (clockifyStore && clockifyStore.lastError.length > 0)
                    return i18n("Clockify: %1", clockifyStore.lastError);
                return " ";   // U+00A0 NO-BREAK SPACE: reserves vertical space.
            }
            color: {
                if (full._statusOverride.length > 0) return full._statusOverrideColor;
                if ((jiraStore && jiraStore.lastError.length > 0) ||
                    (clockifyStore && clockifyStore.lastError.length > 0)) {
                    return PlasmaCore.Theme.negativeTextColor;
                }
                return PlasmaCore.Theme.textColor;
            }
            opacity: text === " " ? 0 : 0.8
            font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
        }

        // -------- Calendar --------
        WorklogCalendar {
            id: cal
            Layout.fillWidth: true
            Layout.fillHeight: true
            jiraStore: full.jiraStore
            clockifyStore: full.clockifyStore
            weekStart: full.currentWeekStart
            source: full.source
            onCreateJiraRequested:     jiraEditDialog.openCreate(dayMs, startMs, endMs)
            onCreateClockifyRequested: clockifyEditDialog.openCreate(startMs, endMs)
            onEditJiraRequested:       jiraEditDialog.openEdit(entry)
            onEditClockifyRequested:   clockifyEditDialog.openEdit(entry)
            // One handler covers cross-day move, top resize and bottom
            // resize — all three end up as a Jira/Clockify update with
            // a new (start, duration) pair.
            onMoveJiraRequested: function(entry, newStartMs, newDurationSec) {
                if (!jiraStore) return;
                // _setStatus restarts the auto-clear timer; don't stop it
                // here — the message should fade naturally after 6 s while
                // the next status (loading / done) takes over via the
                // binding fallback.
                full._setStatus(i18n("Actualizando worklog Jira…"), false);
                jiraStore.updateWorklog(
                    entry.issueKey,
                    entry.id,
                    new Date(newStartMs),
                    newDurationSec,
                    undefined   // keep existing comment
                );
            }
            onMoveClockifyRequested: function(entry, newStartMs, newDurationSec) {
                if (!clockifyStore) return;
                full._setStatus(i18n("Actualizando entrada Clockify…"), false);
                var newStart = new Date(newStartMs);
                var newEnd   = new Date(newStartMs + newDurationSec * 1000);
                clockifyStore.updateEntry(
                    entry.id,
                    newStart, newEnd,
                    entry.description,
                    entry.projectId,
                    entry.tagIds,
                    entry.billable
                );
            }
            // Duplicate-button handlers — clone the entry verbatim
            // (same start, same duration, same comment/project/tags/etc).
            // The existing onCreateFinished Connections triggers a
            // refetch so the new block appears alongside the original.
            onDuplicateJiraRequested: function(entry) {
                if (!jiraStore) return;
                full._setStatus(i18n("Duplicando worklog Jira…"), false);
                jiraStore.createWorklog(
                    entry.issueKey,
                    new Date(entry.started),
                    entry.durationSec,
                    entry.comment || ""
                );
            }
            onDuplicateClockifyRequested: function(entry) {
                if (!clockifyStore) return;
                full._setStatus(i18n("Duplicando entrada Clockify…"), false);
                clockifyStore.createEntry(
                    new Date(entry.started),
                    new Date(entry.started + entry.durationSec * 1000),
                    entry.description || "",
                    entry.projectId || "",
                    entry.tagIds || [],
                    entry.billable === true
                );
            }
        }

        // Central refetch trigger. Any successful mutation (drag-move,
        // modal create/save/delete) lands here and bumps a single
        // fetchWeek. On failure we surface the error in the status line.
        Connections {
            target: jiraStore
            function onUpdateFinished(ok, err) {
                if (ok) full.syncNow();
                else    full._setStatus(i18n("Jira: no se pudo guardar — %1", err), true);
            }
            function onCreateFinished(ok, err) {
                if (ok) full.syncNow();
                else    full._setStatus(i18n("Jira: no se pudo crear — %1", err), true);
            }
            function onDeleteFinished(ok, err) {
                if (ok) full.syncNow();
                else    full._setStatus(i18n("Jira: no se pudo borrar — %1", err), true);
            }
        }
        Connections {
            target: clockifyStore
            function onUpdateFinished(ok, err) {
                if (ok) full.syncNow();
                else    full._setStatus(i18n("Clockify: no se pudo guardar — %1", err), true);
            }
            function onCreateFinished(ok, err) {
                if (ok) full.syncNow();
                else    full._setStatus(i18n("Clockify: no se pudo crear — %1", err), true);
            }
            function onDeleteFinished(ok, err) {
                if (ok) full.syncNow();
                else    full._setStatus(i18n("Clockify: no se pudo borrar — %1", err), true);
            }
        }

        // -------- Bottom panel: rings ⟷ heatmap, with a vertical switch --
        RowLayout {
            Layout.fillWidth: true
            visible: full._showBottomPanel
            spacing: PlasmaCore.Units.smallSpacing

            // Content area — both views exist; only the selected one shows.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(
                    full._bottomIsRings ? sprintGauges.implicitHeight : 0,
                    full._bottomIsHeatmap ? monthHeatmap.implicitHeight : 0)

                SprintGauges {
                    id: sprintGauges
                    anchors.fill: parent
                    visible: full._bottomIsRings
                    jiraStore: full.jiraStore
                }
                MonthHeatmap {
                    id: monthHeatmap
                    anchors.fill: parent
                    visible: full._bottomIsHeatmap
                    clockifyStore: full.clockifyStore
                    jiraStore: full.jiraStore
                }
            }

            // Vertical switch: two stacked icon buttons (rings / heatmap).
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                PlasmaComponents3.ToolButton {
                    icon.name: "office-chart-ring"
                    checkable: true
                    checked: full._bottomIsRings
                    onClicked: {
                        plasmoid.configuration.worklogBottomView = "rings";
                        if (jiraStore) jiraStore.fetchSprintInfo();
                        sprintGauges.startFillAnimation();
                    }
                    PlasmaComponents3.ToolTip.text: i18n("Ver anillos (Sprint / Horas)")
                    PlasmaComponents3.ToolTip.visible: hovered
                    PlasmaComponents3.ToolTip.delay: 500
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "view-calendar-month"
                    checkable: true
                    checked: full._bottomIsHeatmap
                    onClicked: {
                        plasmoid.configuration.worklogBottomView = "heatmap";
                        monthHeatmap.refresh();
                    }
                    PlasmaComponents3.ToolTip.text: i18n("Ver heatmap mensual")
                    PlasmaComponents3.ToolTip.visible: hovered
                    PlasmaComponents3.ToolTip.delay: 500
                }
            }
        }

        // -------- Footer --------
        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: {
                    var parts = [];
                    if (full._showJira && jiraStore) {
                        var jt = 0;
                        for (var i = 0; i < jiraStore.worklogs.length; i++) jt += jiraStore.worklogs[i].durationSec;
                        parts.push(i18n("Jira: %1h %2m", Math.floor(jt/3600), Math.floor((jt%3600)/60)));
                    }
                    if (full._showClockify && clockifyStore) {
                        var ct = 0;
                        for (var j = 0; j < clockifyStore.entries.length; j++) ct += clockifyStore.entries[j].durationSec;
                        parts.push(i18n("Clockify: %1h %2m", Math.floor(ct/3600), Math.floor((ct%3600)/60)));
                    }
                    return parts.join("  ·  ");
                }
                opacity: 0.7
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            }

            // Combined-mode-only: project picker for the sync.
            // Color swatch + ComboBox showing every Clockify project. The
            // default selection is mirrored from plasmoid.configuration
            // .clockifyDefaultProjectId via the Connections block above,
            // and changes here persist back to that same kcfg key.
            Rectangle {
                visible: full._isCombined
                Layout.preferredWidth: 12
                Layout.preferredHeight: 12
                radius: 2
                color: {
                    if (!clockifyStore) return "transparent";
                    for (var i = 0; i < clockifyStore.projects.length; i++) {
                        if (clockifyStore.projects[i].id === full.syncProjectId
                            && clockifyStore.projects[i].color)
                            return clockifyStore.projects[i].color;
                    }
                    return "transparent";
                }
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.3)
                Layout.alignment: Qt.AlignVCenter
            }
            QQC2.ComboBox {
                id: syncProjectCombo
                visible: full._isCombined
                Layout.preferredWidth: 200
                textRole: "name"
                valueRole: "id"
                model: {
                    var head = [{ id: "", name: i18n("(sin proyecto)"), color: "" }];
                    return (clockifyStore && clockifyStore.projects.length > 0)
                           ? head.concat(clockifyStore.projects)
                           : head;
                }
                currentIndex: {
                    var arr = syncProjectCombo.model || [];
                    for (var i = 0; i < arr.length; i++) {
                        if (arr[i].id === full.syncProjectId) return i;
                    }
                    return 0;
                }
                onActivated: function(idx) {
                    full.syncProjectId = syncProjectCombo.model[idx].id;
                    // Persist so the choice survives the next popup open.
                    plasmoid.configuration.clockifyDefaultProjectId = full.syncProjectId;
                }
                PlasmaComponents3.ToolTip.text: i18n("Proyecto destino del sync Jira → Clockify")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }

            // Combined-mode-only: copy Jira worklogs into Clockify entries.
            PlasmaComponents3.Button {
                visible: full._isCombined
                text: i18n("Jira → Clockify")
                icon.name: "edit-copy"
                onClicked: full.syncJiraIntoClockify()
                PlasmaComponents3.ToolTip.text: i18n("Crea una entrada Clockify por cada worklog de Jira " +
                                                     "que aún no tenga su réplica (descripción = CP-XXX: título).")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }

            // Mode hamburger — uses a Popup with RadioButtons (real circles)
            // and a ButtonGroup so the selection is always exclusive and
            // can't be cleared by clicking the active one.
            PlasmaComponents3.ToolButton {
                id: modeBtn
                icon.name: "application-menu"
                onClicked: modePopup.open()
                PlasmaComponents3.ToolTip.text: i18n("Cambiar fuente de worklog")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500

                QQC2.Popup {
                    id: modePopup
                    parent: modeBtn
                    y: -implicitHeight - 4
                    padding: 10
                    modal: true
                    focus: true
                    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutsideParent

                    QQC2.ButtonGroup { id: sourceGroup }

                    contentItem: ColumnLayout {
                        spacing: 4
                        QQC2.RadioButton {
                            QQC2.ButtonGroup.group: sourceGroup
                            text: i18n("Jira")
                            checked: full.source === "jira"
                            onClicked: if (checked && full.source !== "jira") {
                                plasmoid.configuration.worklogSource = "jira";
                                full.syncNow();
                                modePopup.close();
                            }
                        }
                        QQC2.RadioButton {
                            QQC2.ButtonGroup.group: sourceGroup
                            text: i18n("Jira / Clockify")
                            checked: full.source === "jira-clockify"
                            onClicked: if (checked && full.source !== "jira-clockify") {
                                plasmoid.configuration.worklogSource = "jira-clockify";
                                full.syncNow();
                                modePopup.close();
                            }
                        }
                        QQC2.RadioButton {
                            QQC2.ButtonGroup.group: sourceGroup
                            text: i18n("Clockify")
                            checked: full.source === "clockify"
                            onClicked: if (checked && full.source !== "clockify") {
                                plasmoid.configuration.worklogSource = "clockify";
                                full.syncNow();
                                modePopup.close();
                            }
                        }
                    }
                }
            }

            PlasmaComponents3.ToolButton {
                icon.name: "configure"
                text: i18n("Configurar…")
                onClicked: plasmoid.action("configure").trigger()
            }
        }
    }

    // -------- Modals --------
    // Refetch is driven by the store-level Connections above (which cover
    // both modal saves and drag-to-move) so we don't double-fire it.
    WorklogEditDialog {
        id: jiraEditDialog
        store: full.jiraStore
        anchors.fill: parent
    }
    ClockifyEditDialog {
        id: clockifyEditDialog
        store: full.clockifyStore
        anchors.fill: parent
    }

    // -------- Debug overlay --------
    Item {
        id: debugOverlay
        anchors.fill: parent
        visible: false
        z: 900

        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.5
            MouseArea { anchors.fill: parent; onClicked: debugOverlay.visible = false }
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.max(400, parent.width - 16)
            height: Math.max(300, parent.height - 30)
            color: PlasmaCore.Theme.backgroundColor
            border.color: PlasmaCore.Theme.textColor
            border.width: 1
            radius: 4

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: PlasmaCore.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: i18n("Diagnóstico (Jira + Clockify)")
                        font.bold: true
                    }
                    PlasmaComponents3.ToolButton {
                        icon.name: "edit-clear-all"
                        text: i18n("Limpiar")
                        onClicked: {
                            if (jiraStore && jiraStore.hasDebugLog) jiraStore.clearDebugLog();
                            if (clockifyStore && clockifyStore.hasDebugLog) clockifyStore.clearDebugLog();
                        }
                    }
                    PlasmaComponents3.ToolButton {
                        icon.name: "window-close"
                        onClicked: debugOverlay.visible = false
                    }
                }

                QQC2.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    QQC2.TextArea {
                        id: logArea
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.WrapAnywhere
                        font.family: "monospace"
                        font.pixelSize: 11
                        text: {
                            var j = (jiraStore && jiraStore.hasDebugLog) ? jiraStore.lastDebugLog : "";
                            var c = (clockifyStore && clockifyStore.hasDebugLog) ? clockifyStore.lastDebugLog : "";
                            var _ = (full._vJira, full._vClockify);
                            if (!j && !c) return i18n("Sin datos. Pulsá ↻ para sincronizar.");
                            return "---- JIRA ----\n" + (j || "(vacío)") +
                                   "\n\n---- CLOCKIFY ----\n" + (c || "(vacío)");
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        if (jiraStore && jiraStore.lastFetchedAt === 0 && _showJira) jiraStore.fetchWeek(currentWeekStart);
        if (clockifyStore && clockifyStore.lastFetchedAt === 0 && _showClockify) clockifyStore.fetchWeek(currentWeekStart);
        if (_showBottomPanel && _bottomIsRings && jiraStore) {
            jiraStore.fetchSprintInfo();
            sprintGauges.startFillAnimation();
        }
        if (_showBottomPanel && _bottomIsHeatmap) monthHeatmap.refresh();
    }

    // Re-trigger the fill animation every time the popup re-opens (Plasma
    // reuses the same FullRepresentation instance so Component.onCompleted
    // only fires once on first open). Also re-fetch the visible bottom view.
    Connections {
        target: plasmoid
        function onExpandedChanged() {
            if (!plasmoid.expanded) return;
            if (!full._showBottomPanel) return;
            if (full._bottomIsRings) {
                sprintGauges.startFillAnimation();
                if (jiraStore) jiraStore.fetchSprintInfo();
            } else {
                monthHeatmap.refresh();
            }
        }
    }

    // Refetch sprint info when the user toggles experimental Sprint config
    // — strategy / field / board / remaining mode — so the gauges update
    // without a manual sync click.
    Connections {
        target: plasmoid.configuration
        function _refetchRings() {
            if (full._showBottomPanel && full._bottomIsRings && jiraStore)
                jiraStore.fetchSprintInfo();
        }
        function onWorklogSprintStrategyChanged() { _refetchRings(); }
        function onWorklogSprintFieldChanged()    { _refetchRings(); }
        function onWorklogSprintBoardIdChanged()  { _refetchRings(); }
        function onWorklogRemainingModeChanged()  { _refetchRings(); }
    }
}
