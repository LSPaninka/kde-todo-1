/*
 * MonthHeatmap.qml - month-at-a-glance hours table for Clockify mode.
 *
 * A horizontal table spanning the popup width with one column per day of
 * the visible month. Rows:
 *   1. weekday letter (D L M Mi J V S) — gray on weekends
 *   2. day number — gray on weekends
 *   3. Clockify hours that day as a decimal number (3h30m → 3.5), the
 *      cell background graded gray→red→yellow→green from 0 to 4 (≥4 green).
 *   4. (optional) Jira burned hours that day, same format + grading.
 *
 * Two views: current month and last month, toggled with ◀ / ▶.
 *
 * The per-day totals come from clockifyStore.fetchMonthTotals /
 * jiraStore.fetchMonthTotals, which aggregate without disturbing the
 * stores' week-scoped arrays.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: heat

    property var clockifyStore
    property var jiraStore
    property bool showJiraRow: true
    property int monthOffset: 0   // 0 = current month, -1 = last month

    implicitHeight: col.implicitHeight

    // Reference date = first day of the visible month.
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
    property int _v: 0                   // bumped when totals arrive

    readonly property var _monthNames: ["Enero","Febrero","Marzo","Abril","Mayo","Junio",
                                        "Julio","Agosto","Septiembre","Octubre","Noviembre","Diciembre"]
    readonly property var _dowLetters: ["D","L","M","Mi","J","V","S"]

    function refresh() {
        if (clockifyStore && clockifyStore.fetchMonthTotals) {
            clockifyStore.fetchMonthTotals(year, month, function(ok, t) {
                if (ok) { heat.clockifyTotals = t; heat._v++; }
            });
        }
        if (showJiraRow && jiraStore && jiraStore.fetchMonthTotals) {
            jiraStore.fetchMonthTotals(year, month, function(ok, t) {
                if (ok) { heat.jiraTotals = t; heat._v++; }
            });
        }
    }
    onMonthOffsetChanged: refresh()
    Component.onCompleted: refresh()

    function _dow(day) { return new Date(year, month, day).getDay(); } // 0=Sun..6=Sat
    function _isWeekend(day) { var d = _dow(day); return d === 0 || d === 6; }
    function _weekdayLetter(day) { return _dowLetters[_dow(day)]; }

    function _hoursDecimal(sec) {
        if (!sec || sec <= 0) return 0;
        return Math.round((sec / 3600) * 10) / 10;   // one decimal
    }
    function _fmtNum(h) {
        if (h <= 0) return "";
        if (h === Math.floor(h)) return "" + h;
        return h.toFixed(1);
    }

    // Gray (0) → red (#e74c3c) → yellow (#f1c40f) → light green (#81c784, ≥4).
    function _lerp(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t,
                       a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, 1);
    }
    function _cellColor(h) {
        if (h <= 0) return Qt.rgba(1, 1, 1, 0.06);   // gray
        var red    = Qt.rgba(231/255, 76/255,  60/255, 1);
        var yellow = Qt.rgba(241/255, 196/255, 15/255, 1);
        var green  = Qt.rgba(129/255, 199/255, 132/255, 1);
        var c = Math.min(4, h);
        if (c <= 2) return _lerp(red, yellow, c / 2);
        return _lerp(yellow, green, (c - 2) / 2);
    }
    function _cellTextColor(h) {
        return h > 0 ? "#1a1a1a" : PlasmaCore.Theme.textColor;
    }

    readonly property color _weekendColor: PlasmaCore.Theme.disabledTextColor

    ColumnLayout {
        id: col
        anchors.fill: parent
        spacing: 2

        // Header: month label + prev/next.
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

        // The day grid: one column per day, sharing the width equally.
        RowLayout {
            Layout.fillWidth: true
            spacing: 1

            Repeater {
                model: heat.daysInMonth
                delegate: ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 1
                    readonly property int day: index + 1
                    readonly property bool weekend: heat._isWeekend(day)

                    // Row 1: weekday letter
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: heat._weekdayLetter(day)
                        color: weekend ? heat._weekendColor : PlasmaCore.Theme.textColor
                        font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                        opacity: weekend ? 0.8 : 1.0
                    }
                    // Row 2: day number
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: "" + day
                        color: weekend ? heat._weekendColor : PlasmaCore.Theme.textColor
                        font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                        font.bold: !weekend
                    }
                    // Row 3: Clockify hours cell
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 18
                        radius: 2
                        color: heat._cellColor((heat._v, heat._hoursDecimal(heat.clockifyTotals[day] || 0)))
                        border.width: 1
                        border.color: Qt.rgba(0, 0, 0, 0.15)
                        PlasmaComponents3.Label {
                            anchors.centerIn: parent
                            text: heat._fmtNum(heat._hoursDecimal(heat.clockifyTotals[day] || 0))
                            color: heat._cellTextColor(heat._hoursDecimal(heat.clockifyTotals[day] || 0))
                            font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                            font.bold: true
                        }
                    }
                    // Row 4 (optional): Jira hours cell
                    Rectangle {
                        visible: heat.showJiraRow
                        Layout.fillWidth: true
                        Layout.preferredHeight: 18
                        radius: 2
                        color: heat._cellColor((heat._v, heat._hoursDecimal(heat.jiraTotals[day] || 0)))
                        border.width: 1
                        border.color: Qt.rgba(0, 0, 0, 0.15)
                        PlasmaComponents3.Label {
                            anchors.centerIn: parent
                            text: heat._fmtNum(heat._hoursDecimal(heat.jiraTotals[day] || 0))
                            color: heat._cellTextColor(heat._hoursDecimal(heat.jiraTotals[day] || 0))
                            font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                            font.bold: true
                        }
                    }
                }
            }
        }

        // Legend.
        RowLayout {
            Layout.fillWidth: true
            spacing: PlasmaCore.Units.smallSpacing
            PlasmaComponents3.Label {
                text: i18n("Clockify (fila 3)") + (heat.showJiraRow ? i18n(" · Jira (fila 4)") : "")
                opacity: 0.6
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            }
            Item { Layout.fillWidth: true }
            PlasmaComponents3.Label {
                text: i18n("horas en decimal (3h30m = 3.5)")
                opacity: 0.6
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            }
        }
    }
}
