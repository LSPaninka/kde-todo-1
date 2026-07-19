/*
 * configJiraCategories.qml - "Categorías Jira" tab of the configuration
 * dialog.
 *
 * For each of the up-to-10 categories the user can pick:
 *   - name (display label)
 *   - color (with native ColorDialog)
 *   - text color for the panel swatch (white | black)
 *   - filter: a Jira field (status / statusCategory / issuetype / priority),
 *             default "status" (exact status name), plus a value
 *             (semicolon-separated for OR matching, e.g. "Test QA; Done").
 *
 * The active count is configured separately in the General tab. All 10
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

    // NOTE: we deliberately do NOT use `cfg_<key>` properties for these
    // StringLists. Reassigning a standalone `var` StringList on a config page
    // does not reliably persist through the Apply button (a well-known Plasma
    // quirk). Instead we read from and write to plasmoid.configuration
    // directly, which saves immediately and reliably.

    readonly property int _slots: 10

    // Bump on every write so the function-based bindings below re-read.
    property int _rev: 0

    // Build a fresh 10-slot array with slot i set to value.
    function _buildList(current, fallback, i, value) {
        var arr = (current || []).slice();
        while (arr.length < page._slots) arr.push(fallback[arr.length] !== undefined ? fallback[arr.length] : "");
        arr[i] = value;
        return arr;
    }

    // Persist a StringList straight to plasmoid.configuration.
    function _persist(key, fallback, i, value) {
        var arr = _buildList(plasmoid.configuration[key], fallback, i, value);
        plasmoid.configuration[key] = arr;
        page._rev++;
    }

    readonly property var _defaultNames:        ["Por hacer", "En curso", "Hechas", "Otras", "Cat 5", "Cat 6", "Cat 7", "Cat 8", "Cat 9", "Cat 10"]
    readonly property var _defaultColors:       ["#42526e", "#f5a623", "#2ecc71", "#9b59b6", "#3498db", "#e67e22", "#1abc9c", "#e74c3c", "#34495e", "#16a085"]
    readonly property var _defaultTextColors:   ["white", "white", "white", "white", "white", "white", "white", "white", "white", "white"]
    // Default filter is "status" (Estado — nombre exacto) for every slot.
    readonly property var _defaultFilterFields: ["status", "status", "status", "status", "status", "status", "status", "status", "status", "status"]
    readonly property var _defaultFilterValues: ["", "", "", "", "", "", "", "", "", ""]

    // The dropdown options. Internal value vs. display label.
    readonly property var _filterFieldOptions: [
        { value: "",               label: i18n("(sin filtro — todas)") },
        { value: "statusCategory", label: i18n("Categoría de estado (To Do / In Progress / Done)") },
        { value: "status",         label: i18n("Estado (nombre exacto)") },
        { value: "issuetype",      label: i18n("Tipo de incidencia (Story, Bug, Task, Sub-task…)") },
        { value: "priority",       label: i18n("Prioridad") }
    ]

    function _name(i)          { var v = (page._rev, plasmoid.configuration.jira2CategoryNames        || [])[i]; return v !== undefined ? v : _defaultNames[i]; }
    function _color(i)         { var v = (page._rev, plasmoid.configuration.jira2CategoryColors       || [])[i]; return v !== undefined ? v : _defaultColors[i]; }
    function _textColor(i)     { var v = (page._rev, plasmoid.configuration.jira2CategoryTextColors   || [])[i]; return v !== undefined ? v : _defaultTextColors[i]; }
    function _filterField(i)   { var v = (page._rev, plasmoid.configuration.jira2CategoryFilterFields || [])[i]; return v !== undefined ? v : _defaultFilterFields[i]; }
    function _filterValue(i)   { var v = (page._rev, plasmoid.configuration.jira2CategoryFilterValues || [])[i]; return v !== undefined ? v : _defaultFilterValues[i]; }

    function _optionIndexForField(f) {
        for (var k = 0; k < _filterFieldOptions.length; k++) {
            if (_filterFieldOptions[k].value === f) return k;
        }
        return 0;
    }

    Label {
        Layout.fillWidth: true
        Layout.preferredWidth: 600
        wrapMode: Text.WordWrap
        opacity: 0.75
        text: i18n("Cada categoría representa una pestaña en el popup y un cuadrado en el panel cuando "
                 + "el modo es «Jira 2». La cantidad activa se ajusta en la pestaña «General». Para que "
                 + "una categoría haga match con varias opciones, separá los valores con punto y coma "
                 + "(por ejemplo «In Progress; Code Review»).")
    }

    Repeater {
        model: page._slots
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
                        onEditingFinished: page._persist("jira2CategoryNames", page._defaultNames, index, text)
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
                        onToggled: if (checked) page._persist("jira2CategoryTextColors", page._defaultTextColors, index, "white")
                    }
                    RadioButton {
                        ButtonGroup.group: textGroup
                        text: i18n("Negra")
                        checked: page._textColor(index) === "black"
                        onToggled: if (checked) page._persist("jira2CategoryTextColors", page._defaultTextColors, index, "black")
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
                        // Initialise once from config; do NOT keep a reactive
                        // binding on currentIndex — that would fight the user's
                        // selection (onActivated writes config, which would then
                        // recompute the binding and snap the combo back).
                        Component.onCompleted: currentIndex = page._optionIndexForField(page._filterField(index))
                        onActivated: {
                            var v = page._filterFieldOptions[currentIndex].value;
                            page._persist("jira2CategoryFilterFields", page._defaultFilterFields, index, v);
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
                        onEditingFinished: page._persist("jira2CategoryFilterValues", page._defaultFilterValues, index, text)
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
        onAccepted: page._persist("jira2CategoryColors", page._defaultColors, targetIndex, color.toString())
    }
}
