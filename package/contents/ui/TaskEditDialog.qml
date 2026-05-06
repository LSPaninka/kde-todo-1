/*
 * TaskEditDialog.qml - dialog used to create and edit tasks.
 *
 *   - openNew(categoryIndex) to create a task in that category
 *   - openEdit(taskObject) to edit an existing task
 * On Save, writes back through the TaskStore.
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

    CategoryHelper { id: cats }

    title: editingId === 0 ? i18n("New task") : i18n("Edit task")
    modal: true
    standardButtons: QQC2.Dialog.Save | QQC2.Dialog.Cancel
    anchors.centerIn: parent
    width: Math.min(420, (parent ? parent.width : 420) - 40)

    function openNew(c) {
        editingId = 0;
        catIndex = c;
        titleField.text = "";
        descField.text = "";
        prioField.value = "M";
        catCombo.currentIndex = c;
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
        open();
        titleField.forceActiveFocus();
    }

    onAccepted: {
        var t = titleField.text.trim();
        if (t.length === 0) return;
        if (editingId === 0) {
            store.addTask(t, catCombo.currentIndex, prioField.value, descField.text);
        } else {
            store.updateTask(editingId, {
                title: t,
                description: descField.text,
                category: catCombo.currentIndex,
                priority: prioField.value
            });
        }
    }

    contentItem: ColumnLayout {
        spacing: PlasmaCore.Units.smallSpacing

        PlasmaComponents3.Label { text: i18n("Title") }
        PlasmaComponents3.TextField {
            id: titleField
            Layout.fillWidth: true
            placeholderText: i18n("What do you need to do?")
        }

        PlasmaComponents3.Label { text: i18n("Description (optional)") }
        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            QQC2.TextArea {
                id: descField
                wrapMode: TextEdit.WordWrap
            }
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
                Layout.preferredWidth: 100
                PlasmaComponents3.Label { text: i18n("Priority") }
                PrioritySelector {
                    id: prioField
                    Layout.fillWidth: true
                    value: "M"
                }
            }
        }
    }
}
