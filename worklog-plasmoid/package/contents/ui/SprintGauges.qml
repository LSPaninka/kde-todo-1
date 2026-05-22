/*
 * SprintGauges.qml - twin RingGauge widget that sits at the bottom of
 * the calendar in 9h-mode Jira (or Jira/Clockify) view.
 *
 * Left ring  : "Sprint" — % of time elapsed in the current Jira sprint.
 *              Colors go from cyan → yellow → orange → red → dark red as
 *              the sprint nears its end (thresholds 0/75/85/90/100).
 *
 * Right ring : "Horas" — % of the user's total estimated time in this
 *              sprint that's already been logged. Stays light green
 *              until 100% (which uses a brighter green). The color
 *              cycles between baseColor and a paler tint to draw the
 *              eye — faster cycle when the sprint is ≥85% and you've
 *              logged less than 99% of your hours (i.e. you're behind).
 *
 * Side / middle horizontal lines are purely decorative.
 *
 * Both rings animate from 0% to their target on startFillAnimation(),
 * which the FullRepresentation calls every time the popup is opened.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: gauges

    property var jiraStore           // expose currentSprint + sprint hours
    implicitHeight: layout.implicitHeight

    // Trigger the fill-in animation on both rings.
    function startFillAnimation() {
        sprintRing.startFill();
        hoursRing.startFill();
    }

    // --------- Helpers --------------------------------------------------

    function _hasSprint() {
        return jiraStore && jiraStore.currentSprint && jiraStore.currentSprint.startDate;
    }

    function _sprintPct() {
        if (!_hasSprint()) return 0;
        var start = new Date(jiraStore.currentSprint.startDate).getTime();
        var end   = new Date(jiraStore.currentSprint.endDate).getTime();
        var now   = Date.now();
        if (isNaN(start) || isNaN(end) || end <= start) return 0;
        if (now <= start) return 0;
        if (now >= end)   return 100;
        return ((now - start) / (end - start)) * 100;
    }

    // Per the original definition: "el total de horas seteadas (disponibles
    // y consumidas)". Available is what's still pending, consumed is what
    // I've logged in this sprint; the denominator is the SUM so the
    // percentage walks from 0 → 100 as you log hours against the sprint.
    function _hoursPct() {
        if (!jiraStore) return 0;
        var avail    = jiraStore.sprintAvailableSec | 0;
        var consumed = jiraStore.sprintConsumedSec  | 0;
        var total    = avail + consumed;
        if (total <= 0) return 0;
        return Math.max(0, Math.min(100, (consumed / total) * 100));
    }

    function _sprintColor(pct) {
        if (pct >= 100) return "#B71C1C";   // dark red
        if (pct >= 90)  return "#E53935";   // red
        if (pct >= 85)  return "#FB8C00";   // orange
        if (pct >= 75)  return "#FBC02D";   // yellow
        return "#29B6F6";                    // celeste / light blue
    }
    function _hoursBase(pct) {
        return pct >= 100 ? "#4CAF50" : "#81C784";
    }

    function _fmtDate(iso) {
        if (!iso) return "—";
        var d = new Date(iso);
        if (isNaN(d.getTime())) return "—";
        return d.getDate() + "/" + (d.getMonth() + 1);
    }
    function _fmtHours(sec) {
        if (!sec) return "0h";
        var h = Math.floor(sec / 3600);
        var m = Math.floor((sec % 3600) / 60);
        if (h > 0 && m > 0) return h + "h " + m + "m";
        if (h > 0)          return h + "h";
        return m + "m";
    }

    // Re-read percentages when the store version bumps.
    readonly property int _v: jiraStore ? jiraStore.version : 0
    readonly property real sprintPct: (_v, _sprintPct())
    readonly property real hoursPct:  (_v, _hoursPct())

    // Faster fade when the sprint is ≥85% and you're behind on hours.
    readonly property bool _hoursIntermittent: sprintPct >= 85 && hoursPct < 99

    RowLayout {
        id: layout
        anchors.fill: parent
        spacing: PlasmaCore.Units.smallSpacing * 2

        // Left decorative line.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.alignment: Qt.AlignVCenter
            color: Qt.rgba(1, 1, 1, 0.10)
        }

        // ----- Sprint column -----
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 4
            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignHCenter
                text: i18n("Sprint")
                font.bold: true
                font.pixelSize: PlasmaCore.Theme.defaultFont.pixelSize + 1
            }
            RingGauge {
                id: sprintRing
                Layout.alignment: Qt.AlignHCenter
                diameter: 110
                thickness: 12
                value: gauges.sprintPct
                baseColor: gauges._sprintColor(gauges.sprintPct)
                useFadeLoop: false
            }
            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
                text: gauges._hasSprint()
                      ? i18n("Inicio: %1\nFin: %2",
                             gauges._fmtDate(jiraStore.currentSprint.startDate),
                             gauges._fmtDate(jiraStore.currentSprint.endDate))
                      : i18n("Sin sprint activo")
                opacity: 0.75
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            }
        }

        // Middle decorative line.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.alignment: Qt.AlignVCenter
            color: Qt.rgba(1, 1, 1, 0.10)
        }

        // ----- Horas column -----
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 4
            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignHCenter
                text: i18n("Horas")
                font.bold: true
                font.pixelSize: PlasmaCore.Theme.defaultFont.pixelSize + 1
            }
            RingGauge {
                id: hoursRing
                Layout.alignment: Qt.AlignHCenter
                diameter: 110
                thickness: 12
                value: gauges.hoursPct
                baseColor: gauges._hoursBase(gauges.hoursPct)
                paleColor: "#C8E6C9"
                useFadeLoop: true
                intermittent: gauges._hoursIntermittent
            }
            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
                text: jiraStore
                      ? i18n("Disponible: %1\nQuemadas: %2",
                             gauges._fmtHours(jiraStore.sprintAvailableSec),
                             gauges._fmtHours(jiraStore.sprintConsumedSec))
                      : ""
                opacity: 0.75
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            }
        }

        // Right decorative line.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.alignment: Qt.AlignVCenter
            color: Qt.rgba(1, 1, 1, 0.10)
        }
    }
}
