/*
 * CompactRepresentation.qml - panel view. Just the calendar icon.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore

Item {
    id: compact

    Layout.minimumWidth: PlasmaCore.Units.iconSizes.small
    Layout.minimumHeight: PlasmaCore.Units.iconSizes.small
    Layout.preferredWidth: PlasmaCore.Units.iconSizes.medium
    Layout.preferredHeight: PlasmaCore.Units.iconSizes.medium

    PlasmaCore.IconItem {
        anchors.fill: parent
        source: "view-calendar-week"
    }

    MouseArea {
        anchors.fill: parent
        onClicked: plasmoid.expanded = !plasmoid.expanded
    }
}
