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

    // Geometry hints from the parent so the MouseArea below can decide
    // whether to constrain the drag and how to translate pixel deltas
    // into slot / day deltas.
    property real columnHeight: parent ? parent.height : 0
    property real columnWidth:  parent ? parent.width  : 0
    property real rowHeight: 22                // slot height in px (= 30 min)

    signal clicked()
    // Emitted on drag release with the pixel delta from the original
    // x/y. WorklogCalendar maps to (day, slot) deltas and triggers an
    // API update.
    signal moveRequested(real deltaX, real deltaY)
    // Edge-resize signals: deltaY is the difference between the block's
    // current y/height and the value it had at press time.
    signal resizeTopRequested(real deltaY)
    signal resizeBottomRequested(real deltaH)

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

    // Single MouseArea handling three interactions, chosen on press by
    // pointer Y within the block:
    //   - top ≤ 5 px         → resize from the top (changes y + height)
    //   - bottom ≤ 5 px      → resize from the bottom (changes height)
    //   - middle             → click / drag-to-move (X+Y, cross-day OK)
    //
    // For move we lean on Qt's drag.target so the block visually follows
    // the cursor. For resize drag.target is null and we recompute y/height
    // manually from a parent-relative cursor (so the moving MouseArea
    // doesn't confuse the math).
    readonly property int _edgePx: 5

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        drag.axis: Drag.XAndYAxis
        drag.threshold: 4

        property int  _mode: 0          // 0=idle, 1=move, 2=resizeTop, 3=resizeBottom
        property real _pressBlockX: 0
        property real _pressBlockY: 0
        property real _origY: 0
        property real _origH: 0
        property real _pressParentY: 0   // cursor Y in block.parent's coords at press
        property bool _dragged: false

        cursorShape: {
            if (pressed) {
                if (_mode === 1) return Qt.SizeAllCursor;
                if (_mode === 2 || _mode === 3) return Qt.SizeVerCursor;
            }
            if (!containsMouse) return Qt.ArrowCursor;
            if (mouseY < block._edgePx)               return Qt.SizeVerCursor;
            if (mouseY > height - block._edgePx)      return Qt.SizeVerCursor;
            return Qt.SizeAllCursor;
        }

        onPressed: function(mouse) {
            _dragged = false;
            _origY        = block.y;
            _origH        = block.height;
            _pressBlockX  = block.x;
            _pressBlockY  = block.y;
            _pressParentY = ma.mapToItem(block.parent, mouse.x, mouse.y).y;

            if (mouse.y < block._edgePx) {
                _mode = 2;                 // resize top
                drag.target = null;
            } else if (mouse.y > height - block._edgePx) {
                _mode = 3;                 // resize bottom
                drag.target = null;
            } else {
                _mode = 1;                 // move
                drag.target = block;
                // Float the block AND its day-column above siblings, so a
                // drag into Thursday isn't visually covered by Friday.
                block.z = 999;
                if (block.parent) block.parent.z = 999;
            }
        }

        onPositionChanged: function(mouse) {
            if (_mode === 1) {
                if (drag.active) _dragged = true;
                return;
            }
            // Resize modes: compute dy in stable parent coords.
            var nowParentY = ma.mapToItem(block.parent, mouse.x, mouse.y).y;
            var dy = nowParentY - _pressParentY;
            if (Math.abs(dy) > 2) _dragged = true;

            if (_mode === 2) {
                // Top edge: grow upward (dy<0) / shrink downward.
                var newY = _origY + dy;
                var newH = _origH - dy;
                if (newY < 0) { newH += newY; newY = 0; }
                if (newH < block.rowHeight) {
                    newH = block.rowHeight;
                    newY = _origY + _origH - block.rowHeight;
                }
                block.y = newY;
                block.height = newH;
            } else {
                // Bottom edge: grow downward (dy>0) / shrink upward.
                var maxH = Math.max(block.rowHeight, block.columnHeight - block.y);
                var newHb = _origH + dy;
                if (newHb < block.rowHeight) newHb = block.rowHeight;
                if (newHb > maxH)            newHb = maxH;
                block.height = newHb;
            }
        }

        onReleased: function(mouse) {
            block.z = 0;
            if (block.parent) block.parent.z = 0;
            var m = _mode;
            _mode = 0;
            if (!_dragged) return;   // tap → handled by onClicked
            if (m === 1) {
                var dx = block.x - _pressBlockX;
                var dy = block.y - _pressBlockY;
                block.moveRequested(dx, dy);
            } else if (m === 2) {
                block.resizeTopRequested(block.y - _origY);
            } else if (m === 3) {
                block.resizeBottomRequested(block.height - _origH);
            }
        }

        onClicked: function(mouse) {
            if (!_dragged) block.clicked();
        }
    }
}
