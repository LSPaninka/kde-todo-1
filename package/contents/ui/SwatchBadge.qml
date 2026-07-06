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

    // Scale (percent, 50..100) applied to the "inside" style only: the
    // swatch, its number and the inner spacing all shrink together.
    property int scalePercent: 100
    readonly property real _scale: Math.max(50, Math.min(100, scalePercent)) / 100
    readonly property int _effBig: insideMode ? Math.max(10, Math.round(bigSwatch * _scale)) : bigSwatch

    // Tooltip payload. We don't render a QQC2 tooltip ourselves anymore;
    // the parent forwards these to Plasmoid.toolTipMainText/SubText so the
    // native Plasma tooltip (the one that sits above the panel) is reused.
    property string tooltipTitle: ""
    property string tooltipBody: ""

    // Emitted when the cursor enters or leaves this badge. CompactRepresentation
    // listens and pipes the values up to main.qml's tooltip override.
    signal hoverChanged(bool isHovered, string mainText, string subText)

    // Emitted on a left click on this specific swatch (carries its index).
    signal clicked(int catIndex)

    HoverHandler {
        id: _hover
        onHoveredChanged: badge.hoverChanged(hovered, badge.tooltipTitle, badge.tooltipBody)
    }

    // Per-swatch click handling. Sits above CompactRepresentation's global
    // MouseArea so a click here opens the matching category. Wheel events are
    // explicitly passed through (accepted = false) so mode-cycling by wheel
    // still works while hovering a swatch.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: badge.clicked(badge.catIndex)
        onWheel: wheel.accepted = false
    }

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
        spacing: Math.max(2, Math.round(PlasmaCore.Units.smallSpacing * badge._scale))

        Rectangle {
            id: bigSwatchRect
            property bool wide: badge.count >= 10
            Layout.preferredWidth: wide ? badge._effBig + Math.round(8 * badge._scale) : badge._effBig
            Layout.preferredHeight: badge._effBig
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
                    Math.round(PlasmaCore.Theme.smallestFont.pixelSize * badge._scale),
                    Math.round(badge._effBig * 0.6))
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
