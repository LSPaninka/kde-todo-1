/*
 * WorklogEntry.qml - one logged block on the calendar grid.
 *
 * Used for both Jira and Clockify entries; the `kind` property switches
 * the color and the text rendered:
 *
 *   kind = "jira":
 *     ≤30 min: single line "09:00  CP-2796"
 *     >30 min: two lines (time range / issue key [+ summary if toggled])
 *     color  : Jira purple
 *
 *   kind = "clockify":
 *     ≤30 min: single line "09:00  <project | description>"
 *     >30 min: two lines (time range / description, elided right)
 *     color  : light green by default; if the project has a color and
 *              the parent set `useProjectColor: true`, the project color
 *              tints the block.
 *
 * In the combined "jira-clockify" mode the parent passes a half-width
 * geometry so the two stacks sit side by side; the inner layout
 * automatically uses smaller fonts to fit.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Rectangle {
    id: block
    property var entry
    property string kind: "jira"   // "jira" | "clockify"
    property bool compact: false   // true in combined mode (force smaller font)
    property bool useProjectColor: false

    // Used by the drag-to-move MouseArea below to constrain the block to
    // its containing day column.
    property real columnHeight: parent ? parent.height : 0

    signal clicked()
    // Emitted on drag release with the Y delta (px) from the press point.
    // Parent maps that to a slot delta and triggers an API update.
    signal moveRequested(real deltaY)

    radius: 3
    border.width: 1
    color: block._fillColor()
    border.color: block._borderColor()

    readonly property bool _isShort: entry && entry.durationSec <= 30 * 60
    readonly property bool _showSummary: plasmoid.configuration.worklogShowIssueSummary === true
    readonly property int _baseSize:    PlasmaCore.Theme.smallestFont.pixelSize
    readonly property int _smallSize:   Math.max(7, _baseSize - 1)
    readonly property int _useSize:     (compact || _isShort) ? _smallSize : _baseSize

    function _fillColor() {
        if (kind === "jira") {
            return Qt.rgba(155/255, 145/255, 230/255, 0.55);       // muted purple
        }
        // Clockify: optional project tint, otherwise light green.
        if (useProjectColor && entry && entry.projectColor && entry.projectColor.length > 0) {
            return Qt.tint(Qt.rgba(0, 0, 0, 0.0), entry.projectColor);
        }
        return Qt.rgba(120/255, 215/255, 145/255, 0.55);            // light green
    }
    function _borderColor() {
        if (kind === "jira") return Qt.rgba(120/255, 110/255, 200/255, 0.95);
        if (useProjectColor && entry && entry.projectColor) {
            return Qt.darker(entry.projectColor, 1.3);
        }
        return Qt.rgba(70/255, 170/255, 100/255, 0.95);
    }

    function _fmtTime(ms) {
        var d = new Date(ms);
        function p(n) { return n < 10 ? "0" + n : "" + n; }
        return p(d.getHours()) + ":" + p(d.getMinutes());
    }
    function _fmtDur(sec) {
        var h = Math.floor(sec / 3600);
        var m = Math.floor((sec % 3600) / 60);
        if (h > 0 && m > 0) return h + "h " + m + "m";
        if (h > 0)          return h + "h";
        return m + "m";
    }

    function _jiraTopText() {
        if (!entry) return "";
        return _fmtTime(entry.started) + " - " +
               _fmtTime(entry.started + entry.durationSec * 1000) +
               "  (" + _fmtDur(entry.durationSec) + ")";
    }
    function _jiraBottomText() {
        if (!entry) return "";
        if (_showSummary && entry.issueSummary && entry.issueSummary.length > 0) {
            return entry.issueKey + ": " + entry.issueSummary;
        }
        return entry.issueKey;
    }
    function _jiraCompactText() {
        if (!entry) return "";
        return _fmtTime(entry.started) + "  " + entry.issueKey;
    }

    function _clockifyTopText() {
        if (!entry) return "";
        return _fmtTime(entry.started) + " - " +
               _fmtTime(entry.started + entry.durationSec * 1000) +
               "  (" + _fmtDur(entry.durationSec) + ")";
    }
    function _clockifyBottomText() {
        if (!entry) return "";
        var desc = (entry.description && entry.description.length > 0)
                   ? entry.description
                   : i18n("(sin descripción)");
        if (entry.projectName && entry.projectName.length > 0) {
            return "[" + entry.projectName + "] " + desc;
        }
        return desc;
    }
    function _clockifyCompactText() {
        if (!entry) return "";
        var label = (entry.description && entry.description.length > 0)
                    ? entry.description
                    : (entry.projectName || i18n("(sin descripción)"));
        return _fmtTime(entry.started) + "  " + label;
    }

    // -------- Single-line layout (≤30 min OR combined mode forces it) --
    Item {
        anchors.fill: parent
        anchors.margins: 2
        visible: block._isShort

        PlasmaComponents3.Label {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 2
            anchors.rightMargin: 2
            text: block.kind === "jira" ? block._jiraCompactText() : block._clockifyCompactText()
            color: "white"
            font.pixelSize: block._smallSize
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
    }

    // -------- Two-line layout (>30 min) --------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 3
        spacing: 0
        visible: !block._isShort

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: block.kind === "jira" ? block._jiraTopText() : block._clockifyTopText()
            color: "white"
            font.pixelSize: block._useSize
            elide: Text.ElideRight
        }
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: block.kind === "jira" ? block._jiraBottomText() : block._clockifyBottomText()
            color: "white"
            font.pixelSize: block._useSize
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }
        Item { Layout.fillHeight: true }
    }

    // Click + vertical drag handler. drag.threshold ≥ 4px so a small
    // press-release still fires onClicked; once the user actually drags,
    // onClicked is suppressed (Qt's MouseArea behavior).
    MouseArea {
        anchors.fill: parent
        drag.target: block
        drag.axis: Drag.YAxis
        drag.minimumY: 0
        drag.maximumY: Math.max(0, block.columnHeight - block.height)
        drag.threshold: 4
        cursorShape: Qt.SizeVerCursor

        property bool _dragged: false
        property real _pressY: 0

        onPressed: {
            _dragged = false;
            _pressY = block.y;
        }
        onPositionChanged: function(mouse) {
            if (drag.active) _dragged = true;
        }
        onReleased: function(mouse) {
            if (_dragged) {
                var dy = block.y - _pressY;
                if (Math.abs(dy) >= 1) block.moveRequested(dy);
                else block.y = _pressY;   // undo a no-op nudge
            }
        }
        onClicked: function(mouse) {
            if (!_dragged) block.clicked();
        }
    }
}
