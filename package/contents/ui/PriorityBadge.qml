/*
 * PriorityBadge.qml - small "XS/S/M/L/XL" chip used next to task titles.
 */

import QtQuick 2.15
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Rectangle {
    id: badge
    property string level: "M"

    function _colorFor(p) {
        switch (p) {
            case "XS": return "#95a5a6";
            case "S":  return "#3498db";
            case "M":  return "#2ecc71";
            case "L":  return "#f39c12";
            case "XL": return "#e74c3c";
        }
        return "#2ecc71";
    }

    implicitWidth: label.implicitWidth + PlasmaCore.Units.smallSpacing * 2
    implicitHeight: label.implicitHeight + 2
    radius: 3
    color: _colorFor(level)
    border.color: Qt.darker(color, 1.5)
    border.width: 1

    PlasmaComponents3.Label {
        id: label
        anchors.centerIn: parent
        text: badge.level
        color: "white"
        font.bold: true
        font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
    }
}
