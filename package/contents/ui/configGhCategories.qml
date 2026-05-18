/*
 * configGhCategories.qml - "Categorías GH" tab of the configuration
 * dialog. Mirrors configJiraCategories.qml but for the GitHub Projects
 * StringList entries (ghCategory*).
 *
 * Available filter fields:
 *   - status: matches the value of the project's Status single-select
 *             field (the field name is set in the "GitHub" tab via
 *             ghStatusField; defaults to "Status").
 *   - type:   "Issue" / "PullRequest" / "DraftIssue".
 *   - state:  "OPEN" / "CLOSED" / "MERGED" / "DRAFT".
 *   - repo:   "owner/name" exact match.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import QtQuick.Dialogs 1.3 as Dialogs
import org.kde.kirigami 2.5 as Kirigami

ColumnLayout {
    id: page
    spacing: Kirigami.Units.largeSpacing

    property var cfg_ghCategoryNames: []
    property var cfg_ghCategoryColors: []
    property var cfg_ghCategoryTextColors: []
    property var cfg_ghCategoryFilterFields: []
    property var cfg_ghCategoryFilterValues: []

    readonly property var _defaultNames:        ["Todo", "In Progress", "Done", "Otras"]
    readonly property var _defaultColors:       ["#6e7681", "#d29922", "#238636", "#8957e5"]
    readonly property var _defaultTextColors:   ["white", "white", "white", "white"]
    readonly property var _defaultFilterFields: ["status", "status", "status", ""]
    readonly property var _defaultFilterValues: ["Todo", "In Progress", "Done", ""]

    readonly property var _filterFieldOptions: [
        { value: "",       label: i18n("(sin filtro — todos)") },
        { value: "status", label: i18n("Status (campo single-select del proyecto)") },
        { value: "type",   label: i18n("Tipo (Issue / PullRequest / DraftIssue)") },
        { value: "state",  label: i18n("Estado (OPEN / CLOSED / MERGED / DRAFT)") },
        { value: "repo",   label: i18n("Repositorio (owner/name)") }
    ]

    function _name(i)          { var v = (cfg_ghCategoryNames        || [])[i]; return v !== undefined ? v : _defaultNames[i]; }
    function _color(i)         { var v = (cfg_ghCategoryColors       || [])[i]; return v !== undefined ? v : _defaultColors[i]; }
    function _textColor(i)     { var v = (cfg_ghCategoryTextColors   || [])[i]; return v !== undefined ? v : _defaultTextColors[i]; }
    function _filterField(i)   { var v = (cfg_ghCategoryFilterFields || [])[i]; return v !== undefined ? v : _defaultFilterFields[i]; }
    function _filterValue(i)   { var v = (cfg_ghCategoryFilterValues || [])[i]; return v !== undefined ? v : _defaultFilterValues[i]; }

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
                 + "el modo es «GitHub Projects». La cantidad activa se ajusta en la pestaña «GitHub». "
                 + "Para que una categoría haga match con varios valores, separá con punto y coma "
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

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Label { text: i18n("Nombre:") }
                    TextField {
                        Layout.fillWidth: true
                        text: page._name(index)
                        onEditingFinished: {
                            page.cfg_ghCategoryNames =
                                page._setListItem(function() { return page.cfg_ghCategoryNames; },
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
                            page.cfg_ghCategoryTextColors =
                                page._setListItem(function() { return page.cfg_ghCategoryTextColors; },
                                                  page._defaultTextColors, index, "white");
                        }
                    }
                    RadioButton {
                        ButtonGroup.group: textGroup
                        text: i18n("Negra")
                        checked: page._textColor(index) === "black"
                        onToggled: if (checked) {
                            page.cfg_ghCategoryTextColors =
                                page._setListItem(function() { return page.cfg_ghCategoryTextColors; },
                                                  page._defaultTextColors, index, "black");
                        }
                    }
                }

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
                            page.cfg_ghCategoryFilterFields =
                                page._setListItem(function() { return page.cfg_ghCategoryFilterFields; },
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
                                case "status": return i18n("Todo ; In Progress ; Done");
                                case "type":   return i18n("Issue ; PullRequest");
                                case "state":  return i18n("OPEN ; CLOSED ; MERGED");
                                case "repo":   return i18n("owner/repo ; otra/repo");
                            }
                            return i18n("(separá con ; para OR)");
                        }
                        onEditingFinished: {
                            page.cfg_ghCategoryFilterValues =
                                page._setListItem(function() { return page.cfg_ghCategoryFilterValues; },
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
            page.cfg_ghCategoryColors =
                page._setListItem(function() { return page.cfg_ghCategoryColors; },
                                  page._defaultColors, targetIndex, color.toString());
        }
    }
}
