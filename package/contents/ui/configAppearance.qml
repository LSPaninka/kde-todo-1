/*
 * configAppearance.qml - Appearance tab of the configuration dialog.
 *
 * Controls the compact (panel) representation:
 *   - whether to show category names next to counters
 *   - whether to show categories with zero pending tasks
 *   - the counter style: number to the right of the swatch, or inside it
 *   - per-category text color for the counter (white or black)
 *
 * RadioButtons are grouped via ButtonGroup so toggling one automatically
 * unchecks the other and the bindings stay consistent.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import org.kde.kirigami 2.5 as Kirigami

ColumnLayout {
    id: page
    spacing: Kirigami.Units.largeSpacing

    // Auto-bound to KCfg entries:
    property alias  cfg_panelShowLabels: showLabelsCheck.checked
    property alias  cfg_panelShowZero:   showZeroCheck.checked
    property string cfg_panelCounterStyle: "right"
    property var    cfg_panelCounterColors: []

    readonly property var _defaultCounterColors: ["white", "black", "white", "white"]
    readonly property var _defaultNames:  ["Personal", "Trabajo", "Estudio", "Otros"]
    readonly property var _defaultColors: ["#2ecc71", "#f1c40f", "#3498db", "#e74c3c"]

    function _counterColor(i) {
        var v = (cfg_panelCounterColors || [])[i];
        return (v === "black") ? "black" : "white";
    }
    function _setCounterColor(i, v) {
        var arr = (cfg_panelCounterColors || []).slice();
        while (arr.length < 4) arr.push(_defaultCounterColors[arr.length]);
        arr[i] = v;
        cfg_panelCounterColors = arr;
    }
    function _categoryName(i) {
        var arr = plasmoid.configuration.categoryNames || [];
        return arr[i] || _defaultNames[i];
    }
    function _categoryColor(i) {
        var arr = plasmoid.configuration.categoryColors || [];
        return arr[i] || _defaultColors[i];
    }

    ButtonGroup { id: styleGroup }

    GroupBox {
        Layout.fillWidth: true
        title: i18n("Counter layout")

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            RadioButton {
                ButtonGroup.group: styleGroup
                text: i18n("Number to the right of the colored square")
                checked: page.cfg_panelCounterStyle === "right"
                onToggled: if (checked) page.cfg_panelCounterStyle = "right"
            }
            RadioButton {
                ButtonGroup.group: styleGroup
                text: i18n("Number inside the colored square (bigger swatch)")
                checked: page.cfg_panelCounterStyle === "inside"
                onToggled: if (checked) page.cfg_panelCounterStyle = "inside"
            }
        }
    }

    GroupBox {
        Layout.fillWidth: true
        title: i18n("Counter text color (per category)")

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: 4
                delegate: RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    ButtonGroup { id: colorGroup }

                    // Mini preview mimicking the panel swatch.
                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 22
                        radius: 3
                        color: page._categoryColor(index)
                        border.width: 1
                        border.color: Qt.darker(color, 1.4)
                        Text {
                            anchors.centerIn: parent
                            text: "9"
                            color: ((page.cfg_panelCounterColors || [])[index] === "black")
                                   ? "black" : "white"
                            font.bold: true
                            font.pixelSize: 14
                        }
                    }

                    Label {
                        Layout.preferredWidth: 120
                        text: page._categoryName(index)
                        elide: Text.ElideRight
                    }

                    RadioButton {
                        ButtonGroup.group: colorGroup
                        text: i18n("White")
                        checked: ((page.cfg_panelCounterColors || [])[index] || "white") !== "black"
                        onToggled: if (checked) page._setCounterColor(index, "white")
                    }
                    RadioButton {
                        ButtonGroup.group: colorGroup
                        text: i18n("Black")
                        checked: ((page.cfg_panelCounterColors || [])[index] || "white") === "black"
                        onToggled: if (checked) page._setCounterColor(index, "black")
                    }

                    Item { Layout.fillWidth: true }
                }
            }

            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: i18n("Pick the color that contrasts best with each category's color.")
            }
        }
    }

    GroupBox {
        Layout.fillWidth: true
        title: i18n("Visibility")

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            CheckBox {
                id: showLabelsCheck
                text: i18n("Show category names next to counters")
            }
            CheckBox {
                id: showZeroCheck
                text: i18n("Show categories with zero pending tasks")
            }
        }
    }

    Label {
        Layout.fillWidth: true
        Layout.preferredWidth: 360
        wrapMode: Text.WordWrap
        opacity: 0.65
        text: i18n("The panel representation always shows a colored square per "
                 + "category followed by the number of pending tasks, laid out "
                 + "horizontally. For example: [green] 1  [yellow] 3  [blue] 5  [red] 0")
    }

    Item { Layout.fillHeight: true }
}
