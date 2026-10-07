/*
 * ModeMenuButton.qml - hamburger button + popup menu to switch operating
 * mode. Lives in the footer row of every mode-specific view next to
 * "Configure…". Selecting an item writes Plasmoid.configuration.mode and
 * the FullRepresentation StackLayout reacts immediately.
 */

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3

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
            checked: Plasmoid.configuration.mode === "todo"
            onTriggered: Plasmoid.configuration.mode = "todo"
        }
        QQC2.MenuItem {
            text: i18n("Jira 1")
            icon.name: "go-bottom"
            checkable: true
            checked: Plasmoid.configuration.mode === "jira"
            onTriggered: Plasmoid.configuration.mode = "jira"
        }
        QQC2.MenuItem {
            text: i18n("Jira 2")
            icon.name: "go-bottom"
            checkable: true
            checked: Plasmoid.configuration.mode === "jira2"
            onTriggered: Plasmoid.configuration.mode = "jira2"
        }
        QQC2.MenuItem {
            text: i18n("GitHub Projects")
            icon.name: "applications-development"
            checkable: true
            checked: Plasmoid.configuration.mode === "gh"
            onTriggered: Plasmoid.configuration.mode = "gh"
        }
        // The standalone Notion (ntn CLI) mode is disabled for now; Notion is
        // integrated into the ToDo mode as a two-way sync instead.
    }
}
