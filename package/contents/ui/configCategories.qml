/*
 * configCategories.qml - Categories tab of the configuration dialog.
 *
 * Lets the user rename each of the 4 categories and pick a color. Only the
 * first `cfg_categoryCount` are actually used by the rest of the plasmoid,
 * but all 4 slots are kept so changing the count doesn't lose data.
 *
 * The category lists are stored in the config as StringList (comma-joined
 * values under the hood). We bind them as whole arrays via the cfg_ alias.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import QtQuick.Dialogs 1.3 as Dialogs
import org.kde.kirigami 2.5 as Kirigami

ColumnLayout {
    id: page
    spacing: Kirigami.Units.largeSpacing

    // These are auto-synced with categoryNames/categoryColors in main.xml.
    property var cfg_categoryNames: []
    property var cfg_categoryColors: []

    // Fallbacks, so the UI always renders exactly 7 rows.
    readonly property var _defaultNames:  ["Personal", "Trabajo", "Estudio", "Otros", "Salud", "Hogar", "Hobbies"]
    readonly property var _defaultColors: ["#2ecc71", "#f1c40f", "#3498db", "#e74c3c", "#9b59b6", "#1abc9c", "#e67e22"]

    function _name(i)  { return (cfg_categoryNames[i]  !== undefined) ? cfg_categoryNames[i]  : _defaultNames[i]; }
    function _color(i) { return (cfg_categoryColors[i] !== undefined) ? cfg_categoryColors[i] : _defaultColors[i]; }

    function _setName(i, v) {
        var arr = cfg_categoryNames.slice();
        while (arr.length < 7) arr.push(_defaultNames[arr.length]);
        arr[i] = v;
        cfg_categoryNames = arr;
    }

    function _setColor(i, v) {
        var arr = cfg_categoryColors.slice();
        while (arr.length < 7) arr.push(_defaultColors[arr.length]);
        arr[i] = v;
        cfg_categoryColors = arr;
    }

    Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: i18n("Configure up to 7 categories. Each category has a name and a color. "
                 + "The number of active categories is set in the General tab.")
        opacity: 0.75
    }

    Repeater {
        model: 7
        delegate: RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Label {
                text: i18n("#%1", index + 1)
                Layout.preferredWidth: 24
            }

            TextField {
                id: nameField
                Layout.fillWidth: true
                text: page._name(index)
                onEditingFinished: page._setName(index, text)
            }

            Rectangle {
                id: swatch
                width: 28
                height: 28
                radius: 4
                border.color: Qt.darker(color, 1.5)
                border.width: 1
                color: page._color(index)

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        colorDlg.targetIndex = index;
                        colorDlg.color = swatch.color;
                        colorDlg.open();
                    }
                }
            }

            Button {
                text: i18n("Pick…")
                onClicked: {
                    colorDlg.targetIndex = index;
                    colorDlg.color = swatch.color;
                    colorDlg.open();
                }
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
