/*
 * NotionEditDialog.qml - inline editor for a Notion page's title and body.
 *
 * Loads the current Markdown via `ntn pages get <id>` when opened, lets
 * the user edit, then on Save calls store.updatePage(id, title, content).
 * Uses an in-popup Item overlay (not QQC2.Dialog) for the same reason as
 * the Jira/GH debug overlays — robust against parent/Overlay weirdness in
 * the plasmoid popup context.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: dlg
    anchors.fill: parent
    visible: false
    z: 1000

    property var notion
    property var page: null
    property bool loading: false
    property string statusText: ""
    property color statusColor: PlasmaCore.Theme.textColor

    function openFor(p) {
        if (!p) return;
        dlg.page = p;
        titleField.text = p.title || "";
        contentArea.text = "";
        statusText = "";
        loading = true;
        visible = true;
        // Pull the current Markdown asynchronously.
        notion.getPageContent(p.id);
    }

    Connections {
        target: notion
        function onPageContentReady(pageId, markdown, ok, err) {
            if (!dlg.page || pageId !== dlg.page.id) return;
            dlg.loading = false;
            if (ok) {
                contentArea.text = markdown;
                dlg.statusText = "";
            } else {
                contentArea.text = "";
                dlg.statusText = i18n("No se pudo leer el contenido: %1", err);
                dlg.statusColor = PlasmaCore.Theme.negativeTextColor;
            }
        }
        function onPageUpdated(pageId, ok, err) {
            if (!dlg.page || pageId !== dlg.page.id) return;
            dlg.loading = false;
            if (ok) {
                dlg.statusText = i18n("Guardado.");
                dlg.statusColor = PlasmaCore.Theme.positiveTextColor;
                dlg.visible = false;
            } else {
                dlg.statusText = i18n("Error al guardar: %1", err);
                dlg.statusColor = PlasmaCore.Theme.negativeTextColor;
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.55
        MouseArea {
            anchors.fill: parent
            onClicked: if (!dlg.loading) dlg.visible = false
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.max(420, parent.width - 24)
        height: Math.max(360, parent.height - 30)
        color: PlasmaCore.Theme.backgroundColor
        border.color: PlasmaCore.Theme.textColor
        border.width: 1
        radius: 4

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: PlasmaCore.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: i18n("Editar página de Notion")
                    font.bold: true
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "window-close"
                    enabled: !dlg.loading
                    onClicked: dlg.visible = false
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: dlg.page ? i18n("ID: %1", (dlg.page.id || "")) : ""
                opacity: 0.55
                font.family: "monospace"
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            }

            PlasmaComponents3.Label { text: i18n("Título"); opacity: 0.75 }
            QQC2.TextField {
                id: titleField
                Layout.fillWidth: true
                placeholderText: i18n("Título de la página…")
            }

            PlasmaComponents3.Label { text: i18n("Contenido (Markdown)"); opacity: 0.75 }
            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                QQC2.TextArea {
                    id: contentArea
                    selectByMouse: true
                    wrapMode: TextEdit.WrapAnywhere
                    font.family: "monospace"
                    font.pixelSize: 12
                    placeholderText: dlg.loading
                                     ? i18n("Cargando contenido desde Notion…")
                                     : i18n("Escribí Markdown aquí…")
                    readOnly: dlg.loading
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: dlg.statusText
                visible: dlg.statusText.length > 0
                color: dlg.statusColor
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents3.BusyIndicator {
                    visible: dlg.loading
                    running: visible
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents3.Button {
                    text: i18n("Cancelar")
                    enabled: !dlg.loading
                    onClicked: dlg.visible = false
                }
                PlasmaComponents3.Button {
                    text: i18n("Guardar")
                    enabled: !dlg.loading && dlg.page
                    icon.name: "document-save"
                    onClicked: {
                        if (!dlg.page) return;
                        dlg.statusText = i18n("Guardando…");
                        dlg.statusColor = PlasmaCore.Theme.textColor;
                        dlg.loading = true;
                        var newTitle = titleField.text.trim();
                        var newContent = contentArea.text;
                        var titleChanged = (newTitle !== (dlg.page.title || ""));
                        notion.updatePage(
                            dlg.page.id,
                            titleChanged ? newTitle : "",
                            newContent
                        );
                    }
                }
            }
        }
    }
}
