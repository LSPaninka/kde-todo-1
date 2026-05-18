/*
 * ModeMenuButton.qml - hamburger button + popup menu to switch operating
 * mode. Lives in the footer row of every mode-specific view next to
 * "Configure…". Selecting an item writes plasmoid.configuration.mode and
 * the FullRepresentation StackLayout reacts immediately.
 */

import QtQuick 2.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

PlasmaComponents3.ToolButton {
    id: btn
    icon.name: "application-menu"
    PlasmaComponents3.ToolTip.text: i18n("Cambiar de modo")
    PlasmaComponents3.ToolTip.visible: hovered
    PlasmaComponents3.ToolTip.delay: 500

    onClicked: modeMenu.open()

    QQC2.Menu {
        id: modeMenu
        // Open above the button (footer is at the bottom of the popup).
        y: -implicitHeight

        QQC2.MenuItem {
            text: i18n("ToDo")
            icon.name: "view-task"
            checkable: true
            checked: plasmoid.configuration.mode === "todo"
            onTriggered: plasmoid.configuration.mode = "todo"
        }
        QQC2.MenuItem {
            text: i18n("Jira")
            icon.name: "go-bottom"
            checkable: true
            checked: plasmoid.configuration.mode === "jira"
            onTriggered: plasmoid.configuration.mode = "jira"
        }
        QQC2.MenuItem {
            text: i18n("GitHub Projects")
            icon.name: "applications-development"
            checkable: true
            checked: plasmoid.configuration.mode === "gh"
            onTriggered: plasmoid.configuration.mode = "gh"
        }
        QQC2.MenuItem {
            text: i18n("Notion")
            icon.name: "notes"
            checkable: true
            checked: plasmoid.configuration.mode === "notion"
            onTriggered: plasmoid.configuration.mode = "notion"
        }
    }
}
