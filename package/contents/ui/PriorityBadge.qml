/*
 * PriorityBadge.qml - small "XS/S/M/L/XL" chip used next to task titles.
 */

import QtQuick 2.15
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Rectangle {
    id: badge
    property string level: "M"

    // Colors come from the configurable priority scheme.
    CategoryHelper { id: _prio }

    implicitWidth: label.implicitWidth + PlasmaCore.Units.smallSpacing * 2
    implicitHeight: label.implicitHeight + 2
    radius: 3
    color: _prio.priorityColor(level)
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
