/*
 * MonthHeatmap.qml - month-at-a-glance hours table, available in every mode
 * (toggled against the Sprint/Horas rings by the vertical switch in
 * FullRepresentation).
 *
 * Columns are uniform: the first is a row-icon column (Clockify / Jira),
 * the rest are one per day of the month. Rows:
 *   1: weekday letter (D L M Mi J V S) — gray on weekends
 *   2: day number — gray on weekends
 *   3: Clockify hours that day in decimal (3h30m → 3.5)
 *   4: Jira burned hours that day in decimal (always shown)
 * Colored cells grade gray(0)→red→yellow→green from 0 to 4h (green ≥4),
 * and lighten with a short fade on hover.
 *
 * Two views: current and last month (◀ / ▶). Per-day totals are tagged
 * with the month they belong to (clockifyKey / jiraKey); a cell only reads
 * a value when its month matches the visible one, so navigating months can
 * never show the previous month's numbers even if a response lands late.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: heat

    property var clockifyStore
    property var jiraStore
    property int monthOffset: 0   // 0 = current month, -1 = last month

    implicitHeight: col.implicitHeight

    // Fixed row heights so the left icon column lines up with the grid.
    readonly property int letterRowH: 13
    readonly property int numberRowH: 14
    readonly property int cellRowH: 18

    readonly property var _ref: {
        var d = new Date();
        d.setDate(1);
        d.setMonth(d.getMonth() + monthOffset);
        d.setHours(0, 0, 0, 0);
        return d;
    }
    readonly property int year: _ref.getFullYear()
    readonly property int month: _ref.getMonth()           // 0..11
    readonly property int daysInMonth: new Date(year, month + 1, 0).getDate()

    property var clockifyTotals: ({})   // { day: seconds }
    property var jiraTotals: ({})
    property string clockifyKey: ""     // "year-month" the data belongs to
    property string jiraKey: ""
    property int _v: 0                   // bumped when totals arrive
    property int _reqId: 0

    readonly property var _monthNames: ["Enero","Febrero","Marzo","Abril","Mayo","Junio",
                                        "Julio","Agosto","Septiembre","Octubre","Noviembre","Diciembre"]
    readonly property var _dowLetters: ["D","L","M","Mi","J","V","S"]

    function _curKey() { return year + "-" + month; }

    function refresh() {
        // Wipe immediately AND invalidate the keys so nothing from the old
        // month can render while the new fetch is in flight.
        clockifyTotals = {}; jiraTotals = {};
        clockifyKey = ""; jiraKey = "";
        _v++;
        var req = ++_reqId;
        var y = year, m = month;
        var key = y + "-" + m;
        if (clockifyStore && clockifyStore.fetchMonthTotals) {
            clockifyStore.fetchMonthTotals(y, m, function(ok, t) {
                if (!ok || req !== heat._reqId) return;
                heat.clockifyTotals = t; heat.clockifyKey = key; heat._v++;
            });
        }
        if (jiraStore && jiraStore.fetchMonthTotals) {
            jiraStore.fetchMonthTotals(y, m, function(ok, t) {
                if (!ok || req !== heat._reqId) return;
                heat.jiraTotals = t; heat.jiraKey = key; heat._v++;
            });
        }
    }
    onMonthOffsetChanged: refresh()
    Component.onCompleted: refresh()

    function _dow(day) { return new Date(year, month, day).getDay(); }
    function _isWeekend(day) { var d = _dow(day); return d === 0 || d === 6; }
    function _weekdayLetter(day) { return _dowLetters[_dow(day)]; }

    function _hoursDecimal(sec) {
        if (!sec || sec <= 0) return 0;
        return Math.round((sec / 3600) * 10) / 10;
    }
    // Month-guarded per-day lookups: only return a value if the loaded data
    // is for the currently visible month.
    function _clkHours(day) {
        if (clockifyKey !== _curKey()) return 0;
        return _hoursDecimal(clockifyTotals[day] || 0);
    }
    function _jiraHours(day) {
        if (jiraKey !== _curKey()) return 0;
        return _hoursDecimal(jiraTotals[day] || 0);
    }
    function _fmtNum(h) {
        if (h <= 0) return "";
        if (h === Math.floor(h)) return "" + h;
        return h.toFixed(1);
    }

    function _lerp(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t,
                       a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, 1);
    }
    function _cellColor(h) {
        if (h <= 0) return Qt.rgba(1, 1, 1, 0.06);
        var red    = Qt.rgba(231/255, 76/255,  60/255, 1);
        var yellow = Qt.rgba(241/255, 196/255, 15/255, 1);
        var green  = Qt.rgba(129/255, 199/255, 132/255, 1);
        var c = Math.min(4, h);
        if (c <= 2) return _lerp(red, yellow, c / 2);
        return _lerp(yellow, green, (c - 2) / 2);
    }
    function _cellTextColor(h) { return h > 0 ? "#1a1a1a" : PlasmaCore.Theme.textColor; }

    readonly property color _weekendColor: PlasmaCore.Theme.disabledTextColor

    component HoursCell: Rectangle {
        property real hours: 0
        Layout.fillWidth: true
        Layout.preferredHeight: heat.cellRowH
        radius: 2
        color: heat._cellColor(hours)
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.15)

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "white"
            opacity: cellMA.containsMouse ? 0.28 : 0.0
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
        }
        PlasmaComponents3.Label {
            anchors.centerIn: parent
            text: heat._fmtNum(parent.hours)
            color: heat._cellTextColor(parent.hours)
            font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            font.bold: true
        }
        MouseArea {
            id: cellMA
            anchors.fill: parent
            hoverEnabled: true
        }
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        spacing: 2

        // Header: title + month label + prev/next.
        RowLayout {
            Layout.fillWidth: true
            spacing: PlasmaCore.Units.smallSpacing

            PlasmaComponents3.Label {
                text: i18n("Horas del mes")
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            PlasmaComponents3.ToolButton {
                icon.name: "go-previous"
                enabled: heat.monthOffset > -1
                onClicked: heat.monthOffset = -1
                PlasmaComponents3.ToolTip.text: i18n("Mes anterior")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
            PlasmaComponents3.Label {
                text: heat._monthNames[heat.month] + " " + heat.year
                font.bold: true
                Layout.minimumWidth: 130
                horizontalAlignment: Text.AlignHCenter
            }
            PlasmaComponents3.ToolButton {
                icon.name: "go-next"
                enabled: heat.monthOffset < 0
                onClicked: heat.monthOffset = 0
                PlasmaComponents3.ToolTip.text: i18n("Mes actual")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
        }

        // Grid: uniform columns — icon column + one per day.
        RowLayout {
            Layout.fillWidth: true
            spacing: 1

            // Icon column (same width as a day column).
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 1
                Item { Layout.fillWidth: true; Layout.preferredHeight: heat.letterRowH }
                Item { Layout.fillWidth: true; Layout.preferredHeight: heat.numberRowH }
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: heat.cellRowH
                    PlasmaCore.IconItem {
                        anchors.centerIn: parent
                        width: 16; height: 16
                        source: "chronometer"
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        PlasmaComponents3.ToolTip.text: i18n("Clockify")
                        PlasmaComponents3.ToolTip.visible: containsMouse
                        PlasmaComponents3.ToolTip.delay: 300
                    }
                }
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: heat.cellRowH
                    PlasmaCore.IconItem {
                        anchors.centerIn: parent
                        width: 16; height: 16
                        source: "view-task"
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        PlasmaComponents3.ToolTip.text: i18n("Jira")
                        PlasmaComponents3.ToolTip.visible: containsMouse
                        PlasmaComponents3.ToolTip.delay: 300
                    }
                }
            }

            // One column per day.
            Repeater {
                model: heat.daysInMonth
                delegate: ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 1
                    readonly property int day: index + 1
                    readonly property bool weekend: heat._isWeekend(day)

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        Layout.preferredHeight: heat.letterRowH
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: heat._weekdayLetter(day)
                        color: weekend ? heat._weekendColor : PlasmaCore.Theme.textColor
                        font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                        opacity: weekend ? 0.8 : 1.0
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        Layout.preferredHeight: heat.numberRowH
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "" + day
                        color: weekend ? heat._weekendColor : PlasmaCore.Theme.textColor
                        font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                        font.bold: !weekend
                    }
                    HoursCell { hours: (heat._v, heat._clkHours(day)) }
                    HoursCell { hours: (heat._v, heat._jiraHours(day)) }
                }
            }
        }
    }
}
