/*
 * ImportDialog.qml - paste-in JSON to bulk-create tasks in a category.
 *
 * Accepts either:
 *   - The format produced by ExportDialog: { schema, tasks: [...] }
 *   - A bare array of task objects: [ {...}, {...} ]
 *
 * Each imported task gets a fresh id and is forced into the current
 * category, regardless of the value stored in the JSON.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

QQC2.Dialog {
    id: dlg

    property var store
    property int catIndex: 0
    property string categoryName: ""

    title: i18n("Import — %1", categoryName)
    modal: true
    standardButtons: QQC2.Dialog.NoButton
    anchors.centerIn: parent
    width: Math.min(520, (parent ? parent.width : 520) - 40)
    height: Math.min(420, (parent ? parent.height : 420) - 40)

    function openFor(c, name) {
        catIndex = c;
        categoryName = name;
        textArea.text = "";
        statusLabel.text = "";
        statusLabel.color = PlasmaCore.Theme.textColor;
        open();
        textArea.forceActiveFocus();
    }

    contentItem: ColumnLayout {
        spacing: PlasmaCore.Units.smallSpacing

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: i18n("Paste a JSON payload below. Imported tasks are added "
                     + "to \"%1\" as new entries (their ids are regenerated).",
                       dlg.categoryName)
            wrapMode: Text.WordWrap
            opacity: 0.75
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            QQC2.TextArea {
                id: textArea
                wrapMode: TextEdit.NoWrap
                font.family: "monospace"
                selectByMouse: true
                placeholderText: i18n('{ "schema": "categorizedtodo.v1", "tasks": [ … ] }')
            }
        }

        PlasmaComponents3.Label {
            id: statusLabel
            Layout.fillWidth: true
            text: ""
            wrapMode: Text.WordWrap
            font.italic: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: PlasmaCore.Units.smallSpacing

            PlasmaComponents3.Button {
                icon.name: "edit-paste"
                text: i18n("Paste from clipboard")
                onClicked: {
                    textArea.clear();
                    textArea.paste();
                }
            }

            Item { Layout.fillWidth: true }

            PlasmaComponents3.Button {
                text: i18n("Cancel")
                onClicked: dlg.close()
            }

            PlasmaComponents3.Button {
                icon.name: "document-import"
                text: i18n("Import")
                highlighted: true
                onClicked: {
                    var txt = textArea.text;
                    if (!txt || txt.trim().length === 0) {
                        statusLabel.color = PlasmaCore.Theme.negativeTextColor;
                        statusLabel.text = i18n("Please paste a JSON payload first.");
                        return;
                    }
                    try {
                        var n = store.importCategoryJson(dlg.catIndex, txt);
                        statusLabel.color = PlasmaCore.Theme.positiveTextColor;
                        statusLabel.text = i18np("Imported %1 task.",
                                                 "Imported %1 tasks.", n);
                        // Close after a short delay so the user sees the result.
                        closeTimer.start();
                    } catch (err) {
                        statusLabel.color = PlasmaCore.Theme.negativeTextColor;
                        statusLabel.text = i18n("Import failed: %1", err.message);
                    }
                }
            }
        }
    }

    Timer {
        id: closeTimer
        interval: 700
        repeat: false
        onTriggered: dlg.close()
    }
}
