/*
 * NotionPageItem.qml - one row in the Notion popup list.
 *
 * Shows the page's title, optional emoji icon, last-edited timestamp, and
 * three actions: edit (opens the title + Markdown editor), open-in-browser
 * (uses xdg-open via Qt.openUrlExternally), and copy-id (handy when piping
 * to other ntn commands).
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: row
    property var page
    height: layout.implicitHeight + PlasmaCore.Units.smallSpacing * 2

    signal editRequested(var page)

    function _formatEdited(iso) {
        if (!iso) return "";
        var d = new Date(iso);
        if (isNaN(d.getTime())) return iso;
        return Qt.formatDateTime(d, Qt.DefaultLocaleShortDate);
    }

    Rectangle {
        anchors.fill: parent
        color: hoverArea.containsMouse
               ? Qt.rgba(PlasmaCore.Theme.highlightColor.r,
                         PlasmaCore.Theme.highlightColor.g,
                         PlasmaCore.Theme.highlightColor.b, 0.10)
               : "transparent"
        radius: 3
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.06)
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: row.editRequested(row.page)
    }

    RowLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: PlasmaCore.Units.smallSpacing
        spacing: PlasmaCore.Units.smallSpacing

        // Emoji icon or generic page icon.
        Item {
            Layout.preferredWidth: 22
            Layout.preferredHeight: 22
            Layout.alignment: Qt.AlignVCenter
            PlasmaCore.IconItem {
                anchors.fill: parent
                source: (row.page && row.page.icon && row.page.icon.indexOf("http") === 0)
                        ? "text-x-generic" : "text-x-generic"
                visible: !emojiLabel.visible
            }
            PlasmaComponents3.Label {
                id: emojiLabel
                anchors.centerIn: parent
                text: (row.page && row.page.icon && row.page.icon.length > 0
                       && row.page.icon.indexOf("http") !== 0) ? row.page.icon : ""
                visible: text.length > 0
                font.pixelSize: 18
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: row.page ? (row.page.title || i18n("(sin título)")) : ""
                font.bold: true
                elide: Text.ElideRight
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                PlasmaComponents3.Label {
                    visible: row.page && row.page.lastEditedTime
                    text: row.page ? i18n("Editada: %1", row._formatEdited(row.page.lastEditedTime)) : ""
                    font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                    opacity: 0.65
                }
                PlasmaComponents3.Label {
                    text: row.page ? "[" + (row.page.id || "").substring(0, 8) + "…]" : ""
                    font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                    opacity: 0.5
                    font.family: "monospace"
                }
                Item { Layout.fillWidth: true }
            }
        }

        PlasmaComponents3.ToolButton {
            icon.name: "edit-entry"
            onClicked: row.editRequested(row.page)
            PlasmaComponents3.ToolTip.text: i18n("Editar título y contenido")
            PlasmaComponents3.ToolTip.visible: hovered
            PlasmaComponents3.ToolTip.delay: 500
        }
        PlasmaComponents3.ToolButton {
            icon.name: "applications-internet"
            visible: row.page && row.page.url
            onClicked: Qt.openUrlExternally(row.page.url)
            PlasmaComponents3.ToolTip.text: i18n("Abrir en Notion (navegador)")
            PlasmaComponents3.ToolTip.visible: hovered
            PlasmaComponents3.ToolTip.delay: 500
        }
        PlasmaComponents3.ToolButton {
            icon.name: "edit-copy"
            onClicked: {
                idCopy.selectAll();
                idCopy.copy();
                idCopy.deselect();
            }
            PlasmaComponents3.ToolTip.text: i18n("Copiar ID de la página")
            PlasmaComponents3.ToolTip.visible: hovered
            PlasmaComponents3.ToolTip.delay: 500
        }

        // Off-screen helper so the ID can be put into the clipboard via
        // TextInput.copy() — there's no global clipboard API in QML 5.
        QQC2.TextField {
            id: idCopy
            visible: false
            width: 0
            text: row.page ? (row.page.id || "") : ""
        }
    }
}
