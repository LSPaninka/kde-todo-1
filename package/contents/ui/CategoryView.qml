/*
 * CategoryView.qml - list of tasks for a single category.
 *
 * The text field below the header has two roles, toggled by the magnifier
 * button left of "New…":
 *   - default: quick-add — type a title, press Enter (or the + button) to
 *     create a task in this category.
 *   - search mode: filter the tasks in this category as you type.
 *
 * Import/export moved to the configuration dialog ("Datos" page).
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

    // Signals handled by TodoView (which owns the dialogs).
    signal editTaskRequested(var task)
    signal newTaskRequested(int catIndex)
    signal linkJiraRequested(var task)
    signal openJiraRequested(var task)

    // Search vs. quick-add mode for the text field.
    property bool _searchMode: false

    // ----- Persistent expand state (survives store bumps) -----
    // Delegates are recreated whenever the model array is reassigned (every
    // store bump). Keeping expansion here — not on the delegate — means
    // toggling a checkbox no longer collapses the open cards.
    property int _expandSeq: 0
    property bool _expandDefault: false
    property var _expandOverrides: ({})
    function _isExpanded(id) {
        if (_expandOverrides.hasOwnProperty(id)) return _expandOverrides[id];
        return _expandDefault;
    }
    function _setExpanded(id, v) { _expandOverrides[id] = v; }
    function _expandAll(v) { _expandDefault = v; _expandOverrides = ({}); _expandSeq++; }

    CategoryHelper { id: cats }

    readonly property int _v: store ? store.version : 0
    readonly property var _allInCategory: (_v, store ? store.tasksForCategory(catIndex) : [])
    readonly property var filtered:
        view._searchMode ? view._applyFilter(_allInCategory, entryField.text) : _allInCategory

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

    function _commitQuickAdd() {
        if (view._searchMode) return;
        var t = entryField.text.trim();
        if (t.length === 0) return;
        store.addTask(t, view.catIndex, cats.defaultPriority(), "");
        entryField.text = "";
        entryField.forceActiveFocus();
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
                onClicked: view._expandAll(true)
                PlasmaComponents3.ToolTip.text: i18n("Expandir todas las tareas")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
            PlasmaComponents3.ToolButton {
                icon.name: "arrow-up-double"
                onClicked: view._expandAll(false)
                PlasmaComponents3.ToolTip.text: i18n("Colapsar todas las tareas")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
            // Toggle search vs. quick-add for the text field below.
            PlasmaComponents3.ToolButton {
                checkable: true
                checked: view._searchMode
                icon.name: "search"
                onToggled: {
                    view._searchMode = checked;
                    entryField.text = "";
                    entryField.forceActiveFocus();
                }
                PlasmaComponents3.ToolTip.text: view._searchMode
                        ? i18n("Volver a «crear tarea rápida»")
                        : i18n("Buscar tareas en esta categoría")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
            PlasmaComponents3.Button {
                icon.name: "document-new"
                text: i18n("New…")
                onClicked: view.newTaskRequested(view.catIndex)
            }
        }

        // Text field: quick-add by default, filter in search mode.
        RowLayout {
            Layout.fillWidth: true
            spacing: PlasmaCore.Units.smallSpacing

            PlasmaCore.IconItem {
                source: view._searchMode ? "search" : "list-add"
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
            }
            PlasmaComponents3.TextField {
                id: entryField
                Layout.fillWidth: true
                placeholderText: view._searchMode
                        ? i18n("Buscar tareas en esta categoría…")
                        : i18n("Nueva tarea rápida… (Enter para crear)")
                onAccepted: view._commitQuickAdd()
                Keys.onEscapePressed: text = ""
            }
            // Search mode: clear button. Quick-add mode: create button.
            PlasmaComponents3.ToolButton {
                visible: view._searchMode && entryField.text.length > 0
                icon.name: "edit-clear"
                onClicked: entryField.text = ""
                PlasmaComponents3.ToolTip.text: i18n("Limpiar búsqueda")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
            PlasmaComponents3.Button {
                visible: !view._searchMode
                icon.name: "list-add"
                text: i18n("Agregar")
                enabled: entryField.text.trim().length > 0
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
                    view: view
                    catColor: cats.color(modelData ? modelData.category : 0)
                    expandSignal: view._expandSeq
                    onEditRequested: view.editTaskRequested(task)
                    onLinkJiraRequested: view.linkJiraRequested(task)
                    onOpenJiraRequested: view.openJiraRequested(task)
                }

                PlasmaComponents3.Label {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    width: parent.width - 40
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: (view._searchMode && entryField.text.length > 0)
                          ? i18n("Ninguna tarea coincide con la búsqueda.")
                          : i18n("No tasks in this category yet. Escribí arriba para crear una.")
                    opacity: 0.55
                }
            }
        }
    }
}
