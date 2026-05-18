/*
 * GhItemDelegate.qml - delegate for a single GitHub Projects item.
 *
 *  [type] [repo#123]  Title…             [state]  [status]
 *
 * Click: opens the issue / PR in the default browser. Draft issues have
 * no URL so the click is a no-op.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Rectangle {
    id: item

    property var entry        // normalized item from GhStore

    width: parent ? parent.width : 0
    implicitHeight: col.implicitHeight + PlasmaCore.Units.smallSpacing * 2
    radius: 4
    color: mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.04)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)

    function _typeBadge(t) {
        if (t === "Issue")       return "I";
        if (t === "PullRequest") return "P";
        if (t === "DraftIssue")  return "D";
        return "?";
    }
    function _typeColor(t, isDraft) {
        if (t === "PullRequest") return isDraft ? "#6e7681" : "#8957e5";
        if (t === "Issue")       return "#238636";
        if (t === "DraftIssue")  return "#6e7681";
        return "#7f8c8d";
    }
    function _stateColor(s) {
        switch ((s || "").toUpperCase()) {
            case "OPEN":   return "#238636";
            case "CLOSED": return "#a40e26";
            case "MERGED": return "#8957e5";
            case "DRAFT":  return "#6e7681";
        }
        return "#7f8c8d";
    }
    function _shortRepo(r) {
        if (!r) return "";
        // Strip owner if the repo string is "owner/name" to keep things compact.
        var i = r.indexOf("/");
        return (i >= 0) ? r.substring(i + 1) : r;
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: (entry && entry.url) ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (entry && entry.url) Qt.openUrlExternally(entry.url);
        }
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: PlasmaCore.Units.smallSpacing
        anchors.rightMargin: PlasmaCore.Units.smallSpacing
        anchors.topMargin: PlasmaCore.Units.smallSpacing
        anchors.bottomMargin: PlasmaCore.Units.smallSpacing
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: PlasmaCore.Units.smallSpacing

            // Type badge.
            Rectangle {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                radius: 3
                color: item._typeColor(entry ? entry.type : "", entry ? entry.isDraft : false)
                Text {
                    anchors.centerIn: parent
                    text: item._typeBadge(entry ? entry.type : "")
                    color: "white"
                    font.bold: true
                    font.pixelSize: 12
                }
            }

            // repo#number.
            PlasmaComponents3.Label {
                visible: entry && (entry.number > 0 || entry.repo)
                text: {
                    if (!entry) return "";
                    var r = item._shortRepo(entry.repo);
                    if (entry.number > 0) return (r ? r + "#" + entry.number : "#" + entry.number);
                    return r;
                }
                font.family: "monospace"
                font.bold: true
                opacity: 0.9
            }

            // Title.
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: entry ? entry.title : ""
                elide: Text.ElideRight
            }

            // State chip.
            Rectangle {
                visible: entry && entry.state
                Layout.preferredHeight: 18
                Layout.preferredWidth: stateLbl.implicitWidth + 12
                radius: 9
                color: item._stateColor(entry ? entry.state : "")
                PlasmaComponents3.Label {
                    id: stateLbl
                    anchors.centerIn: parent
                    text: entry ? entry.state : ""
                    color: "white"
                    font.bold: true
                    font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                }
            }

            // Status chip (from the project's Status field).
            Rectangle {
                visible: entry && entry.statusName
                Layout.preferredHeight: 20
                Layout.preferredWidth: statusLbl.implicitWidth + 14
                radius: 4
                color: "#1f6feb"
                PlasmaComponents3.Label {
                    id: statusLbl
                    anchors.centerIn: parent
                    text: entry ? entry.statusName : ""
                    color: "white"
                    font.bold: true
                    font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                }
            }
        }
    }
}
