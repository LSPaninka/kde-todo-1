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
    signal linkJiraRequested(var task)
    signal openJiraRequested(var task)

    // Expand/collapse-all control (see TaskItem.expandSignal/expandTarget).
    property int _expandSeq: 0
    property bool _expandTarget: false

    CategoryHelper { id: cats }

    readonly property int _v: store ? store.version : 0
    readonly property var _allInCategory: (_v, store ? store.tasksForCategory(catIndex) : [])
    readonly property var filtered: view._applyFilter(_allInCategory, searchField.text)

    function _applyFilter(arr, q) {
        if (!q || q.trim().length === 0) return arr;
        var needle = q.trim().toLowerCase();
        var out = [];
        for (var i = 0; i < arr.length; i++) {
            var t = arr[i];
            var hay = ((t.title || "") + " " + (t.description || "")).toLowerCase();
            if (hay.indexOf(needle) >= 0) out.push(t);
        }
        return out;
    }

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
                    var total = view._allInCategory.length;
                    var pending = store.pendingCountForCategory(view.catIndex);
                    return i18n("%1 — %2 pending of %3",
                                cats.name(view.catIndex), pending, total);
                }
                font.bold: true
                elide: Text.ElideRight
            }
            // Expand / collapse all tasks (show/hide descriptions).
            PlasmaComponents3.ToolButton {
                icon.name: "arrow-down-double"
                onClicked: { view._expandTarget = true; view._expandSeq++; }
                PlasmaComponents3.ToolTip.text: i18n("Expandir todas las tareas")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
            PlasmaComponents3.ToolButton {
                icon.name: "arrow-up-double"
                onClicked: { view._expandTarget = false; view._expandSeq++; }
                PlasmaComponents3.ToolTip.text: i18n("Colapsar todas las tareas")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
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

        // Search row (filters within this category as you type).
        RowLayout {
            Layout.fillWidth: true
            spacing: PlasmaCore.Units.smallSpacing

            PlasmaCore.IconItem {
                source: "search"
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
            }
            PlasmaComponents3.TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: i18n("Buscar tareas en esta categoría…")
                Keys.onEscapePressed: text = ""
            }
            PlasmaComponents3.ToolButton {
                visible: searchField.text.length > 0
                icon.name: "edit-clear"
                onClicked: searchField.text = ""
                PlasmaComponents3.ToolTip.text: i18n("Limpiar búsqueda")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
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
                    expandSignal: view._expandSeq
                    expandTarget: view._expandTarget
                    onEditRequested: view.editTaskRequested(task)
                    onSubtaskEditRequested: view.editSubtaskRequested(task, subtask)
                    onLinkJiraRequested: view.linkJiraRequested(task)
                    onOpenJiraRequested: view.openJiraRequested(task)
                }

                PlasmaComponents3.Label {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    width: parent.width - 40
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: searchField.text.length > 0
                          ? i18n("Ninguna tarea coincide con la búsqueda.")
                          : i18n("No tasks in this category yet. Usá «New…» para crear una.")
                    opacity: 0.55
                }
            }
        }
    }
}
