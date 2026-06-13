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
    // x/y. `fine` = Shift was held → snap to 10-min instead of 30-min.
    signal moveRequested(real deltaX, real deltaY, bool fine)
    // Edge-resize signals: deltaY is the difference between the block's
    // current y/height and the value it had at press time.
    signal resizeTopRequested(real deltaY, bool fine)
    signal resizeBottomRequested(real deltaH, bool fine)
    // Duplicate button in the top-right corner.
    signal duplicateRequested()

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
    // Drag does NOT use Qt's drag.target — we update block.x/y/height
    // ourselves snapped to slots (rowHeight) and day columns
    // (columnWidth), so the block hops between cells instead of
    // smoothly following the cursor. positionChanged is guarded by
    // `pressed` so plain hover (with hoverEnabled: true) doesn't
    // accidentally trigger the resize logic and corrupt the height
    // binding.
    readonly property int _edgePx: 5

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        // The calendar lives inside a QQC2.ScrollView (Flickable under
        // the hood). Without `drag.target` set, the Flickable interprets
        // a press-and-move on the block as a scroll gesture and steals
        // the events — the user would scroll the grid instead of moving
        // the block. preventStealing keeps the pointer on this MouseArea
        // for the whole gesture, regardless of how far the cursor moves.
        preventStealing: true

        property int  _mode: 0          // 0=idle, 1=move, 2=resizeTop, 3=resizeBottom
        property real _origBlockX: 0
        property real _origBlockY: 0
        property real _origH: 0
        property real _pressParentX: 0
        property real _pressParentY: 0
        property bool _dragged: false
        property bool _fine: false      // Shift held → 10-min granularity

        // Vertical snap step in px: a full row (30 min) normally, a third
        // of a row (10 min) when Shift is held.
        function _stepPx() { return _fine ? block.rowHeight / 3 : block.rowHeight; }
        function _snapMinH() { return _fine ? block.rowHeight / 3 : block.rowHeight; }

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
            _dragged    = false;
            _fine       = (mouse.modifiers & Qt.ShiftModifier) !== 0;
            _origBlockX = block.x;
            _origBlockY = block.y;
            _origH      = block.height;
            var p = ma.mapToItem(block.parent, mouse.x, mouse.y);
            _pressParentX = p.x;
            _pressParentY = p.y;

            if (mouse.y < block._edgePx)                _mode = 2;
            else if (mouse.y > height - block._edgePx)  _mode = 3;
            else                                         _mode = 1;

            if (_mode === 1) {
                // Float the block AND its day-column above siblings, so a
                // drag into Thursday isn't visually covered by Friday.
                block.z = 999;
                if (block.parent) block.parent.z = 999;
            }
        }

        onPositionChanged: function(mouse) {
            // CRITICAL: positionChanged also fires on plain hover when
            // hoverEnabled is true. Ignoring this guard would let the
            // resize logic run on hover and silently break the height
            // binding (block stays at the corrupted size until refetch).
            if (!pressed) return;

            var p  = ma.mapToItem(block.parent, mouse.x, mouse.y);
            var dx = p.x - _pressParentX;
            var dy = p.y - _pressParentY;
            var stepPx = _stepPx();      // 30-min row, or 10-min third with Shift
            var minH   = _snapMinH();    // smallest block height (10 or 30 min)

            if (_mode === 1) {
                // Manual drag with cell-snapping. The block hops between
                // grid steps (full rows, or 10-min thirds with Shift). Y is
                // clamped to [0, columnHeight - height] so the block can't
                // escape the visible hour range (9:00–18:00 in 9h mode).
                if (!_dragged && Math.abs(dx) < 4 && Math.abs(dy) < 4) return;
                _dragged = true;
                var snappedDx = block.columnWidth > 0
                              ? Math.round(dx / block.columnWidth) * block.columnWidth
                              : 0;
                var snappedDy = Math.round(dy / stepPx) * stepPx;
                var newY = _origBlockY + snappedDy;
                if (block.columnHeight > 0) {
                    var maxY = Math.max(0, block.columnHeight - block.height);
                    if (newY < 0)    newY = 0;
                    if (newY > maxY) newY = maxY;
                }
                block.x = _origBlockX + snappedDx;
                block.y = newY;
            } else if (_mode === 2) {
                // Top resize — snap to the current step so the top edge
                // lands on a 30- or 10-min boundary, clamped to row 0.
                if (Math.abs(dy) > 2) _dragged = true;
                var stepY = Math.round(dy / stepPx) * stepPx;
                var newY2 = _origBlockY + stepY;
                var newH  = _origH - stepY;
                if (newY2 < 0) { newH += newY2; newY2 = 0; }
                if (newH < minH) {
                    newH = minH;
                    newY2 = _origBlockY + _origH - minH;
                }
                block.y = newY2;
                block.height = newH;
            } else if (_mode === 3) {
                // Bottom resize — snap height delta to the current step.
                // Clamp so the bottom edge stays inside columnHeight.
                if (Math.abs(dy) > 2) _dragged = true;
                var stepDH = Math.round(dy / stepPx) * stepPx;
                var newHb  = _origH + stepDH;
                if (newHb < minH) newHb = minH;
                if (block.columnHeight > 0) {
                    var maxH = Math.max(minH, block.columnHeight - block.y);
                    if (newHb > maxH) newHb = maxH;
                }
                block.height = newHb;
            }
            // _mode === 0 (idle) intentionally falls through with no-op.
        }

        onReleased: function(mouse) {
            block.z = 0;
            if (block.parent) block.parent.z = 0;
            var m = _mode;
            _mode = 0;
            if (!_dragged) return;   // tap → handled by onClicked
            if (m === 1) {
                block.moveRequested(block.x - _origBlockX, block.y - _origBlockY, _fine);
            } else if (m === 2) {
                block.resizeTopRequested(block.y - _origBlockY, _fine);
            } else if (m === 3) {
                block.resizeBottomRequested(block.height - _origH, _fine);
            }
        }

        onClicked: function(mouse) {
            if (!_dragged) block.clicked();
        }
    }

    // Duplicate button (top-right corner). Declared *after* the main
    // MouseArea so its 16×16 area intercepts clicks (pressing the icon
    // doesn't accidentally start a resize-top gesture). Visibility is
    // bound to the main MouseArea's containsMouse so the button shows
    // any time the cursor is over the block — HoverHandler was unreliable
    // in this layout because the MouseArea fills the same area.
    Rectangle {
        id: dupBtn
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 1
        anchors.rightMargin: 1
        width: 16
        height: 16
        radius: 3
        visible: ma.containsMouse || dupBtnMA.containsMouse
        color: dupBtnMA.containsMouse ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(0, 0, 0, 0.30)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.45)

        PlasmaCore.IconItem {
            anchors.fill: parent
            anchors.margins: 1
            source: "edit-copy"
            colorGroup: PlasmaCore.Theme.ComplementaryColorGroup
        }
        MouseArea {
            id: dupBtnMA
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: block.duplicateRequested()
        }

        PlasmaComponents3.ToolTip.text: i18n("Duplicar este worklog")
        PlasmaComponents3.ToolTip.visible: dupBtnMA.containsMouse
        PlasmaComponents3.ToolTip.delay: 500
    }
}
