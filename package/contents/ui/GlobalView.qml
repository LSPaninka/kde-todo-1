/*
 * GlobalView.qml - "Global" tab in the ToDo popup. Lists every task across
 * every category, with a colored bar on the left showing which category it
 * belongs to. Read-only-ish: clicks open the same edit dialogs as the
 * per-category view; quick-add is intentionally absent here (the user picks
 * a real category to create tasks).
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

    signal editTaskRequested(var task)
    signal linkJiraRequested(var task)
    signal openJiraRequested(var task)

    // ----- Persistent expand state (survives store bumps) -----
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
    readonly property var _allTasks: (_v, view._collect())
    readonly property var filtered: view._applyFilter(_allTasks, searchField.text)

    function _collect() {
        if (!store || !store.tasks) return [];
        var n = cats.count();
        var out = [];
        for (var i = 0; i < store.tasks.length; i++) {
            var t = store.tasks[i];
            if ((t.category | 0) < 0 || (t.category | 0) >= n) continue;
            out.push(t);
        }
        // Sort: pending first, then by priority high → low, then by createdAt desc.
        out.sort(function(a, b) {
            if (a.done !== b.done) return a.done ? 1 : -1;
            var pa = cats.priorityRank(a.priority);
            var pb = cats.priorityRank(b.priority);
            if (pa !== pb) return pb - pa;
            return (b.createdAt || 0) - (a.createdAt || 0);
        });
        return out;
    }

    function _applyFilter(arr, q) {
        if (!q || q.trim().length === 0) return arr;
        var needle = q.trim().toLowerCase();
        var out = [];
        for (var i = 0; i < arr.length; i++) {
            var t = arr[i];
            var name = (cats.name(t.category | 0) || "").toLowerCase();
            var hay = ((t.title || "") + " " + (t.description || "") + " " + name).toLowerCase();
            if (hay.indexOf(needle) >= 0) out.push(t);
        }
        return out;
    }

    function _pendingCount() {
        var c = 0;
        for (var i = 0; i < view._allTasks.length; i++) if (!view._allTasks[i].done) c++;
        return c;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: PlasmaCore.Units.smallSpacing

        // Header.
        RowLayout {
            Layout.fillWidth: true

            PlasmaCore.IconItem {
                source: "view-list-tree"
                Layout.preferredWidth: 14
                Layout.preferredHeight: 14
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: i18n("Global — %1 pending of %2",
                           view._pendingCount(), view._allTasks.length)
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
            // Small legend swatches so the user can read the color → category mapping.
            Repeater {
                model: cats.count()
                Rectangle {
                    Layout.preferredWidth: 10
                    Layout.preferredHeight: 10
                    radius: 2
                    color: cats.color(index)
                    border.width: 1
                    border.color: Qt.darker(color, 1.4)
                    PlasmaComponents3.ToolTip.visible: _legendHover.hovered
                    PlasmaComponents3.ToolTip.text: cats.name(index)
                    PlasmaComponents3.ToolTip.delay: 300
                    HoverHandler { id: _legendHover }
                }
            }
        }

        // Search row (filters across categories — also matches the category name).
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
                placeholderText: i18n("Buscar tareas en todas las categorías…")
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
                    view: view
                    catColor: cats.color(modelData ? (modelData.category | 0) : 0)
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
                    text: searchField.text.length > 0
                          ? i18n("Ninguna tarea coincide con la búsqueda.")
                          : i18n("No tasks yet. Crea una en una categoría específica.")
                    opacity: 0.55
                }
            }
        }
    }
}
