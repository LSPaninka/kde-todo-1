/*
 * PrioritySelector.qml - a small ComboBox listing the configured priority
 * letters (editable via the "Prioridades" config page). Used in the task
 * edit dialog and subtask rows.
 */

import QtQuick 2.15
import org.kde.plasma.components 3.0 as PlasmaComponents3

PlasmaComponents3.ComboBox {
    id: combo
    property string value: ""

    CategoryHelper { id: _prio }
    readonly property var levels: _prio.priorityLevelsList()

    model: levels
    currentIndex: {
        var i = levels.indexOf(value);
        return i >= 0 ? i : Math.floor(levels.length / 2);
    }
    onActivated: value = levels[currentIndex]

    // Keep currentIndex in sync if value changes from the outside.
    onValueChanged: {
        var i = levels.indexOf(value);
        if (i >= 0 && i !== currentIndex) currentIndex = i;
    }

    // Ensure `value` is always a valid configured level.
    Component.onCompleted: {
        if (levels.indexOf(value) < 0)
            value = levels[Math.floor(levels.length / 2)] || "";
    }
}
