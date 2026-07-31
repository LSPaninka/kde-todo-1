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
    property var notionSync
    property var jira

    readonly property int _nv: notionSync ? notionSync.version : 0

    CategoryHelper { id: cats }

    Connections {
        target: notionSync || null
        function onSyncFinished(ok, pulled, pushed) {
            if (ok) {
                notionStatus.text = i18n("Notion: %1 ↓ / %2 ↑", pulled, pushed);
                notionStatus.color = PlasmaCore.Theme.positiveTextColor;
            } else {
                notionStatus.text = notionSync.lastError || i18n("Error de sincronización");
                notionStatus.color = PlasmaCore.Theme.negativeTextColor;
            }
        }
    }

    // Global + N category tabs + Archive. Each tab is sized to a 1/N share
    // of the bar so they always fill the popup width.
    readonly property int _tabCount: 2 + cats.count()
    readonly property real _tabWidth: tabs.width / Math.max(1, _tabCount)

    // Jump to the tab requested from a panel swatch click. Category `index`
    // lives at tab index `index + 1` (tab 0 is the always-on Global tab).
    Connections {
        target: store || null
        function onCategoryRequested(index) {
            if (index >= 0 && index < cats.count())
                tabs.currentIndex = index + 1;
        }
    }
    Component.onCompleted: {
        if (store && store.selectedCategory >= 0 && store.selectedCategory < cats.count())
            tabs.currentIndex = store.selectedCategory + 1;
    }

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
                onLinkJiraRequested: jiraPicker.openFor(task)
                onOpenJiraRequested: todoView._openLinkedJira(task)
            }

            Repeater {
                model: cats.count()
                CategoryView {
                    store: todoView.store
                    catIndex: index
                    onNewTaskRequested: taskDialog.openNew(catIndex)
                    onEditTaskRequested: taskDialog.openEdit(task)
                    onLinkJiraRequested: jiraPicker.openFor(task)
                    onOpenJiraRequested: todoView._openLinkedJira(task)
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
                text: (store.version, i18np("%1 pending task in total",
                                             "%1 pending tasks in total",
                                             store.totalPending()))
                opacity: 0.6
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            }

            PlasmaComponents3.Label {
                id: notionStatus
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                opacity: 0.7
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                text: {
                    if (!todoView.notionSync) return "";
                    if ((todoView._nv, todoView.notionSync.loading)) return i18n("Sincronizando con Notion…");
                    return "";
                }
            }

            // Sync-with-Notion button (only useful once Notion is configured).
            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh"
                text: i18n("Notion")
                visible: todoView.notionSync && todoView.notionSync.isConfigured()
                enabled: todoView.notionSync && !(todoView._nv, todoView.notionSync.loading)
                onClicked: {
                    notionStatus.text = i18n("Sincronizando con Notion…");
                    notionStatus.color = PlasmaCore.Theme.textColor;
                    todoView.notionSync.sync(null);
                }
                PlasmaComponents3.ToolTip.text: i18n("Sincronizar la lista con Notion")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }

            ModeMenuButton {}
            PlasmaComponents3.ToolButton {
                icon.name: "configure"
                text: i18n("Configure…")
                onClicked: plasmoid.action("configure").trigger()
            }
        }
    }

    // Open the Jira detail modal for a linked task (guards against a stale
    // link with no key).
    function _openLinkedJira(task) {
        if (!task) return;
        if (task.jiraKey && task.jiraKey.length > 0)
            jiraDetail.openForLinked(task.jiraKey, task.id);
        else
            jiraPicker.openFor(task);
    }

    // -------- Shared dialogs (rendered on top of the popup) --------
    TaskEditDialog {
        id: taskDialog
        store: todoView.store
    }

    // Jira-link dialogs (only used when todoJiraLink is on).
    JiraSubtaskPicker {
        id: jiraPicker
        jira: todoView.jira
        onPicked: function(taskId, key) { todoView.store.setJiraKey(taskId, key); }
    }
    JiraIssueDialog {
        id: jiraDetail
        jira: todoView.jira
        onRelinkRequested: function(taskId) {
            jiraPicker.openFor(todoView.store.getAnyTask(taskId));
        }
    }

    // Close the Jira detail modal if the plasmoid popup is collapsed.
    Connections {
        target: plasmoid
        function onExpandedChanged() {
            if (!plasmoid.expanded && jiraDetail.opened) jiraDetail.close();
        }
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
