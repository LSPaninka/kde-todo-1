/*
 * configData.qml - "Datos" tab of the configuration dialog.
 *
 * Import / export the tasks of a chosen category as JSON. This lives in the
 * settings dialog (moved out of each category header). It reaches the very
 * same SQLite database the popup uses by instantiating Database + TaskStore
 * against the shared QtQuick.LocalStorage logical name ("CategorizedToDo").
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import org.kde.kirigami 2.5 as Kirigami

ColumnLayout {
    id: page
    spacing: Kirigami.Units.largeSpacing

    CategoryHelper { id: cats }

    // Own DB + store, pointed at the same on-disk database as the widget.
    Database { id: db }
    TaskStore { id: store; plasmoid: plasmoid; database: db }

    property int _selCat: 0

    Component.onCompleted: {
        db.init();
        store.load();
    }

    function _reload() {
        store.load();
    }

    Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.75
        text: i18n("Exportá o importá las tareas de una categoría en formato JSON. "
                 + "Los cambios impactan la misma base de datos que usa el widget; "
                 + "reabrí el popup para verlos reflejados.")
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Label { text: i18n("Categoría:") }
        ComboBox {
            id: catCombo
            Layout.fillWidth: true
            model: {
                var n = cats.count();
                var out = [];
                for (var i = 0; i < n; i++) out.push(cats.name(i));
                return out;
            }
            onActivated: page._selCat = currentIndex
        }
        Button {
            text: i18n("Recargar")
            icon.name: "view-refresh"
            onClicked: page._reload()
        }
    }

    // -------- Export --------
    GroupBox {
        Layout.fillWidth: true
        Layout.fillHeight: true
        title: i18n("Exportar")

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                Button {
                    text: i18n("Generar JSON")
                    icon.name: "document-export"
                    onClicked: {
                        page._reload();
                        exportArea.text = store.exportCategoryJson(page._selCat);
                        exportArea.selectAll();
                        exportArea.forceActiveFocus();
                    }
                }
                Button {
                    text: i18n("Copiar")
                    icon.name: "edit-copy"
                    enabled: exportArea.text.length > 0
                    onClicked: { exportArea.selectAll(); exportArea.copy(); }
                }
                Item { Layout.fillWidth: true }
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 140
                TextArea {
                    id: exportArea
                    readOnly: true
                    wrapMode: TextEdit.NoWrap
                    font.family: "monospace"
                    selectByMouse: true
                    placeholderText: i18n("Presioná «Generar JSON».")
                }
            }
        }
    }

    // -------- Import --------
    GroupBox {
        Layout.fillWidth: true
        Layout.fillHeight: true
        title: i18n("Importar")

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 140
                TextArea {
                    id: importArea
                    wrapMode: TextEdit.NoWrap
                    font.family: "monospace"
                    selectByMouse: true
                    placeholderText: i18n('{ "schema": "categorizedtodo.v1", "tasks": [ … ] }')
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Button {
                    text: i18n("Pegar")
                    icon.name: "edit-paste"
                    onClicked: { importArea.clear(); importArea.paste(); }
                }
                Item { Layout.fillWidth: true }
                Button {
                    text: i18n("Importar a «%1»", cats.name(page._selCat))
                    icon.name: "document-import"
                    highlighted: true
                    onClicked: {
                        var txt = importArea.text;
                        if (!txt || txt.trim().length === 0) {
                            importStatus.text = i18n("Pegá un JSON primero.");
                            importStatus.color = "#e74c3c";
                            return;
                        }
                        try {
                            page._reload();
                            var n = store.importCategoryJson(page._selCat, txt);
                            importStatus.text = i18np("Importada %1 tarea.",
                                                      "Importadas %1 tareas.", n);
                            importStatus.color = "#2ecc71";
                            importArea.text = "";
                        } catch (err) {
                            importStatus.text = i18n("Falló la importación: %1", err.message);
                            importStatus.color = "#e74c3c";
                        }
                    }
                }
            }

            Label {
                id: importStatus
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: ""
            }
        }
    }
}
