/*
 * TaskItem.qml - delegate for a single task inside a category list.
 *
 * Shows:
 *   - Colored stripe on the left (category color)
 *   - Checkbox (toggles done)
 *   - Title + priority badge
 *   - Expand button (shows description and subtasks) — only when there is
 *     something to expand (a description and/or subtasks)
 *   - Edit button (emits editRequested) — subtasks are edited there now
 *   - Archive button (store.archiveTask)
 *   - Read-only subtask rows (checkbox toggles done; edit happens in the modal)
 *
 * Expansion state is owned by the parent view (via _isExpanded/_setExpanded)
 * so it survives store bumps that recreate delegates — toggling a checkbox no
 * longer collapses the open cards.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Rectangle {
    id: item

    property var task             // plain task object snapshot
    property var store
    property var view             // parent view: owns persistent expand state
    property color catColor: "#7f8c8d"
    property bool expanded: false

    // Bumped by the view's "expand all / collapse all" buttons. When it
    // changes, re-read the (now updated) persistent state. New delegates read
    // the persistent state on creation (Component.onCompleted).
    property int expandSignal: 0
    onExpandSignalChanged: expanded = item._readExpanded()
    Component.onCompleted: expanded = item._readExpanded()

    function _readExpanded() {
        if (view && task && view._isExpanded) return view._isExpanded(task.id);
        return false;
    }
    function _storeExpanded(v) {
        expanded = v;
        if (view && task && view._setExpanded) view._setExpanded(task.id, v);
    }

    readonly property bool _hasSubtasks: task && task.subtasks && task.subtasks.length > 0
    readonly property bool _hasDescription: task && task.description && task.description.length > 0
    readonly property bool _hasDetail: _hasSubtasks || _hasDescription

    signal editRequested(var task)
    // Jira-link feature (only used when plasmoid.configuration.todoJiraLink).
    signal linkJiraRequested(var task)
    signal openJiraRequested(var task)

    width: parent ? parent.width : 0
    implicitHeight: col.implicitHeight + PlasmaCore.Units.smallSpacing * 2
    radius: 4
    color: Qt.rgba(1, 1, 1, 0.04)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)

    // Left color stripe.
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 4
        radius: 2
        color: item.catColor
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 10
        anchors.rightMargin: PlasmaCore.Units.smallSpacing
        anchors.topMargin: PlasmaCore.Units.smallSpacing
        anchors.bottomMargin: PlasmaCore.Units.smallSpacing
        spacing: PlasmaCore.Units.smallSpacing

        // -------- Header row --------
        RowLayout {
            Layout.fillWidth: true
            spacing: PlasmaCore.Units.smallSpacing

            PlasmaComponents3.CheckBox {
                checked: item.task ? item.task.done : false
                onToggled: item.store.toggleTaskDone(item.task.id)
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: item.task ? item.task.title : ""
                // Show the full title (soft wrap) when expanded; otherwise
                // keep a single elided line so collapsed cards stay compact.
                elide: item.expanded ? Text.ElideNone : Text.ElideRight
                wrapMode: item.expanded ? Text.WordWrap : Text.NoWrap
                font.strikeout: item.task && item.task.done
                opacity: item.task && item.task.done ? 0.6 : 1.0
            }

            // Jira-link button (left of the priority badge). Same raised style
            // as the "New…" button so it stands out; "–" when unlinked, the
            // issue key (e.g. CP-123) once linked. Normal (non-bold) weight.
            PlasmaComponents3.Button {
                visible: plasmoid.configuration.todoJiraLink && item.task
                text: (item.task && item.task.jiraKey) ? item.task.jiraKey : "–"
                onClicked: {
                    if (item.task && item.task.jiraKey) item.openJiraRequested(item.task);
                    else item.linkJiraRequested(item.task);
                }
                PlasmaComponents3.ToolTip.text: (item.task && item.task.jiraKey)
                        ? i18n("Subtarea de Jira %1 — click para ver el detalle", item.task.jiraKey)
                        : i18n("Anexar una subtarea de Jira")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }

            PriorityBadge {
                visible: plasmoid.configuration.showPriorityIcons && item.task
                level: item.task ? item.task.priority : "M"
            }

            PlasmaComponents3.ToolButton {
                visible: item._hasDetail
                icon.name: item.expanded ? "go-up" : "go-down"
                onClicked: item._storeExpanded(!item.expanded)
                PlasmaComponents3.ToolTip.text: item.expanded
                        ? i18n("Collapse") : i18n("Expand")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }

            PlasmaComponents3.ToolButton {
                icon.name: "document-edit"
                onClicked: item.editRequested(item.task)
                PlasmaComponents3.ToolTip.text: i18n("Edit task")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }

            PlasmaComponents3.ToolButton {
                icon.name: "archive-insert"
                onClicked: item.store.archiveTask(item.task.id)
                PlasmaComponents3.ToolTip.text: i18n("Send to archive")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
        }

        // -------- Description --------
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            Layout.leftMargin: PlasmaCore.Units.iconSizes.small
            text: item.task ? item.task.description : ""
            wrapMode: Text.WordWrap
            visible: item.expanded && item._hasDescription
            // Gray tint preserved via opacity, italic removed.
            opacity: 0.75
            font.italic: false
        }

        // -------- Subtasks (read-only; edited in the task modal) --------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: PlasmaCore.Units.iconSizes.small
            spacing: 2
            visible: item.expanded && item._hasSubtasks

            Repeater {
                model: item._hasSubtasks ? item.task.subtasks.length : 0
                delegate: RowLayout {
                    Layout.fillWidth: true
                    spacing: PlasmaCore.Units.smallSpacing
                    property var sub: item.task.subtasks[index]

                    PlasmaComponents3.CheckBox {
                        checked: sub.done
                        onToggled: item.store.toggleSubtaskDone(item.task.id, sub.id)
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: sub.title
                        elide: Text.ElideRight
                        font.strikeout: sub.done
                        opacity: sub.done ? 0.55 : 1.0
                    }
                    PriorityBadge {
                        visible: plasmoid.configuration.showPriorityIcons
                        level: sub.priority
                    }
                }
            }
        }
    }
}
