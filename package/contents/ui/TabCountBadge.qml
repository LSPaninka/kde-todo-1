/*
 * TabCountBadge.qml - small pill / circle showing a numeric count next to
 * a tab title. A perfect circle for single-digit counts and a slightly
 * wider pill for two or more digits, so the layout never looks oblong.
 */

import QtQuick 2.15
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Rectangle {
    id: pill
    property int count: 0
    property color badgeColor: "#888"
    property color textColor: "white"

    readonly property int _diameter: PlasmaCore.Units.iconSizes.small - 2
    readonly property bool _wide: count >= 10

    color: badgeColor
    radius: _diameter / 2
    implicitHeight: _diameter
    // For single digits, keep it square (true circle). For 2+ digits, grow.
    implicitWidth: _wide
            ? Math.max(_diameter, label.implicitWidth + _diameter * 0.6)
            : _diameter

    PlasmaComponents3.Label {
        id: label
        anchors.centerIn: parent
        text: pill.count
        color: pill.textColor
        font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
        font.bold: true
    }
}
