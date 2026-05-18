/*
 * GhView.qml - popup contents for the "gh" (GitHub Projects) mode.
 *
 * Tabs come from the user-defined GH categories (1..4). Each tab filters
 * the cached project items by status / type / state / repository, the
 * same way Jira categories do.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: view
    property var gh

    readonly property int _v: gh ? gh.version : 0
    readonly property int categoryCount:
        Math.min(4, Math.max(1, plasmoid.configuration.ghCategoryCount | 0 || 3))

    function _formatDate(ms) {
        if (!ms) return "";
        return Qt.formatDateTime(new Date(ms), Qt.DefaultLocaleShortDate);
    }
    function _categoryName(i) {
        var arr = plasmoid.configuration.ghCategoryNames || [];
        return arr[i] || qsTr("Cat. %1").arg(i + 1);
    }
    function _categoryColor(i) {
        var arr = plasmoid.configuration.ghCategoryColors || [];
        return arr[i] || "#7f8c8d";
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
                source: "applications-development"
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
            }
            PlasmaComponents3.Label {
                text: i18n("GitHub Projects")
                font.bold: true
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: {
                    if (!gh) return "";
                    if (gh.loading) return i18n("Cargando…");
                    if (gh.lastError) return gh.lastError;
                    if (gh.lastFetchedAt > 0)
                        return i18n("Actualizado %1 — %2 ítems",
                                    view._formatDate(gh.lastFetchedAt),
                                    (view._v, gh.totalCount()));
                    return i18n("Sin datos. Pulsá ↻ para cargar.");
                }
                elide: Text.ElideRight
                opacity: 0.7
                color: gh && gh.lastError
                       ? PlasmaCore.Theme.negativeTextColor
                       : PlasmaCore.Theme.textColor
            }
            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh"
                enabled: gh && !gh.loading
                onClicked: gh.fetch()
                PlasmaComponents3.ToolTip.text: i18n("Refrescar")
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

        // -------- Tabs (one per GH category) --------
        QQC2.TabBar {
            id: tabs
            Layout.fillWidth: true

            Repeater {
                model: view.categoryCount
                QQC2.TabButton {
                    id: tabBtn
                    leftPadding: 8
                    rightPadding: 8
                    property int catCount: (view._v, gh ? gh.countByGhCategory(index) : 0)
                    contentItem: RowLayout {
                        spacing: 6
                        Rectangle {
                            Layout.preferredWidth: 8
                            Layout.preferredHeight: 8
                            radius: 4
                            color: view._categoryColor(index)
                            Layout.alignment: Qt.AlignVCenter
                        }
                        PlasmaComponents3.Label {
                            text: view._categoryName(index)
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        TabCountBadge {
                            visible: tabBtn.catCount > 0
                            count: tabBtn.catCount
                            badgeColor: view._categoryColor(index)
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }
            }
        }

        // -------- Body --------
        StackLayout {
            id: stack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex

            Repeater {
                model: view.categoryCount
                Item {
                    QQC2.ScrollView {
                        anchors.fill: parent
                        clip: true
                        ListView {
                            id: list
                            spacing: 4
                            model: (view._v, gh ? gh.itemsByGhCategory(index) : [])
                            delegate: GhItemDelegate {
                                width: list.width
                                entry: modelData
                            }

                            PlasmaComponents3.Label {
                                anchors.centerIn: parent
                                visible: list.count === 0 && gh && !gh.loading
                                width: parent.width - 40
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                opacity: 0.55
                                text: {
                                    if (!gh) return "";
                                    if (gh.lastError) return gh.lastError;
                                    if (gh.lastFetchedAt === 0)
                                        return i18n("Aún no se cargaron ítems. Pulsá el botón de refrescar.");
                                    return i18n("Sin ítems en esta categoría.");
                                }
                            }

                            PlasmaComponents3.BusyIndicator {
                                anchors.centerIn: parent
                                running: gh && gh.loading && list.count === 0
                                visible: running
                            }
                        }
                    }
                }
            }
        }

        // -------- Footer --------
        RowLayout {
            Layout.fillWidth: true

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: gh ? i18np("%1 ítem en total",
                                 "%1 ítems en total",
                                 (view._v, gh.totalCount())) : ""
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

    // -------- Debug overlay --------
    Item {
        id: debugOverlay
        anchors.fill: parent
        visible: false
        z: 1000

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
            width: Math.max(300, parent.width - 20)
            height: Math.max(220, parent.height - 30)
            color: PlasmaCore.Theme.backgroundColor
            border.color: PlasmaCore.Theme.textColor
            border.width: 1
            radius: 4

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: i18n("Diagnóstico — última consulta GitHub")
                        font.bold: true
                    }
                    PlasmaComponents3.ToolButton {
                        icon.name: "edit-copy"
                        text: i18n("Copiar")
                        enabled: gh && gh.hasDebugLog
                        onClicked: {
                            logArea.selectAll();
                            logArea.copy();
                            logArea.deselect();
                        }
                    }
                    PlasmaComponents3.ToolButton {
                        icon.name: "edit-clear-all"
                        text: i18n("Limpiar")
                        enabled: gh && gh.hasDebugLog
                        onClicked: gh.clearDebugLog()
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
                        text: (gh && gh.hasDebugLog)
                              ? ((view._v, gh.lastDebugLog))
                              : i18n("Sin datos. Pulsá ↻ para hacer un fetch primero.")
                    }
                }
            }
        }
    }
}
