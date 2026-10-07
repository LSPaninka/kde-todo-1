/*
 * CompactRepresentation.qml - panel / system-tray view.
 *
 * Four operating modes:
 *   - "todo":   one swatch + count per ToDo category. Hover shows the
 *               pending tasks for that category as a tooltip.
 *   - "jira":   one swatch + count per Jira category (configurable).
 *   - "gh":     one swatch + count per GitHub Projects category.
 *   - "notion": a single Notion-colored swatch + total page count.
 *
 * Inside each mode, the layout follows panelCounterStyle ("right" or
 * "inside") and panelCounterColors (white | black per swatch).
 *
 * Mouse wheel over the compact view cycles through the four modes.
 */

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Item {
    id: compact
    property var store
    property var jira
    property var jira2
    property var gh
    property var notion
    // The PlasmoidItem root (main.qml); owns `expanded`.
    property var plasmoidItem

    readonly property string mode: Plasmoid.configuration.mode || "todo"
    readonly property int _vTodo:   store  ? store.version  : 0
    readonly property int _vJira:   jira   ? jira.version   : 0
    readonly property int _vJira2:  jira2  ? jira2.version  : 0
    readonly property int _vGh:     gh     ? gh.version     : 0
    readonly property int _vNotion: notion ? notion.version : 0

    // The "notion" CLI mode is disabled for now, so the wheel cycles
    // todo → jira → jira2 → gh. (Notion is a ToDo-mode sync, not a mode.)
    readonly property var _modeOrder: ["todo", "jira", "jira2", "gh"]

    // Emitted whenever a swatch gains or loses hover. main.qml uses this
    // to swap toolTipMainText / toolTipSubText so the *native*
    // Plasma tooltip (the one above the panel) shows the per-square detail
    // instead of overlapping the widget with our own QQC2 tooltip.
    signal hoverChanged(bool isHovered, string mainText, string subText)

    CategoryHelper { id: cats }

    readonly property int _smallSwatch: Math.max(10, Kirigami.Units.iconSizes.small - 2)
    readonly property int _bigSwatch:   Math.max(18, Kirigami.Units.iconSizes.medium - 2)

    readonly property bool _insideMode: Plasmoid.configuration.panelCounterStyle === "inside"
    readonly property int  _scalePct:
        Math.max(50, Math.min(100, Plasmoid.configuration.panelCounterScale | 0 || 100))

    function _todoTextColor(idx) {
        var arr = Plasmoid.configuration.panelCounterColors || [];
        var v = arr[idx];
        return (v === "black") ? "black" : "white";
    }

    // Builds the tooltip body for a ToDo category: a bulleted list of the
    // pending task titles, capped at 10 entries with a "+N más" suffix.
    function _todoTooltipBody(idx) {
        if (!store) return "";
        var pending = [];
        var all = store.tasksForCategory(idx);
        for (var i = 0; i < all.length; i++) {
            if (!all[i].done) pending.push(all[i]);
        }
        if (pending.length === 0) return i18n("Sin tareas pendientes.");
        var lines = [];
        var max = 10;
        for (var j = 0; j < Math.min(max, pending.length); j++) {
            var t = pending[j];
            var prio = t.priority ? " [" + t.priority + "]" : "";
            lines.push("• " + (t.title || "(sin título)") + prio);
        }
        if (pending.length > max) {
            lines.push(i18np("…y %1 más.", "…y %1 más.", pending.length - max));
        }
        return lines.join("\n");
    }

    // Jira swatch helpers, parameterized by config prefix ("jira"/"jira2").
    function _jiraTextColor(prefix, idx) {
        var arr = Plasmoid.configuration[prefix+"CategoryTextColors"] || [];
        var v = arr[idx];
        return (v === "black") ? "black" : "white";
    }
    function _jiraName(prefix, i) {
        var arr = Plasmoid.configuration[prefix+"CategoryNames"] || [];
        return arr[i] || qsTr("Cat. %1").arg(i + 1);
    }
    function _jiraColor(prefix, i) {
        var arr = Plasmoid.configuration[prefix+"CategoryColors"] || [];
        return arr[i] || "#7f8c8d";
    }
    function _jiraCount(prefix) {
        return Math.min(10, Math.max(1, Plasmoid.configuration[prefix+"CategoryCount"] | 0 || 3));
    }

    function _ghTextColor(idx) {
        var arr = Plasmoid.configuration.ghCategoryTextColors || [];
        var v = arr[idx];
        return (v === "black") ? "black" : "white";
    }
    function _ghName(i) {
        var arr = Plasmoid.configuration.ghCategoryNames || [];
        return arr[i] || qsTr("Cat. %1").arg(i + 1);
    }
    function _ghColor(i) {
        var arr = Plasmoid.configuration.ghCategoryColors || [];
        return arr[i] || "#7f8c8d";
    }
    function _ghCount() {
        return Math.min(4, Math.max(1, Plasmoid.configuration.ghCategoryCount | 0 || 3));
    }

    function _cycleMode(delta) {
        var cur = compact.mode;
        var i = _modeOrder.indexOf(cur);
        if (i < 0) i = 0;
        var n = _modeOrder.length;
        var next = ((i + delta) % n + n) % n;
        Plasmoid.configuration.mode = _modeOrder[next];
    }

    Layout.minimumWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
    Layout.preferredWidth: Layout.minimumWidth
    Layout.minimumHeight: Kirigami.Units.iconSizes.small
    Layout.preferredHeight: Kirigami.Units.iconSizes.medium

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        hoverEnabled: true
        // Wheel cycles through todo -> jira -> gh -> todo (and reverse).
        // We accept wheel events so they don't bubble up to plasmashell.
        onWheel: (wheel) => {
            if (wheel.angleDelta.y === 0) { wheel.accepted = false; return; }
            compact._cycleMode(wheel.angleDelta.y > 0 ? 1 : -1);
            wheel.accepted = true;
        }
        onClicked: compact.plasmoidItem.expanded = !compact.plasmoidItem.expanded
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        // Inside mode: the gap between swatches shrinks with the scale too.
        spacing: compact._insideMode
                 ? Math.max(2, Math.round(Kirigami.Units.smallSpacing * 2 * compact._scalePct / 100))
                 : Kirigami.Units.smallSpacing * 2

        // -------- TODO mode --------
        Repeater {
            model: compact.mode === "todo" ? cats.count() : 0
            delegate: SwatchBadge {
                catIndex: index
                color: cats.color(index)
                count: (compact._vTodo, store ? store.pendingCountForCategory(index) : 0)
                showZero: Plasmoid.configuration.panelShowZero
                label: cats.name(index)
                showLabel: Plasmoid.configuration.panelShowLabels
                textColor: compact._todoTextColor(index)
                insideMode: Plasmoid.configuration.panelCounterStyle === "inside"
                scalePercent: compact._scalePct
                smallSwatch: compact._smallSwatch
                bigSwatch: compact._bigSwatch
                tooltipTitle: cats.name(index)
                tooltipBody: (compact._vTodo, compact._todoTooltipBody(index))
                onHoverChanged: function(isHov, m, s) { compact.hoverChanged(isHov, m, s); }
                onClicked: {
                    // Mirror the Jira behaviour: clicking a specific swatch
                    // opens the popup and jumps to that category's tab.
                    if (compact.plasmoidItem.expanded) {
                        compact.plasmoidItem.expanded = false;
                    } else {
                        if (store) store.requestCategory(index);
                        compact.plasmoidItem.expanded = true;
                    }
                }
            }
        }

        // -------- JIRA 1 mode --------
        Repeater {
            model: compact.mode === "jira" ? compact._jiraCount("jira") : 0
            delegate: SwatchBadge {
                catIndex: index
                color: compact._jiraColor("jira", index)
                count: (compact._vJira, jira ? jira.countByJiraCategory(index) : 0)
                showZero: Plasmoid.configuration.panelShowZero
                label: compact._jiraName("jira", index)
                showLabel: Plasmoid.configuration.panelShowLabels
                textColor: compact._jiraTextColor("jira", index)
                insideMode: Plasmoid.configuration.panelCounterStyle === "inside"
                scalePercent: compact._scalePct
                smallSwatch: compact._smallSwatch
                bigSwatch: compact._bigSwatch
                tooltipTitle: compact._jiraName("jira", index)
                tooltipBody: (compact._vJira, jira ? jira.issueTitlesForCategory(index) : "")
                onHoverChanged: function(isHov, m, s) { compact.hoverChanged(isHov, m, s); }
                onClicked: {
                    if (compact.plasmoidItem.expanded) {
                        compact.plasmoidItem.expanded = false;
                    } else {
                        if (jira) jira.requestCategory(index);
                        compact.plasmoidItem.expanded = true;
                    }
                }
            }
        }

        // -------- JIRA 2 mode --------
        Repeater {
            model: compact.mode === "jira2" ? compact._jiraCount("jira2") : 0
            delegate: SwatchBadge {
                catIndex: index
                color: compact._jiraColor("jira2", index)
                count: (compact._vJira2, jira2 ? jira2.countByJiraCategory(index) : 0)
                showZero: Plasmoid.configuration.panelShowZero
                label: compact._jiraName("jira2", index)
                showLabel: Plasmoid.configuration.panelShowLabels
                textColor: compact._jiraTextColor("jira2", index)
                insideMode: Plasmoid.configuration.panelCounterStyle === "inside"
                scalePercent: compact._scalePct
                smallSwatch: compact._smallSwatch
                bigSwatch: compact._bigSwatch
                tooltipTitle: compact._jiraName("jira2", index)
                tooltipBody: (compact._vJira2, jira2 ? jira2.issueTitlesForCategory(index) : "")
                onHoverChanged: function(isHov, m, s) { compact.hoverChanged(isHov, m, s); }
                onClicked: {
                    if (compact.plasmoidItem.expanded) {
                        compact.plasmoidItem.expanded = false;
                    } else {
                        if (jira2) jira2.requestCategory(index);
                        compact.plasmoidItem.expanded = true;
                    }
                }
            }
        }

        // -------- GITHUB PROJECTS mode --------
        Repeater {
            model: compact.mode === "gh" ? compact._ghCount() : 0
            delegate: SwatchBadge {
                catIndex: index
                color: compact._ghColor(index)
                count: (compact._vGh, gh ? gh.countByGhCategory(index) : 0)
                showZero: Plasmoid.configuration.panelShowZero
                label: compact._ghName(index)
                showLabel: Plasmoid.configuration.panelShowLabels
                textColor: compact._ghTextColor(index)
                insideMode: Plasmoid.configuration.panelCounterStyle === "inside"
                scalePercent: compact._scalePct
                smallSwatch: compact._smallSwatch
                bigSwatch: compact._bigSwatch
                tooltipTitle: compact._ghName(index)
                tooltipBody: {
                    if (!gh) return "";
                    var c = (compact._vGh, gh.countByGhCategory(index));
                    return i18np("%1 ítem en esta categoría.",
                                 "%1 ítems en esta categoría.", c);
                }
                onHoverChanged: function(isHov, m, s) { compact.hoverChanged(isHov, m, s); }
                onClicked: compact.plasmoidItem.expanded = !compact.plasmoidItem.expanded
            }
        }

        // -------- NOTION mode --------
        // Notion has no native categorization, so we render a single swatch
        // with the total page count.
        SwatchBadge {
            visible: compact.mode === "notion"
            catIndex: 0
            color: "#37352f"   // Notion's brand black-ish
            count: (compact._vNotion, notion ? notion.totalCount() : 0)
            showZero: true
            label: i18n("Notion")
            showLabel: Plasmoid.configuration.panelShowLabels
            textColor: "white"
            insideMode: Plasmoid.configuration.panelCounterStyle === "inside"
            scalePercent: compact._scalePct
            smallSwatch: compact._smallSwatch
            bigSwatch: compact._bigSwatch
            tooltipTitle: i18n("Notion")
            tooltipBody: {
                if (!notion) return "";
                if (notion.loading) return i18n("Cargando…");
                if (notion.lastError) return notion.lastError;
                return i18np("%1 página sincronizada.",
                             "%1 páginas sincronizadas.",
                             (compact._vNotion, notion.totalCount()));
            }
            onHoverChanged: function(isHov, m, s) { compact.hoverChanged(isHov, m, s); }
            onClicked: compact.plasmoidItem.expanded = !compact.plasmoidItem.expanded
        }
    }
}
