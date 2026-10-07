/*
 * CompactRepresentation.qml - panel view. Just the calendar icon.
 */

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

Item {
    id: compact

    // The PlasmoidItem root (main.qml); owns `expanded`.
    property var plasmoidItem

    Layout.minimumWidth: Kirigami.Units.iconSizes.small
    Layout.minimumHeight: Kirigami.Units.iconSizes.small
    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
    Layout.preferredHeight: Kirigami.Units.iconSizes.medium

    Kirigami.Icon {
        anchors.fill: parent
        source: "view-calendar-week"
    }

    MouseArea {
        anchors.fill: parent
        onClicked: compact.plasmoidItem.expanded = !compact.plasmoidItem.expanded
    }
}
