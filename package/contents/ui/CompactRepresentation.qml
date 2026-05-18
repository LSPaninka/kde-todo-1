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

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: compact
    property var store
    property var jira
    property var gh
    property var notion

    readonly property string mode: plasmoid.configuration.mode || "todo"
    readonly property int _vTodo:   store  ? store.version  : 0
    readonly property int _vJira:   jira   ? jira.version   : 0
    readonly property int _vGh:     gh     ? gh.version     : 0
    readonly property int _vNotion: notion ? notion.version : 0

    readonly property var _modeOrder: ["todo", "jira", "gh", "notion"]

    // Emitted whenever a swatch gains or loses hover. main.qml uses this
    // to swap Plasmoid.toolTipMainText / toolTipSubText so the *native*
    // Plasma tooltip (the one above the panel) shows the per-square detail
    // instead of overlapping the widget with our own QQC2 tooltip.
    signal hoverChanged(bool isHovered, string mainText, string subText)

    CategoryHelper { id: cats }

    readonly property int _smallSwatch: Math.max(10, PlasmaCore.Units.iconSizes.small - 2)
    readonly property int _bigSwatch:   Math.max(18, PlasmaCore.Units.iconSizes.medium - 2)

    function _todoTextColor(idx) {
        var arr = plasmoid.configuration.panelCounterColors || [];
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

    function _jiraTextColor(idx) {
        var arr = plasmoid.configuration.jiraCategoryTextColors || [];
        var v = arr[idx];
        return (v === "black") ? "black" : "white";
    }
    function _jiraName(i) {
        var arr = plasmoid.configuration.jiraCategoryNames || [];
        return arr[i] || qsTr("Cat. %1").arg(i + 1);
    }
    function _jiraColor(i) {
        var arr = plasmoid.configuration.jiraCategoryColors || [];
        return arr[i] || "#7f8c8d";
    }
    function _jiraCount() {
        return Math.min(4, Math.max(1, plasmoid.configuration.jiraCategoryCount | 0 || 3));
    }

    function _ghTextColor(idx) {
        var arr = plasmoid.configuration.ghCategoryTextColors || [];
        var v = arr[idx];
        return (v === "black") ? "black" : "white";
    }
    function _ghName(i) {
        var arr = plasmoid.configuration.ghCategoryNames || [];
        return arr[i] || qsTr("Cat. %1").arg(i + 1);
    }
    function _ghColor(i) {
        var arr = plasmoid.configuration.ghCategoryColors || [];
        return arr[i] || "#7f8c8d";
    }
    function _ghCount() {
        return Math.min(4, Math.max(1, plasmoid.configuration.ghCategoryCount | 0 || 3));
    }

    function _cycleMode(delta) {
        var cur = compact.mode;
        var i = _modeOrder.indexOf(cur);
        if (i < 0) i = 0;
        var n = _modeOrder.length;
        var next = ((i + delta) % n + n) % n;
        plasmoid.configuration.mode = _modeOrder[next];
    }

    Layout.minimumWidth: row.implicitWidth + PlasmaCore.Units.smallSpacing * 2
    Layout.preferredWidth: Layout.minimumWidth
    Layout.minimumHeight: PlasmaCore.Units.iconSizes.small
    Layout.preferredHeight: PlasmaCore.Units.iconSizes.medium

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        hoverEnabled: true
        // Wheel cycles through todo -> jira -> gh -> todo (and reverse).
        // We accept wheel events so they don't bubble up to plasmashell.
        onWheel: {
            if (wheel.angleDelta.y === 0) { wheel.accepted = false; return; }
            compact._cycleMode(wheel.angleDelta.y > 0 ? 1 : -1);
            wheel.accepted = true;
        }
        onClicked: plasmoid.expanded = !plasmoid.expanded
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: PlasmaCore.Units.smallSpacing * 2

        // -------- TODO mode --------
        Repeater {
            model: compact.mode === "todo" ? cats.count() : 0
            delegate: SwatchBadge {
                catIndex: index
                color: cats.color(index)
                count: (compact._vTodo, store ? store.pendingCountForCategory(index) : 0)
                showZero: plasmoid.configuration.panelShowZero
                label: cats.name(index)
                showLabel: plasmoid.configuration.panelShowLabels
                textColor: compact._todoTextColor(index)
                insideMode: plasmoid.configuration.panelCounterStyle === "inside"
                smallSwatch: compact._smallSwatch
                bigSwatch: compact._bigSwatch
                tooltipTitle: cats.name(index)
                tooltipBody: (compact._vTodo, compact._todoTooltipBody(index))
                onHoverChanged: function(isHov, m, s) { compact.hoverChanged(isHov, m, s); }
            }
        }

        // -------- JIRA mode --------
        Repeater {
            model: compact.mode === "jira" ? compact._jiraCount() : 0
            delegate: SwatchBadge {
                catIndex: index
                color: compact._jiraColor(index)
                count: (compact._vJira, jira ? jira.countByJiraCategory(index) : 0)
                showZero: plasmoid.configuration.panelShowZero
                label: compact._jiraName(index)
                showLabel: plasmoid.configuration.panelShowLabels
                textColor: compact._jiraTextColor(index)
                insideMode: plasmoid.configuration.panelCounterStyle === "inside"
                smallSwatch: compact._smallSwatch
                bigSwatch: compact._bigSwatch
                tooltipTitle: compact._jiraName(index)
                tooltipBody: {
                    if (!jira) return "";
                    var c = (compact._vJira, jira.countByJiraCategory(index));
                    return i18np("%1 incidencia en esta categoría.",
                                 "%1 incidencias en esta categoría.", c);
                }
                onHoverChanged: function(isHov, m, s) { compact.hoverChanged(isHov, m, s); }
            }
        }

        // -------- GITHUB PROJECTS mode --------
        Repeater {
            model: compact.mode === "gh" ? compact._ghCount() : 0
            delegate: SwatchBadge {
                catIndex: index
                color: compact._ghColor(index)
                count: (compact._vGh, gh ? gh.countByGhCategory(index) : 0)
                showZero: plasmoid.configuration.panelShowZero
                label: compact._ghName(index)
                showLabel: plasmoid.configuration.panelShowLabels
                textColor: compact._ghTextColor(index)
                insideMode: plasmoid.configuration.panelCounterStyle === "inside"
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
            showLabel: plasmoid.configuration.panelShowLabels
            textColor: "white"
            insideMode: plasmoid.configuration.panelCounterStyle === "inside"
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
        }
    }
}
