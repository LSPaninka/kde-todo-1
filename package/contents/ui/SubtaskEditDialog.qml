/*
 * SubtaskEditDialog.qml - edit an existing subtask (title + priority).
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

QQC2.Dialog {
    id: dlg

    property var store
    property int taskId: 0
    property int subId: 0

    title: i18n("Edit subtask")
    modal: true
    standardButtons: QQC2.Dialog.Save | QQC2.Dialog.Cancel
    anchors.centerIn: parent
    width: Math.min(360, (parent ? parent.width : 360) - 40)

    function openFor(task, sub) {
        taskId = task.id;
        subId = sub.id;
        titleField.text = sub.title;
        prioField.value = sub.priority;
        open();
        titleField.forceActiveFocus();
    }

    onAccepted: {
        var t = titleField.text.trim();
        if (t.length === 0) return;
        store.updateSubtask(taskId, subId, {
            title: t,
            priority: prioField.value
        });
    }

    contentItem: ColumnLayout {
        spacing: PlasmaCore.Units.smallSpacing

        PlasmaComponents3.TextField {
            id: titleField
            Layout.fillWidth: true
            placeholderText: i18n("Title")
        }
        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents3.Label { text: i18n("Priority:") }
            PrioritySelector {
                id: prioField
                Layout.fillWidth: true
            }
        }
    }
}
