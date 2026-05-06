/*
 * PrioritySelector.qml - a small ComboBox listing XS/S/M/L/XL.
 * Used in edit dialogs and in "new subtask" rows.
 */

import QtQuick 2.15
import org.kde.plasma.components 3.0 as PlasmaComponents3

PlasmaComponents3.ComboBox {
    id: combo
    property string value: "M"
    readonly property var levels: ["XS", "S", "M", "L", "XL"]

    model: levels
    currentIndex: Math.max(0, levels.indexOf(value))
    onActivated: value = levels[currentIndex]

    // Keep currentIndex in sync if value changes from the outside.
    onValueChanged: {
        var i = levels.indexOf(value);
        if (i >= 0 && i !== currentIndex) currentIndex = i;
    }
}
