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
    readonly property var priorityLevels: ["XS", "S", "M", "L", "XL"]

    function priorityColor(p) {
        switch (p) {
            case "XS": return "#95a5a6";
            case "S":  return "#3498db";
            case "M":  return "#2ecc71";
            case "L":  return "#f39c12";
            case "XL": return "#e74c3c";
        }
        return "#2ecc71";
    }
}
