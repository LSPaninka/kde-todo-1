/*
 * ArchiveView.qml - scrollable list of archived (completed) tasks.
 * Only archived tasks can be permanently deleted, matching the requirement.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: archiveView
    property var store

    // These signals bubble up so FullRepresentation can host the dialogs.
    signal confirmDelete(int id)
    signal confirmEmpty()

    CategoryHelper { id: cats }

    readonly property int _v: store ? store.version : 0

    ColumnLayout {
        anchors.fill: parent
        spacing: PlasmaCore.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: (archiveView._v, i18np("%1 archived task",
                                             "%1 archived tasks",
                                             store.archived.length))
                font.bold: true
            }
            PlasmaComponents3.Button {
                icon.name: "edit-clear-all"
                text: i18n("Empty archive")
                enabled: (archiveView._v, store.archived.length > 0)
                onClicked: archiveView.confirmEmpty()
            }
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: list
                spacing: 4
                // Re-read `archived` through _v so this binding updates on any mutation.
                model: (archiveView._v, store.archived)
                delegate: Rectangle {
                    width: list.width
                    readonly property var item: modelData
                    height: row.implicitHeight + PlasmaCore.Units.smallSpacing * 2
                    radius: 3
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 4
                        color: cats.color(item.category)
                    }

                    RowLayout {
                        id: row
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 10
                        anchors.rightMargin: PlasmaCore.Units.smallSpacing
                        spacing: PlasmaCore.Units.smallSpacing

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            PlasmaComponents3.Label {
                                text: item.title
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                font.strikeout: true
                                opacity: 0.7
                            }
                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                text: i18n("%1 · archived %2",
                                           cats.name(item.category),
                                           Qt.formatDateTime(new Date(item.archivedAt),
                                                             Qt.DefaultLocaleShortDate))
                                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                                opacity: 0.6
                            }
                        }

                        PriorityBadge {
                            visible: plasmoid.configuration.showPriorityIcons
                            level: item.priority
                        }

                        PlasmaComponents3.ToolButton {
                            icon.name: "edit-undo"
                            onClicked: store.restoreTask(item.id)
                            PlasmaComponents3.ToolTip.text: i18n("Restore to active list")
                            PlasmaComponents3.ToolTip.visible: hovered
                            PlasmaComponents3.ToolTip.delay: 500
                        }
                        PlasmaComponents3.ToolButton {
                            icon.name: "edit-delete"
                            onClicked: {
                                if (plasmoid.configuration.confirmDelete) {
                                    archiveView.confirmDelete(item.id);
                                } else {
                                    store.deleteArchived(item.id);
                                }
                            }
                            PlasmaComponents3.ToolTip.text: i18n("Delete permanently")
                            PlasmaComponents3.ToolTip.visible: hovered
                            PlasmaComponents3.ToolTip.delay: 500
                        }
                    }
                }

                PlasmaComponents3.Label {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: i18n("The archive is empty.")
                    opacity: 0.55
                }
            }
        }
    }
}
