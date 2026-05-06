/*
 * CompactRepresentation.qml - panel / system-tray view.
 *
 * Two operating modes:
 *   - "todo": one swatch + count per ToDo category.
 *   - "jira": one swatch + count per Jira category (configurable).
 *
 * Inside each mode, the layout follows panelCounterStyle ("right" or
 * "inside") and panelCounterColors (white | black per swatch).
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: compact
    property var store
    property var jira

    readonly property string mode: plasmoid.configuration.mode || "todo"
    readonly property int _vTodo: store ? store.version : 0
    readonly property int _vJira: jira ? jira.version : 0

    CategoryHelper { id: cats }

    readonly property int _smallSwatch: Math.max(10, PlasmaCore.Units.iconSizes.small - 2)
    readonly property int _bigSwatch:   Math.max(18, PlasmaCore.Units.iconSizes.medium - 2)

    function _todoTextColor(idx) {
        var arr = plasmoid.configuration.panelCounterColors || [];
        var v = arr[idx];
        return (v === "black") ? "black" : "white";
    }

    function _jiraTextColor(idx) {
        var arr = plasmoid.configuration.jiraCategoryTextColors || [];
        var v = arr[idx];
        return (v === "black") ? "black" : "white";
    }
    function _jiraName(i) {
        var arr = plasmoid.configuration.jiraCategoryNames || [];
        return arr[i] || qsTr("Cat. %1").arg(i + 1);
    }
    function _jiraColor(i) {
        var arr = plasmoid.configuration.jiraCategoryColors || [];
        return arr[i] || "#7f8c8d";
    }
    function _jiraCount() {
        return Math.min(4, Math.max(1, plasmoid.configuration.jiraCategoryCount | 0 || 3));
    }

    Layout.minimumWidth: row.implicitWidth + PlasmaCore.Units.smallSpacing * 2
    Layout.preferredWidth: Layout.minimumWidth
    Layout.minimumHeight: PlasmaCore.Units.iconSizes.small
    Layout.preferredHeight: PlasmaCore.Units.iconSizes.medium

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        hoverEnabled: true
        onClicked: plasmoid.expanded = !plasmoid.expanded
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: PlasmaCore.Units.smallSpacing * 2

        // -------- TODO mode --------
        Repeater {
            model: compact.mode === "todo" ? cats.count() : 0
            delegate: SwatchBadge {
                catIndex: index
                color: cats.color(index)
                count: (compact._vTodo, store ? store.pendingCountForCategory(index) : 0)
                showZero: plasmoid.configuration.panelShowZero
                label: cats.name(index)
                showLabel: plasmoid.configuration.panelShowLabels
                textColor: compact._todoTextColor(index)
                insideMode: plasmoid.configuration.panelCounterStyle === "inside"
                smallSwatch: compact._smallSwatch
                bigSwatch: compact._bigSwatch
            }
        }

        // -------- JIRA mode --------
        Repeater {
            model: compact.mode === "jira" ? compact._jiraCount() : 0
            delegate: SwatchBadge {
                catIndex: index
                color: compact._jiraColor(index)
                count: (compact._vJira, jira ? jira.countByJiraCategory(index) : 0)
                showZero: plasmoid.configuration.panelShowZero
                label: compact._jiraName(index)
                showLabel: plasmoid.configuration.panelShowLabels
                textColor: compact._jiraTextColor(index)
                insideMode: plasmoid.configuration.panelCounterStyle === "inside"
                smallSwatch: compact._smallSwatch
                bigSwatch: compact._bigSwatch
            }
        }
    }
}
