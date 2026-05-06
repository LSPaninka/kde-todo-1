/*
 * JiraIssueItem.qml - delegate for a single Jira issue.
 *
 *  [type] [KEY-123]  Summary text...        [priority]  [status]
 *                    ↳ Parent: PARENT-12 — parent summary
 *
 * Click: open the issue in the user's default browser.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Rectangle {
    id: item

    property var issue        // normalized issue from JiraStore

    width: parent ? parent.width : 0
    implicitHeight: col.implicitHeight + PlasmaCore.Units.smallSpacing * 2
    radius: 4
    color: mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.04)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)

    function _statusColor(name) {
        // Map Jira's named colorName to a real RGB. Jira returns names
        // like "blue-gray", "yellow", "green", "warm-red", etc.
        switch ((name || "").toLowerCase()) {
            case "blue-gray":
            case "medium-gray": return "#42526e";
            case "yellow":      return "#f5a623";
            case "green":       return "#2ecc71";
            case "brown":       return "#8b572a";
            case "warm-red":    return "#e74c3c";
            case "purple":      return "#9b59b6";
            case "blue":        return "#3498db";
        }
        // Fallback by category.
        switch (issue && issue.statusCat) {
            case "new":           return "#42526e";
            case "indeterminate": return "#f5a623";
            case "done":          return "#2ecc71";
        }
        return "#7f8c8d";
    }

    function _typeBadge(name, isSub) {
        if (isSub) return "↳";
        var n = (name || "").toLowerCase();
        if (n.indexOf("story") >= 0)   return "S";
        if (n.indexOf("bug") >= 0)     return "B";
        if (n.indexOf("epic") >= 0)    return "E";
        if (n.indexOf("task") >= 0)    return "T";
        return (name || "?").substring(0, 1).toUpperCase();
    }

    function _typeColor(name, isSub) {
        if (isSub) return "#5e6c84";
        var n = (name || "").toLowerCase();
        if (n.indexOf("story") >= 0) return "#65ba43";
        if (n.indexOf("bug") >= 0)   return "#e5493a";
        if (n.indexOf("epic") >= 0)  return "#904ee2";
        if (n.indexOf("task") >= 0)  return "#4bade8";
        return "#7f8c8d";
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (issue && issue.url) Qt.openUrlExternally(issue.url);
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

        // -------- Header row --------
        RowLayout {
            Layout.fillWidth: true
            spacing: PlasmaCore.Units.smallSpacing

            // Issuetype badge
            Rectangle {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                radius: 3
                color: item._typeColor(issue ? issue.issuetype : "", issue ? issue.isSubtask : false)
                Text {
                    anchors.centerIn: parent
                    text: item._typeBadge(issue ? issue.issuetype : "", issue ? issue.isSubtask : false)
                    color: "white"
                    font.bold: true
                    font.pixelSize: 12
                }
            }

            // Issue key (monospace)
            PlasmaComponents3.Label {
                text: issue ? issue.key : ""
                font.family: "monospace"
                font.bold: true
                opacity: 0.9
            }

            // Summary
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: issue ? issue.summary : ""
                elide: Text.ElideRight
            }

            // Priority chip
            Rectangle {
                visible: issue && issue.priority
                Layout.preferredHeight: 18
                Layout.preferredWidth: prioLbl.implicitWidth + 12
                radius: 9
                color: Qt.rgba(1, 1, 1, 0.08)
                border.color: Qt.rgba(1, 1, 1, 0.15)
                border.width: 1
                PlasmaComponents3.Label {
                    id: prioLbl
                    anchors.centerIn: parent
                    text: issue ? issue.priority : ""
                    font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                    opacity: 0.9
                }
            }

            // Status chip
            Rectangle {
                Layout.preferredHeight: 20
                Layout.preferredWidth: statusLbl.implicitWidth + 14
                radius: 4
                color: item._statusColor(issue ? issue.statusColor : "")
                PlasmaComponents3.Label {
                    id: statusLbl
                    anchors.centerIn: parent
                    text: issue ? issue.statusName : ""
                    color: "white"
                    font.bold: true
                    font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                }
            }
        }

        // -------- Optional parent line for subtasks --------
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            Layout.leftMargin: 28
            visible: issue && issue.parentKey
            text: issue
                  ? i18n("↳ Parent: %1 — %2", issue.parentKey, issue.parentSummary)
                  : ""
            elide: Text.ElideRight
            opacity: 0.6
            font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            font.italic: true
        }
    }
}
