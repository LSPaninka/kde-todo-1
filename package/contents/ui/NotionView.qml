/*
 * NotionView.qml - popup contents in "notion" mode.
 *
 * Flat list of pages from `ntn api v1/search` with a sync button, a debug
 * overlay (same shape as the Jira/GH ones) and an edit dialog.
 *
 * No category tabs: Notion pages don't have a clear "status" axis the way
 * Jira/GitHub do, so we keep it simple — one list, sorted by last_edited.
 * The user can filter via the `notionQuery` field in config.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: view
    property var notion

    readonly property int _v: notion ? notion.version : 0

    function _formatDate(ms) {
        if (!ms) return "";
        return Qt.formatDateTime(new Date(ms), Qt.DefaultLocaleShortDate);
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: PlasmaCore.Units.smallSpacing
        spacing: PlasmaCore.Units.smallSpacing

        // -------- Header --------
        RowLayout {
            Layout.fillWidth: true
            spacing: PlasmaCore.Units.smallSpacing

            PlasmaCore.IconItem {
                source: "notes"
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
            }
            PlasmaComponents3.Label {
                text: i18n("Notion")
                font.bold: true
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: {
                    if (!notion) return "";
                    if (notion.loading) return i18n("Cargando…");
                    if (notion.lastError) return notion.lastError;
                    if (notion.lastFetchedAt > 0)
                        return i18n("Actualizado %1 — %2 página(s)",
                                    view._formatDate(notion.lastFetchedAt),
                                    (view._v, notion.totalCount()));
                    return i18n("Sin datos. Pulsá ↻ para sincronizar.");
                }
                elide: Text.ElideRight
                opacity: 0.7
                color: notion && notion.lastError
                       ? PlasmaCore.Theme.negativeTextColor
                       : PlasmaCore.Theme.textColor
            }
            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh"
                enabled: notion && !notion.loading
                onClicked: notion.fetch()
                PlasmaComponents3.ToolTip.text: i18n("Sincronizar con Notion (ntn)")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
            PlasmaComponents3.ToolButton {
                icon.name: "dialog-information"
                onClicked: debugOverlay.visible = true
                PlasmaComponents3.ToolTip.text: i18n("Ver diagnóstico de la última consulta")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
        }

        // -------- Body --------
        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ListView {
                id: list
                spacing: 4
                model: (view._v, notion ? notion.pages : [])
                delegate: NotionPageItem {
                    width: list.width
                    page: modelData
                    onEditRequested: editDialog.openFor(page)
                }

                PlasmaComponents3.Label {
                    anchors.centerIn: parent
                    visible: list.count === 0 && notion && !notion.loading
                    width: parent.width - 40
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    opacity: 0.6
                    text: {
                        if (!notion) return "";
                        if (notion.lastError) return notion.lastError;
                        if (notion.lastFetchedAt === 0)
                            return i18n("Aún no se cargaron páginas. Pulsá el botón de sincronizar.\n\n" +
                                        "Si es la primera vez, asegurate de haber corrido `ntn login` " +
                                        "en una terminal.");
                        return i18n("No se encontraron páginas que cumplan la búsqueda.");
                    }
                }
                PlasmaComponents3.BusyIndicator {
                    anchors.centerIn: parent
                    running: notion && notion.loading && list.count === 0
                    visible: running
                }
            }
        }

        // -------- Footer --------
        RowLayout {
            Layout.fillWidth: true

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: notion ? i18np("%1 página en total",
                                     "%1 páginas en total",
                                     (view._v, notion.totalCount())) : ""
                opacity: 0.6
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            }

            ModeMenuButton {}
            PlasmaComponents3.ToolButton {
                icon.name: "configure"
                text: i18n("Configurar…")
                onClicked: plasmoid.action("configure").trigger()
            }
        }
    }

    // -------- Edit dialog (in-popup overlay) --------
    NotionEditDialog {
        id: editDialog
        notion: view.notion
    }

    // -------- Debug overlay --------
    Item {
        id: debugOverlay
        anchors.fill: parent
        visible: false
        z: 900

        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.5
            MouseArea {
                anchors.fill: parent
                onClicked: debugOverlay.visible = false
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.max(400, parent.width - 16)
            height: Math.max(300, parent.height - 30)
            color: PlasmaCore.Theme.backgroundColor
            border.color: PlasmaCore.Theme.textColor
            border.width: 1
            radius: 4

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: PlasmaCore.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: i18n("Diagnóstico — última consulta Notion")
                        font.bold: true
                    }
                    PlasmaComponents3.ToolButton {
                        icon.name: "edit-copy"
                        text: i18n("Copiar")
                        enabled: notion && notion.hasDebugLog
                        onClicked: {
                            logArea.selectAll();
                            logArea.copy();
                            logArea.deselect();
                        }
                    }
                    PlasmaComponents3.ToolButton {
                        icon.name: "edit-clear-all"
                        text: i18n("Limpiar")
                        enabled: notion && notion.hasDebugLog
                        onClicked: notion.clearDebugLog()
                    }
                    PlasmaComponents3.ToolButton {
                        icon.name: "window-close"
                        onClicked: debugOverlay.visible = false
                    }
                }

                QQC2.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    QQC2.TextArea {
                        id: logArea
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.WrapAnywhere
                        font.family: "monospace"
                        font.pixelSize: 11
                        text: (notion && notion.hasDebugLog)
                              ? ((view._v, notion.lastDebugLog))
                              : i18n("Sin datos. Pulsá ↻ para sincronizar primero.")
                    }
                }
            }
        }
    }
}
