/*
 * PriorityBadge.qml - small "XS/S/M/L/XL" chip used next to task titles.
 */

import QtQuick
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Rectangle {
    id: badge
    property string level: "M"

    // Colors come from the configurable priority scheme.
    CategoryHelper { id: _prio }

    implicitWidth: label.implicitWidth + Kirigami.Units.smallSpacing * 2
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
        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
    }
}
