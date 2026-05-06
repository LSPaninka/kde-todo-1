/*
 * CategoryView.qml - list of tasks for a single category + "new task" field.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: view
    property var store
    property int catIndex: 0

    // Signals handled by FullRepresentation (which owns the dialogs).
    signal editTaskRequested(var task)
    signal newTaskRequested(int catIndex)
    signal editSubtaskRequested(var task, var subtask)
    signal exportRequested(int catIndex, string categoryName)
    signal importRequested(int catIndex, string categoryName)

    CategoryHelper { id: cats }

    readonly property int _v: store ? store.version : 0
    readonly property var filtered: (_v, store ? store.tasksForCategory(catIndex) : [])

    ColumnLayout {
        anchors.fill: parent
        spacing: PlasmaCore.Units.smallSpacing

        // Header.
        RowLayout {
            Layout.fillWidth: true

            Rectangle {
                width: 14
                height: 14
                radius: 2
                color: cats.color(view.catIndex)
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: {
                    var total = view.filtered.length;
                    var pending = store.pendingCountForCategory(view.catIndex);
                    return i18n("%1 — %2 pending of %3",
                                cats.name(view.catIndex), pending, total);
                }
                font.bold: true
                elide: Text.ElideRight
            }
            PlasmaComponents3.ToolButton {
                icon.name: "document-export"
                onClicked: view.exportRequested(view.catIndex, cats.name(view.catIndex))
                PlasmaComponents3.ToolTip.text: i18n("Export this category as JSON")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
            PlasmaComponents3.ToolButton {
                icon.name: "document-import"
                onClicked: view.importRequested(view.catIndex, cats.name(view.catIndex))
                PlasmaComponents3.ToolTip.text: i18n("Import JSON into this category")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
            PlasmaComponents3.Button {
                icon.name: "document-new"
                text: i18n("New…")
                onClicked: view.newTaskRequested(view.catIndex)
            }
        }

        // Quick-add row.
        RowLayout {
            Layout.fillWidth: true

            PlasmaComponents3.TextField {
                id: quickAddField
                Layout.fillWidth: true
                placeholderText: i18n("Type a task title and press Enter…")
                onAccepted: view._commitQuickAdd()
            }
            PrioritySelector {
                id: quickAddPrio
                value: "M"
                Layout.preferredWidth: 90
            }
            PlasmaComponents3.Button {
                icon.name: "list-add"
                onClicked: view._commitQuickAdd()
            }
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: list
                spacing: 4
                model: view.filtered
                delegate: TaskItem {
                    width: list.width
                    task: modelData
                    store: view.store
                    catColor: cats.color(modelData ? modelData.category : 0)
                    onEditRequested: view.editTaskRequested(task)
                    onSubtaskEditRequested: view.editSubtaskRequested(task, subtask)
                }

                PlasmaComponents3.Label {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: i18n("No tasks in this category yet.")
                    opacity: 0.55
                }
            }
        }
    }

    function _commitQuickAdd() {
        var t = quickAddField.text.trim();
        if (t.length === 0) return;
        store.addTask(t, catIndex, quickAddPrio.value, "");
        quickAddField.text = "";
        quickAddPrio.value = "M";
        quickAddField.forceActiveFocus();
    }
}
