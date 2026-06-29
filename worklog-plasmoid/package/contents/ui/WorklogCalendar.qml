/*
 * WorklogCalendar.qml - the actual week grid.
 *
 * Receives both stores (jiraStore + clockifyStore) and a `source` mode
 * ("jira" | "clockify" | "jira-clockify"). It renders the appropriate
 * entries and, in the combined mode, splits each day column into a
 * left (Jira) and right (Clockify) half.
 *
 * Drag-to-create works for both sides: in the combined mode, the press
 * X coordinate decides whether to emit createJiraRequested or
 * createClockifyRequested.
 *
 * Each row = 30 min. View mode ("9h" / "24h") comes from the kcfg
 * setting.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: cal

    property var jiraStore
    property var clockifyStore
    property var googleStore
    property date weekStart: new Date()
    property string source: "jira"   // "jira" | "clockify" | "jira-clockify"

    signal createJiraRequested(real dayMs, real startMs, real endMs)
    signal createClockifyRequested(real dayMs, real startMs, real endMs)
    signal editJiraRequested(var entry)
    signal editClockifyRequested(var entry)
    // Unified change signals — used for cross-day moves, top-edge resizes
    // (changes both start and duration) and bottom-edge resizes (duration
    // only). The store layer doesn't care which gesture produced them.
    signal moveJiraRequested(var entry, real newStartMs, int newDurationSec)
    signal moveClockifyRequested(var entry, real newStartMs, int newDurationSec)
    signal duplicateJiraRequested(var entry)
    signal duplicateClockifyRequested(var entry)

    function _emitChange(entry, newStartMs, newDurationSec, isJira) {
        // Clamp to the visible week so a wild drag can't log on day -1
        // or day 8. Per-day clamp is intentionally skipped — entries that
        // span midnight are legal in both Jira and Clockify.
        var wsMs = weekStart.getTime();
        var weMs = wsMs + 7 * 86400000;
        var durMs = newDurationSec * 1000;
        if (newStartMs < wsMs)         newStartMs = wsMs;
        if (newStartMs + durMs > weMs) newStartMs = weMs - durMs;
        if (newDurationSec < 600)      newDurationSec = 600;   // 10-min floor
        if (newStartMs === entry.started && newDurationSec === entry.durationSec) return;
        if (isJira) moveJiraRequested(entry, newStartMs, newDurationSec);
        else        moveClockifyRequested(entry, newStartMs, newDurationSec);
    }

    // px → snapped minutes. `fine` (Shift) snaps to 10 min, else 30.
    function _pxToSnappedMin(px, fine) {
        var g = fine ? 10 : 30;
        var rawMin = (px / cal.rowHeight) * 30;
        return Math.round(rawMin / g) * g;
    }

    function _handleMove(entry, deltaX, deltaY, currentDayWidth, isJira, fine) {
        var stepMin = _pxToSnappedMin(deltaY, fine);
        var days    = currentDayWidth > 0 ? Math.round(deltaX / currentDayWidth) : 0;
        if (stepMin === 0 && days === 0) return;
        var newStart = entry.started + days * 86400000 + stepMin * 60000;
        _emitChange(entry, newStart, entry.durationSec, isJira);
    }
    function _handleResizeTop(entry, deltaY, isJira, fine) {
        var stepMin = _pxToSnappedMin(deltaY, fine);
        if (stepMin === 0) return;
        // deltaY positive → started later, duration shrinks by same.
        var newStart = entry.started + stepMin * 60000;
        var newDur   = entry.durationSec - stepMin * 60;
        _emitChange(entry, newStart, newDur, isJira);
    }
    function _handleResizeBottom(entry, deltaH, isJira, fine) {
        var stepMin = _pxToSnappedMin(deltaH, fine);
        if (stepMin === 0) return;
        var newDur = entry.durationSec + stepMin * 60;
        _emitChange(entry, entry.started, newDur, isJira);
    }

    readonly property bool _isCombined: source === "jira-clockify"
    readonly property bool _showJira:   source === "jira" || source === "jira-clockify"
    readonly property bool _showClockify: source === "clockify" || source === "jira-clockify"

    readonly property string viewMode: plasmoid.configuration.worklogViewMode || "9h"
    readonly property int startHour: viewMode === "24h" ? 0 : 9
    readonly property int endHour:   viewMode === "24h" ? 24 : 18
    readonly property int slotsPerDay: (endHour - startHour) * 2
    readonly property real rowHeight: 22
    readonly property real hourColWidth: 56
    readonly property real headerRowHeight: 22
    readonly property real totalsRowHeight: 22
    readonly property real dailyTargetHours: plasmoid.configuration.worklogDailyTargetHours || 8

    readonly property int _vJira: jiraStore ? jiraStore.version : 0
    readonly property int _vClockify: clockifyStore ? clockifyStore.version : 0
    readonly property int _vGoogle: googleStore ? googleStore.version : 0

    // Google Calendar event blocks — immovable, non-interactive, drawn
    // behind the Jira/Clockify entries. Shown only when the toggle is on.
    readonly property bool _showGoogle:
        plasmoid.configuration.googleCalEnabled === true && !!googleStore

    // calendarId → base color (hex). Re-evaluates when the config lists
    // change so color edits apply live without a refetch. Missing ids
    // fall back to the translucent red we've always used.
    readonly property string _googleDefaultColor: "#e74c3c"
    readonly property var _googleColorMap: {
        var m = {};
        var ids = plasmoid.configuration.googleCalendarIds || [];
        var cols = plasmoid.configuration.googleCalendarColors || [];
        for (var i = 0; i < ids.length; i++) {
            var id = ("" + (ids[i] || "")).trim();
            if (id) m[id] = ("" + (cols[i] || "")).trim() || cal._googleDefaultColor;
        }
        return m;
    }
    function _googleBase(calId) {
        var c = _googleColorMap[calId];
        return (c && c.length > 0) ? c : _googleDefaultColor;
    }
    // Always render the chosen color translucent (per the spec).
    function _translucent(base, a) {
        var c = (base && base.length > 0) ? Qt.color(base) : Qt.color(cal._googleDefaultColor);
        return Qt.rgba(c.r, c.g, c.b, a);
    }
    // A Google block is "covered" if any Jira/Clockify entry shown on the
    // same day overlaps it in time — used to hide its label so the text
    // doesn't bleed through the worklog block on top (the translucent
    // block itself stays).
    function _googleCovered(ev, dayIdx) {
        var s = ev.started, e = ev.started + ev.durationSec * 1000;
        var lists = [];
        if (_showJira)     lists.push(_jiraByDay[dayIdx] || []);
        if (_showClockify) lists.push(_clockifyByDay[dayIdx] || []);
        for (var l = 0; l < lists.length; l++) {
            var arr = lists[l];
            for (var i = 0; i < arr.length; i++) {
                var a = arr[i];
                var aEnd = a.started + a.durationSec * 1000;
                if (s < aEnd && a.started < e) return true;
            }
        }
        return false;
    }

    // Buckets per day for both sources.
    property var _jiraByDay:     cal._rebuild(_vJira,     weekStart, jiraStore ? jiraStore.worklogs : [])
    property var _clockifyByDay: cal._rebuild(_vClockify, weekStart, clockifyStore ? clockifyStore.entries : [])
    property var _googleByDay:   cal._rebuild(_vGoogle,   weekStart, googleStore ? googleStore.events : [])

    // Per-source overlap maps {entryId: true}. Two entries on the same
    // day overlap if their [started, started+duration) intervals share
    // any millisecond. Touching ranges (one ends exactly when the next
    // starts) do NOT count. Recomputed on every store version bump via
    // the same `_v…` dependencies that drive `_byDay`.
    readonly property var _jiraOverlapMap:     cal._computeOverlaps(_vJira,     _jiraByDay)
    readonly property var _clockifyOverlapMap: cal._computeOverlaps(_vClockify, _clockifyByDay)

    function _rebuild(_unusedV, _unusedWs, list) {
        var out = [[], [], [], [], [], [], []];
        if (!list) return out;
        var startMs = weekStart.getTime();
        for (var i = 0; i < list.length; i++) {
            var w = list[i];
            var dayIdx = Math.floor((w.started - startMs) / 86400000);
            if (dayIdx >= 0 && dayIdx < 7) out[dayIdx].push(w);
        }
        return out;
    }

    function _computeOverlaps(_unusedV, byDay) {
        var ids = {};
        if (!byDay) return ids;
        for (var d = 0; d < 7; d++) {
            var arr = byDay[d] || [];
            for (var i = 0; i < arr.length; i++) {
                var a = arr[i];
                var aEnd = a.started + a.durationSec * 1000;
                for (var j = i + 1; j < arr.length; j++) {
                    var b = arr[j];
                    var bEnd = b.started + b.durationSec * 1000;
                    if (a.started < bEnd && b.started < aEnd) {
                        ids[a.id] = true;
                        ids[b.id] = true;
                    }
                }
            }
        }
        return ids;
    }

    function _dayMs(idx) { return weekStart.getTime() + idx * 86400000; }

    function _isToday(idx) {
        var d = new Date(_dayMs(idx));
        var t = new Date();
        return d.getFullYear() === t.getFullYear() &&
               d.getMonth()    === t.getMonth() &&
               d.getDate()     === t.getDate();
    }
    // weekStart is Sunday → index 0 = Sun, 6 = Sat.
    function _isWeekend(idx) { return idx === 0 || idx === 6; }

    function _formatDayHeader(idx) {
        var d = new Date(_dayMs(idx));
        var names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        return names[idx] + ", " + d.getDate() + "/" + _shortMonth(d.getMonth());
    }
    function _shortMonth(m) {
        return ["Ene","Feb","Mar","Abr","May","Jun","Jul","Ago","Sep","Oct","Nov","Dic"][m];
    }

    function _totalSecForDay(idx) {
        // Total prefers Jira when shown (closest to "what was logged for billing").
        var arr = (_showJira ? _jiraByDay[idx] : _clockifyByDay[idx]) || [];
        var s = 0;
        for (var i = 0; i < arr.length; i++) s += arr[i].durationSec;
        return s;
    }
    function _formatTotal(sec) {
        if (sec <= 0) return "—";
        var h = Math.floor(sec / 3600);
        var m = Math.floor((sec % 3600) / 60);
        if (h > 0 && m > 0) return h + "h " + m + "m";
        if (h > 0)          return h + "h";
        return m + "m";
    }
    function _formatDiff(sec) {
        var target = dailyTargetHours * 3600;
        var diff = sec - target;
        if (diff === 0) return "";
        var sign = diff > 0 ? "+" : "-";
        var abs = Math.abs(diff);
        var h = Math.floor(abs / 3600);
        var m = Math.floor((abs % 3600) / 60);
        var s = sign + (h > 0 ? h + "h" : "") + (m > 0 ? (h > 0 ? " " : "") + m + "m" : "");
        return "(" + s + ")";
    }

    function _slotLabel(slot) {
        var minutes = (startHour * 60) + slot * 30;
        var h = Math.floor(minutes / 60);
        var m = minutes % 60;
        return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
    }
    function _fmtClock(ms) {
        var d = new Date(ms);
        function p(n) { return n < 10 ? "0" + n : "" + n; }
        return p(d.getHours()) + ":" + p(d.getMinutes());
    }
    function _msAtSlot(dayIdx, slot) {
        return _dayMs(dayIdx) + (startHour * 3600 + slot * 1800) * 1000;
    }
    function _slotOfMs(ms, dayIdx) {
        var dayStart = _dayMs(dayIdx);
        var localMs = ms - dayStart;
        var slotsFromMidnight = Math.floor(localMs / (30 * 60 * 1000));
        return slotsFromMidnight - startHour * 2;
    }
    // Minute-precise positioning so 10-min blocks render at their real
    // size (1 row = 30 min = rowHeight).
    function _yForEntry(entry, dayIdx) {
        var dayStart = _dayMs(dayIdx);
        var minFromViewStart = (entry.started - dayStart) / 60000 - startHour * 60;
        return (minFromViewStart / 30) * rowHeight;
    }
    function _heightForEntry(entry) {
        var h = (entry.durationSec / 1800) * rowHeight;   // 1800s = 30min = rowHeight
        return Math.max(rowHeight / 3, h);                 // floor ≈ 10-min visual
    }

    QQC2.ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true

        GridLayout {
            width: scroll.availableWidth
            columns: 8
            rowSpacing: 0
            columnSpacing: 0

            // Corner (top-left).
            Rectangle {
                Layout.preferredWidth: cal.hourColWidth
                Layout.preferredHeight: cal.headerRowHeight + cal.totalsRowHeight
                color: PlasmaCore.Theme.backgroundColor
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                PlasmaComponents3.Label {
                    anchors.centerIn: parent
                    text: "total"
                    font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                    opacity: 0.6
                }
            }

            // Day header + totals row per day.
            Repeater {
                model: 7
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: cal.headerRowHeight + cal.totalsRowHeight
                    Column {
                        anchors.fill: parent
                        Rectangle {
                            width: parent.width
                            height: cal.headerRowHeight
                            color: cal._isToday(index)
                                   ? Qt.rgba(PlasmaCore.Theme.highlightColor.r,
                                             PlasmaCore.Theme.highlightColor.g,
                                             PlasmaCore.Theme.highlightColor.b, 0.22)
                                   : cal._isWeekend(index)
                                       ? Qt.rgba(0, 0, 0, 0.18)
                                       : Qt.rgba(1, 1, 1, 0.04)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.1)
                            PlasmaComponents3.Label {
                                anchors.centerIn: parent
                                text: cal._formatDayHeader(index)
                                font.bold: true
                                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                            }
                        }
                        Rectangle {
                            width: parent.width
                            height: cal.totalsRowHeight
                            color: {
                                var s = (cal._vJira, cal._vClockify, cal._totalSecForDay(index));
                                if (s <= 0) return Qt.rgba(1, 1, 1, 0.02);
                                var t = cal.dailyTargetHours * 3600;
                                return s >= t ? Qt.rgba(46/255, 204/255, 113/255, 0.18)
                                              : Qt.rgba(241/255, 196/255, 15/255, 0.18);
                            }
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.1)
                            PlasmaComponents3.Label {
                                anchors.centerIn: parent
                                text: {
                                    var s = (cal._vJira, cal._vClockify, cal._totalSecForDay(index));
                                    if (s <= 0) return i18n("—");
                                    return i18n("Logged: %1 %2",
                                                cal._formatTotal(s), cal._formatDiff(s));
                                }
                                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                            }
                        }
                    }
                }
            }

            // Hour-label column (row 2, col 0).
            Item {
                Layout.preferredWidth: cal.hourColWidth
                Layout.preferredHeight: cal.slotsPerDay * cal.rowHeight
                Column {
                    anchors.fill: parent
                    Repeater {
                        model: cal.slotsPerDay
                        Rectangle {
                            width: parent.width
                            height: cal.rowHeight
                            color: index % 2 === 0 ? Qt.rgba(1,1,1,0.02) : "transparent"
                            PlasmaComponents3.Label {
                                anchors.right: parent.right
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                text: cal._slotLabel(index)
                                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                                opacity: index % 2 === 0 ? 0.85 : 0.45
                            }
                        }
                    }
                }
            }

            // 7 day columns.
            Repeater {
                model: 7

                Item {
                    id: dayCol
                    Layout.fillWidth: true
                    Layout.preferredHeight: cal.slotsPerDay * cal.rowHeight
                    property int dayIndex: index

                    // Weekend tint — Sat/Sun get a slight darken so they
                    // stand out from weekdays. Drawn before the today
                    // overlay so both can stack on a Saturday-that-is-
                    // today.
                    Rectangle {
                        visible: cal._isWeekend(dayCol.dayIndex)
                        anchors.fill: parent
                        color: Qt.rgba(0, 0, 0, 0.18)
                    }
                    // Today-column tint sits underneath the slot grid so
                    // the alternating-row pattern still shows through.
                    Rectangle {
                        visible: cal._isToday(dayCol.dayIndex)
                        anchors.fill: parent
                        color: Qt.rgba(PlasmaCore.Theme.highlightColor.r,
                                       PlasmaCore.Theme.highlightColor.g,
                                       PlasmaCore.Theme.highlightColor.b, 0.10)
                    }

                    // Background grid.
                    Column {
                        anchors.fill: parent
                        Repeater {
                            model: cal.slotsPerDay
                            Rectangle {
                                width: parent.width
                                height: cal.rowHeight
                                color: index % 2 === 0 ? Qt.rgba(1,1,1,0.03) : Qt.rgba(1,1,1,0.0)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.06)
                            }
                        }
                    }

                    // Google Calendar event blocks. Declared before the
                    // drag overlay + the Jira/Clockify entry Repeaters, so
                    // they sit BEHIND everything: the drag-to-create input
                    // (dragMouse) lands on top of them, and any Jira/Clockify
                    // block covers them. They carry no MouseArea, so they're
                    // immovable and can't be selected. In combined mode the
                    // block spans the FULL column width (both halves) as one.
                    Repeater {
                        model: cal._showGoogle ? (cal._vGoogle, cal._googleByDay[dayCol.dayIndex] || []) : []
                        delegate: Rectangle {
                            readonly property string _base: cal._googleBase(modelData.calendarId)
                            x: 2
                            y: cal._yForEntry(modelData, dayCol.dayIndex)
                            width: dayCol.width - 4
                            height: cal._heightForEntry(modelData)
                            radius: 3
                            color: cal._translucent(_base, 0.18)
                            border.color: cal._translucent(_base, 0.45)
                            border.width: 1
                            PlasmaComponents3.Label {
                                anchors.fill: parent
                                anchors.margins: 3
                                text: modelData.summary || ""
                                color: "white"
                                opacity: 0.85
                                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                verticalAlignment: Text.AlignTop
                                // Hide the text when a Jira/Clockify block sits
                                // on top, so the letters don't overlap; the
                                // translucent block behind stays visible.
                                visible: (cal._vJira, cal._vClockify,
                                          !cal._googleCovered(modelData, dayCol.dayIndex))
                            }
                        }
                    }

                    // Vertical mid-divider for combined mode.
                    Rectangle {
                        visible: cal._isCombined
                        x: dayCol.width / 2 - 0.5
                        y: 0
                        width: 1
                        height: dayCol.height
                        color: Qt.rgba(1, 1, 1, 0.12)
                    }

                    // Drag selection overlay.
                    Rectangle {
                        id: dragSel
                        visible: dragMouse.isDragging
                        x: dragMouse._snapX()
                        y: dragMouse._snappedTop
                        width: dragMouse._snapWidth()
                        height: Math.max(cal.rowHeight, dragMouse._snappedBottom - dragMouse._snappedTop)
                        color: Qt.rgba(PlasmaCore.Theme.highlightColor.r,
                                       PlasmaCore.Theme.highlightColor.g,
                                       PlasmaCore.Theme.highlightColor.b, 0.30)
                        border.color: PlasmaCore.Theme.highlightColor
                        border.width: 1

                        // Live time-range readout, centered, on a dark pill
                        // so it's readable over any theme highlight color.
                        // Updates as the drag grows/shrinks.
                        Rectangle {
                            anchors.centerIn: parent
                            width: dragLabel.implicitWidth + 8
                            height: dragLabel.implicitHeight + 4
                            radius: 3
                            color: Qt.rgba(0, 0, 0, 0.6)
                            PlasmaComponents3.Label {
                                id: dragLabel
                                anchors.centerIn: parent
                                text: cal._fmtClock(dragMouse._pxToMs(dragMouse._snappedTop)) + " - " +
                                      cal._fmtClock(dragMouse._pxToMs(dragMouse._snappedBottom))
                                color: "white"
                                font.bold: true
                                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                            }
                        }
                    }

                    MouseArea {
                        id: dragMouse
                        anchors.fill: parent
                        hoverEnabled: false
                        preventStealing: true
                        property bool isDragging: false
                        property bool _pressLeft: true   // for combined: which half started the drag
                        property bool _fine: false       // Shift held → 10-min granularity
                        property real _pressY: 0
                        property real _curY: 0
                        property real _snappedTop: 0
                        property real _snappedBottom: 0

                        // Snap a pixel offset to a 30-min row or, with Shift,
                        // a 10-min third of a row — returned in pixels.
                        function _stepPx() { return _fine ? cal.rowHeight / 3 : cal.rowHeight; }
                        function _snap(y) {
                            var step = _stepPx();
                            var maxPx = cal.slotsPerDay * cal.rowHeight;
                            return Math.max(0, Math.min(maxPx, Math.round(y / step) * step));
                        }
                        function _snapX() {
                            if (!cal._isCombined) return 0;
                            return _pressLeft ? 0 : dayCol.width / 2;
                        }
                        function _snapWidth() {
                            return cal._isCombined ? dayCol.width / 2 : dayCol.width;
                        }
                        // Pixel offset within the day → absolute ms.
                        function _pxToMs(px) {
                            var minFromStart = (px / cal.rowHeight) * 30;
                            return cal._dayMs(dayCol.dayIndex) + (cal.startHour * 60 + minFromStart) * 60000;
                        }

                        onPressed: function(mouse) {
                            _pressLeft = cal._isCombined ? (mouse.x < dayCol.width / 2) : true;
                            _fine = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                            _pressY = mouse.y;
                            _curY = mouse.y;
                            _snappedTop    = _snap(Math.min(_pressY, _curY));
                            _snappedBottom = _snap(Math.max(_pressY, _curY)) + _stepPx();
                            isDragging = true;
                        }
                        onPositionChanged: function(mouse) {
                            if (!isDragging) return;
                            _curY = mouse.y;
                            var lo = Math.min(_pressY, _curY);
                            var hi = Math.max(_pressY, _curY);
                            _snappedTop    = _snap(lo);
                            _snappedBottom = Math.max(_snappedTop + _stepPx(), _snap(hi) + _stepPx());
                        }
                        onReleased: function(mouse) {
                            if (!isDragging) return;
                            isDragging = false;
                            var startMs = _pxToMs(_snappedTop);
                            var endMs   = _pxToMs(_snappedBottom);
                            if (endMs <= startMs) endMs = startMs + (_fine ? 10 : 30) * 60 * 1000;

                            if (cal._isCombined) {
                                if (_pressLeft) cal.createJiraRequested(cal._dayMs(dayCol.dayIndex), startMs, endMs);
                                else            cal.createClockifyRequested(cal._dayMs(dayCol.dayIndex), startMs, endMs);
                            } else if (cal.source === "jira") {
                                cal.createJiraRequested(cal._dayMs(dayCol.dayIndex), startMs, endMs);
                            } else {
                                cal.createClockifyRequested(cal._dayMs(dayCol.dayIndex), startMs, endMs);
                            }
                        }
                    }

                    // Jira entries.
                    Repeater {
                        model: cal._showJira ? (cal._vJira, cal._jiraByDay[dayCol.dayIndex] || []) : []
                        delegate: WorklogEntry {
                            entry: modelData
                            kind: "jira"
                            compact: cal._isCombined
                            overlapping: !!(cal._jiraOverlapMap && cal._jiraOverlapMap[modelData.id])
                            x: cal._isCombined ? 2 : 2
                            y: cal._yForEntry(modelData, dayCol.dayIndex)
                            width: cal._isCombined ? (dayCol.width / 2) - 3 : dayCol.width - 4
                            height: cal._heightForEntry(modelData)
                            columnHeight: dayCol.height
                            columnWidth: dayCol.width
                            rowHeight: cal.rowHeight
                            onClicked: cal.editJiraRequested(entry)
                            onMoveRequested: function(dx, dy, fine) {
                                cal._handleMove(entry, dx, dy, dayCol.width, true, fine);
                            }
                            onResizeTopRequested:    function(dy, fine) { cal._handleResizeTop(entry, dy, true, fine); }
                            onResizeBottomRequested: function(dh, fine) { cal._handleResizeBottom(entry, dh, true, fine); }
                            onDuplicateRequested:    function() { cal.duplicateJiraRequested(entry); }
                        }
                    }

                    // Clockify entries.
                    Repeater {
                        model: cal._showClockify ? (cal._vClockify, cal._clockifyByDay[dayCol.dayIndex] || []) : []
                        delegate: WorklogEntry {
                            entry: modelData
                            kind: "clockify"
                            compact: cal._isCombined
                            overlapping: !!(cal._clockifyOverlapMap && cal._clockifyOverlapMap[modelData.id])
                            // pure clockify mode → use project color if available
                            useProjectColor: !cal._isCombined
                            x: cal._isCombined ? (dayCol.width / 2) + 1 : 2
                            y: cal._yForEntry(modelData, dayCol.dayIndex)
                            width: cal._isCombined ? (dayCol.width / 2) - 3 : dayCol.width - 4
                            height: cal._heightForEntry(modelData)
                            columnHeight: dayCol.height
                            columnWidth: dayCol.width
                            rowHeight: cal.rowHeight
                            onClicked: cal.editClockifyRequested(entry)
                            onMoveRequested: function(dx, dy, fine) {
                                cal._handleMove(entry, dx, dy, dayCol.width, false, fine);
                            }
                            onResizeTopRequested:    function(dy, fine) { cal._handleResizeTop(entry, dy, false, fine); }
                            onResizeBottomRequested: function(dh, fine) { cal._handleResizeBottom(entry, dh, false, fine); }
                            onDuplicateRequested:    function() { cal.duplicateClockifyRequested(entry); }
                        }
                    }
                }
            }
        }   // end GridLayout
    }       // end ScrollView
}
