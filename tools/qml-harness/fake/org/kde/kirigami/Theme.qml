pragma Singleton
import QtQuick

QtObject {
    property color textColor: "#fcfcfc"
    property color backgroundColor: "#2a2e32"
    property color highlightColor: "#3daee9"
    property color negativeTextColor: "#da4453"
    property color positiveTextColor: "#27ae60"
    property color neutralTextColor: "#f67400"
    property color disabledTextColor: "#a1a9b1"
    property font defaultFont: Qt.font({ pointSize: 10 })
    property font smallFont: Qt.font({ pointSize: 8 })
}
