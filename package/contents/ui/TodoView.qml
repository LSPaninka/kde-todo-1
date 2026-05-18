/*
 * TodoView.qml - the popup contents in "todo" mode.
 *
 * Tabs: one per category + Archive. All dialogs (new/edit task,
 * edit subtask, export, import, delete confirmation) are hosted at the
 * root of this Item so they overlay the entire popup.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: todoView

    property var store

    CategoryHelper { id: cats }

    // Global + N category tabs + Archive. Each tab is sized to a 1/N share
    // of the bar so they always fill the popup width.
    readonly property int _tabCount: 2 + cats.count()
    readonly property real _tabWidth: tabs.width / Math.max(1, _tabCount)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: PlasmaCore.Units.smallSpacing
        spacing: PlasmaCore.Units.smallSpacing

        // -------- Tab bar --------
        QQC2.TabBar {
            id: tabs
            Layout.fillWidth: true

            // Global: shows every task from every category, color-coded.
            QQC2.TabButton {
                id: globalTab
                width: todoView._tabWidth
                leftPadding: 6
                rightPadding: 6
                property int pending: (store.version, store.totalPending())
                contentItem: RowLayout {
                    spacing: 6
                    PlasmaCore.IconItem {
                        source: "view-list-tree"
                        Layout.preferredWidth: 12
                        Layout.preferredHeight: 12
                        Layout.alignment: Qt.AlignVCenter
                    }
                    PlasmaComponents3.Label {
                        text: i18n("Global")
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    TabCountBadge {
                        visible: globalTab.pending > 0
                        count: globalTab.pending
                        badgeColor: PlasmaCore.Theme.highlightColor
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }

            Repeater {
                model: cats.count()
                QQC2.TabButton {
                    id: catTab
                    width: todoView._tabWidth
                    property int pending: (store.version, store.pendingCountForCategory(index))
                    leftPadding: 6
                    rightPadding: 6
                    contentItem: RowLayout {
                        spacing: 6
                        Rectangle {
                            Layout.preferredWidth: 8
                            Layout.preferredHeight: 8
                            radius: 4
                            color: cats.color(index)
                            Layout.alignment: Qt.AlignVCenter
                        }
                        PlasmaComponents3.Label {
                            text: cats.name(index)
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        TabCountBadge {
                            visible: catTab.pending > 0
                            count: catTab.pending
                            badgeColor: cats.color(index)
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }
            }

            QQC2.TabButton {
                id: archiveTab
                width: todoView._tabWidth
                leftPadding: 6
                rightPadding: 6
                contentItem: RowLayout {
                    spacing: 6
                    PlasmaCore.IconItem {
                        source: "archive-insert"
                        Layout.preferredWidth: 14
                        Layout.preferredHeight: 14
                        Layout.alignment: Qt.AlignVCenter
                    }
                    PlasmaComponents3.Label {
                        text: i18n("Archive")
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    TabCountBadge {
                        visible: (store.version, store.archived.length > 0)
                        count: (store.version, store.archived.length)
                        badgeColor: PlasmaCore.Theme.disabledTextColor
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }
        }

        // -------- Stacked views --------
        StackLayout {
            id: stack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex

            // Index 0: Global view (matches the position of globalTab above).
            GlobalView {
                store: todoView.store
                onEditTaskRequested: taskDialog.openEdit(task)
                onEditSubtaskRequested: subDialog.openFor(task, subtask)
            }

            Repeater {
                model: cats.count()
                CategoryView {
                    store: todoView.store
                    catIndex: index
                    onNewTaskRequested: taskDialog.openNew(catIndex)
                    onEditTaskRequested: taskDialog.openEdit(task)
                    onEditSubtaskRequested: subDialog.openFor(task, subtask)
                    onExportRequested: exportDialog.openFor(catIndex, categoryName)
                    onImportRequested: importDialog.openFor(catIndex, categoryName)
                }
            }

            ArchiveView {
                store: todoView.store
                onConfirmDelete: { confirmDeleteDlg.pendingId = id; confirmDeleteDlg.open(); }
                onConfirmEmpty: confirmEmptyDlg.open()
            }
        }

        // -------- Footer --------
        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: (store.version, i18np("%1 pending task in total",
                                             "%1 pending tasks in total",
                                             store.totalPending()))
                opacity: 0.6
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            }
            ModeMenuButton {}
            PlasmaComponents3.ToolButton {
                icon.name: "configure"
                text: i18n("Configure…")
                onClicked: plasmoid.action("configure").trigger()
            }
        }
    }

    // -------- Shared dialogs (rendered on top of the popup) --------
    TaskEditDialog {
        id: taskDialog
        store: todoView.store
    }

    SubtaskEditDialog {
        id: subDialog
        store: todoView.store
    }

    ExportDialog {
        id: exportDialog
        store: todoView.store
    }

    ImportDialog {
        id: importDialog
        store: todoView.store
    }

    QQC2.Dialog {
        id: confirmDeleteDlg
        property int pendingId: 0
        title: i18n("Delete task?")
        modal: true
        standardButtons: QQC2.Dialog.Yes | QQC2.Dialog.No
        anchors.centerIn: parent
        onAccepted: if (pendingId) store.deleteArchived(pendingId)
        contentItem: PlasmaComponents3.Label {
            text: i18n("This will permanently remove the task from the archive.")
            wrapMode: Text.WordWrap
        }
    }

    QQC2.Dialog {
        id: confirmEmptyDlg
        title: i18n("Empty archive?")
        modal: true
        standardButtons: QQC2.Dialog.Yes | QQC2.Dialog.No
        anchors.centerIn: parent
        onAccepted: store.clearArchive()
        contentItem: PlasmaComponents3.Label {
            text: i18n("This will permanently delete all archived tasks.")
            wrapMode: Text.WordWrap
        }
    }
}
