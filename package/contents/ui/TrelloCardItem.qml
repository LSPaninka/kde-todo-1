/*
 * TrelloCardItem.qml - delegate for a single Trello card.
 *
 *   [P1-P2] [Bug]                              ← colored labels
 *   Card title (wraps up to 3 lines)
 *   ≡  💬 3  ☑ 2/5  🕑 12 nov            LP AS  ← badges + members
 *   [========== checklist progress ==========]
 *
 * Left click: open the detail/edit modal (`activated`).
 * Middle click: open the card on trello.com.
 * Right click: context menu (detail, move to another list, open in Trello).
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Rectangle {
    id: item

    property var card          // normalized card from TrelloStore
    property var trello        // the TrelloStore
    property color listColor: "#0079bf"

    signal activated(var card)

    width: parent ? parent.width : 0
    implicitHeight: col.implicitHeight + Kirigami.Units.smallSpacing * 2
    radius: 6
    color: cardMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)

    readonly property int _ckTotal: card && card.badges ? card.badges.checkItems : 0
    readonly property int _ckDone:  card && card.badges ? card.badges.checkItemsChecked : 0
    readonly property real _ckProgress: _ckTotal > 0 ? _ckDone / _ckTotal : 0

    // Due state: "" (none), "complete", "overdue", "soon" (< 24h), "future".
    function _dueState() {
        if (!card || !card.due) return "";
        if (card.dueComplete) return "complete";
        var t = Date.parse(card.due);
        if (isNaN(t)) return "";
        var now = Date.now();
        if (t < now) return "overdue";
        if (t - now < 24 * 3600 * 1000) return "soon";
        return "future";
    }
    function _dueColor() {
        switch (_dueState()) {
            case "complete": return "#1f845a";
            case "overdue":  return "#c9372c";
            case "soon":     return "#b38600";
        }
        return Qt.rgba(1, 1, 1, 0.10);
    }
    function _dueText() {
        if (!card || !card.due) return "";
        var d = new Date(card.due);
        if (isNaN(d.getTime())) return "";
        return Qt.formatDateTime(d, "d MMM");
    }

    MouseArea {
        id: cardMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (mouse) => {
            if (mouse.button === Qt.MiddleButton) {
                if (card && card.url) Qt.openUrlExternally(card.url);
            } else if (mouse.button === Qt.RightButton) {
                ctxMenu.x = mouse.x;
                ctxMenu.y = mouse.y;
                ctxMenu.open();
            } else {
                item.activated(card);
            }
        }
    }

    QQC2.Menu {
        id: ctxMenu

        QQC2.MenuItem {
            text: i18n("Ver / editar")
            icon.name: "document-edit"
            onTriggered: item.activated(card)
        }

        QQC2.Menu {
            id: moveMenu
            title: i18n("Mover a")

            Instantiator {
                model: (item.trello ? (item.trello.version, item.trello.lists) : [])
                delegate: QQC2.MenuItem {
                    text: modelData.name
                    enabled: item.card && modelData.id !== item.card.idList
                    onTriggered: {
                        if (item.trello && item.card) item.trello.moveCard(item.card.id, modelData.id, null);
                        ctxMenu.close();
                    }
                }
                onObjectAdded: function(index, object) { moveMenu.insertItem(index, object); }
                onObjectRemoved: function(index, object) { moveMenu.removeItem(object); }
            }
        }

        QQC2.MenuSeparator {}

        QQC2.MenuItem {
            text: i18n("Abrir en Trello")
            icon.name: "globe"
            onTriggered: { if (card && card.url) Qt.openUrlExternally(card.url); }
        }
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Kirigami.Units.smallSpacing + 2
        anchors.rightMargin: Kirigami.Units.smallSpacing + 2
        anchors.topMargin: Kirigami.Units.smallSpacing
        spacing: 4

        // -------- Labels --------
        Flow {
            Layout.fillWidth: true
            spacing: 4
            visible: item.card && item.card.idLabels.length > 0

            Repeater {
                model: item.card ? item.card.idLabels : []
                delegate: Rectangle {
                    property var lbl: item.trello ? item.trello.labelById(modelData) : null
                    property color bg: item.trello && lbl ? item.trello.labelColor(lbl.color) : "#6b778c"
                    visible: lbl !== null
                    // Unnamed labels render as a short colored bar, like Trello.
                    width: lbl && lbl.name ? lblText.implicitWidth + 12 : 36
                    height: lbl && lbl.name ? 18 : 8
                    radius: 3
                    color: bg
                    PlasmaComponents3.Label {
                        id: lblText
                        anchors.centerIn: parent
                        visible: parent.lbl && parent.lbl.name
                        text: parent.lbl ? parent.lbl.name : ""
                        color: item.trello ? item.trello.contrastText(parent.bg.toString()) : "white"
                        font.bold: true
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }
                }
            }
        }

        // -------- Title --------
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: item.card ? item.card.name : ""
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }

        // -------- Badges + members --------
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                visible: item.card && item.card.badges.description
                source: "format-justify-left"
                Layout.preferredWidth: 14
                Layout.preferredHeight: 14
                opacity: 0.7
            }

            RowLayout {
                visible: item.card && item.card.badges.comments > 0
                spacing: 2
                Kirigami.Icon {
                    source: "dialog-messages"
                    Layout.preferredWidth: 14
                    Layout.preferredHeight: 14
                    opacity: 0.7
                }
                PlasmaComponents3.Label {
                    text: item.card ? item.card.badges.comments : ""
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    opacity: 0.8
                }
            }

            Rectangle {
                visible: item._ckTotal > 0
                Layout.preferredHeight: 18
                Layout.preferredWidth: ckRow.implicitWidth + 8
                radius: 3
                color: item._ckDone === item._ckTotal ? "#1f845a" : "transparent"
                RowLayout {
                    id: ckRow
                    anchors.centerIn: parent
                    spacing: 2
                    Kirigami.Icon {
                        source: "checkbox"
                        Layout.preferredWidth: 14
                        Layout.preferredHeight: 14
                    }
                    PlasmaComponents3.Label {
                        text: item._ckDone + "/" + item._ckTotal
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }
                }
            }

            Rectangle {
                visible: item._dueState() !== ""
                Layout.preferredHeight: 18
                Layout.preferredWidth: dueRow.implicitWidth + 8
                radius: 3
                color: item._dueColor()
                RowLayout {
                    id: dueRow
                    anchors.centerIn: parent
                    spacing: 2
                    Kirigami.Icon {
                        source: item.card && item.card.dueComplete ? "checkmark" : "chronometer"
                        Layout.preferredWidth: 14
                        Layout.preferredHeight: 14
                    }
                    PlasmaComponents3.Label {
                        text: item._dueText()
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        color: item._dueState() === "future" ? Kirigami.Theme.textColor : "white"
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Repeater {
                model: item.card ? item.card.idMembers : []
                delegate: Rectangle {
                    property var mem: item.trello ? item.trello.memberById(modelData) : null
                    visible: mem !== null
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    radius: 11
                    color: item.trello ? item.trello.memberColor(modelData) : "#0079bf"
                    PlasmaComponents3.Label {
                        anchors.centerIn: parent
                        text: parent.mem ? parent.mem.initials : ""
                        color: "white"
                        font.bold: true
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize - 1
                    }
                    HoverHandler { id: memHover }
                    PlasmaComponents3.ToolTip.text: mem ? mem.fullName : ""
                    PlasmaComponents3.ToolTip.visible: memHover.hovered
                    PlasmaComponents3.ToolTip.delay: 400
                }
            }
        }

        // -------- Checklist progress bar --------
        Rectangle {
            id: ckTrack
            Layout.fillWidth: true
            Layout.preferredHeight: 4
            Layout.bottomMargin: 2
            visible: item._ckTotal > 0
            radius: 2
            color: Qt.rgba(1, 1, 1, 0.10)
            Rectangle {
                width: Math.round(ckTrack.width * item._ckProgress)
                height: parent.height
                radius: 2
                color: item._ckProgress >= 1 ? "#4bce97" : item.listColor
            }
        }
    }
}
