import QtQuick

// Simula el motor "executable": responde con un JSON vacío.
QtObject {
    property string engine
    property var connectedSources: []
    signal newData(string sourceName, var data)

    function connectSource(sourceName) {
        Qt.callLater(function() {
            newData(sourceName, { "exit code": 0, "stdout": "{\"results\": []}", "stderr": "" });
        });
    }
    function disconnectSource(sourceName) {}
}
