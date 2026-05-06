/*
 * TaskItem.qml - delegate for a single task inside a category list.
 *
 * Shows:
 *   - Colored stripe on the left (category color)
 *   - Checkbox (toggles done)
 *   - Title + priority badge
 *   - Expand button (shows description and subtasks)
 *   - Edit button (emits editRequested)
 *   - Archive button (store.archiveTask)
 *   - Subtask rows with their own checkbox/priority/edit/delete buttons
 *   - "Add subtask" inline row
 *
 * Dialog-less by design: the parent view owns the subtask-edit dialog
 * and this delegate signals back to it via subtaskEditRequested.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Rectangle {
    id: item

    property var task             // plain task object snapshot
    property var store
    property color catColor: "#7f8c8d"
    property bool expanded: false

    signal editRequested(var task)
    signal subtaskEditRequested(var task, var subtask)

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
                elide: Text.ElideRight
                font.strikeout: item.task && item.task.done
                opacity: item.task && item.task.done ? 0.6 : 1.0
            }

            PriorityBadge {
                visible: plasmoid.configuration.showPriorityIcons && item.task
                level: item.task ? item.task.priority : "M"
            }

            PlasmaComponents3.ToolButton {
                icon.name: item.expanded ? "go-up" : "go-down"
                onClicked: item.expanded = !item.expanded
                PlasmaComponents3.ToolTip.text: item.expanded
                        ? i18n("Collapse") : i18n("Expand / add subtasks")
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
            visible: item.expanded && item.task && item.task.description.length > 0
            opacity: 0.75
            font.italic: true
        }

        // -------- Subtasks --------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: PlasmaCore.Units.iconSizes.small
            spacing: 2
            visible: item.expanded

            Repeater {
                model: item.task ? item.task.subtasks.length : 0
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
                    PlasmaComponents3.ToolButton {
                        icon.name: "document-edit"
                        onClicked: item.subtaskEditRequested(item.task, sub)
                        PlasmaComponents3.ToolTip.text: i18n("Edit subtask")
                        PlasmaComponents3.ToolTip.visible: hovered
                        PlasmaComponents3.ToolTip.delay: 500
                    }
                    PlasmaComponents3.ToolButton {
                        icon.name: "list-remove"
                        onClicked: item.store.removeSubtask(item.task.id, sub.id)
                        PlasmaComponents3.ToolTip.text: i18n("Remove subtask")
                        PlasmaComponents3.ToolTip.visible: hovered
                        PlasmaComponents3.ToolTip.delay: 500
                    }
                }
            }

            // Inline add-subtask row.
            RowLayout {
                Layout.fillWidth: true
                spacing: PlasmaCore.Units.smallSpacing

                PlasmaComponents3.TextField {
                    id: newSubField
                    Layout.fillWidth: true
                    placeholderText: i18n("Add subtask and press Enter…")
                    onAccepted: item._commitNewSub()
                }
                PrioritySelector {
                    id: newSubPrio
                    value: "M"
                    Layout.preferredWidth: 90
                }
                PlasmaComponents3.Button {
                    icon.name: "list-add"
                    text: i18n("Add")
                    onClicked: item._commitNewSub()
                }
            }
        }
    }

    function _commitNewSub() {
        var t = newSubField.text.trim();
        if (t.length === 0) return;
        store.addSubtask(task.id, t, newSubPrio.value);
        newSubField.text = "";
        newSubPrio.value = "M";
        newSubField.forceActiveFocus();
    }
}
