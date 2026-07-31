/*
 * configPriorities.qml - "Prioridades" tab of the configuration dialog.
 *
 * Lets the user edit the priority scale: the letters (any text), their color,
 * and how many there are (add / remove rows). Ordered lowest → highest.
 *
 * priorityLevels / priorityColors are StringLists; we read/write
 * plasmoid.configuration directly (reassigning a `var` StringList alias does
 * not persist reliably on the target Plasma).
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import QtQuick.Dialogs 1.3 as Dialogs
import org.kde.kirigami 2.5 as Kirigami

ColumnLayout {
    id: page
    spacing: Kirigami.Units.largeSpacing

    property int _rev: 0

    readonly property var _fallbackLevels: ["XS", "S", "M", "L", "XL"]
    readonly property var _fallbackColors: ["#95a5a6", "#3498db", "#2ecc71", "#f39c12", "#e74c3c"]

    function _levels() {
        var a = (page._rev, plasmoid.configuration.priorityLevels || []);
        return (a && a.length > 0) ? a.slice() : _fallbackLevels.slice();
    }
    function _colors() {
        var a = (page._rev, plasmoid.configuration.priorityColors || []);
        return a ? a.slice() : [];
    }
    function _colorAt(i) {
        var c = _colors();
        if (c[i] && ("" + c[i]).length > 0) return c[i];
        return _fallbackColors[i % _fallbackColors.length];
    }

    function _commit(levels, colors) {
        plasmoid.configuration.priorityLevels = levels;
        plasmoid.configuration.priorityColors = colors;
        page._rev++;
    }

    function _setLevel(i, v) {
        var lv = _levels(); var co = _colors();
        while (co.length < lv.length) co.push(_colorAt(co.length));
        lv[i] = v;
        _commit(lv, co);
    }
    function _setColor(i, v) {
        var lv = _levels(); var co = _colors();
        while (co.length < lv.length) co.push(_colorAt(co.length));
        co[i] = v;
        _commit(lv, co);
    }
    function _addLevel() {
        var lv = _levels(); var co = _colors();
        while (co.length < lv.length) co.push(_colorAt(co.length));
        lv.push("N" + (lv.length + 1));
        co.push(_fallbackColors[lv.length % _fallbackColors.length]);
        _commit(lv, co);
    }
    function _removeLevel(i) {
        var lv = _levels(); var co = _colors();
        while (co.length < lv.length) co.push(_colorAt(co.length));
        if (lv.length <= 1) return;   // keep at least one level
        lv.splice(i, 1);
        co.splice(i, 1);
        _commit(lv, co);
    }

    Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.75
        text: i18n("Definí las etiquetas de prioridad, de menor (arriba) a mayor (abajo). "
                 + "Podés cambiar el texto, el color y la cantidad. El orden determina el "
                 + "peso al ordenar la vista Global.")
    }

    Repeater {
        model: (page._rev, page._levels().length)
        delegate: RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Label {
                text: i18n("#%1", index + 1)
                Layout.preferredWidth: 28
            }

            TextField {
                Layout.preferredWidth: 90
                text: page._levels()[index]
                onEditingFinished: page._setLevel(index, text)
            }

            Rectangle {
                id: swatch
                width: 28
                height: 28
                radius: 4
                border.color: Qt.darker(color, 1.5)
                border.width: 1
                color: page._colorAt(index)

                // Preview letter in white, like the real badge.
                Label {
                    anchors.centerIn: parent
                    text: page._levels()[index]
                    color: "white"
                    font.bold: true
                    font.pixelSize: 10
                }

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
                text: i18n("Color…")
                onClicked: {
                    colorDlg.targetIndex = index;
                    colorDlg.color = swatch.color;
                    colorDlg.open();
                }
            }

            Item { Layout.fillWidth: true }

            ToolButton {
                icon.name: "list-remove"
                enabled: page._levels().length > 1
                onClicked: page._removeLevel(index)
                ToolTip.text: i18n("Quitar esta prioridad")
                ToolTip.visible: hovered
                ToolTip.delay: 500
            }
        }
    }

    Button {
        text: i18n("Agregar prioridad")
        icon.name: "list-add"
        onClicked: page._addLevel()
    }

    Item { Layout.fillHeight: true }

    Dialogs.ColorDialog {
        id: colorDlg
        property int targetIndex: 0
        title: i18n("Elegí un color")
        onAccepted: page._setColor(targetIndex, color.toString())
    }
}
