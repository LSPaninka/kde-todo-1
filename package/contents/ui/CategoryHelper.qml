/*
 * CategoryHelper.qml - small helper that reads category metadata from
 * plasmoid.configuration. Instantiated in each view that needs it so
 * we don't have to chain properties across files.
 */

import QtQuick 2.15
import org.kde.plasma.plasmoid 2.0

QtObject {
    function count() {
        return Math.min(7, Math.max(1, plasmoid.configuration.categoryCount || 4));
    }
    function name(i) {
        var names = plasmoid.configuration.categoryNames || [];
        return names[i] || qsTr("Category %1").arg(i + 1);
    }
    function color(i) {
        var colors = plasmoid.configuration.categoryColors || [];
        return colors[i] || "#7f8c8d";
    }

    // Priority helpers so callers don't need a separate Priority instance.
    // Levels and colors are user-configurable (priorityLevels/priorityColors,
    // parallel StringLists, ordered lowest → highest). Fall back to the
    // classic XS/S/M/L/XL scheme when the config is empty or malformed.
    readonly property var _fallbackLevels: ["XS", "S", "M", "L", "XL"]
    readonly property var _fallbackColors: ["#95a5a6", "#3498db", "#2ecc71", "#f39c12", "#e74c3c"]

    function priorityLevelsList() {
        var arr = plasmoid.configuration.priorityLevels || [];
        var out = [];
        for (var i = 0; i < arr.length; i++) {
            var s = ("" + arr[i]).trim();
            if (s.length > 0) out.push(s);
        }
        return out.length > 0 ? out : _fallbackLevels;
    }

    // Kept for source compatibility with older callers.
    readonly property var priorityLevels: priorityLevelsList()

    function priorityColorsList() {
        var arr = plasmoid.configuration.priorityColors || [];
        return arr;
    }

    function priorityIndex(p) {
        var levels = priorityLevelsList();
        var i = levels.indexOf(p);
        return i; // -1 if not present
    }

    function priorityColor(p) {
        var idx = priorityIndex(p);
        if (idx >= 0) {
            var colors = priorityColorsList();
            if (colors[idx] && ("" + colors[idx]).length > 0) return colors[idx];
            if (_fallbackColors[idx]) return _fallbackColors[idx];
        }
        // Legacy fallback for letters not in the configured list.
        switch (p) {
            case "XS": return "#95a5a6";
            case "S":  return "#3498db";
            case "M":  return "#2ecc71";
            case "L":  return "#f39c12";
            case "XL": return "#e74c3c";
        }
        return "#2ecc71";
    }

    // Rank (0 = lowest). Used for sorting; unknown letters sort as "middle".
    function priorityRank(p) {
        var idx = priorityIndex(p);
        if (idx >= 0) return idx;
        var levels = priorityLevelsList();
        return Math.floor(levels.length / 2);
    }

    // Sensible default for new tasks/subtasks: the middle of the scale.
    function defaultPriority() {
        var levels = priorityLevelsList();
        return levels[Math.floor(levels.length / 2)] || "M";
    }
}
