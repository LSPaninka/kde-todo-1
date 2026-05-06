/*
 * SwatchBadge.qml - one entry of the compact (panel) representation.
 *
 * Renders either:
 *   - a small colored swatch with the count to the right, or
 *   - a bigger colored swatch with the count drawn inside,
 * depending on `insideMode`. Optionally appends a label after the count.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: badge

    property int catIndex: 0
    property color color: "#7f8c8d"
    property int count: 0
    property bool showZero: true
    property string label: ""
    property bool showLabel: false
    property color textColor: "white"
    property bool insideMode: false
    property int smallSwatch: 12
    property int bigSwatch: 22

    visible: showZero || count > 0
    implicitWidth:  insideMode ? insideRow.implicitWidth : rightRow.implicitWidth
    implicitHeight: insideMode ? insideRow.implicitHeight : rightRow.implicitHeight
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight

    // -------- "right" style --------
    RowLayout {
        id: rightRow
        visible: !badge.insideMode
        spacing: PlasmaCore.Units.smallSpacing

        Rectangle {
            Layout.preferredWidth: badge.smallSwatch
            Layout.preferredHeight: badge.smallSwatch
            radius: 2
            color: badge.color
            border.width: 1
            border.color: Qt.darker(color, 1.4)
        }

        PlasmaComponents3.Label {
            text: badge.count
            color: badge.textColor
            font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize + 2
            font.bold: true
        }

        PlasmaComponents3.Label {
            visible: badge.showLabel
            text: badge.label
            font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            opacity: 0.75
        }
    }

    // -------- "inside" style --------
    RowLayout {
        id: insideRow
        visible: badge.insideMode
        spacing: PlasmaCore.Units.smallSpacing

        Rectangle {
            id: bigSwatchRect
            property bool wide: badge.count >= 10
            Layout.preferredWidth: wide ? badge.bigSwatch + 8 : badge.bigSwatch
            Layout.preferredHeight: badge.bigSwatch
            radius: 3
            color: badge.color
            border.width: 1
            border.color: Qt.darker(color, 1.4)

            PlasmaComponents3.Label {
                anchors.centerIn: parent
                text: badge.count
                color: badge.textColor
                font.bold: true
                font.pixelSize: Math.max(
                    PlasmaCore.Theme.smallestFont.pixelSize,
                    Math.round(badge.bigSwatch * 0.6))
            }
        }

        PlasmaComponents3.Label {
            visible: badge.showLabel
            text: badge.label
            font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            opacity: 0.75
        }
    }
}
