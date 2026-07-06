/*
 * JiraView.qml - the popup contents when the plasmoid is in "jira" mode.
 *
 * Tabs come from the user-defined Jira categories (1..4), each with its
 * own name, color and filter (issuetype / status / statusCategory /
 * priority). See configJiraCategories.qml.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: view
    property var jira

    readonly property int _v: jira ? jira.version : 0
    readonly property int categoryCount:
        Math.min(10, Math.max(1, plasmoid.configuration.jiraCategoryCount | 0 || 3))
    // Each tab gets a 1/N share of the bar so they always fill the width.
    readonly property real _tabWidth: tabs.width / Math.max(1, categoryCount)

    function _formatDate(ms) {
        if (!ms) return "";
        return Qt.formatDateTime(new Date(ms), Qt.DefaultLocaleShortDate);
    }
    function _categoryName(i) {
        var arr = plasmoid.configuration.jiraCategoryNames || [];
        return arr[i] || qsTr("Cat. %1").arg(i + 1);
    }
    function _categoryColor(i) {
        var arr = plasmoid.configuration.jiraCategoryColors || [];
        return arr[i] || "#7f8c8d";
    }

    // Jump to the tab requested from a panel swatch click.
    Connections {
        target: jira || null
        function onCategoryRequested(index) {
            if (index >= 0 && index < view.categoryCount) tabs.currentIndex = index;
        }
    }
    // On (re)open, honour the last requested category.
    Component.onCompleted: {
        if (jira && jira.selectedCategory >= 0 && jira.selectedCategory < view.categoryCount)
            tabs.currentIndex = jira.selectedCategory;
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
                source: "view-task"
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
            }
            PlasmaComponents3.Label {
                text: i18n("Jira")
                font.bold: true
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: {
                    if (!jira) return "";
                    if (jira.loading) return i18n("Cargando…");
                    if (jira.lastError) return jira.lastError;
                    if (jira.lastFetchedAt > 0)
                        return i18n("Actualizado %1 — %2 incidencias",
                                    view._formatDate(jira.lastFetchedAt),
                                    (view._v, jira.totalCount()));
                    return i18n("Sin datos. Pulsá ↻ para cargar.");
                }
                elide: Text.ElideRight
                opacity: 0.7
                color: jira && jira.lastError
                       ? PlasmaCore.Theme.negativeTextColor
                       : PlasmaCore.Theme.textColor
            }
            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh"
                enabled: jira && !jira.loading
                onClicked: jira.fetch()
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

        // -------- Tabs (one per Jira category) --------
        QQC2.TabBar {
            id: tabs
            Layout.fillWidth: true

            Repeater {
                model: view.categoryCount
                QQC2.TabButton {
                    id: tabBtn
                    width: view._tabWidth
                    leftPadding: 8
                    rightPadding: 8
                    property int catCount: (view._v, jira ? jira.countByJiraCategory(index) : 0)
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

        // -------- Body: list per tab --------
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
                            model: (view._v, jira ? jira.issuesByJiraCategory(index) : [])
                            delegate: JiraIssueItem {
                                width: list.width
                                issue: modelData
                                onActivated: function(iss) { issueDialog.openFor(iss); }
                            }

                            PlasmaComponents3.Label {
                                anchors.centerIn: parent
                                visible: list.count === 0 && jira && !jira.loading
                                width: parent.width - 40
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                opacity: 0.55
                                text: {
                                    if (!jira) return "";
                                    if (jira.lastError) return jira.lastError;
                                    if (jira.lastFetchedAt === 0)
                                        return i18n("Aún no se cargaron incidencias. Pulsá el botón de refrescar.");
                                    return i18n("Sin incidencias en esta categoría.");
                                }
                            }

                            PlasmaComponents3.BusyIndicator {
                                anchors.centerIn: parent
                                running: jira && jira.loading && list.count === 0
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
                text: jira ? i18np("%1 incidencia en total",
                                   "%1 incidencias en total",
                                   (view._v, jira.totalCount())) : ""
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

    // -------- Issue detail modal (opened from an issue click) --------
    JiraIssueDialog {
        id: issueDialog
        jira: view.jira
    }

    // -------- Debug overlay (in-popup modal showing last fetch log) --------
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
                        text: i18n("Diagnóstico — última consulta Jira")
                        font.bold: true
                    }
                    PlasmaComponents3.ToolButton {
                        icon.name: "edit-copy"
                        text: i18n("Copiar")
                        enabled: jira && jira.hasDebugLog
                        onClicked: {
                            logArea.selectAll();
                            logArea.copy();
                            logArea.deselect();
                        }
                    }
                    PlasmaComponents3.ToolButton {
                        icon.name: "edit-clear-all"
                        text: i18n("Limpiar")
                        enabled: jira && jira.hasDebugLog
                        onClicked: jira.clearDebugLog()
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
                        text: (jira && jira.hasDebugLog)
                              ? ((view._v, jira.lastDebugLog))
                              : i18n("Sin datos. Pulsá ↻ para hacer un fetch primero.")
                    }
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.6
                    font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                    text: i18n("Cada fetch reemplaza este log. Los warnings aparecen con [!].")
                }
            }
        }
    }
}
