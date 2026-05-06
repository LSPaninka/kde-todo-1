/*
 * ExportDialog.qml - shows the JSON payload of one category in a read-only
 * text area. The user can copy it to the clipboard or save it manually.
 *
 * Pure-QML, no external dependencies: clipboard is reached via the standard
 * TextEdit.copy() shortcut after selecting all the text.
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

    title: i18n("Export — %1", categoryName)
    modal: true
    standardButtons: QQC2.Dialog.Close
    anchors.centerIn: parent
    width: Math.min(520, (parent ? parent.width : 520) - 40)
    height: Math.min(420, (parent ? parent.height : 420) - 40)

    function openFor(c, name) {
        catIndex = c;
        categoryName = name;
        textArea.text = store.exportCategoryJson(c);
        statusLabel.text = "";
        open();
        // Select the whole content so Ctrl+C just works.
        textArea.selectAll();
        textArea.forceActiveFocus();
    }

    contentItem: ColumnLayout {
        spacing: PlasmaCore.Units.smallSpacing

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: i18n("This is the JSON representation of all tasks in this "
                     + "category. Copy it to share, back up or move tasks.")
            wrapMode: Text.WordWrap
            opacity: 0.75
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            QQC2.TextArea {
                id: textArea
                readOnly: true
                wrapMode: TextEdit.NoWrap
                font.family: "monospace"
                selectByMouse: true
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: PlasmaCore.Units.smallSpacing

            PlasmaComponents3.Button {
                icon.name: "edit-copy"
                text: i18n("Copy to clipboard")
                onClicked: {
                    textArea.selectAll();
                    textArea.copy();
                    statusLabel.text = i18n("Copied to clipboard.");
                }
            }

            PlasmaComponents3.Label {
                id: statusLabel
                Layout.fillWidth: true
                text: ""
                opacity: 0.65
                font.italic: true
            }
        }
    }
}
