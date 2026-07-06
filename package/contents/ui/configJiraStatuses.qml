/*
 * configJiraStatuses.qml - "Estados Jira" tab of the configuration dialog.
 *
 * Lets the user override the color of the status chip that appears on the
 * right of each Jira issue, per status name. Up to 10 name→color pairs are
 * stored in the parallel StringLists jiraStatusNames / jiraStatusColors.
 * Empty rows are ignored; unmatched statuses keep Jira's own color.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import QtQuick.Dialogs 1.3 as Dialogs
import org.kde.kirigami 2.5 as Kirigami

ColumnLayout {
    id: page
    spacing: Kirigami.Units.largeSpacing

    // Read/write plasmoid.configuration directly — reassigning a standalone
    // `var` StringList does not persist reliably through Apply (Plasma quirk).
    readonly property int _slots: 10
    readonly property string _defaultColor: "#3498db"
    property int _rev: 0

    function _name(i)  { var v = (page._rev, plasmoid.configuration.jiraStatusNames  || [])[i]; return v !== undefined ? v : ""; }
    function _color(i) { var v = (page._rev, plasmoid.configuration.jiraStatusColors || [])[i]; return (v !== undefined && v !== "") ? v : _defaultColor; }

    function _setName(i, value) {
        var arr = (plasmoid.configuration.jiraStatusNames || []).slice();
        while (arr.length < _slots) arr.push("");
        arr[i] = value;
        plasmoid.configuration.jiraStatusNames = arr;
        page._rev++;
    }
    function _setColor(i, value) {
        var arr = (plasmoid.configuration.jiraStatusColors || []).slice();
        while (arr.length < _slots) arr.push("");
        arr[i] = value;
        plasmoid.configuration.jiraStatusColors = arr;
        page._rev++;
    }

    Label {
        Layout.fillWidth: true
        Layout.preferredWidth: 600
        wrapMode: Text.WordWrap
        opacity: 0.75
        text: i18n("Asigná un color a la etiqueta de estado (la que aparece a la derecha de cada "
                 + "incidencia) según el nombre exacto del estado en Jira, por ejemplo «En curso», "
                 + "«Test QA» o «Done». Los estados sin una fila acá conservan el color que define "
                 + "Jira. El nombre no distingue mayúsculas.")
    }

    Repeater {
        model: page._slots
        delegate: RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Label {
                Layout.preferredWidth: 24
                text: (index + 1) + "."
                opacity: 0.6
            }

            TextField {
                Layout.fillWidth: true
                text: page._name(index)
                placeholderText: i18n("Nombre del estado (ej: En curso)")
                onEditingFinished: page._setName(index, text)
            }

            // Preview chip using the configured color.
            Rectangle {
                Layout.preferredWidth: 90
                Layout.preferredHeight: 22
                radius: 4
                color: page._color(index)
                Text {
                    anchors.centerIn: parent
                    text: page._name(index) || i18n("estado")
                    color: "white"
                    font.bold: true
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    width: parent.width - 8
                    horizontalAlignment: Text.AlignHCenter
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { colorDlg.targetIndex = index; colorDlg.color = page._color(index); colorDlg.open(); }
                }
            }

            Button {
                text: i18n("Color…")
                onClicked: { colorDlg.targetIndex = index; colorDlg.color = page._color(index); colorDlg.open(); }
            }
        }
    }

    Item { Layout.fillHeight: true }

    Dialogs.ColorDialog {
        id: colorDlg
        property int targetIndex: 0
        title: i18n("Pick a color")
        onAccepted: page._setColor(targetIndex, color.toString())
    }
}
