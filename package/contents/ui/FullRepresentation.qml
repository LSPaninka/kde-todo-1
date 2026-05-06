/*
 * FullRepresentation.qml - mode-aware dispatcher for the popup contents.
 *
 * Renders TodoView when mode == "todo", JiraView when mode == "jira".
 * Switching is reactive: the StackLayout currentIndex follows the
 * configuration change immediately.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0

Item {
    id: full

    property var store
    property var jira

    readonly property string mode: plasmoid.configuration.mode || "todo"

    StackLayout {
        anchors.fill: parent
        currentIndex: full.mode === "jira" ? 1 : 0

        TodoView {
            store: full.store
        }

        JiraView {
            jira: full.jira
        }
    }
}
