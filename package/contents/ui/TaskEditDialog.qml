/*
 * TaskEditDialog.qml - dialog used to create and edit tasks, including their
 * subtasks (subtasks are edited here now, not inline in the list).
 *
 *   - openNew(categoryIndex) to create a task in that category
 *   - openEdit(taskObject) to edit an existing task
 * On Save, writes the task and its whole subtask list back through TaskStore.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

QQC2.Dialog {
    id: dlg

    property var store
    property int editingId: 0      // 0 => creating new
    property int catIndex: 0

    // Working copy of the subtasks being edited. Each entry:
    //   { id (0 = new), title, priority, done }
    property var _subs: []
    property int _subsRev: 0

    CategoryHelper { id: cats }

    title: editingId === 0 ? i18n("New task") : i18n("Edit task")
    modal: true
    standardButtons: QQC2.Dialog.Save | QQC2.Dialog.Cancel
    anchors.centerIn: parent
    width: Math.min(560, (parent ? parent.width : 560) - 32)
    height: Math.min(560, (parent ? parent.height : 560) - 32)

    function _resetSubs(arr) {
        var out = [];
        for (var i = 0; i < (arr ? arr.length : 0); i++) {
            var s = arr[i];
            out.push({ id: s.id || 0, title: s.title || "",
                       priority: s.priority || cats.defaultPriority(),
                       done: !!s.done });
        }
        _subs = out;
        _subsRev++;
    }

    function _addSub() {
        var arr = _subs.slice();
        arr.push({ id: 0, title: "", priority: cats.defaultPriority(), done: false });
        _subs = arr;
        _subsRev++;
    }
    function _removeSub(i) {
        var arr = _subs.slice();
        arr.splice(i, 1);
        _subs = arr;
        _subsRev++;
    }
    function _setSubTitle(i, v)    { if (_subs[i]) _subs[i].title = v; }
    function _setSubPriority(i, v) { if (_subs[i]) _subs[i].priority = v; }

    function openNew(c) {
        editingId = 0;
        catIndex = c;
        titleField.text = "";
        descField.text = "";
        prioField.value = cats.defaultPriority();
        catCombo.currentIndex = c;
        _resetSubs([]);
        bodyScroll.contentItem.contentY = 0;
        open();
        titleField.forceActiveFocus();
    }

    function openEdit(task) {
        editingId = task.id;
        catIndex = task.category;
        titleField.text = task.title;
        descField.text = task.description;
        prioField.value = task.priority;
        catCombo.currentIndex = task.category;
        _resetSubs(task.subtasks || []);
        bodyScroll.contentItem.contentY = 0;
        open();
        titleField.forceActiveFocus();
    }

    onAccepted: {
        var t = titleField.text.trim();
        if (t.length === 0) return;
        var id = editingId;
        if (editingId === 0) {
            id = store.addTask(t, catCombo.currentIndex, prioField.value, descField.text);
        } else {
            store.updateTask(editingId, {
                title: t,
                description: descField.text,
                category: catCombo.currentIndex,
                priority: prioField.value
            });
        }
        store.setTaskSubtasks(id, _subs);
    }

    // Plain Item wrapper so the ColumnLayout keeps its full height on reopen
    // (a bare ColumnLayout as contentItem collapses to its implicit height).
    contentItem: Item {
        ColumnLayout {
            anchors.fill: parent
            spacing: PlasmaCore.Units.smallSpacing

            PlasmaComponents3.Label { text: i18n("Title") }
            PlasmaComponents3.TextField {
                id: titleField
                Layout.fillWidth: true
                placeholderText: i18n("What do you need to do?")
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: PlasmaCore.Units.smallSpacing

                ColumnLayout {
                    Layout.fillWidth: true
                    PlasmaComponents3.Label { text: i18n("Category") }
                    PlasmaComponents3.ComboBox {
                        id: catCombo
                        Layout.fillWidth: true
                        model: {
                            var n = cats.count();
                            var out = [];
                            for (var i = 0; i < n; i++) out.push(cats.name(i));
                            return out;
                        }
                    }
                }

                ColumnLayout {
                    Layout.preferredWidth: 110
                    PlasmaComponents3.Label { text: i18n("Priority") }
                    PrioritySelector {
                        id: prioField
                        Layout.fillWidth: true
                    }
                }
            }

            PlasmaComponents3.Label { text: i18n("Description (optional)") }
            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                QQC2.TextArea {
                    id: descField
                    wrapMode: TextEdit.WordWrap
                }
            }

            // -------- Subtasks --------
            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents3.Label {
                    text: i18n("Subtasks")
                    font.bold: true
                    Layout.fillWidth: true
                }
                PlasmaComponents3.Button {
                    icon.name: "list-add"
                    text: i18n("Agregar subtarea")
                    onClicked: dlg._addSub()
                }
            }

            QQC2.ScrollView {
                id: bodyScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    width: bodyScroll.availableWidth
                    spacing: PlasmaCore.Units.smallSpacing

                    Repeater {
                        model: (dlg._subsRev, dlg._subs.length)
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            spacing: PlasmaCore.Units.smallSpacing
                            property int subIndex: index

                            PlasmaComponents3.TextField {
                                Layout.fillWidth: true
                                text: dlg._subs[subIndex] ? dlg._subs[subIndex].title : ""
                                placeholderText: i18n("Subtask title…")
                                onTextChanged: dlg._setSubTitle(subIndex, text)
                            }
                            PrioritySelector {
                                Layout.preferredWidth: 100
                                value: dlg._subs[subIndex] ? dlg._subs[subIndex].priority : cats.defaultPriority()
                                onValueChanged: dlg._setSubPriority(subIndex, value)
                            }
                            PlasmaComponents3.ToolButton {
                                icon.name: "list-remove"
                                onClicked: dlg._removeSub(subIndex)
                                PlasmaComponents3.ToolTip.text: i18n("Remove subtask")
                                PlasmaComponents3.ToolTip.visible: hovered
                                PlasmaComponents3.ToolTip.delay: 500
                            }
                        }
                    }

                    PlasmaComponents3.Label {
                        visible: (dlg._subsRev, dlg._subs.length === 0)
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: i18n("Sin subtareas. Usá «Agregar subtarea».")
                        opacity: 0.55
                        font.italic: true
                    }
                }
            }
        }
    }
}
