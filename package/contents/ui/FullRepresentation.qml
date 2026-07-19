/*
 * FullRepresentation.qml - mode-aware dispatcher for the popup contents.
 *
 * Renders TodoView for "todo", JiraView for "jira", GhView for "gh", and
 * NotionView for "notion". Switching is reactive: the StackLayout
 * currentIndex follows the configuration change immediately.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0

Item {
    id: full

    property var store
    property var jira
    property var jira2
    property var gh
    property var notion
    property var notionSync

    readonly property string mode: plasmoid.configuration.mode || "todo"

    function _modeIndex() {
        if (full.mode === "jira")   return 1;
        if (full.mode === "gh")     return 2;
        if (full.mode === "notion") return 3;
        if (full.mode === "jira2")  return 4;
        return 0;
    }

    StackLayout {
        anchors.fill: parent
        currentIndex: full._modeIndex()

        TodoView {
            store: full.store
            notionSync: full.notionSync
            jira: full.jira
        }

        JiraView {
            jira: full.jira
            cfgPrefix: "jira"
        }

        GhView {
            gh: full.gh
        }

        NotionView {
            notion: full.notion
        }

        JiraView {
            jira: full.jira2
            cfgPrefix: "jira2"
        }
    }
}
