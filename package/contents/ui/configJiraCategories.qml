/*
 * configJiraCategories.qml - "Categorías Jira" tab of the configuration
 * dialog.
 *
 * For each of the up-to-4 categories the user can pick:
 *   - name (display label)
 *   - color (with native ColorDialog)
 *   - text color for the panel swatch (white | black)
 *   - filter: a Jira field (issuetype / statusCategory / status / priority)
 *             plus a value (semicolon-separated for OR matching).
 *
 * The active count is configured separately in the General tab. All 4
 * slots are kept in storage so changing the count doesn't lose data.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import QtQuick.Dialogs 1.3 as Dialogs
import org.kde.kirigami 2.5 as Kirigami

ColumnLayout {
    id: page
    spacing: Kirigami.Units.largeSpacing

    // KCfg-bound StringLists.
    property var cfg_jiraCategoryNames: []
    property var cfg_jiraCategoryColors: []
    property var cfg_jiraCategoryTextColors: []
    property var cfg_jiraCategoryFilterFields: []
    property var cfg_jiraCategoryFilterValues: []

    readonly property var _defaultNames:        ["Por hacer", "En curso", "Hechas", "Otras"]
    readonly property var _defaultColors:       ["#42526e", "#f5a623", "#2ecc71", "#9b59b6"]
    readonly property var _defaultTextColors:   ["white", "white", "white", "white"]
    readonly property var _defaultFilterFields: ["statusCategory", "statusCategory", "statusCategory", ""]
    readonly property var _defaultFilterValues: ["new", "indeterminate", "done", ""]

    // The dropdown options. Internal value vs. display label.
    readonly property var _filterFieldOptions: [
        { value: "",               label: i18n("(sin filtro — todas)") },
        { value: "statusCategory", label: i18n("Categoría de estado (To Do / In Progress / Done)") },
        { value: "status",         label: i18n("Estado (nombre exacto)") },
        { value: "issuetype",      label: i18n("Tipo de incidencia (Story, Bug, Task, Sub-task…)") },
        { value: "priority",       label: i18n("Prioridad") }
    ]

    function _name(i)          { var v = (cfg_jiraCategoryNames        || [])[i]; return v !== undefined ? v : _defaultNames[i]; }
    function _color(i)         { var v = (cfg_jiraCategoryColors       || [])[i]; return v !== undefined ? v : _defaultColors[i]; }
    function _textColor(i)     { var v = (cfg_jiraCategoryTextColors   || [])[i]; return v !== undefined ? v : _defaultTextColors[i]; }
    function _filterField(i)   { var v = (cfg_jiraCategoryFilterFields || [])[i]; return v !== undefined ? v : _defaultFilterFields[i]; }
    function _filterValue(i)   { var v = (cfg_jiraCategoryFilterValues || [])[i]; return v !== undefined ? v : _defaultFilterValues[i]; }

    function _setListItem(getter, fallback, i, value) {
        var arr = (getter() || []).slice();
        while (arr.length < 4) arr.push(fallback[arr.length]);
        arr[i] = value;
        return arr;
    }

    Label {
        Layout.fillWidth: true
        Layout.preferredWidth: 600
        wrapMode: Text.WordWrap
        opacity: 0.75
        text: i18n("Cada categoría representa una pestaña en el popup y un cuadrado en el panel cuando "
                 + "el modo es «Jira». La cantidad activa se ajusta en la pestaña «General». Para que "
                 + "una categoría haga match con varias opciones, separá los valores con punto y coma "
                 + "(por ejemplo «In Progress; Code Review»).")
    }

    Repeater {
        model: 4
        delegate: GroupBox {
            Layout.fillWidth: true
            title: i18n("Categoría #%1", index + 1)

            ColumnLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                // Row 1: name + color + text color
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Label { text: i18n("Nombre:") }
                    TextField {
                        id: nameField
                        Layout.fillWidth: true
                        text: page._name(index)
                        onEditingFinished: {
                            page.cfg_jiraCategoryNames =
                                page._setListItem(function() { return page.cfg_jiraCategoryNames; },
                                                  page._defaultNames, index, text);
                        }
                    }

                    Rectangle {
                        id: swatch
                        width: 28
                        height: 22
                        radius: 3
                        color: page._color(index)
                        border.color: Qt.darker(color, 1.5)
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "9"
                            color: page._textColor(index)
                            font.bold: true
                            font.pixelSize: 14
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { colorDlg.targetIndex = index; colorDlg.color = swatch.color; colorDlg.open(); }
                        }
                    }

                    Button {
                        text: i18n("Color…")
                        onClicked: { colorDlg.targetIndex = index; colorDlg.color = swatch.color; colorDlg.open(); }
                    }

                    ButtonGroup { id: textGroup }
                    RadioButton {
                        ButtonGroup.group: textGroup
                        text: i18n("Letra blanca")
                        checked: page._textColor(index) !== "black"
                        onToggled: if (checked) {
                            page.cfg_jiraCategoryTextColors =
                                page._setListItem(function() { return page.cfg_jiraCategoryTextColors; },
                                                  page._defaultTextColors, index, "white");
                        }
                    }
                    RadioButton {
                        ButtonGroup.group: textGroup
                        text: i18n("Negra")
                        checked: page._textColor(index) === "black"
                        onToggled: if (checked) {
                            page.cfg_jiraCategoryTextColors =
                                page._setListItem(function() { return page.cfg_jiraCategoryTextColors; },
                                                  page._defaultTextColors, index, "black");
                        }
                    }
                }

                // Row 2: filter field + filter value
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Label { text: i18n("Filtrar por:") }
                    ComboBox {
                        id: fieldCombo
                        Layout.preferredWidth: 320
                        textRole: "label"
                        valueRole: "value"
                        model: page._filterFieldOptions
                        currentIndex: {
                            var f = page._filterField(index);
                            for (var k = 0; k < page._filterFieldOptions.length; k++) {
                                if (page._filterFieldOptions[k].value === f) return k;
                            }
                            return 0;
                        }
                        onActivated: {
                            var v = page._filterFieldOptions[currentIndex].value;
                            page.cfg_jiraCategoryFilterFields =
                                page._setListItem(function() { return page.cfg_jiraCategoryFilterFields; },
                                                  page._defaultFilterFields, index, v);
                        }
                    }

                    Label { text: i18n("Valor:") }
                    TextField {
                        Layout.fillWidth: true
                        enabled: fieldCombo.currentIndex !== 0
                        text: page._filterValue(index)
                        placeholderText: {
                            switch (page._filterField(index)) {
                                case "statusCategory": return i18n("new ; indeterminate ; done");
                                case "status":         return i18n("To Do ; In Progress ; Code Review");
                                case "issuetype":      return i18n("Story ; Sub-task ; Bug");
                                case "priority":       return i18n("Highest ; High ; Medium");
                            }
                            return i18n("(separá con ; para OR)");
                        }
                        onEditingFinished: {
                            page.cfg_jiraCategoryFilterValues =
                                page._setListItem(function() { return page.cfg_jiraCategoryFilterValues; },
                                                  page._defaultFilterValues, index, text);
                        }
                    }
                }
            }
        }
    }

    Item { Layout.fillHeight: true }

    Dialogs.ColorDialog {
        id: colorDlg
        property int targetIndex: 0
        title: i18n("Pick a color")
        onAccepted: {
            page.cfg_jiraCategoryColors =
                page._setListItem(function() { return page.cfg_jiraCategoryColors; },
                                  page._defaultColors, targetIndex, color.toString());
        }
    }
}
